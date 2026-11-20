import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        AgentCommandView,
        ApprovalWaitView,
        ClientWorkspace,
        ClientWorkspaceException,
        Connected,
        InspectorProjection,
        PendingApprovalView,
        PromptOutcome,
        PromptQueued,
        SessionHandle,
        SessionStatusView,
        SessionView,
        ToolCallItem,
        TranscriptItem,
        UsageLedgerIdle,
        UsageLedgerState,
        UsageView;
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_ui/codelab_ui.dart';

import '../../../app/language/app_language_cubit.dart' show AppStrings;
import '../../../core/platform/usage_csv_saver.dart';
import '../../../l10n/app_localizations.dart';
import '../../usage/application/ledger_refresh.dart';
import '../../usage/application/usage_csv.dart';
import '../../usage/application/usage_pane_data.dart';
import 'agents_pane_data.dart';
import 'shell_part.dart';
import 'approval_shortcut_decision.dart';
import 'ui_mappers.dart';

/// Показываемая сессия: лента, инспектор, очередь, одобрения, опции, план.
final class ActiveSessionState {
  const ActiveSessionState({
    this.sessionId,
    this.transcriptRows = const [],
    this.inspectorEntries = const [_emptyInspectorEntry],
    this.agentCommands = const [],
    this.agentCommandViews = const [],
    this.configOptions = const [],
    this.currentPlan,
    this.agents = AgentsPaneData.empty,
    this.queuedPrompts = const [],
    this.composerDraft = '',
    this.composerDraftRevision = 0,
    this.isPromptSubmitting = false,
    this.canCancel = false,
    this.isRespondingToApproval = false,
    this.isRespondingToConfigOption = false,
    this.sessionMode,
    this.turnState,
    this.statusBar,
    this.usage = UsagePaneData.empty,
  });

  static const _emptyInspectorEntry = CodeLabInspectorEntry(
    id: 'inspector-empty',
    category: CodeLabInspectorCategory.protocol,
    title: 'Protocol log',
    summary: 'Start a session to inspect ACP activity.',
  );

  /// Сессия, которую сейчас показывает рабочее место; совпадает с
  /// `SessionsState.activeSessionId`: обе части меняются одним пакетом.
  final String? sessionId;
  final List<CodeLabTranscriptRow> transcriptRows;
  final List<CodeLabInspectorEntry> inspectorEntries;

  /// Команды агента из последнего `available_commands_update`.
  final List<CodeLabCommandAction> agentCommands;

  /// Те же команды в форме kit — вход каталога палитры (`paletteCatalogOf`).
  final List<AgentCommandView> agentCommandViews;
  final List<CodeLabConfigOption> configOptions;

  /// План сессии; `null` — плана не было или пользователь его скрыл.
  final List<CodeLabPlanEntry>? currentPlan;

  /// Данные панели Agents: строки kit и связь с лентой (D33, D49 Т8);
  /// пусто — у сессии нет субагентов, панель недоступна.
  final AgentsPaneData agents;

  /// Очередь показываемой сессии; очередь фоновой сессии живёт в kit
  /// невидимо, пока её не выберут (add-multi-session-concurrency/design.md).
  final List<CodeLabQueuedPrompt> queuedPrompts;

  /// Текст для композера: `/{name} ` выбранной команды агента или
  /// возвращённый из очереди промпт. `CodeLabPromptComposer.initialPrompt`
  /// применяет его только при изменении значения.
  final String composerDraft;

  /// Растёт при каждой подстановке черновика: повторная вставка того же
  /// текста тоже доходит до композера (`CodeLabPromptComposer.draftRevision`).
  final int composerDraftRevision;

  /// Флаги совместимости из `SessionView.status` (design D4).
  final bool isPromptSubmitting;
  final bool canCancel;

  /// Защита от второго ответа на одобрение и второго
  /// `session/set_config_option`, пока первый в полёте. Глобальны для окна и
  /// сбрасываются при потере соединения (design D4).
  final bool isRespondingToApproval;
  final bool isRespondingToConfigOption;

  /// Режим сессии из опции категории `mode` — чип шапки сессии (change
  /// `redesign-workbench-shell`, D7); `null` — агент режим не публикует.
  final String? sessionMode;

  /// Чип состояния хода в шапке панели сессии; `null` — сессия свободна
  /// (требование «Session pane header», change `redesign-transcript-rows`).
  final CodeLabTurnState? turnState;

  /// Данные строки статуса под композером (change `add-usage-extension`,
  /// D11, D23 Т1); `null` — нет `SessionView` показываемой сессии, строки нет.
  final CodeLabSessionStatusData? statusBar;

  /// Данные панели Usage сессии в фокусе (change `add-desktop-usage-pane`,
  /// D1): собираются в той же подписке `_onView`, что и [statusBar].
  final UsagePaneData usage;

  static const Object _unset = Object();

