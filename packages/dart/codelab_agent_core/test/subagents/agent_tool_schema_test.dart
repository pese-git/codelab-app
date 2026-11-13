import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../permissions/fake_gate.dart';
import '../support/models.dart';
import 'subagent_rig.dart';

/// Инструмент `agent`: схема, `enum` типов, проверки и ключ разрешения
/// (agent-subagents «Инструмент agent и типы субагентов», сценарии «Enum
/// типов» и «Неверный заголовок»; agent-configuration «Глубина 1»;
/// agent-permissions «Всегда для типа субагента»; agent-runtime «Субагенты
/// включены»; design.md change `add-subagents-and-tasks`, D36 Т5;
/// `agent-core/17-3-subagents.md` §17.3.2).
///
/// Красные до задач 2.3–2.4: инструмента `agent` нет в реестре сессии.
/// Схема читается из первого запроса модели — это то, что видит модель, а не
/// внутренности `SubagentTool`.
void main() {
  /// Результат вызова [id] — текст из контекста следующего запроса.
  String lastResultText(SubagentRig rig, String id) =>
      resultText(rig.contexts.last, id);

  Future<SubagentRig> runOnce({
    CoreConfig? config,
    List<MarkdownFile> agents = const [],
  }) async {
    final rig = SubagentRig(
      scripts: {
        'go': [replyStep('ok')],
      },
      config: config,
      projectFiles: AgentsPort(agents),
    );
    await rig.open();
    await rig.run('go');
    return rig;
  }

  Map<String, Object?> properties(SubagentRig rig) =>
      (schemaOf(rig.contexts.first, 'agent').parameters['properties']!
          as Map<String, Object?>);

  test('сценарий «Enum типов»: explore, general, plan, review и reviewer по '
      'алфавиту, без определения со scope session', () async {
    final rig = await runOnce(
      agents: [
        agentFile('reviewer', scope: 'both'),
        agentFile('notes', scope: 'session'),
      ],
    );

    final type = properties(rig)['type']! as Map<String, Object?>;
    expect(type['enum'], ['explore', 'general', 'plan', 'review', 'reviewer']);
    expect(type['default'], 'general');
  });

  test(
    'определение со scope subagent входит в enum, пользовательское с '
    'именем встроенного заменяет его (лог subagent.type_overridden)',
    () async {
      final rig = await runOnce(
        agents: [
          agentFile('auditor', scope: 'subagent'),
          agentFile('explore', scope: 'both', body: 'My explore.'),
        ],
      );

      final type = properties(rig)['type']! as Map<String, Object?>;
      expect(type['enum'], ['auditor', 'explore', 'general', 'plan', 'review']);
      expect(rig.logger.eventsOf('subagent.type_overridden'), hasLength(1));
    },
  );

  test('схема базового этапа: description, prompt, type и task; нет '
      'output_schema и run_in_background', () async {
    final rig = await runOnce();

    final schema = schemaOf(rig.contexts.first, 'agent');
    expect(schema.parameters['required'], ['description', 'prompt']);
    expect(properties(rig).keys.toSet(), {
      'description',
      'prompt',
      'type',
      'task',
    });
  });

  test('agent идёт последним встроенным инструментом сессии, после '
      'базовых (agent-runtime «Субагенты включены»)', () async {
    final rig = await runOnce();

    expect(toolNamesOf(rig.contexts.first), [
      'read',
      'write',
      'edit',
      'task_create',
      'task_update',
      'task_list',
      'task_get',
      'ls',
      'search',
      'agent',
    ]);
  });

  group('сценарий «Неверный заголовок»', () {
    /// Ход корня с одним вызовом `agent`; ребёнка в скриптах нет: запрос с
    /// ключом [prompt] получил бы ошибку «нет скрипта» и был бы виден.
    Future<SubagentRig> badCall(Map<String, Object?> args) async {
      final rig = SubagentRig(
        scripts: {
          'go': [oneCallStep('c1', 'agent', args), replyStep('ok')],
        },
      );
      await rig.open();
      await rig.run('go');
      return rig;
    }

    test('description из двух символов: результат-ошибка, ни ребёнка, ни '
        'журнала', () async {
      final rig = await badCall(agentArgs('look around', description: 'ab'));

      expect(
        lastResultText(rig, 'c1'),
        'Invalid agent call: description must be 3-60 characters.',
      );
      expect(resultIsError(rig.contexts.last, 'c1'), isTrue);
      expect(rig.requestsOf('look around'), isEmpty);
      expect(
        rig.eventsOf<ToolCallFinished>().single.outcome,
        ToolOutcome.failed,
      );
      expect((await rig.store.list()).items, hasLength(1));
    });

    test('description считается после обрезки пробелов', () async {
      final rig = await badCall(
        agentArgs('look around', description: '  ab  '),
      );

      expect(
        lastResultText(rig, 'c1'),
        'Invalid agent call: description must be 3-60 characters.',
      );
    });

    test('description длиннее 60 символов', () async {
      final rig = await badCall(
        agentArgs('look around', description: 'x' * 61),
      );

      expect(
        lastResultText(rig, 'c1'),
        'Invalid agent call: description must be 3-60 characters.',
      );
    });

    test('пустой prompt', () async {
      final rig = await badCall(agentArgs('', description: 'Look around'));

      expect(
        lastResultText(rig, 'c1'),
        'Invalid agent call: prompt must be 1-32768 characters.',
      );
    });

    test('prompt длиннее 32768 символов', () async {
      final rig = await badCall(
        agentArgs('p' * 32769, description: 'Look around'),
      );

      expect(
        lastResultText(rig, 'c1'),
        'Invalid agent call: prompt must be 1-32768 characters.',
      );
    });

    test('неизвестный пункт списка задач: Unknown task #9, ребёнок не '
        'создан', () async {
      final rig = await badCall(agentArgs('look around', task: '9'));

      expect(lastResultText(rig, 'c1'), startsWith('Unknown task #9.'));
      expect(rig.requestsOf('look around'), isEmpty);
    });
  });

  group('сценарий «Глубина 1» (agent-configuration)', () {
    test('при max_depth 1 описание agent корня: потомки не запускают '
        'потомков', () async {
      final rig = await runOnce(
        config: CoreConfig(
          defaultModel: testModel,
          subagents: const SubagentsConfig(maxDepth: 1),
        ),
      );

      expect(
        schemaOf(rig.contexts.first, 'agent').description,
        contains('Subagents you start cannot start other subagents.'),
      );
    });

    test('при max_depth 3 описание корня разрешает ещё два уровня '
        '(agent-prompts «Описание agent по глубине»)', () async {
      final rig = await runOnce(
        config: CoreConfig(
          defaultModel: testModel,
          subagents: const SubagentsConfig(maxDepth: 3),
        ),
      );

      expect(
        schemaOf(rig.contexts.first, 'agent').description,
        contains(
          'A subagent may start its own subagents, up to 2 more level(s) '
          'below it.',
        ),
      );
    });

    test('описание agent перечисляет типы строками "- <name>: '
        '<description>" по алфавиту', () async {
      final rig = await runOnce();

      final description = schemaOf(rig.contexts.first, 'agent').description;
      final lines = [
        for (final name in ['explore', 'general', 'plan', 'review'])
          description.indexOf('- $name: '),
      ];
      expect(lines, everyElement(isNonNegative));
      expect(lines, orderedEquals([...lines]..sort()));
    });
  });

  group('agent-runtime «Субагенты выключены»', () {
    test('subagents.enabled: false — ни схемы agent, ни его описания в '
        'промпте', () async {
      final rig = await runOnce(
        config: CoreConfig(
          defaultModel: testModel,
          subagents: const SubagentsConfig(enabled: false),
        ),
      );

      expect(toolNamesOf(rig.contexts.first), isNot(contains('agent')));
      expect(rig.contexts.first.systemPrompt, isNot(contains('subagent')));
    });
  });

  group('сценарий «Всегда для типа субагента» (agent-permissions)', () {
    test('allowAlways для explore не разрешает general: gate получает '
        'запрос только по general', () async {
      final gate = FakeGate((_) => PermissionDecision.allowAlways);
      final rig = SubagentRig(
        scripts: {
          'go': [
            oneCallStep(
              'c1',
              'agent',
              agentArgs('first explore', type: 'explore'),
            ),
            oneCallStep(
              'c2',
              'agent',
              agentArgs('second explore', type: 'explore'),
            ),
            oneCallStep(
              'c3',
              'agent',
              agentArgs('then general', type: 'general'),
            ),
            replyStep('done'),
          ],
          'first explore': [replyStep('found a')],
          'second explore': [replyStep('found b')],
          'then general': [replyStep('did c')],
        },
        gate: gate,
        config: rigConfig(mode: ModeId.ask),
      );
      await rig.open();

      await rig.run('go');

      final asked = [
        for (final r in gate.requests)
          if (r.tool == 'agent') r.pattern,
      ];
      expect(asked, ['explore', 'general']);
    });
  });
}
