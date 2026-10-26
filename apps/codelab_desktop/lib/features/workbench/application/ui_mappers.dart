/// Отображение представлений `codelab_client_core` и ядра клиента в модели `codelab_ui`.
///
/// Почему: `codelab_ui` не зависит ни от протокола, ни от kit (`AGENTS.md` §5), а
/// после разделения `CodeLabShellCubit` (change `extract-acp-client-kit`,
/// design D10) одни и те же модели строят несколько Cubit-ов.
///
/// Для чего: единственное место, где `SessionView`, `ConnectionView` и
/// `AcpSession` превращаются в `AcpTranscriptEntry`, `AcpSessionListItem`,
/// `AcpConfigOption` и другие модели виджетов. Логики клиента здесь нет —
/// только отображение; значения совпадают с прежними значениями Cubit.
///
/// Как использовать: чистые функции без состояния; Cubit-ы рабочего места
/// вызывают их при каждом изменении своей части состояния.
library;

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentIcons;

/// Модели инспектора — модели kit (`InspectorProjection`, design D9);
/// прежние имена остаются для виджетов и тестов.
typedef CodeLabInspectorCategory = InspectorCategory;
typedef CodeLabInspectorEntry = InspectorEntry;
typedef CodeLabInspectorDetail = InspectorDetail;

/// Выбор варианта ожидающего одобрения [approval] в ленте.
///
/// Обработчик получает само одобрение, а не «текущее» одобрение окна: так
/// поздний нажатый вариант не решит чужой вызов (PERM-003,
/// `docs/architecture/permissions.md`).
typedef ApprovalOptionChosen =
    void Function(PendingApprovalView approval, String optionId);

AcpConnectionStatus connectionStatusOf(ConnectionView connection) =>
    switch (connection) {
      Disconnected() => AcpConnectionStatus.disconnected,
      Connecting() => AcpConnectionStatus.connecting,
      Reconnecting() => AcpConnectionStatus.reconnecting,
      Connected() => AcpConnectionStatus.connected,
      ConnectionFailed() => AcpConnectionStatus.failed,
    };

/// Строка сайдбара: заголовок сессии или `Session <id>`, подзаголовок — `cwd`.
AcpSessionListItem sessionListItemOf(AcpSession session) {
  final title = session.title?.trim().isNotEmpty == true
      ? session.title!.trim()
      : 'Session ${session.id.value}';
  return AcpSessionListItem(
    id: session.id.value,
    title: title,
    status: _sessionStatusOf(session.status),
    subtitle: session.cwd,
    updatedLabel: 'Active',
  );
}

AcpSessionStatus _sessionStatusOf(SessionLifecycleStatus status) =>
    switch (status) {
      SessionLifecycleStatus.idle ||
      SessionLifecycleStatus.active => AcpSessionStatus.idle,
      SessionLifecycleStatus.runningTurn ||
      SessionLifecycleStatus.cancellingTurn => AcpSessionStatus.running,
      SessionLifecycleStatus.awaitingApproval =>
        AcpSessionStatus.awaitingApproval,
      SessionLifecycleStatus.failed => AcpSessionStatus.failed,
    };

/// Транскрипт kit (`TranscriptProjector`, design D5) в записи ленты.
///
/// Id записей — позиционные (`prompt-N`, `agent-N`, `tool-N`,
/// `prompt-error-N`), как до переноса проекции в kit: на них опираются
/// виджеты и тесты. [approvalsEnabled] гасит кнопки одобрения, пока ответ на
/// другое одобрение в полёте.
List<AcpTranscriptEntry> transcriptEntriesOf(
  List<TranscriptItem> transcript, {
  required String cwd,
  required bool approvalsEnabled,
  required ApprovalOptionChosen onApprovalSelected,
}) => [
  for (final (index, item) in transcript.indexed)
    switch (item) {
      UserItem(:final text) => AcpTranscriptEntry(
        id: 'prompt-${index + 1}',
        kind: AcpTranscriptEntryKind.user,
        title: 'You',
        body: text,
      ),
      AgentTextItem(:final text) ||
      ThoughtItem(:final text) ||
      NoticeItem(kind: NoticeKind.emptyTurn, :final text) => AcpTranscriptEntry(
        id: 'agent-${index + 1}',
        kind: AcpTranscriptEntryKind.agent,
        title: 'Agent',
        body: text,
      ),
      NoticeItem(kind: NoticeKind.error, :final text) => AcpTranscriptEntry(
        id: 'prompt-error-${index + 1}',
        kind: AcpTranscriptEntryKind.diagnostic,
        title: 'Prompt failed',
        body: text,
      ),
      ToolCallItem(:final title, :final details, :final approval) =>
        AcpTranscriptEntry(
          id: 'tool-${index + 1}',
          kind: AcpTranscriptEntryKind.toolCall,
          title: title,
          toolCall: details == null
              ? null
              : AcpToolCallSummary(
                  name: details.kind.wireName,
                  status: _toolCallStatusOf(details.status),
                  detail: details.command,
                ),
          approval: _transcriptApprovalOf(
            approval,
            cwd: cwd,
            enabled: approvalsEnabled,
            onSelected: onApprovalSelected,
          ),
        ),
    },
];