  ActiveSessionState _copyWith({
    String? sessionId,
    List<CodeLabTranscriptRow>? transcriptRows,
    List<CodeLabInspectorEntry>? inspectorEntries,
    List<CodeLabCommandAction>? agentCommands,
    List<AgentCommandView>? agentCommandViews,
    List<CodeLabConfigOption>? configOptions,
    Object? currentPlan = _unset,
    AgentsPaneData? agents,
    List<CodeLabQueuedPrompt>? queuedPrompts,
    String? composerDraft,
    int? composerDraftRevision,
    bool? isPromptSubmitting,
    bool? canCancel,
    bool? isRespondingToApproval,
    bool? isRespondingToConfigOption,
    Object? sessionMode = _unset,
    Object? turnState = _unset,
    Object? statusBar = _unset,
    UsagePaneData? usage,
  }) => ActiveSessionState(
    sessionId: sessionId ?? this.sessionId,
    transcriptRows: transcriptRows ?? this.transcriptRows,
    inspectorEntries: inspectorEntries ?? this.inspectorEntries,
    agentCommands: agentCommands ?? this.agentCommands,
    agentCommandViews: agentCommandViews ?? this.agentCommandViews,
    configOptions: configOptions ?? this.configOptions,
    // `null` здесь — «скрыть план», а не «не менять».
    currentPlan: identical(currentPlan, _unset)
        ? this.currentPlan
        : currentPlan as List<CodeLabPlanEntry>?,
    agents: agents ?? this.agents,
    queuedPrompts: queuedPrompts ?? this.queuedPrompts,
    composerDraft: composerDraft ?? this.composerDraft,
    composerDraftRevision: composerDraftRevision ?? this.composerDraftRevision,
    isPromptSubmitting: isPromptSubmitting ?? this.isPromptSubmitting,
    canCancel: canCancel ?? this.canCancel,
    isRespondingToApproval:
        isRespondingToApproval ?? this.isRespondingToApproval,
    isRespondingToConfigOption:
        isRespondingToConfigOption ?? this.isRespondingToConfigOption,
    sessionMode: identical(sessionMode, _unset)
        ? this.sessionMode
        : sessionMode as String?,
    turnState: identical(turnState, _unset)
        ? this.turnState
        : turnState as CodeLabTurnState?,
    statusBar: identical(statusBar, _unset)
        ? this.statusBar
        : statusBar as CodeLabSessionStatusData?,
    usage: usage ?? this.usage,
  );
}

/// Показываемая сессия рабочего места и действия пользователя в ней.
///
/// Почему: логика сессии — очередь, отмена, одобрения, опции, проекции
/// ленты и инспектора — уже в `codelab_client_core` (итерации 3–6 change
/// `extract-acp-client-kit`); здесь остаётся отображение в модели `codelab_ui`
/// и флаги окна (design D10).
///
/// Для чего: владелец ленты, инспектора, очереди, плана и опций
/// показываемой сессии; промпты, отмена, ответы на одобрения и выбор опций
/// идут через `SessionHandle` kit.
///
/// Как использовать: какую сессию показывать, решает `SessionsCubit` — он
/// вызывает [show], [showCreated] или [showMissing] в одном пакете со своим
/// изменением. Диагностику исходов хода, отмены и ответов пишет kit.
///
/// Язык (`add-desktop-localization`, D5): текст ленты (заметки, метки вызовов)
/// и строки статуса — функция `(снимок сессии, SessionView, язык)`. Язык
/// читается из [AppStrings] только внутри проекции; по `AppStrings.changes`
/// лента и строка статуса пересобираются из последних входов, а данные панели
/// Usage остаются языконезависимыми (их текст собирает presentation, D5 п. 4).
/// Подписка одна: создаётся в конструкторе, отменяется в `close()` и не
/// зависит от смены сессии.
final class ActiveSessionCubit extends ShellPartCubit<ActiveSessionState> {
  ActiveSessionCubit({
    required super.changes,
    required ClientWorkspace workspace,
    required ShellDiagnostics diagnostics,
    required UsageCsvSaver usageCsvSaver,
    required AppStrings strings,
    Logger? usageLogger,
    Logger? approvalLogger,
    DateTime Function()? clock,
    DateTime Function()? wallClock,
  }) : _workspace = workspace,
       _diagnostics = diagnostics,
       _usageCsvSaver = usageCsvSaver,
       _strings = strings,
       _usageLogger = usageLogger,
       _approvalLogger = approvalLogger,
       _clock = clock ?? DateTime.now,
       _wallClock = wallClock ?? clock ?? DateTime.now,
       super(const ActiveSessionState()) {
    activation = ApprovalActivationTracker(clock: _clock);
    _languageSubscription = strings.changes.listen(_handleLanguage);
    // Исход хода любой сессии — отправленного отсюда и ушедшего из очереди
    // kit: очередь могла сдвинуться.
    _outcomeSubscription = _workspace.promptOutcomes.listen(
      (outcome) => _syncQueue(outcome.sessionId.value),
    );
  }

  final ClientWorkspace _workspace;
  final ShellDiagnostics _diagnostics;
  final AppStrings _strings;
  late final StreamSubscription<AppLocalizations> _languageSubscription;

  AppLocalizations get _l10n => _strings.current;

  /// Порт сохранения CSV панели Usage (D5); `app_scope` привязывает его
  /// всегда, тесты передают двойник.
  final UsageCsvSaver _usageCsvSaver;

