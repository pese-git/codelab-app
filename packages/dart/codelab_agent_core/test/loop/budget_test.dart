import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import '../tools/fake_tools.dart';
import 'loop_harness.dart';

/// Шаг, который зовёт инструмент `probe` и сообщает о расходе токенов.
Map<String, Object?> _probeStep(String id, {int input = 0, int output = 0}) => {
  ...callStep([(id, 'probe', <String, Object?>{})]),
  'usage': {'input': input, 'output': output},
};

void main() {
  // Бюджет хода (LOOP-12): проверка только на границе шага.
  test('maxSteps: exactly two steps, budgetExceeded = steps', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('probe')],
      llm: script([_probeStep('c1'), _probeStep('c2')]),
    );

    await h.run([
      user('go'),
    ], config: h.config(budget: const TurnBudget(maxSteps: 2)));

    expect(h.events.whereType<StepStarted>(), hasLength(2));
    expect(h.trace.last, 'TurnEnded(completed steps)');
    // Оба вызова исполнены: инструмент не прерывается бюджетом.
    expect(h.events.whereType<ToolCallFinished>(), hasLength(2));
  });

  test('maxTokens: input + output of every step', () async {
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

    expect(h.events.whereType<StepStarted>(), hasLength(2));
    expect(h.trace.last, 'TurnEnded(completed tokens)');
  });

  test('maxCost: checked with known prices', () async {
    final priced = ModelRef(
      provider: testModel.provider,
      id: testModel.id,
      api: testModel.api,
      baseUrl: testModel.baseUrl,
      contextWindow: testModel.contextWindow,
      maxOutputTokens: testModel.maxOutputTokens,
      // Цена за миллион токенов: шаг на 500 000 входных стоит 0.5.
      cost: const ModelCost(input: 1, output: 1),
    );
    final h = await LoopHarness.create(
      tools: [FakeTool('probe')],
      llm: script([
        _probeStep('c1', input: 500000, output: 0),
        _probeStep('c2', input: 500000, output: 0),
        _probeStep('c3', input: 500000, output: 0),
      ]),
    );

    await h.run(
      [user('go')],
      config: h
          .config(budget: const TurnBudget(maxCost: 1))
          .copyWith(model: priced),
    );

    expect(h.events.whereType<StepStarted>(), hasLength(2));
    expect(h.trace.last, 'TurnEnded(completed cost)');
  });

  test('maxCost is not checked while prices are unknown', () async {
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

    expect(h.trace.last, 'TurnEnded(completed)');
  });

  test('maxDuration: time of the turn on the host clock', () async {
    late LoopHarness h;
    h = await LoopHarness.create(
      tools: [
        FakeTool(
          'probe',
          onExecute: (args, ctx) async {
            await h.clock.elapse(const Duration(seconds: 6));
            return const ToolExecutionResult([TextContent('ok')]);
          },
        ),
      ],
      llm: script([_probeStep('c1'), _probeStep('c2'), _probeStep('c3')]),
    );

    await h.run(
      [user('go')],
      config: h.config(
        budget: const TurnBudget(maxDuration: Duration(seconds: 10)),
      ),
    );

    expect(h.events.whereType<StepStarted>(), hasLength(2));
    expect(h.trace.last, 'TurnEnded(completed duration)');
  });

  test('waiting for approval is not the time of the turn (D6)', () async {
    late LoopHarness h;
    h = await LoopHarness.create(
      tools: [
        FakeTool(
          'probe',
          onExecute: (args, ctx) async {
            await h.clock.elapse(const Duration(seconds: 1));
            return const ToolExecutionResult([TextContent('ok')]);
          },
        ),
      ],
      llm: script([_probeStep('c1'), _probeStep('c2'), textStep('done')]),
    );
    // Хук ведёт себя как gate: человек думает 60 с, политика добавляет это
    // время в счётчик ожидания (§7.4).
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
        budget: const TurnBudget(maxDuration: Duration(seconds: 10)),
        beforeToolCall: [gate],
      ),
    );

    expect(h.trace.last, 'TurnEnded(completed)');
    expect(h.events.whereType<StepStarted>(), hasLength(3));
  });
}
