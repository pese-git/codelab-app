import 'dart:async';

import '../cancel/cancel_token.dart';
import '../compaction/compactor.dart';
import '../compaction/estimate.dart';
import '../compaction/settings.dart';
import '../compaction/summarizer.dart';
import '../env/bounded_env.dart';
import '../env/execution_env.dart';
import '../llm/messages.dart';
import '../llm/model_catalog.dart';
import '../llm/model_ref.dart';
import '../llm/stream_function.dart';
import '../loop/agent.dart';
import '../loop/agent_events.dart';
import '../loop/loop_config.dart';
import '../permissions/modes.dart';
import '../permissions/policy.dart';
import '../prompts/compose.dart';
import '../session/ids.dart';
import '../session/projections.dart';
import '../session/records.dart';
import '../session/session_store.dart';
import '../session/session_writer.dart';
import '../session/summary.dart';
import '../session/tree.dart';
import '../tools/agent_tool.dart';
import '../tools/executor.dart';
import '../tools/registry.dart';
import '../util/logger.dart';
import '../host/host_profile.dart';
import '../host/services.dart';
import 'agent_session.dart';

/// Кто пишет журналы этого ядра (поле `agent` заголовка, §8.2.1).
const coreAgentInfo = AgentInfo(name: 'codelab-agent', version: '0.1.0');

/// Среда выполнения ядра (`agent-core-architecture` §5.6): создаёт,
/// открывает и перечисляет сессии этого процесса.
///
/// Почему отдельный объект: сессии делят сервисы хоста (хранилище журнала,
/// часы, id, модель), а хост и ACP-адаптер получают их через одну точку —
/// `buildAgentCore` (HOST-6).
///
/// Как использовать: [createSession] — новая сессия с журналом;
/// [loadSession] — продолжение сохранённой; [listSessions] — страница
/// сводок из хранилища; [dispose] — при выходе хоста (design.md change
/// `add-agent-core-sessions-and-compaction`, D4, D5).
abstract interface class AgentRuntime {
  Future<AgentSession> createSession(SessionSpec spec);

  /// Каталог моделей сборки: опция `model` и `AgentSession.setModel`
  /// (§2.12.2, §13.6).
  ModelCatalog get models;

  /// Открывает журнал, дописывает синтетические результаты прерванных
  /// вызовов и восстанавливает транскрипт, режим, план и усилие
  /// рассуждения. [model] — модель сессии; `null` — последняя
  /// `model_change` ветки, найденная в [models], иначе модель по умолчанию
  /// конфигурации с логом `session.model.not_restored` (design.md change
  /// `add-dart-agent-acp-server`, D3). [cwd] — рабочая папка клиента: если
  /// она не совпадает с заголовком, сессия работает в ней и пишет `custom`
  /// `codelab.cwd_changed` (§13.5, шаг 2).
  Future<AgentSession> loadSession(
    SessionId id,
    SessionHostPorts ports, {
    ModelRef? model,
    String? cwd,
  });

  /// Страница сводок хранилища; неверный курсор — `InvalidCursor`.
  Future<SessionPage> listSessions({
    String? cwd,
    String? cursor,
    int pageSize = 50,
  });

  /// Отменяет идущие ходы, дожидается записи журналов и закрывает потоки
  /// событий.
  Future<void> dispose();
}

/// Реализация среды выполнения; создаётся только `buildAgentCore` (HOST-6).
final class AgentRuntimeImpl implements AgentRuntime {
  AgentRuntimeImpl({
    required this.profile,
    required this.services,
    required this.config,
    required this.registry,
    required this.stream,
  }) : models = services.models ?? FixedModelCatalog([config.defaultModel]);

  final HostProfile profile;
  final AgentCoreServices services;
  final CoreConfig config;
  final ToolRegistry registry;
  final StreamFunction stream;

  @override
  final ModelCatalog models;
  final _sessions = <_Session>[];

  SessionStore get _store => services.sessions;

