import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcNotification, JsonRpcResponse;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// Конфигурация сессии по её папке на границе ACP (agent-acp-server «Ошибка
/// проектного конфига сессии», «Модели сессии по её каталогу»; design.md
/// change `require-project-folder`, D21, Q20 (a)).
///
/// Почему отдельный файл: все четыре сценария делят один стенд — корень
/// запуска `/work/demo` и подставной `ProjectConfigLoader` с папкой
/// `/work/b`, провайдер `local` которой есть только в ней.
void main() {
  const root = '/work/demo';
  const other = '/work/b';
  ServerHarness? h;
  ServerHarness? second;
  tearDown(() async {
    await h?.dispose();
    await second?.dispose();
    h = second = null;
  });

  ConfigTree user() => ConfigTree(
    kind: ConfigLayerKind.user,
    source: '/home/u/.codelab/config.yaml',
    values: {
      'providers': <String, Object?>{
        'a': <String, Object?>{
          'kind': 'openai-compatible',
          'base_url': 'https://a.test/v1',
          'models': <String, Object?>{
            'm1': <String, Object?>{},
            'm2': <String, Object?>{},
          },
        },
      },
      'agent': <String, Object?>{'default_model': 'a/m1'},
    },
  );

  /// Конфигурация папки: пользовательский слой и, для [withLocal], провайдер
  /// `local` слоем `projectLocal` (как «This project only»).
  ConfigLoadResult folder(String path, {bool withLocal = false}) =>
      CoreConfig.fromLayers(
        [
          user(),
          if (withLocal)
            ConfigTree(
              kind: ConfigLayerKind.projectLocal,
              source: '$path/.codelab/config.local.yaml',
              values: {
                'providers': <String, Object?>{
                  'local': <String, Object?>{
                    'kind': 'openai-compatible',
                    'base_url': 'https://local.test/v1',
                    'models': <String, Object?>{'m': <String, Object?>{}},
                  },
                },
              },
            ),
        ],
        environment: const {},
        projectRoot: path,
        pinnedTrustedProjects: const [root, other],
      );

  /// Две проблемы в разных файлах: `message` обязан собрать их через `; `.
  ConfigLoadResult broken(String path) => ConfigLoadResult(
    issues: [
      ConfigIssue(
        kind: ConfigIssueKind.syntax,
        key: '',
        source: '$path/.codelab/config.yaml',
        line: 3,
        column: 5,
        message: 'bad yaml',
      ),
      ConfigIssue(
        kind: ConfigIssueKind.value,
        key: 'agent.mode',
        source: '$path/.codelab/config.local.yaml',
        line: 1,
        column: 1,
        message: 'unknown mode',
      ),
    ],
  );

  Future<ServerHarness> start(
    _Port port, {
    JournalStore? sessions,
    ConfigSource? configSource,
  }) async {
    final started = await ServerHarness.start(
      sessions: sessions,
      projectConfig: port,
      rootConfig: configSource == null ? folder(root).config : null,
      configSource: configSource,
    );
    await started.initialize();
    return started;
  }

  List<String> modelValues(Iterable<Object?> options) => [
    for (final option in options.cast<Map>())
      if (option['id'] == 'model')
        for (final entry in (option['options']! as List).cast<Map>())
          entry['value']! as String,
  ];

  final expectedMessage =
      '$other/.codelab/config.yaml:3:5: bad yaml; '
      '$other/.codelab/config.local.yaml:1:1: agent.mode: unknown mode';
  const expectedData = {
    'codelab': {'reason': 'projectConfigInvalid'},
  };

  group('ProjectConfigException', () {
    test('session/new answers -32603 with one line and only the reason, '
        'the session is not listed and the connection lives', () async {
      final port = _Port({root: folder(root), other: broken(other)});
      final started = h = await start(port);

      final refused = await started.client.request('session/new', {
        'cwd': other,
        'mcpServers': <Object?>[],
      });

      expect(refused.errorCode, -32603);
      expect(refused.error!.message, expectedMessage);
      expect(refused.error!.message, isNot(contains('\n')));
      expect(refused.error!.data, expectedData);
      // §16: корреляция без значений конфига и текста проблем.
      expect(
        started.logger
            .eventsOf('acp.session.project_config_invalid')
            .single
            .fields,
        {'cwd': other, 'issues': 2},
      );
      final listed = await started.client.request('session/list', {});
      expect(listed.resultMap['sessions'], isEmpty);
      expect(await started.newSession(cwd: root), isNotEmpty);
    });

    test('session/load answers the same error and leaves the journal '
        'as it was', () async {
      final store = JournalStore();
      final port = _Port({root: folder(root), other: folder(other)});
      final creator = h = await start(port, sessions: store);
      final id = await creator.newSession(cwd: other);
      final before = (await store.open(SessionId(id))).records.length;
      await creator.dispose();
      h = null;

      port.results[other] = broken(other);
      final loader = second = await start(port, sessions: store);
      final refused = await loader.client.request('session/load', {
        'sessionId': id,
        'cwd': other,
        'mcpServers': <Object?>[],
      });

      expect(refused.errorCode, -32603);
      expect(refused.error!.message, expectedMessage);
      expect(refused.error!.data, expectedData);
      expect(
        loader.logger
            .eventsOf('acp.session.project_config_invalid')
            .single
            .fields,
        {'cwd': other, 'session_id': id, 'issues': 2},
      );
      expect((await store.open(SessionId(id))).records, hasLength(before));
    });
  });

  group('models by the catalog of the session', () {
    test('model options of sessions of different folders differ and a '
        'foreign model is -32602', () async {
      final port = _Port({
        root: folder(root),
        other: folder(other, withLocal: true),
      });
      final started = h = await start(port);

      final inRoot = await started.client.request('session/new', {
        'cwd': root,
        'mcpServers': <Object?>[],
      });
      await started.client.next();
      final inOther = await started.client.request('session/new', {
        'cwd': other,
        'mcpServers': <Object?>[],
      });
      await started.client.next();

      expect(modelValues(inRoot.resultMap['configOptions']! as List), [
        'a/m1',
        'a/m2',
      ]);
      expect(modelValues(inOther.resultMap['configOptions']! as List), [
        'a/m1',
        'a/m2',
        'local/m',
      ]);
      Future<int?> choose(JsonRpcResponse response, String model) async =>
          (await started.client.request('session/set_config_option', {
            'sessionId': response.resultMap['sessionId'],
            'configId': 'model',
            'value': model,
          })).errorCode;
      expect(await choose(inRoot, 'local/m'), -32602);
      expect(await choose(inOther, 'local/m'), isNull);
    });

    test('a config_option_update after a root reload reaches only the '
        'sessions of the root', () async {
      final source = _RootSource(folder(root));
      final port = _Port({
        root: folder(root),
        other: folder(other, withLocal: true),
      });
      final started = h = await start(port, configSource: source);
      final inRoot = await started.newSession(cwd: root);
      await started.newSession(cwd: other);

      source.addModel('m3');
      final report = await started.core.runtime.reloadConfig();
      await pumpEventQueue();

      expect(report.outcome, ConfigReloadOutcome.applied);
      final targets = [
        for (final frame in await started.client.drain())
          if (frame is JsonRpcNotification &&
              (frame.params! as Map)['update']['sessionUpdate'] ==
                  'config_option_update')
            (frame.params! as Map)['sessionId'],
      ];
      expect(targets, [inRoot]);
    });
  });
}

