import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:codelab_agent_core/src/tools/builtin/write.dart';
import 'package:test/test.dart';

import '../tools/executor_harness.dart';
import '../tools/fake_shell.dart';
import 'fake_gate.dart';
import 'policy_harness.dart';

const _paths = [
  '.codelab/config.yaml',
  '.codelab/config.local.yaml',
  '.codelab/cli.yaml',
  '.codelab/agents/x.md',
  '.codelab/skills/s/SKILL.md',
  '.codelab/prompts/p.md',
  '.codelab/hooks/pre.sh',
];

Future<(PolicyHarness, MemoryExecutionEnv)> _harness({
  ModeId mode = ModeId.bypass,
  PermissionMode? modeOverride,
  PermissionGate? gate,
}) async {
  final memory = MemoryExecutionEnv(cwd: '/proj');
  for (final path in _paths) {
    await memory.writeText('/proj/$path', 'old\n');
  }
  final h = await ExecutorHarness.create([
    ReadTool(),
    WriteTool(),
    EditTool(),
    ExecTool(),
  ], base: FakeShellEnv(memory, answering('')));
  final p = await PolicyHarness.wrap(
    h,
    mode: mode,
    modeOverride: modeOverride,
    gate: gate,
  );
  return (p, memory);
}

String _requiresHuman(String tool, String path) =>
    deniedText(tool, 'Editing agent configuration requires a human: $path');

void main() {
  // Критические пути правок конфигурации агента (§7.6.1, PERM-11).
  for (final mode in [ModeId.bypass, ModeId.acceptEdits]) {
    test('write and edit ask in ${mode.value} without allow_always', () async {
      final gate = FakeGate((_) => PermissionDecision.allowAlways);
      final (p, _) = await _harness(mode: mode, gate: gate);

      for (final (i, path) in _paths.indexed) {
        await p.run('write', {'path': path, 'content': 'x'}, id: 'w$i');
        await p.run('edit', {
          'path': './$path',
          'oldText': 'x',
          'newText': 'y',
        }, id: 'e$i');
      }

      expect(gate.requests, hasLength(_paths.length * 2));
      expect(
        gate.requests.map((r) => r.allowAlwaysOffered),
        everyElement(isFalse),
      );
    });
  }

  test('allow-always granted earlier does not apply to the path', () async {
    final gate = FakeGate();
    final (p, _) = await _harness(gate: gate);
    p.policy.decisions.allowAlways.add(
      const PermissionKey('write', '.codelab/config.yaml'),
    );

    await p.run('write', {'path': '.codelab/config.yaml', 'content': 'x'});

    expect(gate.requests, hasLength(1));
  });

  test('without a gate and in autopilot the edit is denied', () async {
    final (headless, _) = await _harness();
    final (autopilot, _) = await _harness(
      modeOverride: PermissionMode.autopilot,
      gate: FakeGate(),
    );

    final a = await headless.run('write', {
      'path': '.codelab/agents/x.md',
      'content': 'x',
    });
    final b = await autopilot.run('edit', {
      'path': '.codelab/config.yaml',
      'oldText': 'old',
      'newText': 'new',
    });

    expect(textOf(a), _requiresHuman('write', '.codelab/agents/x.md'));
    expect(textOf(b), _requiresHuman('edit', '.codelab/config.yaml'));
  });

  test('read of agent configuration is not restricted', () async {
    final gate = FakeGate();
    final (p, _) = await _harness(gate: gate);

    final outcome = await p.run('read', {'path': '.codelab/config.yaml'});

    expect(gate.requests, isEmpty);
    expect(outcome.outcome, ToolOutcome.completed);
  });

  test('other .codelab files and look-alikes are ordinary', () async {
    final gate = FakeGate();
    final (p, _) = await _harness(gate: gate);

    for (final (i, path) in [
      '.codelab/notes.md',
      'codelab/config.yaml',
      'lib/.codelab/config.yaml',
    ].indexed) {
      await p.run('write', {'path': path, 'content': 'x'}, id: 'o$i');
    }

    expect(gate.requests, isEmpty);
  });

  test('exec writing into agent configuration is critical', () async {
    final gate = FakeGate();
    final (p, _) = await _harness(gate: gate);

    for (final (i, command) in [
      'echo x >> .codelab/config.yaml',
      'tee .codelab/cli.yaml',
      'cp evil.md .codelab/agents/',
      'ln -s /tmp/x .codelab/hooks/pre.sh',
      "sed -i 's/a/b/' .codelab/config.yaml",
    ].indexed) {
      await p.run('exec', {'command': command}, id: 'x$i');
    }

    expect(
      gate.requests.map((r) => r.reason),
      everyElement('critical command: write to agent configuration'),
    );
    expect(gate.requests, hasLength(5));
  });
}
