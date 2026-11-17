import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/projections.dart';
import 'package:test/test.dart';

import '../skills/skill_command_rig.dart';
import '../skills/skills_support.dart';
import 'journal_lines.dart';

/// Журнал сессии и команда навыка (agent-sessions «Поле записи command»,
/// сценарий «Команда навыка в журнале»; «Заголовок сессии из команды»;
/// design.md change `add-agent-skills`, D8; §8.2.3). Образец —
/// `record_command_test.dart` (то же для шаблонов).
///
/// Фиксируемое поведение: `CommandRef.displayText` для источника `skill`
/// даёт `/skill:<name>` или `/skill:<name> <args>`; в журнале `command.name`
/// — имя навыка без префикса `skill:`.
void main() {
  const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  SessionSnapshot snapshot(List<String> lines) =>
      parseSessionLines(journal([header(), ...lines]), id: id).snapshot;

  const skillCommand = {
    'source': 'skill',
    'name': 'release-notes',
    'args': 'v1.2 v1.3',
  };

  group('the record', () {
    test('a record with source skill reads into a typed field and writes '
        'back without loss', () {
      final line = user('u1', null, text: 'WRAPPED', command: skillCommand);

      final record =
          SessionRecord.fromJson(jsonDecode(line) as Map<String, Object?>)
              as MessageRecord;

      expect(record.command?.source, 'skill');
      expect(record.command?.name, 'release-notes');
      expect(record.command?.args, 'v1.2 v1.3');
      expect(jsonEncode(record.toJson()), jsonEncode(jsonDecode(line)));
    });

    test('displayText: /skill:<name> <args>, and /skill:<name> for empty '
        'args; templates keep /<name>', () {
      expect(
        const CommandRef(
          source: 'skill',
          name: 'release-notes',
          args: 'v1.2 v1.3',
        ).displayText,
        '/skill:release-notes v1.2 v1.3',
      );
      expect(
        const CommandRef(source: 'skill', name: 'notes', args: '').displayText,
        '/skill:notes',
      );
      expect(
        const CommandRef(
          source: 'template',
          name: 'review',
          args: 'lib',
        ).displayText,
        '/review lib',
      );
    });

    test('the model context holds the wrapped text only, never the '
        'command field', () {
      final s = snapshot([
        user('u1', null, text: 'WRAPPED BLOCK', command: skillCommand),
      ]);

      final json = jsonEncode(buildLlmContext(s).messages.single.toJson());

      expect(json, contains('WRAPPED BLOCK'));
      expect(json, isNot(contains('command')));
      expect(json, isNot(contains('release-notes')));
    });
  });

  group('the title (scenario "Заголовок сессии из команды")', () {
    test('/skill:<name> <args>, not the wrapper of the skill', () {
      final s = snapshot([
        user('u1', null, text: 'WRAPPED BLOCK', command: skillCommand),
      ]);

      expect(summarize(s).title, '/skill:release-notes v1.2 v1.3');
    });

    test('/skill:<name> for empty args', () {
      final s = snapshot([
        user(
          'u1',
          null,
          text: 'WRAPPED BLOCK',
          command: const {'source': 'skill', 'name': 'notes', 'args': ''},
        ),
      ]);

      expect(summarize(s).title, '/skill:notes');
    });
  });

  group('the replay', () {
    String firstText(List<AgentEvent> events) =>
        ((events.first as MessageStarted).message.content.first as TextContent)
            .text;

    test('shows /skill:<name> <args> instead of the wrapper', () {
      final s = snapshot([
        user('u1', null, text: 'WRAPPED BLOCK', command: skillCommand),
      ]);

      final events = buildReplay(s);

      expect(firstText(events), '/skill:release-notes v1.2 v1.3');
      final all = events
          .whereType<MessageEnded>()
          .map((e) => jsonEncode(e.message.toJson()))
          .join();
      expect(all, isNot(contains('WRAPPED')));
    });

    test('keeps the other blocks after the command text', () {
      final line = jsonEncode({
        'type': 'message',
        'id': 'u1',
        'parentId': null,
        'timestamp': at,
        'command': skillCommand,
        'message': {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'WRAPPED'},
            {'type': 'image', 'data': 'AAAA', 'mimeType': 'image/png'},
          ],
          'timestamp': at,
        },
      });

      final content = (buildReplay(snapshot([line])).first as MessageStarted)
          .message
          .content;

      expect(content, hasLength(2));
      expect(
        (content.first as TextContent).text,
        '/skill:release-notes v1.2 v1.3',
      );
      expect(content.last, isA<ImageContent>());
    });

    test('an unknown source still shows the message text', () {
      final s = snapshot([
        user(
          'u1',
          null,
          text: 'PLUGIN TEXT',
          command: const {'source': 'plugin', 'name': 'x', 'args': ''},
        ),
      ]);

      expect(firstText(buildReplay(s)), 'PLUGIN TEXT');
    });
  });

  group('through the session (scenario "Команда навыка в журнале")', () {
    SkillCommandRig newRig() => SkillCommandRig(
      skills: [
        validSkill(
          'release-notes',
          body: r'Collect the changes between $1 and $2.',
        ),
      ],
    );

    test('the user record carries command {skill, name, args}; the message '
        'is the wrapped skill', () async {
      final rig = newRig();
      await rig.open();

      await rig.ask('/skill:release-notes v1.2 v1.3');

      final record = rig.journal().singleWhere((r) => r.containsKey('command'));
      expect(record['command'], skillCommand);
      expect(
        jsonEncode(record['message']),
        contains('Collect the changes between v1.2 and v1.3.'),
      );
    });

    test('after loadSession: the replay shows /skill:… and not the '
        'wrapper', () async {
      final rig = newRig();
      final created = await rig.open();
      await rig.ask('/skill:release-notes v1.2 v1.3');
      await created.close();

      final loaded = await rig.core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
        cwd: '/work/a',
      );
      final replayed = loaded
          .replay()
          .whereType<MessageEnded>()
          .map((e) => e.message)
          .whereType<UserMessage>()
          .single;

      expect(
        replayed.content.whereType<TextContent>().map((b) => b.text).join(),
        '/skill:release-notes v1.2 v1.3',
      );
      expect(jsonEncode(replayed.toJson()), isNot(contains('<skill name=')));
    });

    test('the automatic title is the typed command', () async {
      final rig = newRig();
      final session = await rig.open();
      final events = <AgentEvent>[];
      session.events.listen(events.add);

      await rig.ask('/skill:release-notes v1.2 v1.3');
      await pumpEventQueue();

      expect(
        events.whereType<SessionTitleChanged>().single.title,
        '/skill:release-notes v1.2 v1.3',
      );
    });
  });
}
