// Решение по нажатию глобального сочетания ответа на одобрение (задача 7.3
// change `fix-approval-focus`; design.md D14; spec agent-workbench-ui «Ответ
// на одобрение сочетанием с любого места рабочего места»).
//
// Решает application, а не виджет: цель — самое раннее ожидающее одобрение
// (`focused`), вариант — по виду, ответ только при видимой полосе и когда цель
// активна не меньше 500 мс. Часы внедряются, поэтому время не ждётся.
//
// Красный до задачи 7.5: `approvalShortcutDecisionOf` — заглушка, всегда
// `no_target`; `ApprovalActivationTracker` ничего не запоминает.
//
// «Неизвестный kind» (D14) в типах невозможен: `PermissionOptionKind` и
// `CodeLabApprovalOptionKind` закрыты четырьмя значениями. Случай «нет
// варианта этого вида» покрыт сценарием `no_option`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show ApprovalRequestId, ApprovalRiskLevel;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/approval_shortcut_decision.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Четыре стандартных варианта; [prefix] делает id вариантов разными у
/// разных одобрений, чтобы видеть, чьим вариантом отвечено.
List<PermissionOption> _options(String prefix) => [
  PermissionOption(
    optionId: PermissionOptionId('$prefix-allow-once'),
    name: 'Allow once',
    kind: PermissionOptionKind.allowOnce,
  ),
  PermissionOption(
    optionId: PermissionOptionId('$prefix-allow-always'),
    name: 'Always allow',
    kind: PermissionOptionKind.allowAlways,
  ),
  PermissionOption(
    optionId: PermissionOptionId('$prefix-reject-once'),
    name: 'Reject once',
    kind: PermissionOptionKind.rejectOnce,
  ),
  PermissionOption(
    optionId: PermissionOptionId('$prefix-reject-always'),
    name: 'Always reject',
    kind: PermissionOptionKind.rejectAlways,
  ),
];

PendingApprovalView _pending(
  String id, {
  bool focused = true,
  List<PermissionOption>? options,
  String session = 's1',
}) => PendingApprovalView(
  approvalId: ApprovalRequestId(id),
  sessionId: SessionId(session),
  risk: ApprovalRiskLevel.shell,
  options: options ?? _options(id),
  focused: focused,
);

SessionView _view(
  List<PendingApprovalView> pending, {
  SessionStatusView status = SessionStatusView.running,
}) => SessionView(revision: 1, status: status, pendingApprovals: pending);

