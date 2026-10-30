import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/projections.dart';
import 'package:test/test.dart';

import 'journal_lines.dart';

/// Поле записи `command` (agent-sessions «Поле записи command»;
/// agent-slash-commands «Исходный текст команды в журнале»; §8.2.3; design.md
/// change `add-agent-project-files`, D8).
void main() {
  const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

  SessionSnapshot snapshot(List<String> lines) =>
      parseSessionLines(journal([header(), ...lines]), id: id).snapshot;

  Map<String, Object?> decode(String line) =>
      jsonDecode(line) as Map<String, Object?>;

  const template = {'source': 'template', 'name': 'review', 'args': 'lib'};

  test('a record with command reads into a typed field and writes back', () {
    final line = user('u1', null, text: 'Review lib', command: template);

    final record = SessionRecord.fromJson(decode(line)) as MessageRecord;

    expect(record.command?.source, 'template');
    expect(record.command?.name, 'review');
    expect(record.command?.args, 'lib');
    expect(jsonEncode(record.toJson()), jsonEncode(decode(line)));
  });

  test('a record without command reads as before', () {
    final record =
        SessionRecord.fromJson(decode(user('u1', null))) as MessageRecord;

    expect(record.command, isNull);
    expect(record.toJson().containsKey('command'), isFalse);
  });

  test('an unknown source and unknown fields survive a round trip', () {
    const command = {
      'source': 'plugin',
      'name': 'x',
      'args': 'a b',
      'plugin': {'id': 7},
    };
    final line = user('u1', null, command: command);

    final record = SessionRecord.fromJson(decode(line)) as MessageRecord;

    expect(record.command?.source, 'plugin');
    expect(record.toJson()['command'], command);
  });

  test('a malformed command is kept in extra and does not fail', () {
    final line = user('u1', null, command: 'oops');

    final record = SessionRecord.fromJson(decode(line)) as MessageRecord;

    expect(record.command, isNull);
    expect(record.toJson()['command'], 'oops');
  });

  test('the model context holds the expanded text only', () {
    final s = snapshot([
      user('u1', null, text: 'Review lib focusing', command: template),
    ]);

    final messages = buildLlmContext(s).messages;

    final json = jsonEncode(messages.single.toJson());
    expect(json, contains('Review lib focusing'));
    expect(json, isNot(contains('command')));
    expect(json, isNot(contains('"template"')));
  });

  group('title', () {
    test('a template command gives /name args, not the expanded text', () {
      final s = snapshot([
        user('u1', null, text: 'EXPANDED BODY', command: template),
      ]);

      expect(summarize(s).title, '/review lib');
    });

    test('an unknown source gives the message text', () {
      final s = snapshot([
        user(
          'u1',
          null,
          text: 'PLUGIN TEXT',
          command: const {'source': 'plugin', 'name': 'x', 'args': ''},
        ),
      ]);

      expect(summarize(s).title, 'PLUGIN TEXT');
    });
  });

  group('replay', () {
    String firstText(List<AgentEvent> events) =>
        ((events.first as MessageStarted).message.content.first as TextContent)
            .text;

    test('shows /name args instead of the expanded text', () {
      final s = snapshot([
        user('u1', null, text: 'EXPANDED BODY', command: template),
      ]);

      final events = buildReplay(s);

      expect(firstText(events), '/review lib');
      expect(
        jsonEncode([for (final e in events) e.runtimeType.toString()]),
        isNot(contains('EXPANDED')),
      );
      final all = events
          .whereType<MessageEnded>()
          .map((e) => jsonEncode(e.message.toJson()))
          .join();
      expect(all, isNot(contains('EXPANDED')));
    });

    test('shows only /name when args are empty', () {
      final s = snapshot([
        user(
          'u1',
          null,
          text: 'BODY',
          command: const {'source': 'template', 'name': 'bare', 'args': ''},
        ),
      ]);

      expect(firstText(buildReplay(s)), '/bare');
    });

    test('keeps the other blocks after the command text', () {
      final line = jsonEncode({
        'type': 'message',
        'id': 'u1',
        'parentId': null,
        'timestamp': at,
        'command': template,
        'message': {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'BODY'},
            {'type': 'image', 'data': 'AAAA', 'mimeType': 'image/png'},
          ],
          'timestamp': at,
        },
      });

      final events = buildReplay(snapshot([line]));

      final content = (events.first as MessageStarted).message.content;
      expect(content, hasLength(2));
      expect((content.first as TextContent).text, '/review lib');
      expect(content.last, isA<ImageContent>());
    });

    test('an unknown source shows the message text', () {
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
}