/// Одобрение встроено в запись вызова: ожидающее — интерактивное,
/// решённое — компактная отметка (embed-approval-in-thread/design.md,
/// Decisions 1–3).
AcpTranscriptApproval? _transcriptApprovalOf(
  ApprovalStateView? approval, {
  required String cwd,
  required bool enabled,
  required ApprovalOptionChosen onSelected,
}) => switch (approval) {
  null => null,
  ResolvedApprovalView(:final label) => AcpTranscriptApproval.resolved(
    label: label,
  ),
  PendingApprovalView() => AcpTranscriptApproval.pending(
    risk: _approvalRiskOf(approval.risk),
    command: approval.command,
    cwd: cwd,
    rawInput: formatRedactedJson(approval.rawInput),
    options: approval.options.map(_approvalOptionOf).toList(),
    enabled: enabled,
    shortcutsEnabled: approval.focused,
    onOptionSelected: (optionId) => onSelected(approval, optionId),
  ),
};

AcpApprovalRisk _approvalRiskOf(ApprovalRiskLevel risk) => switch (risk) {
  ApprovalRiskLevel.readOnly => AcpApprovalRisk.readOnly,
  ApprovalRiskLevel.localWrite => AcpApprovalRisk.localWrite,
  ApprovalRiskLevel.network => AcpApprovalRisk.network,
  ApprovalRiskLevel.shell => AcpApprovalRisk.shell,
  ApprovalRiskLevel.destructive => AcpApprovalRisk.destructive,
};

AcpApprovalOption _approvalOptionOf(PermissionOption option) =>
    AcpApprovalOption(
      id: option.optionId.value,
      label: option.name,
      kind: switch (option.kind) {
        PermissionOptionKind.allowOnce => AcpApprovalOptionKind.allowOnce,
        PermissionOptionKind.allowAlways => AcpApprovalOptionKind.allowAlways,
        PermissionOptionKind.rejectOnce => AcpApprovalOptionKind.rejectOnce,
        PermissionOptionKind.rejectAlways => AcpApprovalOptionKind.rejectAlways,
      },
      tone: switch (option.kind) {
        PermissionOptionKind.allowOnce ||
        PermissionOptionKind.allowAlways => AcpTone.success,
        PermissionOptionKind.rejectOnce ||
        PermissionOptionKind.rejectAlways => AcpTone.danger,
      },
    );

AcpToolCallStatus _toolCallStatusOf(ToolCallStatusView status) =>
    switch (status) {
      ToolCallStatusView.queued => AcpToolCallStatus.queued,
      ToolCallStatusView.running => AcpToolCallStatus.running,
      ToolCallStatusView.succeeded => AcpToolCallStatus.succeeded,
      ToolCallStatusView.failed => AcpToolCallStatus.failed,
      ToolCallStatusView.cancelled => AcpToolCallStatus.cancelled,
    };

/// Опции конфигурации сессии (селекторы модели и режима, объявленные агентом).
List<AcpConfigOption> configOptionsOf(List<ConfigOptionView> options) => [
  for (final option in options)
    AcpConfigOption(
      id: option.id,
      name: option.name,
      currentValue: option.currentValue,
      description: option.description,
      values: [
        for (final value in option.values)
          AcpConfigOptionValue(
            value: value.value,
            name: value.name,
            description: value.description,
          ),
      ],
    ),
];

/// Команды агента (последний `available_commands_update`) — действия палитры
/// с источником `agent`; выбор такой команды вставляет `/{name} ` в композер.
List<AcpCommandAction> agentCommandsOf(List<AgentCommandView> commands) => [
  for (final command in commands)
    AcpCommandAction(
      id: 'agent-${command.name}',
      label: command.name,
      slashCommand: '/${command.name}',
      description: command.description,
      icon: FluentIcons.robot,
      source: AcpCommandSource.agent,
      hint: command.hint,
    ),
];

/// План сессии — последний `SessionUpdate.plan` по всем её ходам.
///
/// План из раннего хода остаётся текущим и в следующем ходе, который своего
/// не прислал (add-plan-progress-checklist/design.md, Decisions). `null` —
/// плана ещё не было: секция плана скрыта.
List<AcpPlanEntry>? currentPlanOf(AcpSession session) {
  List<PlanEntry>? latest;
  for (final turn in session.turns) {
    for (final update in turn.updates) {
      if (update case PlanUpdate(:final entries)) {
        latest = entries;
      }
    }
  }
  return latest
      ?.map(
        (entry) => AcpPlanEntry(
          content: entry.content,
          status: switch (entry.status) {
            PlanEntryStatus.pending => AcpPlanEntryStatus.pending,
            PlanEntryStatus.inProgress => AcpPlanEntryStatus.inProgress,
            PlanEntryStatus.completed => AcpPlanEntryStatus.completed,
          },
          priority: switch (entry.priority) {
            PlanEntryPriority.high => AcpPlanEntryPriority.high,
            PlanEntryPriority.medium => AcpPlanEntryPriority.medium,
            PlanEntryPriority.low => AcpPlanEntryPriority.low,
          },
        ),
      )
      .toList(growable: false);
}

/// Очередь промптов сессии из kit (design D7).
List<AcpQueuedPrompt> queuedPromptsOf(List<QueuedPrompt> queue) => [
  for (final item in queue) AcpQueuedPrompt(id: item.id, content: item.text),
];

/// Недавние проекты, самый свежий первым.
///
/// Порядок — забота приложения: контракт `RecentProjectsStore` порядка не
/// обещает (add-open-project-picker/design.md, Decision 4).
List<AcpRecentProject> recentProjectsOf(Iterable<RecentProject> recents) {
  final sorted = recents.toList()
    ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
  return sorted
      .map((entry) => AcpRecentProject(path: entry.path))
      .toList(growable: false);
}
