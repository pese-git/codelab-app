import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';

import '../session/session_views.dart';
import 'transcript_item.dart';

/// Изменение списка задач за один вызов.
///
/// Почему: сам вызов (`think`) ничего не говорит о содержании; изменение
/// берётся из `plan._meta.codelab.taskChange` (design.md change
/// `add-subagents-and-tasks`, D27, D35).
///
/// Для чего: основа [TaskOpsItem]; поля — id пунктов в порядке плана.
final class TaskDiff {
  const TaskDiff({
    this.added = const [],
    this.completed = const [],
    this.removed = const [],
    this.updated = const [],
  });

  final List<String> added;
  final List<String> completed;
  final List<String> removed;
  final List<String> updated;

  bool get isEmpty =>
      added.isEmpty && completed.isEmpty && removed.isEmpty && updated.isEmpty;

  /// Слияние подряд идущих операций: списки объединяются без повторов.
  ///
  /// Пункт, добавленный и затем удалённый внутри слияния, из итога исчезает
  /// (его не было ни до, ни после); id удалённого пункта не остаётся и в
  /// `completed`/`updated`.
  TaskDiff merge(TaskDiff other) {
    final gone = other.removed.toSet();
    List<String> kept(List<String> ids) => [
      for (final id in ids)
        if (!gone.contains(id)) id,
    ];
    return TaskDiff(
      added: _union(kept(added), other.added),
      completed: _union(kept(completed), other.completed),
      removed: _union(removed, [
        for (final id in other.removed)
          if (!added.contains(id)) id,
      ]),
      updated: _union(kept(updated), other.updated),
    );
  }

  static List<String> _union(List<String> a, List<String> b) => [
    ...a,
    for (final id in b)
      if (!a.contains(id)) id,
  ];
}

/// Ключ `plan._meta.codelab.taskChange` (design.md change
/// `add-subagents-and-tasks`, D35); `null` при отсутствии и при любой
/// неверной форме (ключ неверной формы — как отсутствующий).
Map<String, Object?>? taskChangeOf(Map<String, Object?>? planMeta) {
  final codelab = planMeta?['codelab'];
  final change = codelab is Map ? codelab['taskChange'] : null;
  return change is Map ? change.cast<String, Object?>() : null;
}

/// Есть ли у `plan` ключ `taskChange` с `toolCallId`: только такой `plan`
/// может превратить вызов в операцию со списком.
bool hasTaskChangeCall(Map<String, Object?>? planMeta) =>
    taskChangeOf(planMeta)?['toolCallId'] is String;

List<String> _ids(Object? value) => value is List
    ? [
        for (final v in value)
          if (v is String) v,
      ]
    : const [];

/// Операции со списком задач хода: `toolCallId → разница`.
///
/// Почему: вызов опознаётся только по ключу `plan._meta.codelab.taskChange`
/// (D35): порядок кадров и сравнение планов дают ложные срабатывания у
/// сторонних агентов и приписывают чужую операцию при параллельных вызовах.
///
/// Для чего: вызов корневого уровня вида `think`, без
/// `_meta.codelab.subagent`, завершившийся `completed`, на который ссылается
/// `taskChange.toolCallId` хотя бы одного `plan`, становится операцией.
/// Разница строится из `op` и `changed`/`deleted`; `completed` у `update`
/// определяется сравнением пункта с предыдущим планом сессии — только для
/// слова «done». `plan` без ключа и ключ без `toolCallId` (`restore`,
/// `assign`) только обновляют план; `failed` и вызовы без ссылки остаются
/// обычными.
///
/// Как использовать: [prior] — план, действовавший к началу хода (последний
/// `plan` предыдущих ходов).
Map<ToolCallId, TaskDiff> taskOperationsOf(
  PromptTurn turn,
  List<PlanEntry>? prior,
) {
  final diffs = <String, TaskDiff>{};
  final subagent = <String>{};
  final nested = <String>{};
  var plan = prior ?? const <PlanEntry>[];

  for (final update in turn.updates) {
    switch (update) {
      case ToolCallSessionUpdate(:final toolCall):
        if (_hasSubagent(toolCall.meta)) {
          subagent.add(toolCall.toolCallId.value);
        }
        if (_parentOf(toolCall.meta) != null) {
          nested.add(toolCall.toolCallId.value);
        }
      case ToolCallUpdateSessionUpdate(:final toolCallUpdate):
        if (_hasSubagent(toolCallUpdate.meta)) {
          subagent.add(toolCallUpdate.toolCallId.value);
        }
      case PlanUpdate(:final entries, :final meta):
        final change = taskChangeOf(meta);
        final callId = change?['toolCallId'];
        if (change != null && callId is String) {
          final diff = _diffOf(change, before: plan, after: entries);
          diffs[callId] = diffs[callId]?.merge(diff) ?? diff;
        }
        plan = entries;
      default:
    }
  }

  final result = <ToolCallId, TaskDiff>{};
  for (final MapEntry(key: callId, value: diff) in diffs.entries) {
    final record = turn.toolCalls[ToolCallId(callId)];
    if (record == null ||
        record.kind != ToolKind.think ||
        record.status != ToolCallStatus.completed ||
        record.cancelledByClient ||
        subagent.contains(callId) ||
        nested.contains(callId) ||
        // Пустое изменение (например, `changed` пуст) — не операция: вызов
        // остаётся обычной строкой (D27).
        diff.isEmpty) {
      continue;
    }
    result[ToolCallId(callId)] = diff;
  }
  return result;
}

