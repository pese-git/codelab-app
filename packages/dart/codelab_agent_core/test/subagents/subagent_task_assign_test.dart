import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/subagents/subagent_manager.dart';
import 'package:codelab_agent_core/src/subagents/subagent_types.dart';
import 'package:codelab_agent_core/src/tools/path_lock.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

/// Операция `assign` менеджера при получении слота (agent-tools «Инструменты
/// списка задач», «Назначение пункта ребёнку»; design.md change
/// `add-subagents-and-tasks`, D45 Т8, D46 п. 3, D18 «task.assign.skipped»;
/// `agent-core/17-16-task-list.md` §17.16.4).
///
/// Красные до задачи 4.5: менеджер не трогает список при получении слота.
/// Тест на уровне менеджера нужен потому, что случай «пункт удалён, пока
/// ребёнок стоял в очереди» моделью недостижим (корень ждёт свою группу
/// `agent`, а потомки пунктов не удаляют): список меняется напрямую.
///
/// Фабрика дочерней сессии бросает после записи состояния списка: менеджер
/// фиксирует ошибку и завершает хэндл, а тесту нужен только момент вызова
/// `create` — после `assign` и до создания дочерней сессии.
void main() {
  late SessionTaskList list;
  late RecordingLogger logger;
  late List<TaskChange> changes;
  late List<TaskItem> seenAtCreate;
  late SubagentManager manager;
  late SubagentTree tree;

  Future<void> addItem(String subject, {TaskOwner? owner}) async {
    await list.apply(
      CreateTask(subject: subject, owner: owner),
      const MainActor(),
    );
  }

  setUp(() async {
    logger = RecordingLogger();
    changes = [];
    seenAtCreate = [];
    list = SessionTaskList(
      isKnownOwner: (_) => true,
      publish: (items, change) => changes.add(change),
    );
    const limits = SubagentsConfig(maxConcurrent: 1);
    tree = SubagentTree(limits: () => limits);
    manager = SubagentManager(
      tree: tree,
      limits: () => limits,
      emit: (_) async {},
      create: (spec) async {
        seenAtCreate = list.items;
        throw StateError('the test stops here');
      },
      clock: FakeClock(),
      logger: logger,
      sessionId: const SessionId('root'),
      rootBudget: () => const TurnBudget(),
      parent: () => SubagentParent(
        tools: () => const [],
        model: () => ModelRef(
          provider: 'test',
          id: 'm',
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('http://localhost:8080/v1'),
          contextWindow: 65536,
          maxOutputTokens: 4096,
        ),
        mode: () => (mode: PermissionMode.write, deniedTiers: const {}),
        skills: SkillCatalog.empty,
        decisions: PermissionDecisionStore(),
        rules: const PolicyRules(),
        env: MemoryExecutionEnv(cwd: '/proj'),
        tasks: list,
        locks: PathLock(),
        maxChildDepth: 1,
      ),
    );
  });

  SubagentSpec spec(String id, {String? taskId}) => SubagentSpec(
    id: id,
    parentSessionId: const SessionId('root'),
    parentToolCallId: 'c_$id',
    depth: 1,
    type: buildSubagentTypes(const []).firstWhere((t) => t.name == 'general'),
    description: 'Job $id',
    prompt: 'do it',
    taskId: taskId,
  );

  test('пункт удалён, пока ребёнок стоял в очереди: assign пропущен, лог '
      'task.assign.skipped с task_id и subagent_id, ребёнок всё равно '
      'создаётся', () async {
    await addItem('One');
    await addItem('Two');
    changes.clear();
    final holder = await tree.acquire(resume: false, cancel: CancelToken.none);
    expect(holder, isTrue);

    final handle = manager.spawn(
      spec('sub_aaaaaaaa', taskId: '2'),
      CancelToken.none,
    );
    await list.apply(const DeleteTask('2'), const MainActor());
    changes.clear();
    tree.release();
    await handle.report;

    final skipped = logger.eventsOf('task.assign.skipped').single;
    expect(skipped.fields['task_id'], '2');
    expect(skipped.fields['subagent_id'], 'sub_aaaaaaaa');
    expect(changes.where((c) => c.op == 'assign'), isEmpty);
    expect(seenAtCreate.map((i) => i.id), ['1'], reason: 'create вызван');
  });

  test('assign выполняется до создания дочерней сессии от имени main без '
      'toolCallId: владелец — ребёнок, pending → in_progress', () async {
    await addItem('One');
    await addItem('Two');
    changes.clear();

    final handle = manager.spawn(
      spec('sub_aaaaaaaa', taskId: '2'),
      CancelToken.none,
    );
    await handle.report;

    final assign = changes.singleWhere((c) => c.op == 'assign');
    expect(assign.actor, const MainActor());
    expect(assign.toolCallId, isNull);
    final atCreate = seenAtCreate.singleWhere((i) => i.id == '2');
    expect(atCreate.owner, const TaskOwner('sub_aaaaaaaa'));
    expect(atCreate.status, TaskStatus.inProgress);
    expect(seenAtCreate.singleWhere((i) => i.id == '1').owner, TaskOwner.main);
  });

  test('повторное назначение (D46, п. 3): пункт уже у другого потомка — '
      'владелец меняется без проверки прежнего, статус in_progress '
      'сохраняется', () async {
    await addItem('One', owner: const TaskOwner('sub_oldoldol'));
    await list.apply(
      const UpdateTask('1', status: TaskStatus.inProgress),
      const MainActor(),
    );
    changes.clear();

    final handle = manager.spawn(
      spec('sub_bbbbbbbb', taskId: '1'),
      CancelToken.none,
    );
    await handle.report;

    final item = seenAtCreate.single;
    expect(item.owner, const TaskOwner('sub_bbbbbbbb'));
    expect(item.status, TaskStatus.inProgress);
    expect(changes.where((c) => c.op == 'assign'), hasLength(1));
  });

  test('пункт уже completed: assign меняет владельца, статус остаётся '
      '(in_progress ставится только у pending, §17.16.4)', () async {
    await addItem('One');
    await list.apply(
      const UpdateTask('1', status: TaskStatus.completed),
      const MainActor(),
    );

    final handle = manager.spawn(
      spec('sub_cccccccc', taskId: '1'),
      CancelToken.none,
    );
    await handle.report;

    final item = seenAtCreate.single;
    expect(item.owner, const TaskOwner('sub_cccccccc'));
    expect(item.status, TaskStatus.completed);
  });
}
