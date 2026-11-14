import 'dart:async';
import 'dart:collection';

import '../agents/agent_definition.dart';
import '../env/execution_env.dart';
import '../llm/model_ref.dart';
import '../permissions/agent_config_paths.dart';
import '../permissions/gate.dart';
import '../permissions/modes.dart';
import '../permissions/pattern.dart';
import '../permissions/policy.dart';
import '../skills/skill_catalog.dart';
import '../tools/agent_tool.dart';
import '../tools/path_lock.dart';
import '../tools/tasks/task_list.dart';
import '../cancel/cancel_token.dart';
import '../llm/messages.dart';
import '../llm/usage.dart';
import '../loop/agent.dart';
import '../loop/agent_events.dart';
import '../loop/turn_budget.dart';
import '../util/clock.dart';
import '../util/logger.dart';
import 'child_tools.dart';
import 'subagent_model.dart';
import 'subagent_report.dart';
import 'subagent_task_list.dart';
import 'subagents_config.dart';

/// Исчерпан `subagents.max_per_turn` за ход корневой сессии (SUB-5).
final class SubagentLimitException implements Exception {
  const SubagentLimitException(this.limit);

  final int limit;

  @override
  String toString() => 'SubagentLimitException: at most $limit per turn';
}

/// Что нужно, чтобы запустить потомка (`agent-core/17-3-subagents.md`
/// §17.3.2).
final class SubagentSpec {
  const SubagentSpec({
    required this.id,
    required this.parentSessionId,
    required this.parentToolCallId,
    required this.depth,
    this.path = const [],
    required this.type,
    required this.description,
    required this.prompt,
    this.taskId,
  });

  final SubagentId id;
  final SessionId parentSessionId;

  /// Вызов `agent` в сессии родителя.
  final String parentToolCallId;

  /// Глубина потомка (корневая сессия — 0, ребёнок — 1).
  final int depth;

  /// Id предков-субагентов от глубины 1, без самого потомка.
  final List<SubagentId> path;
  final AgentDefinition type;
  final String description, prompt;

  /// Пункт списка задач, назначенный ребёнку (только от корня).
  final String? taskId;
}

/// Части родителя, из которых менеджер собирает ребёнка (`agent-core/
/// 05-agent-loop.md` §5.6; design.md change `add-subagents-and-tasks`, D36
/// Т2, Т9, Т10).
///
/// Почему не ссылка на сессию родителя: `_Session` приватна, ребёнку нужны
/// её части, а не объект. Значения-функции читаются при каждом `spawn`
/// («текущее состояние родителя»), остальное постоянно для сессии.
final class SubagentParent {
  const SubagentParent({
    required this.tools,
    required this.model,
    required this.mode,
    this.gate,
    required this.skills,
    this.agentConfigPaths,
    required this.decisions,
    required this.rules,
    this.extraDeniedTiers = const {},
    required this.env,
    required this.tasks,
    required this.locks,
    required this.maxChildDepth,
  });

  /// Схемы текущего шага родителя (`base` набора ребёнка).
  final List<AgentTool> Function() tools;
  final ModelRef Function() model;

  /// Эффективный режим родителя: `narrow(этот, type.mode)` при каждом решении
  /// ребёнка (SUB-2).
  final ModeResolution Function() mode;

  /// `null` до итерации 3: вопрос ребёнка — отказ (D38).
  final PermissionGate? gate;

  /// Неизменяемый снимок каталога навыков родителя (D34); `skill` входит в
  /// набор ребёнка только с ним.
  final SkillCatalog skills;

  /// Тот же набор защищаемых путей, что у корня (SUB-1, PERM-11).
  final AgentConfigPaths? agentConfigPaths;

  /// Хранилище решений, правила и запреты уровней корня — общие на дерево.
  final PermissionDecisionStore decisions;
  final PolicyRules rules;
  final Set<ToolTier> extraDeniedTiers;

  /// Env родителя как есть (D36 Т9), список задач дерева и блокировки путей
  /// корня (TOOL-7): параллельные правки одного файла родителем и детьми
  /// упорядочены одной очередью.
  final ExecutionEnv env;
  final TaskList tasks;
  final PathLock locks;

  /// Наибольшая глубина потомка, которую рантайм умеет запускать; до
  /// итерации 4 — 1, поэтому `agent` ребёнку не даётся.
  final int maxChildDepth;
}

