import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../config/config_support.dart' show baseValues, withValues;
import '../subagents/subagent_rig.dart';
import '../support/models.dart';

/// Сборка и живая перезагрузка субагентов в рантайме (agent-runtime
/// «Минимальная сборка buildAgentCore», сценарии «Матрица профиля»,
/// «Субагенты включены», «Субагенты выключены перезагрузкой»;
/// agent-configuration «Запись через config set», окончание сценария;
/// design.md change `add-subagents-and-tasks`, D17, D22, D36 Т5, D37).
///
/// Красные до задач 2.2 и 2.4: нет `CoreConfig.subagents`, регистрации
/// `agent` в реестре сессии и геттера `AgentRuntime.subagents`.
///
/// Фиксируемый API: `AgentRuntime.subagents` — `null` при выключенных
/// субагентах в применённом конфиге, иначе значение с `maxDepth`
/// (`subagents.max_depth`); читается из применённого снимка при каждом
/// обращении.
void main() {
  const base = [
    'read',
    'write',
    'edit',
    'task_create',
    'task_update',
    'task_list',
    'task_get',
    'ls',
    'search',
  ];

  Future<LlmContext> firstRequest(CoreConfig config) async {
    final rig = SubagentRig(
      config: config,
      scripts: {
        'go': [replyStep('ok')],
      },
    );
    await rig.open();
    await rig.run('go');
    return rig.contexts.first;
  }

  group('Матрица профиля и «Субагенты включены»', () {
    test('subagents.enabled: false — схемы только базовые, без agent и без '
        'его секции в промпте', () async {
      final request = await firstRequest(
        CoreConfig(
          defaultModel: testModel,
          subagents: const SubagentsConfig(enabled: false),
        ),
      );

      expect(toolNamesOf(request), base);
      expect(request.systemPrompt, isNot(contains('subagent')));
    });

    test('subagents.enabled: true — agent последним встроенным '
        'инструментом сессии', () async {
      final request = await firstRequest(
        CoreConfig(
          defaultModel: testModel,
          subagents: const SubagentsConfig(enabled: true),
        ),
      );

      expect(toolNamesOf(request), [...base, 'agent']);
      expect(schemaOf(request, 'agent').description, contains('- explore: '));
    });

    test('CorePlan.toolNames не содержит agent: он регистрируется в копии '
        'реестра сессии (D36 Т5)', () async {
      final rig = SubagentRig(scripts: const {});

      expect(rig.core.plan.toolNames, isNot(contains('agent')));
    });
  });

  group('геттер AgentRuntime.subagents (D37)', () {
    test('по умолчанию — включено, maxDepth 3', () {
      final rig = SubagentRig(scripts: const {});

      expect(rig.core.runtime.subagents, isNotNull);
      expect(rig.core.runtime.subagents!.maxDepth, 3);
    });

    test('при subagents.enabled: false — null', () {
      final rig = SubagentRig(
        scripts: const {},
        config: CoreConfig(
          defaultModel: testModel,
          subagents: const SubagentsConfig(enabled: false),
        ),
      );

      expect(rig.core.runtime.subagents, isNull);
    });

    test('maxDepth берётся из subagents.max_depth', () {
      final rig = SubagentRig(
        scripts: const {},
        config: CoreConfig(
          defaultModel: testModel,
          subagents: const SubagentsConfig(maxDepth: 2),
        ),
      );

      expect(rig.core.runtime.subagents!.maxDepth, 2);
    });

    test('значение живое: перезагрузка конфига меняет его без '
        'перезапуска', () async {
      final source = LayeredConfigSource();
      final rig = SubagentRig(scripts: const {}, source: source);
      expect(rig.core.runtime.subagents!.maxDepth, 3);

      source.user['subagents'] = {'max_depth': 1};
      await rig.core.runtime.reloadConfig();
      expect(rig.core.runtime.subagents!.maxDepth, 1);

      source.user['subagents'] = {'enabled': false};
      await rig.core.runtime.reloadConfig();
      expect(rig.core.runtime.subagents, isNull);

      source.user['subagents'] = {'enabled': true, 'max_depth': 2};
      await rig.core.runtime.reloadConfig();
      expect(rig.core.runtime.subagents!.maxDepth, 2);
    });
  });

  test('сценарий «Субагенты выключены перезагрузкой»: сессия A сохраняет '
      'agent, у сессии B его нет, AgentRuntime.subagents — null', () async {
    final source = LayeredConfigSource();
    final rig = SubagentRig(
      source: source,
      scripts: {
        'go': [replyStep('a1'), replyStep('b1'), replyStep('a2')],
      },
    );
    final a = await rig.core.runtime.createSession(SessionSpec(cwd: '/proj'));
    await a.prompt([const TextContent('go')]);
    expect(toolNamesOf(rig.contexts.last), contains('agent'));

    source.user['subagents'] = {'enabled': false};
    await rig.core.runtime.reloadConfig();
    final b = await rig.core.runtime.createSession(SessionSpec(cwd: '/proj'));
    await b.prompt([const TextContent('go')]);
    final bRequest = rig.contexts.last;
    await a.prompt([const TextContent('go')]);
    final aRequest = rig.contexts.last;

    expect(toolNamesOf(bRequest), isNot(contains('agent')));
    expect(toolNamesOf(aRequest), contains('agent'));
    expect(rig.core.runtime.subagents, isNull);
  });

  test('max_depth и enabled меняют схему agent только в новых сессиях: '
      'сессия A хранит прежнее описание (D22, кэш промпта)', () async {
    final source = LayeredConfigSource();
    final rig = SubagentRig(
      source: source,
      scripts: {
        'go': [replyStep('a1'), replyStep('b1'), replyStep('a2')],
      },
    );
    final a = await rig.core.runtime.createSession(SessionSpec(cwd: '/proj'));
    await a.prompt([const TextContent('go')]);
    final before = schemaOf(rig.contexts.last, 'agent').description;

    source.user['subagents'] = {'max_depth': 1};
    await rig.core.runtime.reloadConfig();
    final b = await rig.core.runtime.createSession(SessionSpec(cwd: '/proj'));
    await b.prompt([const TextContent('go')]);
    final fresh = schemaOf(rig.contexts.last, 'agent').description;
    await a.prompt([const TextContent('go')]);
    final again = schemaOf(rig.contexts.last, 'agent').description;

    expect(
      fresh,
      contains('Subagents you start cannot start other subagents.'),
    );
    expect(again, before);
    expect(before, isNot(contains('Subagents you start cannot start')));
  });

  test('лимиты читаются при каждом spawn: после перезагрузки '
      'max_concurrent 1 следующий ход идёт одним слотом без перезапуска '
      '(agent-configuration «Запись через config set»)', () async {
    final source = LayeredConfigSource(
      withValues(baseValues(), {
        'subagents': {'max_concurrent': 3},
      }),
    );
    final rig = SubagentRig(
      source: source,
      scripts: {
        'go': [
          multiCallStep([
            ('a1', 'agent', agentArgs('child one', description: 'One')),
            ('a2', 'agent', agentArgs('child two', description: 'Two')),
          ]),
          replyStep('first turn'),
          multiCallStep([
            ('a3', 'agent', agentArgs('child three', description: 'Three')),
            ('a4', 'agent', agentArgs('child four', description: 'Four')),
          ]),
          replyStep('second turn'),
        ],
        'child one': [replyStep('one', delayMs: 10)],
        'child two': [replyStep('two', delayMs: 10)],
        'child three': [replyStep('three', delayMs: 10)],
        'child four': [replyStep('four', delayMs: 10)],
      },
    );
    await rig.open();

    final first = rig.run('go');
    await pumpUntil(() => rig.eventsOf<SubagentStarted>().length == 2);
    expect(rig.eventsOf<SubagentStarted>(), hasLength(2), reason: '3 слота');
    await rig.clock.elapse(const Duration(milliseconds: 10));
    await first;

    source.user['subagents'] = {'max_concurrent': 1};
    await rig.core.runtime.reloadConfig();
    final second = rig.run('again');
    await pumpUntil(() => rig.eventsOf<SubagentStarted>().length == 3);
    await pumpEventQueue(times: 30);
    expect(
      rig.eventsOf<SubagentStarted>(),
      hasLength(3),
      reason: 'после перезагрузки слот один: четвёртый ждёт',
    );
    await rig.clock.elapse(const Duration(milliseconds: 10));
    await pumpUntil(() => rig.eventsOf<SubagentStarted>().length == 4);
    await rig.clock.elapse(const Duration(milliseconds: 10));
    await second;
  });
}
