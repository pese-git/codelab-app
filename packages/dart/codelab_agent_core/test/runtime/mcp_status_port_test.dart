import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../config/config_support.dart' show baseValues, layer;
import '../host/core_harness.dart' show inMemoryJournal, noExec, textStep;
import '../mcp/fake_mcp_connector.dart';

/// Порт состояния MCP сессии для хоста (agent-mcp-client «Поток состояний
/// серверов сессии»; design.md change `add-provider-setup-ui`, D12, решение
/// Q18): `AgentRuntime.mcpStatus(SessionId)` есть у любой открытой сессии,
/// `null` — только для неизвестной или закрытой.
void main() {
  group('кому порт выдаётся', () {
    test('открытая сессия без MCP-серверов: порт есть, servers пуст', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      final port = rig.runtime.mcpStatus(session.id);

      expect(port, isNotNull);
      expect(port!.servers, isEmpty);
    });

    test('открытая сессия с сервером: servers — снимок коннектора', () async {
      final rig = await _Rig.create(servers: [_http('docs')]);
      final session = await rig.session();

      final port = rig.runtime.mcpStatus(session.id)!;

      expect([for (final s in port.servers) s.name], ['docs']);
    });

    test('неизвестная сессия — null', () async {
      final rig = await _Rig.create();

      expect(rig.runtime.mcpStatus(const SessionId('unknown')), isNull);
    });

    test('закрытая сессия — null', () async {
      final rig = await _Rig.create(servers: [_http('docs')]);
      final session = await rig.session();
      await session.close();

      expect(rig.runtime.mcpStatus(session.id), isNull);
    });
  });

  group('первый сервер после перезагрузки конфига (Q18)', () {
    test(
      'порт, взятый до сервера, получает его через changes без нового '
      'mcpStatus (сценарий «Первый сервер после перезагрузки конфига»)',
      () async {
        final rig = await _Rig.create();
        final session = await rig.session();
        final port = rig.runtime.mcpStatus(session.id)!;
        final seen = <List<String>>[];
        port.changes.listen((list) => seen.add([for (final s in list) s.name]));
        expect(port.servers, isEmpty);

        _put(rig.user, 'mcp.servers', [_http('docs')]);
        await rig.runtime.reloadConfig();
        await pumpEventQueue();

        expect(
          seen.last,
          ['docs'],
          reason:
              'подписчик не должен пропустить сервер, добавленный '
              'перезагрузкой: порт переподписывается на новый McpSessionTools',
        );
        expect([for (final s in port.servers) s.name], ['docs']);
      },
    );

    test('после появления сервера события нового McpSessionTools идут в тот '
        'же порт', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final port = rig.runtime.mcpStatus(session.id)!;
      final seen = <String>[];
      port.changes.listen(
        (list) =>
            seen.add(list.map((s) => '${s.name}:${s.state.name}').join(',')),
      );
      _put(rig.user, 'mcp.servers', [_http('docs')]);
      await rig.runtime.reloadConfig();
      await pumpEventQueue();
      seen.clear();

      rig.fake.sessions.single.emit([
        const McpServerSummary(
          name: 'docs',
          toolCount: 0,
          state: McpServerState.failed,
        ),
      ]);

      expect(seen, ['docs:failed']);
    });

    test('сервер удалён перезагрузкой: порт жив, список пуст', () async {
      final rig = await _Rig.create(servers: [_http('docs')]);
      final session = await rig.session();
      final port = rig.runtime.mcpStatus(session.id)!;
      final seen = <int>[];
      port.changes.listen((list) => seen.add(list.length));

      _put(rig.user, 'mcp.servers', <Object?>[]);
      await rig.runtime.reloadConfig();
      await pumpEventQueue();

      expect(rig.runtime.mcpStatus(session.id), isNotNull);
      expect(port.servers, isEmpty);
    });
  });
}

// ---------------------------------------------------------------------------

Map<String, Object?> _http(String name) => {
  'name': name,
  'type': 'http',
  'url': 'https://$name.test/mcp',
};

void _put(Map<String, Object?> root, String path, Object? value) {
  final names = path.split('.');
  var node = root;
  for (final name in names.take(names.length - 1)) {
    node =
        node.putIfAbsent(name, () => <String, Object?>{})!
            as Map<String, Object?>;
  }
  node[names.last] = _deep(value);
}

Object? _deep(Object? node) => switch (node) {
  final Map<Object?, Object?> map => <String, Object?>{
    for (final entry in map.entries) entry.key! as String: _deep(entry.value),
  },
  final List<Object?> list => <Object?>[for (final item in list) _deep(item)],
  _ => node,
};

/// Источник конфигурации в памяти: `load()` пересобирает конфиг из слоя
/// пользователя, который тест правит по месту (как в
/// `mcp_apply_config_test.dart`).
final class _Source implements ConfigSource {
  _Source(this._build) {
    _initial = _build(null);
    expect(_initial.issues, isEmpty, reason: _initial.issues.join('\n'));
  }

  final ConfigLoadResult Function(List<String>? pinned) _build;
  late final ConfigLoadResult _initial;

  @override
  ConfigLoadResult get initial => _initial;

  @override
  Future<ConfigLoadResult> load({bool rebase = true}) async =>
      _build(_initial.config!.trustedProjects);

  @override
  Stream<void> get changes => const Stream.empty();
}

final class _Rig {
  _Rig._(this.user, this.runtime, this.fake);

  static Future<_Rig> create({
    List<Map<String, Object?>> servers = const [],
  }) async {
    final user = <String, Object?>{
      ...baseValues(),
      'providers': {
        'a': {
          'kind': 'openai-compatible',
          'base_url': 'https://a.test/v1',
          'models': {'m1': <String, Object?>{}},
        },
      },
      'agent': {'default_model': 'a/m1'},
      'mcp': {'servers': _deep(servers)},
    };
    final clock = FakeClock();
    final logger = RecordingLogger(clock: clock);
    final scripted = ScriptedStreamFunction.fromJson({
      'steps': [for (var i = 0; i < 5; i++) textStep('ok')],
    }, clock: clock);
    final source = _Source(
      (pinned) => CoreConfig.fromLayers(
        [layer(user)],
        environment: const {},
        projectRoot: '/proj',
        pinnedTrustedProjects: pinned,
      ),
    );
    ModelCatalog catalogOf(CoreConfig config) =>
        StaticModelCatalog(config.providers, logger: logger);
    final fake = FakeMcpConnector();
    final initial = source.initial.config!;
    final built = buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...noExec}),
      services: AgentCoreServices(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: MemorySessionStore(),
        models: catalogOf(initial),
        mcp: fake,
        config: source,
      ),
      config: initial,
      streamFunction: scripted.call,
      modelsFor: (config) =>
          (stream: scripted.call, catalog: catalogOf(config)),
    );
    return _Rig._(user, built.runtime, fake);
  }

  final Map<String, Object?> user;
  final AgentRuntime runtime;
  final FakeMcpConnector fake;

  Future<AgentSession> session() =>
      runtime.createSession(SessionSpec(cwd: '/proj'));
}