/// Всё для дочерней сессии (`agent-core/05-agent-loop.md` §5.6, внутренний
/// тип ядра; D36 Т2): набор, модель, функция режима, gate, снимок навыков и
/// пути конфигурации, общие части родителя и крючки менеджера (usage и бюджет
/// предков, D4).
final class ChildSessionSpec {
  const ChildSessionSpec({
    required this.subagent,
    required this.tools,
    required this.model,
    required this.budget,
    required this.mode,
    this.gate,
    this.skills,
    this.agentConfigPaths,
    required this.decisions,
    required this.rules,
    this.extraDeniedTiers = const {},
    required this.env,
    required this.tasks,
    required this.locks,
    required this.logger,
    required this.onOwnUsage,
    required this.ancestorBudget,
  });

  final SubagentSpec subagent;

  /// `base ∩ type.tools` (SUB-1), без `task_create`; `skill` — только со
  /// снимком [skills].
  final List<AgentTool> tools;
  final ModelRef model;
  final TurnBudget budget;

  /// `narrow(parentMode(), type.mode)` на каждое решение (SUB-2).
  final ModeResolution Function() mode;
  final PermissionGate? gate;

  /// Тот же снимок, что у родителя: второй загрузки файлов навыков нет.
  final SkillCatalog? skills;
  final AgentConfigPaths? agentConfigPaths;
  final PermissionDecisionStore decisions;
  final PolicyRules rules;
  final Set<ToolTier> extraDeniedTiers;
  final ExecutionEnv env;
  final TaskList tasks;
  final PathLock locks;

  /// Логгер ребёнка с `root_session_id`, `subagent_id`, `parent_tool_call_id`;
  /// `session_id` ребёнка фабрика добавляет сама (D18).
  final Logger logger;
  final void Function(Usage own) onOwnUsage;
  final BudgetLimit? Function() ancestorBudget;
}

/// Дочерняя сессия, собранная фабрикой рантайма: агент со своим писателем
/// журнала. Менеджер только запускает ход, слушает события и закрывает её.
final class ChildSession {
  ChildSession({
    required this.id,
    required this.journalPath,
    required this.agent,
    required Future<void> Function() close,
  }) : _close = close;

  final SessionId id;

  /// Непрозрачный адрес журнала от `SessionStore.createChild`.
  final String journalPath;

  /// Первым подписчиком уже стоит писатель журнала ребёнка.
  final Agent agent;
  final Future<void> Function() _close;

  Future<void> close() => _close();
}

/// Фабрика дочерней сессии: приватный метод рантайма (D36 Т2).
typedef ChildSessionFactory = Future<ChildSession> Function(
  ChildSessionSpec spec,
);

/// Слоты дерева и счётчик запусков (`agent-core/17-3-subagents.md` §17.3.4;
/// SUB-5, SUB-23; design.md change `add-subagents-and-tasks`, D3).
///
/// Почему отдельный объект: слоты, счётчик `max_per_turn` и очередь общие для
/// всего дерева корневой сессии, а менеджеров — по одному на сессию с `agent`.
///
/// Для чего: `max_concurrent` слотов; держатель слота работает сам, поэтому
/// слоты освобождаются без участия очереди и взаимоблокировки нет. Очередь
/// двухуровневая: сначала возвращающиеся родители (`resume`), затем новые
/// дети; внутри уровня — FIFO. Лимиты читаются из конфигурации при каждом
/// обращении (D17, D22).
final class SubagentTree {
  SubagentTree({required SubagentsConfig Function() limits}) : _limits = limits;

  final SubagentsConfig Function() _limits;
  var _held = 0;
  var _spawned = 0;
  final _resumeQueue = Queue<_Waiter>();
  final _newQueue = Queue<_Waiter>();

  /// `subagents.max_depth` на сейчас.
  int get maxDepth => _limits().maxDepth;

  /// Запусков за ход корневой сессии.
  int get spawnedThisTurn => _spawned;

  /// Сбрасывается в `AgentSession.prompt()` корневой сессии.
  void resetTurn() => _spawned = 0;

  /// Занимает счётчик запуска; [SubagentLimitException] при исчерпании.
  void countSpawn() {
    final limit = _limits().maxPerTurn;
    if (_spawned >= limit) {
      throw SubagentLimitException(limit);
    }
    _spawned++;
  }

