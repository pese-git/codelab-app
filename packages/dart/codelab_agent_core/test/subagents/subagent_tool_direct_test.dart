import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/subagents/subagent_manager.dart';
import 'package:codelab_agent_core/src/subagents/subagent_tool.dart';
import 'package:codelab_agent_core/src/subagents/subagent_types.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

/// Защитные ветки `SubagentTool.execute` вызовом напрямую (agent-subagents
/// «Инструмент agent и типы субагентов»): провайдер может не соблюсти `enum`
/// схемы, и тогда `execute` сам отвечает `Unknown agent type` (design.md
/// change `add-subagents-and-tasks`, решение по итерации 2). Через модель эта
/// ветка недостижима — валидатор схемы отсекает неизвестный `enum` раньше.
void main() {
  Future<ToolExecutionResult> run(Map<String, Object?> args) async {
    final clock = FakeClock();
    final logger = RecordingLogger();
    final manager = SubagentManager(
      tree: SubagentTree(limits: () => const SubagentsConfig()),
      limits: () => const SubagentsConfig(),
      emit: (_) async {},
      create: (_) => throw StateError('no child must be created'),
      clock: clock,
      logger: logger,
      sessionId: const SessionId('root'),
      rootBudget: () => const TurnBudget(),
      parent: () => throw StateError('no child must be created'),
    );
    final tool = SubagentTool(
      manager: manager,
      types: buildSubagentTypes(const []),
      ids: SequentialIdGenerator(),
      limits: () => const SubagentsConfig(),
      clock: clock,
      logger: logger,
      parentSessionId: const SessionId('root'),
      maxDepth: 3,
      maxConcurrent: 3,
    );
    final env = await BoundedEnv.wrap(
      MemoryExecutionEnv(cwd: '/proj'),
      '/proj',
    );
    return tool.execute(
      args,
      ToolContext(
        env: env,
        cancel: CancelToken.none,
        onUpdate: (_) {},
        toolCallId: 'c1',
        services: ToolServices(clock: clock, logger: logger),
      ),
    );
  }

  test('неизвестный тип: SubagentCallError с перечнем доступных, ребёнок не '
      'создан', () async {
    await expectLater(
      run({'description': 'Look around', 'prompt': 'find it', 'type': 'nope'}),
      throwsA(
        isA<SubagentCallError>().having(
          (e) => e.message,
          'message',
          'Unknown agent type "nope". Available: explore, general, plan, '
              'review.',
        ),
      ),
    );
  });

  SubagentTool toolAt(int depth, int maxDepth) {
    final clock = FakeClock();
    final logger = RecordingLogger();
    return SubagentTool(
      manager: SubagentManager(
        tree: SubagentTree(limits: () => const SubagentsConfig()),
        limits: () => const SubagentsConfig(),
        emit: (_) async {},
        create: (_) => throw StateError('no child'),
        clock: clock,
        logger: logger,
        sessionId: const SessionId('root'),
        rootBudget: () => const TurnBudget(),
        parent: () => throw StateError('no child'),
      ),
      types: buildSubagentTypes(const []),
      ids: SequentialIdGenerator(),
      limits: () => const SubagentsConfig(),
      clock: clock,
      logger: logger,
      parentSessionId: const SessionId('root'),
      depth: depth,
      maxDepth: maxDepth,
      maxConcurrent: 3,
    );
  }

  group(
    'описание agent по глубине (agent-prompts «Описание agent по глубине»)',
    () {
      test('корень при max_depth 3 разрешает ещё два уровня', () {
        expect(
          toolAt(0, 3).description,
          contains(
            'A subagent may start its own subagents, up to 2 more level(s) '
            'below it.',
          ),
        );
      });

      test(
        'ребёнок глубины 2 при том же max_depth — не запускает потомков',
        () {
          expect(
            toolAt(2, 3).description,
            contains('Subagents you start cannot start other subagents.'),
          );
        },
      );

      test('схема ребёнка без task: поле только у корня', () {
        expect(
          (toolAt(0, 3).parameters['properties']! as Map).containsKey('task'),
          isTrue,
        );
        expect(
          (toolAt(1, 3).parameters['properties']! as Map).containsKey('task'),
          isFalse,
        );
      });
    },
  );
}
