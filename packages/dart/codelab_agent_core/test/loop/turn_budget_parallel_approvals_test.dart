// Красные тесты времени хода при параллельных одобрениях (change
// `fix-usage-pane-live-cards`, задача 2.1; design.md D6, Q3 (а), Q4 (а);
// agent-loop «Бюджет хода», сценарии «Параллельные одобрения вычитаются один
// раз» и «Ожидание одобрения не тратит время хода»; LOOP-12).
//
// Почему красные на текущем коде: `ApprovalWaitMeter.add` складывает
// пересекающиеся ожидания, `_progress` вычитает 120 с из 61 с настенного
// времени, и `active` уходит в минус (−59 с). Тесты идут через настоящую
// `PermissionPolicy` и gate на `FakeClock`, поэтому не зависят от API
// счётчика и компилируются сразу: падение — неверное значение `active`.
// Детерминизм: FakeClock, скриптованная модель, без сети и реальных пауз.
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/permissions/policy.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../permissions/fake_gate.dart';
import '../tools/fake_tools.dart';
import 'loop_harness.dart';

const _sec = Duration(seconds: 1);

/// Gate: ответ через время из [waits] по `toolCallId` на часах теста.
final class _StaggeredGate implements PermissionGate {
  _StaggeredGate(this.clock, this.waits);

  final FakeClock clock;
  final Map<String, Duration> waits;

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) async {
    await clock.delay(waits[req.toolCallId] ?? Duration.zero);
    return PermissionDecision.allowOnce;
  }
}

/// Инструмент уровня `write` (в режиме `standard` требует одобрения),
/// параллельный, занимает [work] на часах теста. Часы берутся лениво:
/// `LoopHarness` создаёт часы вместе с инструментами.
FakeTool _tool(
  String name,
  FakeClock Function() clock, {
  Duration work = _sec,
  ToolExecutionMode? mode = ToolExecutionMode.parallel,
}) => FakeTool(
  name,
  tier: ToolTier.write,
  executionMode: mode,
  onExecute: (args, ctx) async {
    await clock().delay(work);
    return const ToolExecutionResult([TextContent('ok')]);
  },
);

/// Запускает ход под настоящей политикой и двигает часы по [timeline]:
/// перед каждым сдвигом вычерпывается очередь событий, чтобы gate и
/// инструменты успели встать на таймеры.
Future<void> _drive(
  LoopHarness h,
  PermissionGate gate,
  TurnBudget budget,
  List<Duration> timeline,
) async {
  final policy = PermissionPolicy(
    mode: ModeId.standard,
    gate: gate,
    logger: h.logger,
  );
  final running = h.run(
    [user('go')],
    config: h.config(
      budget: budget,
      beforeToolCall: [policy.asHook(h.executor.registry.lookup)],
    ),
  );
  for (final step in timeline) {
    await pumpEventQueue();
    await h.clock.elapse(step);
  }
  await pumpEventQueue();
  await running;
}

List<Duration> _actives(LoopHarness h) => [
  for (final e in h.events.whereType<StepEnded>()) e.budget!.active,
];

Future<LoopHarness> _pair({
  required List<Map<String, Object?>> steps,
  List<FakeTool> Function(FakeClock Function() clock)? extra,
}) async {
  late LoopHarness h;
  h = await LoopHarness.create(
    tools: [_tool('a', () => h.clock), ...?extra?.call(() => h.clock)],
    llm: script(steps),
  );
  return h;
}

void main() {
  test('два одновременных одобрения по 60 с, шаг 61 с: active 1 с', () async {
    final h = await _pair(
      steps: [
        callStep([('c1', 'a', const {}), ('c2', 'a', const {})]),
        textStep('done'),
      ],
    );

    await _drive(
      h,
      _StaggeredGate(h.clock, {'c1': _sec * 60, 'c2': _sec * 60}),
      const TurnBudget(),
      [_sec * 60, _sec],
    );

    expect(_actives(h).first, _sec);
  });

  test('частично пересекающиеся ожидания 0–30 с и 0–60 с: вычитается 60 с, '
      'а не 90 с', () async {
    final h = await _pair(
      steps: [
        callStep([('c1', 'a', const {}), ('c2', 'a', const {})]),
        textStep('done'),
      ],
    );

    await _drive(
      h,
      _StaggeredGate(h.clock, {'c1': _sec * 30, 'c2': _sec * 60}),
      const TurnBudget(),
      [_sec * 30, _sec * 30, _sec],
    );

    // Шаг по часам 61 с; объединение ожиданий 60 с. Каждый вызов после
    // своего ответа работает 1 с, вызовы идут параллельно.
    expect(_actives(h).first, _sec);
  });

  test('время хода не убывает между границами шагов, maxDuration срабатывает '
      'вовремя', () async {
    final h = await _pair(
      steps: [
        callStep([('c1', 'a', const {}), ('c2', 'a', const {})]),
        callStep([('c3', 'slow', const {})]),
        textStep('done'),
      ],
      extra: (clock) => [
        FakeTool(
          'slow',
          onExecute: (args, ctx) async {
            await clock().delay(_sec * 12);
            return const ToolExecutionResult([TextContent('ok')]);
          },
        ),
      ],
    );

    await _drive(
      h,
      _StaggeredGate(h.clock, {'c1': _sec * 60, 'c2': _sec * 60}),
      const TurnBudget(maxDuration: Duration(seconds: 10)),
      [_sec * 60, _sec, _sec * 12],
    );

    final actives = _actives(h);
    // Шаг 1: 61 − 60 = 1 с; шаг 2: ещё 12 с без одобрений → 13 с > 10 с.
    expect(actives, [_sec, _sec * 13]);
    expect(actives[1], greaterThanOrEqualTo(actives[0]));
    expect(
      h.events.whereType<TurnEnded>().single.budgetExceeded,
      BudgetLimit.duration,
    );
    expect(h.events.whereType<StepStarted>(), hasLength(2));
  });

  test('непересекающиеся ожидания разных шагов вычитаются как сумма', () async {
    final h = await _pair(
      steps: [
        callStep([('c1', 'a', const {})]),
        callStep([('c2', 'a', const {})]),
        textStep('done'),
      ],
    );

    await _drive(
      h,
      _StaggeredGate(h.clock, {'c1': _sec * 30, 'c2': _sec * 20}),
      const TurnBudget(),
      [_sec * 30, _sec, _sec * 20, _sec],
    );

    // Шаги по 31 и 21 с, ожидания 30 и 20 с: по 1 с активного на шаг;
    // третий шаг (ответ текстом) времени не добавляет.
    expect(_actives(h), [_sec, _sec * 2, _sec * 2]);
  });

  test(
    'одно ожидание — прежнее значение, maxDuration не срабатывает',
    () async {
      final h = await _pair(
        steps: [
          callStep([('c1', 'a', const {})]),
          textStep('done'),
        ],
      );

      await _drive(
        h,
        FakeGate((_) => PermissionDecision.allowOnce, h.clock, _sec * 60),
        const TurnBudget(maxDuration: Duration(seconds: 10)),
        [_sec * 60, _sec],
      );

      expect(_actives(h).first, _sec);
      expect(h.events.whereType<TurnEnded>().single.budgetExceeded, isNull);
    },
  );
}
