/// Отображение представлений `codelab_client_core` и ядра клиента в модели `codelab_ui`.
///
/// Почему: `codelab_ui` не зависит ни от протокола, ни от kit (`AGENTS.md` §5), а
/// после разделения `CodeLabShellCubit` (change `extract-acp-client-kit`,
/// design D10) одни и те же модели строят несколько Cubit-ов.
///
/// Для чего: единственное место, где `SessionView`, `ConnectionView` и
/// `AcpSession` превращаются в `CodeLabTranscriptEntry`, `CodeLabSessionListItem`,
/// `CodeLabConfigOption` и другие модели виджетов. Логики клиента здесь нет —
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

CodeLabConnectionStatus connectionStatusOf(ConnectionView connection) =>
    switch (connection) {
      Disconnected() => CodeLabConnectionStatus.disconnected,
      Connecting() => CodeLabConnectionStatus.connecting,
      Reconnecting() => CodeLabConnectionStatus.reconnecting,
      Connected() => CodeLabConnectionStatus.connected,
      ConnectionFailed() => CodeLabConnectionStatus.failed,
    };

/// Название сессии, у которой ещё нет ни заголовка, ни промпта.
const untitledSessionTitle = 'New session';

/// Предел длины названия из первого промпта: строка сайдбара однострочная.
const _promptTitleMaxLength = 60;

/// Строка сайдбара: заголовок сессии, подзаголовок — `cwd`.
///
/// Заголовок агент присылает в `session_info_update` только после первого
/// хода, а некоторые агенты не присылают его вовсе. До этого название —
/// начало первого промпта, а у сессии без промптов — [untitledSessionTitle];
/// id сессии (ULID) пользователю ничего не говорит и в названии не
/// показывается.
CodeLabSessionListItem sessionListItemOf(AcpSession session) {
  final title = session.title?.trim().isNotEmpty == true
      ? session.title!.trim()
      : _firstPromptTitle(session) ?? untitledSessionTitle;
  return CodeLabSessionListItem(
    id: session.id.value,
    title: title,
    status: _sessionStatusOf(session.status),
    subtitle: session.cwd,
    updatedLabel: 'Active',
  );
}

String? _firstPromptTitle(AcpSession session) {
  for (final turn in session.turns) {
    for (final block in turn.prompt) {
      if (block case TextContent(:final text)) {
        final line = text.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (line.isEmpty) continue;
        return line.length <= _promptTitleMaxLength
            ? line
            : '${line.substring(0, _promptTitleMaxLength).trimRight()}…';
      }
    }
  }
  return null;
}

CodeLabSessionStatus _sessionStatusOf(SessionLifecycleStatus status) =>
    switch (status) {
      SessionLifecycleStatus.idle ||
      SessionLifecycleStatus.active => CodeLabSessionStatus.idle,
      SessionLifecycleStatus.runningTurn ||
      SessionLifecycleStatus.cancellingTurn => CodeLabSessionStatus.running,
      SessionLifecycleStatus.awaitingApproval =>
        CodeLabSessionStatus.awaitingApproval,
      SessionLifecycleStatus.failed => CodeLabSessionStatus.failed,
    };

