import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
// Тест проверяет применённый снимок рантайма: это шов тестов, а не публичный
// API (PKG-5).
import 'package:codelab_agent_core/src/runtime/agent_runtime.dart'
    show AgentRuntimeImpl;
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../config/config_support.dart' show baseValues, layer;
import '../host/core_harness.dart' show inMemoryJournal, noExec, textStep;
import '../mcp/fake_mcp_connector.dart';
import '../support/manual_stream.dart';

/// Серверы конфигурации при перезагрузке (agent-runtime «Серверы
/// конфигурации при перезагрузке»; design.md change
/// `add-config-writer-and-reload`, D10; R0-1, R0-4, R6-1, R6-2): шаг 7а
/// отдаёт `replaceServers` полный желаемый список — серверы нового снимка,
/// затем серверы клиента на момент применения — через очередь сессии,
/// общую с `setMcpServers`.
///
/// Коннектор — `FakeMcpConnector`: проверяется список, его момент и порядок;
/// «оставить, закрыть, подключить» делает настоящий коннектор (тесты пакета
/// `codelab_agent_mcp`).
void main() {
  group('replaceServers gets the desired list', () {
    test('one changed server: the new variant, the rest as they were '
        '(scenario "Изменён один сервер")', () async {
      final rig = await _Rig.create(servers: [_http('a'), _http('b')]);
      final session = await rig.session();
      final first = rig.fake.requests.single.servers;
      _put(rig.user, 'mcp.servers', [
        _http('a'),
        _http('b', url: 'https://b2.test/mcp'),
      ]);

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, isEmpty);
      final desired = rig.replaced(session).single;
      expect([for (final s in desired) s.name], ['a', 'b']);
      expect(desired.first.sameConnection(first.first), isTrue);
      expect(
        (desired.last as McpHttpServerConfig).url.host,
        'b2.test',
        reason: 'the changed server',
      );
    });

    test('a server of the client is not touched: it follows the servers of '
        'the config (scenario "Сервер клиента не тронут")', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final client = McpHttpServerConfig(
        name: 'mine',
        url: Uri.parse('https://mine.test/mcp'),
      );
      final session = await rig.session(mcp: [client]);
      _put(rig.user, 'mcp.servers', [_http('a'), _http('b')]);

      await rig.runtime.reloadConfig();

      final desired = rig.replaced(session).single;
      expect([for (final s in desired) s.name], ['a', 'b', 'mine']);
      expect(desired.last.origin, McpServerOrigin.session);
    });

    test(
      'a client server with the name of a config server shadows it',
      () async {
        final rig = await _Rig.create(servers: [_http('a')]);
        final client = McpHttpServerConfig(
          name: 'b',
          url: Uri.parse('https://client.test/mcp'),
        );
        final session = await rig.session(mcp: [client]);
        _put(rig.user, 'mcp.servers', [_http('a'), _http('b')]);

        await rig.runtime.reloadConfig();

        final desired = rig.replaced(session).single;
        expect(
          [for (final s in desired) '${s.name}:${s.origin.name}'],
          ['a:config', 'b:session'],
        );
      },
    );

    test('a removed server is not in the list', () async {
      final rig = await _Rig.create(servers: [_http('a'), _http('b')]);
      final session = await rig.session();
      _put(rig.user, 'mcp.servers', [_http('b')]);

      await rig.runtime.reloadConfig();

      expect([for (final s in rig.replaced(session).single) s.name], ['b']);
    });

    test('an unchanged server stays in the list: the connector wakes it if '
        'it is failed (OQ8)', () async {
      final rig = await _Rig.create(servers: [_http('a'), _http('b')]);
      final session = await rig.session();
      _put(rig.user, 'mcp.servers', [_http('a'), _http('b'), _http('c')]);

      await rig.runtime.reloadConfig();

      expect(
        [for (final s in rig.replaced(session).single) s.name],
        ['a', 'b', 'c'],
      );
    });

    test('a reload without a difference does not touch the servers', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();

      await rig.runtime.reloadConfig();

      expect(rig.replaced(session), isEmpty);
    });

    test('a closed session gets no replacement', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();
      await session.close();
      _put(rig.user, 'mcp.servers', [_http('b')]);

      await rig.runtime.reloadConfig();

      expect(rig.replaced(session), isEmpty);
    });
  });

  group('what the config may not start (R0-1, R0-4, R6-1)', () {
    test('a new and a changed stdio server, http to stdio, an http server '
        'with a substitution: not in the list; one without is', () async {
      final rig = await _Rig.create(
        servers: [_stdio('s'), _http('h'), _http('t')],
      );
      final session = await rig.session();
      _put(rig.user, 'mcp.servers', [
        _stdio('s', command: 'other-mcp'),
        _stdio('h'),
        _http('t'),
        _stdio('new'),
        _http('x', headers: {'X-Gw': r'${secret:codelab/mcp/x/gw}'}),
        _http('y', headers: {'Authorization': r'Bearer ${GITHUB_TOKEN}'}),
        _http('plain'),
      ]);

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, [
        'mcp.servers[h]',
        'mcp.servers[new]',
        'mcp.servers[s]',
        'mcp.servers[x]',
        'mcp.servers[y]',
      ]);
      final desired = rig.replaced(session).single;
      expect([for (final s in desired) s.name], ['s', 'h', 't', 'plain']);
      expect((desired.first as McpStdioServerConfig).command, 'fake-mcp');
      expect(desired[1], isA<McpHttpServerConfig>(), reason: 'the old variant');
    });

    test('enabling a stdio server from enabled: false waits; disabling '
        'closes: the server is in the list with enabled == false', () async {
      final rig = await _Rig.create(
        servers: [_stdio('off', enabled: false), _stdio('on')],
      );
      final session = await rig.session();
      _put(rig.user, 'mcp.servers', [
        _stdio('off'),
        _stdio('on', enabled: false),
      ]);

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, ['mcp.servers[off]']);
      final desired = rig.replaced(session).single;
      expect(
        [for (final s in desired) '${s.name}:${s.enabled}'],
        ['off:false', 'on:false'],
      );
    });

    test('a changed command of a disabled stdio server waits; the enable of '
        'a human uses the old one (R6-1)', () async {
      final rig = await _Rig.create(
        servers: [_stdio('off', enabled: false), _http('h')],
      );
      final session = await rig.session();
      _put(rig.user, 'mcp.servers', [
        _stdio('off', command: 'evil-mcp', enabled: false),
        _http('h', url: 'https://h2.test/mcp'),
      ]);

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, ['mcp.servers[off]']);
      final off = rig.replaced(session).single.first as McpStdioServerConfig;
      expect(off.command, 'fake-mcp');
      expect(off.enabled, isFalse);
    });
  });

  group('disabling together with a changed connection (R6-1)', () {
    test('the server is closed: the list has the old parameters with '
        'enabled == false', () async {
      final rig = await _Rig.create(servers: [_stdio('a'), _http('h')]);
      final session = await rig.session();
      _put(rig.user, 'mcp.servers', [
        _stdio('a', command: 'evil-mcp', enabled: false),
        _http('h'),
      ]);

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, ['mcp.servers[a]']);
      final a = rig.replaced(session).single.first as McpStdioServerConfig;
      expect(a.command, 'fake-mcp');
      expect(a.enabled, isFalse);
    });
  });

  group('close during a reload that hangs in replaceServers', () {
    // Коннектор зависает в `replaceServers` до отмены токена сессии, как
    // настоящий при зависшем рукопожатии или раскрытии секретов (D11).
    test(
      'session.close() ends, reloadConfig() ends, nothing more is applied',
      () async {
        final rig = await _Rig.create(
          servers: [_http('a')],
          replaceHangs: true,
        );
        final session = await rig.session();
        _put(rig.user, 'mcp.servers', [_http('a'), _http('b')]);
        var reloaded = false;
        final reloading = rig.runtime.reloadConfig().whenComplete(
          () => reloaded = true,
        );
        await pumpEventQueue();
        expect(reloaded, isFalse, reason: 'waits for the hanging replacement');
        expect(rig.replaced(session), hasLength(1));

        await session.close().timeout(const Duration(seconds: 5));
        await reloading.timeout(const Duration(seconds: 5));

        expect(reloaded, isTrue);
        _put(rig.user, 'mcp.servers', [_http('c')]);
        await rig.runtime.reloadConfig();
        expect(rig.replaced(session), hasLength(1), reason: 'closed: no more');
      },
    );

    test('runtime.dispose() ends, reloadConfig() ends', () async {
      final rig = await _Rig.create(servers: [_http('a')], replaceHangs: true);
      await rig.session();
      _put(rig.user, 'mcp.servers', [_http('b')]);
      final reloading = rig.runtime.reloadConfig();
      await pumpEventQueue();

      await rig.runtime.dispose().timeout(const Duration(seconds: 5));
      await reloading.timeout(const Duration(seconds: 5));
    });
  });

  group('timing and the queue of the session', () {
    test('during a turn the replacement waits for TurnEnded; the last '
        'desired set wins (scenarios "Удаление во время хода", "Последний '
        'побеждает")', () async {
      final rig = await _Rig.create(servers: [_http('a')], hold: true);
      final session = await rig.session();
      final turn = session.prompt(const [TextContent('go')]);
      await pumpEventQueue();
      expect(rig.manual!.calls, 1, reason: 'the turn is running');
      _put(rig.user, 'mcp.servers', []);
      await rig.runtime.reloadConfig();
      _put(rig.user, 'mcp.servers', [_http('b'), _http('c')]);
      await rig.runtime.reloadConfig();

      expect(rig.replaced(session), isEmpty, reason: 'not inside a turn');

      await session.cancel();
      await turn;
      await pumpEventQueue();

      final replaced = rig.replaced(session);
      expect(replaced, hasLength(1));
      expect([for (final s in replaced.single) s.name], ['b', 'c']);
    });

    test('without a turn the replacement is finished before reloadConfig '
        'returns', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();
      final gate = Completer<void>();
      rig.fake.sessions.single.replaceGate = gate;
      _put(rig.user, 'mcp.servers', [_http('b')]);

      var done = false;
      final reloading = rig.runtime.reloadConfig().whenComplete(
        () => done = true,
      );
      await pumpEventQueue();
      expect(done, isFalse, reason: 'waits for the connector');
      gate.complete();
      await reloading;

      expect(rig.replaced(session), hasLength(1));
    });

    test('shares the queue with setMcpServers: the list of the client is '
        'taken at the moment of applying', () async {
      final rig = await _Rig.create(servers: [_http('a')], hold: true);
      final session = await rig.session();
      final turn = session.prompt(const [TextContent('go')]);
      await pumpEventQueue();
      final c1 = McpHttpServerConfig(
        name: 'c1',
        url: Uri.parse('https://c1.test/mcp'),
      );
      await session.setMcpServers([c1]);
      _put(rig.user, 'mcp.servers', [_http('a'), _http('b')]);
      await rig.runtime.reloadConfig();

      await session.cancel();
      await turn;
      await pumpEventQueue();

      final replaced = rig.replaced(session);
      expect(replaced, hasLength(1));
      expect([for (final s in replaced.single) s.name], ['a', 'b', 'c1']);
    });

    test(
      'setMcpServers after a reload sees the new servers of the config',
      () async {
        final rig = await _Rig.create(servers: [_http('a')]);
        final session = await rig.session();
        _put(rig.user, 'mcp.servers', [_http('a'), _http('b')]);
        await rig.runtime.reloadConfig();
        final c1 = McpHttpServerConfig(
          name: 'c1',
          url: Uri.parse('https://c1.test/mcp'),
        );

        await session.setMcpServers([c1]);

        final replaced = rig.replaced(session);
        expect(replaced, hasLength(2));
        expect([for (final s in replaced.last) s.name], ['a', 'b', 'c1']);
      },
    );
  });
}