  /// События `usage_pane.refresh` и `usage_pane.export` (D13): логгер
  /// `codelab_desktop.usage`; без секретов, путей, подписей и чисел.
  final Logger? _usageLogger;

  /// События `workbench.approval_answer` и
  /// `workbench.approval_shortcut_skipped` (D9, D14): без сырых аргументов,
  /// команды, заголовка и подписей вариантов агента.
  final Logger? _approvalLogger;
  final DateTime Function() _clock;

  /// Время стены для имени CSV; отсчёты задержек идут по [_clock] (монотонным).
  final DateTime Function() _wallClock;

  /// Момент, с которого активное одобрение показанной сессии стало активным
  /// (D14, п. 2). Владелец — этот Cubit: он сообщает трекеру каждый снимок
  /// показанной сессии; решение по сочетанию (`CodeLabShellCubit`) только
  /// читает его и после показа невидимой полосы перезапускает отсчёт.
  late final ApprovalActivationTracker activation;
  late final StreamSubscription<PromptOutcome> _outcomeSubscription;
  StreamSubscription<SessionView>? _viewSubscription;
  SessionHandle? _watchedHandle;

  /// Последний показанный снимок: по нему лента перестраивается при потере
  /// соединения, чтобы убрать Retry (design D4 change
  /// `add-connection-and-error-states`).
  AcpSession? _shown;

  /// Показывает [session] по её живому снимку в ядре и `SessionView` kit.
  ///
  /// `SessionView` к этому моменту уже обновлён: рабочее пространство
  /// подписано на `sessionChanges` раньше части сессий (design D6).
  void show(AcpSession session) {
    final id = session.id.value;
    final view = _handle(id)?.current;
    _shown = session;
    activation.observe(view);
    emit(
      state._copyWith(
        sessionId: id,
        transcriptRows: _rowsOf(session, view),
        inspectorEntries: const InspectorProjection().project(session),
        agentCommands: agentCommandsOf(view?.agentCommands ?? const []),
        agentCommandViews: view?.agentCommands ?? const [],
        configOptions: configOptionsOf(view?.configOptions ?? const []),
        sessionMode: modeLabelOf(view?.configOptions ?? const []),
        currentPlan: planEntriesOf(view?.plan ?? const []),
        agents: agentsPaneDataOf(view),
        queuedPrompts: _queueOf(id),
        isPromptSubmitting: _isBusy(view?.status),
        canCancel: view?.status == SessionStatusView.running,
        turnState: turnStateOf(view),
        statusBar: view == null ? null : sessionStatusDataOf(view, l10n: _l10n),
        usage: _usageOf(id, view, session.cwd),
      ),
    );
    _watchView(id);
    if (view != null) {
      _refreshLedgerIfNeeded(id, view, reason: 'seq');
    }
  }

  /// Показывает только что созданную сессию: лента пуста, ход не идёт.
  void showCreated(AcpSession session) {
    final id = session.id.value;
    _shown = session;
    final view = _handle(id)?.current;
    activation.observe(view);
    emit(
      state._copyWith(
        sessionId: id,
        transcriptRows: const [],
        inspectorEntries: const InspectorProjection().project(session),
        agentCommands: agentCommandsOf(view?.agentCommands ?? const []),
        agentCommandViews: view?.agentCommands ?? const [],
        configOptions: configOptionsOf(view?.configOptions ?? const []),
        sessionMode: modeLabelOf(view?.configOptions ?? const []),
        currentPlan: planEntriesOf(view?.plan ?? const []),
        agents: agentsPaneDataOf(view),
        queuedPrompts: _queueOf(id),
        isPromptSubmitting: false,
        canCancel: false,
        turnState: null,
        statusBar: view == null ? null : sessionStatusDataOf(view, l10n: _l10n),
        usage: _usageOf(id, view, session.cwd),
      ),
    );
    _watchView(id);
    if (view != null) {
      _refreshLedgerIfNeeded(id, view, reason: 'seq');
    }
  }

  /// Строки ленты [session] по её `SessionView`.
  ///
  /// Единственное место сборки ленты: [show] и смена языка ([_handleLanguage])
  /// строят её одинаково, поэтому после смены языка лента равна ленте, которую
  /// построил бы новый `session/update` (D5 п. 1).
  ///
  /// [approvalsEnabled] — переопределение доступности кнопок одобрений для
  /// кадра, который выставляет и признак ответа, и ленту одним `emit`; без него
  /// берётся текущее состояние.
  List<CodeLabTranscriptRow> _rowsOf(
    AcpSession session,
    SessionView? view, {
    bool? approvalsEnabled,
  }) {
    // Соединение kit в `canRetry` не учитывает — его проверяет хост
    // (design D4 change `add-connection-and-error-states`).
    final canRetry =
        view != null &&
        view.canRetry &&
        _workspace.current.connection is Connected;
    return transcriptRowsOf(
      view?.transcript ?? const [],
      cwd: session.cwd,
      isRunning: view?.status == SessionStatusView.running,
      approvalsEnabled: approvalsEnabled ?? !state.isRespondingToApproval,
      onApprovalSelected: _onApprovalSelected,
      onRetry: canRetry ? () => unawaited(retryTurn()) : null,
      l10n: _l10n,
    );
  }

