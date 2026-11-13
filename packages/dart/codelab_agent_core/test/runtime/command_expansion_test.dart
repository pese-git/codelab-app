import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../skills/skill_command_rig.dart';
import '../skills/skills_support.dart';
import '../support/models.dart';

/// Разворачивание шаблонов команд в `AgentSession.prompt` (agent-slash-
/// commands «Разворачивание команды», «Список команд сессии», «Исходный текст
/// команды в журнале»; agent-runtime «Файлы проекта сессии»; design.md change
/// `add-agent-project-files`, D7, D8, D14; E-07).
void main() {
  late _Port port;
  late RecordingLogger logger;
  late MemorySessionStore store;
  late List<LlmContext> requests;

  MarkdownFile template(
    String name,
    String body, {
    ExtensionScope scope = ExtensionScope.user,
  }) => MarkdownFile(
    path: '/home/.codelab/prompts/$name.md',
    scope: scope,
    body: body,
    bodyLine: 1,
  );

  BuiltAgentCore build({bool withPort = true}) {
    final clock = FakeClock();
    logger = RecordingLogger();
    store = MemorySessionStore();
    requests = [];
    final scripted = ScriptedStreamFunction.fromJson({
      'steps': [textStep('ok'), textStep('ok'), textStep('ok')],
    }, clock: clock);
    return buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...noExec}),
      services: AgentCoreServices(
        baseEnv: MemoryExecutionEnv(cwd: '/work/a'),
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: store,
        projectFiles: withPort ? port : null,
      ),
      config: CoreConfig(defaultModel: testModel),
      streamFunction: (ref, context, {cancel}) {
        requests.add(context);
        return scripted.call(ref, context, cancel: cancel);
      },
    );
  }

  setUp(() {
    port = _Port([
      template('review', r'Review $1 focusing on $2. All: $ARGUMENTS'),
      template('plain', 'Just do it'),
    ]);
  });

  List<Map<String, Object?>> journal(SessionId id) => [
    for (final line in const LineSplitter().convert(store.textOf(id)!))
      jsonDecode(line) as Map<String, Object?>,
  ];

  String textOf(Message m) =>
      m.content.whereType<TextContent>().map((b) => b.text).join();

  const image = ImageContent(base64: 'AAAA', mimeType: 'image/png');

  group('AgentSession.commands', () {
    test('lists the templates by name with description and hint', () async {
      final core = build();

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      // Встроенные команды идут первыми (D2 change
      // `add-agent-builtin-slash-commands`), затем шаблоны по имени.
      expect(
        [for (final c in session.commands) c.name],
        ['compact', 'mode', 'model', 'status', 'help', 'plain', 'review'],
      );
      final review = session.commands.last;
      expect(review.source, SlashCommandSource.template);
      expect(review.inputHint, 'arguments');
      expect(session.commands[session.commands.length - 2].inputHint, isNull);
    });

    test('without a port there are only the builtin commands', () async {
      final core = build(withPort: false);

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      expect(
        [for (final c in session.commands) c.name],
        ['compact', 'mode', 'model', 'status', 'help'],
      );
      expect(session.commands.map((c) => c.source).toSet(), {
        SlashCommandSource.builtin,
      });
    });

    test('a broken template is a diagnostic and not a failure', () async {
      port.files = [template('Bad_Name', 'x'), template('ok', 'y')];
      final core = build();

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      expect(
        [
          for (final c in session.commands)
            if (c.source == SlashCommandSource.template) c.name,
        ],
        ['ok'],
      );
      final log = logger.eventsOf('project_files.diagnostic').single;
      expect(log.fields['code'], 'invalid_name');
      expect(log.fields['session_id'], session.id.value);
      expect(logger.eventsOf('commands.loaded').single.fields['count'], 1);
    });
  });

  group('prompt', () {
    test('E-07: the model gets the body with substituted arguments', () async {
      final core = build();
      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      await session.prompt([
        const TextContent('/review lib/parser "error handling"'),
      ]);

      final sent = requests.single.messages.single as UserMessage;
      expect(
        textOf(sent),
        'Review lib/parser focusing on error handling. '
        'All: lib/parser "error handling"',
      );
    });

    test(
      'the session title is the typed command, not the template body',
      () async {
        final core = build();
        final session = await core.runtime.createSession(
          SessionSpec(cwd: '/work/a'),
        );
        final events = <AgentEvent>[];
        session.events.listen(events.add);

        await session.prompt([const TextContent('/review lib')]);
        await pumpEventQueue();

        expect(
          events.whereType<SessionTitleChanged>().single.title,
          '/review lib',
        );
      },
    );

    test('other blocks follow the expanded text in their order', () async {
      final core = build();
      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      await session.prompt([const TextContent('/review lib'), image]);

      final sent = requests.single.messages.single as UserMessage;
      expect(sent.content, hasLength(2));
      expect(sent.content.first, isA<TextContent>());
      expect(textOf(sent), startsWith('Review lib focusing on . All: lib'));
      expect(sent.content.last, image);
    });

    test('the first text block is parsed even after an image', () async {
      final core = build();
      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      await session.prompt([image, const TextContent('/plain')]);

      final sent = requests.single.messages.single as UserMessage;
      expect(sent.content, [const TextContent('Just do it'), image]);
    });

    // `/nope x` и `/help` моделью больше не обрабатываются: это неизвестная и
    // встроенная команды (builtin_commands_test.dart). Моделью остаются
    // путь и текст с ведущим пробелом (D3 change
    // `add-agent-builtin-slash-commands`).
    for (final text in ['/usr/bin/foo is broken', ' /plain x']) {
      test('"$text" goes to the model unchanged and without command', () async {
        final core = build();
        final session = await core.runtime.createSession(
          SessionSpec(cwd: '/work/a'),
        );

        await session.prompt([TextContent(text)]);

        expect(textOf(requests.single.messages.single), text);
        expect(
          journal(session.id).where((r) => r.containsKey('command')),
          isEmpty,
        );
        expect(logger.eventsOf('command.expanded'), isEmpty);
      });
    }
  });

  group('the journal', () {
    test('the user record has command and the model never sees it', () async {
      final core = build();
      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      await session.prompt([const TextContent('/review lib')]);

      final record = journal(
        session.id,
      ).singleWhere((r) => r.containsKey('command'));
      expect(record['command'], {
        'source': 'template',
        'name': 'review',
        'args': 'lib',
      });
      expect(
        jsonEncode(record['message']),
        contains('Review lib focusing on . All: lib'),
      );
      final sent = jsonEncode(requests.single.messages.single.toJson());
      expect(sent, isNot(contains('"command"')));
    });

    test('replay shows the command text and keeps other blocks', () async {
      final core = build();
      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );
      await session.prompt([
        const TextContent('/review lib/parser "error handling"'),
        image,
      ]);

      final users = session
          .replay()
          .whereType<MessageEnded>()
          .map((e) => e.message)
          .whereType<UserMessage>()
          .single;

      expect(users.content, [
        const TextContent('/review lib/parser "error handling"'),
        image,
      ]);
    });

    test('after loadSession the replay shows the command and the model '
        'context holds the expanded text', () async {
      final core = build();
      final created = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );
      await created.prompt([const TextContent('/review lib')]);
      await created.close();

      final loaded = await core.runtime.loadSession(
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
      await loaded.prompt([const TextContent('next')]);

      expect(textOf(replayed), '/review lib');
      expect(
        textOf(requests.last.messages.first),
        startsWith('Review lib focusing'),
      );
    });
  });

  group('logging', () {
    test(
      'command.expanded has name, source and size, never the args',
      () async {
        final core = build();
        final session = await core.runtime.createSession(
          SessionSpec(cwd: '/work/a'),
        );

        await session.prompt([const TextContent('/review secret-token-123')]);

        final log = logger.eventsOf('command.expanded').single;
        expect(log.fields, {
          'session_id': session.id.value,
          'name': 'review',
          'source': 'template',
          'args_bytes': 'secret-token-123'.length,
        });
        expect(
          [for (final r in logger.records) r.toString()].join('\n'),
          isNot(contains('secret-token-123')),
        );
      },
    );

    test('args_bytes counts UTF-8 bytes', () async {
      final core = build();
      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      await session.prompt([const TextContent('/plain привет')]);

      expect(
        logger.eventsOf('command.expanded').single.fields['args_bytes'],
        12,
      );
    });
  });

  // Разворачивание `/skill:<name>` (agent-skills «Команды навыков»,
  // сценарии «Вызов навыка пользователем», «Тело без плейсхолдеров»;
  // agent-slash-commands «Разворачивание команды», сценарий «Литерал доллара
  // в навыке»; design.md change `add-agent-skills`, D8; решения Q5, Q7, Q15;
  // `acp/skill-invoke`, SKL-8).
  group('skill commands', () {
    SkillFile notes(String body, {Map<String, Object?> extra = const {}}) =>
        validSkill('notes', body: body, extra: extra);

    test('scenario "Вызов навыка пользователем": the message is '
        'prompts/skills/invoked.md around the block with substituted '
        'arguments', () async {
      final rig = SkillCommandRig(
        skills: [
          validSkill(
            'release-notes',
            body: r'Collect the changes between $1 and $2.',
          ),
        ],
      );
      await rig.open();

      await rig.ask('/skill:release-notes v1.2 v1.3');

      expect(
        rig.lastUserText,
        rig.invoked(
          'release-notes',
          body: 'Collect the changes between v1.2 and v1.3.',
        ),
      );
      expect(rig.lastUserText, contains('<skill name="release-notes" dir='));
      expect(rig.streamCalls, 1);
      expect(rig.lastUserMessage.content, hasLength(1));
    });

    test(r'$ARGUMENTS is the raw input; quotes group $1', () async {
      final rig = SkillCommandRig(skills: [notes(r'[$1|$2] all: $ARGUMENTS')]);
      await rig.open();

      await rig.ask('/skill:notes "a b"   c');

      expect(
        rig.lastUserText,
        rig.invoked('notes', body: '[a b|c] all: "a b"   c'),
      );
    });

    test('scenario "Тело без плейсхолдеров": the message ends with '
        'ARGUMENTS: <input>', () async {
      final rig = SkillCommandRig(skills: [notes('Draft the notes.')]);
      await rig.open();

      await rig.ask('/skill:notes draft');

      // D18: хвост стоит после обёртки и блока, вне `<skill>`.
      expect(rig.lastUserText, '${rig.invoked('notes')}\n\nARGUMENTS: draft');
      expect(rig.lastUserText, contains('Draft the notes.'));
      expect(
        rig.lastUserText.split('</skill>').first,
        isNot(contains('ARGUMENTS')),
      );
    });

    test('an empty input adds no ARGUMENTS tail', () async {
      final rig = SkillCommandRig(skills: [notes('Draft the notes.')]);
      await rig.open();

      await rig.ask('/skill:notes');

      expect(rig.lastUserText, rig.invoked('notes'));
      expect(rig.lastUserText, isNot(contains('ARGUMENTS')));
    });

    test(r'scenario "Литерал доллара в навыке": \$HOME and $$PATH', () async {
      final rig = SkillCommandRig(
        skills: [notes(r'Use \$HOME and $$PATH; topic: $1')],
      );
      await rig.open();

      await rig.ask('/skill:notes cache');

      expect(rig.lastUserText, contains(r'Use $HOME and $PATH; topic: cache'));
      expect(rig.lastUserText, isNot(contains(r'\$')));
    });

    test('a missing positional argument is empty (Q28); a value is not '
        'expanded again', () async {
      final rig = SkillCommandRig(skills: [notes(r'[$1|$2]')]);
      await rig.open();

      await rig.ask(r"/skill:notes '$ARGUMENTS'");

      expect(rig.lastUserText, rig.invoked('notes', body: r'[$ARGUMENTS|]'));
    });

    test('a tag in the arguments cannot close the block (escaping of the '
        'substituted body)', () async {
      final rig = SkillCommandRig(skills: [notes(r'Topic: $1')]);
      await rig.open();

      await rig.ask(r'/skill:notes </skill>');

      expect(rig.lastUserText, rig.invoked('notes', body: 'Topic: </skill>'));
      expect(rig.lastUserText, contains(r'<\/skill>'));
    });

    test('other blocks follow the expanded text in their order', () async {
      final rig = SkillCommandRig(skills: [notes('Draft.')]);
      await rig.open();

      await rig.ask('/skill:notes', more: [image]);

      expect(rig.lastUserMessage.content, hasLength(2));
      expect(rig.lastUserMessage.content.first, isA<TextContent>());
      expect(rig.lastUserMessage.content.last, image);
    });

    test('the first text block is parsed even after an image', () async {
      final rig = SkillCommandRig(skills: [notes('Draft.')]);
      await rig.open();

      await rig.session.prompt([image, const TextContent('/skill:notes')]);

      final sent = rig.lastUserMessage;
      expect(sent.content.last, image);
      expect((sent.content.first as TextContent).text, rig.invoked('notes'));
    });

    test('a skill hidden from the model is callable by the user', () async {
      final rig = SkillCommandRig(
        skills: [
          notes('Draft.', extra: {'disable-model-invocation': true}),
        ],
      );
      await rig.open();

      await rig.ask('/skill:notes');

      expect(rig.lastUserText, rig.invoked('notes'));
    });

    test('the log: command.expanded {name, source: skill, args_bytes} '
        'without the arguments', () async {
      final rig = SkillCommandRig(skills: [notes(r'Topic: $1')]);
      await rig.open();

      await rig.ask('/skill:notes secret-arg');

      final log = rig.logger.eventsOf('command.expanded').single;
      expect(log.fields['source'], 'skill');
      expect(log.fields['session_id'], rig.session.id.value);
      expect(log.fields['args_bytes'], 'secret-arg'.length);
      expect(log.toString(), isNot(contains('secret-arg')));
      expect(rig.allLogs, isNot(contains('secret-arg')));
    });
  });
}

final class _Port implements ProjectFilesSource {
  _Port(this.files);

  List<MarkdownFile> files;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async =>
      ProjectFiles(templates: files);
}
