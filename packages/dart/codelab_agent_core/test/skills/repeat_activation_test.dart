import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart' show textStep;
import '../session/journal_lines.dart' show compaction;
import 'skill_command_rig.dart';
import 'skills_support.dart';

/// Повторная активация (agent-skills «Повторная активация», сценарии «Модель
/// загружает навык дважды», «Модель загрузила, пользователь вызвал»,
/// «Повтор команды с другими аргументами»; «Активные навыки»; design.md
/// change `add-agent-skills`, D7, D8, D15; решение Q10; руководство Agent
/// Skills, «Deduplicate activations»). Сквозные тесты через
/// `createSession` + `prompt`; чистая функция — `active_skills_test.dart`.
/// Сценарии со сжатием — итерация 4 (`4.1`).
void main() {
  const toolRepeat =
      'Skill "{n}" is already loaded in this conversation; follow the '
      'instructions above.';
  String commandRepeat(String name) =>
      'The user invoked the skill "$name" again; its instructions are '
      'already loaded above.';

  SkillFile plain(String name) => validSkill(name, body: 'Body of $name.');
  SkillFile withArg() =>
      validSkill('release-notes', body: r'Collect changes for $1.');

  /// Тексты результатов инструмента `skill` в последнем запросе модели.
  List<ToolResultMessage> toolResults(SkillCommandRig rig) =>
      rig.contexts.last.messages.whereType<ToolResultMessage>().toList();

  String resultText(ToolResultMessage m) =>
      m.content.whereType<TextContent>().map((b) => b.text).join();

  group('the tool skill', () {
    test('scenario "Модель загружает навык дважды": the second result is the '
        'repeat line, no body, isError false, log repeated true', () async {
      final rig = SkillCommandRig(
        skills: [plain('release-notes')],
        steps: [
          loadSkillStep('c1', 'release-notes'),
          loadSkillStep('c2', 'release-notes'),
          textStep('done'),
        ],
      );
      await rig.open();

      await rig.ask('go');

      final results = toolResults(rig);
      expect(results, hasLength(2));
      expect(resultText(results.first), contains('Body of release-notes.'));
      expect(
        resultText(results.last),
        toolRepeat.replaceFirst('{n}', 'release-notes'),
      );
      expect(results.last.isError, isFalse);
      expect(resultText(results.last), isNot(contains('Body of')));
      expect(
        [
          for (final l in rig.logger.eventsOf('skill.activated'))
            l.fields['repeated'],
        ],
        [false, true],
      );
    });

    test('another skill is a full block: the mark concerns the same skill '
        'only', () async {
      final rig = SkillCommandRig(
        skills: [plain('a-skill'), plain('b-skill')],
        steps: [
          loadSkillStep('c1', 'a-skill'),
          loadSkillStep('c2', 'b-skill'),
          loadSkillStep('c3', 'a-skill'),
          textStep('done'),
        ],
      );
      await rig.open();

      await rig.ask('go');

      final results = toolResults(rig);
      expect(resultText(results[1]), contains('Body of b-skill.'));
      expect(resultText(results[2]), toolRepeat.replaceFirst('{n}', 'a-skill'));
      expect(
        [
          for (final l in rig.logger.eventsOf('skill.activated'))
            l.fields['repeated'],
        ],
        [false, false, true],
      );
    });

    test('the repeat mark does not hide the skill from the journal: a '
        'third call is a repeat again', () async {
      final rig = SkillCommandRig(
        skills: [plain('a-skill')],
        steps: [
          loadSkillStep('c1', 'a-skill'),
          loadSkillStep('c2', 'a-skill'),
          loadSkillStep('c3', 'a-skill'),
          textStep('done'),
        ],
      );
      await rig.open();

      await rig.ask('go');

      final results = toolResults(rig);
      expect(resultText(results[1]), resultText(results[2]));
      expect(resultText(results[2]), contains('already loaded'));
    });

    test('a skill the user invoked by the command is active for the tool: '
        'the model gets the repeat line', () async {
      final rig = SkillCommandRig(
        skills: [withArg()],
        steps: [
          textStep('ok'),
          loadSkillStep('c1', 'release-notes'),
          textStep('done'),
        ],
      );
      await rig.open();

      await rig.ask('/skill:release-notes v1.2');
      await rig.ask('go');

      expect(
        resultText(toolResults(rig).single),
        toolRepeat.replaceFirst('{n}', 'release-notes'),
      );
      expect(
        rig.logger.eventsOf('skill.activated').last.fields,
        containsPair('repeated', true),
      );
    });

    test('reading SKILL.md is not an activation: the skill tool still '
        'returns the full block', () async {
      final rig = SkillCommandRig(
        skills: [plain('a-skill')],
        steps: [
          {
            'reply': [
              {
                'toolCall': {
                  'id': 'r1',
                  'name': 'read',
                  'arguments': {
                    'path': '/home/.codelab/skills/a-skill/SKILL.md',
                  },
                },
              },
            ],
          },
          loadSkillStep('c1', 'a-skill'),
          textStep('done'),
        ],
      );
      await rig.open();

      await rig.ask('go');

      expect(resultText(toolResults(rig).last), contains('Body of a-skill.'));
      expect(
        rig.logger.eventsOf('skill.activated').single.fields['repeated'],
        false,
      );
    });
  });

  group('the command /skill:<name>', () {
    test('scenario "Модель загрузила, пользователь вызвал": the repeat line '
        'and ARGUMENTS: <input>, no block', () async {
      final rig = SkillCommandRig(
        skills: [plain('notes')],
        steps: [loadSkillStep('c1', 'notes'), textStep('done'), textStep('ok')],
      );
      await rig.open();
      await rig.ask('go');

      await rig.ask('/skill:notes draft');

      expect(rig.lastUserText, '${commandRepeat('notes')}\n\nARGUMENTS: draft');
      expect(rig.lastUserText, isNot(contains('<skill')));
      final log = rig.logger.eventsOf('skill.activated').last;
      expect(log.fields['via'], 'command');
      expect(log.fields['repeated'], true);
    });

    test('an empty input: the repeat line only', () async {
      final rig = SkillCommandRig(skills: [plain('notes')]);
      await rig.open();
      await rig.ask('/skill:notes');

      await rig.ask('/skill:notes');

      expect(rig.lastUserText, commandRepeat('notes'));
    });

    test(
      'the same arguments of a body with placeholders: the repeat line '
      '(scenario "Повтор команды с другими аргументами", the tail)',
      () async {
        final rig = SkillCommandRig(skills: [withArg()]);
        await rig.open();

        await rig.ask('/skill:release-notes v1.2');
        expect(rig.lastUserText, contains('Collect changes for v1.2.'));
        await rig.ask('/skill:release-notes v1.2');

        expect(
          rig.lastUserText,
          '${commandRepeat('release-notes')}\n\nARGUMENTS: v1.2',
        );
        expect(rig.lastUserText, isNot(contains('<skill')));
      },
    );

    test('other arguments of a body with placeholders: a full block with '
        'the new text', () async {
      final rig = SkillCommandRig(skills: [withArg()]);
      await rig.open();

      await rig.ask('/skill:release-notes v1.2');
      await rig.ask('/skill:release-notes v1.3');

      expect(
        rig.lastUserText,
        rig.invoked('release-notes', body: 'Collect changes for v1.3.'),
      );
      expect(
        rig.logger.eventsOf('skill.activated').last.fields['repeated'],
        false,
      );
    });

    test('a newer record replaces the older one (D15, step 4): v1.2, v1.3, '
        'v1.2 is a full block again', () async {
      final rig = SkillCommandRig(skills: [withArg()]);
      await rig.open();

      await rig.ask('/skill:release-notes v1.2');
      await rig.ask('/skill:release-notes v1.3');
      await rig.ask('/skill:release-notes v1.2');

      expect(
        rig.lastUserText,
        rig.invoked('release-notes', body: 'Collect changes for v1.2.'),
      );
    });

    test('the model loaded a body with placeholders, the user invoked: the '
        'content differs (raw body vs substituted), a full block', () async {
      final rig = SkillCommandRig(
        skills: [withArg()],
        steps: [
          loadSkillStep('c1', 'release-notes'),
          textStep('done'),
          textStep('ok'),
        ],
      );
      await rig.open();
      await rig.ask('go');

      await rig.ask('/skill:release-notes v1.2');

      expect(
        rig.lastUserText,
        rig.invoked('release-notes', body: 'Collect changes for v1.2.'),
      );
    });

    test('a skill hidden from the model is repeated '
        'too (a command-only skill)', () async {
      final rig = SkillCommandRig(
        skills: [
          validSkill(
            'cmd',
            body: 'Only for the user.',
            extra: {'disable-model-invocation': true},
          ),
        ],
      );
      await rig.open();

      await rig.ask('/skill:cmd');
      await rig.ask('/skill:cmd more');

      expect(rig.lastUserText, '${commandRepeat('cmd')}\n\nARGUMENTS: more');
    });

    test('the repeat message is a command record in the journal with the '
        'typed arguments; the model context holds the repeat line', () async {
      final rig = SkillCommandRig(skills: [plain('notes')]);
      await rig.open();
      await rig.ask('/skill:notes');

      await rig.ask('/skill:notes draft');

      final record = rig.journal().lastWhere((r) => r.containsKey('command'));
      expect(record['command'], {
        'source': 'skill',
        'name': 'notes',
        'args': 'draft',
      });
    });
  });

  // Q48 (б), D18: SKILL.md изменили между сессиями, затем `session/load`.
  // Журнал помнит прежний текст, снимок каталога — новый; такая запись не
  // активация, поэтому повтор вставляет новое тело полностью.
  group('SKILL.md changed before session/load (Q48 (б))', () {
    Future<AgentSession> reopen(SkillCommandRig rig, SkillFile changed) async {
      final created = rig.session;
      await created.close();
      rig.port.files = SkillFiles(skills: [changed]);
      return rig.session = await rig.core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
        cwd: '/work/a',
      );
    }

    test('the command: the old record is not an activation, the new body '
        'goes in full, not as the repeat line', () async {
      final rig = SkillCommandRig(
        skills: [validSkill('notes', body: 'Old notes.')],
      );
      await rig.open();
      await rig.ask('/skill:notes');
      await reopen(rig, validSkill('notes', body: 'New notes.'));

      await rig.ask('/skill:notes');

      expect(rig.lastUserText, rig.invoked('notes'));
      expect(rig.lastUserText, contains('New notes.'));
      expect(rig.lastUserText, isNot(contains('already loaded')));
      expect(
        rig.logger.eventsOf('skill.activated').last.fields['repeated'],
        false,
      );
    });

    test('the tool: the old block is not an activation, the model gets '
        'the new block', () async {
      final rig = SkillCommandRig(
        skills: [validSkill('notes', body: 'Old notes.')],
        steps: [
          loadSkillStep('c1', 'notes'),
          textStep('done'),
          loadSkillStep('c2', 'notes'),
          textStep('done again'),
        ],
      );
      await rig.open();
      await rig.ask('go');
      await reopen(rig, validSkill('notes', body: 'New notes.'));

      await rig.ask('go again');

      final text = resultText(toolResults(rig).last);
      expect(text, contains('New notes.'));
      expect(text, isNot(contains('already loaded')));
    });

    test(
      'an unchanged file: the repeat still works after session/load',
      () async {
        final rig = SkillCommandRig(skills: [plain('notes')]);
        await rig.open();
        await rig.ask('/skill:notes');
        await reopen(rig, plain('notes'));

        await rig.ask('/skill:notes');

        expect(rig.lastUserText, commandRepeat('notes'));
      },
    );
  });

  test('the repeat message is not an activation: after it, a changed body '
      'is not taken for loaded (the tail of the session)', () async {
    final rig = SkillCommandRig(skills: [plain('notes')]);
    await rig.open();
    await rig.ask('/skill:notes');
    await rig.ask('/skill:notes again');

    final records = rig.journal().where((r) => r.containsKey('command'));
    expect(records, hasLength(2));
    expect(rig.lastUserText, '${commandRepeat('notes')}\n\nARGUMENTS: again');
  });

  // D15, шаги 1 и 3: активация до `firstKeptId` последнего сжатия ушла в
  // резюме и в контексте модели не лежит. Перенос навыков после сжатия —
  // итерация 4, поэтому сейчас повтор невозможен и вставляется полный блок.
  group('after a compaction the activation does not count (D15)', () {
    /// Сессия, где навык загружен, а в журнал дописано сжатие: `firstKeptId` —
    /// последняя запись, то есть активация осталась в резюме.
    Future<SkillCommandRig> compacted({
      required List<Map<String, Object?>> steps,
    }) async {
      final rig = SkillCommandRig(skills: [plain('notes')], steps: steps);
      await rig.open();
      await rig.ask('go');
      final created = rig.session;
      await created.close();
      final records = rig.journal();
      final lastId = records.last['id']! as String;
      rig.store.putText(
        created.id,
        '${rig.store.textOf(created.id)}'
        '${compaction('k1', lastId, firstKept: lastId)}\n',
      );
      rig.session = await rig.core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
        cwd: '/work/a',
      );
      return rig;
    }

    test('the command gives a full block, not the repeat line', () async {
      final rig = await compacted(
        steps: [loadSkillStep('c1', 'notes'), textStep('done'), textStep('ok')],
      );

      await rig.ask('/skill:notes');

      expect(rig.lastUserText, rig.invoked('notes'));
      expect(
        rig.logger.eventsOf('skill.activated').last.fields['repeated'],
        false,
      );
    });

    test('the tool gives a full block, not the repeat line', () async {
      final rig = await compacted(
        steps: [
          loadSkillStep('c1', 'notes'),
          textStep('done'),
          loadSkillStep('c2', 'notes'),
          textStep('ok'),
        ],
      );

      await rig.ask('again');

      final text = resultText(toolResults(rig).last);
      expect(text, contains('Body of notes.'));
      expect(text, isNot(contains('already loaded')));
    });
  });
}
