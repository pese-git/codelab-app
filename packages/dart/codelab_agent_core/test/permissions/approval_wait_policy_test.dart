// Красные тесты открытия и закрытия ожидания одобрения в политике (change
// `fix-usage-pane-live-cards`, задача 2.1; design.md D6). Политика открывает
// ожидание перед `gate.request` и закрывает в `finally`, в том числе при
// отмене. Тесты читают счётчик через `totalAt(now)`, которого в текущем коде
// нет, — ошибка компиляции здесь ожидаема (см. approval_wait_meter_test.dart).
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'fake_gate.dart';
import 'policy_harness.dart';

void main() {
  test(
    'два одновременных одобрения политики — объединение, не сумма',
    () async {
      final p0 = await PolicyHarness.create();
      final clock = p0.h.clock;
      final gate = FakeGate(
        (_) => PermissionDecision.allowOnce,
        clock,
        const Duration(seconds: 60),
      );
      final p = await PolicyHarness.wrap(p0.h, gate: gate);

      final a = p.run('w', const {}, id: 'a');
      final b = p.run('w', const {}, id: 'b');
      await clock.elapse(const Duration(seconds: 60));
      await Future.wait([a, b]);

      expect(gate.requests, hasLength(2));
      expect(
        p.h.executor.services.approvalWait.totalAt(clock.now()),
        const Duration(seconds: 60),
      );
    },
  );

  test('отмена во время вопроса закрывает ожидание', () async {
    final p0 = await PolicyHarness.create();
    final clock = p0.h.clock;
    final cancel = CancelTokenSource();
    final gate = FakeGate(
      (_) {
        cancel.cancel();
        return PermissionDecision.cancelled;
      },
      clock,
      const Duration(seconds: 5),
    );
    final p = await PolicyHarness.wrap(p0.h, gate: gate);

    final running = p.run('w', const {}, cancel: cancel.token);
    await clock.elapse(const Duration(seconds: 5));
    await running;
    await clock.elapse(const Duration(seconds: 100));

    expect(
      p.h.executor.services.approvalWait.totalAt(clock.now()),
      const Duration(seconds: 5),
    );
  });

  test('исключение шлюза (не отмена) закрывает ожидание в finally', () async {
    final p0 = await PolicyHarness.create();
    final clock = p0.h.clock;
    final gate = FakeGate(
      (_) => throw StateError('gate failed'),
      clock,
      const Duration(seconds: 7),
    );
    final p = await PolicyHarness.wrap(p0.h, gate: gate);

    final running = p.run('w', const {});
    await clock.elapse(const Duration(seconds: 7));
    final outcome = await running;
    await clock.elapse(const Duration(seconds: 100));

    // Ошибка шлюза не глотается: исполнитель отдаёт failed.
    expect(outcome.outcome, ToolOutcome.failed);
    expect(
      p.h.executor.services.approvalWait.totalAt(clock.now()),
      const Duration(seconds: 7),
    );
  });
}