void main() {
  const connected = CodeLabConnectionStatus.connected;
  var now = DateTime.utc(2026, 11, 20, 12);
  late ApprovalActivationTracker tracker;

  setUp(() {
    now = DateTime.utc(2026, 11, 20, 12);
    tracker = ApprovalActivationTracker(clock: () => now);
  });

  void advance(int ms) => now = now.add(Duration(milliseconds: ms));

  ApprovalShortcutDecision decide(
    SessionView? view, {
    CodeLabApprovalOptionKind kind = CodeLabApprovalOptionKind.allowOnce,
    CodeLabConnectionStatus status = connected,
    bool visible = true,
    void Function(String session, String approval)? onAsked,
  }) => approvalShortcutDecisionOf(
    connectionStatus: status,
    view: view,
    kind: kind,
    isVisible: (session, approval) {
      onAsked?.call(session, approval);
      return visible;
    },
    activation: tracker,
  );

  ApprovalShortcutSkipped skipped(ApprovalShortcutDecision d) =>
      d as ApprovalShortcutSkipped;

  ApprovalShortcutAnswer answered(ApprovalShortcutDecision d) =>
      d as ApprovalShortcutAnswer;

  group('нет цели — no_target, ответа и показа нет', () {
    test('нет ожидающего одобрения', () {
      final d = skipped(decide(_view(const [])));
      expect(d.reason, ApprovalShortcutSkipReason.noTarget);
      expect(d.show, isFalse);
    });

    test('нет снимка активной сессии', () {
      final d = skipped(decide(null));
      expect(d.reason, ApprovalShortcutSkipReason.noTarget);
      expect(d.show, isFalse);
    });

    test('соединение не Connected', () {
      final view = _view([_pending('A')]);
      tracker.observe(view);
      advance(1000);
      for (final status in CodeLabConnectionStatus.values) {
        if (status == connected) continue;
        final d = skipped(decide(view, status: status));
        expect(
          d.reason,
          ApprovalShortcutSkipReason.noTarget,
          reason: '$status',
        );
        expect(d.show, isFalse, reason: '$status');
      }
    });

    test('сессия detached', () {
      final view = _view([_pending('A')], status: SessionStatusView.detached);
      tracker.observe(view);
      advance(1000);
      final d = skipped(decide(view));
      expect(d.reason, ApprovalShortcutSkipReason.noTarget);
      expect(d.show, isFalse);
    });
  });

  group('нет варианта этого вида — no_option', () {
    test('агент предложил только allow_once и reject_once', () {
      final view = _view([
        _pending(
          'A',
          options: _options('A').where((o) {
            return o.kind == PermissionOptionKind.allowOnce ||
                o.kind == PermissionOptionKind.rejectOnce;
          }).toList(),
        ),
      ]);
      tracker.observe(view);
      advance(1000);

      for (final kind in const [
        CodeLabApprovalOptionKind.allowAlways,
        CodeLabApprovalOptionKind.rejectAlways,
      ]) {
        final d = skipped(decide(view, kind: kind));
        expect(d.reason, ApprovalShortcutSkipReason.noOption, reason: '$kind');
        expect(d.approvalId, const ApprovalRequestId('A'), reason: '$kind');
      }
    });

    test('пустой список вариантов', () {
      final view = _view([_pending('A', options: const [])]);
      tracker.observe(view);
      advance(1000);
      expect(skipped(decide(view)).reason, ApprovalShortcutSkipReason.noOption);
    });

    test('нажатие только показывает полосу цели, ответа нет (D14)', () {
      final view = _view([
        _pending('A', options: [_options('A').first]),
      ]);
      tracker.observe(view);
      advance(1000);
      final d = skipped(
        decide(view, kind: CodeLabApprovalOptionKind.rejectOnce),
      );
      expect(d.reason, ApprovalShortcutSkipReason.noOption);
      expect(d.show, isTrue);
    });
  });

  group('полоса не видна — not_visible', () {
    test(
      'показать без ответа; следующее нажатие при видимой полосе отвечает',
      () {
        final view = _view([_pending('A')]);
        tracker.observe(view);
        advance(1000);

        final first = skipped(decide(view, visible: false));
        expect(first.reason, ApprovalShortcutSkipReason.notVisible);
        expect(first.show, isTrue);
        expect(first.approvalId, const ApprovalRequestId('A'));

        expect(decide(view), isA<ApprovalShortcutAnswer>());
      },
    );

    test('видимость спрашивается у полосы цели: сессия и id запроса', () {
      final view = _view([_pending('A', session: 's7')]);
      tracker.observe(view);
      advance(1000);
      final asked = <(String, String)>[];

      decide(view, onAsked: (s, a) => asked.add((s, a)));

      expect(asked, [('s7', 'A')]);
    });

    test('видимость другого (не самого раннего) одобрения не нужна', () {
      final view = _view([_pending('B', focused: false), _pending('A')]);
      tracker.observe(view);
      advance(1000);
      final asked = <String>[];

      decide(view, onAsked: (_, a) => asked.add(a));

      expect(asked, ['A']);
    });
  });

  group('задержка после появления — settling', () {
    test('цель активна меньше 500 мс: показать без ответа', () {
      final view = _view([_pending('A')]);
      tracker.observe(view);

      for (final ms in const [0, 200, 499]) {
        now = DateTime.utc(2026, 11, 20, 12).add(Duration(milliseconds: ms));
        final d = skipped(decide(view));
        expect(d.reason, ApprovalShortcutSkipReason.settling, reason: '$ms мс');
        expect(d.show, isTrue, reason: '$ms мс');
        expect(d.approvalId, const ApprovalRequestId('A'), reason: '$ms мс');
      }
    });

    test('ровно 500 мс и больше: ответ', () {
      final view = _view([_pending('A')]);
      tracker.observe(view);

      advance(500);
      expect(decide(view), isA<ApprovalShortcutAnswer>(), reason: '500 мс');
      advance(1);
      expect(decide(view), isA<ApprovalShortcutAnswer>(), reason: '501 мс');
    });

    test(
      'цель, которую никто не наблюдал, считается только что появившейся',
      () {
        final view = _view([_pending('A')]);
        advance(10000);

        final d = skipped(decide(view));
        expect(d.reason, ApprovalShortcutSkipReason.settling);
      },
    );

    test('повторный снимок той же цели не сбрасывает отсчёт', () {
      final view = _view([_pending('A')]);
      tracker.observe(view);
      advance(300);
      tracker.observe(_view([_pending('A')]));
      advance(200);

      expect(decide(view), isA<ApprovalShortcutAnswer>());
    });

    test('отсчёт начинается заново, когда активным становится другой id', () {
      final viewA = _view([_pending('A'), _pending('B', focused: false)]);
      tracker.observe(viewA);
      advance(1000);
      expect(answered(decide(viewA)).approvalId, const ApprovalRequestId('A'));

      // Ответили на A: активным стал B. Двойное нажатие через 100 мс его
      // не получает.
      final viewB = _view([_pending('B')]);
      tracker.observe(viewB);
      advance(100);
      final early = skipped(decide(viewB));
      expect(early.reason, ApprovalShortcutSkipReason.settling);
      expect(early.approvalId, const ApprovalRequestId('B'));

      advance(400);
      expect(answered(decide(viewB)).approvalId, const ApprovalRequestId('B'));
    });

    test('новый запрос того же вызова — новый id, новый отсчёт', () {
      final first = _view([_pending('A')]);
      tracker.observe(first);
      advance(1000);

      final second = _view([_pending('A2')]);
      tracker.observe(second);
      advance(50);

      expect(
        skipped(decide(second)).reason,
        ApprovalShortcutSkipReason.settling,
      );
    });
  });

  group('ответ', () {
    test('несёт id запроса, сессию и optionId варианта по виду', () {
      final view = _view([_pending('A', session: 's7')]);
      tracker.observe(view);
      advance(1000);

      final expected = {
        CodeLabApprovalOptionKind.allowOnce: 'A-allow-once',
        CodeLabApprovalOptionKind.allowAlways: 'A-allow-always',
        CodeLabApprovalOptionKind.rejectOnce: 'A-reject-once',
        CodeLabApprovalOptionKind.rejectAlways: 'A-reject-always',
      };
      for (final MapEntry(key: kind, value: optionId) in expected.entries) {
        final a = answered(decide(view, kind: kind));
        expect(a.approvalId, const ApprovalRequestId('A'), reason: '$kind');
        expect(a.sessionId, 's7', reason: '$kind');
        expect(a.optionId, PermissionOptionId(optionId), reason: '$kind');
      }
    });

    test('вариант выбирается по виду, а не по подписи агента', () {
      final view = _view([
        _pending(
          'A',
          options: const [
            PermissionOption(
              optionId: PermissionOptionId('x1'),
              name: 'Reject',
              kind: PermissionOptionKind.allowOnce,
            ),
            PermissionOption(
              optionId: PermissionOptionId('x2'),
              name: 'Allow',
              kind: PermissionOptionKind.rejectOnce,
            ),
          ],
        ),
      ]);
      tracker.observe(view);
      advance(1000);

      expect(answered(decide(view)).optionId, const PermissionOptionId('x1'));
      expect(
        answered(
          decide(view, kind: CodeLabApprovalOptionKind.rejectOnce),
        ).optionId,
        const PermissionOptionId('x2'),
      );
    });

    test('цель — самое раннее одобрение (focused), а не порядок списка', () {
      final view = _view([_pending('B', focused: false), _pending('A')]);
      tracker.observe(view);
      advance(1000);

      expect(answered(decide(view)).approvalId, const ApprovalRequestId('A'));
    });

    test('другое одобрение, ставшее активным после, ответа не получает', () {
      final viewA = _view([_pending('A')]);
      tracker.observe(viewA);
      advance(1000);
      final decision = answered(decide(viewA));

      // Решение уже принято для A; B, появившееся потом, его не меняет.
      tracker.observe(_view([_pending('B')]));
      expect(decision.approvalId, const ApprovalRequestId('A'));
      expect(decision.optionId, const PermissionOptionId('A-allow-once'));
    });
  });
}