  @override
  Future<AgentSession> createSession(SessionSpec spec) async {
    final header = SessionHeader(
      id: newSessionId(services.clock, services.ids),
      cwd: spec.cwd,
      created: services.clock.now(),
      agent: coreAgentInfo,
      metadata: {'profile': profile.name},
    );
    await _store.create(header);
    final model = _resolve(spec.model ?? config.defaultModel, config.effort);
    final session = await _open(
      snapshot: SessionSnapshot.empty(header),
      cwd: spec.cwd,
      mode: spec.mode ?? config.permissions.mode ?? profile.defaultMode,
      model: model,
      effort: config.effort,
      ports: spec.ports,
      extraBeforeToolCall: [
        ...spec.extraBeforeToolCall,
        ...spec.ports.extraBeforeToolCall,
      ],
      extraAfterToolCall: [
        ...spec.extraAfterToolCall,
        ...spec.ports.extraAfterToolCall,
      ],
    );
    await session._writer.append(
      (id, parent, at) => _modelChange(id, parent, at, model),
    );
    return session;
  }

  @override
  Future<AgentSession> loadSession(
    SessionId id,
    SessionHostPorts ports, {
    ModelRef? model,
    String? cwd,
  }) async {
    final snapshot = await _store.open(id);
    final restored = buildLlmContext(snapshot);
    final effort =
        ReasoningEffort.values
            .where((e) => e.name == restored.config['effort'])
            .firstOrNull ??
        config.effort;
    // Модель журнала выигрывает, если её знает каталог (D3); иначе —
    // поведение этапа 3: модель конфигурации и новая model_change.
    final journalModel = switch (restored.model) {
      final ModelChangeRecord record => models.resolve(
        ModelId('${record.provider}/${record.modelId}'),
        effort: effort,
      ),
      null => null,
    };
    final chosen = model != null
        ? _resolve(model, effort)
        : journalModel ?? _resolve(config.defaultModel, effort);
    final header = snapshot.header.cwd;
    final session = await _open(
      snapshot: snapshot,
      cwd: cwd ?? header,
      mode:
          ModeId.values.where((m) => m.value == restored.modeId).firstOrNull ??
          config.permissions.mode ??
          profile.defaultMode,
      model: chosen,
      effort: effort,
      ports: ports,
      extraBeforeToolCall: ports.extraBeforeToolCall,
      extraAfterToolCall: ports.extraAfterToolCall,
    );
    await session._heal();
    if (restored.model case final journal?
        when journal.provider != chosen.provider ||
            journal.modelId != chosen.id) {
      session._logger.log(
        LogLevel.warning,
        'session.model.not_restored',
        fields: {
          'session_id': id.value,
          'journal': '${journal.provider}/${journal.modelId}',
          'model': '${chosen.provider}/${chosen.id}',
        },
      );
      await session._writer.append(
        (id, parent, at) => _modelChange(id, parent, at, chosen),
      );
    }
    session._restoreHistory();
    if (cwd != null && cwd != header) {
      await session._writer.append(
        (id, parent, at) => CustomRecord(
          id: id,
          parentId: parent,
          timestamp: at,
          customType: 'codelab.cwd_changed',
          data: {'from': header, 'to': cwd},
        ),
      );
    }
    return session;
  }

  /// Ссылка каталога с уровнем рассуждения сессии; модели нет в каталоге —
  /// ссылка как есть, но тоже с уровнем только при рассуждении (§2.12.3).
  ModelRef _resolve(ModelRef model, ReasoningEffort effort) =>
      models.resolve(
        ModelId('${model.provider}/${model.id}'),
        effort: effort,
      ) ??
      _withEffort(model, model.supportsReasoning ? effort : null);

  @override
  Future<SessionPage> listSessions({
    String? cwd,
    String? cursor,
    int pageSize = 50,
  }) => _store.list(cwd: cwd, cursor: cursor, pageSize: pageSize);

  @override
  Future<void> dispose() async {
    for (final session in _sessions) {
      await session.close();
    }
    _sessions.clear();
  }

  static ModelChangeRecord _modelChange(
    String id,
    String? parent,
    DateTime at,
    ModelRef model,
  ) => ModelChangeRecord(
    id: id,
    parentId: parent,
    timestamp: at,
    provider: model.provider,
    modelId: model.id,
    baseUrl: model.baseUrl.toString(),
  );

