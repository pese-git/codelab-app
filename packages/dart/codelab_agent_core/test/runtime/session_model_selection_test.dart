import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';

/// Выбор модели новой сессии и порт последней модели (agent-runtime «Модель
/// новой сессии» и «Последняя выбранная модель»; design.md change
/// `optional-default-model`, D5, D6). Красные тесты задачи 2.1: на фейке
/// `LastModelStore`, без файлов.
void main() {
  ModelRef model(String provider, String id) => ModelRef(
    provider: provider,
    id: id,
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse('http://localhost:8080/v1'),
    contextWindow: 32000,
    maxOutputTokens: 4096,
  );

  final ax = model('a', 'x');
  final by = model('b', 'y');
  final catalog = FixedModelCatalog([ax, by]);

  List<Map<String, Object?>> lines(SessionStore store, SessionId id) => [
    for (final line in const LineSplitter().convert(
      (store as MemorySessionStore).textOf(id)!,
    ))
      jsonDecode(line) as Map<String, Object?>,
  ];

  CoreHarness harness({
    DefaultModelSource source = DefaultModelSource.firstProvider,
    ModelRef? defaultModel,
    LastModelStore? lastModel,
    SessionStore? store,
    ProjectFilesSource? projectFiles,
  }) => CoreHarness.build(
    baseEnv: MemoryExecutionEnv(cwd: '/proj'),
    narrow: noExec,
    gate: FakeGate(),
    sessions: store ?? MemorySessionStore(),
    models: catalog,
    defaultModel: defaultModel ?? ax,
    defaultModelSource: source,
    lastModel: lastModel,
    projectFiles: projectFiles,
    steps: const [],
  );

  Future<AgentSession> create(CoreHarness h, {ModelRef? explicit}) =>
      h.core.runtime.createSession(SessionSpec(cwd: '/proj', model: explicit));

  group('the model of a new session (D5)', () {
    test(
      'an explicit config model wins over the last one, the port is not '
      'even read (scenario "Явная модель конфига побеждает последнюю")',
      () async {
        final last = _FakeLastModel(stored: const ModelId('b/y'));
        final h = harness(source: DefaultModelSource.config, lastModel: last);

        final session = await create(h);

        expect(session.model.provider, 'a');
        expect(session.model.id, 'x');
        final event = h.logger.eventsOf('session.model.selected').single;
        expect(event.level, LogLevel.info);
        expect(event.fields['source'], 'config');
        expect(event.fields['model'], 'a/x');
        expect(event.fields['session_id'], session.id.value);
        expect(last.reads, 0);
        expect(last.writes, isEmpty);
      },
    );

    test('the last model wins over the first provider; the first journal '
        'record is model_change b/y (scenario "Последняя модель побеждает '
        'первого провайдера")', () async {
      final last = _FakeLastModel(stored: const ModelId('b/y'));
      final h = harness(lastModel: last);

      final session = await create(h);

      expect(session.model.provider, 'b');
      expect(session.model.id, 'y');
      final records = lines(h.sessions, session.id);
      expect(records[1]['type'], 'model_change');
      expect(records[1]['provider'], 'b');
      expect(records[1]['modelId'], 'y');
      // Опция `model` для клиента строится из каталога рантайма; выбранная
      // модель — его элемент (currentValue ACP берётся из `session.model`).
      expect(
        [for (final m in h.core.runtime.models.models) m.id.value],
        ['a/x', 'b/y'],
      );
      final event = h.logger.eventsOf('session.model.selected').single;
      expect(event.fields['source'], 'last-used');
      expect(event.fields['model'], 'b/y');
    });

    test('the last model is not in the catalog: first provider, no write '
        '(scenario "Последней модели нет в каталоге")', () async {
      final last = _FakeLastModel(stored: const ModelId('gone/z'));
      final h = harness(lastModel: last);

      final session = await create(h);

      expect(session.model.id, 'x');
      expect(
        h.logger.eventsOf('session.model.selected').single.fields['source'],
        'first-provider',
      );
      expect(last.writes, isEmpty);
    });

    test('without the port the step is skipped', () async {
      final h = harness();

      final session = await create(h);

      expect(session.model.id, 'x');
      expect(
        h.logger.eventsOf('session.model.selected').single.fields['source'],
        'first-provider',
      );
    });

    test('a read failure is a fallback and model.last_used.ignored, not an '
        'error (scenario "Сбой чтения последней модели")', () async {
      final last = _FakeLastModel(
        readError: StateError('secret path /home/u/sk-test-leak-0123456789'),
      );
      final h = harness(lastModel: last);

      final session = await create(h);

      expect(session.model.id, 'x');
      final ignored = h.logger.eventsOf('model.last_used.ignored').single;
      expect(ignored.fields['reason'], 'StateError');
      expect(ignored.fields.toString(), isNot(contains('sk-test-leak')));
      expect(
        h.logger.eventsOf('session.model.selected').single.fields['source'],
        'first-provider',
      );
    });

    test('spec.model is used as before: no selection event', () async {
      final last = _FakeLastModel(stored: const ModelId('a/x'));
      final h = harness(lastModel: last);

      final session = await create(h, explicit: by);

      expect(session.model.id, 'y');
      expect(h.logger.eventsOf('session.model.selected'), isEmpty);
      expect(last.reads, 0);
    });

    test('loadSession without a journal model takes CoreConfig.defaultModel '
        'and does not read the last one (D5)', () async {
      final store = MemorySessionStore();
      // Журнал без записи модели: только заголовок сессии.
      final id = const SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0A');
      await store.create(
        SessionHeader(
          id: id,
          cwd: '/proj',
          created: DateTime.utc(2026),
          agent: const AgentInfo(name: 'test', version: '0'),
        ),
      );
      final last = _FakeLastModel(stored: const ModelId('b/y'));
      final h = harness(store: store, lastModel: last);

      final loaded = await h.core.runtime.loadSession(
        id,
        const SessionHostPorts(),
      );

      expect(loaded.model.provider, 'a');
      expect(loaded.model.id, 'x');
      expect(last.reads, 0);
      expect(last.writes, isEmpty);
      expect(h.logger.eventsOf('session.model.selected'), isEmpty);
    });
  });

  group('writing the last model (D6)', () {
    test('automatic selection writes nothing (scenario "Автоматический '
        'выбор не пишет файл")', () async {
      final last = _FakeLastModel(stored: const ModelId('b/y'));
      final h = harness(lastModel: last);

      await create(h);
      await create(h);

      expect(last.writes, isEmpty);
    });

    test('setModel writes after model_change of the same operation', () async {
      final last = _FakeLastModel();
      final h = harness(lastModel: last);
      final session = await create(h);
      last.onWrite = () {
        // На момент записи `model_change` уже в журнале (D6: после записи
        // журнала внутри `_serial`).
        last.journalAtWrite = (h.sessions as MemorySessionStore).textOf(
          session.id,
        );
      };

      await session.setModel(const ModelId('b/y'));

      expect(last.writes, [const ModelId('b/y')]);
      expect(last.journalAtWrite, contains('"modelId":"y"'));
      expect(
        lines(h.sessions, session.id).where((l) => l['type'] == 'model_change'),
        hasLength(2),
      );
    });

    test('createSession with spec.model writes it', () async {
      final last = _FakeLastModel();
      final h = harness(lastModel: last);

      await create(h, explicit: by);

      expect(last.writes, [const ModelId('b/y')]);
    });

    test('loadSession(model:) writes it', () async {
      final store = MemorySessionStore();
      final first = harness(store: store);
      final created = await create(first);
      await first.core.runtime.dispose();
      final last = _FakeLastModel();
      final h = harness(store: store, lastModel: last);

      await h.core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
        model: by,
      );

      expect(last.writes, [const ModelId('b/y')]);
    });

    test('restoring the model from the journal does not write', () async {
      final store = MemorySessionStore();
      final first = harness(store: store);
      final created = await create(first, explicit: by);
      await first.core.runtime.dispose();
      final last = _FakeLastModel();
      final h = harness(store: store, lastModel: last);

      final loaded = await h.core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
      );

      expect(loaded.model.id, 'y');
      expect(last.writes, isEmpty);
    });

    test('changing the agent does not write, even when the agent has a '
        'model', () async {
      final last = _FakeLastModel();
      final h = harness(
        lastModel: last,
        projectFiles: _AgentPort([_agentFile('reviewer', model: 'b/y')]),
      );
      final session = await create(h);

      await session.setAgent('reviewer');

      expect(session.model.id, 'y');
      expect(last.writes, isEmpty);
    });

    test('a write failure does not break setModel (scenario "Сбой записи '
        'не ломает смену модели")', () async {
      final last = _FakeLastModel(
        writeError: StateError('read-only /home/u/sk-test-leak-0123456789'),
      );
      final h = harness(lastModel: last);
      final session = await create(h);

      final result = await session.setModel(const ModelId('b/y'));

      expect(result.model?.id, 'y');
      expect(session.model.id, 'y');
      expect(
        lines(
          h.sessions,
          session.id,
        ).where((l) => l['type'] == 'model_change').last['modelId'],
        'y',
      );
      final failed = h.logger.eventsOf('model.last_used.write_failed').single;
      expect(failed.level, LogLevel.warning);
      expect(failed.fields['reason'], 'StateError');
      expect(failed.fields.toString(), isNot(contains('sk-test-leak')));
    });
  });

  group('selectSessionModel (D5)', () {
    CoreConfig config(DefaultModelSource source) =>
        CoreConfig(defaultModel: ax, defaultModelSource: source);

    test('config source ignores the last model', () {
      final (picked, source) = selectSessionModel(
        config(DefaultModelSource.config),
        const ModelId('b/y'),
        catalog,
      );

      expect(picked.id, 'x');
      expect(source, DefaultModelSource.config);
    });

    test('the last model of the catalog wins for firstProvider', () {
      final (picked, source) = selectSessionModel(
        config(DefaultModelSource.firstProvider),
        const ModelId('b/y'),
        catalog,
      );

      expect(picked.provider, 'b');
      expect(source, DefaultModelSource.lastUsed);
    });

    test('a missing or unknown last model gives the first provider', () {
      for (final last in <ModelId?>[null, const ModelId('gone/z')]) {
        final (picked, source) = selectSessionModel(
          config(DefaultModelSource.firstProvider),
          last,
          catalog,
        );

        expect(picked.id, 'x');
        expect(source, DefaultModelSource.firstProvider);
      }
    });
  });
}