  /// Смена языка: лента и строка статуса пересобираются из последнего
  /// снимка и `SessionView` показываемой сессии; остальное состояние (ввод,
  /// очередь, одобрения в полёте) не трогается. После `close` событие
  /// игнорируется (D5 п. 3).
  void _handleLanguage(AppLocalizations l10n) {
    if (isClosed) return;
    final id = state.sessionId;
    if (id == null) return;
    final view = _handle(id)?.current;
    final shown = _shown;
    emit(
      state._copyWith(
        transcriptRows: shown != null && shown.id.value == id
            ? _rowsOf(shown, view)
            : null,
        statusBar: view == null
            ? state.statusBar
            : sessionStatusDataOf(view, l10n: l10n),
      ),
    );
  }

  /// Выбрана сессия, которой нет в ядре клиента: показывать нечего, кроме
  /// её очереди.
  void showMissing(String sessionId) {
    emit(
      state._copyWith(
        sessionId: sessionId,
        transcriptRows: const [],
        inspectorEntries: const [],
        agentCommands: const [],
        agentCommandViews: const [],
        configOptions: const [],
        sessionMode: null,
        currentPlan: null,
        agents: AgentsPaneData.empty,
        queuedPrompts: _queueOf(sessionId),
        isPromptSubmitting: false,
        canCancel: false,
        turnState: null,
        statusBar: null,
        usage: _usageOf(sessionId, null, ''),
      ),
    );
    _watchView(null);
  }

  /// Неожиданная потеря соединения: ход не идёт, запросы в полёте ядро уже
  /// не завершит — их флаги сбрасываются здесь (design D4).
  void resetAfterConnectionLoss() {
    // Без соединения повторять нечем: лента перестраивается без Retry —
    // до сброса флагов, иначе снимок идущего хода вернул бы их обратно.
    if (_shown case final session? when session.id.value == state.sessionId) {
      show(session);
    }
    emit(
      state._copyWith(
        isPromptSubmitting: false,
        canCancel: false,
        turnState: null,
        isRespondingToApproval: false,
        isRespondingToConfigOption: false,
      ),
    );
  }

  /// Повторяет последний сорвавшийся ход показываемой сессии тем же
  /// промптом (spec `agent-workbench-ui` «Failed turn notice with Retry»).
  ///
  /// Новый ход и его исход приходят из `sessionChanges` и диагностики kit;
  /// здесь — только отказ kit, если повтор стал невозможен между показом
  /// кнопки и нажатием.
  Future<void> retryTurn() async {
    final sessionId = state.sessionId;
    final handle = sessionId == null ? null : _handle(sessionId);
    if (handle == null) {
      return;
    }
    try {
      await handle.retry();
    } on ClientWorkspaceException catch (error) {
      _diagnostics.record(
        'Failed to retry prompt turn: ${error.message}',
        severity: DiagnosticSeverity.warning,
        source: 'prompt',
      );
    }
  }

  Future<void> submitPrompt(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty) {
      return;
    }

    final sessionId = state.sessionId;
    if (sessionId == null) {
      _diagnostics.record(
        'Create or select a session before sending a prompt.',
        severity: DiagnosticSeverity.warning,
        source: 'prompt',
      );
      return;
    }
    final handle = _handle(sessionId);
    if (handle == null) {
      _diagnostics.record(
        'Failed to send prompt: ACP session $sessionId is not open.',
        severity: DiagnosticSeverity.error,
        source: 'prompt',
      );
      return;
    }

