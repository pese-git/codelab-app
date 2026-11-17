// Красные тесты прогресса бюджета хода (change `add-desktop-usage-pane`,
// задача 2.1; design.md D8; agent-loop «Прогресс бюджета хода в событиях шага
// и хода»; C-13). Почему: клиент не может восстановить то, что проверяет
// цикл (дети, кэш, ожидание одобрения, модель без цен), поэтому прогресс
// считает сам цикл — той же функцией, что и `_budgetExceeded` (LOOP-12).
// Тесты детерминированы: FakeClock и скриптованная модель, без сети.
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import '../tools/fake_tools.dart';
import 'loop_harness.dart';

/// Шаг, который зовёт `probe` и сообщает расход токенов.
Map<String, Object?> _probeStep(
  String id, {
  int input = 0,
  int output = 0,
  int cacheRead = 0,
}) => {
  ...callStep([(id, 'probe', <String, Object?>{})]),
  'usage': {'input': input, 'output': output, 'cacheRead': cacheRead},
};

/// Модель с ценами: миллион входных токенов стоит 1 USD.
final _priced = ModelRef(
  provider: testModel.provider,
  id: testModel.id,
  api: testModel.api,
  baseUrl: testModel.baseUrl,
  contextWindow: testModel.contextWindow,
  maxOutputTokens: testModel.maxOutputTokens,
  cost: const ModelCost(input: 1, output: 1),
);

List<BudgetProgress?> _stepProgress(LoopHarness h) => [
  for (final e in h.events.whereType<StepEnded>()) e.budget,
];