  /// Общая сборка новой и загруженной сессии: env, политика, агент,
  /// писатель журнала.
  Future<_Session> _open({
    required SessionSnapshot snapshot,
    required String cwd,
    required ModeId mode,
    required ModelRef model,
    required ReasoningEffort effort,
    required SessionHostPorts ports,
    List<BeforeToolCallHook> extraBeforeToolCall = const [],
    List<AfterToolCallHook> extraAfterToolCall = const [],
  }) async {
    final id = snapshot.header.id;
    final env = await BoundedEnv.wrap(ports.env ?? services.baseEnv, cwd);
    final logger = ports.logger ?? services.logger;
    final tools = ToolServices(clock: services.clock, logger: logger);
    final gate = profile.isOn(HostCapability.interactiveApproval)
        ? ports.gate ?? services.gate
        : null;
    final policy = PermissionPolicy(
      mode: mode,
      modeOverride: config.permissions.modeOverride,
      gate: gate,
      rules: config.permissions.rules,
      logger: logger,
    );
    final compaction = profile.isOn(HostCapability.compaction);
    // Сессия создаётся после агента, а аварийное сжатие — её метод.
    late final _Session session;
    final agent = Agent(
      config: AgentLoopConfig(
        sessionId: id,
        model: model,
        stream: stream,
        executor: ToolCallExecutor(
          registry: registry,
          env: env,
          services: tools,
        ),
        clock: services.clock,
        ids: services.ids,
        budget: config.budget,
        beforeToolCall: [
          policy.asHook(registry.lookup),
          ...extraBeforeToolCall,
        ],
        afterToolCall: extraAfterToolCall,
        // Смена модели или усилия посреди хода действует со следующего шага
        // (§13.6): идущий запрос не прерывается.
        prepareNextStep: (_) async => session._takeModelUpdate(),
        approvalWait: tools.approvalWait,
        logger: logger,
        // Без capability compaction — поведение этапа 2: размер не
        // проверяется, overflow — обычная ошибка шага.
        estimateTokens: compaction ? estimateLlmContext : null,
        emergencyCompact: compaction
            ? (cause, cancel) => session._emergency(cause, cancel)
            : null,
        contextWindowCap: config.compaction.contextWindowCap,
      ),
      systemPrompt: _systemPrompt(cwd, mode),
      tools: registry.tools,
    );
    // План эмитится через очередь агента: PlanUpdated приходит подписчикам
    // между ToolCallStarted и ToolCallFinished своего вызова (design.md
    // этапа 2, D5).
    tools.plan.publish = (entries) =>
        agent.emit(PlanUpdated(id, entries: entries));
    session = _Session(
      id: id,
      cwd: cwd,
      mode: mode,
      model: model,
      effort: effort,
      catalog: models,
      agent: agent,
      policy: policy,
      tools: tools,
      env: env,
      registry: registry,
      services: services,
      logger: logger,
      compose: _systemPrompt,
      snapshot: snapshot,
      stream: stream,
      compaction: compaction ? config.compaction : null,
    );
    _sessions.add(session);
    return session;
  }

  static ModelRef _withEffort(ModelRef model, ReasoningEffort? effort) =>
      ModelRef(
        provider: model.provider,
        id: model.id,
        api: model.api,
        baseUrl: model.baseUrl,
        contextWindow: model.contextWindow,
        maxOutputTokens: model.maxOutputTokens,
        cost: model.cost,
        supportsImages: model.supportsImages,
        supportsReasoning: model.supportsReasoning,
        reasoningEffort: effort,
        hiddenReasoning: model.hiddenReasoning,
        thinkingMode: model.thinkingMode,
        supportsTools: model.supportsTools,
      );

  /// Системный промпт сессии (§11.5): собирается при создании и загрузке
  /// сессии и при смене режима; дата — по часам хоста.
  String _systemPrompt(String cwd, ModeId mode) => composeSystemPrompt(
    PromptInputs(
      cwd: cwd,
      platform: services.platform,
      today: services.clock.now(),
      mode: mode,
      profile: profile,
      toolNames: {for (final tool in registry.tools) tool.name},
    ),
  );
}

