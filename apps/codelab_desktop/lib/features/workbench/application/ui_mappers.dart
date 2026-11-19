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

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentIcons, VoidCallback;

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_en.dart';
import 'agents_pane_data.dart';

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

/// Предел длины названия из первого промпта: строка сайдбара однострочная.
const _promptTitleMaxLength = 60;

/// Строка сайдбара: заголовок сессии, подзаголовок — `cwd`.
///
/// Заголовок агент присылает в `session_info_update` только после первого
/// хода, а некоторые агенты не присылают его вовсе. До этого название —
/// начало первого промпта, а у сессии без промптов — `commonNewSession`
/// каталога [l10n]; id сессии (ULID) пользователю ничего не говорит и в
/// названии не показывается. Заголовок агента и промпт пользователя не
/// переводятся (D7). Язык — явный вход (`add-desktop-localization`, D5):
/// Cubit-ы пересобирают строки по событию `AppStrings.changes`.
CodeLabSessionListItem sessionListItemOf(
  AcpSession session, {
  required AppLocalizations l10n,
}) {
  final title = session.title?.trim().isNotEmpty == true
      ? session.title!.trim()
      : _firstPromptTitle(session) ?? l10n.commonNewSession;
  return CodeLabSessionListItem(
    id: session.id.value,
    title: title,
    status: _sessionStatusOf(session.status),
    subtitle: session.cwd,
    updatedLabel: l10n.workbenchSessionActive,
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
CodeLabSessionListItem sessionListItemOfSummary(
  SessionSummaryView summary, {
  required AppLocalizations l10n,
}) {
  final title = summary.title?.trim();
  final updated = summary.updatedAt?.toLocal();
  return CodeLabSessionListItem(
    id: summary.id.value,
    title: title == null || title.isEmpty
        ? l10n.workbenchSessionTitleWithId(summary.id.value)
        : title,
    status: CodeLabSessionStatus.notLoaded,
    subtitle: summary.cwd,
    updatedLabel: updated == null
        ? null
        : l10n.workbenchSessionUpdated(_minuteOf(updated)),
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
/// `tool-N`, `prompt-error-N`, `session-notice-N`, `notice-N`), как до
/// переноса проекции в kit: на них опираются тесты, и по ним лента хранит
/// ручное раскрытие.
/// Строку вызова собирает `ToolRowFormatter` с [cwd] сессии.
///
/// Как использовать: [isRunning] — сессия выполняет ход; последние мысли и
/// ответ идущего хода стримятся (design D4; `add-desktop-markdown` D3).
/// [approvalsEnabled] гасит кнопки одобрения, пока ответ на другое одобрение
/// в полёте. [onRetry] — повтор последнего сорвавшегося хода; хост передаёт
/// его, только когда повтор возможен (`SessionView.canRetry` и соединение
/// установлено, design D4 change `add-connection-and-error-states`), и кнопка
/// Retry появляется у последней заметки о сбое.
///
/// Заметки строятся по типизированной причине `NoticeItem.reason`, а не по
/// английскому `NoticeItem.text` ядра (D6): `text` остаётся запасным
/// значением для заметки без причины. Ответ агента, запрос пользователя,
/// мысли и заголовки вызовов от агента не переводятся (D7).
List<CodeLabTranscriptRow> transcriptRowsOf(
  List<TranscriptItem> transcript, {
  required String cwd,
  required bool approvalsEnabled,
  required ApprovalOptionChosen onApprovalSelected,
  required AppLocalizations l10n,
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
        // Ответ — одна строка с текстом как есть: markdown, в том числе ответ
        // одним огороженным блоком (`/mcp list`), разбирает и рисует кит
        // (change `add-desktop-markdown`, D3, D11); `streaming` — последний
        // элемент идущего хода, как у мыслей.
        AgentTextItem(:final text) => CodeLabAgentTextRow(
          id: 'agent-${index + 1}',
          text: text,
          streaming: isRunning && index == transcript.length - 1,
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
            title: failureTitleOf(failure, l10n: l10n),
            body: _failureBodyOf(failure, l10n) ?? text,
            details: failure == null ? null : text,
            action: index == lastErrorIndex && onRetry != null
                ? CodeLabTranscriptAction(
                    label: l10n.commonRetry,
                    icon: FluentIcons.refresh,
                    onPressed: onRetry,
                  )
                : null,
          ),
        // Связь сессии с агентом (design D5, D6 change
        // `add-session-list-and-reload`): потеря — предупреждение, новая или
        // переподключённая сессия и пустой ход — нейтральная строка
        // (design D6 change `redesign-transcript-rows`).
        NoticeItem(kind: NoticeKind.detached, :final text, :final reason) =>
          CodeLabNoticeRow(
            id: 'session-notice-${index + 1}',
            severity: CodeLabNoticeSeverity.warning,
            title: l10n.workbenchNoticeSessionDetached,
            body: _noticeBodyOf(NoticeKind.detached, reason, text, l10n),
          ),
        NoticeItem(kind: NoticeKind.reconnected, :final text, :final reason) =>
          CodeLabNoticeRow(
            id: 'session-notice-${index + 1}',
            severity: CodeLabNoticeSeverity.info,
            body: _noticeBodyOf(NoticeKind.reconnected, reason, text, l10n),
          ),
        // Заметка исхода хода (Q33, D27): лимит токенов, лимит запросов,
        // отказ агента — информационная строка, как `emptyTurn`.
        NoticeItem(kind: NoticeKind.turnStopped, :final text, :final reason) =>
          CodeLabNoticeRow(
            id: 'notice-${index + 1}',
            severity: CodeLabNoticeSeverity.info,
            body: _noticeBodyOf(NoticeKind.turnStopped, reason, text, l10n),
          ),
        NoticeItem(kind: NoticeKind.emptyTurn, :final text, :final reason) =>
          CodeLabNoticeRow(
            id: 'notice-${index + 1}',
            severity: CodeLabNoticeSeverity.info,
            body: _noticeBodyOf(NoticeKind.emptyTurn, reason, text, l10n),
          ),
        // Тихая строка операций со списком задач (D27): текст даёт kit.
        final TaskOpsItem ops => CodeLabTaskOpsRow(
          id: 'task-ops-${index + 1}',
          text: ops.text,
        ),
        final ToolCallItem call => _toolCallRowOf(
          call,
          id: _toolRowIdOf(call, index),
          cwd: cwd,
          approvalsEnabled: approvalsEnabled,
          onApprovalSelected: onApprovalSelected,
          l10n: l10n,
        ),
      },
  ];
}

/// Тело заметки хода или связи сессии по типизированной причине [reason].
///
/// Почему не `text` ядра: он английский и общий с CLI, а desktop строит
/// текст сам (D6). Причина другого вида или `null` — запасной [text] ядра:
/// заметка не теряется, если ядро добавит новую причину.
String _noticeBodyOf(
  NoticeKind kind,
  NoticeReason? reason,
  String text,
  AppLocalizations l10n,
) => switch (reason) {
  TurnStoppedReason(:final stopReason, :final budgetLimit) =>
    switch (stopReason) {
      StopReason.maxTokens => l10n.workbenchNoticeMaxTokens,
      StopReason.refusal => l10n.workbenchNoticeRefusal,
      StopReason.maxTurnRequests =>
        budgetLimit == null
            ? l10n.workbenchNoticeMaxTurnRequests
            : l10n.workbenchNoticeBudgetExceeded(budgetLimit),
      StopReason.endTurn || StopReason.cancelled => text,
    },
  // `stopReason` — значение провода: подставляется как `name`, как в тексте
  // ядра (решение оркестратора 2026-11-18), и не переводится (D7).
  EmptyTurnReason(:final stopReason) =>
    stopReason == null
        ? l10n.workbenchNoticeCompletedStopReasonUnknown
        : l10n.workbenchNoticeCompletedWithStopReason(stopReason.name),
  SessionRestoreReason(:final cause, :final sessionId) => switch ((
    kind,
    cause,
  )) {
    (NoticeKind.detached, SessionRestoreCause.agentCannotRestore) =>
      l10n.workbenchNoticeDetachedCannotRestore,
    // Без id сессии сообщение с плейсхолдером теряет смысл («сессию  не
    // удалось…»): остаётся текст ядра.
    (_, SessionRestoreCause.restoreFailed) when sessionId == null => text,
    (NoticeKind.detached, SessionRestoreCause.restoreFailed) =>
      l10n.workbenchNoticeDetachedRestoreFailed(sessionId!.value),
    (_, SessionRestoreCause.agentCannotRestore) =>
      l10n.workbenchNoticeReconnectedCannotRestore,
    (_, SessionRestoreCause.restoreFailed) =>
      l10n.workbenchNoticeReconnectedRestoreFailed(sessionId!.value),
  },
  null => text,
};

/// Id строки ленты верхнего уровня для вызова [call] на позиции [index].
///
/// Вызов, объявленный только запросом субагента (строки корня нет, D43 п. 2),
/// несёт стабильный id элемента транскрипта: индекс сдвигается, когда строка
/// корня появляется позже. Тот же id нужен панели Agents (`topRowIds`), чтобы
/// найти строку ленты по пути элементов kit.
String _toolRowIdOf(ToolCallItem call, int index) =>
    _isSubagentRequested(call) ? call.id : 'tool-${index + 1}';

/// Строка вызова ленты; [nested] — строка потомка внутри дерева `agent`.
///
/// Почему [nested]: панель решения принадлежит блоку под строкой корня
/// (`childApprovals`, D27 п. 4, D47 Т9), а у вложенной строки ожидающее
/// одобрение даёт лишь пометку «ждёт решения»: две панели одного запроса
/// дали бы два набора кнопок на одно решение (PERM-4). Решённое одобрение
/// остаётся тегом исхода и на своём месте в дереве.
CodeLabToolCallRow _toolCallRowOf(
  ToolCallItem call, {
  required String id,
  required String cwd,
  required bool approvalsEnabled,
  required ApprovalOptionChosen onApprovalSelected,
  required AppLocalizations l10n,
  bool nested = false,
}) {
  final view = ToolRowFormatter.format(call, cwd: cwd);
  final details = call.details;
  // Вызов `agent` опознан kit с первого кадра (D28): компактная строка D27.
  // Заголовок «Subagent <type>: <description>» и итог готовит kit
  // (`ToolRowFormatter`), маппер только переносит их; отчёт — в раскрытие.
  final isSubagent = details?.subagentCall != null;
  final approval = call.approval;
  final waitsRootDecision = nested && approval is PendingApprovalView;
  CodeLabToolCallRow rowOf(ToolCallItem child) => _toolCallRowOf(
    child,
    id: child.id,
    cwd: cwd,
    approvalsEnabled: approvalsEnabled,
    onApprovalSelected: onApprovalSelected,
    l10n: l10n,
    nested: true,
  );
  return CodeLabToolCallRow(
    id: id,
    status: _toolCallStatusOf(details?.status ?? ToolCallStatusView.queued),
    // Метка вида вызова — текст app; заголовок вида `other` и строка
    // субагента приходят от агента и ядра и не переводятся (D6, D7).
    label: isSubagent
        ? '${view.label} ${view.detail}'.trim()
        : toolKindLabelOf(details?.kind, view.label, l10n),
    detail: isSubagent ? '' : view.detail,
    secondary: view.secondary,
    output: isSubagent
        ? [if (view.report case final report?) ...report.split('\n')]
        : details?.textOutput ?? const [],
    subagent: isSubagent
        ? CodeLabSubagentCall(
            stats: view.summaryShort ?? view.runningCounter,
            progress: view.progress,
            // Хвост — готовый срез kit (D25, D47 Т9). Kit строит его
            // независимо от статуса, а показывает строка только у работающего
            // вызова; итог завершённого берётся из `summary`. Операция со
            // списком задач — тихая строка (D48 п. 3).
            tail: [
              for (final tailed in call.tail.calls)
                switch (call.tail.operations[tailed.toolCallId]) {
                  final TaskOpsItem ops => CodeLabTaskOpsRow(
                    id: tailed.id,
                    text: ops.text,
                  ),
                  null => rowOf(tailed),
                },
            ],
            tailMore: call.tail.moreCount,
          )
        : null,
    approval: waitsRootDecision
        ? null
        : _transcriptApprovalOf(
            approval,
            callStatus: details?.status,
            enabled: approvalsEnabled,
            onSelected: onApprovalSelected,
            l10n: l10n,
          ),
    awaitsRootDecision: waitsRootDecision,
    // Одобрения потомков — блоки под строкой корня (D27 п. 4, D43 п. 2).
    childApprovals: [
      for (final child in call.childApprovals)
        ?_transcriptApprovalOf(
          child,
          callStatus: null,
          enabled: approvalsEnabled,
          onSelected: onApprovalSelected,
          l10n: l10n,
        ),
    ],
    // Дерево вызовов потомков (D24, D47 Т11): id вложенных строк — id
    // элементов kit (`<ход>/tool-<цепочка>`), не зависят от индекса и годятся
    // ключом раскрытия в `TranscriptViewCubit`. Операции со списком задач
    // потомка — те же тихие строки (D48 п. 3).
    children: [
      for (final child in call.children)
        switch (child) {
          final ToolCallItem nestedCall => rowOf(nestedCall),
          final TaskOpsItem ops => CodeLabTaskOpsRow(
            id: ops.id,
            text: ops.text,
          ),
          _ => null,
        },
    ].nonNulls.toList(),
  );
}

/// Одобрение вызова пришло от субагента (`subagent` у ожидающего и решённого).
bool _isSubagentRequested(ToolCallItem call) => switch (call.approval) {
  PendingApprovalView(:final subagent) ||
  ResolvedApprovalView(:final subagent) => subagent != null,
  null => false,
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
String failureTitleOf(
  PromptFailure? failure, {
  required AppLocalizations l10n,
}) => switch (failure) {
  AgentPromptFailure(errorClass: 'auth') => l10n.workbenchFailureAuth,
  AgentPromptFailure(errorClass: 'network' || 'timeout' || 'server') =>
    l10n.workbenchFailureProviderUnavailable,
  AgentPromptFailure(errorClass: 'rateLimited') =>
    l10n.workbenchFailureRateLimited,
  AgentPromptFailure(errorClass: 'overflow') => l10n.workbenchFailureOverflow,
  ConnectionLostPromptFailure() => l10n.workbenchFailureConnectionLost,
  AgentPromptFailure() ||
  RequestPromptFailure() ||
  UnknownPromptFailure() ||
  null => l10n.workbenchFailureGeneric,
};

/// Тело заметки: сообщение агента или JSON-RPC; сырой текст ошибки уходит в
/// Details. Без типизированного сбоя тело — сам текст заметки.
String? _failureBodyOf(PromptFailure? failure, AppLocalizations l10n) =>
    switch (failure) {
      AgentPromptFailure(:final message) ||
      RequestPromptFailure(:final message) ||
      UnknownPromptFailure(:final message) => message,
      ConnectionLostPromptFailure() => l10n.workbenchFailureConnectionLostBody,
      null => null,
    };

/// Метка вызова по виду [kind]: перевод app для известных видов; для `other`
/// (и вида, которого ядро не назвало) — [coreLabel], то есть заголовок вызова
/// от агента, который не переводится (D6, D7).
String toolKindLabelOf(
  ToolKind? kind,
  String coreLabel,
  AppLocalizations l10n,
) => switch (kind) {
  ToolKind.read => l10n.workbenchToolKindRead,
  ToolKind.edit => l10n.workbenchToolKindEdit,
  ToolKind.delete => l10n.workbenchToolKindDelete,
  ToolKind.move => l10n.workbenchToolKindMove,
  ToolKind.search => l10n.workbenchToolKindSearch,
  ToolKind.execute => l10n.workbenchToolKindExecute,
  ToolKind.fetch => l10n.workbenchToolKindFetch,
  ToolKind.think => l10n.workbenchToolKindThink,
  ToolKind.switchMode => l10n.workbenchToolKindSwitchMode,
  ToolKind.other || null => coreLabel,
};

/// Одобрение встроено в строку вызова: ожидающее — интерактивная карточка,
/// решённое — тег исхода (embed-approval-in-thread/design.md,
/// Decisions 1–3).
///
/// [callStatus] — статус вызова строки: при отменённом одобрении и статусе
/// `cancelled` тега исхода нет, строку маркирует тег статуса (Q38, D27).
CodeLabTranscriptApproval? _transcriptApprovalOf(
  ApprovalStateView? approval, {
  required ToolCallStatusView? callStatus,
  required bool enabled,
  required ApprovalOptionChosen onSelected,
  required AppLocalizations l10n,
}) => switch (approval) {
  null => null,
  // Ход отменён, пока вызов ждал решения: тег статуса уже читается
  // «Cancelled», второй такой же тег исхода не нужен (Q38, D27).
  ResolvedApprovalView(outcome: ApprovalOutcomeView.cancelled)
      when callStatus == ToolCallStatusView.cancelled =>
    null,
  // Название варианта пришло от агента — не переводится (D4); без него ядро
  // отдаёт лишь запасной английский `label`, а текст берём из каталога.
  ResolvedApprovalView(:final agentLabel, :final outcome) =>
    CodeLabTranscriptApproval.resolved(
      label:
          agentLabel ??
          (outcome == ApprovalOutcomeView.cancelled
              ? l10n.workbenchApprovalCancelled
              : l10n.workbenchApprovalResolved),
      outcome: switch (outcome) {
        ApprovalOutcomeView.allowed => CodeLabApprovalOutcome.allowed,
        ApprovalOutcomeView.rejected => CodeLabApprovalOutcome.rejected,
        ApprovalOutcomeView.cancelled => CodeLabApprovalOutcome.cancelled,
        ApprovalOutcomeView.unknown => CodeLabApprovalOutcome.unknown,
      },
      requesterLine: _requesterLineOf(approval.subagent, l10n),
    ),
  PendingApprovalView() => CodeLabTranscriptApproval.pending(
    risk: _approvalRiskOf(approval.risk),
    command: approval.command,
    rawInput: formatRedactedJson(approval.rawInput),
    options: approval.options.map(_approvalOptionOf).toList(),
    enabled: enabled,
    shortcutsEnabled: approval.focused,
    onOptionSelected: (optionId) => onSelected(approval, optionId),
    requesterLine: _requesterLineOf(approval.subagent, l10n),
    requesterHint: approval.subagent?.description,
    callTitle: approval.subagent == null ? null : _callTitleOf(approval),
    // Цель «Go to approval» панели Agents: лента прокручивается к блоку по
    // id запроса (D49 Т7). Решение по-прежнему принимается только в ленте.
    targetId: approval.approvalId.value,
  ),
};

/// Заголовок вызова потомка для блока, без дубля команды.
///
/// Почему: заголовок вызова `exec` после срезания префикса равен самой
/// команде, и блок показывал её дважды (ручной прогон, задача 3.5a, D44 п. 4).
/// UI не решает, что считать дублем, поэтому сравнение здесь: совпадение с
/// командой после обрезки пробелов — заголовка нет. У write/edit команда
/// пуста, и заголовок («Write NOTES.md») остаётся единственным видимым путём.
String? _callTitleOf(PendingApprovalView approval) {
  final title = _titleWithoutRequesterPrefix(
    approval.toolTitle,
    approval.subagent!,
  );
  if (title == null) return null;
  final command = approval.command?.trim();
  return command != null && command.isNotEmpty && command == title.trim()
      ? null
      : title;
}

/// Заголовок вызова потомка без префикса `[тип: описание] ` (D8).
///
/// Почему: путь и описание задачи блок уже показывает строкой «review wants
/// to run» и подсказкой, префикс их дублирует; нужны инструмент и путь файла
/// («Write .codelab/config.yaml»), которых иначе не видно без раскрытия `{}`.
/// Режется ровно известный префикс из `type` и `description` запроса:
/// описание пишет модель, и поиск первой `"] "` дал бы подмену видимого пути
/// (`x] Write README.md]`). Иной заголовок показывается целиком.
String? _titleWithoutRequesterPrefix(
  String? title,
  SubagentRequester requester,
) {
  if (title == null) return null;
  final prefix = '[${requester.type}: ${requester.description}] ';
  return title.startsWith(prefix) ? title.substring(prefix.length) : title;
}

/// Строка «review › explore wants to run»: путь готовит kit (`pathText`,
/// D43 п. 4), маппер только добавляет действие.
String? _requesterLineOf(SubagentRequester? requester, AppLocalizations l10n) =>
    requester == null
    ? null
    : l10n.workbenchRequesterWantsToRun(requester.pathText);

CodeLabApprovalRisk _approvalRiskOf(ApprovalRiskLevel risk) => switch (risk) {
  ApprovalRiskLevel.readOnly => CodeLabApprovalRisk.readOnly,
  ApprovalRiskLevel.unknown => CodeLabApprovalRisk.unknown,
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

/// Подпись и описание команды хоста [id] на языке [l10n].
///
/// Почему по `id`, а не из `CodeLabCommandAction.defaults`: `defaults` — набор
/// кита с английскими литералами для превью и тестов кита и в итерации 3 не
/// меняется; переводит подписи app по `id` (`add-desktop-localization`, D4).
/// [localRestart] — пункт `reconnect` для локального агента называется
/// «Restart agent» (Q24, D22), для удалённого — «Reconnect».
///
/// `switch` по `id` закрытого набора: `null` — `id` не команда хоста.
({String label, String description})? _hostTextOf(
  String id,
  AppLocalizations l10n, {
  required bool localRestart,
}) => switch (id) {
  'new' => (
    label: l10n.paletteNewLabel,
    description: l10n.paletteNewDescription,
  ),
  'plan' => (
    label: l10n.palettePlanLabel,
    description: l10n.palettePlanDescription,
  ),
  'permissions' => (
    label: l10n.palettePermissionsLabel,
    description: l10n.palettePermissionsDescription,
  ),
  'logs' => (
    label: l10n.paletteLogsLabel,
    description: l10n.paletteLogsDescription,
  ),
  'compact' => (
    label: l10n.paletteCompactLabel,
    description: l10n.paletteCompactDescription,
  ),
  'reconnect' when localRestart => (
    label: l10n.commonRestartAgent,
    description: l10n.paletteRestartDescription,
  ),
  'reconnect' => (
    label: l10n.paletteReconnectLabel,
    description: l10n.paletteReconnectDescription,
  ),
  'files' => (
    label: l10n.paletteFilesLabel,
    description: l10n.paletteFilesDescription,
  ),
  'agents' => (
    label: l10n.paletteAgentsLabel,
    description: l10n.paletteAgentsDescription,
  ),
  'usage-pane' => (
    label: l10n.paletteUsageLabel,
    description: l10n.paletteUsageDescription,
  ),
  _ => null,
};

/// Действие палитры «Files»: открывает или закрывает панель Files дока.
///
/// Почему отдельно от `CodeLabCommandAction.defaults`: пункт есть только когда
/// панель доступна (локальная папка сессии и привязка `ProjectFiles`), а
/// `defaults` — фиксированный набор `codelab_ui` (spec workspace-file-browser
/// «Панель Files в доке инструментов»; design.md change
/// `add-file-preview-and-tree`, D7). Отдельной «группы Go to» у палитры нет:
/// пункт стоит в общем списке после команд app. Подпись и описание здесь —
/// английские эталоны для значка и команды; на экране их заменяет
/// [_paletteActionOf] по каталогу языка.
const _filesAction = CodeLabCommandAction(
  id: 'files',
  label: 'Files',
  slashCommand: '/files',
  description: 'Go to the project files panel.',
  icon: FluentIcons.folder,
);

/// Действие палитры «Agents»: открывает панель Agents дока.
///
/// Почему отдельно от `CodeLabCommandAction.defaults`: пункт есть только когда
/// у сессии в фокусе есть строка субагента (панель доступна), как у «Files»
/// (design.md change `add-subagents-and-tasks`, D49 Т11; spec
/// agent-workbench-ui «Панель Agents v1»). Совпадение с командой агента
/// `/agents` разрешает `CommandCatalog` (D3 change
/// `add-command-palette-agent-commands`).
const _agentsAction = CodeLabCommandAction(
  id: 'agents',
  label: 'Agents',
  slashCommand: '/agents',
  description: 'Go to the subagents panel.',
  icon: FluentIcons.robot,
);

/// Действие палитры «Usage»: открывает панель Usage дока.
///
/// Почему отдельно от `CodeLabCommandAction.defaults`: пункт есть только когда
/// панель доступна (у агента есть `usage` или `usageLedger`, D10), как у
/// «Agents». Команда называется `/usage-pane`, а не `/usage`: у агента CodeLab
/// есть своя команда `/usage` (change `add-usage-ledger`, D5), и каталог
/// показывает команду хоста рядом с одноимённой командой агента (design.md
/// change `add-desktop-usage-pane`, D11).
const _usageAction = CodeLabCommandAction(
  id: 'usage-pane',
  label: 'Usage',
  slashCommand: '/usage-pane',
  description: 'Go to the usage panel.',
  icon: FluentIcons.chart,
);

/// Команда хоста для [action]: подпись и описание — на языке [l10n], а
/// `searchAliases` — английские подпись и описание из `AppLocalizationsEn()`.
///
/// Почему английские строки в `searchAliases`: команды хоста ищутся и по
/// тому, что видит пользователь, и по английскому названию из документации
/// (решение пользователя 2026-11-18, D4). Прямой `AppLocalizationsEn()` равен
/// `lookupAppLocalizations(const Locale('en'))`, как у `titlesOf` в
/// `settings_shell.dart`. Совпадающие с `label`/`description` строки не
/// добавляются, а на `en` поле пусто: поиск там прежний. Ядро не знает, что
/// это английский текст (spec workspace-architecture).
HostCommand _hostCommandOf(
  CodeLabCommandAction action,
  AppLocalizations l10n, {
  required bool localRestart,
}) {
  final text =
      _hostTextOf(action.id, l10n, localRestart: localRestart) ??
      (label: action.label, description: action.description);
  final english =
      _hostTextOf(
        action.id,
        AppLocalizationsEn(),
        localRestart: localRestart,
      ) ??
      (label: action.label, description: action.description);
  return HostCommand(
    id: action.id,
    name: action.slashCommand.substring(1),
    label: text.label,
    description: text.description,
    isAvailable: action.isAvailable,
    searchAliases: [
      if (english.label != text.label) english.label,
      if (english.description != text.description) english.description,
    ],
  );
}

/// Команды хоста для сочетания необязательных пунктов (D11) и языка: один
/// построитель вместо перебора сочетаний. Результат кэшируется, чтобы каталог
/// не получал новый список на каждое состояние рабочего места; язык входит в
/// ключ, иначе после смены языка вернулся бы старый (R1, D4).
///
/// Инвариант ключа: каталоги различаются по `localeName` (`en`, `ru`). Если
/// появятся региональные варианты (`ru_BY`), `localeName` перестанет быть
/// достаточным различителем — ключевать нужно по полному `Locale`.
final Map<String, List<HostCommand>> _hostCommandsCache = {};

List<HostCommand> _paletteHostCommandsOf(
  AppLocalizations l10n, {
  required bool files,
  required bool agents,
  required bool usage,
  required bool localRestart,
}) => _hostCommandsCache.putIfAbsent(
  '${l10n.localeName}|${files ? 1 : 0}${agents ? 1 : 0}${usage ? 1 : 0}'
  '|${localRestart ? 1 : 0}',
  () => List.unmodifiable([
    for (final action in CodeLabCommandAction.defaults)
      _hostCommandOf(action, l10n, localRestart: localRestart),
    if (files) _hostCommandOf(_filesAction, l10n, localRestart: localRestart),
    if (agents) _hostCommandOf(_agentsAction, l10n, localRestart: localRestart),
    if (usage) _hostCommandOf(_usageAction, l10n, localRestart: localRestart),
  ]),
);

/// Каталог палитры для команд агента активной сессии: команды app и
/// [agentCommands] с правилами kit (конфликты имён, поиск — D3, D4).
/// [filesAvailable] добавляет пункт «Files» (панель доступна, D7),
/// [agentsAvailable] — пункт «Agents» (у сессии есть субагенты, D49 Т11),
/// [usageAvailable] — пункт «Usage» (панель Usage доступна, D10, D11).
/// [localRestart] — агент локальный: пункт `reconnect` называется
/// «Restart agent». Команды агента не переводятся (D7).
CommandCatalog paletteCatalogOf(
  List<AgentCommandView> agentCommands, {
  required AppLocalizations l10n,
  bool filesAvailable = false,
  bool agentsAvailable = false,
  bool usageAvailable = false,
  bool localRestart = false,
}) => CommandCatalog(
  host: _paletteHostCommandsOf(
    l10n,
    files: filesAvailable,
    agents: agentsAvailable,
    usage: usageAvailable,
    localRestart: localRestart,
  ),
  agent: agentCommands,
);

/// Полный список палитры в порядке каталога.
List<CodeLabCommandAction> paletteActionsOf(CommandCatalog catalog) => [
  for (final command in catalog.commands) _paletteActionOf(command),
];

/// Команды палитры под запрос [query] в порядке поиска каталога.
List<CodeLabCommandAction> searchPaletteActions(
  CommandCatalog catalog,
  String query,
) => [for (final command in catalog.search(query)) _paletteActionOf(command)];

/// Строка палитры: значок, `/команда` и доступность — из действия по `id`,
/// подпись и описание — из команды хоста каталога (они уже на языке каталога).
/// `searchAliases` на экран не попадает.
CodeLabCommandAction _paletteActionOf(CatalogCommand command) =>
    switch (command) {
      HostCatalogCommand(:final command) =>
        (command.id == _filesAction.id
                ? _filesAction
                : command.id == _agentsAction.id
                ? _agentsAction
                : command.id == _usageAction.id
                ? _usageAction
                : CodeLabCommandAction.defaults.firstWhere(
                    (action) => action.id == command.id,
                  ))
            .copyWith(label: command.label, description: command.description),
      AgentCatalogCommand(:final command) => _agentCommandAction(command),
    };

/// Данные панели Agents из `SessionView` сессии в фокусе (D33, D49 Т8).
///
/// Почему здесь: строки считает kit (`SessionView.subagents`), а app только
/// связывает их с лентой: id вызова верхнего уровня → id его строки, id
/// элемента → ожидающее одобрение (для шагов дерева) и заголовки пунктов
/// плана для подсказок `#N`. Время не считается — оно зависит от часов виджета
/// (`agentRowsOf`).
///
/// `null` или сессия без субагентов дают [AgentsPaneData.empty]: панель
/// недоступна.
AgentsPaneData agentsPaneDataOf(SessionView? view) {
  if (view == null || view.subagents.isEmpty) {
    return AgentsPaneData.empty;
  }
  final topRowIds = <String, String>{};
  for (final (index, item) in view.transcript.indexed) {
    if (item is ToolCallItem) {
      topRowIds[item.id] = _toolRowIdOf(item, index);
    }
  }
  final pending = <String, String>{};
  void walk(List<TranscriptItem> items) {
    for (final item in items) {
      if (item is! ToolCallItem) {
        continue;
      }
      if (item.approval case PendingApprovalView(:final approvalId)) {
        pending[item.id] = approvalId.value;
      }
      walk(item.children);
    }
  }

  walk(view.transcript);
  return AgentsPaneData(
    rows: view.subagents,
    planTitles: {for (final entry in view.plan) ?entry.taskId: entry.content},
    busy:
        view.status == SessionStatusView.running ||
        view.status == SessionStatusView.cancelling,
    topRowIds: Map.unmodifiable(topRowIds),
    pendingApprovals: Map.unmodifiable(pending),
    counts: {
      for (final state in SubagentRowState.values)
        state: view.subagentCount(state),
    },
  );
}

/// Строки панели Agents: готовые тексты по данным [data] и часам [now].
///
/// Почему тексты здесь: `codelab_ui` ничего не форматирует
/// (`codelab_ui/AGENTS.md` §2), а формат берётся у kit — тот же, что у итога
/// в ленте (D24, D49 Т9, Т10).
///
/// Время: у терминальной строки — длительность из итога; у работающей —
/// `now − startedAt`, но только пока сессия занята, иначе времени нет и строка
/// просто `running` (D50 п. 2). Поля без данных остаются `null`: заглушек нет.
List<CodeLabAgentRow> agentRowsOf(
  AgentsPaneData data, {
  required DateTime now,
  required AppLocalizations l10n,
}) => [
  for (final row in data.rows)
    CodeLabAgentRow(
      id: row.toolCallId.value,
      depth: row.depth,
      type: row.type,
      title: row.title,
      state: _agentRowStateOf(row.state),
      time: _agentTimeOf(row, busy: data.busy, now: now),
      calls: row.toolCalls == null
          ? null
          : l10n.workbenchAgentRowToolCalls(row.toolCalls!),
      tokens: row.summary == null
          ? null
          : l10n.workbenchAgentRowTokens(row.summary!.tokensText),
      lastAction: row.lastAction,
      items: [
        for (final id in row.taskIds)
          CodeLabAgentItemRef(label: '#$id', hint: data.planTitles[id]),
      ],
    ),
];

String? _agentTimeOf(
  SubagentRowView row, {
  required bool busy,
  required DateTime now,
}) {
  if (row.summary case final summary?) {
    return summary.durationText;
  }
  final started = row.startedAt;
  final running =
      row.state == SubagentRowState.running ||
      row.state == SubagentRowState.awaitingApproval;
  if (!running || !busy || started == null) {
    return null;
  }
  final elapsed = now.difference(started);
  return formatSubagentDuration(elapsed.isNegative ? Duration.zero : elapsed);
}

/// Счётчики заголовка панели Agents по состояниям: числа считает kit
/// (`SessionView.subagentCount`), здесь только соответствие состояний kit
/// состояниям виджета — то же, что в [agentRowsOf]. Нулевые опускает сам
/// организм.
Map<CodeLabAgentRowState, int> agentCountsOf(AgentsPaneData data) => {
  for (final state in SubagentRowState.values)
    _agentRowStateOf(state): data.counts[state] ?? 0,
};

CodeLabAgentRowState _agentRowStateOf(SubagentRowState state) =>
    switch (state) {
      SubagentRowState.running => CodeLabAgentRowState.running,
      SubagentRowState.awaitingApproval =>
        CodeLabAgentRowState.waitingForApproval,
      SubagentRowState.completed => CodeLabAgentRowState.done,
      SubagentRowState.failed => CodeLabAgentRowState.failed,
      SubagentRowState.cancelled => CodeLabAgentRowState.cancelled,
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
            taskId: entry.taskId,
            ownerLabel: entry.ownerLabel,
            blockedBy: entry.openBlockers,
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
/// Один агент обслуживает сессии разных папок (`require-project-folder`, D11,
/// Q23): открытая сессия попадает в группу проекта с тем же путём. Папку
/// сессии даёт [sessionFolders] (`cwd` из `WorkspaceState`), а не подпись
/// строки. Группа не выбранного проекта раскрывается, пока в ней сессия идёт,
/// ждёт одобрения или упала: ход в `/work/a` остаётся виден со статусом после
/// перехода в `/work/b`. Сессии без своей группы остаются под выбранным
/// проектом; их `subtitle` — полный путь — показывает, откуда они.
///
/// Выбранный проект, которого нет среди недавних, всё равно идёт первой
/// группой; без выбранного проекта сессии попадают в группу «No project».
List<CodeLabSidebarProject> sidebarProjectsOf({
  required String? selectedProjectPath,
  required List<CodeLabSessionListItem> sessions,
  required List<CodeLabRecentProject> recentProjects,
  Map<String, String> sessionFolders = const {},
  required AppLocalizations l10n,
}) {
  final selected = selectedProjectPath;
  final otherPaths = {
    for (final recent in recentProjects)
      if (recent.path != selected) recent.path,
  };
  final byPath = <String, List<CodeLabSessionListItem>>{};
  final underSelected = <CodeLabSessionListItem>[];
  for (final session in sessions) {
    final folder = sessionFolders[session.id];
    if (folder != null && otherPaths.contains(folder)) {
      (byPath[folder] ??= []).add(session);
    } else {
      underSelected.add(session);
    }
  }
  bool attention(List<CodeLabSessionListItem> items) => items.any(
    (s) =>
        s.status == CodeLabSessionStatus.running ||
        s.status == CodeLabSessionStatus.awaitingApproval ||
        s.status == CodeLabSessionStatus.failed,
  );
  return [
    CodeLabSidebarProject(
      path: selected ?? '',
      name: selected == null
          ? l10n.workbenchNoProject
          : projectNameOf(selected),
      current: true,
      sessions: underSelected,
    ),
    for (final recent in recentProjects)
      if (recent.path != selected)
        CodeLabSidebarProject(
          path: recent.path,
          name: projectNameOf(recent.path),
          expanded: attention(byPath[recent.path] ?? const []),
          sessions: byPath[recent.path] ?? const [],
        ),
  ];
}

/// Значение опции режима для чипа шапки сессии — по категории `mode` из
/// ACP; без такой опции чипа нет (change `redesign-workbench-shell`, D7).
String? modeLabelOf(List<ConfigOptionView> options) =>
    _selectedLabelOf(options, 'mode');

/// Подпись модели для строки статуса — по категории `model` из ACP, тем же
/// правилом, что [modeLabelOf] (D23 Т1: имя выбранного значения, иначе
/// `currentValue`).
String? modelLabelOf(List<ConfigOptionView> options) =>
    _selectedLabelOf(options, 'model');

String? _selectedLabelOf(List<ConfigOptionView> options, String category) {
  for (final option in options) {
    if (option.category != category) {
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

/// Данные строки статуса под композером из `SessionView` (change
/// `add-usage-extension`, D11, D23 Т1; spec `agent-workbench-ui` «Строка
/// статуса сессии под композером»).
///
/// Почему: виджет `CodeLabSessionStatusBar` ничего не считает, а числа и
/// «~» — политика kit. Здесь только состав сегментов: числа форматирует
/// общая функция `usage_format.dart` (D24, Q16 (а)), своих правил формата и
/// суммирования у маппера нет.
///
/// Как использовать: `ActiveSessionCubit` зовёт при каждой ревизии
/// `SessionHandle.view`. `unknown` даёт «usage: —»; `awaiting` — только
/// индикатор во время хода; `reported` — токены хода, стоимость и контекст.
/// `busy` задан только для `awaiting` и пока ход идёт или отменяется
/// (`running`/`cancelling`, D23 Т9 п. 2): у `reported` числа
/// остаются на месте между шагами хода.
CodeLabSessionStatusData sessionStatusDataOf(
  SessionView view, {
  required AppLocalizations l10n,
}) {
  final usage = view.usage;
  final modelLabel = modelLabelOf(view.configOptions);
  final modeLabel = modeLabelOf(view.configOptions);
  switch (usage.support) {
    case UsageSupport.unknown:
      return CodeLabSessionStatusData(
        modelLabel: modelLabel,
        modeLabel: modeLabel,
        usage: CodeLabStatusSegment(
          label: l10n.workbenchStatusUsageUnknown,
          tooltip: l10n.workbenchStatusUsageUnknownTooltip,
        ),
      );
    case UsageSupport.awaiting:
      return CodeLabSessionStatusData(
        modelLabel: modelLabel,
        modeLabel: modeLabel,
        busy:
            view.status == SessionStatusView.running ||
            view.status == SessionStatusView.cancelling,
      );
    case UsageSupport.reported:
      return CodeLabSessionStatusData(
        modelLabel: modelLabel,
        modeLabel: modeLabel,
        usage: _usageSegmentOf(usage.lastTurn, l10n),
        cost: _costSegmentOf(usage.lastTurn, usage.session, l10n),
        context: _contextSegmentOf(usage.context, l10n),
      );
  }
}

/// Токены хода: `<вход> → <выход>`, вход = `input + cacheRead + cacheWrite`
/// (D11). Подсказка — пять счётчиков точными числами и причины неполноты.
/// Нулевые токены хода (`0 → 0`) сегмент не рисуют (D23 Т9 п. 4):
/// ноль вместо «ничего не пришло» вводил бы в заблуждение.
CodeLabStatusSegment? _usageSegmentOf(
  UsageTotals? turn,
  AppLocalizations l10n,
) {
  if (turn == null) {
    return null;
  }
  final tokens = turn.tokens;
  final input = usageInputTokens(tokens);
  if (input == 0 && tokens.output == 0) {
    return null;
  }
  final mark = usageTokensPartial(turn.partial) ? '~' : '';
  final lines = [
    l10n.workbenchStatusTokenInput(tokens.input),
    l10n.workbenchStatusTokenOutput(tokens.output),
    l10n.workbenchStatusTokenCacheRead(tokens.cacheRead),
    l10n.workbenchStatusTokenCacheWrite(tokens.cacheWrite),
    if (tokens.reasoning case final reasoning?)
      l10n.workbenchStatusTokenReasoning(reasoning),
  ];
  final reasons = [
    for (final reason in UsagePartial.values)
      if (turn.partial.contains(reason)) partialReasonTextOf(reason, l10n),
  ];
  return CodeLabStatusSegment(
    label:
        '$mark${formatUsageTokens(input)} → '
        '${formatUsageTokens(tokens.output)}',
    tooltip: [
      lines.join(' · '),
      if (reasons.isNotEmpty)
        l10n.workbenchStatusApproximate(reasons.join(', ')),
    ].join('\n'),
  );
}

/// Причина неполной суммы расхода на языке [l10n]: общая для строки статуса и
/// карточки стоимости панели Usage.
String partialReasonTextOf(UsagePartial reason, AppLocalizations l10n) =>
    switch (reason) {
      UsagePartial.noUsage => l10n.usagePartialNoUsage,
      UsagePartial.noPrice => l10n.usagePartialNoPrice,
      UsagePartial.beforeLoad => l10n.usagePartialBeforeLoad,
    };

/// `<стоимость хода> · session <стоимость сессии>` (D11, Q19 (а)); «~» — по
/// правилу kit перед суммой, чья полнота под вопросом (D6).
CodeLabStatusSegment? _costSegmentOf(
  UsageTotals? turn,
  UsageTotals? session,
  AppLocalizations l10n,
) {
  final turnCost = turn?.cost;
  final sessionCost = session?.cost;
  if (turnCost == null && sessionCost == null) {
    return turn == null
        ? null
        : CodeLabStatusSegment(
            label: '—',
            tooltip: l10n.workbenchStatusPriceUnknown,
          );
  }
  final turnText = turnCost == null
      ? '—'
      : '${usageCostPartial(turn!.partial) ? '~' : ''}'
            '${formatUsageMoney(turnCost)}';
  if (sessionCost == null) {
    return CodeLabStatusSegment(label: turnText);
  }
  final mark = usageCostPartial(session!.partial) ? '~' : '';
  return CodeLabStatusSegment(
    label: l10n.workbenchStatusCostWithSession(
      turnText,
      '$mark${formatUsageMoney(sessionCost)}',
    ),
  );
}

/// `<N>% context[ · compaction soon]`; тон — по уровню kit (D24, Q17 (а)).
CodeLabStatusSegment? _contextSegmentOf(
  ContextFillView? context,
  AppLocalizations l10n,
) {
  if (context == null) {
    return null;
  }
  final fill = usageContextOf(context);
  if (fill == null) {
    return null;
  }
  return CodeLabStatusSegment(
    label: context.compactionSoon
        ? l10n.workbenchStatusContextCompactionSoon(fill.label)
        : l10n.workbenchStatusContext(fill.label),
    tone: switch (fill.level) {
      UsageLevel.normal => CodeLabTone.neutral,
      UsageLevel.warning => CodeLabTone.warning,
      UsageLevel.danger => CodeLabTone.danger,
    },
  );
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
