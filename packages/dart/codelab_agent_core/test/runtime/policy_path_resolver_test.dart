import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../env/resolving_env.dart';
import '../host/core_harness.dart' show CoreHarness, callStep, textStep;
import '../permissions/fake_gate.dart';

/// PERM-11 в сессиях `serve` (design.md change `add-config-writer-and-reload`,
/// D8; ревью итерации 5): окружение сессии от хоста (`ports.env`) —
/// клиентское и `PathResolver` не реализует, а канонизацию путей должен
/// давать `services.baseEnv`.
void main() {
  Future<(CoreHarness, FakeGate)> build(
    List<Map<String, Object?>> steps,
  ) async {
    final memory = MemoryExecutionEnv(cwd: '/proj');
    await memory.writeText('/proj/.codelab/config.local.yaml', 'old\n');
    await memory.writeText('/proj/a', 'a\n');
    final base = ResolvingEnv(
      memory,
      links: {'/proj/c.yaml': '/proj/.codelab/config.local.yaml'},
    );
    final gate = FakeGate();
    final h = CoreHarness.build(
      baseEnv: base,
      steps: steps,
      gate: gate,
      agentConfigPaths: AgentConfigPaths(
        paths: ['/proj/.codelab/config.local.yaml'],
      ),
      permissions: const PermissionsConfig(mode: ModeId.bypass),
    );
    return (h, gate);
  }

  Future<void> run(CoreHarness h, ExecutionEnv env) async {
    final session = await h.core.runtime.createSession(
      SessionSpec(
        cwd: '/proj',
        ports: SessionHostPorts(env: env),
      ),
    );
    await session.prompt([const TextContent('go')]);
  }

  test('a write through a link to the local config is critical when the '
      'session env is not a PathResolver but baseEnv is', () async {
    final (h, gate) = await build([
      callStep('w1', 'write', {'path': 'c.yaml', 'content': 'x'}),
      textStep('done'),
    ]);

    await run(h, _Plain(MemoryExecutionEnv(cwd: '/proj')));

    expect(gate.requests, hasLength(1));
    expect(gate.requests.single.allowAlwaysOffered, isFalse);
  });

  test('mv a . in the root is not critical', () async {
    final (h, gate) = await build([
      callStep('x1', 'exec', {'command': 'mv a .'}),
      textStep('done'),
    ]);

    await run(h, _Plain(MemoryExecutionEnv(cwd: '/proj')));

    expect(gate.requests, isEmpty);
  });
}

/// Окружение сессии от клиента: делегирует, но `PathResolver` не реализует.
final class _Plain implements ExecutionEnv {
  _Plain(this._inner);
  final ExecutionEnv _inner;

  @override
  String get cwd => _inner.cwd;

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) => _inner.readText(path, line: line, limit: limit);

  @override
  Future<Result<void, FileError>> writeText(String path, String content) =>
      _inner.writeText(path, content);

  @override
  Future<Result<FileStat, FileError>> stat(String path) => _inner.stat(path);

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => _inner.exec(command, options);
}
