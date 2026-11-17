import 'dart:async';
import 'dart:collection';

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
import '../compaction/estimate.dart';
import '../compaction/settings.dart';
import '../llm/messages.dart';
import '../llm/usage.dart';
import '../loop/loop_config.dart';
import '../loop/agent.dart';
import '../loop/agent_events.dart';
import '../loop/turn_budget.dart';
import '../util/clock.dart';
import '../util/logger.dart';
import 'child_tools.dart';
import 'subagent_model.dart';

// SubagentSpec живёт в subagent_model.dart (разрыв цикла с gate); реэкспорт
// сохраняет импорты вида subagent_manager.dart.
export 'subagent_model.dart' show SubagentSpec;
import 'subagent_permission_gate.dart';
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
    this.contextWindowCap = _noCap,
    this.hostBeforeToolCall = const [],
  });

  static int? _noCap() => null;

  /// Схемы текущего шага родителя (`base` набора ребёнка).
  final List<AgentTool> Function() tools;
  final ModelRef Function() model;

  /// Эффективный режим родителя: `narrow(этот, type.mode)` при каждом решении
  /// ребёнка (SUB-2).
  final ModeResolution Function() mode;

  /// Gate корневой сессии (D8, D42 Т3): через него идут вопросы потомков
  /// всего дерева. `null` — у корня нет gate, и вопрос потомка — отказ
  /// `no approval interface is available` (PERM-5).
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

  /// Наибольшая глубина потомка — `subagents.max_depth`, снимок корневой
  /// сессии на всё дерево (D46, п. 2): `agent` ребёнку даётся, пока его
  /// глубина меньше.
  final int maxChildDepth;

  /// `compaction.context_window_cap` сессии: нужен для правила окна
  /// потомка (D40; `agent` не входит в набор ребёнка с малым окном).
  final int? Function() contextWindowCap;

  /// Хуки хоста `extraBeforeToolCall` корневой сессии, общие на всё дерево
  /// (design.md change `add-subagents-and-tasks`, D48 п. 1; `agent-core/
  /// 17-3-subagents.md` §17.3.3, шаг 6).
  ///
  /// Почему здесь: хосту (ACP-адаптер с `markInProgress`) нужны вызовы
  /// потомков любой глубины; как и gate, хуки корня одни на дерево, а
  /// `nestedFor` передаёт их внукам. Префикс цепочки в них не зашит: его
  /// фабрика берёт из `SubagentSpec.sessionChain` и подставляет отдельным
  /// значением (D45 Т3). `extraAfterToolCall` потомкам не передаются.
  final List<BeforeToolCallHook> hostBeforeToolCall;

  /// Части родителя для менеджера потомка, у которого есть `agent` (D45 Т2).
  ///
  /// Почему копия: gate, навыки, пути, хранилище решений, правила, env,
  /// список задач и блокировки — общие объекты корня; различаются только
  /// схемы шага, модель и режим самого потомка — `narrow` идёт по цепочке
  /// (SUB-2).
  SubagentParent nestedFor({
    required List<AgentTool> Function() tools,
    required ModelRef Function() model,
    required ModeResolution Function() mode,
  }) => SubagentParent(
    tools: tools,
    model: model,
    mode: mode,
    gate: gate,
    skills: skills,
    agentConfigPaths: agentConfigPaths,
    decisions: decisions,
    rules: rules,
    extraDeniedTiers: extraDeniedTiers,
    env: env,
    tasks: tasks,
    locks: locks,
    maxChildDepth: maxChildDepth,
    contextWindowCap: contextWindowCap,
    hostBeforeToolCall: hostBeforeToolCall,
  );
}

