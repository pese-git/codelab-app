import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../skills/skill_command_rig.dart';
import '../skills/skills_support.dart';

/// Команды навыков в списке сессии, `/help` и разборе неизвестной команды
/// (agent-slash-commands «Список команд сессии», сценарий «Навыки после
/// шаблонов»; «Неизвестная команда», сценарий «skill без навыков»;
/// agent-skills «Команды навыков», сценарии «Неизвестный навык», «Навык без
/// команды», «Навыки выключены»; design.md change `add-agent-skills`, D8, D16;
/// R-07, R-08, SKL-5, SKL-6).
///
/// Фиксируемый API: `SlashCommandSource.skill` (wire `skill`),
/// `AgentSession.commands` с командами `skill:<name>` после шаблонов.
/// Разворачивание тела — `test/runtime/command_expansion_test.dart`.
void main() {
  SkillFile skill(String name, {Map<String, Object?> extra = const {}}) =>
      validSkill(name, extra: extra);

  const unknownSkillTail = 'Run /help to list commands.';

  group('the list (scenario "Навыки после шаблонов")', () {
    test('after builtin commands and templates: skill:<name> in bytewise '
        'order, the hint from argument-hint or "arguments", no tool skill, '
        'no non-invocable skill', () async {
      final rig = SkillCommandRig(
        narrow: {
          HostCapability.compaction: const CapabilityOff('test'),
          HostCapability.mcp: const CapabilityOff('test'),
        },
        templates: [templateFile('review', r'Review $1')],
        skills: [
          skill(
            'release-notes',
            extra: {'argument-hint': '<from-tag> <to-tag>'},
          ),
          skill('flutter-golden'),
          skill('internal', extra: {'user-invocable': false}),
        ],
      );
      final session = await rig.open();

      expect(
        [for (final c in session.commands) c.name],
        [
          'mode',
          'model',
          'status',
          'help',
          'review',
          'skill:flutter-golden',
          'skill:release-notes',
        ],
      );
      final byName = {for (final c in session.commands) c.name: c};
      expect(byName['skill:flutter-golden']!.inputHint, 'arguments');
      expect(byName['skill:release-notes']!.inputHint, '<from-tag> <to-tag>');
      expect(
        byName['skill:release-notes']!.description,
        'About release-notes.',
      );
      expect(byName['skill:release-notes']!.source, SlashCommandSource.skill);
      expect(SlashCommandSource.skill.wire, 'skill');
      expect(byName['review']!.source, SlashCommandSource.template);
      expect(byName, isNot(contains('skill:internal')));
      expect(byName, isNot(contains('skill')));
    });

    test('uppercase names go before lowercase (bytewise), as in the tool '
        'enum', () async {
      final rig = SkillCommandRig(skills: [skill('beta'), skill('Zeta')]);
      final session = await rig.open();

      expect(
        [
          for (final c in session.commands)
            if (c.source == SlashCommandSource.skill) c.name,
        ],
        ['skill:Zeta', 'skill:beta'],
      );
    });

    test('a skill hidden from the model (disable-model-invocation) is still '
        'a user command', () async {
      final rig = SkillCommandRig(
        skills: [
          skill('only-command', extra: {'disable-model-invocation': true}),
        ],
      );
      final session = await rig.open();

      expect(session.commands.last.name, 'skill:only-command');
    });

    test('capability skills off: no skill:* commands', () async {
      final rig = SkillCommandRig(
        narrow: {HostCapability.skills: const CapabilityOff('test')},
        skills: [skill('release-notes')],
      );
      final session = await rig.open();

      expect(
        session.commands.where((c) => c.source == SlashCommandSource.skill),
        isEmpty,
      );
    });

    test('skills.enabled: false: no skill:* commands (SKL-5)', () async {
      final rig = SkillCommandRig(
        settings: const SkillsConfig(enabled: false),
        skills: [skill('release-notes')],
      );
      final session = await rig.open();

      expect(
        session.commands.where((c) => c.source == SlashCommandSource.skill),
        isEmpty,
      );
    });

    test(
      'the list does not change after the session is open (a snapshot)',
      () async {
        final rig = SkillCommandRig(skills: [skill('a-skill')]);
        final session = await rig.open();
        final before = [for (final c in session.commands) c.name];

        rig.port.files = SkillFiles(
          skills: [skill('a-skill'), skill('b-skill')],
        );
        await rig.ask('hello');

        expect([for (final c in session.commands) c.name], before);
      },
    );
  });

  group('/help marks skill commands with (skill)', () {
    test('the line is "/skill:<name> <hint> - <description> (skill)", '
        'templates keep (template)', () async {
      final rig = SkillCommandRig(
        narrow: {
          HostCapability.compaction: const CapabilityOff('test'),
          HostCapability.mcp: const CapabilityOff('test'),
        },
        templates: [templateFile('review', 'Review')],
        skills: [
          skill('release-notes', extra: {'argument-hint': '<from> <to>'}),
          skill('flutter-golden'),
        ],
      );
      await rig.open();

      final reply = await rig.ask('/help');

      expect(reply.text.split('\n'), [
        'Commands:',
        '/mode plan | ask | standard | accept-edits | bypass - '
            'Switch the session mode',
        '/model provider/model - Switch the model',
        '/status - Show the model, mode, working directory and MCP servers',
        '/help - List commands',
        '/review - Review (template)',
        '/skill:flutter-golden arguments - About flutter-golden. (skill)',
        '/skill:release-notes <from> <to> - About release-notes. (skill)',
      ]);
      expect(rig.streamCalls, 0);
    });
  });

  group('an unknown skill (scenario "Неизвестный навык")', () {
    test(
      'no model, one agent message, endTurn, the journal is untouched',
      () async {
        final rig = SkillCommandRig(skills: [skill('release-notes')]);
        await rig.open();
        final journal = rig.store.textOf(rig.session.id);

        final reply = await rig.ask('/skill:nope x');

        expect(reply.text, 'Unknown skill: nope. $unknownSkillTail');
        expect(
          [for (final e in reply.events) e.runtimeType],
          [TurnStarted, MessageStarted, MessageDelta, MessageEnded, TurnEnded],
        );
        expect(reply.result.reason, TurnEndReason.completed);
        expect(rig.streamCalls, 0);
        expect(rig.store.textOf(rig.session.id), journal);
        expect(rig.logger.eventsOf('skill.activated'), isEmpty);
      },
    );

    test('a long name is cut to 64 runes', () async {
      final rig = SkillCommandRig(skills: [skill('release-notes')]);
      await rig.open();

      final reply = await rig.ask('/skill:${'a' * 100}');

      expect(reply.text, 'Unknown skill: ${'a' * 64}. $unknownSkillTail');
    });

    test('user-invocable: false answers like an unknown skill and writes '
        'nothing (scenario "Навык без команды")', () async {
      final rig = SkillCommandRig(
        skills: [
          skill('internal', extra: {'user-invocable': false}),
        ],
      );
      await rig.open();
      final journal = rig.store.textOf(rig.session.id);

      final reply = await rig.ask('/skill:internal go');

      expect(reply.text, 'Unknown skill: internal. $unknownSkillTail');
      expect(rig.streamCalls, 0);
      expect(rig.store.textOf(rig.session.id), journal);
    });

    test('the slot is free afterwards', () async {
      final rig = SkillCommandRig();
      await rig.open();

      await rig.ask('/skill:nope');
      final reply = await rig.ask('hello');

      expect(reply.result.reason, TurnEndReason.completed);
      expect(rig.streamCalls, 1);
    });
  });

  group('skills off: Unknown command, not Unknown skill', () {
    test('scenario "skill без навыков": capability skills off', () async {
      final rig = SkillCommandRig(
        narrow: {HostCapability.skills: const CapabilityOff('test')},
        skills: [skill('release-notes')],
      );
      await rig.open();

      final reply = await rig.ask('/skill:release-notes');

      expect(
        reply.text,
        'Unknown command: /skill:release-notes. $unknownSkillTail',
      );
      expect(rig.streamCalls, 0);
    });

    test('scenario "Навыки выключены": skills.enabled false', () async {
      final rig = SkillCommandRig(
        settings: const SkillsConfig(enabled: false),
        skills: [skill('release-notes')],
      );
      await rig.open();

      final reply = await rig.ask('/skill:release-notes');

      expect(
        reply.text,
        'Unknown command: /skill:release-notes. $unknownSkillTail',
      );
      expect(rig.streamCalls, 0);
      expect(rig.logger.eventsOf('command.unknown'), hasLength(1));
    });
  });

  group('the parse order (D8): builtin, template, skill:, unknown', () {
    test('a word with the prefix skill: is not handled as a template or as '
        'an unknown command while the skill exists', () async {
      final rig = SkillCommandRig(
        templates: [templateFile('review', 'Review')],
        skills: [skill('notes')],
      );
      await rig.open();

      await rig.ask('/skill:notes');

      expect(rig.streamCalls, 1);
      expect(rig.logger.eventsOf('command.unknown'), isEmpty);
    });

    test('a path with the prefix is not a command and goes to the model '
        'unchanged', () async {
      final rig = SkillCommandRig(skills: [skill('notes')]);
      await rig.open();

      await rig.ask('/skill:/etc/passwd please');

      expect(rig.lastUserText, '/skill:/etc/passwd please');
    });
  });

  group('details of D18', () {
    test('a description longer than 1024 runes is cut with …', () async {
      final rig = SkillCommandRig(
        skills: [
          validSkill('long', extra: {'description': 'я' * 1100}),
        ],
      );
      final session = await rig.open();

      final command = session.commands.singleWhere(
        (c) => c.name == 'skill:long',
      );

      expect(command.description, '${'я' * 1024}…');
    });

    test('a description of exactly 1024 runes stays as is', () async {
      final rig = SkillCommandRig(
        skills: [
          validSkill('edge', extra: {'description': 'я' * 1024}),
        ],
      );
      final session = await rig.open();

      expect(
        session.commands.singleWhere((c) => c.name == 'skill:edge').description,
        'я' * 1024,
      );
    });

    test('/skill:x without skills in the snapshot: the exact Unknown '
        'command and the log command.unknown', () async {
      final rig = SkillCommandRig();
      await rig.open();

      final reply = await rig.ask('/skill:x');

      expect(
        reply.text,
        'Unknown command: /skill:x. Run /help to list commands.',
      );
      expect(rig.streamCalls, 0);
      expect(rig.logger.eventsOf('command.unknown'), hasLength(1));
    });

    test('/skill: without a name: Unknown command: /skill:.', () async {
      final rig = SkillCommandRig(skills: [skill('release-notes')]);
      await rig.open();

      final reply = await rig.ask('/skill:');

      expect(
        reply.text,
        'Unknown command: /skill:. Run /help to list commands.',
      );
      expect(rig.streamCalls, 0);
    });

    test('only non-invocable skills: the branch is on, so Unknown skill '
        'and not Unknown command', () async {
      final rig = SkillCommandRig(
        skills: [
          skill('internal', extra: {'user-invocable': false}),
        ],
      );
      final session = await rig.open();

      final reply = await rig.ask('/skill:internal');

      expect(
        session.commands.where((c) => c.source == SlashCommandSource.skill),
        isEmpty,
      );
      expect(reply.text, 'Unknown skill: internal. $unknownSkillTail');
    });

    test('the log of an unknown skill: command.unknown {session_id, '
        'name_bytes, source: skill}, bytes of the word after the slash, no '
        'name', () async {
      final rig = SkillCommandRig(skills: [skill('release-notes')]);
      await rig.open();

      await rig.ask('/skill:nope');

      final log = rig.logger.eventsOf('command.unknown').single;
      expect(log.level, LogLevel.info);
      expect(log.fields['name_bytes'], 'skill:nope'.length);
      expect(log.fields['source'], 'skill');
      expect(log.fields['session_id'], rig.session.id.value);
      expect(log.fields, isNot(contains('name')));
      expect(log.toString(), isNot(contains('nope')));
      expect(rig.logger.eventsOf('skill.activated'), isEmpty);
    });
  });
}
