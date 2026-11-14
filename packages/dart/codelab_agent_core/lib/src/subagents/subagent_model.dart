import '../llm/usage.dart';
import '../loop/turn_budget.dart';

/// Идентификатор субагента: `sub_` и восемь символов `[0-9a-z]` от
/// `IdGenerator` (`agent-core/17-3-subagents.md` §17.3.2; design.md change
/// `add-subagents-and-tasks`, D28, D36 Т6).
typedef SubagentId = String;

/// Состояния хэндла потомка (§17.3.2). Терминальное — ровно одно (SUB-4).
enum SubagentState { queued, running, waiting, completed, failed, cancelled }

/// Чего ждёт потомок в состоянии `waiting`.
enum SubagentWait { approval, subagents }

/// Причина `failed`; значение `failure` записи журнала и `_meta` ACP.
enum SubagentFailure {
  error,
  budgetExceeded,
  invalidOutput,
  interrupted,
  refused,
}

/// Признак вызова `agent` с первого кадра: id и тип, зарезервированные
/// `SubagentTool.present` до `ToolCallStarted` (D28).
final class SubagentCallRef {
  const SubagentCallRef({required this.id, required this.type});

  final SubagentId id;

  /// Имя типа субагента из аргументов вызова.
  final String type;

  @override
  bool operator ==(Object other) =>
      other is SubagentCallRef && other.id == id && other.type == type;

  @override
  int get hashCode => Object.hash(id, type);
}

/// Снимок потомка для прогресса и доски (§17.3.2).
///
/// Почему неизменяемый снимок: события `SubagentProgress` уходят подписчикам
/// асинхронно, а хэндл продолжает меняться.
final class SubagentSnapshot {
  const SubagentSnapshot({
    required this.id,
    required this.parentToolCallId,
    required this.agent,
    required this.description,
    required this.depth,
    required this.state,
    this.waitingFor,
    this.steps = 0,
    this.toolCalls = 0,
    this.usage = Usage.zero,
    this.activeChildren = 0,
    required this.startedAt,
    this.endedAt,
    this.lastActivity,
  });

  final SubagentId id;
  final String parentToolCallId, agent, description;
  final int depth;
  final SubagentState state;

  /// Только при `state == waiting`.
  final SubagentWait? waitingFor;
  final int steps, toolCalls;

  /// Вместе с потомками потомка.
  final Usage usage;

  /// Потомки в `queued | running | waiting`.
  final int activeChildren;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Заголовок последнего `ToolCallStarted` потомка или его потомка.
  final String? lastActivity;
}

/// Итог потомка (§17.3.2, §17.3.5): текст, статус, счётчики вместе с
/// потомками.
final class SubagentReport {
  const SubagentReport({
    required this.id,
    required this.agent,
    required this.status,
    this.failure,
    this.budgetExceeded,
    this.text = '',
    this.truncated = false,
    this.steps = 0,
    this.toolCalls = 0,
    this.usage = Usage.zero,
    this.duration = Duration.zero,
    this.failureMessage,
  });

  final SubagentId id;
  final String agent;

  /// `completed | failed | cancelled`.
  final SubagentState status;
  final SubagentFailure? failure;

  /// При `failure == budgetExceeded`.
  final BudgetLimit? budgetExceeded;

  /// Финальный текст ребёнка после усечения.
  final String text;
  final bool truncated;
  final int steps, toolCalls;
  final Usage usage;
  final Duration duration;

  /// Текст ошибки ребёнка для тела `Subagent failed: …`.
  final String? failureMessage;
}

/// Что агент умеет сообщить клиенту о субагентах: значение геттера
/// `AgentRuntime.subagents` (design.md change `add-subagents-and-tasks`,
/// D37).
///
/// Почему отдельный тип: объявление в `initialize` строится по живому
/// применённому конфигу, а не по `CorePlan`; поле одно — глубина.
final class SubagentsInfo {
  const SubagentsInfo({required this.maxDepth});

  /// `subagents.max_depth` применённого конфига.
  final int maxDepth;
}