  /// Ждёт слот; `false` — запрос отменён [cancel] до получения слота
  /// (ребёнок в очереди не делает запросов и не создаёт журнал).
  Future<bool> acquire({required bool resume, required CancelToken cancel}) {
    if (cancel.isCancelled) {
      return Future.value(false);
    }
    final waiter = _Waiter();
    (resume ? _resumeQueue : _newQueue).add(waiter);
    cancel.onCancel.then((_) {
      if (!waiter.completer.isCompleted) {
        _resumeQueue.remove(waiter);
        _newQueue.remove(waiter);
        waiter.completer.complete(false);
      }
    });
    _pump();
    return waiter.completer.future;
  }

  /// Свободные слоты на сейчас (для лога `subagent.slot.release`).
  int get freeSlots => (_limits().maxConcurrent - _held).clamp(0, 1 << 30);

  /// Возвращает слот и передаёт его следующему в очереди.
  void release() {
    _held--;
    _pump();
  }

  void _pump() {
    while (_held < _limits().maxConcurrent) {
      final next = _resumeQueue.isNotEmpty
          ? _resumeQueue.removeFirst()
          : _newQueue.isNotEmpty
          ? _newQueue.removeFirst()
          : null;
      if (next == null) {
        return;
      }
      _held++;
      next.completer.complete(true);
    }
  }
}

final class _Waiter {
  final completer = Completer<bool>();
}

/// Хэндл потомка (`agent-core/17-3-subagents.md` §17.3.2).
abstract interface class SubagentHandle {
  SubagentId get id;
  SubagentSpec get spec;
  SessionId? get childSessionId;
  SubagentState get state;

  /// Состояния без повторов подряд; широковещательный.
  Stream<SubagentState> get states;
  SubagentSnapshot get snapshot;

  /// Каждое переизлучённое `SubagentProgress`; по нему вызов `agent` пишет
  /// строку прогресса.
  Stream<SubagentSnapshot> get progress;

  /// Завершается ровно один раз и никогда ошибкой.
  Future<SubagentReport> get report;
}

/// Менеджер потомков одной сессии: запуск, отмена, события, отчёт
/// (`agent-core/17-3-subagents.md` §17.3.3–§17.3.5; design.md change
/// `add-subagents-and-tasks`, D3–D6).
///
/// Почему отдельный объект: ни цикл, ни политика, ни единая точка исполнения
/// не знают о детях; всё особенное сосредоточено в `SubagentTool`, менеджере,
/// дереве и обёртке gate (§17.3.1).
///
/// Для чего: [spawn] ставит ребёнка в очередь и сразу возвращает хэндл;
/// дальше менеджер получает слот, создаёт дочернюю сессию фабрикой рантайма,
/// эмитит `SubagentStarted`, `SubagentProgress`, `SubagentActivity` и
/// `SubagentFinished` в поток родителя, строит отчёт и освобождает слот.
/// Терминальное состояние наступает ровно один раз; поздние события ребёнка
/// не переизлучаются.
///
/// Как использовать: рантайм создаёт по одному на сессию с `agent`, передаёт
/// `SubagentTool` и закрывает [closeAll] при закрытии сессии.
final class SubagentManager {
  SubagentManager({
    required this.tree,
    required SubagentsConfig Function() limits,
    required Future<void> Function(AgentEvent event) emit,
    required ChildSessionFactory create,
    required Clock clock,
    required Logger logger,
    required SessionId sessionId,
    required TurnBudget Function() rootBudget,
    required SubagentParent Function() parent,
  }) : _limits = limits,
       _emit = emit,
       _create = create,
       _clock = clock,
       _logger = logger,
       _sessionId = sessionId,
       _rootBudget = rootBudget,
       _parent = parent;

  final SubagentTree tree;
  final SubagentsConfig Function() _limits;
  final Future<void> Function(AgentEvent event) _emit;
  final ChildSessionFactory _create;
  final Clock _clock;
  final Logger _logger;
  final SessionId _sessionId;
  final TurnBudget Function() _rootBudget;

  /// Части родителя читаются при каждом `spawn`: `_Session` и политика
  /// появляются позже менеджера.
  final SubagentParent Function() _parent;

  final _all = <_Handle>[];

  /// Id всех когда-либо созданных хэндлов: `knows` не зависит от очистки
  /// самих хэндлов.
  final _known = <SubagentId>{};
  var _turnHandles = <_Handle>[];
  var _rootOwn = Usage.zero;

  /// Собственный usage хода корня (без детей): для остатка бюджета потомков.
  set rootOwnUsage(Usage value) => _rootOwn = value;

