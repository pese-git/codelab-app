import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../tools/fake_shell.dart';

/// `core/resume-after-crash-no-tool-recall` и `core/interrupted-tool-not-
/// retried` (S-13; agent-sessions «Продолжение прерванного хода», SES-9,
/// SES-10). «Сбой» — снимок журнала, пока идёт долгий `exec`: процесс
/// дальше ничего не записал бы.
void main() {
  /// The journal text at the moment the long `exec` is running.
  Future<(SessionId, String, _CountingEnv)> crashDuringExec() async {
    final store = MemorySessionStore();
    final hang = Completer<Result<ExecResult, ExecError>>();
    final env = _CountingEnv(
      MemoryExecutionEnv(cwd: '/proj'),
      (command, options) => hang.future,
    );
    final h = CoreHarness.build(
      baseEnv: env,
      gate: FakeGate(),
      sessions: store,
      steps: [
        callStep('c1', 'write', {'path': 'a.txt', 'content': 'A'}),
        callStep('c2', 'exec', {'command': 'sleep 600'}),
      ],
    );
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj', mode: ModeId.bypass),
    );
    unawaited(session.prompt(const [TextContent('Write a.txt, then wait')]));
    while (env.commands.isEmpty) {
      await pumpEventQueue();
    }
    return (session.id, store.textOf(session.id)!, env);
  }

  test('a crash after a tool does not call it again', () async {
    final (id, crashed, before) = await crashDuringExec();
    expect(before.writes, 1);

    final store = MemorySessionStore()..putText(id, crashed);
    final env = _CountingEnv(
      MemoryExecutionEnv(cwd: '/proj'),
      answering('should not run'),
    );
    final h = CoreHarness.build(
      baseEnv: env,
      gate: FakeGate(),
      sessions: store,
      steps: [textStep('Continuing.')],
    );
    final session = await h.core.runtime.loadSession(
      id,
      const SessionHostPorts(),
    );
    await session.prompt(const [TextContent('продолжай')]);

    expect(env.writes, 0);
    expect(env.commands, isEmpty);
    final messages = h.model.requests.single.messages;
    final results = {
      for (final m in messages.whereType<ToolResultMessage>()) m.toolCallId: m,
    };
    expect(results.keys, ['c1', 'c2']);
    expect(results['c1']!.isError, isFalse);
    expect(results['c2']!.isError, isTrue);
    expect(
      (results['c2']!.content.single as TextContent).text,
      startsWith('Tool call was interrupted'),
    );
  });

  test('the interrupted result is written once, before the replay', () async {
    final (id, crashed, _) = await crashDuringExec();
    final store = MemorySessionStore()..putText(id, crashed);

    for (var i = 0; i < 2; i++) {
      final h = CoreHarness.build(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        narrow: noExec,
        gate: FakeGate(),
        sessions: store,
        steps: const [],
      );
      final session = await h.core.runtime.loadSession(
        id,
        const SessionHostPorts(),
      );
      final finished = session.replay().whereType<ToolCallFinished>().toList();
      expect(finished.map((e) => e.toolCallId), ['c1', 'c2']);
      expect(finished.last.interrupted, isTrue);
      expect(finished.last.outcome, ToolOutcome.failed);
      await h.core.runtime.dispose();
    }

    expect(
      '"outcome":"interrupted"'.allMatches(store.textOf(id)!),
      hasLength(1),
    );
  });
}

/// [FakeShellEnv] that counts `write` calls.
final class _CountingEnv implements ExecutionEnv, DirectoryListing {
  _CountingEnv(MemoryExecutionEnv memory, ShellHandler handler)
    : _inner = FakeShellEnv(memory, handler);

  final FakeShellEnv _inner;
  var writes = 0;

  List<String> get commands => _inner.commands;

  @override
  String get cwd => _inner.cwd;

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => _inner.exec(command, options);

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) => _inner.readText(path, line: line, limit: limit);

  @override
  Future<Result<void, FileError>> writeText(String path, String content) {
    writes++;
    return _inner.writeText(path, content);
  }

  @override
  Future<Result<FileStat, FileError>> stat(String path) => _inner.stat(path);

  @override
  Future<Result<List<FileStat>, FileError>> listDir(String path) =>
      _inner.listDir(path);
}