/// Порт папок: результат на каждый вызов берётся из изменяемой карты.
final class _Port implements ProjectConfigLoader {
  _Port(this.results);

  final Map<String, ConfigLoadResult> results;

  @override
  Future<ConfigLoadResult> loadForProject(String canonicalCwd) async =>
      results[canonicalCwd] ?? (throw StateError('no folder $canonicalCwd'));
}

/// Источник перезагрузки корня: пользовательский слой с правкой каталога.
final class _RootSource implements ConfigSource {
  _RootSource(this.initial);

  @override
  final ConfigLoadResult initial;
  final _extra = <String>[];

  void addModel(String name) => _extra.add(name);

  @override
  Future<ConfigLoadResult> load({bool rebase = true}) async =>
      CoreConfig.fromLayers(
        [
          ConfigTree(
            kind: ConfigLayerKind.user,
            source: '/home/u/.codelab/config.yaml',
            values: {
              'providers': <String, Object?>{
                'a': <String, Object?>{
                  'kind': 'openai-compatible',
                  'base_url': 'https://a.test/v1',
                  'models': <String, Object?>{
                    'm1': <String, Object?>{},
                    'm2': <String, Object?>{},
                    for (final name in _extra) name: <String, Object?>{},
                  },
                },
              },
              'agent': <String, Object?>{'default_model': 'a/m1'},
            },
          ),
        ],
        environment: const {},
        projectRoot: '/work/demo',
        pinnedTrustedProjects: initial.config!.trustedProjects,
      );

  @override
  Stream<void> get changes => const Stream.empty();
}
