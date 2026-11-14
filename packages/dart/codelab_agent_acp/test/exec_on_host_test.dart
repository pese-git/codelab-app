import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// agent-acp-server: признак `SessionHostPorts.execOnHost` (задача 2.14
/// change `add-agent-skills`; design.md D17, D5, Q23).
///
/// Рантайм разрешает `exec` с `cwd` в корне навыка только если команды
/// исполняются на машине агента: сервер ставит `true` лишь для `localEnv`.
void main() {
  late ServerHarness h;
  late _SpyRuntime spy;

  Future<void> open({ExecutionEnv Function(String cwd)? localEnv}) async {
    h = await ServerHarness.start(
      localEnv: localEnv,
      wrapRuntime: (inner) => spy = _SpyRuntime(inner),
    );
    await h.initialize();
    await h.newSession(cwd: '/work/demo');
  }

  tearDown(() => h.dispose());

  test('localEnv: execOnHost is true', () async {
    await open(localEnv: (_) => MemoryExecutionEnv(cwd: '/work/demo'));
    expect(spy.specs.single.ports.execOnHost, isTrue);
  });

  test('client env over terminal/*: execOnHost is false', () async {
    await open();
    expect(spy.specs.single.ports.execOnHost, isFalse);
  });

  test('localListing without localEnv: execOnHost is false', () async {
    h = await ServerHarness.start(
      localListing: (_) => MemoryExecutionEnv(cwd: '/work/demo'),
      wrapRuntime: (inner) => spy = _SpyRuntime(inner),
    );
    await h.initialize();
    await h.newSession(cwd: '/work/demo');
    expect(spy.specs.single.ports.execOnHost, isFalse);
  });
}

/// Рантайм-прокси: запоминает `SessionSpec`, остальное отдаёт настоящему.
final class _SpyRuntime implements AgentRuntime {
  _SpyRuntime(this.inner);

  final AgentRuntime inner;
  final specs = <SessionSpec>[];

  @override
  Future<AgentSession> createSession(SessionSpec spec) {
    specs.add(spec);
    return inner.createSession(spec);
  }

  @override
  SubagentsInfo? get subagents => inner.subagents;

  @override
  Future<void> dispose() => inner.dispose();

  // Остальные методы тесту не нужны: вызов упадёт явно.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