// ---------------------------------------------------------------------------

Map<String, Object?> _http(
  String name, {
  String? url,
  Map<String, String>? headers,
}) => {
  'name': name,
  'type': 'http',
  'url': url ?? 'https://$name.test/mcp',
  'headers': ?headers,
};

Map<String, Object?> _stdio(
  String name, {
  String command = 'fake-mcp',
  bool enabled = true,
}) => {
  'name': name,
  'type': 'stdio',
  'command': command,
  if (!enabled) 'enabled': false,
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

Map<String, Object?> _user(List<Map<String, Object?>> servers) => {
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

/// Источник конфигурации в памяти: `load()` пересобирает конфиг из слоя
/// пользователя, который тест правит по месту.
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
  _Rig._(this.user, this.built, this.fake, this.manual);

  static Future<_Rig> create({
    List<Map<String, Object?>> servers = const [],
    bool hold = false,
    bool replaceHangs = false,
  }) async {
    final user = _user(servers);
    final clock = FakeClock();
    final logger = RecordingLogger(clock: clock);
    final manual = hold ? ManualStream(clock) : null;
    final scripted = ScriptedStreamFunction.fromJson({
      'steps': [for (var i = 0; i < 10; i++) textStep('ok')],
    }, clock: clock);
    StreamFunction stream() => manual != null ? manual.call : scripted.call;
    final source = _Source(
      (pinned) => CoreConfig.fromLayers(
        [layer(user)],
        environment: const {'GITHUB_TOKEN': 'tok-test'},
        projectRoot: '/proj',
        pinnedTrustedProjects: pinned,
      ),
    );
    ModelCatalog catalogOf(CoreConfig config) =>
        StaticModelCatalog(config.providers, logger: logger);
    final fake = FakeMcpConnector(replaceBlocksUntilCancel: replaceHangs);
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
      streamFunction: stream(),
      modelsFor: (config) => (stream: stream(), catalog: catalogOf(config)),
    );
    return _Rig._(user, built, fake, manual);
  }

  final Map<String, Object?> user;
  final BuiltAgentCore built;
  final FakeMcpConnector fake;
  final ManualStream? manual;

  AgentRuntimeImpl get runtime => built.runtime as AgentRuntimeImpl;

  Future<AgentSession> session({List<McpServerConfig> mcp = const []}) =>
      runtime.createSession(SessionSpec(cwd: '/proj', mcpServers: mcp));

  /// Аргументы каждого `replaceServers` сессии, по порядку.
  List<List<McpServerConfig>> replaced(AgentSession session) {
    final index = fake.requests.indexWhere((r) => r.sessionId == session.id);
    return index < 0 ? const [] : fake.sessions[index].replaced;
  }
}
