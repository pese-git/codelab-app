import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

void main() {
  Future<List<String>> runBatch(List<Map<String, Object?>> args) async {
    final log = <String>[];
    final h = await LoopHarness.create(
      tools: [
        FakeTool(
          'step',
          sequentialWhen: 'lock',
          onExecute: (a, ctx) async {
            log.add('start ${ctx.toolCallId}');
            await Future<void>.delayed(Duration.zero);
            log.add('end ${ctx.toolCallId}');
            return const ToolExecutionResult([]);
          },
        ),
      ],
      llm: script([
        callStep([for (final (i, a) in args.indexed) ('c$i', 'step', a)]),
        textStep('ok'),
      ]),
    );
    await h.run([user('go')]);
    return log;
  }

  test('without the argument the batch is parallel', () async {
    expect(await runBatch([const {}, const {}]), [
      'start c0',
      'start c1',
      'end c0',
      'end c1',
    ]);
  });

  test('one sequential call makes the batch sequential (LOOP-4)', () async {
    expect(
      await runBatch([
        const {},
        const {'lock': true},
      ]),
      ['start c0', 'end c0', 'start c1', 'end c1'],
    );
  });

  test(
    'cancel in a sequential batch: the rest are cancelled before start',
    () async {
      final source = CancelTokenSource();
      final h = await LoopHarness.create(
        tools: [
          FakeTool(
            'step',
            executionMode: ToolExecutionMode.sequential,
            onExecute: (a, ctx) {
              source.cancel();
              return const ToolExecutionResult([TextContent('first')]);
            },
          ),
        ],
        llm: script([
          callStep([
            ('a', 'step', const {}),
            ('b', 'step', const {}),
            ('c', 'step', const {}),
          ]),
        ]),
      );

      final added = await h.run([user('go')], cancel: source.token);

      final results = {
        for (final m in added.whereType<ToolResultMessage>())
          m.toolCallId: (m.content.single as TextContent).text,
      };
      expect(results, {
        'a': 'first',
        'b': 'Tool call was cancelled before it started',
        'c': 'Tool call was cancelled before it started',
      });
      expect(h.trace.where((t) => t.startsWith('ToolCall')), [
        'ToolCallStarted(a)',
        'ToolCallFinished(a completed)',
        'ToolCallStarted(b)',
        'ToolCallFinished(b cancelled)',
        'ToolCallStarted(c)',
        'ToolCallFinished(c cancelled)',
      ]);
      expect(h.trace.last, 'TurnEnded(cancelled)');
    },
  );
}