void main() {
  test('шаги, токены input+output с детьми без кэша и лимиты', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('probe')],
      llm: script([
        _probeStep('c1', input: 1000, output: 200, cacheRead: 9000),
        textStep('done'),
      ]),
    );

    await h.run(
      [user('go')],
      config: h
          .config(budget: const TurnBudget(maxTokens: 200000))
          .copyWith(subagentUsage: () => const Usage(input: 300, output: 100)),
    );

    final first = _stepProgress(h).first;
    expect(first, isNotNull);
    expect(first!.steps, 1);
    expect(first.tokens, 1600);
    expect(first.limits.maxSteps, 50);
    expect(first.limits.maxTokens, 200000);
  });

  test('ожидание одобрения не входит во время хода', () async {
    late LoopHarness h;
    h = await LoopHarness.create(
      tools: [
        FakeTool(
          'probe',
          onExecute: (args, ctx) async {
            await h.clock.elapse(const Duration(seconds: 2));
            return const ToolExecutionResult([TextContent('ok')]);
          },
        ),
      ],
      llm: script([_probeStep('c1'), textStep('done')]),
    );
    Future<Block?> gate(
      ToolCall call,
      Map<String, Object?> args,
      ToolContext ctx,
    ) async {
      await h.clock.elapse(const Duration(seconds: 60));
      ctx.services.approvalWait.add(const Duration(seconds: 60));
      return null;
    }

    await h.run(
      [user('go')],
      config: h.config(
        budget: const TurnBudget(maxDuration: Duration(minutes: 10)),
        beforeToolCall: [gate],
      ),
    );

    expect(_stepProgress(h).first!.active, const Duration(seconds: 2));
    expect(h.events.whereType<TurnEnded>().single.budget!.active, isNotNull);
    expect(
      h.events.whereType<TurnEnded>().single.budget!.active,
      lessThan(const Duration(seconds: 60)),
    );
  });

  test('стоимость есть при ценах модели', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('probe')],
      llm: script([_probeStep('c1', input: 500000), textStep('done')]),
    );

    await h.run(
      [user('go')],
      config: h
          .config(budget: const TurnBudget(maxCost: 1))
          .copyWith(model: _priced),
    );

    final first = _stepProgress(h).first!;
    expect(first.cost, closeTo(0.5, 1e-9));
    expect(first.limits.maxCost, 1);
  });

  test('модель без цен: стоимость null, лимит есть, ход не стоп', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('probe')],
      llm: script([
        _probeStep('c1', input: 500000),
        _probeStep('c2', input: 500000),
        textStep('done'),
      ]),
    );

    await h.run([
      user('go'),
    ], config: h.config(budget: const TurnBudget(maxCost: 0.000001)));

    for (final progress in _stepProgress(h)) {
      expect(progress!.cost, isNull);
      expect(progress.limits.maxCost, 0.000001);
    }
    expect(h.events.whereType<TurnEnded>().single.budget!.cost, isNull);
    expect(h.trace.last, 'TurnEnded(completed)');
  });

  test(
    'итог хода: остановка по tokens, израсходованное не меньше лимита',
    () async {
      final h = await LoopHarness.create(
        tools: [FakeTool('probe')],
        llm: script([
          _probeStep('c1', input: 400, output: 100),
          _probeStep('c2', input: 400, output: 100),
          _probeStep('c3', input: 400, output: 100),
        ]),
      );

      await h.run([
        user('go'),
      ], config: h.config(budget: const TurnBudget(maxTokens: 1000)));

      final ended = h.events.whereType<TurnEnded>().single;
      expect(ended.budgetExceeded, BudgetLimit.tokens);
      expect(ended.budget, isNotNull);
      expect(ended.budget!.tokens, greaterThanOrEqualTo(1000));
      expect(ended.budget!.steps, 2);
      expect(ended.budget!.limits.maxTokens, 1000);
    },
  );

  test('итог хода включает usage детей', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('probe')],
      llm: script([
        {
          ...textStep('done'),
          'usage': {'input': 10, 'output': 5},
        },
      ]),
    );

    await h.run(
      [user('go')],
      config: h.config().copyWith(
        subagentUsage: () => const Usage(input: 300, output: 100),
      ),
    );

    expect(h.events.whereType<TurnEnded>().single.budget!.tokens, 415);
  });

  test('прогресс и проверка — одна функция: следующий шаг есть, '
      'пока прогресс ниже каждого лимита', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('probe')],
      llm: script([
        for (var i = 0; i < 6; i++) _probeStep('c$i', input: 300, output: 100),
      ]),
    );

    await h.run([
      user('go'),
    ], config: h.config(budget: const TurnBudget(maxTokens: 1000)));

    final steps = h.events.whereType<StepEnded>().toList();
    final started = h.events.whereType<StepStarted>().length;
    // Токены по шагам 400, 800, 1200: стоп ровно на первом >= 1000.
    expect([for (final s in steps) s.budget!.tokens], [400, 800, 1200]);
    expect(started, steps.length);
    for (final s in steps.take(steps.length - 1)) {
      expect(s.budget!.tokens, lessThan(1000));
    }
    expect(steps.last.budget!.tokens, greaterThanOrEqualTo(1000));
    expect(
      h.events.whereType<TurnEnded>().single.budgetExceeded,
      BudgetLimit.tokens,
    );
  });

  test('лимит шагов: прогресс достигает maxSteps на остановке', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('probe')],
      llm: script([_probeStep('c1'), _probeStep('c2'), _probeStep('c3')]),
    );

    await h.run([
      user('go'),
    ], config: h.config(budget: const TurnBudget(maxSteps: 2)));

    expect([for (final p in _stepProgress(h)) p!.steps], [1, 2]);
    final ended = h.events.whereType<TurnEnded>().single;
    expect(ended.budgetExceeded, BudgetLimit.steps);
    expect(ended.budget!.steps, 2);
  });

  // Расхождение с формулировкой задачи («без лимитов прогресса нет»): спека
  // и D8 требуют заполнять поле при любых лимитах, решение «слать или нет»
  // принимает адаптер (D7). Тест фиксирует спеку.
  test('без необязательных лимитов поле заполнено, лимиты null', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('probe')],
      llm: script([_probeStep('c1', input: 10, output: 5), textStep('done')]),
    );

    await h.run([user('go')]);

    final first = _stepProgress(h).first!;
    expect(first.limits.maxTokens, isNull);
    expect(first.limits.maxCost, isNull);
    expect(first.limits.maxDuration, isNull);
    expect(first.tokens, 15);
  });

  // Сбой модели на шаге N: StepEnded уже посчитал этот шаг, итог хода обязан
  // совпасть с ним (иначе клиент видит ход на шаг короче, чем UsageAccounting).
  test(
    'ошибка модели на шаге: TurnEnded.budget.steps == последний StepEnded',
    () async {
      final h = await LoopHarness.create(
        tools: [FakeTool('probe')],
        llm: script([
          _probeStep('c1'),
          {
            'error': {'class': 'server', 'message': 'boom'},
          },
        ]),
      );

      await h.run([user('go')]);

      final steps = [for (final p in _stepProgress(h)) p!.steps];
      expect(steps, [1, 2]);
      expect(h.events.whereType<TurnEnded>().single.budget!.steps, steps.last);
    },
  );
}
