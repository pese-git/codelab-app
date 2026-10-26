import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcript_item.freezed.dart';

/// Элемент транскрипта сессии для отображения.
///
/// Почему: UI и CLI показывают один и тот же транскрипт, а сырые
/// `session/update` и read-модель ядра клиента — протокольные данные, не
/// представление (`AGENTS.md` §7). Проекция в элементы — логика kit
/// (spec acp-client-kit «Инкрементальная проекция транскрипта»).
///
/// Для чего: `SessionView.transcript`. Порядок — порядок ходов сессии; в
/// ходе — промпт, затем элементы по порядку обновлений агента, затем
/// одобрения вызовов, о которых агент не объявлял, и итоговое уведомление.
///
/// Как использовать: хост отображает элементы через `switch`; [id]
/// стабилен, пока элемент живёт (растущий текст сохраняет id), и подходит
/// как ключ виджета.
@freezed
sealed class TranscriptItem with _$TranscriptItem {
  const TranscriptItem._();

  /// Текст промпта пользователя.
  const factory TranscriptItem.user({
    required String id,
    required String text,
  }) = UserItem;

  /// Сплошной отрезок `agent_message_chunk` подряд.
  const factory TranscriptItem.agentText({
    required String id,
    required String text,
  }) = AgentTextItem;

  /// Сплошной отрезок `agent_thought_chunk` подряд.
  const factory TranscriptItem.thought({
    required String id,
    required String text,
  }) = ThoughtItem;

  /// Вызов инструмента; [details] — `null`, если ядро не знает записи вызова.
  const factory TranscriptItem.toolCall({
    required String id,
    required ToolCallId toolCallId,
    required String title,
    ToolCallView? details,
    ApprovalStateView? approval,
  }) = ToolCallItem;

  /// Итог хода, который не виден из обновлений агента.
  const factory TranscriptItem.notice({
    required String id,
    required NoticeKind kind,
    required String text,
  }) = NoticeItem;
}

/// Состояние вызова инструмента в элементе транскрипта.
@freezed
abstract class ToolCallView with _$ToolCallView {
  const factory ToolCallView({
    required ToolKind kind,
    required ToolCallStatusView status,

    /// Команда из `rawInput.command`, если агент её прислал.
    String? command,
  }) = _ToolCallView;
}

/// Статус вызова для отображения.
///
/// [cancelled] — вызов не закончился к `session/cancel` клиента: в ACP такого
/// статуса нет, ядро хранит его как `failed` с флагом `cancelledByClient`
/// (fix-prompt-cancel-tool-calls/design.md, D3).
enum ToolCallStatusView { queued, running, succeeded, failed, cancelled }

/// Одобрение вызова инструмента, встроенное в его элемент.
@freezed
sealed class ApprovalStateView with _$ApprovalStateView {
  const ApprovalStateView._();

  /// Ждёт ответа пользователя. [focused] — самое раннее ожидающее одобрение
  /// хода: только оно отвечает на клавиши одобрения
  /// (embed-approval-in-thread/design.md, Decision 6).
  const factory ApprovalStateView.pending({
    required ApprovalRequestId approvalId,
    required SessionId sessionId,
    required ApprovalRiskLevel risk,
    String? command,
    Map<String, Object?>? rawInput,
    required List<PermissionOption> options,
    required bool focused,
  }) = PendingApprovalView;

  /// Решено; [label] — имя выбранного варианта, `Cancelled` или `Resolved`.
  const factory ApprovalStateView.resolved({required String label}) =
      ResolvedApprovalView;
}

/// Вид итогового уведомления хода.
enum NoticeKind {
  /// Ход сорвался; текст — `Failed to send prompt: <причина>`.
  error,

  /// Ход завершился без вывода агента; текст — `Completed with stopReason …`.
  emptyTurn,
}
