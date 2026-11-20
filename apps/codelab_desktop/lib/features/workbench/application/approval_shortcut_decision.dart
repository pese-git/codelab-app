import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show PermissionOption, PermissionOptionId;
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show ApprovalRequestId;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_ui/codelab_ui.dart';

/// Задержка после появления цели, раньше которой сочетание не отвечает
/// (`fix-approval-focus`, D14, п. 2; решение пользователя Q8).
const approvalShortcutSettleDelay = Duration(milliseconds: 500);

/// Почему нажатие сочетания ответа не отправило ответ (D9, D14).
///
/// [wireName] — значение поля `reason` события журнала
/// `workbench.approval_shortcut_skipped`.
enum ApprovalShortcutSkipReason {
  noTarget('no_target'),
  noOption('no_option'),
  notVisible('not_visible'),
  settling('settling');

  const ApprovalShortcutSkipReason(this.wireName);

  final String wireName;
}

/// Результат нажатия сочетания ответа на одобрение: ответить или нет.
sealed class ApprovalShortcutDecision {
  const ApprovalShortcutDecision();
}

/// Ответить: запрос [approvalId] сессии [sessionId] вариантом [optionId].
///
/// Id и вариант взяты в момент нажатия (D14): другой запрос, появившийся
/// позже, этот ответ не получает.
final class ApprovalShortcutAnswer extends ApprovalShortcutDecision {
  const ApprovalShortcutAnswer({
    required this.sessionId,
    required this.approvalId,
    required this.optionId,
  });

  final String sessionId;
  final ApprovalRequestId approvalId;
  final PermissionOptionId optionId;
}

/// Не отвечать. [approvalId] — цель, если она есть; [show] — только показать
/// полосу цели (запрос показа без фокуса), как «Go to approval» панели Agents.
final class ApprovalShortcutSkipped extends ApprovalShortcutDecision {
  const ApprovalShortcutSkipped({
    required this.reason,
    this.sessionId,
    this.approvalId,
    this.show = false,
  });

  final ApprovalShortcutSkipReason reason;
  final String? sessionId;
  final ApprovalRequestId? approvalId;
  final bool show;
}

/// Момент, с которого одобрение стало активным (самым ранним ожидающим).
///
/// Почему: задержка после появления отсчитывается от первого снимка, где id
/// стал активным; от момента нажатия её отсчитать нельзя (D14, п. 2).
///
/// Для чего: хранит id активного одобрения и время его первого появления.
/// Новый активный id (другой запрос, новый запрос того же вызова) начинает
/// отсчёт заново; одобрение, которое трекер ни разу не видел, считается только
/// что появившимся.
///
/// Как использовать: владелец (`CodeLabShellCubit`) вызывает [observe] на
/// каждый снимок активной сессии, функция решения читает [ageOf]. Часы —
/// параметр, как у `WorkbenchUsagePane`: тесты подставляют свои.
final class ApprovalActivationTracker {
  ApprovalActivationTracker({required DateTime Function() clock})
    : _clock = clock;

  final DateTime Function() _clock;
  ApprovalRequestId? _activeId;
  String? _activeSession;
  DateTime? _since;

  /// Сообщает снимок активной сессии: активное одобрение — `focused` модели
  /// клиентского ядра. Не активное или нет снимка — отсчёт сбрасывается.
  void observe(SessionView? view) {
    PendingApprovalView? active;
    for (final approval in view?.pendingApprovals ?? const []) {
      if (approval.focused) {
        active = approval;
        break;
      }
    }
    if (active == null) {
      _activeId = null;
      _activeSession = null;
      _since = null;
      return;
    }
    if (_activeId != active.approvalId ||
        _activeSession != active.sessionId.value) {
      _activeId = active.approvalId;
      _activeSession = active.sessionId.value;
      _since = _clock();
    }
  }

  /// Сколько [approvalId] активно; `null` — не активно или не наблюдалось.
  Duration? ageOf(ApprovalRequestId approvalId) {
    final since = _since;
    if (since == null || _activeId != approvalId) {
      return null;
    }
    return _clock().difference(since);
  }
}

/// Решение по нажатию сочетания ответа вида [kind] (`fix-approval-focus`,
/// D14).
///
/// Почему в application: что можно ответить и когда, решает политика, а не
/// виджет (AGENTS.md §10). Кит сообщает только нажатие.
///
/// Для чего: хост вызывает функцию на каждое нажатие и выполняет результат.
/// Порядок проверок: цель (`no_target`), вариант по виду (`no_option`),
/// видимость полосы (`not_visible`), задержка после появления (`settling`).
/// Отказ, кроме `no_target`, только показывает полосу (`show`).
///
/// Как использовать: [view] — снимок активной сессии, [isVisible] — ручка
/// ленты, [activation] — трекер с [ApprovalActivationTracker.observe] на
/// каждый снимок. Функция ответа не отправляет.
ApprovalShortcutDecision approvalShortcutDecisionOf({
  required CodeLabConnectionStatus connectionStatus,
  required SessionView? view,
  required CodeLabApprovalOptionKind kind,
  required bool Function(String sessionId, String approvalId) isVisible,
  required ApprovalActivationTracker activation,
}) {
  if (connectionStatus != CodeLabConnectionStatus.connected ||
      view == null ||
      view.status == SessionStatusView.detached) {
    return const ApprovalShortcutSkipped(
      reason: ApprovalShortcutSkipReason.noTarget,
    );
  }
  PendingApprovalView? target;
  for (final approval in view.pendingApprovals) {
    if (approval.focused) {
      target = approval;
      break;
    }
  }
  if (target == null) {
    return const ApprovalShortcutSkipped(
      reason: ApprovalShortcutSkipReason.noTarget,
    );
  }
  final session = target.sessionId.value;
  ApprovalShortcutSkipped skipped(ApprovalShortcutSkipReason reason) =>
      ApprovalShortcutSkipped(
        reason: reason,
        sessionId: session,
        approvalId: target!.approvalId,
        show: true,
      );

  // Вариант выбирается по виду, а не по подписи агента (spec «Approval options
  // are rendered and bound to shortcuts by kind»).
  PermissionOption? option;
  for (final candidate in target.options) {
    if (candidate.kind.wireName == kind.wireName) {
      option = candidate;
      break;
    }
  }
  if (option == null) {
    return skipped(ApprovalShortcutSkipReason.noOption);
  }
  if (!isVisible(session, target.approvalId.value)) {
    return skipped(ApprovalShortcutSkipReason.notVisible);
  }
  final age = activation.ageOf(target.approvalId);
  if (age == null || age < approvalShortcutSettleDelay) {
    return skipped(ApprovalShortcutSkipReason.settling);
  }
  return ApprovalShortcutAnswer(
    sessionId: session,
    approvalId: target.approvalId,
    optionId: option.optionId,
  );
}
