/// Список задач сессии (`agent-core/17-16-task-list.md` §17.16.2;
/// change `add-subagents-and-tasks`, D13, D29).
///
/// Почему отдельная библиотека без событий: типы нужны и событию
/// `TaskListChanged`, и записи журнала `task`, и инструментам `task_*`;
/// здесь нет ни одного импорта цикла или журнала, поэтому они не образуют
/// циклов зависимостей.
library;

import 'dart:async';

import '../../util/logger.dart';

/// Id пункта: десятичная строка, растёт и не переиспользуется (TSK-3).
typedef TaskId = String;

/// Наибольший допустимый числовой id в журнале.
///
/// Почему предел: id приходят из файла, который могли испортить или
/// подделать; без предела запись с огромным id переполнила бы счётчик
/// (TSK-3). Живых пунктов не больше 100, поэтому миллиона хватает с запасом.
const maxTaskIdValue = 1000000;

/// Разбирает id из журнала: десятичная строка от 1 до [maxTaskIdValue].
///
/// Бросает [FormatException] — запись уходит в карантин как нечитаемая
/// (`parseSessionLines`).
TaskId parseTaskId(Object? raw) {
  if (raw is String && RegExp(r'^[1-9][0-9]{0,6}$').hasMatch(raw)) {
    if (int.parse(raw) <= maxTaskIdValue) {
      return raw;
    }
  }
  throw FormatException('invalid task id', raw);
}

/// Статус пункта; значения совпадают с ACP `PlanEntryStatus`.
enum TaskStatus {
  pending('pending'),
  inProgress('in_progress'),
  completed('completed');

  const TaskStatus(this.wire);

  /// Имя на проводе и в журнале (`in_progress`).
  final String wire;

  static TaskStatus? fromWire(Object? value) {
    for (final status in values) {
      if (status.wire == value) {
        return status;
      }
    }
    return null;
  }
}

/// Приоритет пункта; значения совпадают с ACP `PlanEntryPriority`.
enum TaskPriority { high, medium, low }

/// Владелец пункта: `main` или id субагента дерева (§17.16.4).
extension type const TaskOwner(String value) {
  static const main = TaskOwner('main');
}

/// Пункт списка задач: снимок одной задачи в конкретный момент.
///
/// Почему неизменяемый: пункт попадает в событие `TaskListChanged`, запись
/// журнала `task` и сводки для модели; изменяемый объект позволил бы одному
/// потребителю испортить снимок другого (TSK-1).
///
/// Для чего: хранит поля §17.16.2 (`subject` 1–200 символов, `description`
/// до 4000, статус, приоритет, владелец, блокеры). Значимые `==` и `hashCode`
/// нужны сравнению списков в тестах и проекциях.
///
/// Как использовать: создаёт `SessionTaskList` по операции модели или
/// `TaskItem.fromJson` при чтении журнала; изменение — через [copyWith].
/// Проверки длин делает список, а не конструктор.
final class TaskItem {
  TaskItem({
    required this.id,
    required this.subject,
    this.description,
    this.status = TaskStatus.pending,
    this.priority = TaskPriority.medium,
    this.owner = TaskOwner.main,
    List<TaskId> blockedBy = const [],
  }) : blockedBy = List.unmodifiable(blockedBy);

  final TaskId id;
  final String subject;
  final String? description;
  final TaskStatus status;
  final TaskPriority priority;
  final TaskOwner owner;

  /// По возрастанию id, без удалённых пунктов.
  final List<TaskId> blockedBy;

  TaskItem copyWith({
    String? subject,
    Object? description = _keep,
    TaskStatus? status,
    TaskPriority? priority,
    TaskOwner? owner,
    List<TaskId>? blockedBy,
  }) => TaskItem(
    id: id,
    subject: subject ?? this.subject,
    description: identical(description, _keep)
        ? this.description
        : description as String?,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    owner: owner ?? this.owner,
    blockedBy: blockedBy ?? this.blockedBy,
  );

  /// Снимок записи журнала `task`: порядок ключей фиксирован (§17.16.6), чтобы
  /// запись побайтово совпадала с исходной строкой.
  Map<String, Object?> toJson() => {
    'id': id,
    'subject': subject,
    'description': ?description,
    'status': status.wire,
    'priority': priority.name,
    'owner': owner.value,
    'blockedBy': blockedBy,
  };

