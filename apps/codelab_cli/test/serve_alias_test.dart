// Модульные тесты алиаса `codelab serve` без процессов (change
// `retire-python-agent`, задачи 1.3 и 1.5; design.md D7, D9; spec codelab-cli
// «Алиас codelab serve»).

import 'dart:async';
import 'dart:io' show ProcessException, ProcessSignal;

import 'package:codelab_cli/codelab_cli.dart' show CliIo, SignalSeam;
import 'package:codelab_cli/src/serve_alias.dart';
import 'package:test/test.dart';

void main() {
  _runTests();

  group('locateAgentExecutable', () {
    /// Поиск над виртуальной файловой системой: [files] — исполняемые файлы,
    /// [links] — канонические пути ссылок (по умолчанию путь канонический).
    String? locate({
      String codelab = '/opt/codelab/bin/codelab',
      String? path,
      Set<String> files = const {},
      Map<String, String> links = const {},
      bool isWindows = false,
    }) => locateAgentExecutable(
      codelabExecutable: codelab,
      path: path,
      pathSeparator: isWindows ? ';' : ':',
      isWindows: isWindows,
      isExecutableFile: files.contains,
      canonicalize: (file) => links[file] ?? file,
    );

    test('the binary next to codelab wins over PATH', () {
      expect(
        locate(
          path: '/usr/local/bin',
          files: {
            '/opt/codelab/bin/codelab-agent',
            '/usr/local/bin/codelab-agent',
          },
        ),
        '/opt/codelab/bin/codelab-agent',
      );
    });

    test('PATH entries are searched in order', () {
      expect(
        locate(
          path: '/a:/b:/c',
          files: {'/c/codelab-agent', '/b/codelab-agent'},
        ),
        '/b/codelab-agent',
      );
    });

    test('empty and relative PATH entries are skipped (no current dir)', () {
      expect(
        locate(
          path: ':.:bin:/real',
          files: {
            'codelab-agent',
            './codelab-agent',
            'bin/codelab-agent',
            '/real/codelab-agent',
          },
        ),
        '/real/codelab-agent',
      );
      expect(
        locate(path: ':.:bin', files: {'codelab-agent', './codelab-agent'}),
        isNull,
      );
    });

    test('on Windows the name is codelab-agent.exe and ; separates PATH', () {
      expect(
        locate(
          codelab: r'C:\codelab\codelab.exe',
          path: r'C:\x;D:\tools',
          files: {r'D:\tools\codelab-agent.exe', r'D:\tools\codelab-agent'},
          isWindows: true,
        ),
        r'D:\tools\codelab-agent.exe',
      );
    });

    test('a candidate whose canonical path is codelab itself is dropped, the '
        'search goes on', () {
      expect(
        locate(
          path: '/loop:/real',
          files: {'/loop/codelab-agent', '/real/codelab-agent'},
          links: {'/loop/codelab-agent': '/opt/codelab/bin/codelab'},
        ),
        '/real/codelab-agent',
      );
    });

    test('the only candidate being a link to codelab means not found', () {
      expect(
        locate(
          path: '/loop',
          files: {'/loop/codelab-agent'},
          links: {'/loop/codelab-agent': '/opt/codelab/bin/codelab'},
        ),
        isNull,
      );
    });

    test('codelab itself is compared by its canonical path too', () {
      expect(
        locate(
          codelab: '/link/codelab',
          path: '/bin',
          files: {'/bin/codelab-agent'},
          links: {
            '/link/codelab': '/real/codelab',
            '/bin/codelab-agent': '/real/codelab',
          },
        ),
        isNull,
      );
    });

    test('on Windows the quotes around a PATH entry are removed', () {
      expect(
        locate(
          codelab: r'C:\codelab\codelab.exe',
          path: r'"D:\Program Files\tools";"E:\x"',
          files: {r'D:\Program Files\tools\codelab-agent.exe'},
          isWindows: true,
        ),
        r'D:\Program Files\tools\codelab-agent.exe',
      );
    });

    test('nothing found and a missing PATH give null', () {
      expect(locate(path: '/a:/b'), isNull);
      expect(locate(path: null), isNull);
      expect(locate(path: ''), isNull);
    });
  });

  group('serveAliasExitCode', () {
    test('a normal code of the agent is passed as is', () {
      for (final code in [0, 1, 64, 143]) {
        expect(serveAliasExitCode(code), code);
      }
    });

    test('a negative code is a signal N and becomes 128 + N', () {
      expect(serveAliasExitCode(-15), 143);
      expect(serveAliasExitCode(-2), 130);
      expect(serveAliasExitCode(-9), 137);
    });
  });

  group('texts', () {
    test('the warning is one line with the replacement command', () {
      expect(
        serveAliasWarning,
        'codelab: "codelab serve" is deprecated and will be removed in a '
        'future release; use "codelab-agent serve" instead.',
      );
      expect(serveAliasWarning, isNot(contains('\n')));
    });

    test('not found names both places and prints no PATH', () {
      expect(
        serveAliasNotFound,
        'codelab: codelab-agent was not found next to codelab or in PATH; '
        'install it or run "codelab-agent serve" directly',
      );
    });

    test('a start failure carries only the OS message', () {
      expect(
        serveAliasStartFailure('Permission denied'),
        'codelab: cannot start codelab-agent: Permission denied',
      );
    });
  });
}

