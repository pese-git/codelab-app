import 'dart:typed_data';

import 'package:acp_protocol/acp_protocol.dart' hide SessionId;
import 'package:codelab_agent_acp/codelab_agent_acp.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../../codelab_agent_core/test/env/execution_env_contract.dart';
import 'support/client_channel.dart';

/// agent-acp-server «Запросы агента к клиенту», `AcpClientExecutionEnv`
/// (задача 3.3; §4.7, §13.9; ACP-9, ENV-7).
void main() {
  late MemoryExecutionEnv files;

  executionEnvContract(
    'AcpClientExecutionEnv',
    create: () async {
      final channel = await ClientChannel.open();
      files = MemoryExecutionEnv(cwd: '/work');
      channel.client.serveFiles(files);
      return channel.env(cwd: '/work');
    },
    writeBytes: (env, path, bytes) async =>
        files.putBytes(path, Uint8List.fromList(bytes)),
    clientBacked: true,
  );

  group('fs', () {
    late ClientChannel ch;

    setUp(() async {
      ch = await ClientChannel.open();
      files = MemoryExecutionEnv(cwd: '/work');
      await files.writeText('/work/lib/a.dart', '1\n2\n3\n');
      ch.client.serveFiles(files);
    });

    test('readText sends the absolute path, line and limit', () async {
      final env = ch.env();

      final read = await env.readText('lib/a.dart', line: 2, limit: 1);

      expect(read, const Ok<String, FileError>('2\n'));
      final request = ch.client.requests.single;
      expect(request.method, 'fs/read_text_file');
      expect(request.id, JsonRpcId.string('fs-1'));
      expect(request.params, {
        'sessionId': 'sess_1',
        'path': '/work/lib/a.dart',
        'line': 2,
        'limit': 1,
      });
    });

    test('writeText sends fs/write_text_file', () async {
      final written = await ch.env().writeText('/work/b.txt', 'b');

      expect(written, isA<Ok<void, FileError>>());
      expect(ch.client.paramsOf('fs/write_text_file'), {
        'sessionId': 'sess_1',
        'path': '/work/b.txt',
        'content': 'b',
      });
      expect(
        await files.readText('/work/b.txt'),
        const Ok<String, FileError>('b'),
      );
    });

    test('stat reads one line: a file without size', () async {
      final stat = await ch.env().stat('/work/lib/a.dart');

      expect(
        stat,
        isA<Ok<FileStat, FileError>>()
            .having((r) => r.value.type, 'type', FileType.file)
            .having((r) => r.value.size, 'size', isNull),
      );
      expect(ch.client.paramsOf('fs/read_text_file'), {
        'sessionId': 'sess_1',
        'path': '/work/lib/a.dart',
        'limit': 1,
      });
    });

    test(
      '-32002 is notFound, other errors are io with the client text',
      () async {
        ch.client.handlers['fs/write_text_file'] = (_) =>
            throw const ClientFailure(-32602, 'path outside cwd');

        final missing = await ch.env().readText('/work/none.txt');
        final denied = await ch.env().writeText('/work/x.txt', 'x');

        expect(
          missing,
          isA<Err<String, FileError>>().having(
            (r) => r.error.code,
            'code',
            FileErrorCode.notFound,
          ),
        );
        expect(
          denied,
          isA<Err<void, FileError>>()
              .having((r) => r.error.code, 'code', FileErrorCode.io)
              .having((r) => r.error.message, 'message', 'path outside cwd'),
        );
      },
    );

    test(
      'no answer in 30 s is an io timeout; a late answer is ignored',
      () async {
        ch.client.handlers.remove('fs/read_text_file');
        final env = ch.env();

        final read = env.readText('/work/lib/a.dart');
        final request = await ch.client.arrival('fs/read_text_file');
        await ch.clock.elapse(const Duration(seconds: 30));

        expect(
          await read,
          isA<Err<String, FileError>>()
              .having((r) => r.error.code, 'code', FileErrorCode.io)
              .having((r) => r.error.message, 'message', contains('timed out')),
        );
        await ch.client.respond(request, {'content': 'late'});
        await pumpEventQueue();
        expect(ch.logger.eventsOf('acp.frame.bad'), isNotEmpty);
      },
    );

    test('a declined capability gives unsupported without a frame', () async {
      final narrow = await ClientChannel.open(
        capabilities: const ClientCapabilities(),
      );
      final env = narrow.env();

      expect(
        await env.readText('/work/a.txt'),
        isA<Err<String, FileError>>().having(
          (r) => r.error.code,
          'code',
          FileErrorCode.unsupported,
        ),
      );
      expect(
        await env.writeText('/work/a.txt', 'a'),
        isA<Err<void, FileError>>().having(
          (r) => r.error.code,
          'code',
          FileErrorCode.unsupported,
        ),
      );
      await pumpEventQueue();
      expect(narrow.client.requests, isEmpty);
    });

    test('a lost connection is io "client connection lost"', () async {
      ch.client.handlers.remove('fs/read_text_file');
      final read = ch.env().readText('/work/lib/a.dart');
      await ch.client.arrival('fs/read_text_file');

      await ch.client.close();

      expect(
        await read,
        isA<Err<String, FileError>>()
            .having((r) => r.error.code, 'code', FileErrorCode.io)
            .having(
              (r) => r.error.message,
              'message',
              'client connection lost',
            ),
      );
    });

    test('abortPending ends waiting fs requests as aborted', () async {
      ch.client.handlers.remove('fs/read_text_file');
      final env = ch.env();
      final read = env.readText('/work/lib/a.dart');
      await ch.client.arrival('fs/read_text_file');

      env.abortPending();

      expect(
        await read,
        isA<Err<String, FileError>>()
            .having((r) => r.error.code, 'code', FileErrorCode.io)
            .having((r) => r.error.message, 'message', 'aborted'),
      );
    });
  });

  group('exec', () {
    late ClientChannel ch;

    setUp(() async {
      ch = await ClientChannel.open();
    });

    List<String> terminalMethods() => [
      for (final m in ch.client.methods)
        if (m.startsWith('terminal/')) m,
    ];

    test(
      'create, wait, output, release; the terminal reaches onTerminal',
      () async {
        ch.client.serveTerminals(exitCode: 1, output: 'Some tests failed.\n');
        final terminals = <String>[];

        final result = await ch.env().exec(
          'dart test',
          ExecOptions(
            cwd: '/work/demo',
            env: {'GIT_PAGER': 'cat'},
            onTerminal: terminals.add,
          ),
        );

        expect(terminalMethods(), [
          'terminal/create',
          'terminal/wait_for_exit',
          'terminal/output',
          'terminal/release',
        ]);
        expect(ch.client.paramsOf('terminal/create'), {
          'sessionId': 'sess_1',
          'command': '/bin/sh',
          'args': ['-c', 'dart test'],
          'env': [
            {'name': 'GIT_PAGER', 'value': 'cat'},
          ],
          'cwd': '/work/demo',
          'outputByteLimit': 1048576,
        });
        expect(ch.client.requests.first.id, JsonRpcId.string('term-1'));
        expect(terminals, ['term_1']);
        expect(
          result,
          isA<Ok<ExecResult, ExecError>>()
              .having((r) => r.value.exitCode, 'exitCode', 1)
              .having((r) => r.value.output, 'output', 'Some tests failed.\n')
              .having((r) => r.value.truncated, 'truncated', isFalse),
        );
      },
    );

    test('an error of wait_for_exit still releases the terminal', () async {
      ch.client
        ..serveTerminals()
        ..handlers['terminal/wait_for_exit'] = (_) =>
            throw const ClientFailure(-32603, 'terminal crashed');

      final result = await ch.env().exec('make', ExecOptions(cwd: '/work'));

      expect(result, isA<Err<ExecResult, ExecError>>());
      expect(terminalMethods().last, 'terminal/release');
      expect(
        terminalMethods().where((m) => m == 'terminal/release'),
        hasLength(1),
      );
    });

    test(
      'timeout: kill, output, release and Err(timeout) with the tail',
      () async {
        ch.client.serveTerminals(holdExit: true, output: 'still running\n');

        final result = ch.env().exec(
          'sleep 60',
          ExecOptions(cwd: '/work', timeout: const Duration(seconds: 5)),
        );
        await ch.client.arrival('terminal/wait_for_exit');
        await ch.clock.elapse(const Duration(seconds: 5));

        expect(
          await result,
          isA<Err<ExecResult, ExecError>>()
              .having((r) => r.error.code, 'code', ExecErrorCode.timeout)
              .having((r) => r.error.outputTail, 'tail', 'still running\n'),
        );
        expect(terminalMethods(), [
          'terminal/create',
          'terminal/wait_for_exit',
          'terminal/kill',
          'terminal/output',
          'terminal/release',
        ]);
      },
    );

    test('cancel: kill, output, release and Err(aborted)', () async {
      ch.client.serveTerminals(holdExit: true);
      final cancel = CancelTokenSource();

      final result = ch.env().exec(
        'sleep 60',
        ExecOptions(cwd: '/work', cancel: cancel.token),
      );
      await ch.client.arrival('terminal/wait_for_exit');
      cancel.cancel();

      expect(
        await result,
        isA<Err<ExecResult, ExecError>>().having(
          (r) => r.error.code,
          'code',
          ExecErrorCode.aborted,
        ),
      );
      expect(terminalMethods().sublist(2), [
        'terminal/kill',
        'terminal/output',
        'terminal/release',
      ]);
    });

    test('a failed release is only logged', () async {
      ch.client
        ..serveTerminals()
        ..handlers['terminal/release'] = (_) =>
            throw const ClientFailure(-32603, 'gone');

      final result = await ch.env().exec('true', ExecOptions(cwd: '/work'));

      expect(result, isA<Ok<ExecResult, ExecError>>());
      expect(ch.logger.eventsOf('acp.terminal.release_failed'), isNotEmpty);
    });

    test('a failed create is spawnFailed without release', () async {
      ch.client
        ..serveTerminals()
        ..handlers['terminal/create'] = (_) =>
            throw const ClientFailure(-32603, 'no shell');

      final result = await ch.env().exec('true', ExecOptions(cwd: '/work'));

      expect(
        result,
        isA<Err<ExecResult, ExecError>>().having(
          (r) => r.error.code,
          'code',
          ExecErrorCode.spawnFailed,
        ),
      );
      expect(terminalMethods(), ['terminal/create']);
    });

    test('without the terminal capability no frame is sent', () async {
      final narrow = await ClientChannel.open(
        capabilities: const ClientCapabilities(
          fs: FileSystemCapabilities(readTextFile: true, writeTextFile: true),
        ),
      );

      final result = await narrow.env().exec('ls', ExecOptions(cwd: '/work'));

      expect(
        result,
        isA<Err<ExecResult, ExecError>>().having(
          (r) => r.error.code,
          'code',
          ExecErrorCode.shellUnavailable,
        ),
      );
      await pumpEventQueue();
      expect(narrow.client.requests, isEmpty);
    });
  });

  test('timeouts default to §13.9', () {
    const timeouts = AcpTimeouts();

    expect(timeouts.fs, const Duration(seconds: 30));
    expect(timeouts.terminalKill, const Duration(seconds: 10));
  });
}