final class _Session implements AgentSession {
  _Session({
    required this.id,
    required this.cwd,
    required ModeId mode,
    required ModelRef model,
    required ReasoningEffort effort,
    required ModelCatalog catalog,
    required Agent agent,
    required PermissionPolicy policy,
    required ToolServices tools,
    required ExecutionEnv env,
    required ToolRegistry registry,
    required AgentCoreServices services,
    required Logger logger,
    required String Function(String cwd, ModeId mode) compose,
    required SessionSnapshot snapshot,
    required StreamFunction stream,
    required CompactionOverrides? compaction,
  }) : _mode = mode,
       _effort = effort,
       _catalog = catalog,
       _stream = stream,
       _compaction = compaction,
       _model = model,
       _agent = agent,
       _policy = policy,
       _tools = tools,
       _env = env,
       _registry = registry,
       _services = services,
       _logger = logger,
       _compose = compose,
       _titled = _hasTitle(snapshot) {
    _writer = SessionWriter(
      store: services.sessions,
      snapshot: snapshot,
      ids: services.ids,
      clock: services.clock,
      logger: logger,
      onFailure: _onStorageFailure,
    );
    // Писатель — первый подписчик агента: запись идёт до того, как событие
    // увидят остальные (§8.3, SES-8).
    _agent.subscribe(_onEvent);
  }

  @override
  final SessionId id;
  final String cwd;
  ModeId _mode;
  ModelRef _model;
  ReasoningEffort _effort;
  final ModelCatalog _catalog;

  /// Новая модель, которую идущий ход получит на границе шага.
  ModelRef? _pendingModel;
  final Agent _agent;
  final PermissionPolicy _policy;
  final ToolServices _tools;
  final ExecutionEnv _env;
  final ToolRegistry _registry;
  final AgentCoreServices _services;
  final Logger _logger;
  late final SessionWriter _writer;
  final StreamFunction _stream;

  /// Переопределения сжатия; `null` — capability `compaction` выключена.
  final CompactionOverrides? _compaction;

  /// Фоновое сжатие после хода: следующий [prompt] ждёт его (§9.5).
  Future<void>? _background;
  CancelTokenSource? _backgroundCancel;

  /// Сборка системного промпта для нового режима.
  final String Function(String cwd, ModeId mode) _compose;
  final _live = StreamController<AgentEvent>.broadcast(sync: true);
  final _turn = <AgentEvent>[];
  TurnEnded? _ended;

  /// Заголовок уже есть в журнале: автоматический больше не пишется.
  bool _titled;

  @override
  ModeId get mode => _mode;

  @override
  ModelRef get model => _model;

  @override
  ReasoningEffort get effort => _effort;

  @override
  Future<void> setModel(ModelId id) async {
    final model =
        _catalog.resolve(id, effort: _effort) ??
        (throw ArgumentError.value(id.value, 'id', 'not in the model catalog'));
    _apply(model);
    await _writer.append(
      (id, parent, at) => AgentRuntimeImpl._modelChange(id, parent, at, model),
    );
  }

  @override
  Future<void> setEffort(ReasoningEffort effort) async {
    _effort = effort;
    _apply(
      _catalog.resolve(
            ModelId('${_model.provider}/${_model.id}'),
            effort: effort,
          ) ??
          AgentRuntimeImpl._withEffort(
            _model,
            _model.supportsReasoning ? effort : null,
          ),
    );
    await _writer.append(
      (id, parent, at) => ConfigChangeRecord(
        id: id,
        parentId: parent,
        timestamp: at,
        optionId: 'effort',
        value: effort.name,
      ),
    );
  }

  /// Модель следующего хода — сразу, идущего — на границе шага.
  void _apply(ModelRef model) {
    _model = model;
    _agent.config = _agent.config.copyWith(model: model);
    if (_agent.isRunning) {
      _pendingModel = model;
    }
  }

  Future<StepUpdate?> _takeModelUpdate() async {
    final model = _pendingModel;
    _pendingModel = null;
    return model == null ? null : StepUpdate(model: model);
  }