// Поведение `runServeAlias` на подставных запуске, файловой системе и
// сигналах: ни процессов, ни `chmod` (D9, D10). Порядок событий задаётся
// явно: сигнал посылается до или после `Completer` старта, выход агента
// завершает тест.
void _runTests() {
  group('runServeAlias', () {
    late Map<String, String> environment;
    late List<String> events;
    late _RecordingIo io;
    late StreamController<ProcessSignal> sigint;
    late StreamController<ProcessSignal> sigterm;
    late StreamController<ProcessSignal> sighup;
    late Completer<AgentProcess> started;
    late Completer<int> exit;
    late List<ProcessSignal> kills;
    late List<Map<String, String>> startEnvironments;

    setUp(() {
      environment = {'PATH': '/agents'};
      events = [];
      io = _RecordingIo(events);
      sigint = StreamController<ProcessSignal>.broadcast();
      sigterm = StreamController<ProcessSignal>.broadcast();
      sighup = StreamController<ProcessSignal>.broadcast();
      started = Completer<AgentProcess>();
      exit = Completer<int>();
      kills = [];
      startEnvironments = [];
    });
    tearDown(() {
      unawaited(sigint.close());
      unawaited(sigterm.close());
      unawaited(sighup.close());
    });

    Future<int> run({
      Future<AgentProcess> Function()? start,
      bool windows = false,
    }) => runServeAlias(
      ['--stdio'],
      environment: environment,
      io: io,
      signals: SignalSeam(
        sigint: sigint.stream,
        sigterm: sigterm.stream,
        sighup: sighup.stream,
        forceExit: (_) => fail('forced exit'),
      ),
      codelabExecutable: windows
          ? r'C:\codelab\codelab.exe'
          : '/nowhere/codelab',
      isWindows: windows,
      isExecutableFile: (file) =>
          file == '/agents/codelab-agent' ||
          file == r'C:\agents\codelab-agent.exe',
      canonicalize: (file) => file,
      startAgent: (executable, args, extra) {
        events.add('start ${args.join(' ')}');
        startEnvironments.add(extra);
        return start != null ? start() : started.future;
      },
    );

    AgentProcess agent() => AgentProcess(
      kill: (signal) {
        kills.add(signal);
        return true;
      },
      exitCode: exit.future,
    );

    test('the warning is flushed before the process starts', () async {
      final result = run();
      await pumpEventQueue();
      expect(events, [
        'stderr $serveAliasWarning',
        'flush',
        'start serve --stdio',
      ]);

      started.complete(agent());
      exit.complete(0);
      expect(await result, 0);
    });

    test('the child gets the recursion marker', () async {
      final result = run();
      started.complete(agent());
      exit.complete(0);
      await result;

      expect(startEnvironments, [
        {serveAliasMarker: '1'},
      ]);
    });

    test('with the marker in the environment the agent is not started: 1, '
        'a message without argv', () async {
      environment[serveAliasMarker] = '1';

      expect(await run(), 1);
      expect(events, [
        'stderr $serveAliasWarning',
        'flush',
        'stderr $serveAliasRecursion',
      ]);
      expect(serveAliasRecursion, isNot(contains('--stdio')));
    });

    test('SIGTERM before the start is forwarded right after it', () async {
      final result = run();
      await pumpEventQueue();
      sigterm.add(ProcessSignal.sigterm);
      await pumpEventQueue();
      expect(kills, isEmpty);

      started.complete(agent());
      await pumpEventQueue();
      expect(kills, [ProcessSignal.sigterm]);

      exit.complete(143);
      expect(await result, 143);
    });

    test('an early SIGTERM and a start failure: 1, no kill', () async {
      final failing = Completer<AgentProcess>();
      final result = run(start: () => failing.future);
      await pumpEventQueue();
      sigterm.add(ProcessSignal.sigterm);
      await pumpEventQueue();

      failing.completeError(
        const ProcessException('/x/codelab-agent', [], 'Permission denied'),
      );

      expect(await result, 1);
      expect(kills, isEmpty);
    });

    test('SIGTERM while the agent runs is forwarded, each time', () async {
      final result = run();
      started.complete(agent());
      await pumpEventQueue();

      sigterm
        ..add(ProcessSignal.sigterm)
        ..add(ProcessSignal.sigterm);
      await pumpEventQueue();
      expect(kills, [ProcessSignal.sigterm, ProcessSignal.sigterm]);

      exit.complete(143);
      expect(await result, 143);
    });

    test('SIGHUP is forwarded like SIGTERM, an early one after the start; '
        'the agent dying of it gives 129', () async {
      final result = run();
      await pumpEventQueue();
      sighup.add(ProcessSignal.sighup);
      await pumpEventQueue();
      expect(kills, isEmpty);

      started.complete(agent());
      await pumpEventQueue();
      sighup.add(ProcessSignal.sighup);
      await pumpEventQueue();
      expect(kills, [ProcessSignal.sighup, ProcessSignal.sighup]);

      exit.complete(-1);
      expect(await result, 129);
      expect(sighup.hasListener, isFalse);
    });

    test('SIGINT is caught but not forwarded, listeners are removed at the '
        'end', () async {
      final result = run();
      started.complete(agent());
      await pumpEventQueue();
      expect(sigint.hasListener, isTrue, reason: 'SIGINT must be caught');
      expect(sigterm.hasListener, isTrue);

      sigint.add(ProcessSignal.sigint);
      await pumpEventQueue();
      expect(kills, isEmpty);

      exit.complete(7);
      expect(await result, 7);
      expect(sigint.hasListener, isFalse);
      expect(sigterm.hasListener, isFalse);
    });

    test('a negative exit code of the agent becomes 128 + N', () async {
      final result = run();
      started.complete(agent());
      exit.complete(-15);

      expect(await result, 143);
    });

    test('a start failure is 1 with the OS message only: no argv, no '
        'secrets; listeners are removed', () async {
      final result = run(
        start: () => Future.error(
          const ProcessException(
            '/x/codelab-agent',
            ['serve', '--stdio', '--provider-config', '{"apiKey":"SECRET"}'],
            'Permission denied',
            13,
          ),
        ),
      );

      expect(await result, 1);
      expect(events, [
        'stderr $serveAliasWarning',
        'flush',
        'start serve --stdio',
        'stderr codelab: cannot start codelab-agent: Permission denied',
      ]);
      final text = events.join('\n');
      for (final leak in ['SECRET', '--provider-config', 'apiKey']) {
        expect(text, isNot(contains(leak)));
      }
      expect(sigint.hasListener, isFalse);
      expect(sigterm.hasListener, isFalse);
      expect(sighup.hasListener, isFalse);
    });

    test('no agent in PATH is 1 and nothing is started', () async {
      environment['PATH'] = '/elsewhere';

      expect(await run(), 1);
      expect(events, [
        'stderr $serveAliasWarning',
        'flush',
        'stderr $serveAliasNotFound',
      ]);
    });

    test('on Windows codelab-agent.exe is found and started', () async {
      environment['PATH'] = r'C:\agents';
      final result = run(windows: true);
      started.complete(agent());
      await pumpEventQueue();

      expect(events, contains('start serve --stdio'));
      exit.complete(0);
      expect(await result, 0);
    });
  });
}

final class _RecordingIo implements CliIo {
  _RecordingIo(this._events);

  final List<String> _events;

  @override
  Stream<List<int>> get stdin => const Stream.empty();

  @override
  bool get stdinIsTerminal => false;

  @override
  bool get stdoutIsTerminal => false;

  @override
  StringSink get stdout => throw StateError('the alias must not write stdout');

  @override
  StringSink get stderr => _Lines((line) => _events.add('stderr $line'));

  @override
  Future<void> flush() async => _events.add('flush');
}

final class _Lines implements StringSink {
  _Lines(this._onLine);

  final void Function(String line) _onLine;

  @override
  void writeln([Object? object = '']) => _onLine('$object');

  @override
  void write(Object? object) => _onLine('$object');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _onLine(objects.join(separator));

  @override
  void writeCharCode(int charCode) => _onLine(String.fromCharCode(charCode));
}