/// Связь менеджера потомка с хэндлом его сессии в менеджере родителя
/// (`agent-core/17-3-subagents.md` §17.3.4, шаг 2; design.md change
/// `add-subagents-and-tasks`, D3, D46, п. 1).
///
/// Почему: слот держит хэндл потомка в менеджере родителя, а решает, когда
/// его отдать, менеджер самого потомка — по числу блокирующих вызовов
/// `agent`, ждущих детей.
///
/// Как использовать: менеджер потомка вызывает [callBegan] при каждом
/// запуске ребёнка и [callEnded] при его терминальном состоянии — до того,
/// как ребёнок вернёт свой слот.
abstract interface class SubagentSlotLink {
  /// Начал ждать ещё один `agent`: 0 → 1 переводит хэндл в `waiting`/
  /// `subagents` и возвращает слот.
  void callBegan();

  /// Очередной `agent` дождался: 1 → 0 ставит родителя в очередь
  /// возвращающихся и отдаёт результат — слот получен (`true`) или родитель
  /// отменён в очереди (`false`). `null` — ждущие вызовы ещё есть.
  Future<bool>? callEnded();
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
    this.hostBeforeToolCall = const [],
    required this.env,
    required this.tasks,
    required this.locks,
    required this.logger,
    required this.onOwnUsage,
    required this.ancestorBudget,
    this.parent,
    this.tree,
    this.link,
    this.rootSessionId,
    this.task,
  });

  final SubagentSpec subagent;

  /// Пункт списка, назначенный ребёнку на момент `assign`: строка
  /// `Your task: #<id> <subject>` системного промпта (D10, D45 Т8).
  final TaskItem? task;

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

  /// Хуки хоста корня (`SubagentParent.hostBeforeToolCall`): фабрика ставит
  /// их в цепочку `beforeToolCall` ребёнка последними, после политики, и
  /// отдаёт вызов с `id`-цепочкой (D48 п. 1).
  final List<BeforeToolCallHook> hostBeforeToolCall;
  final ExecutionEnv env;
  final TaskList tasks;
  final PathLock locks;

  /// Логгер ребёнка с `root_session_id`, `subagent_id`, `parent_tool_call_id`;
  /// `session_id` ребёнка фабрика добавляет сама (D18).
  final Logger logger;
  final void Function(Usage own) onOwnUsage;
  final BudgetLimit? Function() ancestorBudget;

  /// Для вложенности (D45 Т2): части родителя, общее дерево слотов, связь со
  /// слотом хэндла и корень дерева. Фабрика собирает потомку свой менеджер,
  /// только если в [tools] есть `agent`.
  final SubagentParent? parent;
  final SubagentTree? tree;
  final SubagentSlotLink? link;
  final SessionId? rootSessionId;
}

/// Дочерняя сессия, собранная фабрикой рантайма: агент со своим писателем
/// журнала. Менеджер только запускает ход, слушает события и закрывает её.
final class ChildSession {
  ChildSession({
    required this.id,
    required this.journalPath,
    required this.agent,
    required Future<void> Function() close,
    this.subagents,
  }) : _close = close;

  final SessionId id;

  /// Непрозрачный адрес журнала от `SessionStore.createChild`.
  final String journalPath;

  /// Первым подписчиком уже стоит писатель журнала ребёнка.
  final Agent agent;

  /// Менеджер потомков самого ребёнка: есть, только если ему дан `agent`
  /// (D45 Т2). Родитель берёт из него число активных потомков.
  final SubagentManager? subagents;
  final Future<void> Function() _close;

  Future<void> close() => _close();
}

