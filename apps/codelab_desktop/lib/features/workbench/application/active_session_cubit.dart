import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        AgentCommandView,
        ClientWorkspace,
        ClientWorkspaceException,
        Connected,
        InspectorProjection,
        PendingApprovalView,
        PromptOutcome,
        PromptQueued,
        SessionHandle,
        SessionStatusView;
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_ui/codelab_ui.dart';

import 'shell_part.dart';
import 'ui_mappers.dart';

/// Показываемая сессия: лента, инспектор, очередь, одобрения, опции, план.
final class ActiveSessionState {
  const ActiveSessionState({
    this.sessionId,
    this.transcriptEntries = const [],
    this.inspectorEntries = const [_emptyInspectorEntry],
    this.agentCommands = const [],
    this.agentCommandViews = const [],
    this.configOptions = const [],
    this.currentPlan,
    this.queuedPrompts = const [],
    this.composerDraft = '',
    this.composerDraftRevision = 0,
    this.isPromptSubmitting = false,
    this.canCancel = false,
    this.isRespondingToApproval = false,
    this.isRespondingToConfigOption = false,
    this.sessionMode,
  });

  static const _emptyInspectorEntry = CodeLabInspectorEntry(
    id: 'inspector-empty',
    category: CodeLabInspectorCategory.protocol,
    title: 'Protocol log',
    summary: 'Connect and start a session to inspect ACP activity.',
  );

  /// Сессия, которую сейчас показывает рабочее место; совпадает с
  /// `SessionsState.activeSessionId`: обе части меняются одним пакетом.
  final String? sessionId;
  final List<CodeLabTranscriptEntry> transcriptEntries;
  final List<CodeLabInspectorEntry> inspectorEntries;

  /// Команды агента из последнего `available_commands_update`.
  final List<CodeLabCommandAction> agentCommands;

  /// Те же команды в форме kit — вход каталога палитры (`paletteCatalogOf`).
  final List<AgentCommandView> agentCommandViews;
  final List<CodeLabConfigOption> configOptions;

  /// План сессии; `null` — плана не было или пользователь его скрыл.
  final List<CodeLabPlanEntry>? currentPlan;

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

  static const Object _unset = Object();

  ActiveSessionState _copyWith({
    String? sessionId,
    List<CodeLabTranscriptEntry>? transcriptEntries,
    List<CodeLabInspectorEntry>? inspectorEntries,
    List<CodeLabCommandAction>? agentCommands,
    List<AgentCommandView>? agentCommandViews,
    List<CodeLabConfigOption>? configOptions,
    Object? currentPlan = _unset,
    List<CodeLabQueuedPrompt>? queuedPrompts,
    String? composerDraft,
    int? composerDraftRevision,
    bool? isPromptSubmitting,
    bool? canCancel,
    bool? isRespondingToApproval,
    bool? isRespondingToConfigOption,
    Object? sessionMode = _unset,
  }) => ActiveSessionState(
    sessionId: sessionId ?? this.sessionId,
    transcriptEntries: transcriptEntries ?? this.transcriptEntries,
    inspectorEntries: inspectorEntries ?? this.inspectorEntries,
    agentCommands: agentCommands ?? this.agentCommands,
    agentCommandViews: agentCommandViews ?? this.agentCommandViews,
    configOptions: configOptions ?? this.configOptions,
    // `null` здесь — «скрыть план», а не «не менять».
    currentPlan: identical(currentPlan, _unset)
        ? this.currentPlan
        : currentPlan as List<CodeLabPlanEntry>?,
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
final class ActiveSessionCubit extends ShellPartCubit<ActiveSessionState> {
  ActiveSessionCubit({
    required super.changes,
    required ClientWorkspace workspace,
    required ShellDiagnostics diagnostics,
  }) : _workspace = workspace,
       _diagnostics = diagnostics,
       super(const ActiveSessionState()) {
    // Исход хода любой сессии — отправленного отсюда и ушедшего из очереди
    // kit: очередь могла сдвинуться.
    _outcomeSubscription = _workspace.promptOutcomes.listen(
      (outcome) => _syncQueue(outcome.sessionId.value),
    );
  }

  final ClientWorkspace _workspace;
  final ShellDiagnostics _diagnostics;
  late final StreamSubscription<PromptOutcome> _outcomeSubscription;

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
    // Соединение kit в `canRetry` не учитывает — его проверяет хост
    // (design D4 change `add-connection-and-error-states`).
    final canRetry =
        view != null &&
        view.canRetry &&
        _workspace.current.connection is Connected;
    emit(
      state._copyWith(
        sessionId: id,
        transcriptEntries: transcriptEntriesOf(
          view?.transcript ?? const [],
          cwd: session.cwd,
          approvalsEnabled: !state.isRespondingToApproval,
          onApprovalSelected: _onApprovalSelected,
          onRetry: canRetry ? () => unawaited(retryTurn()) : null,
        ),
        inspectorEntries: const InspectorProjection().project(session),
        agentCommands: agentCommandsOf(view?.agentCommands ?? const []),
        agentCommandViews: view?.agentCommands ?? const [],
        configOptions: configOptionsOf(view?.configOptions ?? const []),
        sessionMode: modeLabelOf(view?.configOptions ?? const []),
        currentPlan: currentPlanOf(session),
        queuedPrompts: _queueOf(id),
        isPromptSubmitting: _isBusy(view?.status),
        canCancel: view?.status == SessionStatusView.running,
      ),
    );
  }

  /// Показывает только что созданную сессию: лента пуста, ход не идёт.
  void showCreated(AcpSession session) {
    final id = session.id.value;
    _shown = session;
    final view = _handle(id)?.current;
    emit(
      state._copyWith(
        sessionId: id,
        transcriptEntries: const [],
        inspectorEntries: const InspectorProjection().project(session),
        agentCommands: agentCommandsOf(view?.agentCommands ?? const []),
        agentCommandViews: view?.agentCommands ?? const [],
        configOptions: configOptionsOf(view?.configOptions ?? const []),
        sessionMode: modeLabelOf(view?.configOptions ?? const []),
        currentPlan: currentPlanOf(session),
        queuedPrompts: _queueOf(id),
        isPromptSubmitting: false,
        canCancel: false,
      ),
    );
  }

  /// Выбрана сессия, которой нет в ядре клиента: показывать нечего, кроме
  /// её очереди.
  void showMissing(String sessionId) => emit(
    state._copyWith(
      sessionId: sessionId,
      transcriptEntries: const [],
      inspectorEntries: const [],
      agentCommands: const [],
      agentCommandViews: const [],
      configOptions: const [],
      sessionMode: null,
      currentPlan: null,
      queuedPrompts: _queueOf(sessionId),
      isPromptSubmitting: false,
      canCancel: false,
    ),
  );

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
  }) async {
    if (state.isRespondingToApproval) {
      return;
    }
    final handle = _workspace.session(sessionId);
    if (handle == null) {
      return;
    }

    emit(state._copyWith(isRespondingToApproval: true));
    try {
      await handle.respond(approvalId, PermissionOptionId(optionId));
    } on Object {
      // Ошибка уже записана диагностикой kit.
    }
    if (isClosed) return;
    emit(state._copyWith(isRespondingToApproval: false));
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

  @override
  Future<void> close() async {
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
