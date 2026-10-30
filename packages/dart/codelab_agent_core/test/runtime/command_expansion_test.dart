import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
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

      expect([for (final c in session.commands) c.name], ['plain', 'review']);
      final review = session.commands.last;
      expect(review.source, SlashCommandSource.template);
      expect(review.inputHint, 'arguments');
      expect(session.commands.first.inputHint, isNull);
    });

    test('is empty without a port', () async {
      final core = build(withPort: false);

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      expect(session.commands, isEmpty);
    });

    test('a broken template is a diagnostic and not a failure', () async {
      port.files = [template('Bad_Name', 'x'), template('ok', 'y')];
      final core = build();

      final session = await core.runtime.createSession(
        SessionSpec(cwd: '/work/a'),
      );

      expect([for (final c in session.commands) c.name], ['ok']);
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

    for (final text in ['/nope x', '/usr/bin/foo is broken', '/help']) {
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
}

final class _Port implements ProjectFilesSource {
  _Port(this.files);

  List<MarkdownFile> files;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async =>
      ProjectFiles(templates: files);
}