/// Фабрика дочерней сессии: приватный метод рантайма (D36 Т2).
typedef ChildSessionFactory =
    Future<ChildSession> Function(ChildSessionSpec spec);

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

  /// Лимиты на сейчас: менеджеры потомков читают их оттуда же (D17).
  SubagentsConfig get config => _limits();

  final _known = <SubagentId>{};

  /// Все потомки дерева регистрируют id здесь: владелец пункта списка —
  /// любой потомок, когда-либо запущенный в дереве (D45 Т8).
  void register(SubagentId id) => _known.add(id);

  /// Потомок с таким id запускался в этом дереве.
  bool knows(SubagentId id) => _known.contains(id);

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

  SubagentQuestionQueue? _questions;

  /// FIFO вопросов дерева к gate корня (D8, D42 Т3): один экземпляр на
  /// дерево, потомки любой глубины оборачивают его, а не gate родителя.
  /// Повторный вызов с тем же [root] возвращает ту же очередь.
  SubagentQuestionQueue wrapGate(PermissionGate root) {
    final existing = _questions;
    if (existing != null && identical(existing.root, root)) {
      return existing;
    }
    return _questions = SubagentQuestionQueue(root);
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
/// Вложенность (D45 Т2): ребёнку с `agent` фабрика дочерней сессии создаёт
/// собственный менеджер на том же [SubagentTree]. Он не сбрасывает счётчик
/// `max_per_turn` (это делает только ход корня), берёт gate корня, а о слоте
/// своей сессии говорит через [SubagentSlotLink]: пока хотя бы один его
/// `agent` ждёт детей, слот сессии возвращён дереву (D46, п. 1).
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
    TurnBudget Function()? ownBudget,
    required SubagentParent Function() parent,
    SubagentSlotLink? link,
    SessionId? rootSessionId,
    BudgetLimit? Function()? upstreamBudget,
  }) : assert(
         ownBudget != null || upstreamBudget != null,
         'the root manager needs ownBudget, a nested one upstreamBudget',
       ),
       _link = link,
       _rootSessionId = rootSessionId ?? sessionId,
       _upstreamBudget = upstreamBudget,
       _limits = limits,
       _emit = emit,
       _create = create,
       _clock = clock,
       _logger = logger,
       _sessionId = sessionId,
       _ownBudget = ownBudget,
       _parent = parent;

  final SubagentTree tree;
  final SubagentsConfig Function() _limits;
  final Future<void> Function(AgentEvent event) _emit;
  final ChildSessionFactory _create;
  final Clock _clock;
  final Logger _logger;
  final SessionId _sessionId;

  /// Бюджет сессии самого менеджера: хода корня или, у менеджера потомка,
  /// бюджет ребёнка (D45 Т5).
  final TurnBudget Function()? _ownBudget;

  /// Связь со слотом хэндла сессии этого менеджера в менеджере её родителя;
  /// у менеджера корня `null` (корень слота не занимает).
  final SubagentSlotLink? _link;

  /// Корень дерева для логов `root_session_id` (D45 Т11): у менеджера корня —
  /// его же сессия, у менеджера потомка — корневая, а `session_id` остаётся
  /// сессией, которая запустила потомка.
  final SessionId _rootSessionId;

  /// Бюджет предков сессии менеджера (`ancestorBudget` её цикла): цепочка до
  /// бюджета хода корня (D4); у менеджера корня `null`.
  final BudgetLimit? Function()? _upstreamBudget;

  /// Части родителя читаются при каждом `spawn`: `_Session` и политика
  /// появляются позже менеджера.
  final SubagentParent Function() _parent;

  final _all = <_Handle>[];

  var _turnHandles = <_Handle>[];
  var _ownUsage = Usage.zero;

  /// Собственный usage сессии менеджера (без потомков: хода корня или
  /// ребёнка): вместе с [childrenUsage] сравнивается с её бюджетом на границе
  /// шага потомка.
  set ownUsage(Usage value) => _ownUsage = value;

  /// Начало хода корня: счётчик запусков и учёт usage детей сбрасываются.
  void beginTurn() {
    tree.resetTurn();
    _turnHandles = [];
    _ownUsage = Usage.zero;
  }

  /// Usage потомков сессии менеджера на сейчас, транзитивно (SUB-11): живой
  /// usage каждого хэндла уже включает его потомков.
  Usage get childrenUsage {
    var total = Usage.zero;
    for (final handle in _turnHandles) {
      total += handle.usageNow;
    }
    return total;
  }

  /// Потомок с таким id когда-либо запускался в дереве (хэндл создан у
  /// любого менеджера дерева, D45 Т8).
  bool knows(SubagentId id) => tree.knows(id);

  /// Потомки менеджера и их потомки в `queued | running | waiting`
  /// (`activeChildren`, §17.3.4, шаг 4).
  int get activeCount {
    var total = 0;
    for (final handle in _all) {
      if (!handle.done) {
        total += 1 + handle.activeChildren;
      }
    }
    return total;
  }

  /// Результат повторного взятия слота ждущим родителем для вызова `agent`
  /// [handle] (D46, п. 1): `false` — родитель отменён в очереди
  /// возвращающихся. Вызывает `SubagentTool` после отчёта, до результата
  /// вызова, поэтому `ToolCallFinished` идёт после повторного взятия.
  Future<bool> settled(SubagentHandle handle) =>
      (handle is _Handle ? handle.resume : null) ?? Future.value(true);

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
    tree.register(handle.id);
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
    // Слот возвращается до постановки ребёнка в очередь: иначе ребёнок
    // получил бы слот родителя раньше его соседей по очереди (§17.3.4,
    // шаг 2; сценарий «Возвращающийся родитель раньше нового ребёнка»).
    _link?.callBegan();
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

  /// Исчерпан ли бюджет предков для потомков этой сессии (D4, D45 Т5): токены
  /// и стоимость бюджета самой сессии менеджера против её usage вместе с
  /// потомками, затем цепочка выше до бюджета хода корня. Время предков не
  /// наследуется. Потомок проверяет это на своей границе шага.
  BudgetLimit? limitForDescendants() {
    // Своя сессия менеджера (корень или промежуточный предок): её бюджет
    // против её usage вместе с потомками, затем цепочка выше до бюджета хода
    // корня (D4, D45 Т5). Время предков не наследуется.
    if (_ownBudget?.call() case final budget?) {
      final total = _ownUsage + childrenUsage;
      if (budget.maxTokens case final max?
          when total.input + total.output >= max) {
        return BudgetLimit.tokens;
      }
      if (budget.maxCost case final max?
          when total.cost.total > 0 && total.cost.total >= max) {
        return BudgetLimit.cost;
      }
    }
    return _upstreamBudget?.call();
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
      handle.holdsSlot = true;
      try {
        await _runLeased(handle);
      } finally {
        _releaseSlot(handle);
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

  /// Возвращает слот дереву, только если им владеет [handle]: потомок,
  /// отменённый в очереди возвращающихся, слота не держит и не может вернуть
  /// чужой (D45 Т4).
  void _releaseSlot(_Handle handle) {
    if (!handle.holdsSlot) {
      return;
    }
    handle.holdsSlot = false;
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

  /// Потомок [handle] начал ждать ещё один `agent` (0 → 1 — вернуть слот;
  /// D46, п. 1).
  void _waitBegan(_Handle handle) {
    handle.waitingCalls++;
    if (handle.done || handle.waitingCalls != 1) {
      return;
    }
    _releaseSlot(handle);
    _syncWaiting(handle);
  }

  /// Один из ждущих `agent` потомка [handle] получил отчёт. Последний
  /// (1 → 0) встаёт в очередь возвращающихся, пока ребёнок ещё держит свой
  /// слот: освободившийся слот достаётся родителю, а не новому ребёнку
  /// (SUB-23).
  Future<bool>? _waitEnded(_Handle handle) {
    if (handle.waitingCalls > 0) {
      handle.waitingCalls--;
    }
    if (handle.waitingCalls > 0 || handle.done) {
      return null;
    }
    if (handle.holdsSlot) {
      _syncWaiting(handle);
      return null;
    }
    return handle.resumePending ??= _resume(handle);
  }

  Future<bool> _resume(_Handle handle) async {
    final leased = await tree.acquire(
      resume: true,
      cancel: handle.source.token,
    );
    handle.resumePending = null;
    if (!leased) {
      _syncWaiting(handle);
      return false;
    }
    handle.holdsSlot = true;
    _logger.log(
      LogLevel.debug,
      'subagent.slot.resume',
      fields: {
        'session_id': _sessionId.value,
        'subagent_id': handle.id,
        'free_slots': tree.freeSlots,
      },
    );
    // Пока родитель стоял в очереди, он мог снова начать ждать детей (или
    // закончиться): слот не должен остаться у ждущего.
    if (handle.done || handle.waitingCalls > 0) {
      _releaseSlot(handle);
    }
    _syncWaiting(handle);
    return true;
  }

  Future<void> _runLeased(_Handle handle) async {
    final spec = handle.spec;
    handle.startedAt = _clock.now();
    handle.setState(SubagentState.running);
    final limits = _limits();
    final parent = _parent();
    final model = spec.type.model ?? parent.model();
    // D40, «Ребёнок»: ребёнок с малым окном `agent` не получает.
    final cap = parent.contextWindowCap();
    final windowOk = subagentWindowOk(model, cap);
    if (!windowOk &&
        spec.depth < parent.maxChildDepth &&
        spec.type.allowsTool('agent')) {
      _logger.log(
        LogLevel.info,
        'subagent.unavailable',
        fields: {
          'session_id': _sessionId.value,
          'subagent_id': handle.id,
          'reason': 'context_window',
          'window': effectiveContextWindow(model, cap: cap),
          'min_window': CompactionSettings.minSubagentContextWindow,
        },
      );
    }
    // `assign` — до создания дочерней сессии (D45 Т8): `TaskListChanged`
    // приходит раньше `SubagentStarted`, а `subject` строки `Your task:`
    // берётся на момент назначения. Прежний владелец не проверяется —
    // последнее назначение побеждает (D46, п. 3).
    TaskItem? assigned;
    if (spec.taskId case final taskId?) {
      final result = await parent.tasks.apply(
        AssignTask(taskId, TaskOwner(spec.id)),
        const MainActor(),
      );
      switch (result) {
        case TaskApplied(:final item):
          assigned = item;
        case TaskRejected():
          // Пункт удалён, пока ребёнок стоял в очереди: назначать некому,
          // ребёнок всё равно работает без пункта (D18).
          _logger.log(
            LogLevel.warning,
            'task.assign.skipped',
            fields: {
              'session_id': _sessionId.value,
              'task_id': taskId,
              'subagent_id': spec.id,
            },
          );
      }
    }
    final childLogger = BoundLogger(_logger, {
      'root_session_id': _rootSessionId.value,
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
          agentVisible: windowOk,
        ),
        model: model,
        budget: TurnBudget(
          maxSteps: limits.maxSteps,
          maxTokens: limits.maxTokens,
          maxCost: limits.maxCost,
          maxDuration: limits.maxDuration,
        ),
        mode: () => narrow(parent.mode(), spec.type.mode),
        gate: switch (parent.gate) {
          final root? => SubagentPermissionGate(
            queue: tree.wrapGate(root),
            spec: spec,
            // Цепочка id вызовов `agent` от корня до сессии потомка (D45 Т3).
            chainPrefix: spec.sessionChain,
            onWaiting: () => _setWaiting(handle, true),
            onResumed: () => _setWaiting(handle, false),
            logger: _logger,
            sessionId: _sessionId.value,
          ),
          null => null,
        },
        skills: parent.skills,
        agentConfigPaths: parent.agentConfigPaths,
        decisions: parent.decisions,
        rules: parent.rules,
        extraDeniedTiers: parent.extraDeniedTiers,
        hostBeforeToolCall: parent.hostBeforeToolCall,
        env: parent.env,
        tasks: SubagentTaskList(
          root: parent.tasks,
          subagentId: spec.id,
          parentToolCallId: spec.sessionChain,
        ),
        locks: parent.locks,
        logger: childLogger,
        onOwnUsage: (own) => handle.ownUsage = own,
        ancestorBudget: limitForDescendants,
        parent: parent,
        tree: tree,
        link: _HandleLink(this, handle),
        rootSessionId: _rootSessionId,
        task: assigned,
      ),
    );
    handle.child = child;
    handle.childManager = child.subagents;
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

  /// Открытый вопрос потомка к gate корня (§17.3.2).
  ///
  /// Почему счётчик: ребёнок может держать несколько открытых вопросов (два
  /// параллельных `write` в одном шаге); состояние пересчитывается по всем
  /// причинам ожидания сразу ([_syncWaiting]), а не после первого ответа
  /// (ревью итерации 3).
  void _setWaiting(_Handle handle, bool waiting) {
    if (waiting) {
      handle.openQuestions++;
    } else if (handle.openQuestions > 0) {
      handle.openQuestions--;
    }
    _syncWaiting(handle);
  }

  /// Состояние потомка по причинам ожидания (D46, п. 1): открытый вопрос —
  /// `waiting`/`approval`, иначе ждущие дети или возврат слота —
  /// `waiting`/`subagents` (`approval` важнее), иначе `running`.
  /// Терминальное состояние не трогается: отмена во время ожидания побеждает
  /// (D5). Прогресс уходит при любой смене состояния или причины.
  void _syncWaiting(_Handle handle) {
    if (handle.done ||
        (handle.state != SubagentState.running &&
            handle.state != SubagentState.waiting)) {
      return;
    }
    final SubagentWait? reason = handle.openQuestions > 0
        ? SubagentWait.approval
        : (handle.waitingCalls > 0 || handle.resumePending != null)
        ? SubagentWait.subagents
        : null;
    final next = reason == null ? SubagentState.running : SubagentState.waiting;
    if (handle.state == next && handle.waitingFor == reason) {
      return;
    }
    handle.waitingFor = reason;
    handle.setState(next);
    unawaited(_progress(handle, force: true));
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
      // Вызовы потомков входят в итог ребёнка транзитивно (D45 Т5).
      case SubagentActivity(event: ToolCallStarted(:final title)):
        handle.toolCalls++;
        handle.lastActivity = title;
      case TurnEnded():
        handle.ended = event;
      case AgentError(:final message):
        handle.lastError = message;
      default:
        break;
    }
    // Обёртка плоская (D6, D45 Т6): событие внука уже несёт свой адрес —
    // меняется только сессия, а не вкладывается вторая обёртка.
    await _emit(
      event is SubagentActivity
          ? SubagentActivity(
              _sessionId,
              subagentId: event.subagentId,
              parentToolCallId: event.parentToolCallId,
              path: event.path,
              depth: event.depth,
              event: event.event,
            )
          : SubagentActivity(
              _sessionId,
              subagentId: handle.id,
              parentToolCallId: handle.spec.parentToolCallId,
              path: handle.spec.path,
              depth: handle.spec.depth,
              event: event,
            ),
    );
    if (event is StepEnded ||
        event is ToolCallStarted ||
        (event is SubagentActivity && event.event is ToolCallStarted)) {
      await _progress(handle);
    } else if (event is SubagentStarted || event is SubagentFinished) {
      // Число активных потомков ребёнка изменилось (`activeChildren`).
      await _progress(handle, force: true);
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

  /// Строка о том, что ответ ребёнка оборван лимитом выходных токенов
  /// (D41, п. 6; `17-3-subagents.md` §17.3.5).
  static const _outputLimitNote =
      '[report truncated: the subagent hit the output token limit]';

  SubagentReport _buildReport(_Handle handle) {
    final ended = handle.ended;
    if (ended != null) {
      // Итоговый usage хода ребёнка уже включает его потомков: живую сумму
      // «свой + менеджер потомков» заменяет окончательное значение.
      handle.finalUsage = ended.usage;
    }
    final text = _lastText(handle.child?.agent.messages ?? const []);
    final SubagentState status;
    SubagentFailure? failure;
    BudgetLimit? limit;
    String? message;
    var cutByLimit = false;
    String? noReportBody;
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
          } else if (ended.reason == TurnEndReason.maxTokens &&
              text.trim().isEmpty) {
            // Лимит ушёл в рассуждения: отчёта нет (D41, п. 6).
            status = SubagentState.failed;
            failure = SubagentFailure.maxTokens;
            // Текст нужен клиенту: SubagentFinished.report — единственное
            // тело, которое ACP покажет у failed-вызова.
            noReportBody = subagentNoReportAtOutputLimit;
          } else {
            status = SubagentState.completed;
            cutByLimit = ended.reason == TurnEndReason.maxTokens;
          }
      }
    }
    final cut = truncateReport(text, _limits().reportMaxBytes);
    return handle.reportOf(
      status,
      failure: failure,
      limit: limit,
      // Пометка лимита — после усечения по report_max_bytes, чтобы оно её не
      // отрезало; пометки разных видов независимы, атрибут один (D41, п. 6).
      text:
          noReportBody ??
          (cutByLimit ? '${cut.text}\n$_outputLimitNote' : cut.text),
      truncated: cut.truncated || cutByLimit,
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
    // Родитель встаёт в очередь возвращающихся до того, как ребёнок вернёт
    // слот (SUB-23); результат ждёт `SubagentTool` через [settled].
    handle.resume = _link?.callEnded();
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
        // Раздельные счётчики (D18; D41, п. 2 и 7): сумма скрывала перекос входа и
        // выхода, а числовые поля не маскируются SecretRedactor.
        'tokens_in': report.usage.input,
        'tokens_out': report.usage.output,
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
          truncated: report.truncated,
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

  /// Менеджер потомков самого потомка (`activeChildren`, D45 Т5).
  SubagentManager? childManager;

  /// Слот держит именно этот хэндл (`release` — только у держателя, D45 Т4).
  bool holdsSlot = false;

  /// Блокирующих `agent` потомка, ждущих детей, и возврат слота в очереди
  /// возвращающихся (D46, п. 1).
  int waitingCalls = 0;
  Future<bool>? resumePending;

  /// Результат возврата слота для вызова `agent`, который запустил этот
  /// хэндл (`null` — возвращать нечего).
  Future<bool>? resume;

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

  /// Чего ждёт потомок в `waiting`; вне `waiting` снимок его не показывает.
  SubagentWait? waitingFor;

  /// Открытых вопросов потомка к gate корня; `waiting` держится, пока не 0.
  int openQuestions = 0;

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

  /// Активные потомки потомка, транзитивно.
  int get activeChildren => childManager?.activeCount ?? 0;

  /// Usage потомка на сейчас: живой — по шагам цикла, после итога — отчёта.
  Usage get usageNow =>
      finalUsage ?? ownUsage + (childManager?.childrenUsage ?? Usage.zero);

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
    waitingFor: _state == SubagentState.waiting ? waitingFor : null,
    activeChildren: done ? 0 : activeChildren,
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

/// Связь менеджера потомка со слотом его хэндла в менеджере родителя
/// (D46, п. 1): делегирует счётчик ждущих `agent` менеджеру-владельцу
/// хэндла, где живут слот и состояние `waiting`/`subagents`.
final class _HandleLink implements SubagentSlotLink {
  _HandleLink(this._manager, this._handle);

  final SubagentManager _manager;
  final _Handle _handle;

  @override
  void callBegan() => _manager._waitBegan(_handle);

  @override
  Future<bool>? callEnded() => _manager._waitEnded(_handle);
}
