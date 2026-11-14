import 'subagent_model.dart';
import '../tools/tasks/task_list.dart';

/// Список задач ребёнка: обёртка над общим списком корня (`agent-core/
/// 17-16-task-list.md` §17.16.4; design.md change `add-subagents-and-tasks`,
/// D35, D36 Т7).
///
/// Почему обёртка, а не отдельный список: список один на дерево и
/// принадлежит корневой сессии и её клиенту; ребёнок со своим планом сбил бы
/// клиента. Инструменты `task_*` — те же классы, что у корня; различается
/// только `ToolServices.tasks`.
///
/// Для чего: подменяет актора на `SubagentActor(id)`, проверяет TSK-4
/// (ребёнок меняет только `status` пунктов, владелец которых — он сам) и
/// строит `toolCallId` операции как цепочку `<вызов agent корня>/<вызов
/// ребёнка>` глубины 1: сырой `call_1` ребёнка совпал бы с `call_1` корня, и
/// клиент приписал бы операцию чужому вызову (D35).
///
/// Как использовать: фабрика дочерней сессии кладёт её в `ToolServices.tasks`
/// ребёнка. Пункт ребёнку назначает корень (`assign` — итерация 4).
final class SubagentTaskList implements TaskList {
  SubagentTaskList({
    required this.root,
    required this.subagentId,
    required this.parentToolCallId,
  });

  final TaskList root;
  final SubagentId subagentId;

  /// Вызов `agent` в сессии родителя (первый сегмент цепочки).
  final String parentToolCallId;

  static const _denied = TaskRejected(
    'Subagents may change only the status of their own tasks.',
    TaskRejectReason.owner,
  );

  @override
  List<TaskItem> get items => root.items;

  @override
  List<TaskId> blocksOf(TaskId id) => root.blocksOf(id);

  @override
  Future<TaskResult> apply(
    TaskOp op,
    TaskActor actor, {
    String? toolCallId,
    TaskRejected? Function(List<TaskItem> items)? precheck,
  }) {
    if (op is! UpdateTask) {
      return Future.value(_denied);
    }
    final onlyStatus =
        op.status != null &&
        op.subject == null &&
        op.description == null &&
        op.priority == null &&
        op.owner == null &&
        op.blockedBy == null;
    return root.apply(
      op,
      SubagentActor(subagentId),
      toolCallId: toolCallId == null
          ? parentToolCallId
          : '$parentToolCallId/$toolCallId',
      // Владелец проверяется под замком списка, в том состоянии, в котором
      // операция применится: корень мог переназначить пункт после проверки
      // «снаружи» (TSK-4).
      precheck: (items) {
        final item = items.where((i) => i.id == op.id).firstOrNull;
        // Неизвестный id получает обычную ошибку списка.
        if (item == null) {
          return onlyStatus ? null : _denied;
        }
        return !onlyStatus || item.owner.value != subagentId ? _denied : null;
      },
    );
  }

  @override
  Future<void> restore(
    List<TaskItem> items, {
    required int nextId,
    required bool announce,
  }) => throw StateError('a subagent cannot restore the task list');
}