  /// Начало хода корня: счётчик запусков и учёт usage детей сбрасываются.
  void beginTurn() {
    tree.resetTurn();
    _turnHandles = [];
    _rootOwn = Usage.zero;
  }

  /// Usage детей хода корня на сейчас, транзитивно (SUB-11).
  Usage get childrenUsage {
    var total = Usage.zero;
    for (final handle in _turnHandles) {
      total += handle.usageNow;
    }
    return total;
  }

  /// Потомок с таким id когда-либо запускался в дереве (хэндл создан).
  bool knows(SubagentId id) => _known.contains(id);

  /// Потомки в порядке запуска.
  List<SubagentSnapshot> list() => [for (final h in _all) h.snapshot];

  /// Ставит потомка в очередь слотов (`state == queued`).
  ///
  /// [SubagentLimitException] — исчерпан `max_per_turn`. [cancel] — токен хода
  /// родителя: токен потомка — его дочерний (SUB-6).
  SubagentHandle spawn(SubagentSpec spec, CancelToken cancel) {
    tree.countSpawn();
    final handle = _Handle(spec, cancel, _clock);
    _all.add(handle);
    _known.add(handle.id);
    _turnHandles.add(handle);
    _logger.log(
      LogLevel.info,
      'subagent.spawn',
      fields: {
        'session_id': _sessionId.value,
        'tool_call_id': spec.parentToolCallId,
        'subagent_id': spec.id,
        'subagent_type': spec.type.name,
        'depth': spec.depth,
      },
    );
    unawaited(_run(handle));
    return handle;
  }

  /// Отменяет потомка и его детей, но не родителя и не соседей; идемпотентно.
  Future<void> cancel(SubagentId id, [Object? reason]) async {
    final handle = _all.where((h) => h.id == id).firstOrNull;
    if (handle == null) {
      return;
    }
    handle.source.cancel(reason ?? const UserCancel());
    await handle.report;
  }

  /// Остановка по `cancel_grace`: хэндл помечается `cancelled`, дочерняя
  /// сессия закрывается в фоне (лог `subagent.cancel_grace_exceeded`). Слот
  /// остаётся за ребёнком до его реальной остановки.
  Future<void> forceCancelled(SubagentId id) async {
    final handle = _all.where((h) => h.id == id).firstOrNull;
    if (handle == null || handle.done) {
      return;
    }
    _logger.log(
      LogLevel.warning,
      'subagent.cancel_grace_exceeded',
      fields: {'session_id': _sessionId.value, 'subagent_id': id},
    );
    await _finish(handle, handle.reportOf(SubagentState.cancelled));
  }

  /// Закрытие родительской сессии: все потомки отменяются и завершаются.
  Future<void> closeAll(Object reason) async {
    for (final handle in List.of(_all)) {
      handle.source.cancel(reason);
    }
    await Future.wait([for (final h in List.of(_all)) h.report]);
  }

  /// Остаток бюджета корня для потомка (D4): токены и стоимость хода корня
  /// вместе с usage всех детей; время предков не наследуется.
  BudgetLimit? ancestorBudget() {
    final budget = _rootBudget();
    final total = _rootOwn + childrenUsage;
    if (budget.maxTokens case final max?
        when total.input + total.output >= max) {
      return BudgetLimit.tokens;
    }
    if (budget.maxCost case final max?
        when total.cost.total > 0 && total.cost.total >= max) {
      return BudgetLimit.cost;
    }
    return null;
  }

  Future<void> _run(_Handle handle) async {
    try {
      final leased = await tree.acquire(
        resume: false,
        cancel: handle.source.token,
      );
      if (!leased) {
        // Отменён в очереди: слота не занимал, журнал не создавал, к модели
        // не обращался (SUB-6).
        await _finish(handle, handle.reportOf(SubagentState.cancelled));
        return;
      }
      try {
        await _runLeased(handle);
      } finally {
        tree.release();
        _logger.log(
          LogLevel.debug,
          'subagent.slot.release',
          fields: {
            'session_id': _sessionId.value,
            'subagent_id': handle.id,
            'free_slots': tree.freeSlots,
          },
        );
      }
    } on Object catch (error, stack) {
      _logger.log(
        LogLevel.error,
        'subagent.failed',
        fields: {
          'session_id': _sessionId.value,
          'subagent_id': handle.id,
          'error_class': error.runtimeType.toString(),
        },
        error: error,
        stack: stack,
      );
      await _finish(
        handle,
        handle.reportOf(
          SubagentState.failed,
          failure: SubagentFailure.error,
          message: 'the subagent could not run: ${error.runtimeType}',
        ),
      );
    }
  }

