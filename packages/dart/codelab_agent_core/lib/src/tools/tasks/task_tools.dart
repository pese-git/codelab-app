import '../../llm/messages.dart';
import '../../prompts/prompts.g.dart';
import '../agent_tool.dart';
import '../builtin/common.dart';
import 'task_list.dart';

/// Инструменты списка задач `task_create`, `task_update`, `task_list`,
/// `task_get` (`agent-core/17-16-task-list.md` §17.16.3; change
/// `add-subagents-and-tasks`, D13).
///
/// Почему четыре инструмента вместо одного `update_plan`: модель меняет то,
/// что знает — один статус, одну зависимость, — а не переписывает весь план
/// на каждом шаге (§17.16.8).
///
/// Для чего: все четыре — tier `read`, kind `think`, вывод `trusted`,
/// шаблон разрешения `*` (§7.5): список не касается файлов, команд и сети.
///
/// Как использовать: хост регистрирует их в `buildAgentCore`; инструмент берёт
/// список из `ToolContext.services.tasks` и выполняет операции от имени
/// корневой сессии (детский вариант набора — итерация 4 change).
abstract base class _TaskTool extends AgentTool {
  @override
  ToolTier get tier => ToolTier.read;

  @override
  ToolKind get kind => ToolKind.think;

  /// Режим исполнения не переопределяется: вызовы `task_*` идут параллельно
  /// с остальным пакетом (LOOP-4, `agent_loop.dart`, `_runBatch`).
  ///
  /// Почему parallel безопасен: операции сериализует замок
  /// `SessionTaskList._locked` (проверки цикла и лимита видят состояние после
  /// предыдущей операции), `TaskListChanged` публикуется под замком и
  /// ждётся внутри `execute`, то есть раньше `ToolCallFinished` своего вызова
  /// (TSK-1), а клиент привязывает `plan` к вызову по
  /// `plan._meta.codelab.taskChange.toolCallId` (D35), не по порядку событий.
  ///
  /// Что теряется: глобальный порядок вызовов и порядок выдачи id внутри
  /// пакета — он зависит от порядка захвата замка и недетерминирован; хук
  /// `beforeToolCall` срабатывает не сразу после `ToolCallStarted` своего
  /// вызова, а после announce всего пакета.
  @override
  ToolExecutionMode? get executionMode => null;

  @override
  ContentTrust outputTrust(Map<String, Object?> args) => ContentTrust.trusted;

  @override
  String permissionPattern(Map<String, Object?> args, String cwd) => '*';

  /// Строка сводки (§17.16.3).
  static String summary(List<TaskItem> items) {
    int count(TaskStatus s) => items.where((i) => i.status == s).length;
    return 'Task list: ${items.length} items '
        '(${count(TaskStatus.completed)} completed, '
        '${count(TaskStatus.inProgress)} in progress, '
        '${count(TaskStatus.pending)} pending).';
  }

  /// Заметки после сводки: `in_progress` при незавершённых блокерах и
  /// несколько `in_progress` одновременно.
  static List<String> notes(List<TaskItem> tasks, TaskItem? item) {
    return [
      if (item != null && item.status == TaskStatus.inProgress)
        if (_open(tasks, item) case final open when open.isNotEmpty)
          '[Note: task #${item.id} is in_progress, but '
              '${open.map((b) => '#${b.id}').join(', ')} '
              '${open.length == 1 ? 'is' : 'are'} not completed yet.]',
      if (tasks.where((i) => i.status == TaskStatus.inProgress).length > 1)
        '[Note: more than one task is in_progress.]',
    ];
  }

  /// Незавершённые блокеры пункта среди живых пунктов.
  static List<TaskItem> _open(List<TaskItem> tasks, TaskItem item) => [
    for (final id in item.blockedBy)
      for (final t in tasks)
        if (t.id == id && t.status != TaskStatus.completed) t,
  ];

  static ToolExecutionResult text(List<String> lines) =>
      ToolExecutionResult([TextContent(lines.join('\n'))]);

  static List<String> idList(Object? raw) => [
    if (raw is List<Object?>)
      for (final id in raw) '$id',
  ];
}