/// Транскрипт kit (`TranscriptProjector`, design D5) в записи ленты.
///
/// Id записей — позиционные (`prompt-N`, `agent-N`, `tool-N`,
/// `prompt-error-N`), как до переноса проекции в kit: на них опираются
/// виджеты и тесты. [approvalsEnabled] гасит кнопки одобрения, пока ответ на
/// другое одобрение в полёте.
List<CodeLabTranscriptEntry> transcriptEntriesOf(
  List<TranscriptItem> transcript, {
  required String cwd,
  required bool approvalsEnabled,
  required ApprovalOptionChosen onApprovalSelected,
}) => [
  for (final (index, item) in transcript.indexed)
    switch (item) {
      UserItem(:final text) => CodeLabTranscriptEntry(
        id: 'prompt-${index + 1}',
        kind: CodeLabTranscriptEntryKind.user,
        title: 'You',
        body: text,
      ),
      AgentTextItem(:final text) ||
      ThoughtItem(:final text) ||
      NoticeItem(
        kind: NoticeKind.emptyTurn,
        :final text,
      ) => CodeLabTranscriptEntry(
        id: 'agent-${index + 1}',
        kind: CodeLabTranscriptEntryKind.agent,
        title: 'Agent',
        body: text,
      ),
      NoticeItem(kind: NoticeKind.error, :final text) => CodeLabTranscriptEntry(
        id: 'prompt-error-${index + 1}',
        kind: CodeLabTranscriptEntryKind.diagnostic,
        title: 'Prompt failed',
        body: text,
      ),
      // Связь сессии с агентом: после переподключения или перезапуска
      // (design D5, D6 change `add-session-list-and-reload`).
      NoticeItem(
        kind: NoticeKind.detached || NoticeKind.reconnected,
        :final text,
      ) =>
        CodeLabTranscriptEntry(
          id: 'session-notice-${index + 1}',
          kind: CodeLabTranscriptEntryKind.diagnostic,
          title: 'Session',
          body: text,
        ),
      ToolCallItem(:final title, :final details, :final approval) =>
        CodeLabTranscriptEntry(
          id: 'tool-${index + 1}',
          kind: CodeLabTranscriptEntryKind.toolCall,
          title: title,
          toolCall: details == null
              ? null
              : CodeLabToolCallSummary(
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
CodeLabTranscriptApproval? _transcriptApprovalOf(
  ApprovalStateView? approval, {
  required String cwd,
  required bool enabled,
  required ApprovalOptionChosen onSelected,
}) => switch (approval) {
  null => null,
  ResolvedApprovalView(:final label, :final outcome) =>
    CodeLabTranscriptApproval.resolved(
      label: label,
      outcome: switch (outcome) {
        ApprovalOutcomeView.allowed => CodeLabApprovalOutcome.allowed,
        ApprovalOutcomeView.rejected => CodeLabApprovalOutcome.rejected,
        ApprovalOutcomeView.cancelled => CodeLabApprovalOutcome.cancelled,
        ApprovalOutcomeView.unknown => CodeLabApprovalOutcome.unknown,
      },
    ),
  PendingApprovalView() => CodeLabTranscriptApproval.pending(
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

CodeLabApprovalRisk _approvalRiskOf(ApprovalRiskLevel risk) => switch (risk) {
  ApprovalRiskLevel.readOnly => CodeLabApprovalRisk.readOnly,
  ApprovalRiskLevel.localWrite => CodeLabApprovalRisk.localWrite,
  ApprovalRiskLevel.network => CodeLabApprovalRisk.network,
  ApprovalRiskLevel.shell => CodeLabApprovalRisk.shell,
  ApprovalRiskLevel.destructive => CodeLabApprovalRisk.destructive,
};

CodeLabApprovalOption _approvalOptionOf(
  PermissionOption option,
) => CodeLabApprovalOption(
  id: option.optionId.value,
  label: option.name,
  kind: switch (option.kind) {
    PermissionOptionKind.allowOnce => CodeLabApprovalOptionKind.allowOnce,
    PermissionOptionKind.allowAlways => CodeLabApprovalOptionKind.allowAlways,
    PermissionOptionKind.rejectOnce => CodeLabApprovalOptionKind.rejectOnce,
    PermissionOptionKind.rejectAlways => CodeLabApprovalOptionKind.rejectAlways,
  },
  tone: switch (option.kind) {
    PermissionOptionKind.allowOnce ||
    PermissionOptionKind.allowAlways => CodeLabTone.success,
    PermissionOptionKind.rejectOnce ||
    PermissionOptionKind.rejectAlways => CodeLabTone.danger,
  },
);

CodeLabToolCallStatus _toolCallStatusOf(ToolCallStatusView status) =>
    switch (status) {
      ToolCallStatusView.queued => CodeLabToolCallStatus.queued,
      ToolCallStatusView.running => CodeLabToolCallStatus.running,
      ToolCallStatusView.succeeded => CodeLabToolCallStatus.succeeded,
      ToolCallStatusView.failed => CodeLabToolCallStatus.failed,
      ToolCallStatusView.cancelled => CodeLabToolCallStatus.cancelled,
    };

/// Опции конфигурации сессии (селекторы модели и режима, объявленные агентом).
List<CodeLabConfigOption> configOptionsOf(List<ConfigOptionView> options) => [
  for (final option in options)
    CodeLabConfigOption(
      id: option.id,
      name: option.name,
      currentValue: option.currentValue,
      description: option.description,
      values: [
        for (final value in option.values)
          CodeLabConfigOptionValue(
            value: value.value,
            name: value.name,
            description: value.description,
          ),
      ],
    ),
];

/// Команды агента (последний `available_commands_update`) — действия палитры
/// с источником `agent`; выбор такой команды вставляет `/{name} ` в композер.
List<CodeLabCommandAction> agentCommandsOf(List<AgentCommandView> commands) => [
  for (final command in commands)
    CodeLabCommandAction(
      id: 'agent-${command.name}',
      label: command.name,
      slashCommand: '/${command.name}',
      description: command.description,
      icon: FluentIcons.robot,
      source: CodeLabCommandSource.agent,
      hint: command.hint,
    ),
];

/// План сессии — последний `SessionUpdate.plan` по всем её ходам.
///
/// План из раннего хода остаётся текущим и в следующем ходе, который своего
/// не прислал (add-plan-progress-checklist/design.md, Decisions). `null` —
/// плана ещё не было: секция плана скрыта.
List<CodeLabPlanEntry>? currentPlanOf(AcpSession session) {
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
        (entry) => CodeLabPlanEntry(
          content: entry.content,
          status: switch (entry.status) {
            PlanEntryStatus.pending => CodeLabPlanEntryStatus.pending,
            PlanEntryStatus.inProgress => CodeLabPlanEntryStatus.inProgress,
            PlanEntryStatus.completed => CodeLabPlanEntryStatus.completed,
          },
          priority: switch (entry.priority) {
            PlanEntryPriority.high => CodeLabPlanEntryPriority.high,
            PlanEntryPriority.medium => CodeLabPlanEntryPriority.medium,
            PlanEntryPriority.low => CodeLabPlanEntryPriority.low,
          },
        ),
      )
      .toList(growable: false);
}

/// Очередь промптов сессии из kit (design D7).
List<CodeLabQueuedPrompt> queuedPromptsOf(List<QueuedPrompt> queue) => [
  for (final item in queue)
    CodeLabQueuedPrompt(id: item.id, content: item.text),
];

/// Недавние проекты, самый свежий первым.
///
/// Порядок — забота приложения: контракт `RecentProjectsStore` порядка не
/// обещает (add-open-project-picker/design.md, Decision 4).
List<CodeLabRecentProject> recentProjectsOf(Iterable<RecentProject> recents) {
  final sorted = recents.toList()
    ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
  return sorted
      .map((entry) => CodeLabRecentProject(path: entry.path))
      .toList(growable: false);
}
