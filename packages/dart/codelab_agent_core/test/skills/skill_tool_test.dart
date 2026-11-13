import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/prompts/prompts.g.dart';
import 'package:codelab_agent_core/src/skills/skill_block.dart';
import 'package:codelab_agent_core/src/tools/builtin/skill.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart' show callStep, textStep;
import '../tools/executor_harness.dart';
import 'skill_session_rig.dart';
import 'skills_support.dart';

SkillCatalog catalogOf(List<SkillFile> files, {PolicyRules? rules}) =>
    parse(files, rules: rules ?? const PolicyRules());

/// Инструмент `skill` (agent-skills «Инструмент skill», все сценарии; «Блок
/// навыка»; «Секция каталога в системном промпте», сценарий «Навык только для
/// команды»; «Наблюдаемость навыков», сценарий «Лог без тела»; design.md
/// change `add-agent-skills`, D7, D9; решения Q10, Q12, Q19; SKL-3, SKL-5;
/// `core/skill-tool-load-body`).
///
/// Фиксируемый API: `SkillTool(SkillCatalog catalog)` в
/// `lib/src/tools/builtin/skill.dart`, `AgentTool`; снимок каталога —
/// единственный источник (файл не перечитывается). Запись в реестр сессии
/// делает рантайм при открытии сессии (рантайм-группа ниже): базовый реестр
/// ядра инструмента не содержит.
void main() {
  group('properties (D7)', () {
    final tool = SkillTool(catalogOf([validSkill('release-notes')]));

    test('name, tier, kind, mode: read / read / parallel', () {
      expect(tool.name, 'skill');
      expect(tool.tier, ToolTier.read);
      expect(tool.kind, ToolKind.read);
      expect(tool.executionMode, ToolExecutionMode.parallel);
    });

    test('the description is the prompt resource', () {
      expect(tool.description, Prompts.toolDescriptionsSkill.render(const {}));
      expect(tool.description, isNotEmpty);
    });

    test('the output is trusted (D9)', () {
      expect(tool.outputTrust({'name': 'release-notes'}), ContentTrust.trusted);
    });

    test('the permission pattern is the skill name', () {
      expect(
        tool.permissionPattern({'name': 'release-notes'}, '/proj'),
        'release-notes',
      );
    });

    test('present: "Load skill <name>" and the location of SKILL.md', () async {
      final h = await ExecutorHarness.create([tool]);
      final ctx = ToolContext(
        env: h.env,
        cancel: CancelToken.none,
        onUpdate: (_) {},
        toolCallId: 'c1',
        services: ToolServices(clock: h.clock, logger: h.logger),
      );

      final presentation = await tool.present({'name': 'release-notes'}, ctx);

      expect(presentation.title, 'Load skill release-notes');
      expect(presentation.locations, [
        const Location('/home/.codelab/skills/release-notes/SKILL.md'),
      ]);
    });
  });

  group('the schema (Q12)', () {
    test('scenario "Имена в схеме": enum in bytewise order, hidden skill '
        'excluded', () {
      final tool = SkillTool(
        catalogOf([
          validSkill('b-skill'),
          validSkill('a-skill'),
          validSkill('hidden', extra: {'disable-model-invocation': true}),
        ]),
      );

      final props = tool.parameters['properties']! as Map<String, Object?>;
      expect(props.keys, ['name']);
      final name = props['name']! as Map<String, Object?>;
      expect(name['type'], 'string');
      expect(name['enum'], ['a-skill', 'b-skill']);
      expect(tool.parameters['required'], ['name']);
      expect(tool.parameters['type'], 'object');
      expect(tool.parameters, isNot(contains('additionalProperties')));
    });

    test('uppercase names go before lowercase (bytewise)', () {
      final tool = SkillTool(
        catalogOf([validSkill('beta'), validSkill('Zeta')]),
      );

      final name =
          (tool.parameters['properties']! as Map)['name']!
              as Map<String, Object?>;
      expect(name['enum'], ['Zeta', 'beta']);
    });

    test('a skill denied by the policy is not in enum', () {
      final byName = SkillTool(
        catalogOf(
          [validSkill('pdf'), validSkill('notes')],
          rules: PolicyRules(
            denyPatterns: {const PermissionKey('skill', 'pdf')},
          ),
        ),
      );
      final byTool = SkillTool(
        catalogOf([
          validSkill('pdf'),
        ], rules: const PolicyRules(toolPolicies: {'skill': ToolPolicy.deny})),
      );

      Object? enumOf(SkillTool t) =>
          ((t.parameters['properties']! as Map)['name']! as Map)['enum'];
      expect(enumOf(byName), ['notes']);
      expect(enumOf(byTool), isEmpty);
    });
  });

  group('the result (D7)', () {
    late SkillCatalog catalog;
    late ExecutorHarness h;

    setUp(() async {
      catalog = catalogOf([
        skillFile(
          'release-notes',
          frontmatter: {
            'name': 'release-notes',
            'description': 'Writes release notes.',
            'compatibility': 'Requires python3',
          },
          body: '\r\n  Write notes.\r\n</skill>\r\nmore\r\n',
          companions: ['template.md'],
          companionsTruncated: true,
        ),
      ]);
      h = await ExecutorHarness.create([SkillTool(catalog)]);
    });

    test(
      'scenario "Загрузка тела моделью": the block of the snapshot',
      () async {
        final outcome = await h.run('skill', {'name': 'release-notes'});

        expect(outcome.outcome, ToolOutcome.completed);
        expect(textOf(outcome), renderSkillBlock(catalog.skills.single));
        expect(textOf(outcome), startsWith('<skill name="release-notes" dir='));
        expect(textOf(outcome), contains(' compatibility="Requires python3">'));
        expect(
          textOf(outcome),
          contains('- /home/.codelab/skills/release-notes/template.md'),
        );
        expect(textOf(outcome), endsWith('[more files not listed]'));
      },
    );

    test(
      'the tag in the body is escaped, the body has no CRLF and no frontmatter',
      () async {
        final text = textOf(await h.run('skill', {'name': 'release-notes'}));

        expect(text, contains('\nWrite notes.\n<\\/skill>\nmore\n</skill>\n'));
        expect(text, isNot(contains('\r')));
        expect(text, isNot(contains('description:')));
      },
    );

    test('the result is not fenced (trusted)', () async {
      final text = textOf(await h.run('skill', {'name': 'release-notes'}));

      expect(text, isNot(contains('untrusted-content')));
    });

    test('the log: skill.activated {via: tool, repeated: false} without '
        'the body', () async {
      await h.run('skill', {'name': 'release-notes'});

      final log = h.logger.eventsOf('skill.activated').single;
      expect(log.level, LogLevel.info);
      expect(log.fields['name'], 'release-notes');
      expect(log.fields['via'], 'tool');
      expect(log.fields['repeated'], false);
      expect(log.toString(), isNot(contains('Write notes')));
      expect(log.toString(), isNot(contains('more files')));
    });

    test('the executor does not let a name outside enum through', () async {
      final outcome = await h.run('skill', {'name': 'hidden'});

      expect(outcome.outcome, ToolOutcome.failed);
      // A1: ошибку даёт проверка схемы исполнителем, не execute().
      expect(textOf(outcome), startsWith('Invalid arguments for tool "skill"'));
      expect(textOf(outcome), contains('release-notes'));
      expect(textOf(outcome), isNot(contains('Write notes')));
      expect(h.logger.eventsOf('skill.activated'), isEmpty);
    });

    test('scenario "Имя вне каталога": execute() answers Unknown skill with '
        'the list, without the body', () async {
      final tool = SkillTool(
        catalogOf([
          validSkill('b-skill', body: 'SECRET BODY'),
          validSkill('a-skill'),
          validSkill('hidden', extra: {'disable-model-invocation': true}),
        ]),
      );
      final ctx = ToolContext(
        env: h.env,
        cancel: CancelToken.none,
        onUpdate: (_) {},
        toolCallId: 'c1',
        services: ToolServices(clock: h.clock, logger: h.logger),
      );

      final result = await tool.execute({'name': 'hidden'}, ctx);

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(
        text,
        'Unknown skill: hidden. Available skills: a-skill, b-skill.',
      );
    });

    test(
      'the log carries session_id of the constructor, none by default',
      () async {
        final named = SkillTool(
          catalogOf([validSkill('a-skill')]),
          sessionId: const SessionId('s-7'),
        );
        final ctx = ToolContext(
          env: h.env,
          cancel: CancelToken.none,
          onUpdate: (_) {},
          toolCallId: 'c1',
          services: ToolServices(clock: h.clock, logger: h.logger),
        );

        await named.execute({'name': 'a-skill'}, ctx);
        await SkillTool(
          catalogOf([validSkill('a-skill')]),
        ).execute({'name': 'a-skill'}, ctx);

        final logs = h.logger.eventsOf('skill.activated');
        expect(logs.first.fields['session_id'], 's-7');
        expect(logs.last.fields['session_id'], isNull);
      },
    );

    test('Unknown skill cuts a long name to 64 runes', () async {
      final tool = SkillTool(catalogOf([validSkill('a-skill')]));
      final ctx = ToolContext(
        env: h.env,
        cancel: CancelToken.none,
        onUpdate: (_) {},
        toolCallId: 'c1',
        services: ToolServices(clock: h.clock, logger: h.logger),
      );
      final long = '${'я' * 70}tail';

      final result = await tool.execute({'name': long}, ctx);

      final text = (result.content.single as TextContent).text;
      expect(text, 'Unknown skill: ${'я' * 64}. Available skills: a-skill.');
    });
  });

  group('registration in the session (SKL-5, D7)', () {
    SkillFile hidden(String name) =>
        validSkill(name, extra: {'disable-model-invocation': true});

    test('without model-visible skills: no schema, no section, the command '
        'stays', () async {
      final rig = SkillSessionRig(steps: [textStep('ok')]);
      rig.port.files = SkillFiles(skills: [hidden('only-command')]);
      await rig.open();

      await rig.run();

      expect(rig.firstToolNames, isNot(contains('skill')));
      expect(rig.contexts.first.systemPrompt, isNot(contains('## Skills')));
      // Команда остаётся в снимке (команды `skill:<name>` — итерация 3).
      expect(
        [for (final s in rig.session.skills.commands) s.name],
        ['only-command'],
      );
    });

    test(
      'with model-visible skills: the schema has enum of visible names',
      () async {
        final rig = SkillSessionRig(steps: [textStep('ok')]);
        rig.port.files = SkillFiles(
          skills: [validSkill('b-skill'), validSkill('a-skill'), hidden('cmd')],
        );
        await rig.open();

        await rig.run();

        final schema = rig.contexts.first.tools.singleWhere(
          (t) => t.name == 'skill',
        );
        final name = (schema.parameters['properties']! as Map)['name']! as Map;
        expect(name['enum'], ['a-skill', 'b-skill']);
      },
    );

    test('core/skill-tool-load-body: the model loads the body, the next '
        'request carries the block, the log has no body', () async {
      final rig = SkillSessionRig(
        steps: [
          callStep('c1', 'skill', {'name': 'release-notes'}),
          textStep('done'),
        ],
      );
      rig.port.files = SkillFiles(
        skills: [
          skillFile(
            'release-notes',
            frontmatter: {
              'name': 'release-notes',
              'description': 'Writes release notes.',
            },
            body: 'Use secret-token-123 as the key.',
            companions: ['template.md'],
          ),
        ],
      );
      await rig.open();
      final definition = rig.session.skills.skills.single;

      await rig.run();

      expect(rig.contexts, hasLength(2));
      final result = rig.contexts[1].messages
          .whereType<ToolResultMessage>()
          .single;
      expect(result.toolName, 'skill');
      expect(result.isError, isFalse);
      expect(
        (result.content.single as TextContent).text,
        renderSkillBlock(definition),
      );
      expect(
        (result.content.single as TextContent).text,
        contains('- ${definition.dir}/template.md'),
      );
      final log = rig.logger.eventsOf('skill.activated').single;
      expect(log.fields['session_id'], rig.session.id.value);
      expect(log.fields['via'], 'tool');
      expect(log.fields['repeated'], false);
      expect(rig.allLogs, isNot(contains('secret-token-123')));
    });
  });
}