    // Kit сам решает, отправить сразу или поставить в очередь занятой
    // сессии, и сливает очередь после конца хода (design D7). Исход хода
    // сообщают `promptOutcomes` и диагностика kit.
    final outcome = await handle.send(text);
    if (outcome is PromptQueued) {
      _syncQueue(sessionId);
    }
  }

  /// Убирает [id] из очереди и сразу возвращает его текст в композер, чтобы
  /// текст не жил в двух местах (add-prompt-queue/design.md, Decisions).
  void editQueuedPrompt(String id) {
    final sessionId = state.sessionId;
    final prompt = sessionId == null
        ? null
        : _handle(sessionId)?.queue.remove(id);
    if (prompt == null) {
      return;
    }
    emit(
      state._copyWith(
        queuedPrompts: _queueOf(sessionId!),
        composerDraft: prompt.text,
        composerDraftRevision: state.composerDraftRevision + 1,
      ),
    );
  }

  void deleteQueuedPrompt(String id) {
    final sessionId = state.sessionId;
    if (sessionId == null) {
      return;
    }
    _handle(sessionId)?.queue.remove(id);
    _syncQueue(sessionId);
  }

  /// Отправляет [id] вне очереди, если сессия свободна; у занятой сессии
  /// элемент остаётся на месте (ожидаемая гонка, add-prompt-queue/design.md).
  Future<void> sendQueuedPromptNow(String id) async {
    final sessionId = state.sessionId;
    final handle = sessionId == null ? null : _handle(sessionId);
    if (handle == null) {
      return;
    }
    final sending = handle.queue.sendNow(id);
    _syncQueue(sessionId!);
    await sending;
  }

  void clearQueuedPrompts() {
    final sessionId = state.sessionId;
    if (sessionId == null) {
      return;
    }
    _handle(sessionId)?.queue.clear();
    _syncQueue(sessionId);
  }

  /// Отмена хода показываемой сессии.
  ///
  /// Флаги и ленту здесь не трогаем: отмена меняет статус сессии в ядре, и
  /// новое состояние приходит из `sessionChanges`. Итог отмены пишет
  /// диагностика kit; очередь kit сливает после ответа агента.
  Future<void> cancelTurn() async {
    final sessionId = state.sessionId;
    if (sessionId == null) {
      _diagnostics.record(
        'Select a session before cancelling a prompt turn.',
        severity: DiagnosticSeverity.warning,
        source: 'prompt',
      );
      return;
    }
    try {
      await _handle(sessionId)?.cancel();
    } on Object {
      return;
    }
  }

  /// Отвечает на одобрение [approvalId] сессии [sessionId] вариантом
  /// [optionId] — в том числе отказом: в ACP отказ — тоже выбор варианта.
  ///
  /// Вызывающий передаёт identity конкретного одобрения из записи ленты, а
  /// не «текущее» одобрение окна, поэтому поздний нажатый вариант не решит
  /// другой вызов (PERM-003, `docs/architecture/permissions.md`). Решение
  /// появляется в ленте из следующего `sessionChanges`; итог ответа пишет
  /// диагностика kit.
  Future<void> respondToApproval({
    required ApprovalRequestId approvalId,
    required SessionId sessionId,
    required String optionId,
    ApprovalAnswerSource source = ApprovalAnswerSource.button,
  }) async {
    if (state.isRespondingToApproval) {
      return;
    }
    final handle = _workspace.session(sessionId);
    if (handle == null) {
      return;
    }
    _logApprovalAnswer(handle, approvalId, optionId, source);

    emit(state._copyWith(isRespondingToApproval: true));
    try {
      await handle.respond(approvalId, PermissionOptionId(optionId));
    } on Object {
      // Ошибка уже записана диагностикой kit.
    }
    if (isClosed) return;
    // Кнопки других одобрений гасились на время ответа (`approvalsEnabled`),
    // а лента пересобирается только по `sessionChanges`. Если после ответа
    // нового кадра нет, оставшееся одобрение так и осталось бы выключенным и
    // не отвечало бы на сочетание: лента пересобирается здесь же
    // (`fix-approval-focus`, design.md, D4, п. 4).
    // Один `emit`: два подряд дали бы промежуточный кадр с включёнными
    // кнопками и старой лентой.
    final id = state.sessionId;
    final shown = _shown;
    final rows = id != null && shown != null && shown.id.value == id
        ? _rowsOf(shown, _handle(id)?.current, approvalsEnabled: true)
        : state.transcriptRows;
    emit(state._copyWith(isRespondingToApproval: false, transcriptRows: rows));
  }

  /// Пишет `workbench.approval_answer` (D9): каждый ответ с рабочего места —
  /// кнопкой или сочетанием — с источником решения. Поля: `session_id`,
  /// `request_id`, `tool_call_id`, `kind`, `source`; сырых данных вызова нет.
  void _logApprovalAnswer(
    SessionHandle handle,
    ApprovalRequestId approvalId,
    String optionId,
    ApprovalAnswerSource source,
  ) {
    final logger = _approvalLogger;
    if (logger == null) {
      return;
    }
    PendingApprovalView? approval;
    for (final candidate in handle.current.pendingApprovals) {
      if (candidate.approvalId == approvalId) {
        approval = candidate;
      }
    }
    String? kind;
    for (final option in approval?.options ?? const <PermissionOption>[]) {
      if (option.optionId.value == optionId) {
        kind = option.kind.wireName;
      }
    }
    logger.info(
      'workbench.approval_answer',
      context: {
        'session_id': handle.id.value,
        'request_id': approvalId.value,
        'tool_call_id': ?_toolCallIdOf(handle.id.value, approvalId),
        'kind': ?kind,
        'source': source.wireName,
      },
    );
  }

  /// `tool_call_id` запроса [approvalId] показанной сессии для журнала;
  /// `null`, если сессия не показана или запроса нет.
  String? _toolCallIdOf(String sessionId, ApprovalRequestId approvalId) {
    final shown = _shown;
    if (shown == null || shown.id.value != sessionId) {
      return null;
    }
    for (final turn in shown.turns) {
      final request = turn.approvals[approvalId];
      if (request != null) {
        return request.toolCall.id.value;
      }
    }
    return null;
  }

  /// Пишет `workbench.approval_shortcut_skipped` (D9): нажатие сочетания
  /// ответа, не давшее ответа. `request_id` — только если цель есть.
  void logApprovalShortcutSkipped(ApprovalShortcutSkipped skipped) {
    _approvalLogger?.info(
      'workbench.approval_shortcut_skipped',
      context: {
        'session_id': ?skipped.sessionId,
        'request_id': ?skipped.approvalId?.value,
        'reason': skipped.reason.wireName,
      },
    );
  }

  /// Отправляет агенту выбор [value] опции [configId]. Показанные опции
  /// берутся из следующего `sessionChanges`, а не выставляются заранее.
  Future<void> setSessionConfigOption(String configId, String value) async {
    final sessionId = state.sessionId;
    final handle = sessionId == null ? null : _handle(sessionId);
    if (handle == null || state.isRespondingToConfigOption) {
      return;
    }

    emit(state._copyWith(isRespondingToConfigOption: true));
    try {
      await handle.setConfigOption(configId, value);
    } on Object {
      // Ошибка уже записана диагностикой kit.
    }
    if (isClosed) return;
    emit(state._copyWith(isRespondingToConfigOption: false));
  }

  /// Скрывает план на стороне клиента; агенту ничего не отправляется, а
  /// следующий `SessionUpdate.plan` показывает план снова
  /// (add-plan-progress-checklist/design.md, Decisions).
  void dismissPlan() => emit(state._copyWith(currentPlan: null));

  /// Кладёт [text] в композер (выбор команды агента в палитре).
  void setComposerDraft(String text) => emit(
    state._copyWith(
      composerDraft: text,
      composerDraftRevision: state.composerDraftRevision + 1,
    ),
  );

  /// Подписка на `SessionHandle.view` показываемой сессии (D23 Т1).
  ///
  /// Почему: снимок usage меняет только `SessionView` (`revision + 1` без
  /// нового `AcpSession`, D21 Т4), а [show] вызывают лишь `sessionChanges`
  /// ядра; без подписки строка статуса обновлялась бы со следующим
  /// `session/update` или концом хода. Подписка пересчитывает только данные
  /// строки, не перестраивая ленту.
  ///
  /// Владелец подписки — этот Cubit (как `_outcomeSubscription`,
  /// `AGENTS.md` §9): одна подписка, переподписка при смене сессии или
  /// её handle, отмена в [showMissing] и [close]. Повторный [show] той же
  /// сессии подписку не пересоздаёт — он идёт на каждое `session/update`.
  void _watchView(String? sessionId) {
    final handle = sessionId == null ? null : _handle(sessionId);
    if (identical(handle, _watchedHandle)) {
      return;
    }
    unawaited(_viewSubscription?.cancel());
    _watchedHandle = handle;
    _viewSubscription = handle?.view.listen(
      (view) => _onView(handle.id.value, view),
    );
  }

  /// Панель Usage показана или скрыта (вкладка активна и док виден): сигнал
  /// виджета `WorkbenchUsagePane` из `initState` (`true`) и `dispose`
  /// (`false`); экземпляры считаются, показана — пока их больше нуля (design.md
  /// change `add-desktop-usage-pane`, D1, D3). Показ запускает автоматический
  /// запрос журнала по правилу `ledgerRefreshNeeded`.
  ///
  /// Почему здесь, а не в виджете: правило «когда обновлять» — политика
  /// application, а Cubit уже держит единственную подписку на
  /// `SessionHandle.view` (`AGENTS.md` §9).
  void usagePaneShown(bool shown) {
    final before = _usagePaneInstances;
    _usagePaneInstances = shown ? before + 1 : (before > 0 ? before - 1 : 0);
    // Автозапрос только при появлении первого экземпляра: пока смонтирован
    // хотя бы один, панель показана.
    if (!shown || before > 0) {
      return;
    }
    final id = state.sessionId;
    final view = id == null ? null : _handle(id)?.current;
    if (id != null && view != null) {
      _refreshLedgerIfNeeded(id, view, reason: 'shown');
    }
  }

  /// Запрашивает журнал usage показываемой сессии вне автоматического
  /// правила: `Retry` панели (`rebuild: false`, причина `retry`) и
  /// `Rebuild from log` (`rebuild: true`, причина `manual`) — D3. Слияние с
  /// идущим запросом и защиту от поздних ответов делает kit.
  Future<void> refreshUsageLedger({bool rebuild = false}) async {
    final id = state.sessionId;
    if (id == null || _handle(id) == null) {
      return;
    }
    await _requestLedger(
      id,
      rebuild: rebuild,
      reason: rebuild ? 'manual' : 'retry',
    );
  }

  /// Сохраняет CSV журнала, показанного в панели (D5): строит его
  /// `buildUsageCsv`, предлагает имя `codelab-usage-<sessionId>-<дата>.csv`
  /// и отдаёт порту. Отказ в диалоге — [UsageCsvCancelled] без заметки; сбой
  /// порта или записи — [UsageCsvFailed] с классом ошибки.
  ///
  /// В журнал идёт `usage_pane.export` с исходом (`saved`, `cancelled`,
  /// `failed` + `error_class`) и числом ходов и шагов: путь, подписи, токены
  /// и деньги в запись не попадают (D13, `AGENTS.md` §16). Отказ в диалоге
  /// тоже событие: это решение пользователя, а не отсутствие действия.
  ///
  /// Без события возвращается [UsageCsvCancelled] только когда экспортировать
  /// нечего (нет сессии или журнала; кнопка в этом состоянии скрыта): порт
  /// не вызывался, диалога не было, значит, и исхода для журнала нет.
  Future<UsageCsvSaveResult> exportUsageCsv() async {
    final id = state.sessionId;
    final data = state.usage;
    final ledger = data.ledger;
    if (id == null || !data.canExport || ledger == null) {
      return const UsageCsvCancelled();
    }
    UsageCsvSaveResult result;
    try {
      result = await _usageCsvSaver.save(
        suggestedName: _csvNameOf(id, _wallClock()),
        csv: buildUsageCsv(data),
      );
    } on Object catch (error) {
      // Порт обязан возвращать UsageCsvFailed; непредвиденное исключение
      // не должно терять класс ошибки и ронять панель.
      result = UsageCsvFailed(error.runtimeType.toString());
    }
    _usageLogger?.info(
      'usage_pane.export',
      context: {
        'outcome': result.outcome,
        'turns': ledger.turns.length,
        'steps': ledger.turns.fold<int>(0, (n, turn) => n + turn.steps.length),
        if (result case UsageCsvFailed(:final errorClass))
          'error_class': errorClass,
      },
    );
    return result;
  }

  /// `codelab-usage-<первые 8 символов sessionId>-<yyyyMMdd-HHmm>.csv`; id
  /// сессии приходит от агента, поэтому в имени остаются только безопасные
  /// символы.
  static String _csvNameOf(String sessionId, DateTime now) {
    final safe = sessionId
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')
        .padRight(1, '_');
    final short = safe.length > 8 ? safe.substring(0, 8) : safe;
    String two(int value) => value.toString().padLeft(2, '0');
    final date =
        '${now.year.toString().padLeft(4, '0')}${two(now.month)}${two(now.day)}';
    return 'codelab-usage-$short-$date-${two(now.hour)}${two(now.minute)}.csv';
  }

  /// Число смонтированных экземпляров `WorkbenchUsagePane` (сигнал
  /// [usagePaneShown]); `> 0` — панель показана. Счётчик, а не флаг: при
  /// пересборке дока `initState` нового экземпляра может прийти раньше
  /// `dispose` старого, и флаг «погас» бы, хотя панель на экране.
  int _usagePaneInstances = 0;
  bool get _usagePaneShown => _usagePaneInstances > 0;

  /// Сессия, для которой ведётся учёт автоматических запросов журнала, и
  /// значение `usage.lastSeq`, для которого запрос уже уходил (D3 п. 4).
  String? _ledgerSession;
  int? _requestedForSeq;

  /// Журнал на прошлой ревизии был `idle`: возврат в `idle` из другого
  /// состояния (переподключение, загрузка сессии) открывает ровно один новый
  /// автозапрос, даже если `lastSeq` не изменился.
  bool? _ledgerWasIdle;

  /// Кэш данных панели: пересчёт только при смене входов (D1). Ревизии
  /// ленты на каждый фрагмент ответа usage и журнал не меняют, а разбор
  /// журнала и индекс вызовов не нужны повторять на каждый из них.
  String? _usageSession;
  UsageView? _usageInput;
  UsageLedgerState? _usageLedgerInput;
  String _usageCwd = '';
  UsagePaneData _usageCached = UsagePaneData.empty;

  /// Статус сессии и ожидания одобрений корня входят в ключ кэша: от них
  /// зависят заголовок `This turn` / `Last turn`, признак тика и Time блока
  /// `Turn budget`, а `usage` при этом не меняется (D9 change
  /// `add-desktop-usage-pane`). Ожидания сравниваются по значению (D5 change
  /// `fix-usage-pane-live-cards`): новая ревизия на каждый фрагмент ответа
  /// их не меняет, а ответ на одобрение закрывает интервал и ключ меняет.
  /// Одобрение потомка в `approvalWaits` не входит и ключ не трогает.
  SessionStatusView? _usageStatus;
  List<ApprovalWaitView> _usageWaits = const [];

  /// Вызовы ленты, по которым собраны подписи шагов: сравниваются по
  /// identity. Длины ленты мало — `tool_call_update` меняет вызов без новой
  /// записи, и подписи шагов (`UsageStepLabeler`) должны обновиться.
  List<ToolCallItem> _usageCalls = const [];

  // Не `_usageWaits == view.approvalWaits`: freezed оборачивает список в
  // `EqualUnmodifiableListView`, чей `==` сравнивает исходные списки по
  // identity, а `const []` по умолчанию — обычный список. Нужен поэлементный
  // обход.
  bool _sameUsageWaits(List<ApprovalWaitView> waits) {
    if (identical(_usageWaits, waits)) return true;
    if (_usageWaits.length != waits.length) return false;
    for (var i = 0; i < waits.length; i++) {
      if (_usageWaits[i] != waits[i]) return false;
    }
    return true;
  }

  bool _sameUsageCalls(List<TranscriptItem> transcript) {
    var index = 0;
    for (final item in transcript) {
      if (item is! ToolCallItem) {
        continue;
      }
      if (index >= _usageCalls.length || !identical(_usageCalls[index], item)) {
        return false;
      }
      index++;
    }
    return index == _usageCalls.length;
  }

  UsagePaneData _usageOf(String sessionId, SessionView? view, String cwd) {
    if (view == null) {
      _usageSession = null;
      return _usageCached = UsagePaneData.empty;
    }
    if (_usageSession == sessionId &&
        _usageCwd == cwd &&
        identical(_usageInput, view.usage) &&
        identical(_usageLedgerInput, view.usageLedger) &&
        _usageStatus == view.status &&
        _sameUsageWaits(view.approvalWaits) &&
        _sameUsageCalls(view.transcript)) {
      return _usageCached;
    }
    _usageSession = sessionId;
    _usageCwd = cwd;
    _usageInput = view.usage;
    _usageLedgerInput = view.usageLedger;
    _usageStatus = view.status;
    _usageWaits = view.approvalWaits;
    _usageCalls = [
      for (final item in view.transcript)
        if (item is ToolCallItem) item,
    ];
    return _usageCached = usagePaneDataOf(view, cwd: cwd);
  }

  /// Автоматический запрос журнала по правилу D3 (`ledgerRefreshNeeded`).
  ///
  /// [deferred] — вызов идёт из реакции на ревизию `SessionHandle.view`
  /// ([_onView]). Kit публикует `loading` синхронно, в начале
  /// `refreshUsageLedger`, а broadcast-поток запрещает `add` внутри доставки
  /// события (`Cannot fire new event`), поэтому запрос уходит микрозадачей,
  /// уже после доставки ревизии.
  void _refreshLedgerIfNeeded(
    String sessionId,
    SessionView view, {
    required String reason,
    bool deferred = false,
  }) {
    if (_ledgerSession != sessionId) {
      _ledgerSession = sessionId;
      _requestedForSeq = null;
      _ledgerWasIdle = null;
    }
    final idle = view.usageLedger is UsageLedgerIdle;
    if (idle && _ledgerWasIdle == false) {
      _requestedForSeq = null;
    }
    _ledgerWasIdle = idle;
    if (!ledgerRefreshNeeded(
      paneShown: _usagePaneShown,
      status: view.status,
      ledger: view.usageLedger,
      lastSeq: view.usage.lastSeq,
      requestedForSeq: _requestedForSeq,
    )) {
      return;
    }
    _requestedForSeq = view.usage.lastSeq;
    if (deferred) {
      unawaited(
        Future<void>.microtask(
          () => _requestLedger(sessionId, rebuild: false, reason: reason),
        ),
      );
      return;
    }
    unawaited(_requestLedger(sessionId, rebuild: false, reason: reason));
  }

  Future<void> _requestLedger(
    String sessionId, {
    required bool rebuild,
    required String reason,
  }) async {
    _usageLogger?.debug(
      'usage_pane.refresh',
      context: {'session_id': sessionId, 'rebuild': rebuild, 'reason': reason},
    );
    try {
      await _workspace.refreshUsageLedger(
        SessionId(sessionId),
        rebuild: rebuild,
      );
    } on Object catch (error) {
      // Сбой запроса kit уже отражает состоянием `failed`; сюда доходит
      // только непредвиденное исключение, его нельзя терять (`AGENTS.md` §12).
      _diagnostics.record(
        'Failed to request the usage ledger: ${error.runtimeType}',
        severity: DiagnosticSeverity.warning,
        source: 'usage',
      );
    }
  }

  void _onView(String sessionId, SessionView view) {
    // Поздняя ревизия сессии, которую уже не показывают, не трогает строку.
    if (isClosed || state.sessionId != sessionId) {
      return;
    }
    activation.observe(view);
    final data = sessionStatusDataOf(view, l10n: _l10n);
    final usage = _usageOf(sessionId, view, _shown?.cwd ?? '');
    if (data != state.statusBar || !identical(usage, state.usage)) {
      emit(state._copyWith(statusBar: data, usage: usage));
    }
    _refreshLedgerIfNeeded(sessionId, view, reason: 'seq', deferred: true);
  }

  @override
  Future<void> close() async {
    await _languageSubscription.cancel();
    await _viewSubscription?.cancel();
    await _outcomeSubscription.cancel();
    return super.close();
  }

  void _onApprovalSelected(PendingApprovalView approval, String optionId) =>
      unawaited(
        respondToApproval(
          approvalId: approval.approvalId,
          sessionId: approval.sessionId,
          optionId: optionId,
        ),
      );

  SessionHandle? _handle(String sessionId) =>
      _workspace.session(SessionId(sessionId));

  List<CodeLabQueuedPrompt> _queueOf(String sessionId) =>
      queuedPromptsOf(_handle(sessionId)?.current.queue ?? const []);

  /// Повторяет очередь kit, только если [sessionId] показывается.
  void _syncQueue(String sessionId) {
    if (isClosed || state.sessionId != sessionId) {
      return;
    }
    emit(state._copyWith(queuedPrompts: _queueOf(sessionId)));
  }

  /// Ход идёт, ждёт одобрения или отмена ждёт ответа агента — сессия занята.
  static bool _isBusy(SessionStatusView? status) => switch (status) {
    SessionStatusView.running || SessionStatusView.cancelling => true,
    _ => false,
  };
}