  @override
  Stream<AgentEvent> get events => Stream.multi((controller) {
    for (final event in _turn) {
      controller.add(event);
    }
    final subscription = _live.stream.listen(
      controller.add,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  }, isBroadcast: true);

  @override
  Future<TurnResult> prompt(
    List<ContentBlock> content, {
    CancelToken? cancel,
  }) async {
    if (_background case final background?) {
      await background;
    }
    if (_agent.isRunning) {
      throw StateError('a turn is already running');
    }
    _policy.clearTurnGrants();
    _tools.approvalWait.reset();
    _ended = null;
    cancel?.onCancel.then((_) => _agent.abort(cancel.reason));
    await _agent.prompt([
      UserMessage(content, timestamp: _services.clock.now()),
    ]);
    final ended = _ended!;
    if (ended.reason == TurnEndReason.completed ||
        ended.reason == TurnEndReason.maxTokens) {
      _compactAfterTurn();
    }
    return TurnResult(
      reason: ended.reason,
      usage: ended.usage,
      budgetExceeded: ended.budgetExceeded,
      held: ended.held,
    );
  }

  @override
  Future<void> cancel() async => _agent.abort(const UserCancel());

  @override
  Future<void> setMode(ModeId mode) async {
    _mode = mode;
    _policy.mode = mode;
    // Режим plan добавляет свою секцию: промпт меняется со следующего хода.
    _agent.systemPrompt = _compose(cwd, mode);
    await _sessionEvent(ModeChanged(id, mode: mode));
  }

  @override
  Iterable<AgentEvent> replay() =>
      buildReplay(_writer.snapshot, logger: _logger);

  @override
  Future<void> close() async {
    _agent.abort(const ShutdownCancel());
    _backgroundCancel?.cancel(const ShutdownCancel());
    await _agent.waitForIdle();
    await _background;
    await _services.sessions.close(id);
    if (!_live.isClosed) {
      await _live.close();
    }
  }

  /// Синтетические результаты прерванных вызовов — сразу после открытия, до
  /// реплея и нового шага (§8.8, SES-10).
  Future<void> _heal() async {
    final snapshot = _writer.snapshot;
    final meta = <String, ToolMeta>{
      for (final call in findInterruptedCalls(snapshot))
        call.id: await _describe(call),
    };
    final healed = healInterruptedTurn(
      snapshot,
      _services.ids,
      _services.clock,
      meta: meta,
    );
    for (final record in healed) {
      await _writer.appendBuilt(record, durable: true);
    }
  }

  /// Заголовок прерванного вызова — тот же `present()`, что дал бы
  /// `ToolCallStarted`; без инструмента или при ошибке — его имя.
  Future<ToolMeta> _describe(ToolCall call) async {
    final tool = _registry.lookup(call.name);
    if (tool == null) {
      return ToolMeta(title: call.name, kind: ToolKind.other);
    }
    try {
      final presented = await tool.present(
        call.arguments,
        ToolContext(
          env: _env,
          cancel: CancelTokenSource().token,
          onUpdate: (_) {},
          toolCallId: call.id,
          services: _tools,
        ),
      );
      return ToolMeta(
        title: presented.title,
        kind: tool.kind,
        locations: presented.locations,
      );
    } on Object {
      return ToolMeta(title: call.name, kind: tool.kind);
    }
  }

  /// Транскрипт и план из журнала после ремонта (§8.7).
  void _restoreHistory() {
    final snapshot = _writer.snapshot;
    _agent.replaceTranscript(
      _withModel(buildLlmContext(snapshot, logger: _logger).messages),
    );
    final plan = pathToLeaf(snapshot).whereType<PlanRecord>().lastOrNull;
    if (plan != null) {
      _tools.plan.restore(plan.entries);
    }
  }

  /// Ответы своей модели получают полную ссылку: журнал хранит только
  /// провайдера и id (§2.2).
  List<Message> _withModel(List<Message> messages) => [
    for (final message in messages)
      if (message is AssistantMessage &&
          message.model.provider == _model.provider &&
          message.model.id == _model.id)
        message.copyWith(model: _model)
      else
        message,
  ];

  int get _window => effectiveContextWindow(
    _agent.config.model,
    cap: _compaction?.contextWindowCap,
  );

  CompactionSettings get _settings =>
      CompactionSettings.forWindow(_window, overrides: _compaction);

  List<ToolSchema> get _schemas => [
    for (final tool in _agent.tools) tool.toSchema(),
  ];

  /// Сжатие журнала сессии по §9.8 с суммаризатором над моделью сессии
  /// (design.md, D8).
  Future<CompactionOutcome> _compact(
    CompactionTrigger trigger,
    CancelToken cancel, {
    required void Function(LlmContextProjection projection) onCompacted,
  }) {
    final model = _agent.config.model;
    final settings = _settings;
    return compact(
      writer: _writer,
      trigger: trigger,
      summarize: modelSummarizer(
        stream: _stream,
        model: model,
        sessionId: id,
        settings: settings,
        clock: _services.clock,
      ),
      settings: settings,
      window: _window,
      systemPrompt: _agent.systemPrompt,
      tools: _schemas,
      ids: _services.ids,
      clock: _services.clock,
      cancel: cancel,
      emit: _sessionEvent,
      onCompacted: onCompacted,
      summaryModel: '${model.provider}/${model.id}',
      logger: _logger,
    );
  }

  /// Аварийное сжатие цикла (`preflight`, `overflow`): новый контекст шага
  /// из проекции; транскрипт агента цикл заменит сам после хода.
  Future<LoopContext?> _emergency(
    EmergencyCause cause,
    CancelToken cancel,
  ) async {
    LlmContextProjection? projection;
    final outcome = await _compact(
      cause == EmergencyCause.preflight
          ? CompactionTrigger.preflight
          : CompactionTrigger.overflow,
      cancel,
      onCompacted: (p) => projection = p,
    );
    if (outcome is! Compacted || projection == null) {
      return null;
    }
    return LoopContext(
      systemPrompt: _agent.systemPrompt,
      messages: _withModel(projection!.messages),
      tools: _agent.tools,
    );
  }

  /// `afterTurn` (§9.5): оценка выше порога — сжатие в фоне до следующего
  /// [prompt].
  void _compactAfterTurn() {
    if (_compaction == null) {
      return;
    }
    final tokens = estimateContextTokens(
      _agent.messages,
      systemPrompt: _agent.systemPrompt,
      tools: _schemas,
    );
    if (!shouldCompact(tokens, _window, _settings)) {
      return;
    }
    final source = CancelTokenSource();
    _backgroundCancel = source;
    _background = _runBackground(source.token).whenComplete(() {
      _background = null;
      _backgroundCancel = null;
    });
  }

  Future<void> _runBackground(CancelToken cancel) async {
    try {
      await _compact(
        CompactionTrigger.afterTurn,
        cancel,
        onCompacted: (p) => _agent.replaceTranscript(_withModel(p.messages)),
      );
    } on CancelledException {
      // Сессия закрывается: журнал не тронут (CMP-3).
    } on Object catch (error, stack) {
      // Ошибка фонового сжатия не должна теряться (AGENTS.md §12).
      _logger.log(
        LogLevel.error,
        'compaction.failed',
        fields: {'session_id': id.value, 'trigger': 'afterTurn'},
        error: error,
        stack: stack,
      );
      await _sessionEvent(
        AgentError(
          id,
          cls: AgentErrorClass.compaction,
          message: 'compaction failed: $error',
        ),
      );
    }
  }

  Future<void> _onEvent(AgentEvent event) async {
    await _writer.handle(event);
    _publish(event);
    if (event is TurnEnded) {
      await _afterTurn();
    }
  }

  /// Автоматический заголовок после первого хода со словами пользователя
  /// (§8.10, design.md D6).
  Future<void> _afterTurn() async {
    if (_titled) {
      return;
    }
    final title = summarize(_writer.snapshot, logger: _logger).title;
    if (title == null) {
      return;
    }
    _titled = true;
    await _sessionEvent(
      SessionTitleChanged(id, title: title, updatedAt: _services.clock.now()),
    );
  }

  /// Событие уровня сессии: сначала запись, потом подписчики.
  Future<void> _sessionEvent(AgentEvent event) async {
    await _writer.handle(event);
    _publish(event);
  }

  void _onStorageFailure(Object error) {
    _agent.abort(StorageFailure(error));
    // Не ждём: событие встаёт в очередь агента следом за текущим, а
    // текущее ждёт этого подписчика.
    unawaited(
      _agent.emit(
        AgentError(
          id,
          cls: AgentErrorClass.storage,
          message: 'session journal write failed: $error',
        ),
      ),
    );
  }

  void _publish(AgentEvent event) {
    if (event is TurnStarted) {
      _turn.clear();
    }
    if (event is TurnEnded) {
      _ended = event;
    }
    _turn.add(event);
    if (!_live.isClosed) {
      _live.add(event);
    }
  }

  static bool _hasTitle(SessionSnapshot snapshot) => pathToLeaf(
    snapshot,
  ).any((r) => r is SessionInfoRecord && (r.title?.isNotEmpty ?? false));
}