TaskPriority? _priority(Object? raw) => TaskPriority.values.asNameMap()[raw];

const _priorityProperty = {
  'type': 'string',
  'enum': ['high', 'medium', 'low'],
};

const _blockedByProperty = {
  'type': 'array',
  'items': {'type': 'string'},
};

/// `task_create` — добавить пункт в список задач (§17.16.3).
///
/// Почему отдельный инструмент: модель создаёт пункт, не переписывая весь
/// план. Он же — якорь секции промпта `tools/tasks` и будущих переключателей
/// (D30, D32): без него список корня пуст.
/// Как использовать: хост регистрирует его в `buildAgentCore`; модель
/// присылает `subject` (обязательно), `description`, `priority`,
/// `blocked_by`, `owner`. Ошибка проверки — результат-ошибка с текстом
/// §17.16.3, список не меняется.
final class TaskCreateTool extends _TaskTool {
  @override
  String get name => 'task_create';

  @override
  String get description => Prompts.toolDescriptionsTaskCreate.render(const {});

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'subject': {'type': 'string'},
      'description': {'type': 'string'},
      'priority': _priorityProperty,
      'blocked_by': _blockedByProperty,
      'owner': {'type': 'string'},
    },
    'required': ['subject'],
  };

  @override
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => const ToolPresentation(title: 'Create task');

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final list = ctx.services.tasks;
    final result = await list.apply(
      toolCallId: ctx.toolCallId,
      CreateTask(
        subject: args['subject']! as String,
        description: args['description'] as String?,
        priority: _priority(args['priority']),
        owner: args['owner'] is String
            ? TaskOwner(args['owner']! as String)
            : null,
        blockedBy: args.containsKey('blocked_by')
            ? _TaskTool.idList(args['blocked_by'])
            : null,
      ),
      const MainActor(),
    );
    return switch (result) {
      TaskRejected(:final message) => errorResult(message),
      TaskApplied(:final item, :final snapshot) => _TaskTool.text([
        'Created task #${item!.id}: ${item.subject}.',
        _TaskTool.summary(snapshot),
        ..._TaskTool.notes(snapshot, item),
      ]),
    };
  }
}

/// `task_update` — изменить или удалить один пункт по id (§17.16.3).
///
/// Почему: модель меняет только то, что знает (один статус, одну связь).
/// Статус `deleted` удаляет пункт и убирает его из `blocked_by` остальных;
/// `blocked_by` заменяет список целиком.
/// Как использовать: присылать `id` и только изменённые поля. В ответе —
/// перечень полей, `Unblocked: …` для освобождённых пунктов, сводка и
/// заметки (`in_progress` при незавершённых блокерах, несколько
/// `in_progress`).
final class TaskUpdateTool extends _TaskTool {
  @override
  String get name => 'task_update';

  @override
  String get description => Prompts.toolDescriptionsTaskUpdate.render(const {});

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'id': {'type': 'string'},
      'subject': {'type': 'string'},
      'description': {'type': 'string'},
      'status': {
        'type': 'string',
        'enum': ['pending', 'in_progress', 'completed', 'deleted'],
      },
      'priority': _priorityProperty,
      'owner': {'type': 'string'},
      'blocked_by': _blockedByProperty,
    },
    'required': ['id'],
  };

  @override
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => ToolPresentation(
    title: args['id'] is String ? 'Update task #${args['id']}' : 'Update task',
  );

  /// Поля в порядке параметров схемы: так они перечисляются в ответе.
  static const _fields = [
    'subject',
    'description',
    'status',
    'priority',
    'owner',
    'blocked_by',
  ];

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final list = ctx.services.tasks;
    final id = args['id']! as String;
    final status = args['status'];
    final result = await list.apply(
      toolCallId: ctx.toolCallId,
      status == 'deleted'
          ? DeleteTask(id)
          : UpdateTask(
              id,
              subject: args['subject'] as String?,
              description: args['description'] as String?,
              status: TaskStatus.fromWire(status),
              priority: _priority(args['priority']),
              owner: args['owner'] is String
                  ? TaskOwner(args['owner']! as String)
                  : null,
              blockedBy: args.containsKey('blocked_by')
                  ? _TaskTool.idList(args['blocked_by'])
                  : null,
            ),
      const MainActor(),
    );
    switch (result) {
      case TaskRejected(:final message):
        return errorResult(message);
      case TaskApplied(:final item, :final unblocked, :final snapshot):
        return _TaskTool.text([
          if (item == null)
            'Deleted task #$id.'
          else
            'Updated task #$id: '
                '${_fields.where((f) => args[f] != null).join(', ')}.',
          if (unblocked.isNotEmpty)
            'Unblocked: ${unblocked.map((t) => '#${t.id} ${t.subject}').join(', ')}',
          _TaskTool.summary(snapshot),
          ..._TaskTool.notes(snapshot, item),
        ]);
    }
  }
}

