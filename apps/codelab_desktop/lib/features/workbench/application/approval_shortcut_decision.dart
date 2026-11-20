import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show PermissionOptionId;
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
/// ЗАГЛУШКА красных тестов 7.3: [observe] ничего не запоминает, [ageOf] всегда
/// `null`; реализация — 7.5.
final class ApprovalActivationTracker {
  ApprovalActivationTracker({required DateTime Function() clock})
    : _clock = clock;

  // ignore: unused_field
  final DateTime Function() _clock;

  /// Сообщает снимок активной сессии; вызывается при каждом изменении.
  void observe(SessionView? view) {}

  /// Сколько [approvalId] активно; `null` — не активно или не наблюдалось.
  Duration? ageOf(ApprovalRequestId approvalId) => null;
}

/// Решение по нажатию сочетания ответа вида [kind] (`fix-approval-focus`,
/// D14).
///
/// Почему в application: что можно ответить и когда, решает политика, а не
/// виджет (AGENTS.md §10). Кит сообщает только нажатие.
///
/// Для чего: хост вызывает функцию на каждое нажатие и выполняет результат.
///
/// ЗАГЛУШКА красных тестов 7.3: всегда `no_target`; реализация — 7.5.
ApprovalShortcutDecision approvalShortcutDecisionOf({
  required CodeLabConnectionStatus connectionStatus,
  required SessionView? view,
  required CodeLabApprovalOptionKind kind,
  required bool Function(String sessionId, String approvalId) isVisible,
  required ApprovalActivationTracker activation,
}) =>
    const ApprovalShortcutSkipped(reason: ApprovalShortcutSkipReason.noTarget);