TaskDiff _diffOf(
  Map<String, Object?> change, {
  required List<PlanEntry> before,
  required List<PlanEntry> after,
}) {
  final changed = _ids(change['changed']);
  final deleted = _ids(change['deleted']);
  switch (change['op']) {
    case 'create':
      return TaskDiff(added: changed);
    case 'delete':
      // Только `deleted`: `changed` при удалении — пункты, у которых сняли
      // блокер, они не удалены (D35).
      return TaskDiff(removed: deleted);
    default:
      // `update` и прочее: «done» — пункт `completed` в этом плане и не
      // `completed` в предыдущем; иначе «updated».
      PlanEntryStatus? statusIn(List<PlanEntry> plan, String id) {
        for (final entry in plan) {
          if (taskMetaOf(entry)?['id'] == id) {
            return entry.status;
          }
        }
        return null;
      }

      final done = <String>[];
      final updated = <String>[];
      for (final id in changed) {
        final isDone =
            statusIn(after, id) == PlanEntryStatus.completed &&
            statusIn(before, id) != PlanEntryStatus.completed;
        (isDone ? done : updated).add(id);
      }
      return TaskDiff(completed: done, updated: updated, removed: deleted);
  }
}

/// План, действовавший к концу хода [turn] (после [prior]).
List<PlanEntry>? lastPlanOf(PromptTurn turn, List<PlanEntry>? prior) {
  var latest = prior;
  for (final update in turn.updates) {
    if (update case PlanUpdate(:final entries)) {
      latest = entries;
    }
  }
  return latest;
}

/// Заменяет вызовы-операции [ops] в [body] элементами [TaskOpsItem] и
/// сливает подряд идущие.
List<TranscriptItem> withTaskOps(
  List<TranscriptItem> body,
  Map<ToolCallId, TaskDiff> ops,
) {
  if (ops.isEmpty) {
    return body;
  }
  final result = <TranscriptItem>[];
  TaskDiff? merged;
  for (final item in body) {
    if (item case ToolCallItem(
      :final id,
      :final toolCallId,
    ) when ops.containsKey(toolCallId)) {
      final diff = ops[toolCallId]!;
      if (result.isNotEmpty && result.last is TaskOpsItem) {
        merged = merged!.merge(diff);
        if (merged.isEmpty) {
          // Добавленное и тут же удалённое взаимно уничтожилось.
          result.removeLast();
          continue;
        }
        result[result.length - 1] = _item(
          (result.last as TaskOpsItem).id,
          merged,
        );
      } else {
        merged = diff;
        result.add(_item(id, diff));
      }
    } else {
      result.add(item);
    }
  }
  return result;
}

TaskOpsItem _item(String id, TaskDiff diff) => TaskOpsItem(
  id: id,
  added: diff.added,
  completed: diff.completed,
  removed: diff.removed,
  updated: diff.updated,
);

bool _hasSubagent(Map<String, Object?>? meta) {
  final codelab = meta?['codelab'];
  return codelab is Map && codelab['subagent'] is Map;
}

ToolCallId? _parentOf(Map<String, Object?>? meta) {
  final codelab = meta?['codelab'];
  final parent = codelab is Map ? codelab['parentToolCallId'] : null;
  return parent is String ? ToolCallId(parent) : null;
}