  Future<void> _runLeased(_Handle handle) async {
    final spec = handle.spec;
    handle.startedAt = _clock.now();
    handle.setState(SubagentState.running);
    final limits = _limits();
    final parent = _parent();
    final childLogger = BoundLogger(_logger, {
      'root_session_id': _sessionId.value,
      'subagent_id': handle.id,
      'parent_tool_call_id': spec.parentToolCallId,
    });
    final child = await _create(
      ChildSessionSpec(
        subagent: spec,
        tools: selectChildTools(
          parentTools: parent.tools(),
          type: spec.type,
          depth: spec.depth,
          maxDepth: parent.maxChildDepth,
          skills: parent.skills,
        ),
        model: spec.type.model ?? parent.model(),
        budget: TurnBudget(
          maxSteps: limits.maxSteps,
          maxTokens: limits.maxTokens,
          maxCost: limits.maxCost,
          maxDuration: limits.maxDuration,
        ),
        mode: () => narrow(parent.mode(), spec.type.mode),
        gate: parent.gate,
        skills: parent.skills,
        agentConfigPaths: parent.agentConfigPaths,
        decisions: parent.decisions,
        rules: parent.rules,
        extraDeniedTiers: parent.extraDeniedTiers,
        env: parent.env,
        tasks: SubagentTaskList(
          root: parent.tasks,
          subagentId: spec.id,
          parentToolCallId: spec.parentToolCallId,
        ),
        locks: parent.locks,
        logger: childLogger,
        onOwnUsage: (own) => handle.ownUsage = own,
        ancestorBudget: ancestorBudget,
      ),
    );
    handle.child = child;
    handle.childId = child.id;
    handle.journalPath = child.journalPath;
    // Отмена, пока создавалась сессия: ребёнок закрывается, к модели он не
    // пойдёт.
    if (handle.source.isCancelled) {
      await _finish(handle, handle.reportOf(SubagentState.cancelled));
      return;
    }
    _logger.log(
      LogLevel.info,
      'subagent.start',
      fields: {
        'session_id': _sessionId.value,
        'subagent_id': handle.id,
        'child_session_id': child.id.value,
        'wait_ms': handle.startedAt!
            .difference(handle.createdAt)
            .inMilliseconds,
      },
    );
    await _emit(
      SubagentStarted(
        _sessionId,
        subagentId: handle.id,
        parentToolCallId: spec.parentToolCallId,
        agent: spec.type.name,
        description: spec.description,
        childSessionId: child.id,
        journalPath: child.journalPath,
      ),
    );
    await _progress(handle, force: true);
    handle.unsubscribe = child.agent.subscribe(
      (event) => _onChildEvent(handle, event),
    );
    unawaited(
      handle.source.token.onCancel.then(
        (_) => child.agent.abort(handle.source.token.reason),
      ),
    );
    // Отмена между `SubagentStarted` и началом хода: abort до `prompt` не
    // подействует, поэтому проверка здесь.
    if (handle.source.isCancelled) {
      child.agent.abort(handle.source.token.reason);
    }
    try {
      await child.agent.prompt([
        UserMessage([TextContent(spec.prompt)], timestamp: _clock.now()),
      ]);
    } on Object catch (error, stack) {
      _logger.log(
        LogLevel.error,
        'subagent.turn_failed',
        fields: {
          'session_id': _sessionId.value,
          'subagent_id': handle.id,
          'error_class': error.runtimeType.toString(),
        },
        error: error,
        stack: stack,
      );
      handle.lastError ??= 'the subagent turn failed: ${error.runtimeType}';
    }
    await _finish(handle, _buildReport(handle));
  }

  Future<void> _onChildEvent(_Handle handle, AgentEvent event) async {
    if (handle.done) {
      // Ребёнок пережил `cancel_grace`: его события до клиента не доходят.
      return;
    }
    switch (event) {
      case StepEnded():
        handle.steps++;
      case ToolCallStarted(:final title):
        handle.toolCalls++;
        handle.lastActivity = title;
      case TurnEnded():
        handle.ended = event;
      case AgentError(:final message):
        handle.lastError = message;
      default:
        break;
    }
    await _emit(
      SubagentActivity(
        _sessionId,
        subagentId: handle.id,
        parentToolCallId: handle.spec.parentToolCallId,
        path: handle.spec.path,
        depth: handle.spec.depth,
        event: event,
      ),
    );
    if (event is StepEnded || event is ToolCallStarted) {
      await _progress(handle);
    }
  }

