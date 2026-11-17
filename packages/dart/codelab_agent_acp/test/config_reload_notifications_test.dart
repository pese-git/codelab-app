import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcNotification;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// Уведомления после перезагрузки конфигурации (agent-acp-server «Уведомления
/// после перезагрузки конфигурации»; design.md change
/// `add-config-writer-and-reload`, D8; ACP-8).
///
/// Источник конфигурации здесь подставной: слои — изменяемая карта теста, а
/// `load()` — настоящий `CoreConfig.fromLayers`, как у файлового источника.
void main() {
  ServerHarness? h;
  tearDown(() async => h?.dispose());

  /// Две живые сессии соединения на каталоге `a/m1`, `a/m2`.
  Future<({_Source source, List<String> sessions})> ready({
    int sessions = 2,
  }) async {
    final source = _Source();
    final started = h = await ServerHarness.start(configSource: source);
    await started.initialize();
    return (
      source: source,
      sessions: [for (var i = 0; i < sessions; i++) await started.newSession()],
    );
  }

  List<Map<String, Object?>> configUpdates(Iterable<Object?> frames) => [
    for (final update in TestClient.updates(frames.cast()))
      if (update['sessionUpdate'] == 'config_option_update') update,
  ];

  List<String> modelValues(Map<String, Object?> update) => [
    for (final option in (update['configOptions']! as List).cast<Map>())
      if (option['id'] == 'model')
        for (final entry in (option['options']! as List).cast<Map>())
          entry['value']! as String,
  ];

  String currentModel(Map<String, Object?> update) => [
    for (final option in (update['configOptions']! as List).cast<Map>())
      if (option['id'] == 'model') option['currentValue']! as String,
  ].single;

  test('a changed model list gives each live session one '
      'config_option_update with the new model and the old current value '
      '(scenario "Список моделей изменился")', () async {
    final rig = await ready();
    rig.source.put('providers.a.models.m3.name', 'M3');

    final report = await h!.core.runtime.reloadConfig();
    await pumpEventQueue();

    expect(report.outcome, ConfigReloadOutcome.applied);
    final frames = await h!.client.drain();
    final updates = configUpdates(frames);
    expect(updates, hasLength(2), reason: 'one frame per session');
    final targets = {
      for (final frame in frames)
        if (frame is JsonRpcNotification)
          ((frame.params! as Map)['sessionId']): 1,
    };
    expect(targets.keys, unorderedEquals(rig.sessions));
    for (final update in updates) {
      expect(modelValues(update), ['a/m1', 'a/m2', 'a/m3']);
      expect(currentModel(update), 'a/m1');
    }
  });

  test('a failed reload sends not a single frame (scenario '
      '"Неудачная перезагрузка")', () async {
    final rig = await ready();
    rig.source.put('budget.max_steps', 0);

    final report = await h!.core.runtime.reloadConfig();
    await pumpEventQueue();

    expect(report.outcome, ConfigReloadOutcome.failed);
    expect(await h!.client.drain(), isEmpty);
  });

  test('a change without a model list effect sends no frame', () async {
    final rig = await ready(sessions: 1);
    rig.source.put('budget.max_steps', 15);

    await h!.core.runtime.reloadConfig();
    await pumpEventQueue();

    expect(await h!.client.drain(), isEmpty);
  });

  test('the model removed from the catalog stays the current value and '
      'an option of the session (scenario "Модель сессии удалена")', () async {
    final rig = await ready(sessions: 1);
    rig.source
      ..put('agent.default_model', 'a/m2')
      ..drop('providers.a.models.m1');

    await h!.core.runtime.reloadConfig();
    await pumpEventQueue();

    expect(
      [for (final m in h!.core.runtime.models.models) m.id.value],
      isNot(contains('a/m1')),
      reason: 'the catalog really lost the model of the session',
    );
    final updates = configUpdates(await h!.client.drain());
    expect(updates, hasLength(1));
    expect(currentModel(updates.single), 'a/m1');
    expect(modelValues(updates.single), contains('a/m1'));
    expect(modelValues(updates.single), contains('a/m2'));
  });
}

/// Подставной [ConfigSource]: изменяемая карта слоя пользователя.
final class _Source implements ConfigSource {
  _Source() {
    _initial = _build(null);
    expect(_initial.issues, isEmpty, reason: _initial.issues.join('\n'));
  }

  final Map<String, Object?> _user =
      _deep({
            'providers': {
              'a': {
                'kind': 'openai-compatible',
                'base_url': 'https://a.test/v1',
                'models': {
                  'm1': <String, Object?>{},
                  'm2': <String, Object?>{},
                },
              },
            },
            'agent': {'default_model': 'a/m1'},
            'budget': {'max_steps': 10},
          })!
          as Map<String, Object?>;
  late final ConfigLoadResult _initial;

  void put(String path, Object? value) {
    final names = path.split('.');
    var node = _user;
    for (final name in names.take(names.length - 1)) {
      node =
          node.putIfAbsent(name, () => <String, Object?>{})!
              as Map<String, Object?>;
    }
    node[names.last] = value;
  }

  void drop(String path) {
    final names = path.split('.');
    var node = _user;
    for (final name in names.take(names.length - 1)) {
      node = node[name]! as Map<String, Object?>;
    }
    node.remove(names.last);
  }

  ConfigLoadResult _build(List<String>? pinned) => CoreConfig.fromLayers(
    [
      ConfigTree(
        kind: ConfigLayerKind.user,
        source: '/home/u/.codelab/config.yaml',
        // Копия: снимок рантайма не должен ссылаться на правимую карту теста.
        values: _deep(_user)! as Map<String, Object?>,
      ),
    ],
    environment: const {},
    projectRoot: '/work/demo',
    pinnedTrustedProjects: pinned,
  );

  @override
  ConfigLoadResult get initial => _initial;

  @override
  Future<ConfigLoadResult> load({bool rebase = true}) async =>
      _build(_initial.config!.trustedProjects);

  @override
  Stream<void> get changes => const Stream.empty();
}

/// Копия дерева с типами `Map<String, Object?>` на всех уровнях: литералы
/// теста выводят узкие типы, и правка по месту падала бы на приведении.
Object? _deep(Object? node) => switch (node) {
  final Map<Object?, Object?> map => <String, Object?>{
    for (final entry in map.entries) entry.key! as String: _deep(entry.value),
  },
  final List<Object?> list => <Object?>[for (final item in list) _deep(item)],
  _ => node,
};
