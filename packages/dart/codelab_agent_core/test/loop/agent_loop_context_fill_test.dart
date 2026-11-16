import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/estimate.dart';
import 'package:codelab_agent_core/src/compaction/settings.dart';
import 'package:codelab_agent_core/src/loop/agent_loop.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import 'loop_harness.dart';

/// Заполнение контекста в `StepEnded` (задача 1.1 change `add-usage-extension`;
/// agent-loop «Заполнение контекста после шага»; design.md D5, D18 Т1–Т2,
/// Q10 (а), Q12 (а)).
///
/// Тесты красные, пока в ядре нет `StepEnded.context` (`ContextFill`) и полей
/// `AgentLoopConfig.contextEstimator` / `AgentLoopConfig.compaction`.
void main() {
  /// Шаг с usage, который служит якорем оценки (agent-loop, «Шаг с
  /// инструментом»: `input 41000, cacheRead 9000, output 600`).
  Map<String, Object?> readStep() => {
    ...callStep([
      ('c1', 'read', {'path': 'big.txt'}),
    ]),
    'usage': {'input': 41000, 'cacheRead': 9000, 'output': 600},
  };

  Future<LoopHarness> readHarness(List<Map<String, Object?>> steps) async {
    final h = await LoopHarness.create(tools: [ReadTool()], llm: script(steps));
    await h.env.writeText('/proj/big.txt', 'x' * 12000);
    return h;
  }

  List<StepEnded> stepEnds(LoopHarness h) =>
      h.events.whereType<StepEnded>().toList();

  group('used и window', () {
    test('шаг с read: used по якорю usage + оценка результата', () async {
      final h = await readHarness([readStep(), textStep('done')]);

      final out = await h.runTurn(
        [user('go')],
        config: h
            .config(contextWindowCap: 20000)
            .copyWith(contextEstimator: estimateLlmContext),
      );

      final result = out.added.whereType<ToolResultMessage>().single;
      final first = stepEnds(h).first.context!;
      // Якорь 41000 + 9000 + 600 и оценка только хвоста — результата read.
      expect(first.used, 50600 + estimateTokens([result]));
      // window — по текущей модели цикла с contextWindowCap (CMP-6).
      expect(first.window, effectiveContextWindow(testModel, cap: 20000));
      expect(first.window, 20000);
    });

    test('без contextWindowCap window — окно модели', () async {
      final h = await readHarness([readStep(), textStep('done')]);

      await h.runTurn([
        user('go'),
      ], config: h.config().copyWith(contextEstimator: estimateLlmContext));

      expect(stepEnds(h).first.context!.window, testModel.contextWindow);
    });

    test('без contextEstimator context == null, остальное прежнее', () async {
      final h = await readHarness([readStep(), textStep('done')]);

      await h.runTurn([user('go')]);

      expect(stepEnds(h), hasLength(2));
      expect(stepEnds(h).map((e) => e.context), everyElement(isNull));
      expect(stepEnds(h).first.result.results, hasLength(1));
    });

    test('шаг с ошибкой тоже несёт заполнение', () async {
      final h = await LoopHarness.create(
        llm: script([
          {
            'error': {'class': 'server', 'message': 'boom'},
          },
        ]),
      );

      await h.runTurn([
        user('go'),
      ], config: h.config().copyWith(contextEstimator: estimateLlmContext));

      final ended = stepEnds(h).single;
      expect(ended.context, isNotNull);
      expect(ended.context!.used, greaterThan(0));
      expect(ended.context!.window, testModel.contextWindow);
    });
  });

  group('compactAt', () {
    test(
      'compaction задан: порог afterTurn по правилу shouldCompact',
      () async {
        const overrides = CompactionOverrides(reserveTokens: 4000);
        final h = await readHarness([readStep(), textStep('done')]);

        await h.runTurn(
          [user('go')],
          config: h
              .config(contextWindowCap: 20000)
              .copyWith(
                contextEstimator: estimateLlmContext,
                compaction: (value: overrides),
              ),
        );

        final fill = stepEnds(h).first.context!;
        final expected = compactionThreshold(
          20000,
          CompactionSettings.forWindow(20000, overrides: overrides),
        );
        expect(fill.compactAt, expected);
        expect(fill.compactAt, inExclusiveRange(0, fill.window));
      },
    );

    test('copyWith(compaction: (value: null)) сбрасывает параметры сжатия, '
        'а без аргумента сохраняет (D18)', () async {
      final h = await readHarness([textStep('done')]);
      final withCompaction = h.config().copyWith(
        compaction: (value: const CompactionOverrides(reserveTokens: 4000)),
      );

      expect(withCompaction.copyWith().compaction, isNotNull);
      expect(
        withCompaction.copyWith(compaction: (value: null)).compaction,
        isNull,
      );
    });

    test(
      'compaction == null: compactAt == null (автосжатие выключено)',
      () async {
        final h = await readHarness([readStep(), textStep('done')]);

        await h.runTurn([
          user('go'),
        ], config: h.config().copyWith(contextEstimator: estimateLlmContext));

        final fill = stepEnds(h).first.context!;
        expect(fill.used, greaterThan(0));
        expect(fill.compactAt, isNull);
      },
    );

    test('только contextEstimator, без estimateTokens и emergencyCompact: '
        'used и window есть, compactAt null, проверки перед запросом нет '
        '(Q10 (а))', () async {
      // Окно крошечное: при включённой проверке перед запросом шаг получил
      // бы синтетический overflow; без estimateTokens запрос уходит как на
      // этапе 2 (agent-loop «Автосжатие выключено»).
      final tiny = modelWithWindow(256);
      final h = await LoopHarness.create(llm: script([textStep('hi')]));

      await h.runTurn(
        [user('go')],
        config: h.config().copyWith(
          model: tiny,
          contextEstimator: estimateLlmContext,
        ),
      );

      final fill = stepEnds(h).single.context!;
      expect(fill.window, 256);
      expect(fill.used, greaterThan(0));
      expect(fill.compactAt, isNull);
      expect(h.scripted!.requests, hasLength(1));
      expect(h.trace.where((e) => e.startsWith('AgentError')), isEmpty);
      // Оценщик проверки перед запросом не задан — оценка запроса нулевая.
      expect(h.events.whereType<ModelRequested>().single.estimatedTokens, 0);
    });
  });

  test('смена модели в prepareNextStep: window первого шага — прежняя '
      'модель, второго — новая (Q12 (а))', () async {
    final h = await readHarness([readStep(), textStep('done')]);

    await h.runTurn(
      [user('go')],
      config: h
          .config(
            prepareNextStep: (step) async =>
                StepUpdate(model: modelWithWindow(100000)),
          )
          .copyWith(contextEstimator: estimateLlmContext),
    );

    final ends = stepEnds(h);
    expect(ends, hasLength(2));
    expect(ends[0].context!.window, testModel.contextWindow);
    expect(ends[1].context!.window, 100000);
  });

  test('вычисление не меняет транскрипт, запросы и итог хода (D5: без '
      'обращения к провайдеру, журналу и бюджету)', () async {
    Future<(LoopHarness, TurnOutput)> run({required bool withEstimator}) async {
      final h = await readHarness([readStep(), textStep('done')]);
      final cfg = h.config(budget: const TurnBudget(maxSteps: 5));
      final out = await h.runTurn(
        [user('go')],
        config: withEstimator
            ? cfg.copyWith(
                contextEstimator: estimateLlmContext,
                compaction: (value: const CompactionOverrides()),
              )
            : cfg,
      );
      return (h, out);
    }

    final (plain, plainOut) = await run(withEstimator: false);
    final (filled, filledOut) = await run(withEstimator: true);

    expect(filled.trace, plain.trace);
    expect(filledOut.added.length, plainOut.added.length);
    expect(filled.scripted!.requests.length, plain.scripted!.requests.length);
    final a = plain.events.whereType<TurnEnded>().single;
    final b = filled.events.whereType<TurnEnded>().single;
    expect(b.usage, a.usage);
    expect(b.reason, a.reason);
    expect(b.budgetExceeded, a.budgetExceeded);
  });
}
