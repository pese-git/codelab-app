import 'package:codelab_agent_core/codelab_agent_core.dart';
// Правило набора — внутренняя функция ядра (D36 Т2: `SubagentManager` и
// фабрика дочерней сессии — не публичный API).
import 'package:codelab_agent_core/src/subagents/child_tools.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import '../tools/fake_tools.dart';
import 'subagent_rig.dart';

/// Набор инструментов ребёнка (agent-subagents «Сборка ребёнка», сценарии
/// «Пересечение инструментов» и «Нет снимка каталога — нет skill»; SUB-1,
/// SUB-24; design.md change `add-subagents-and-tasks`, D3, D34, D36 Т7, Т9;
/// `agent-core/17-3-subagents.md` §17.3.3, шаг 3).
///
/// Красные до задач 2.4 и 2.11: нет фабрики дочерней сессии и функции
/// `selectChildTools` (набор ребёнка = `base ∩ type.tools`, `agent` только
/// выше `max_depth`, детский вариант задач, `skill` только со снимком
/// каталога).
///
/// Фиксируемый API: функция `selectChildTools` с именованными параметрами
/// `parentTools`, `type`, `depth`, `maxDepth`, `skills` возвращает список
/// инструментов в порядке `parentTools`; `depth` — глубина ребёнка (корень —
/// 0); `skills` — снимок каталога родителя или `null`.
void main() {
  AgentDefinition type(String name, {List<String>? tools}) => AgentDefinition(
    name: name,
    description: 'The $name type',
    prompt: 'Body.',
    source: 'builtin:$name',
    tools: tools,
  );

  final explore = type('explore', tools: const ['read', 'ls', 'search']);
  final review = type('review', tools: const ['read', 'ls', 'search', 'exec']);
  final general = type('general');

  List<AgentTool> parent(List<String> names) => [
    for (final name in names) FakeTool(name),
  ];

  List<String> names(List<AgentTool> tools) => [for (final t in tools) t.name];

  group('сценарий «Пересечение инструментов» при max_depth: 1', () {
    test('родитель без exec, тип review: read, ls, search и детский вариант '
        'задач, без exec', () async {
      final config = CoreConfig(
        defaultModel: subagentTestModel,
        subagents: const SubagentsConfig(maxDepth: 1),
      );
      final rig = SubagentRig(
        scripts: {
          'go': [
            oneCallStep('c1', 'agent', agentArgs('check it', type: 'review')),
            replyStep('done'),
          ],
          'check it': [replyStep('clean')],
        },
        config: config,
      );
      await rig.open();

      await rig.run('go');

      final child = toolNamesOf(rig.requestsOf('check it').single);
      expect(
        child,
        unorderedEquals([
          'read',
          'ls',
          'search',
          'task_update',
          'task_list',
          'task_get',
        ]),
      );
      expect(child, isNot(contains('exec')));
      expect(child, isNot(contains('agent')));
      expect(child, isNot(contains('task_create')));
    });

    test('тип general: все инструменты родителя в его порядке, без agent '
        'и task_create', () async {
      final rig = SubagentRig(
        scripts: {
          'go': [
            oneCallStep('c1', 'agent', agentArgs('do it')),
            replyStep('done'),
          ],
          'do it': [replyStep('ok')],
        },
        config: CoreConfig(
          defaultModel: subagentTestModel,
          subagents: const SubagentsConfig(maxDepth: 1),
        ),
      );
      await rig.open();

      await rig.run('go');

      expect(toolNamesOf(rig.requestsOf('do it').single), [
        'read',
        'write',
        'edit',
        'task_update',
        'task_list',
        'task_get',
        'ls',
        'search',
      ]);
    });

    test('тип explore: ни write, ни edit, ни task_create (SUB-1: не шире '
        'типа и не шире родителя)', () async {
      final rig = SubagentRig(
        scripts: {
          'go': [
            oneCallStep(
              'c1',
              'agent',
              agentArgs('look around', type: 'explore'),
            ),
            replyStep('done'),
          ],
          'look around': [replyStep('seen')],
        },
        config: CoreConfig(
          defaultModel: subagentTestModel,
          subagents: const SubagentsConfig(maxDepth: 1),
        ),
      );
      await rig.open();

      await rig.run('go');

      expect(
        toolNamesOf(rig.requestsOf('look around').single),
        unorderedEquals([
          'read',
          'ls',
          'search',
          'task_update',
          'task_list',
          'task_get',
        ]),
      );
    });
  });

  group('selectChildTools: правило набора', () {
    final base = [
      'read',
      'write',
      'skill',
      'agent',
      'task_create',
      'task_update',
      'task_list',
      'task_get',
      'exec',
    ];

    test('инструмент типа, которого нет у родителя, не добавляется '
        '(SUB-1)', () {
      final tools = selectChildTools(
        parentTools: parent(['read', 'ls']),
        type: review,
        depth: 1,
        maxDepth: 1,
      );

      expect(names(tools), ['read', 'ls']);
    });

    test('agent входит в набор, только если depth < maxDepth (SUB-24)', () {
      List<String> at(int depth, int maxDepth) => names(
        selectChildTools(
          parentTools: parent(base),
          type: general,
          depth: depth,
          maxDepth: maxDepth,
          skills: SkillCatalog.empty,
        ),
      );

      expect(at(1, 1), isNot(contains('agent')));
      expect(at(1, 3), contains('agent'));
      expect(at(2, 3), contains('agent'));
      expect(at(3, 3), isNot(contains('agent')));
    });

    test('task_create у ребёнка нет на любой глубине, детский вариант — '
        'task_update, task_list, task_get', () {
      final tools = selectChildTools(
        parentTools: parent(base),
        type: general,
        depth: 1,
        maxDepth: 3,
        skills: SkillCatalog.empty,
      );

      expect(names(tools), isNot(contains('task_create')));
      expect(
        names(tools),
        containsAll(['task_update', 'task_list', 'task_get']),
      );
    });

    test('сценарий «Нет снимка каталога — нет skill»: поддельный skill в '
        'наборе родителя, снимка нет — у general его нет, остальное есть', () {
      final tools = selectChildTools(
        parentTools: parent(base),
        type: general,
        depth: 1,
        maxDepth: 1,
      );

      expect(names(tools), [
        'read',
        'write',
        'task_update',
        'task_list',
        'task_get',
        'exec',
      ]);
    });

    test('со снимком каталога skill входит по общему правилу: general — да, '
        'explore и review — нет, пользовательский тип со skill в tools — '
        'да (D34, Q17.1)', () {
      List<String> forType(AgentDefinition t) => names(
        selectChildTools(
          parentTools: parent(base),
          type: t,
          depth: 1,
          maxDepth: 1,
          skills: SkillCatalog.empty,
        ),
      );

      expect(forType(general), contains('skill'));
      expect(forType(explore), isNot(contains('skill')));
      expect(forType(review), isNot(contains('skill')));
      expect(
        forType(type('custom', tools: const ['read', 'skill'])),
        contains('skill'),
      );
    });

    test('без снимка skill убирается и тогда, когда тип называет его '
        'явно', () {
      final tools = selectChildTools(
        parentTools: parent(base),
        type: type('custom', tools: const ['read', 'skill']),
        depth: 1,
        maxDepth: 1,
      );

      expect(names(tools), isNot(contains('skill')));
    });
  });
}
