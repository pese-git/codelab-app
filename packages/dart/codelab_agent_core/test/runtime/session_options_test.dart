import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../support/models.dart';

/// Каталог моделей, модель и усилие рассуждения сессии, хуки хоста у
/// загруженной сессии (задача 6.1; agent-runtime «AgentRuntime и
/// AgentSession», «Минимальная сборка buildAgentCore»; design.md change
/// `add-dart-agent-acp-server`, D3, D4).
void main() {
  final thinker = ModelRef(
    provider: 'test',
    id: 'thinker',
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse('http://localhost:8080/v1'),
    contextWindow: 64000,
    maxOutputTokens: 8192,
    supportsReasoning: true,
  );

  List<Map<String, Object?>> lines(SessionStore store, SessionId id) => [
    for (final line in const LineSplitter().convert(
      (store as MemorySessionStore).textOf(id)!,
    ))
      jsonDecode(line) as Map<String, Object?>,
  ];

  CoreHarness harness(
    List<Map<String, Object?>> steps, {
    SessionStore? store,
    ModelCatalog? models,
    PermissionGate? gate,
  }) => CoreHarness.build(
    baseEnv: MemoryExecutionEnv(cwd: '/proj'),
    narrow: noExec,
    gate: gate ?? FakeGate(),
    sessions: store ?? MemorySessionStore(),
    models: models,
    steps: steps,
  );

  test('without services.models the catalog is the default model', () {
    final h = harness(const []);

    expect(
      [for (final m in h.core.runtime.models.models) m.id.value],
      ['test/model-1'],
    );
  });

  test('FixedModelCatalog gives effort only to a model with reasoning', () {
    final catalog = FixedModelCatalog([testModel, thinker]);

    expect(
      [for (final m in catalog.models) m.id.value],
      ['test/model-1', 'test/thinker'],
    );
    expect(
      catalog
          .resolve(const ModelId('test/thinker'), effort: ReasoningEffort.high)
          ?.reasoningEffort,
      ReasoningEffort.high,
    );
    expect(
      catalog
          .resolve(const ModelId('test/model-1'), effort: ReasoningEffort.high)
          ?.reasoningEffort,
      isNull,
    );
    expect(catalog.resolve(const ModelId('test/none')), isNull);
  });

  test('setModel writes model_change and the next turn uses it', () async {
    final h = harness([
      textStep('one'),
    ], models: FixedModelCatalog([testModel, thinker]));
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );

    await session.setModel(const ModelId('test/thinker'));
    await session.prompt(const [TextContent('hi')]);

    expect(session.model.id, 'thinker');
    expect(session.effort, ReasoningEffort.medium);
    expect(h.requestedModels.single.id, 'thinker');
    expect(h.requestedModels.single.reasoningEffort, ReasoningEffort.medium);
    expect(
      lines(h.sessions, session.id).where((l) => l['type'] == 'model_change'),
      hasLength(2),
    );
    expect(
      lines(
        h.sessions,
        session.id,
      ).lastWhere((l) => l['type'] == 'model_change')['modelId'],
      'thinker',
    );
  });

  test('a model outside the catalog is an ArgumentError', () async {
    final h = harness(const []);
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );

    expect(
      () => session.setModel(const ModelId('test/none')),
      throwsArgumentError,
    );
  });

  test('setEffort writes config_change; only reasoning gets it', () async {
    final h = harness([
      textStep('one'),
      textStep('two'),
    ], models: FixedModelCatalog([testModel, thinker]));
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );

    await session.setEffort(ReasoningEffort.high);
    await session.prompt(const [TextContent('plain')]);
    await session.setModel(const ModelId('test/thinker'));
    await session.prompt(const [TextContent('thinking')]);

    expect(session.effort, ReasoningEffort.high);
    expect(
      [for (final m in h.requestedModels) m.reasoningEffort],
      [null, ReasoningEffort.high],
    );
    expect(
      lines(h.sessions, session.id).where((l) => l['type'] == 'config_change'),
      [
        {
          'type': 'config_change',
          'id': isA<String>(),
          'parentId': isA<String>(),
          'timestamp': isA<String>(),
          'optionId': 'effort',
          'value': 'high',
        },
      ],
    );
  });

  test(
    'loadSession restores the model of the catalog and the effort',
    () async {
      final store = MemorySessionStore();
      final catalog = FixedModelCatalog([testModel, thinker]);
      final first = harness(const [], store: store, models: catalog);
      final created = await first.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await created.setModel(const ModelId('test/thinker'));
      await created.setEffort(ReasoningEffort.low);
      await first.core.runtime.dispose();
      final before = lines(store, created.id).length;

      final second = harness(
        [textStep('again')],
        store: store,
        models: catalog,
      );
      final loaded = await second.core.runtime.loadSession(
        created.id,
        const SessionHostPorts(),
      );
      await loaded.prompt(const [TextContent('hi')]);

      expect(loaded.model.id, 'thinker');
      expect(loaded.effort, ReasoningEffort.low);
      expect(
        second.requestedModels.single.reasoningEffort,
        ReasoningEffort.low,
      );
      expect(
        lines(
          store,
          created.id,
        ).skip(before).where((l) => l['type'] == 'model_change'),
        isEmpty,
      );
      expect(second.logger.eventsOf('session.model.not_restored'), isEmpty);
    },
  );

  test('a journal model outside the catalog: stage 3 behaviour', () async {
    final store = MemorySessionStore();
    final first = harness(
      const [],
      store: store,
      models: FixedModelCatalog([testModel, thinker]),
    );
    final created = await first.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await created.setModel(const ModelId('test/thinker'));
    await first.core.runtime.dispose();

    final second = harness(const [], store: store);
    final loaded = await second.core.runtime.loadSession(
      created.id,
      const SessionHostPorts(),
    );

    expect(loaded.model.id, 'model-1');
    expect(second.logger.eventsOf('session.model.not_restored'), hasLength(1));
    expect(
      lines(
        store,
        created.id,
      ).lastWhere((l) => l['type'] == 'model_change')['modelId'],
      'model-1',
    );
  });

  test(
    'extraBeforeToolCall of a loaded session runs after the policy',
    () async {
      final store = MemorySessionStore();
      final first = harness(const [], store: store);
      final created = await first.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await first.core.runtime.dispose();
      final seen = <String>[];

      final second = harness(
        [
          callStep('w1', 'write', {'path': 'a.txt', 'content': 'a'}),
          callStep('r1', 'read', {'path': 'a.txt'}),
          textStep('done'),
        ],
        store: store,
        gate: FakeGate(
          (request) => request.toolCallId == 'w1'
              ? PermissionDecision.rejectOnce
              : PermissionDecision.allowOnce,
        ),
      );
      final loaded = await second.core.runtime.loadSession(
        created.id,
        SessionHostPorts(
          extraBeforeToolCall: [
            (call, args, ctx) async {
              seen.add(call.id);
              return null;
            },
          ],
        ),
      );
      await loaded.prompt(const [TextContent('write then read')]);

      // Отклонённый политикой вызов до хука хоста не доходит.
      expect(seen, ['r1']);
    },
  );

  // §13.5, шаг 2: рабочую папку задаёт клиент; смена пишется в журнал.
  test('loadSession with another cwd writes codelab.cwd_changed', () async {
    final store = MemorySessionStore();
    final first = harness(const [], store: store);
    final created = await first.core.runtime.createSession(
      SessionSpec(cwd: '/proj'),
    );
    await first.core.runtime.dispose();

    final second = harness(const [], store: store);
    await second.core.runtime.loadSession(
      created.id,
      const SessionHostPorts(),
      cwd: '/moved',
    );
    final changed = lines(store, created.id).last;

    expect(changed['type'], 'custom');
    expect(changed['customType'], 'codelab.cwd_changed');
    expect(changed['data'], {'from': '/proj', 'to': '/moved'});
  });
}
