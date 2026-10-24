import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/update_plan.dart';
import 'package:test/test.dart';

import '../executor_harness.dart';

void main() {
  late ExecutorHarness h;

  setUp(() async {
    h = await ExecutorHarness.create([UpdatePlanTool()]);
  });

  Map<String, Object?> entry(String content, String status) => {
    'content': content,
    'priority': 'medium',
    'status': status,
  };

  test('schema, tier and kind of §6.4', () {
    final tool = UpdatePlanTool();

    expect(tool.name, 'update_plan');
    expect(tool.tier, ToolTier.read);
    expect(tool.kind, ToolKind.think);
    expect(tool.parameters['required'], ['entries']);
  });

  test(
    'replaces the plan, PlanUpdated comes before ToolCallFinished',
    () async {
      final outcome = await h.run('update_plan', {
        'entries': [
          entry('read the code', 'completed'),
          entry('fix the bug', 'in_progress'),
          entry('run the tests', 'pending'),
        ],
      });

      expect(outcome.outcome, ToolOutcome.completed);
      expect(
        textOf(outcome),
        'Plan updated: 3 entries (1 completed, 1 in progress, 1 pending).',
      );
      expect(h.events.map((e) => e.runtimeType), [
        ToolCallStarted,
        PlanUpdated,
        ToolCallFinished,
      ]);
      final plan = h.events.whereType<PlanUpdated>().single;
      expect(plan.entries.map((e) => (e.content, e.status)), [
        ('read the code', PlanStatus.completed),
        ('fix the bug', PlanStatus.inProgress),
        ('run the tests', PlanStatus.pending),
      ]);
      expect(h.plan.entries, plan.entries);
    },
  );

  test('a second call replaces the whole plan', () async {
    await h.run('update_plan', {
      'entries': [entry('a', 'pending'), entry('b', 'pending')],
    });
    await h.run('update_plan', {
      'entries': [entry('c', 'completed')],
    }, id: 'call_2');

    expect(h.plan.entries.map((e) => e.content), ['c']);
  });

  test('more than one in_progress is allowed with a note (C-05)', () async {
    final outcome = await h.run('update_plan', {
      'entries': [entry('a', 'in_progress'), entry('b', 'in_progress')],
    });

    expect(outcome.outcome, ToolOutcome.completed);
    expect(
      textOf(outcome),
      'Plan updated: 2 entries (0 completed, 2 in progress, 0 pending).\n'
      '[Note: more than one entry is in_progress.]',
    );
  });

  test('an unknown status is a validation error', () async {
    final outcome = await h.run('update_plan', {
      'entries': [entry('a', 'done')],
    });

    expect(outcome.outcome, ToolOutcome.failed);
    expect(h.events.whereType<PlanUpdated>(), isEmpty);
  });
}