  /// `SubagentProgress`: смена состояния — всегда, шаги и вызовы — не чаще
  /// `progress_interval`. Подавленное обновление не теряется: последнее
  /// уходит по таймеру, когда интервал истечёт.
  Future<void> _progress(_Handle handle, {bool force = false}) async {
    if (handle.done) {
      return;
    }
    final now = _clock.now();
    final last = handle.lastProgressAt;
    final interval = _limits().progressInterval;
    if (!force && last != null && now.difference(last) < interval) {
      handle.trailing ??= _clock.timer(interval - now.difference(last), () {
        handle.trailing = null;
        unawaited(_progress(handle, force: true));
      });
      return;
    }
    handle.trailing?.cancel();
    handle.trailing = null;
    handle.lastProgressAt = now;
    final snapshot = handle.snapshot;
    await _emit(SubagentProgress(_sessionId, snapshot: snapshot));
    if (!handle.progressController.isClosed) {
      handle.progressController.add(snapshot);
    }
  }

  SubagentReport _buildReport(_Handle handle) {
    final ended = handle.ended;
    if (ended != null) {
      // Итоговый usage хода ребёнка уже включает его потомков.
      handle.ownUsage = ended.usage;
    }
    final text = _lastText(handle.child?.agent.messages ?? const []);
    final SubagentState status;
    SubagentFailure? failure;
    BudgetLimit? limit;
    String? message;
    if (ended == null) {
      status = handle.source.isCancelled
          ? SubagentState.cancelled
          : SubagentState.failed;
      failure = status == SubagentState.failed ? SubagentFailure.error : null;
      message = handle.lastError ?? 'the subagent ended without a result';
    } else {
      switch (ended.reason) {
        case TurnEndReason.cancelled:
          status = SubagentState.cancelled;
        case TurnEndReason.failed:
          status = SubagentState.failed;
          failure = SubagentFailure.error;
          message = handle.lastError ?? (text.isEmpty ? null : text);
        case TurnEndReason.refused:
          status = SubagentState.failed;
          failure = SubagentFailure.refused;
          message = handle.lastError ?? (text.isEmpty ? null : text);
        case TurnEndReason.completed || TurnEndReason.maxTokens:
          if (ended.budgetExceeded case final exceeded?) {
            status = SubagentState.failed;
            failure = SubagentFailure.budgetExceeded;
            limit = exceeded;
          } else {
            status = SubagentState.completed;
          }
      }
    }
    final cut = truncateReport(text, _limits().reportMaxBytes);
    return handle.reportOf(
      status,
      failure: failure,
      limit: limit,
      text: cut.text,
      truncated: cut.truncated,
      message: message,
    );
  }

  /// Текст последнего ответа ребёнка: склейка текстовых блоков через пустую
  /// строку (thinking и вызовы инструментов не входят, §17.3.5, шаг 1).
  static String _lastText(List<Message> messages) {
    final last = messages.whereType<AssistantMessage>().lastOrNull;
    if (last == null) {
      return '';
    }
    return last.content
        .whereType<TextContent>()
        .map((b) => b.text)
        .join('\n\n');
  }

  /// Терминальное состояние ровно один раз: первое записанное выигрывает
  /// (гонка отмены и завершения, D5).
  Future<void> _finish(_Handle handle, SubagentReport report) async {
    if (handle.done) {
      return;
    }
    handle.done = true;
    handle.unsubscribe?.call();
    handle.trailing?.cancel();
    handle.setState(report.status);
    handle.endedAt = _clock.now();
    handle.finalUsage = report.usage;
    final preview = report.text.length > 200
        ? report.text.substring(0, 200)
        : report.text;
    _logger.log(
      LogLevel.info,
      'subagent.end',
      fields: {
        'session_id': _sessionId.value,
        'subagent_id': handle.id,
        'status': report.status.name,
        'failure': failureWire(report.failure, report.budgetExceeded),
        'steps': report.steps,
        'tool_calls': report.toolCalls,
        'tokens': report.usage.input + report.usage.output,
        'duration_ms': report.duration.inMilliseconds,
      },
    );
    try {
      await _emit(
        SubagentFinished(
          _sessionId,
          subagentId: handle.id,
          parentToolCallId: handle.spec.parentToolCallId,
          agent: handle.spec.type.name,
          description: handle.spec.description,
          status: report.status,
          failure: report.failure,
          childSessionId: handle.childId,
          journalPath: handle.journalPath,
          usage: report.usage,
          toolCalls: report.toolCalls,
          duration: report.duration,
          report: report.text,
          reportPreview: preview,
          budgetExceeded: report.budgetExceeded,
        ),
      );
    } finally {
      if (!handle.reportCompleter.isCompleted) {
        handle.reportCompleter.complete(report);
      }
      unawaited(_closeChild(handle));
    }
  }

