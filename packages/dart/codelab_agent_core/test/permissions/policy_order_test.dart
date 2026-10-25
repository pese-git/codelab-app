import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../tools/executor_harness.dart';
import 'fake_gate.dart';
import 'policy_harness.dart';

void main() {
  test('an explicit deny beats a turn grant (PERM-2)', () async {
    final p = await PolicyHarness.create(
      mode: ModeId.bypass,
      rules: const PolicyRules(toolPolicies: {'x': ToolPolicy.deny}),
    );
    p.policy.grantForTurn(allow: {'x'});

    final outcome = await p.run('x', const {});

    expect(textOf(outcome), deniedText('x', 'denied by configuration'));
  });

  test('a deny pattern beats the mode', () async {
    final p = await PolicyHarness.create(
      mode: ModeId.bypass,
      rules: PolicyRules(denyPatterns: {const PermissionKey('x', '{"a":1}')}),
    );

    expect((await p.run('x', {'a': 1})).outcome, ToolOutcome.rejected);
    expect(
      (await p.run('x', {'a': 2}, id: 'b')).outcome,
      ToolOutcome.completed,
    );
  });

  test('a turn deny beats a tool allow', () async {
    final p = await PolicyHarness.create(
      rules: const PolicyRules(toolPolicies: {'w': ToolPolicy.allow}),
    );
    p.policy.grantForTurn(deny: {'w'});

    final outcome = await p.run('w', const {});

    expect(textOf(outcome), deniedText('w', 'not allowed in this turn'));
  });

  test('a tool allow beats the mode; a tool ask beats a turn grant', () async {
    final gate = FakeGate();
    final p = await PolicyHarness.create(
      mode: ModeId.ask,
      gate: gate,
      rules: const PolicyRules(
        toolPolicies: {'w': ToolPolicy.allow, 'x': ToolPolicy.ask},
      ),
    );
    p.policy.grantForTurn(allow: {'x'});

    await p.run('w', const {}, id: 'w1');
    await p.run('x', const {}, id: 'x1');

    expect(gate.requests.map((r) => r.toolCallId), ['x1']);
  });

  test('a turn grant and allow always skip the question', () async {
    final gate = FakeGate((_) => PermissionDecision.allowAlways);
    final p = await PolicyHarness.create(mode: ModeId.ask, gate: gate);
    p.policy.grantForTurn(allow: {'r'});

    await p.run('r', const {}, id: 'r1');
    await p.run('x', const {}, id: 'x1');
    await p.run('x', const {}, id: 'x2');

    expect(gate.requests.map((r) => r.toolCallId), ['x1']);
  });

  test('decisions of the gate', () async {
    for (final (decision, outcome, text) in [
      (PermissionDecision.allowOnce, ToolOutcome.completed, 'w ok'),
      (
        PermissionDecision.rejectOnce,
        ToolOutcome.rejected,
        deniedText('w', 'rejected by the user'),
      ),
      (
        PermissionDecision.cancelled,
        ToolOutcome.rejected,
        deniedText('w', 'permission request was cancelled'),
      ),
    ]) {
      final p = await PolicyHarness.create(gate: gateAnswering(decision));

      final result = await p.run('w', const {});

      expect(result.outcome, outcome, reason: decision.name);
      expect(textOf(result), text, reason: decision.name);
    }
  });

  test(
    'the request carries rawInput, locations and the diff of an edit (PERM-6)',
    () async {
      final memory = MemoryExecutionEnv(cwd: '/proj');
      await memory.writeText('/proj/lib/main.dart', 'debug: false\n');
      final gate = FakeGate();
      final p = await PolicyHarness.create(
        tools: [EditTool()],
        gate: gate,
        memory: memory,
      );

      await p.run('edit', {
        'path': 'lib/main.dart',
        'oldText': 'debug: false',
        'newText': 'debug: true',
      }, id: 'call_7');

      final request = gate.requests.single;
      expect(request.toolCallId, 'call_7');
      expect(request.tool, 'edit');
      expect(request.kind, ToolKind.edit);
      expect(request.tier, ToolTier.write);
      expect(request.title, 'Edit lib/main.dart');
      expect(request.rawInput, {
        'path': 'lib/main.dart',
        'oldText': 'debug: false',
        'newText': 'debug: true',
      });
      expect(request.locations, [
        const Location('/proj/lib/main.dart', line: 1),
      ]);
      expect(request.diffs, [
        const FileDiff(
          path: '/proj/lib/main.dart',
          oldText: 'debug: false\n',
          newText: 'debug: true\n',
        ),
      ]);
      expect(request.allowAlwaysOffered, isTrue);
    },
  );

  test(
    'a cancel during the wait is cancelled; the late answer changes nothing (PERM-4)',
    () async {
      final clock = FakeClock();
      final gate = FakeGate(
        (_) => PermissionDecision.allowOnce,
        clock,
        const Duration(seconds: 30),
      );
      final p = await PolicyHarness.create(gate: gate);
      final source = CancelTokenSource();

      final running = p.run('w', const {}, cancel: source.token);
      await clock.elapse(const Duration(seconds: 1));
      source.cancel();
      final outcome = await running;
      await clock.elapse(const Duration(seconds: 60));

      // Ход отменён во время вопроса — вызов отменён, а не отклонён
      // (§13.7, «Статусы вызова»; design.md change
      // `add-dart-agent-acp-server`, D13).
      expect(outcome.outcome, ToolOutcome.cancelled);
      expect(
        textOf(outcome),
        deniedText('w', 'permission request was cancelled'),
      );
    },
  );

  test(
    'the wait for the gate is metered and kept out of the turn time',
    () async {
      final p0 = await PolicyHarness.create();
      final clock = p0.h.clock;
      final gate = FakeGate(
        (_) => PermissionDecision.allowOnce,
        clock,
        const Duration(seconds: 42),
      );
      final p = await PolicyHarness.wrap(p0.h, gate: gate);

      final running = p.run('w', const {});
      await clock.elapse(const Duration(seconds: 50));
      await running;

      expect(
        p.h.executor.services.approvalWait.total,
        const Duration(seconds: 42),
      );
    },
  );

  test('logs name the call and the decision, never the arguments', () async {
    final p = await PolicyHarness.create(
      gate: gateAnswering(PermissionDecision.rejectOnce),
    );

    await p.run('w', {'secret': 'sk-123'});

    final denied = p.logger.eventsOf('permission.denied').single;
    expect(denied.fields['tool_call_id'], 'call_1');
    expect(denied.fields['tool'], 'w');
    expect(denied.fields['reason'], 'rejected by the user');
    expect(
      p.logger.records.map((r) => '${r.fields}'),
      everyElement(isNot(contains('sk-123'))),
    );
  });
}
