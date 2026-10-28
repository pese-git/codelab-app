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
import 'package:fluent_ui/fluent_ui.dart' show FluentIcons, VoidCallback;

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
      ConnectionLost() => CodeLabConnectionStatus.lost,
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

/// Строка сайдбара для сессии агента, ещё не открытой в этом запуске
/// (`session/list` или снимок прошлого запуска; design D7 change
/// `add-session-list-and-reload`): заголовок агента или `Session <id>`,
/// подзаголовок — `cwd`, подпись — время последнего изменения.
CodeLabSessionListItem sessionListItemOfSummary(SessionSummaryView summary) {
  final title = summary.title?.trim();
  final updated = summary.updatedAt?.toLocal();
  return CodeLabSessionListItem(
    id: summary.id.value,
    title: title == null || title.isEmpty
        ? 'Session ${summary.id.value}'
        : title,
    status: CodeLabSessionStatus.notLoaded,
    subtitle: summary.cwd,
    updatedLabel: updated == null ? null : 'Updated ${_minuteOf(updated)}',
  );
}

String _minuteOf(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
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

/// Транскрипт kit (`TranscriptProjector`, design D5) в строки ленты.
///
/// Почему: лента рисует свой виджет на каждый вид строки — пузырь
/// пользователя, ответ, мысли, вызов, заметку (change
/// `redesign-transcript-rows`, D1); маппер — единственное место, где модели
/// kit превращаются в модели `codelab_ui` (DSK-1).
///
/// Для чего: id строк — позиционные (`prompt-N`, `agent-N`, `thought-N`,
/// `tool-N`, `prompt-error-N`, `session-notice-N`, `notice-N`), как до переноса проекции
/// в kit: на них опираются тесты, и по ним лента хранит ручное раскрытие.
/// Строку вызова собирает `ToolRowFormatter` с [cwd] сессии.
///
/// Как использовать: [isRunning] — сессия выполняет ход; последние мысли
/// идущего хода стримятся (design D4). [approvalsEnabled] гасит кнопки
/// одобрения, пока ответ на другое одобрение в полёте. [onRetry] — повтор
/// последнего сорвавшегося хода; хост передаёт его, только когда повтор
/// возможен (`SessionView.canRetry` и соединение установлено, design D4
/// change `add-connection-and-error-states`), и кнопка Retry появляется у
/// последней заметки о сбое.
List<CodeLabTranscriptRow> transcriptRowsOf(
  List<TranscriptItem> transcript, {
  required String cwd,
  required bool approvalsEnabled,
  required ApprovalOptionChosen onApprovalSelected,
  bool isRunning = false,
  VoidCallback? onRetry,
}) {
  final lastErrorIndex = transcript.lastIndexWhere(
    (item) => item is NoticeItem && item.kind == NoticeKind.error,
  );
  return [
    for (final (index, item) in transcript.indexed)
      switch (item) {
        UserItem(:final text) => CodeLabUserRow(
          id: 'prompt-${index + 1}',
          text: text,
        ),
        AgentTextItem(:final text) => CodeLabAgentTextRow(
          id: 'agent-${index + 1}',
          text: text,
        ),
        ThoughtItem(:final text) => CodeLabThoughtRow(
          id: 'thought-${index + 1}',
          text: text,
          streaming: isRunning && index == transcript.length - 1,
        ),
        NoticeItem(kind: NoticeKind.error, :final text, :final failure) =>
          CodeLabNoticeRow(
            id: 'prompt-error-${index + 1}',
            severity: CodeLabNoticeSeverity.error,
            title: failureTitleOf(failure),
            body: _failureBodyOf(failure) ?? text,
            details: failure == null ? null : text,
            action: index == lastErrorIndex && onRetry != null
                ? CodeLabTranscriptAction(
                    label: 'Retry',
                    icon: FluentIcons.refresh,
                    onPressed: onRetry,
                  )
                : null,
          ),
        // Связь сессии с агентом (design D5, D6 change
        // `add-session-list-and-reload`): потеря — предупреждение, новая или
        // переподключённая сессия и пустой ход — нейтральная строка
        // (design D6 change `redesign-transcript-rows`).
        NoticeItem(kind: NoticeKind.detached, :final text) => CodeLabNoticeRow(
          id: 'session-notice-${index + 1}',
          severity: CodeLabNoticeSeverity.warning,
          title: 'Session detached',
          body: text,
        ),
        NoticeItem(kind: NoticeKind.reconnected, :final text) =>
          CodeLabNoticeRow(
            id: 'session-notice-${index + 1}',
            severity: CodeLabNoticeSeverity.info,
            body: text,
          ),
        NoticeItem(kind: NoticeKind.emptyTurn, :final text) => CodeLabNoticeRow(
          id: 'notice-${index + 1}',
          severity: CodeLabNoticeSeverity.info,
          body: text,
        ),
        final ToolCallItem call => _toolCallRowOf(
          call,
          id: 'tool-${index + 1}',
          cwd: cwd,
          approvalsEnabled: approvalsEnabled,
          onApprovalSelected: onApprovalSelected,
        ),
      },
  ];
}

CodeLabToolCallRow _toolCallRowOf(
  ToolCallItem call, {
  required String id,
  required String cwd,
  required bool approvalsEnabled,
  required ApprovalOptionChosen onApprovalSelected,
}) {
  final view = ToolRowFormatter.format(call, cwd: cwd);
  final details = call.details;
  return CodeLabToolCallRow(
    id: id,
    status: _toolCallStatusOf(details?.status ?? ToolCallStatusView.queued),
    label: view.label,
    detail: view.detail,
    secondary: view.secondary,
    output: details?.textOutput ?? const [],
    approval: _transcriptApprovalOf(
      call.approval,
      title: approvalTitleOf(details?.kind ?? ToolKind.other),
      cwd: cwd,
      enabled: approvalsEnabled,
      onSelected: onApprovalSelected,
    ),
  );
}

/// Вопрос карточки одобрения по виду вызова (требование «Approval card
/// inside the tool call row»).
String approvalTitleOf(ToolKind kind) => switch (kind) {
  ToolKind.execute => 'Run a command?',
  ToolKind.edit => 'Edit a file?',
  ToolKind.delete => 'Delete a file?',
  ToolKind.move => 'Move a file?',
  ToolKind.read => 'Read a file?',
  ToolKind.search => 'Run a search?',
  ToolKind.fetch => 'Fetch a URL?',
  ToolKind.think || ToolKind.other => 'Allow this tool call?',
};

/// Чип хода в шапке панели сессии (требование «Session pane header»):
/// идущий ход с ожидающим одобрением — «Waiting for approval».
CodeLabTurnState? turnStateOf(SessionView? view) => switch (view?.status) {
  SessionStatusView.running when view!.pendingApprovals.isNotEmpty =>
    CodeLabTurnState.awaitingApproval,
  SessionStatusView.running => CodeLabTurnState.running,
  SessionStatusView.cancelling => CodeLabTurnState.cancelling,
  _ => null,
};

/// Заголовок заметки о сбое хода по классу сбоя (design D3 change
/// `add-connection-and-error-states`).
///
/// Почему: сырой текст исключения ничего не говорит пользователю, а класс
/// сбоя от агента (`data.codelab.errorClass`) — говорит. Незнакомый класс и
/// сбой без класса получают общий заголовок: словарь классов растёт на
/// стороне агента.
String failureTitleOf(PromptFailure? failure) => switch (failure) {
  AgentPromptFailure(errorClass: 'auth') =>
    'The agent could not sign in to the model provider',
  AgentPromptFailure(errorClass: 'network' || 'timeout' || 'server') =>
    'The model provider is unavailable',
  AgentPromptFailure(errorClass: 'rateLimited') =>
    "The model provider's rate limit was reached",
  AgentPromptFailure(errorClass: 'overflow') =>
    'The conversation is too long for the model',
  ConnectionLostPromptFailure() => 'The connection to the agent was lost',
  AgentPromptFailure() ||
  RequestPromptFailure() ||
  UnknownPromptFailure() ||
  null => 'The agent could not complete the turn',
};

/// Тело заметки: сообщение агента или JSON-RPC; сырой текст ошибки уходит в
/// Details. Без типизированного сбоя тело — сам текст заметки.
String? _failureBodyOf(PromptFailure? failure) => switch (failure) {
  AgentPromptFailure(:final message) ||
  RequestPromptFailure(:final message) ||
  UnknownPromptFailure(:final message) => message,
  ConnectionLostPromptFailure() =>
    'Reconnect to continue working with the agent.',
  null => null,
};

/// Одобрение встроено в строку вызова: ожидающее — интерактивная карточка,
/// решённое — тег исхода (embed-approval-in-thread/design.md,
/// Decisions 1–3).
CodeLabTranscriptApproval? _transcriptApprovalOf(
  ApprovalStateView? approval, {
  required String title,
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
    title: title,
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
  for (final command in commands) _agentCommandAction(command),
];

CodeLabCommandAction _agentCommandAction(AgentCommandView command) =>
    CodeLabCommandAction(
      id: 'agent-${command.name}',
      label: command.name,
      slashCommand: '/${command.name}',
      description: command.description,
      icon: FluentIcons.robot,
      source: CodeLabCommandSource.agent,
      hint: command.hint,
    );

/// Шесть команд app как команды хоста каталога: имя — `slashCommand` без
/// `/`, связь с иконкой — `id` (D2 change `add-command-palette-agent-commands`).
final List<HostCommand> _paletteHostCommands = List.unmodifiable([
  for (final action in CodeLabCommandAction.defaults)
    HostCommand(
      id: action.id,
      name: action.slashCommand.substring(1),
      label: action.label,
      description: action.description,
      isAvailable: action.isAvailable,
    ),
]);

/// Каталог палитры для команд агента активной сессии: команды app и
/// [agentCommands] с правилами kit (конфликты имён, поиск — D3, D4).
CommandCatalog paletteCatalogOf(List<AgentCommandView> agentCommands) =>
    CommandCatalog(host: _paletteHostCommands, agent: agentCommands);

/// Полный список палитры в порядке каталога.
List<CodeLabCommandAction> paletteActionsOf(CommandCatalog catalog) => [
  for (final command in catalog.commands) _paletteActionOf(command),
];

/// Команды палитры под запрос [query] в порядке поиска каталога.
List<CodeLabCommandAction> searchPaletteActions(
  CommandCatalog catalog,
  String query,
) => [for (final command in catalog.search(query)) _paletteActionOf(command)];

CodeLabCommandAction _paletteActionOf(CatalogCommand command) =>
    switch (command) {
      HostCatalogCommand(:final command) =>
        CodeLabCommandAction.defaults.firstWhere(
          (action) => action.id == command.id,
        ),
      AgentCatalogCommand(:final command) => _agentCommandAction(command),
    };

/// План сессии из kit: `SessionView.plan` в записях виджета.
///
/// Правило «последнее обновление `plan` заменяет план, план раннего хода
/// остаётся текущим» — в kit (design.md change `add-codelab-cli`, D14).
/// `null` — плана ещё не было: секция плана скрыта.
List<CodeLabPlanEntry>? planEntriesOf(List<PlanEntryView> plan) => plan.isEmpty
    ? null
    : [
        for (final entry in plan)
          CodeLabPlanEntry(
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
      ];

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

/// Имя папки проекта для заголовка группы и чипа шапки: последний непустой
/// сегмент пути; полный путь хост показывает подсказкой (change
/// `redesign-workbench-shell`, D4, D7).
String projectNameOf(String path) {
  final segments = path
      .split(RegExp(r'[/\\]'))
      .where((segment) => segment.isNotEmpty);
  return segments.isEmpty ? path : segments.last;
}

/// Группы проектов сайдбара: выбранный проект раскрыт с сессиями, остальные
/// недавние — свёрнутыми группами (change `redesign-workbench-shell`, D4).
///
/// Выбранный проект, которого нет среди недавних, всё равно идёт первой
/// группой; без выбранного проекта сессии попадают в группу «No project».
List<CodeLabSidebarProject> sidebarProjectsOf({
  required String? selectedProjectPath,
  required List<CodeLabSessionListItem> sessions,
  required List<CodeLabRecentProject> recentProjects,
}) {
  final selected = selectedProjectPath;
  return [
    CodeLabSidebarProject(
      path: selected ?? '',
      name: selected == null ? 'No project' : projectNameOf(selected),
      current: true,
      sessions: sessions,
    ),
    for (final recent in recentProjects)
      if (recent.path != selected)
        CodeLabSidebarProject(
          path: recent.path,
          name: projectNameOf(recent.path),
        ),
  ];
}

/// Значение опции режима для чипа шапки сессии — по категории `mode` из
/// ACP; без такой опции чипа нет (change `redesign-workbench-shell`, D7).
String? modeLabelOf(List<ConfigOptionView> options) {
  for (final option in options) {
    if (option.category != 'mode') {
      continue;
    }
    for (final value in option.values) {
      if (value.value == option.currentValue) {
        return value.name;
      }
    }
    return option.currentValue;
  }
  return null;
}

/// Подсказка бейджа соединения: профиль, транспорт и команда или адрес —
/// то, что раньше занимало шапку (change `redesign-workbench-shell`, D6).
String connectionTooltipOf({
  required String profileLabel,
  required String transportLabel,
  required String connectionDetail,
}) => [
  profileLabel,
  transportLabel,
  if (connectionDetail.isNotEmpty) connectionDetail,
].join(' · ');
