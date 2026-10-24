import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/loop/agent.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

Agent _agent(LoopHarness h, {List<Message> history = const []}) => Agent(
  config: h.config(),
  systemPrompt: 'You are CodeLab.',
  tools: h.tools,
  history: history,
);

void main() {
  test(
    'prompt runs a turn and every listener gets the events in order',
    () async {
      final h = await LoopHarness.create(
        tools: [FakeTool('read')],
        llm: script([
          callStep([('a', 'read', const {})]),
          textStep('Done.'),
        ]),
      );
      final agent = _agent(h);
      final first = <String>[];
      final second = <String>[];
      agent
        ..subscribe((e) => first.add(describe(e)))
        ..subscribe((e) => second.add(describe(e)));

      await agent.prompt([user('go')]);

      expect(first.first, 'TurnStarted');
      expect(first.last, 'TurnEnded(completed)');
      expect(second, first);
      expect(agent.isRunning, isFalse);
      expect(agent.messages.map((m) => m.runtimeType), [
        UserMessage,
        AssistantMessage,
        ToolResultMessage,
        AssistantMessage,
      ]);
    },
  );

  test('the transcript grows over turns and is an unmodifiable copy', () async {
    final h = await LoopHarness.create(
      llm: script([textStep('one'), textStep('two')]),
    );
    final agent = _agent(h);

    await agent.prompt([user('a')]);
    await agent.prompt([user('b')]);

    expect(agent.messages, hasLength(4));
    expect(h.scripted!.requests[1].messages, hasLength(3));
    expect(() => agent.messages.add(user('x')), throwsUnsupportedError);
  });

  test('unsubscribe stops the delivery', () async {
    final h = await LoopHarness.create(llm: script([textStep('ok')]));
    final agent = _agent(h);
    final seen = <AgentEvent>[];
    final unsubscribe = agent.subscribe(seen.add);
    unsubscribe();

    await agent.prompt([user('go')]);

    expect(seen, isEmpty);
  });

  test('abort cancels the turn: TurnEnded(cancelled)', () async {
    final h = await LoopHarness.create(
      llm: script([
        {'waitForCancel': true},
      ]),
    );
    final agent = _agent(h);
    final seen = <String>[];
    agent.subscribe((e) => seen.add(describe(e)));

    final turn = agent.prompt([user('go')]);
    await pumpEventQueue();
    expect(agent.isRunning, isTrue);
    agent.abort();
    await turn;

    expect(seen.last, 'TurnEnded(cancelled)');
    expect(agent.isRunning, isFalse);
  });

  test('waitForIdle completes after TurnEnded and every listener', () async {
    final h = await LoopHarness.create(llm: script([textStep('ok')]));
    final agent = _agent(h);
    final done = <String>[];
    agent.subscribe((e) async {
      if (e is TurnEnded) {
        await Future<void>.delayed(Duration.zero);
        done.add('listener');
      }
    });

    unawaited(agent.prompt([user('go')]));
    await pumpEventQueue(times: 2);
    await agent.waitForIdle();

    expect(done, ['listener']);
  });

  test('waitForIdle without a turn completes at once', () async {
    final h = await LoopHarness.create(llm: script([]));

    await _agent(h).waitForIdle();
  });

  test('replaceTranscript only outside a turn', () async {
    final h = await LoopHarness.create(
      llm: script([
        {'waitForCancel': true},
      ]),
    );
    final agent = _agent(h);

    agent.replaceTranscript([user('summary')]);
    expect(agent.messages, hasLength(1));
    final turn = agent.prompt([user('go')]);
    await pumpEventQueue();
    expect(() => agent.replaceTranscript(const []), throwsStateError);
    agent.abort();
    await turn;
  });
}