  Future<void> _closeChild(_Handle handle) async {
    handle.source.dispose();
    final child = handle.child;
    handle.child = null;
    handle.closeControllers();
    if (child == null) {
      return;
    }
    try {
      await child.close();
    } on Object catch (error, stack) {
      _logger.log(
        LogLevel.warning,
        'subagent.close_failed',
        fields: {
          'session_id': _sessionId.value,
          'subagent_id': handle.id,
          'error_class': error.runtimeType.toString(),
        },
        error: error,
        stack: stack,
      );
    }
  }
}

final class _Handle implements SubagentHandle {
  _Handle(this.spec, CancelToken parent, this._clock)
    : source = CancelTokenSource(parent: parent),
      _createdAt = _clock.now();

  @override
  final SubagentSpec spec;
  final CancelTokenSource source;
  final Clock _clock;
  final DateTime _createdAt;

  ChildSession? child;

  /// Id и адрес журнала ребёнка остаются у хэндла после очистки [child]:
  /// `null` — только у отменённого в очереди.
  SessionId? childId;
  String? journalPath;
  void Function()? unsubscribe;
  ClockTimer? trailing;
  DateTime get createdAt => _createdAt;
  var _state = SubagentState.queued;
  var done = false;
  DateTime? startedAt, endedAt, lastProgressAt;
  int steps = 0, toolCalls = 0;
  String? lastActivity, lastError;
  TurnEnded? ended;
  Usage ownUsage = Usage.zero;
  Usage? finalUsage;

  final reportCompleter = Completer<SubagentReport>();
  final _states = StreamController<SubagentState>.broadcast(sync: true);
  final progressController = StreamController<SubagentSnapshot>.broadcast(
    sync: true,
  );

  @override
  SubagentId get id => spec.id;

  @override
  SessionId? get childSessionId => childId;

  @override
  SubagentState get state => _state;

  @override
  Stream<SubagentState> get states => _states.stream;

  @override
  Stream<SubagentSnapshot> get progress => progressController.stream;

  @override
  Future<SubagentReport> get report => reportCompleter.future;

  /// Usage потомка на сейчас: живой — по шагам цикла, после итога — отчёта.
  Usage get usageNow => finalUsage ?? ownUsage;

  /// Закрывает потоки: после итога подписчиков нет.
  void closeControllers() {
    unawaited(_states.close());
    unawaited(progressController.close());
  }

  void setState(SubagentState next) {
    if (_state == next) {
      return;
    }
    _state = next;
    if (!_states.isClosed) {
      _states.add(next);
    }
  }

  @override
  SubagentSnapshot get snapshot => SubagentSnapshot(
    id: id,
    parentToolCallId: spec.parentToolCallId,
    agent: spec.type.name,
    description: spec.description,
    depth: spec.depth,
    state: _state,
    steps: steps,
    toolCalls: toolCalls,
    usage: usageNow,
    startedAt: startedAt ?? _createdAt,
    endedAt: endedAt,
    lastActivity: lastActivity,
  );

  SubagentReport reportOf(
    SubagentState status, {
    SubagentFailure? failure,
    BudgetLimit? limit,
    String text = '',
    bool truncated = false,
    String? message,
  }) {
    final started = startedAt;
    return SubagentReport(
      id: id,
      agent: spec.type.name,
      status: status,
      failure: failure,
      budgetExceeded: limit,
      text: text,
      truncated: truncated,
      steps: steps,
      toolCalls: toolCalls,
      // У отменённого в очереди — нули (D24).
      usage: started == null ? Usage.zero : usageNow,
      duration: started == null
          ? Duration.zero
          : _clock.now().difference(started),
      failureMessage: message,
    );
  }
}
