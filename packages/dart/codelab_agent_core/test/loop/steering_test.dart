import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/loop/agent.dart';
import 'package:codelab_agent_core/src/loop/loop_config.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

String _text(Message m) => switch (m) {
  UserMessage(:final content) || ToolResultMessage(:final content) =>
    content.whereType<TextContent>().map((b) => b.text).join(),
  AssistantMessage(:final content) =>
    content.whereType<TextContent>().map((b) => b.text).join(),
};

void main() {
  // Steering и follow-up (LOOP-8, CAN-6).
  test(
    'steer during a batch is delivered after the whole batch, FIFO',
    () async {
      late Agent agent;
      final h = await LoopHarness.create(
        tools: [
          FakeTool(
            'slow',
            onExecute: (args, ctx) async {
              if (ctx.toolCallId == 'c1') {
                for (final text in ['s1', 's2', 's3']) {
                  agent.steer(user(text));
                }
              }
              return const ToolExecutionResult([TextContent('ok')]);
            },
          ),
        ],
        llm: script([
          callStep([('c1', 'slow', const {}), ('c2', 'slow', const {})]),
          textStep('Done.'),
        ]),
      );
      agent = Agent(config: h.config(), systemPrompt: '', tools: h.tools);

      await agent.prompt([user('go')]);

      expect(agent.messages.map(_describe), [
        'user go',
        'assistant',
        'toolResult c1',
        'toolResult c2',
        'user s1',
        'user s2',
        'user s3',
        'assistant Done.',
      ]);
      // Один опрос — один шаг: после пакета ровно один запрос к модели.
      expect(h.scripted!.requests, hasLength(2));
      expect(h.scripted!.requests[1].messages.map(_text).skip(4), [
        's1',
        's2',
        's3',
      ]);
    },
  );

  test('items queued before the first step are taken in one poll', () async {
    final h = await LoopHarness.create(llm: script([textStep('ok')]));
    final steering = ListMessageQueue<SteeringItem>()
      ..add(SteeringItem(user('a')))
      ..add(SteeringItem(user('b')));

    await h.run([user('go')], config: h.config(steering: steering));

    expect(steering.isEmpty, isTrue);
    expect(h.events.whereType<StepStarted>(), hasLength(1));
    expect(h.scripted!.requests.single.messages.map(_text), ['go', 'a', 'b']);
  });

  test('at most maxSteeringSteps steps are added by steering', () async {
    final steering = ListMessageQueue<SteeringItem>();
    var calls = 0;
    final inner = await LoopHarness.create(
      llm: script([for (var i = 0; i < 25; i++) textStep('r$i')]),
    );
    // Каждый запрос к модели приносит новое сообщение steering.
    AssistantMessageEventStream stream(
      ModelRef model,
      LlmContext context, {
      CancelToken? cancel,
    }) {
      calls++;
      steering.add(SteeringItem(user('steer $calls')));
      return inner.scripted!.call(model, context, cancel: cancel);
    }

    final h = await LoopHarness.create(stream: stream);

    await h.run([
      user('go'),
    ], config: h.config(steering: steering, maxSteeringSteps: 20));

    // Первый шаг — от prompt, ещё 20 — от steering.
    expect(h.events.whereType<StepStarted>(), hasLength(21));
    expect(steering.length, 1);
    expect(h.trace.last, 'TurnEnded(completed)');
  });

  test('steering is not taken when the next step will not start', () async {
    final steering = ListMessageQueue<SteeringItem>();
    final h = await LoopHarness.create(
      tools: [FakeTool('probe')],
      llm: script([
        callStep([('c1', 'probe', const {})]),
      ]),
    );
    final config = h.config(
      steering: steering,
      budget: const TurnBudget(maxSteps: 1),
      afterToolCall: [
        (call, result, isError) async {
          steering.add(SteeringItem(user('late')));
          return null;
        },
      ],
    );

    await h.run([user('go')], config: config);

    expect(h.trace.last, 'TurnEnded(completed steps)');
    expect(steering.length, 1);
  });

  test(
    'followUp starts a step in the same turn after a natural stop',
    () async {
      final h = await LoopHarness.create(
        llm: script([textStep('one'), textStep('two')]),
      );
      final agent = Agent(
        config: h.config(),
        systemPrompt: '',
        tools: const [],
      );
      final seen = <String>[];
      agent.subscribe((e) {
        seen.add(describe(e));
        if (e is TurnStarted) {
          agent.followUp(user('next task'));
        }
      });

      await agent.prompt([user('go')]);

      expect(seen.where((e) => e == 'TurnStarted'), hasLength(1));
      expect(seen.where((e) => e.startsWith('TurnEnded')), hasLength(1));
      expect(agent.messages.map(_describe), [
        'user go',
        'assistant one',
        'user next task',
        'assistant two',
      ]);
    },
  );

  test('followUp outside a turn waits for the next turn', () async {
    final h = await LoopHarness.create(
      llm: script([textStep('one'), textStep('two')]),
    );
    final agent = Agent(config: h.config(), systemPrompt: '', tools: const [])
      ..followUp(user('later'));

    await agent.prompt([user('go')]);

    expect(agent.messages.map(_describe), [
      'user go',
      'assistant one',
      'user later',
      'assistant two',
    ]);
  });
}

String _describe(Message m) => switch (m) {
  UserMessage() => 'user ${_text(m)}',
  AssistantMessage() =>
    _text(m).isEmpty ? 'assistant' : 'assistant ${_text(m)}',
  ToolResultMessage(:final toolCallId) => 'toolResult $toolCallId',
};
