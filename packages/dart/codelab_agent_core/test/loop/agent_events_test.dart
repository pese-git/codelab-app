import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Compiles only while the switch covers every event: the hierarchy is
/// closed (agent-loop «События AgentEvent»).
String kindOf(AgentEvent event) => switch (event) {
  TurnStarted() => 'turn',
  StepStarted() => 'step',
  ModelRequested() => 'model',
  MessageStarted() => 'message.start',
  MessageDelta() => 'message.delta',
  ThoughtDelta() => 'thought.delta',
  MessageEnded() => 'message.end',
  ToolCallStarted() => 'tool.start',
  ToolCallProgress() => 'tool.progress',
  ToolCallFinished() => 'tool.finish',
  ToolPairingRepaired() => 'pairing',
  StepEnded() => 'step.end',
  PlanUpdated() => 'plan',
  ModeChanged() => 'mode',
  AgentError() => 'error',
  TurnEnded() => 'turn.end',
};

void main() {
  const session = SessionId('sess-1');

  test('every event carries its session id', () {
    final events = <AgentEvent>[
      TurnStarted(session, turnId: const TurnId('t-1'), input: const []),
      StepStarted(session, stepIndex: 0),
      TurnEnded(session, reason: TurnEndReason.completed, usage: Usage.zero),
    ];

    expect([for (final e in events) e.sessionId], everyElement(session));
    expect([for (final e in events) kindOf(e)], ['turn', 'step', 'turn.end']);
  });

  test('closed enums of the turn', () {
    expect(TurnEndReason.values.map((v) => v.name), [
      'completed',
      'maxTokens',
      'refused',
      'cancelled',
      'failed',
    ]);
    expect(ToolOutcome.values.map((v) => v.name), [
      'completed',
      'failed',
      'cancelled',
      'rejected',
    ]);
    expect(AgentErrorClass.values.map((v) => v.name), [
      'provider',
      'fallback',
      'compaction',
      'hook',
      'storage',
    ]);
  });

  test('origins of loop messages', () {
    const nudge = LoopNudgeOrigin(LoopNudgeReason.emptyResponse, 2);
    const note = LoopNoteOrigin(LoopNudgeReason.emptyResponse);
    final MessageOrigin origin = nudge;

    expect(nudge.attempt, 2);
    expect(note.reason, LoopNudgeReason.emptyResponse);
    expect(origin, isA<LoopNudgeOrigin>());
  });

  test('the turn budget defaults to 50 steps and no other limit', () {
    const budget = TurnBudget();

    expect(budget.maxSteps, 50);
    expect(budget.maxTokens, isNull);
    expect(budget.maxCost, isNull);
    expect(budget.maxDuration, isNull);
  });
}
