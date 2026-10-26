import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/loop/loop_config.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

const _nudge =
    'Your previous response was empty. Continue the task: call a tool or '
    'answer the user with text.';

String _note(int attempts) =>
    '[Stopped: the model returned an empty response (attempts: $attempts). '
    'Send a message to continue.]';

/// Пустой ответ без текста и без вызовов.
const Map<String, Object?> _empty = {'reply': <Object?>[]};

/// Ответ только с рассуждением: для пользователя он тоже пустой (§5.4.1).
const Map<String, Object?> _thinkingOnly = {
  'reply': [
    {'thinking': 'hmm'},
  ],
};

/// Ответ из одних пробелов.
const Map<String, Object?> _blank = {
  'reply': [
    {'text': '  \n'},
  ],
};

void main() {
  // Критерий матрицы core/empty-completion-retried (C-07, LOOP-14, LOOP-15).
  test('(a) empty, thinking only, Done. — two nudges, three steps', () async {
    final h = await LoopHarness.create(
      llm: script([_empty, _thinkingOnly, textStep('Done.')]),
    );

    final added = await h.run([user('go')]);

    expect(h.trace, [
      'TurnStarted',
      'MessageStarted(user)',
      'MessageEnded(user)',
      'StepStarted(0)',
      'ModelRequested',
      'MessageStarted(assistant)',
      'MessageEnded(assistant stop)',
      'StepEnded(0)',
      'MessageStarted(user nudge 1)',
      'MessageEnded(user)',
      'StepStarted(1)',
      'ModelRequested',
      'MessageStarted(assistant)',
      'ThoughtDelta(hmm)',
      'MessageEnded(assistant stop)',
      'StepEnded(1)',
      'MessageStarted(user nudge 2)',
      'MessageEnded(user)',
      'StepStarted(2)',
      'ModelRequested',
      'MessageStarted(assistant)',
      'MessageDelta(Done.)',
      'MessageEnded(assistant stop)',
      'StepEnded(2)',
      'TurnEnded(completed)',
    ]);
    final nudges = h.events
        .whereType<MessageStarted>()
        .where((e) => e.origin != null)
        .toList();
    expect(nudges.map((e) => e.origin), [
      isA<LoopNudgeOrigin>()
          .having((o) => o.reason, 'reason', LoopNudgeReason.emptyResponse)
          .having((o) => o.attempt, 'attempt', 1),
      isA<LoopNudgeOrigin>().having((o) => o.attempt, 'attempt', 2),
    ]);
    expect(
      nudges.map(
        (e) => ((e.message as UserMessage).content.single as TextContent).text,
      ),
      [_nudge, _nudge],
    );
    // Пустые ответы остаются в транскрипте — это факт разговора.
    expect(added.whereType<AssistantMessage>(), hasLength(3));
    // Payload шага 2: без пустых assistant, с обеими подсказками.
    final payload = h.scripted!.requests[2].messages;
    expect(payload.whereType<AssistantMessage>(), isEmpty);
    expect(payload.whereType<UserMessage>(), hasLength(3));
    expect(
      h.logger.eventsOf('loop.empty_response').map((r) => r.fields['attempt']),
      [1, 2],
    );
  });

  test('(b) three empty answers end with a visible note', () async {
    var finalHookCalls = 0;
    final h = await LoopHarness.create(llm: script([_empty, _blank, _empty]));

    final added = await h.run(
      [user('go')],
      config: h.config(
        beforeFinalResponse: (message, turn) async {
          finalHookCalls++;
          return const Accept();
        },
      ),
    );

    expect(h.trace.sublist(h.trace.length - 5), [
      'StepEnded(2)',
      'MessageStarted(assistant note)',
      'MessageDelta(${_note(3)})',
      'MessageEnded(assistant stop)',
      'TurnEnded(completed)',
    ]);
    expect(h.events.whereType<StepStarted>(), hasLength(3));
    final note = added.last as AssistantMessage;
    expect((note.content.single as TextContent).text, _note(3));
    expect(note.usage, Usage.zero);
    final noteStarted = h.events.whereType<MessageStarted>().last;
    expect(
      noteStarted.origin,
      isA<LoopNoteOrigin>().having(
        (o) => o.reason,
        'reason',
        LoopNudgeReason.emptyResponse,
      ),
    );
    expect(finalHookCalls, 0);
    expect(h.logger.eventsOf('loop.empty_response.stopped'), hasLength(1));
  });

  test('(c) emptyResponseRetries: 0 — the note after the first one', () async {
    final h = await LoopHarness.create(llm: script([_empty]));

    final added = await h.run([
      user('go'),
    ], config: h.config(emptyResponseRetries: 0));

    expect(
      ((added.last as AssistantMessage).content.single as TextContent).text,
      _note(1),
    );
    expect(h.events.whereType<StepStarted>(), hasLength(1));
  });

  test('(d) the budget is stronger than a retry', () async {
    final h = await LoopHarness.create(llm: script([_empty, _empty]));

    await h.run([
      user('go'),
    ], config: h.config(budget: const TurnBudget(maxSteps: 2)));

    expect(h.trace.last, 'TurnEnded(completed steps)');
    expect(
      h.events.whereType<MessageStarted>().where(
        (e) => e.origin is LoopNoteOrigin,
      ),
      isEmpty,
    );
  });

  test('(e) a non-empty answer resets the streak', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('probe')],
      llm: script([
        _empty,
        {
          'reply': [
            {'text': 'checking'},
            {
              'toolCall': {'id': 'c1', 'name': 'probe', 'arguments': {}},
            },
          ],
        },
        _empty,
        textStep('Done.'),
      ]),
    );

    await h.run([user('go')]);

    final attempts = [
      for (final e in h.events.whereType<MessageStarted>())
        if (e.origin case LoopNudgeOrigin(:final attempt)) attempt,
    ];
    expect(attempts, [1, 1]);
    expect(h.trace.last, 'TurnEnded(completed)');
  });

  test('a length answer without calls is not empty', () async {
    final h = await LoopHarness.create(
      llm: script([
        {'reply': <Object?>[], 'stopReason': 'length'},
      ]),
    );

    await h.run([user('go')]);

    expect(h.trace.last, 'TurnEnded(maxTokens)');
    expect(h.events.whereType<StepStarted>(), hasLength(1));
  });
}