  /// Терпимый разбор снимка: неизвестный статус — `pending`, приоритет —
  /// `medium`, как у остальных записей журнала.
  factory TaskItem.fromJson(Map<String, Object?> json) => TaskItem(
    id: parseTaskId(json['id']),
    subject: '${json['subject'] ?? ''}',
    description: json['description'] as String?,
    status: TaskStatus.fromWire(json['status']) ?? TaskStatus.pending,
    priority:
        TaskPriority.values.asNameMap()[json['priority']] ??
        TaskPriority.medium,
    owner: TaskOwner('${json['owner'] ?? 'main'}'),
    blockedBy: [
      for (final id in json['blockedBy'] as List<Object?>? ?? const [])
        parseTaskId(id),
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is TaskItem &&
      other.id == id &&
      other.subject == subject &&
      other.description == description &&
      other.status == status &&
      other.priority == priority &&
      other.owner == owner &&
      _sameIds(other.blockedBy, blockedBy);

  @override
  int get hashCode => Object.hash(
    id,
    subject,
    description,
    status,
    priority,
    owner,
    Object.hashAll(blockedBy),
  );

  @override
  String toString() => 'TaskItem(#$id ${status.wire} $subject)';
}

const Object _keep = Object();

bool _sameIds(List<TaskId> a, List<TaskId> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Кто выполняет операцию: корневая сессия или субагент (§17.16.4).
///
/// [SubagentActor] хранит id строкой до итерации 2 change
/// `add-subagents-and-tasks`: тип `SubagentId` появится там и заменит строку.
sealed class TaskActor {
  const TaskActor();

  /// Значение поля `actor` записи журнала.
  String get wire;

  static TaskActor fromWire(Object? value) => value is String && value != 'main'
      ? SubagentActor(value)
      : const MainActor();
}

/// Операцию выполняет корневая сессия: ей доступны все четыре инструмента и
/// любые поля любого пункта (§17.16.4).
///
/// Почему отдельный класс, а не строка: права определяются типом актора
/// (TSK-4), а `switch` по sealed-иерархии не пропустит новый вид актора.
/// Как использовать: инструменты корня передают `const MainActor()`; в журнале
/// это `"actor":"main"`.
final class MainActor extends TaskActor {
  const MainActor();

  @override
  String get wire => 'main';

  @override
  bool operator ==(Object other) => other is MainActor;

  @override
  int get hashCode => 0;
}

/// Операцию выполняет субагент дерева — id как в `_meta.codelab.subagent`.
///
/// Почему он отделён от [MainActor]: потомок меняет только статус своих
/// пунктов (TSK-4, §17.16.4); проверку делает слой инструментов итерации 4
/// change `add-subagents-and-tasks` по этому типу. В 1.0 корня потомков
/// ещё нет, класс нужен формату журнала: запись `task` уже несёт `actor`.
/// Как использовать: `SubagentActor('sub_k3f9a1c2')`; в журнале id как есть.
final class SubagentActor extends TaskActor {
  const SubagentActor(this.id);

  final String id;

  @override
  String get wire => id;

  @override
  bool operator ==(Object other) => other is SubagentActor && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Операция над списком задач.
///
/// Почему sealed: [TaskList.apply] обязан обработать каждый вид операции, и
/// компилятор не даст забыть новый. Проверки и применение — в
/// [TaskList.apply], а не в самой операции: она только описывает намерение
/// модели (§17.16.2).
/// Как использовать: инструмент строит [CreateTask], [UpdateTask] или
/// [DeleteTask] из аргументов вызова и передаёт в [TaskList.apply].
sealed class TaskOp {
  const TaskOp();
}

/// Создать пункт: id выдаёт список, а не вызывающий (TSK-3).
///
/// Почему поля необязательные: `task_create` принимает только `subject`;
/// приоритет по умолчанию `medium`, владелец — `main`, блокеров нет.
/// Как использовать: `CreateTask(subject: 'Read the test', blockedBy: ['1'])`.
final class CreateTask extends TaskOp {
  const CreateTask({
    required this.subject,
    this.description,
    this.priority,
    this.owner,
    this.blockedBy,
  });

  final String subject;
  final String? description;
  final TaskPriority? priority;
  final TaskOwner? owner;
  final List<TaskId>? blockedBy;
}

/// Изменить поля одного пункта.
///
/// Почему `null` значит «не менять»: модель присылает только изменённые поля
/// (`task_update`). `blockedBy` заменяет список целиком, пустой список снимает
/// все блокеры; пустое описание сбрасывает описание.
/// Как использовать: `UpdateTask('2', status: TaskStatus.completed)`. Статус
/// «deleted» — это [DeleteTask], не [UpdateTask].
final class UpdateTask extends TaskOp {
  const UpdateTask(
    this.id, {
    this.subject,
    this.description,
    this.status,
    this.priority,
    this.owner,
    this.blockedBy,
  });

  final TaskId id;
  final String? subject;
  final String? description;
  final TaskStatus? status;
  final TaskPriority? priority;
  final TaskOwner? owner;
  final List<TaskId>? blockedBy;
}

/// Удалить пункт вместе с его id в `blocked_by` остальных (§17.16.3).
///
/// Почему отдельная операция: у неё другой результат (`deleted`, очистка
/// блокеров, запись журнала `op: delete`). Удалённый id больше не выдаётся
/// (TSK-3). Как использовать: `DeleteTask('3')`.
final class DeleteTask extends TaskOp {
  const DeleteTask(this.id);

  final TaskId id;
}

/// Что записать в журнал и показать клиенту (§17.16.2).
///
/// [op] — `create`, `update`, `delete`, `assign` или `restore`.
final class TaskChange {
  TaskChange({
    required this.op,
    required this.actor,
    required List<TaskItem> changed,
    required List<TaskId> deleted,
    this.toolCallId,
  }) : changed = List.unmodifiable(changed),
       deleted = List.unmodifiable(deleted);

  final String op;
  final TaskActor actor;

  /// Вызов `task_*`, применивший операцию, — в пространстве id корня (у
  /// потомка цепочка D8, с итерации 4); `null` у `assign` и `restore`.
  /// Клиент по нему привязывает `plan` к вызову (D35,
  /// `plan._meta.codelab.taskChange.toolCallId`).
  final String? toolCallId;
  final List<TaskItem> changed;
  final List<TaskId> deleted;

  /// Восстановление не операцией модели: журнал его не пишет (TSK-1).
  static const restoreOp = 'restore';
}

/// Итог [TaskList.apply].
sealed class TaskResult {
  const TaskResult();
}

/// Операция принята; список уже изменён и опубликован.
final class TaskApplied extends TaskResult {
  TaskApplied({
    required this.change,
    required this.item,
    required List<TaskItem> snapshot,
    List<TaskItem> unblocked = const [],
  }) : snapshot = List.unmodifiable(snapshot),
       unblocked = List.unmodifiable(unblocked);

  final TaskChange change;

  /// Список сразу после этой операции. Сводку и заметки для модели строят по
  /// нему, а не по `TaskList.items`: к моменту, когда инструмент продолжит
  /// работу, замок мог уже отдать список следующей операции.
  final List<TaskItem> snapshot;

  /// Созданный или изменённый пункт; `null` у удаления.
  final TaskItem? item;

  /// Пункты, которые эта операция освободила от последнего блокера.
  final List<TaskItem> unblocked;
}

/// Причина отклонения операции; [wire] попадает в лог `task.rejected`.
enum TaskRejectReason {
  validation('validation'),
  limit('limit'),
  unknownId('unknown_id'),
  cycle('cycle'),
  owner('owner'),
  blockedBy('blocked_by');

  const TaskRejectReason(this.wire);

  final String wire;
}

/// Операция отклонена: [message] — текст для модели, список не менялся.
final class TaskRejected extends TaskResult {
  const TaskRejected(this.message, this.reason);

  final String message;
  final TaskRejectReason reason;
}

/// Доставка изменения подписчикам сессии; ждётся до `ToolCallFinished`.
typedef TaskListPublisher =
    FutureOr<void> Function(List<TaskItem> items, TaskChange change);

/// Порт списка задач дерева (§17.16.2, D29).
///
/// Порт нейтрален к источнику состояния: [restore] значит «состояние пришло
/// извне», а не «пришло из ветки журнала». Будущая общая доска команды —
/// другая реализация (§17.16.9).
abstract interface class TaskList {
  /// Живые пункты в порядке создания.
  List<TaskItem> get items;

  /// Обратные рёбра `blockedBy`: пункты, перечисляющие [id] блокером.
  List<TaskId> blocksOf(TaskId id);

  /// Проверяет и применяет операцию атомарно; публикует `TaskListChanged` до
  /// возврата. Отклонение — [TaskRejected], список не меняется.
  ///
  /// [toolCallId] — вызов инструмента, применивший операцию: уходит в
  /// `TaskChange.toolCallId` и далее в `plan._meta.codelab.taskChange` (D35);
  /// также попадает в логи (`task.op`, `task.rejected`).
  Future<TaskResult> apply(TaskOp op, TaskActor actor, {String? toolCallId});

  /// Состояние пришло извне (§17.16.6): при [announce] — один
  /// `TaskListChanged` с `op: restore`. Счётчик id не убывает (TSK-3).
  Future<void> restore(
    List<TaskItem> items, {
    required int nextId,
    required bool announce,
  });
}

/// Максимум живых пунктов (§17.16.1).
const maxTaskItems = 100;

/// Список дерева сессии, состояние которого выводится из журнала корня.
///
/// Почему замок: параллельные вызовы пакета и вызовы потомков должны
/// применяться по одному в порядке прихода, и каждая проверка видит состояние
/// после предыдущей (TSK-1, TSK-2).
///
/// Как использовать: сессия создаёт один экземпляр на дерево, кладёт его в
/// `ToolServices.tasks` и задаёт [publish] (эмит `TaskListChanged` в очередь
/// `Agent`). Инструменты зовут [apply]; открытие сессии и смена ветки —
/// [restore].
final class SessionTaskList implements TaskList {
  SessionTaskList({
    this.publish,
    bool Function(TaskOwner owner)? isKnownOwner,
    this.logger,
    this.sessionId,
  }) : _isKnownOwner = isKnownOwner ?? ((owner) => owner == TaskOwner.main);

  /// Логи `task.op`, `task.rejected`, `task.publish.failed` (D18, `AGENTS.md`
  /// §16). В них нет текстов пунктов: только операция, актор, id и причина.
  final Logger? logger;

  /// Корневая сессия дерева — поле `session_id` логов.
  final String? sessionId;

  /// `null` — список хранится, но никому не публикуется.
  TaskListPublisher? publish;

  final bool Function(TaskOwner owner) _isKnownOwner;
  var _items = <TaskItem>[];
  var _nextId = 1;
  Future<void> _tail = Future.value();

  @override
  List<TaskItem> get items => List.unmodifiable(_items);

  @override
  List<TaskId> blocksOf(TaskId id) => [
    for (final item in _items)
      if (item.blockedBy.contains(id)) item.id,
  ];

  /// Выполняет [body] после всех ранее принятых операций.
  Future<T> _locked<T>(Future<T> Function() body) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return previous.then((_) => body()).whenComplete(done.complete);
  }

  @override
  Future<TaskResult> apply(TaskOp op, TaskActor actor, {String? toolCallId}) =>
      _locked(() async {
        final result = await _apply(op, actor, toolCallId);
        switch (result) {
          case TaskApplied(:final change, :final snapshot):
            // Ошибка подписчика не отменяет уже принятую операцию и не рвёт
            // замок: результат модели должен соответствовать состоянию списка.
            await _publish(snapshot, change, toolCallId: toolCallId);
            _log('task.op', actor, toolCallId, {
              'op': change.op,
              'ids': [
                for (final item in change.changed) item.id,
                ...change.deleted,
              ],
            });
          case TaskRejected(:final reason):
            _log('task.rejected', actor, toolCallId, {
              'op': switch (op) {
                CreateTask() => 'create',
                UpdateTask() => 'update',
                DeleteTask() => 'delete',
              },
              'reason': reason.wire,
              // id приходит от модели: в лог он попадает, только если пригоден
              // как id журнала, иначе отмечается флагом.
              if (op case UpdateTask(:final id) || DeleteTask(:final id))
                ..._loggableId(id),
            });
        }
        return result;
      });

  static Map<String, Object?> _loggableId(String id) {
    try {
      return {'id': parseTaskId(id)};
    } on FormatException {
      return {'id_invalid': true};
    }
  }

  Future<void> _publish(
    List<TaskItem> items,
    TaskChange change, {
    String? toolCallId,
  }) async {
    try {
      await publish?.call(items, change);
    } on Object catch (error, stack) {
      logger?.log(
        LogLevel.error,
        'task.publish.failed',
        fields: {
          'session_id': ?sessionId,
          'tool_call_id': ?toolCallId,
          'op': change.op,
        },
        error: error,
        stack: stack,
      );
    }
  }

  void _log(
    String event,
    TaskActor actor,
    String? toolCallId,
    Map<String, Object?> fields,
  ) => logger?.log(
    event == 'task.rejected' ? LogLevel.warning : LogLevel.info,
    event,
    fields: {
      'session_id': ?sessionId,
      'tool_call_id': ?toolCallId,
      ...fields,
      'actor': actor.wire,
    },
  );

  @override
  Future<void> restore(
    List<TaskItem> items, {
    required int nextId,
    required bool announce,
  }) => _locked(() async {
    final before = _items;
    _items = List.of(items);
    var next = _nextId > nextId ? _nextId : nextId;
    for (final item in items) {
      final n = int.tryParse(item.id);
      if (n != null && n >= next) {
        next = n + 1;
      }
    }
    _nextId = next;
    if (announce) {
      final kept = {for (final item in items) item.id};
      await _publish(
        List.unmodifiable(_items),
        TaskChange(
          op: TaskChange.restoreOp,
          actor: const MainActor(),
          changed: items,
          deleted: [
            for (final item in before)
              if (!kept.contains(item.id)) item.id,
          ],
        ),
      );
    }
  });

  Future<TaskResult> _apply(
    TaskOp op,
    TaskActor actor,
    String? toolCallId,
  ) async {
    switch (op) {
      case CreateTask():
        return _create(op, actor, toolCallId);
      case UpdateTask():
        return _update(op, actor, toolCallId);
      case DeleteTask(:final id):
        return _delete(id, actor, toolCallId);
    }
  }

  TaskItem? _byId(TaskId id) {
    for (final item in _items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  String _unknown(TaskId id) => _items.isEmpty
      ? 'Unknown task #$id. The task list is empty.'
      : 'Unknown task #$id. Known: '
            '${[for (final i in _items) '#${i.id}'].join(', ')}.';

  /// Общие проверки текстов; `null` — всё верно.
  String? _checkTexts(String? subject, String? description) {
    if (subject != null && (subject.isEmpty || subject.length > 200)) {
      return 'Invalid task: subject must be 1-200 characters.';
    }
    if (description != null && description.length > 4000) {
      return 'Invalid task: description must be at most 4000 characters.';
    }
    return null;
  }

  static const _ownerError =
      'Invalid task: owner must be "main" or the id of a subagent of this '
      'session.';
  static const _blockedByError =
      'Invalid task: blocked_by must list other existing tasks.';

  /// Нормализует `blocked_by`: по возрастанию id, без повторов. `null` — ссылка
  /// на себя или несуществующий пункт.
  List<TaskId>? _normalize(List<TaskId> ids, {TaskId? self}) {
    final result = <TaskId>{};
    for (final id in ids) {
      if (id == self || _byId(id) == null) {
        return null;
      }
      result.add(id);
    }
    return _sortedIds(result);
  }

  Future<TaskResult> _create(
    CreateTask op,
    TaskActor actor,
    String? toolCallId,
  ) async {
    final textError = _checkTexts(op.subject, op.description);
    if (textError != null) {
      return TaskRejected(textError, TaskRejectReason.validation);
    }
    // Писатель не создаёт то, что читатель отправит в карантин
    // (`parseTaskId`): id за пределом журнала не выдаются.
    if (_nextId > maxTaskIdValue) {
      return const TaskRejected(
        'Task limit reached: no more task ids are available in this session.',
        TaskRejectReason.limit,
      );
    }
    if (_items.length >= maxTaskItems) {
      return const TaskRejected(
        'Task limit reached: at most $maxTaskItems items. '
        'Delete completed items first.',
        TaskRejectReason.limit,
      );
    }
    final owner = op.owner ?? TaskOwner.main;
    if (!_isKnownOwner(owner)) {
      return const TaskRejected(_ownerError, TaskRejectReason.owner);
    }
    final blockedBy = _normalize(op.blockedBy ?? const []);
    if (blockedBy == null) {
      return const TaskRejected(_blockedByError, TaskRejectReason.blockedBy);
    }
    final item = TaskItem(
      id: '$_nextId',
      subject: op.subject,
      description: op.description,
      priority: op.priority ?? TaskPriority.medium,
      owner: owner,
      blockedBy: blockedBy,
    );
    _nextId++;
    _items = [..._items, item];
    final change = TaskChange(
      op: 'create',
      actor: actor,
      toolCallId: toolCallId,
      changed: [item],
      deleted: const [],
    );
    return TaskApplied(change: change, item: item, snapshot: items);
  }

  Future<TaskResult> _update(
    UpdateTask op,
    TaskActor actor,
    String? toolCallId,
  ) async {
    final current = _byId(op.id);
    if (current == null) {
      return TaskRejected(_unknown(op.id), TaskRejectReason.unknownId);
    }
    final textError = _checkTexts(op.subject, op.description);
    if (textError != null) {
      return TaskRejected(textError, TaskRejectReason.validation);
    }
    if (op.owner != null && !_isKnownOwner(op.owner!)) {
      return const TaskRejected(_ownerError, TaskRejectReason.owner);
    }
    List<TaskId>? blockedBy;
    if (op.blockedBy != null) {
      blockedBy = _normalize(op.blockedBy!, self: op.id);
      if (blockedBy == null) {
        return const TaskRejected(_blockedByError, TaskRejectReason.blockedBy);
      }
      final cycle = _cycleThrough(op.id, blockedBy);
      if (cycle != null) {
        return TaskRejected(
          'Invalid task: blocked_by would create a cycle: '
          '${cycle.map((id) => '#$id').join(' → ')}.',
          TaskRejectReason.cycle,
        );
      }
    }
    final updated = current.copyWith(
      subject: op.subject,
      description: op.description ?? _keep,
      status: op.status,
      priority: op.priority,
      owner: op.owner,
      blockedBy: blockedBy,
    );
    final before = _openBlocked();
    _items = [for (final item in _items) item.id == op.id ? updated : item];
    final change = TaskChange(
      op: 'update',
      actor: actor,
      toolCallId: toolCallId,
      changed: [updated],
      deleted: const [],
    );
    final unblocked = _newlyUnblocked(before, except: op.id);
    return TaskApplied(
      change: change,
      item: updated,
      snapshot: items,
      unblocked: unblocked,
    );
  }

  Future<TaskResult> _delete(
    TaskId id,
    TaskActor actor,
    String? toolCallId,
  ) async {
    if (_byId(id) == null) {
      return TaskRejected(_unknown(id), TaskRejectReason.unknownId);
    }
    final before = _openBlocked();
    final touched = <TaskItem>[];
    final rest = <TaskItem>[];
    for (final item in _items) {
      if (item.id == id) {
        continue;
      }
      if (item.blockedBy.contains(id)) {
        // Удаление убирает id из blocked_by остальных (§17.16.3, TSK-2).
        final cleaned = item.copyWith(
          blockedBy: [
            for (final b in item.blockedBy)
              if (b != id) b,
          ],
        );
        touched.add(cleaned);
        rest.add(cleaned);
      } else {
        rest.add(item);
      }
    }
    _items = rest;
    final change = TaskChange(
      op: 'delete',
      actor: actor,
      toolCallId: toolCallId,
      changed: touched,
      deleted: [id],
    );
    final unblocked = _newlyUnblocked(before, except: id);
    return TaskApplied(
      change: change,
      item: null,
      snapshot: items,
      unblocked: unblocked,
    );
  }

  /// Id пунктов, у которых сейчас есть незавершённый блокер.
  Set<TaskId> _openBlocked() => {
    for (final item in _items)
      if (openBlockers(item).isNotEmpty) item.id,
  };

  /// Незавершённые блокеры пункта (по возрастанию id).
  List<TaskItem> openBlockers(TaskItem item) => [
    for (final id in item.blockedBy)
      if (_byId(id) case final blocker?
          when blocker.status != TaskStatus.completed)
        blocker,
  ];

  List<TaskItem> _newlyUnblocked(
    Set<TaskId> before, {
    required TaskId except,
  }) => [
    for (final item in _items)
      if (item.id != except &&
          item.status != TaskStatus.completed &&
          before.contains(item.id) &&
          openBlockers(item).isEmpty)
        item,
  ];

  /// Цепочка `id → … → id`, если новые блокеры [next] замыкают цикл (TSK-2).
  List<TaskId>? _cycleThrough(TaskId id, List<TaskId> next) {
    List<TaskId>? walk(TaskId from, List<TaskId> path, Set<TaskId> seen) {
      if (from == id) {
        return [...path, id];
      }
      if (!seen.add(from)) {
        return null;
      }
      final edges = _byId(from)?.blockedBy ?? const <TaskId>[];
      for (final to in edges) {
        final found = walk(to, [...path, from], seen);
        if (found != null) {
          return found;
        }
      }
      return null;
    }

    final seen = <TaskId>{};
    for (final first in next) {
      final found = walk(first, [id], seen);
      if (found != null) {
        return found;
      }
    }
    return null;
  }
}

List<TaskId> _sortedIds(Iterable<TaskId> ids) => ids.toList()
  ..sort((a, b) {
    final x = int.tryParse(a), y = int.tryParse(b);
    return x != null && y != null ? x.compareTo(y) : a.compareTo(b);
  });
