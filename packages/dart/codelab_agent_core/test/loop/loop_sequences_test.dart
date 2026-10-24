import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

void main() {
  test('text answer', () async {
    final h = await LoopHarness.create(llm: script([textStep('Hello')]));

    final added = await h.run([user('hi')]);

    expect(h.trace, [
      'TurnStarted',
      'MessageStarted(user)',
      'MessageEnded(user)',
      'StepStarted(0)',
      'ModelRequested',
      'MessageStarted(assistant)',
      'MessageDelta(Hello)',
      'MessageEnded(assistant stop)',
      'StepEnded(0)',
      'TurnEnded(completed)',
    ]);
    expect(added, hasLength(2));
    h.scripted!.verify();
  });

  test('one tool call, then text', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('read')],
      llm: script([
        callStep([
          ('call_1', 'read', {'path': 'a'}),
        ]),
        textStep('Done.'),
      ]),
    );

    final added = await h.run([user('go')]);

    expect(h.trace, [
      'TurnStarted',
      'MessageStarted(user)',
      'MessageEnded(user)',
      'StepStarted(0)',
      'ModelRequested',
      'MessageStarted(assistant)',
      'MessageEnded(assistant toolUse)',
      'ToolCallStarted(call_1)',
      'ToolCallFinished(call_1 completed)',
      'MessageStarted(toolResult call_1)',
      'MessageEnded(toolResult call_1)',
      'StepEnded(0)',
      'StepStarted(1)',
      'ModelRequested',
      'MessageStarted(assistant)',
      'MessageDelta(Done.)',
      'MessageEnded(assistant stop)',
      'StepEnded(1)',
      'TurnEnded(completed)',
    ]);
    expect(added.map((m) => m.runtimeType), [
      UserMessage,
      AssistantMessage,
      ToolResultMessage,
      AssistantMessage,
    ]);
    final turnEnded = h.events.last as TurnEnded;
    expect(turnEnded.usage, Usage.zero);
  });

  test(
    'two parallel calls: finished in completion order, results in call order',
    () async {
      final gates = {'c1': Completer<void>(), 'c2': Completer<void>()};
      final h = await LoopHarness.create(
        tools: [
          FakeTool(
            'wait',
            onExecute: (args, ctx) async {
              await gates[ctx.toolCallId]!.future;
              return ToolExecutionResult([
                TextContent('done ${ctx.toolCallId}'),
              ]);
            },
          ),
        ],
        llm: script([
          callStep([('c1', 'wait', const {}), ('c2', 'wait', const {})]),
          textStep('ok'),
        ]),
      );

      final turn = h.run([user('go')]);
      await pumpEventQueue();
      expect(
        h.trace,
        containsAllInOrder(['ToolCallStarted(c1)', 'ToolCallStarted(c2)']),
      );
      gates['c2']!.complete();
      await pumpEventQueue();
      gates['c1']!.complete();
      final added = await turn;

      expect(
        h.trace.where(
          (t) =>
              t.startsWith('ToolCall') ||
              t.startsWith('MessageStarted(toolResult'),
        ),
        [
          'ToolCallStarted(c1)',
          'ToolCallStarted(c2)',
          'ToolCallFinished(c2 completed)',
          'ToolCallFinished(c1 completed)',
          'MessageStarted(toolResult c1)',
          'MessageStarted(toolResult c2)',
        ],
      );
      expect(
        [for (final m in added.whereType<ToolResultMessage>()) m.toolCallId],
        ['c1', 'c2'],
      );
    },
  );

  test('length: calls of the cut answer are not executed (LOOP-5)', () async {
    final tool = FakeTool('write');
    final h = await LoopHarness.create(
      tools: [tool],
      llm: script([
        {
          ...callStep([
            ('call_1', 'write', {'path': 'a', 'content': 'par'}),
          ]),
          'stopReason': 'length',
        },
        textStep('Sorry.'),
      ]),
    );

    final added = await h.run([user('go')]);

    expect(tool.executed, isEmpty);
    final result = added.whereType<ToolResultMessage>().single;
    expect(result.isError, isTrue);
    expect(
      (result.content.single as TextContent).text,
      'Tool call arguments were truncated because the response hit the '
      'output token limit. Retry with smaller arguments.',
    );
    expect(h.trace.where((t) => t.startsWith('ToolCall')), isEmpty);
    expect(h.trace.last, 'TurnEnded(completed)');
  });

  test('length without calls ends the turn with maxTokens', () async {
    final h = await LoopHarness.create(
      llm: script([
        {...textStep('cut'), 'stopReason': 'length'},
      ]),
    );

    await h.run([user('go')]);

    expect(h.trace.last, 'TurnEnded(maxTokens)');
  });

  test('provider error: AgentError, StepEnded, TurnEnded(failed)', () async {
    final h = await LoopHarness.create(
      llm: script([
        {
          'error': {'class': 'server', 'message': 'boom'},
        },
      ]),
    );

    await h.run([user('go')]);

    expect(h.trace.sublist(3), [
      'StepStarted(0)',
      'ModelRequested',
      'MessageStarted(assistant)',
      'MessageEnded(assistant error)',
      'AgentError(provider server)',
      'StepEnded(0)',
      'TurnEnded(failed)',
    ]);
    final error = h.events.whereType<AgentError>().single;
    expect(error.message, 'boom');
    expect(error.retrying, isFalse);
  });

  test('a refusal ends the turn with refused', () async {
    final h = await LoopHarness.create(
      llm: script([
        {
          'error': {'class': 'terminalFinish', 'message': 'refused'},
        },
      ]),
    );

    await h.run([user('go')]);

    expect(h.trace.last, 'TurnEnded(refused)');
  });

  test(
    'cancel during the stream: TurnEnded(cancelled), no AgentError',
    () async {
      final h = await LoopHarness.create(
        llm: script([
          {'waitForCancel': true},
        ]),
      );
      final source = CancelTokenSource();

      final turn = h.run([user('go')], cancel: source.token);
      await pumpEventQueue();
      source.cancel();
      await turn;

      expect(h.trace.sublist(3), [
        'StepStarted(0)',
        'ModelRequested',
        'MessageStarted(assistant)',
        'MessageEnded(assistant aborted)',
        'StepEnded(0)',
        'TurnEnded(cancelled)',
      ]);
    },
  );

  test(
    'every ToolCallStarted has exactly one ToolCallFinished (LOOP-9)',
    () async {
      final h = await LoopHarness.create(
        tools: [FakeTool('read'), FakeTool('ls')],
        llm: script([
          callStep([
            ('a', 'read', const {}),
            ('b', 'missing', const {}),
            ('c', 'ls', const {}),
          ]),
          textStep('ok'),
        ]),
      );

      await h.run([user('go')]);

      final started = h.events.whereType<ToolCallStarted>().map(
        (e) => e.toolCallId,
      );
      final finished = h.events.whereType<ToolCallFinished>().map(
        (e) => e.toolCallId,
      );
      expect(started.toList()..sort(), ['a', 'b', 'c']);
      expect(finished.toList()..sort(), ['a', 'b', 'c']);
      expect(h.events.whereType<TurnEnded>(), hasLength(1));
      expect(h.events.last, isA<TurnEnded>());
    },
  );

  test(
    'the request carries the session cache key and the tool schemas',
    () async {
      final h = await LoopHarness.create(
        tools: [FakeTool('read'), FakeTool('edit')],
        llm: script([textStep('ok')]),
      );

      await h.run([user('go')]);

      final request = h.scripted!.requests.single;
      expect(request.cacheKey, 'sess-1');
      expect(request.systemPrompt, 'You are CodeLab.');
      expect([for (final t in request.tools) t.name], ['read', 'edit']);
    },
  );

  test('the max steps budget stops at a step boundary', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('read')],
      llm: script([
        callStep([('a', 'read', const {})]),
        callStep([('b', 'read', const {})]),
      ]),
    );

    await h.run([
      user('go'),
    ], config: h.config(budget: const TurnBudget(maxSteps: 2)));

    expect(h.trace.where((t) => t.startsWith('StepStarted')), [
      'StepStarted(0)',
      'StepStarted(1)',
    ]);
    expect(h.trace.last, 'TurnEnded(completed steps)');
  });
}