/// Фейк порта: считает чтения, запоминает записи по порядку, умеет падать.
final class _FakeLastModel implements LastModelStore {
  _FakeLastModel({this.stored, this.readError, this.writeError});

  /// Что вернёт `read()`.
  final ModelId? stored;
  final Object? readError;
  final Object? writeError;

  var reads = 0;
  final writes = <ModelId>[];
  void Function()? onWrite;
  String? journalAtWrite;

  @override
  Future<ModelId?> read() async {
    reads++;
    if (readError case final error?) {
      throw error;
    }
    return stored;
  }

  @override
  Future<void> write(ModelId model) async {
    onWrite?.call();
    if (writeError case final error?) {
      throw error;
    }
    writes.add(model);
  }
}

MarkdownFile _agentFile(String name, {required String model}) {
  const dir = '/home/.codelab/agents';
  return MarkdownFile(
    path: '$dir/$name.md',
    scope: ExtensionScope.user,
    body: 'Review carefully.',
    bodyLine: 6,
    frontmatter: ConfigTree(
      kind: ConfigLayerKind.user,
      source: '$dir/$name.md',
      values: {'name': name, 'description': 'The $name agent', 'model': model},
    ),
  );
}

final class _AgentPort implements ProjectFilesSource {
  _AgentPort(this.agents);

  final List<MarkdownFile> agents;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async =>
      ProjectFiles(agents: agents);
}
