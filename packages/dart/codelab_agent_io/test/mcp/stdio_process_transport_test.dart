import 'dart:async';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// stdio-транспорт MCP на настоящих процессах (agent-mcp-client «stdio-
/// транспорт MCP»; design.md change `add-agent-mcp-client`, D9). Дочерний
/// процесс — `test/support/line_echo.dart`, оболочка — `/bin/sh`.
const _maxLine = 16 * 1024 * 1024;

Future<bool> _alive(String marker) async {
  final ps = await Process.run('ps', ['-A', '-o', 'args=']);
  return '${ps.stdout}'
      .split('\n')
      .any((line) => line.contains(marker) && !line.contains('ps -A'));
}

void main() {
  late Directory tmp;
  late String cwd;
  late RecordingLogger logger;
  final opened = <McpTransport>[];
  final script = File('test/support/line_echo.dart').absolute.path;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('stdio_mcp_');
    cwd = tmp.resolveSymbolicLinksSync();
    logger = RecordingLogger();
  });

  tearDown(() async {
    for (final transport in opened) {
      await transport.close();
    }
    opened.clear();
    tmp.deleteSync(recursive: true);
  });

  StdioMcpTransportFactory factory({Map<String, String>? host}) =>
      StdioMcpTransportFactory(hostEnvironment: host ?? Platform.environment);

  Future<McpTransport> open(
    McpStdioServerConfig server, {
    StdioMcpTransportFactory? using,
    CancelToken? cancel,
  }) async {
    final transport = await (using ?? factory()).open(
      server,
      cwd: cwd,
      cancel: cancel ?? CancelToken.none,
      // Как передаёт коннектор: логгер уже несёт `session_id` (D13).
      logger: BoundLogger(logger, const {'session_id': 's1'}),
    );
    opened.add(transport);
    return transport;
  }

  McpStdioServerConfig echo({Map<String, String> env = const {}}) =>
      McpStdioServerConfig(
        name: 'echo',
        command: Platform.resolvedExecutable,
        args: [script],
        env: env,
      );

  McpStdioServerConfig shell(String script) => McpStdioServerConfig(
    name: 'sh',
    command: '/bin/sh',
    args: ['-c', script],
  );

  group('environment', () {
    test('only the allowlist and the env of the server are visible', () async {
      final transport = await open(
        echo(env: {'API_KEY': 'k', 'HOME': '/server/home'}),
        using: factory(
          host: {
            'PATH': Platform.environment['PATH']!,
            'HOME': '/host/home',
            'SECRET_X': '1',
          },
        ),
      );
      final lines = StreamIterator(transport.incoming);

      Future<String> ask(String name) async {
        await transport.send('env:$name');
        expect(await lines.moveNext(), isTrue);
        return lines.current;
      }

      expect(await ask('API_KEY'), 'API_KEY=k');
      expect(await ask('PATH'), 'PATH=${Platform.environment['PATH']}');
      expect(await ask('SECRET_X'), 'SECRET_X=<unset>');
      expect(await ask('HOME'), 'HOME=/server/home', reason: 'env wins');
      expect(await ask('TERM'), 'TERM=<unset>', reason: 'only for exec');
      await lines.cancel();
    });

    test(
      'a relative command is searched in the PATH of the allowlist',
      () async {
        final transport = await open(
          const McpStdioServerConfig(
            name: 'rel',
            command: 'sh',
            args: ['-c', 'echo from-path'],
          ),
          using: factory(host: {'PATH': Platform.environment['PATH']!}),
        );

        expect(await transport.incoming.first, 'from-path');
      },
    );

    test(
      'the process starts in the working directory of the session',
      () async {
        final transport = await open(echo());
        final lines = StreamIterator(transport.incoming);

        await transport.send('pwd');
        await lines.moveNext();

        expect(lines.current, cwd);
        await lines.cancel();
      },
    );
  });

  group('frames', () {
    test('a line goes there and back; order is kept', () async {
      final transport = await open(echo());
      final received = transport.incoming.take(20).toList();

      await Future.wait([
        for (var i = 0; i < 20; i++) transport.send('{"n":$i}'),
      ]);

      expect(await received, [for (var i = 0; i < 20; i++) '{"n":$i}']);
    });

    test('a line of exactly 16 MiB is delivered', () async {
      final transport = await open(echo());
      final lines = StreamIterator(transport.incoming);

      await transport.send('big:$_maxLine');
      await lines.moveNext();

      expect(lines.current.length, _maxLine);
      await lines.cancel();
    });

    test('a line longer than 16 MiB closes the transport', () async {
      final transport = await open(echo());
      final lines = transport.incoming.toList();

      await transport.send('big:${_maxLine + 1}');
      final closed = await transport.done.timeout(const Duration(seconds: 30));

      expect(closed.reason, 'message too large');
      expect(await lines, isEmpty, reason: 'the line is not delivered');
      await expectLater(
        transport.send('x'),
        throwsA(isA<McpTransportException>()),
      );
    });

    test('a newline inside a message is refused before the write', () async {
      final transport = await open(echo());

      await expectLater(
        transport.send('{"a":\n1}'),
        throwsA(isA<McpTransportException>()),
      );
    });
  });

  group('stderr', () {
    test('a chatty stderr does not block the process', () async {
      final transport = await open(echo());
      final lines = StreamIterator(transport.incoming);

      // Заметно больше буфера канала (64 КиБ): без чтения stderr процесс
      // завис бы на записи и не ответил.
      await transport.send('stderr:1000000');
      final answered = await lines.moveNext().timeout(
        const Duration(seconds: 30),
      );

      expect(answered, isTrue);
      expect(lines.current, 'stderr-done');
      await lines.cancel();
    });

    test('lines go to the log at trace level only, cut to 4 KiB', () async {
      final transport = await open(
        shell("printf '%10000s' '' | tr ' ' s >&2; echo >&2; echo ready"),
      );

      expect(await transport.incoming.first, 'ready');
      await transport.done;

      final records = logger.eventsOf('mcp.server.stderr');
      expect(records, isNotEmpty);
      // trace, а не debug: stderr сервера может нести секреты, а профиль
      // stdio по умолчанию пишет debug (ревью PR #158).
      expect(records.every((r) => r.level == LogLevel.trace), isTrue);
      expect(records.first.fields['server'], 'sh');
      expect(records.first.fields['session_id'], 's1');
      expect((records.first.fields['line'] as String).length, 4096);
    });
  });

  group('closing', () {
    test('done completes with the exit code when the process exits', () async {
      final transport = await open(echo());
      final lines = transport.incoming.toList();

      await transport.send('exit:3');
      final closed = await transport.done;

      expect(closed.exitCode, 3);
      expect(closed.reason, 'process exited');
      expect(await lines, isEmpty);
    });

    test('a server that leaves on EOF is closed quickly; the log has '
        'mcp.server.closed', () async {
      final transport = await open(echo());
      // Старт VM занимает заметное время: засекаем после готовности процесса.
      final lines = StreamIterator(transport.incoming);
      await transport.send('ready?');
      await lines.moveNext();
      final watch = Stopwatch()..start();

      await transport.close();
      final closed = await transport.done;
      await lines.cancel();

      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(closed.exitCode, 0);
      final record = logger.eventsOf('mcp.server.closed').single;
      expect(record.level, LogLevel.info);
      expect(record.fields, {
        'session_id': 's1',
        'server': 'echo',
        'transport': 'stdio',
        'exit_code': 0,
      });
    });

    test('close is idempotent', () async {
      final transport = await open(echo());

      await Future.wait([transport.close(), transport.close()]);
      await transport.close();

      expect(logger.eventsOf('mcp.server.closed'), hasLength(1));
    });

    /// Сценарий в файле и уникальное имя команды потомка (симлинк на
    /// `sleep`): имя не входит в аргументы `sh`, поэтому `ps` находит только
    /// самого потомка.
    ({String command, String script}) hold(String body) {
      final id = '${DateTime.now().microsecondsSinceEpoch}';
      final link = Link('$cwd/held_sleep_$id')..createSync('/bin/sleep');
      final file = File('$cwd/hold_$id.sh')
        ..writeAsStringSync(body.replaceAll(r'$HELD', link.path));
      return (command: 'held_sleep_$id', script: file.path);
    }

    test('a server that ignores EOF and SIGTERM is killed with its '
        'descendants within 10 s', () async {
      final held = hold('trap "" TERM\n\$HELD 600 &\necho up\nwait\n');
      final transport = await open(
        McpStdioServerConfig(
          name: 'sh',
          command: '/bin/sh',
          args: [held.script],
        ),
      );
      expect(await transport.incoming.first, 'up');
      expect(await _alive(held.command), isTrue);
      final watch = Stopwatch()..start();

      await transport.close();

      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
      expect(await _alive(held.command), isFalse);
      final closed = await transport.done;
      expect(closed.exitCode, isNot(0));
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('a descendant that ignores EOF and SIGTERM does not outlive a root '
        'that left on EOF', () async {
      final held = hold(
        '( trap "" TERM; exec \$HELD 600 ) &\necho up\nread x\nexit 0\n',
      );
      final transport = await open(
        McpStdioServerConfig(
          name: 'sh',
          command: '/bin/sh',
          args: [held.script],
        ),
      );
      expect(await transport.incoming.first, 'up');
      expect(await _alive(held.command), isTrue);
      final watch = Stopwatch()..start();

      await transport.close();

      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
      expect(await _alive(held.command), isFalse);
      expect((await transport.done).exitCode, 0, reason: 'the root left');
    }, timeout: const Timeout(Duration(seconds: 40)));
  });

  group('spawn', () {
    test('a missing command is spawn failed', () async {
      final server = McpStdioServerConfig(
        name: 'none',
        command: '$cwd/no-such-binary',
      );

      await expectLater(
        open(server),
        throwsA(
          isA<McpTransportException>().having(
            (e) => e.message,
            'message',
            startsWith('spawn failed: '),
          ),
        ),
      );
    });

    test('a cancelled token does not start the process', () async {
      final source = CancelTokenSource()..cancel();

      await expectLater(
        open(echo(), cancel: source.token),
        throwsA(isA<McpTransportException>()),
      );
    });

    test('the log never contains values of env', () async {
      final transport = await open(echo(env: {'API_KEY': 'sk-secret-123'}));
      await transport.close();

      expect('${logger.records}', isNot(contains('sk-secret-123')));
    });
  });
}