/// `task_list` — показать все пункты строкой на пункт (§17.16.3).
///
/// Почему: после сжатия контекста модель теряет историю вызовов, и это
/// единственный способ узнать состояние списка (правило — в описании
/// инструмента, D32). Список не меняет и `plan` не порождает.
/// Как использовать: без аргументов; `blocked by` показывает только
/// незавершённых блокеров, `owner` — только владельца не `main`.
final class TaskListTool extends _TaskTool {
  @override
  String get name => 'task_list';

  @override
  String get description => Prompts.toolDescriptionsTaskList.render(const {});

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => const ToolPresentation(title: 'List tasks');

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final items = ctx.services.tasks.items;
    if (items.isEmpty) {
      return _TaskTool.text(['The task list is empty.']);
    }
    return _TaskTool.text([
      for (final item in items)
        '#${item.id} [${item.status.wire}] ${item.subject}'
            '${item.owner == TaskOwner.main ? '' : ' (owner: ${item.owner.value})'}'
            '${_blockedBy(items, item)}',
    ]);
  }

  static String _blockedBy(List<TaskItem> items, TaskItem item) {
    final open = _TaskTool._open(items, item);
    return open.isEmpty
        ? ''
        : ' (blocked by ${open.map((b) => '#${b.id}').join(', ')})';
  }
}

/// `task_get` — показать один пункт целиком (§17.16.3).
///
/// Почему: `task_list` не показывает описание и обратные рёбра; здесь они
/// есть — `Blocks` и `Blocked by` с заголовками, пока блокер не завершён.
/// Как использовать: `id` обязателен; неизвестный id — ошибка с перечнем
/// известных. Список не меняется.
final class TaskGetTool extends _TaskTool {
  @override
  String get name => 'task_get';

  @override
  String get description => Prompts.toolDescriptionsTaskGet.render(const {});

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'id': {'type': 'string'},
    },
    'required': ['id'],
  };

  @override
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => ToolPresentation(
    title: args['id'] is String ? 'Get task #${args['id']}' : 'Get task',
  );

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final items = ctx.services.tasks.items;
    final id = args['id']! as String;
    final item = items.where((i) => i.id == id).firstOrNull;
    if (item == null) {
      return errorResult(
        items.isEmpty
            ? 'Unknown task #$id. The task list is empty.'
            : 'Unknown task #$id. Known: '
                  '${items.map((i) => '#${i.id}').join(', ')}.',
      );
    }
    String refs(Iterable<TaskItem> tasks) => tasks.isEmpty
        ? 'none'
        : tasks.map((t) => '#${t.id} ${t.subject}').join(', ');
    // Ребро «A блокирует B» видно, пока A не завершён (§17.16.3); само поле
    // blocked_by при завершении блокера не меняется.
    final blocks = item.status == TaskStatus.completed
        ? const <TaskItem>[]
        : items.where(
            (i) =>
                i.blockedBy.contains(item.id) &&
                i.status != TaskStatus.completed,
          );
    return _TaskTool.text([
      'Task #${item.id}: ${item.subject}',
      'Status: ${item.status.wire}',
      'Priority: ${item.priority.name}',
      'Owner: ${item.owner.value}',
      'Description: ${item.description == null || item.description!.isEmpty ? 'none' : item.description}',
      'Blocks: ${refs(blocks)}',
      'Blocked by: ${refs(_TaskTool._open(items, item))}',
    ]);
  }
}
