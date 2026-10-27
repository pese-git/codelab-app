import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

import '../cli_args.dart';

/// Почему политика приняла решение.
enum ApprovalReason {
  /// Обычное решение политики `--approve`.
  policy,

  /// Запрос помечен агентом критичным: `allow-all` его не разрешает.
  critical,

  /// Подходящего варианта нет: ход отменяется, запрос получает `cancelled`.
  cancelled,
}

/// Решение headless-политики по одному запросу одобрения.
///
/// [optionId] `null` — ни одного варианта `reject_*` агент не предложил, и
/// раннер отменяет ход: ожидающий запрос получает исход `cancelled` (ACP).
final class ApprovalDecision {
  const ApprovalDecision(this.optionId, this.outcome, this.reason);

  final PermissionOptionId? optionId;

  /// Вид выбранного варианта (`allow_once`, `reject_once`, …) или
  /// `cancelled` — для строки stderr.
  final String outcome;
  final ApprovalReason reason;
}

/// Решает запрос одобрения политикой `--approve` без вопросов пользователю.
///
/// Почему: в headless нет человека, а stdin занят промптом; решение должно
/// быть детерминированным и видимым (spec cli-headless «Политика одобрений
/// headless»; design.md change `add-codelab-cli`, D9). Допустимый вариант —
/// только из предложенных агентом.
///
/// Как использовать: раннер вызывает функцию на каждый новый
/// `PendingApprovalView`; [kind] — вид вызова инструмента из транскрипта
/// (`null` — неизвестен, считается не-чтением).
ApprovalDecision decideApproval(
  PendingApprovalView approval,
  ApprovePolicy policy, {
  required ToolKind? kind,
}) {
  final (wanted, reason) = switch (policy) {
    ApprovePolicy.reject => (
      PermissionOptionKind.rejectOnce,
      ApprovalReason.policy,
    ),
    ApprovePolicy.readOnly => (
      kind == ToolKind.read
          ? PermissionOptionKind.allowOnce
          : PermissionOptionKind.rejectOnce,
      ApprovalReason.policy,
    ),
    ApprovePolicy.allowAll when approval.critical => (
      PermissionOptionKind.rejectOnce,
      ApprovalReason.critical,
    ),
    ApprovePolicy.allowAll => (
      PermissionOptionKind.allowOnce,
      ApprovalReason.policy,
    ),
  };
  final option =
      approval.options.where((o) => o.kind == wanted).firstOrNull ??
      approval.options.where(_isReject).firstOrNull;
  if (option == null) {
    return const ApprovalDecision(null, 'cancelled', ApprovalReason.cancelled);
  }
  return ApprovalDecision(option.optionId, option.kind.wireName, reason);
}

/// Строка stderr о решении: одна на каждый запрос (SJ-11 для текстового
/// режима).
String describeApproval(String title, ApprovalDecision decision) =>
    'codelab: permission "$title": ${decision.outcome} '
    '(${decision.reason.name})';

bool _isReject(PermissionOption option) =>
    option.kind == PermissionOptionKind.rejectOnce ||
    option.kind == PermissionOptionKind.rejectAlways;
