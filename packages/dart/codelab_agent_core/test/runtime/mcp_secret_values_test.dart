import 'dart:async';
import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../mcp/fake_mcp_connector.dart';
import '../session/recording_store.dart';
import '../support/fake_secret_store.dart';

const _token = 'tok-test-secret';
const _name = 'codelab/mcp/gh/authorization';

SecretTemplate _bearer([String name = _name]) =>
    SecretTemplate([const SecretLiteral('Bearer '), SecretReference(name)]);

McpHttpServerConfig _gh({SecretTemplate? template, String name = 'gh'}) =>
    McpHttpServerConfig(
      name: name,
      url: Uri.parse('https://$name.example.com/mcp'),
      headers: const [('X-Plain', 'v')],
      origin: McpServerOrigin.config,
      secretValues: {'headers.Authorization': template ?? _bearer()},
    );

McpStdioServerConfig _docs() => const McpStdioServerConfig(
  name: 'docs',
  command: '/usr/bin/docs',
  origin: McpServerOrigin.config,
);

/// Секреты MCP-серверов конфигурации (agent-secrets «Секреты MCP-серверов
/// конфигурации»; design.md change `add-agent-secret-store`, D4, D12):
/// рантайм раскрывает шаблоны перед `connect`.
void main() {
  late RecordingStore store;
  late FakeMcpConnector mcp;
  late FakeSecretStore secrets;

  setUp(() {
    store = RecordingStore();
    mcp = FakeMcpConnector();
    secrets = FakeSecretStore(values: {_name: _token});
  });

  CoreHarness build({
    List<McpServerConfig>? config,
    FakeSecretStore? backend,
    bool withSecrets = true,
  }) {
    final logger = RecordingLogger();
    return CoreHarness.build(
      baseEnv: MemoryExecutionEnv(cwd: '/proj'),
      narrow: noExec,
      steps: const [],
      sessions: store,
      mcp: mcp,
      mcpServers: config ?? [_gh(), _docs()],
      secrets: withSecrets
          ? SecretResolver(
              store: backend ?? secrets,
              environment: const {},
              logger: logger,
            )
          : null,
    );
  }

  group('expansion', () {
    test(
      'a header value comes from the store; log and journal stay clean',
      () async {
        final h = build();

        final session = await h.core.runtime.createSession(
          SessionSpec(cwd: '/proj'),
        );

        final servers = mcp.requests.single.servers;
        expect([for (final s in servers) s.name], ['gh', 'docs']);
        final gh = servers.first as McpHttpServerConfig;
        expect(gh.headers, [
          ('X-Plain', 'v'),
          ('Authorization', 'Bearer $_token'),
        ]);
        expect(gh.secretValues, isEmpty);
        expect(gh.origin, McpServerOrigin.config);

        final snapshot = await store.open(session.id);
        final journal = jsonEncode([
          for (final r in snapshot.records) r.toJson(),
        ]);
        final log = [
          for (final r in h.logger.records)
            '${r.event} ${r.fields} ${r.error} ${r.stack}',
        ].join('\n');
        expect(journal, isNot(contains(_token)));
        expect(log, isNot(contains(_token)));
        expect(secrets.reads, [_name]);
      },
    );

    test('a stdio env value is expanded the same way', () async {
      final h = build(
        config: [
          McpStdioServerConfig(
            name: 'fs',
            command: '/usr/bin/fs',
            env: const {'K': 'v'},
            origin: McpServerOrigin.config,
            secretValues: {'env.TOKEN': _bearer()},
          ),
        ],
      );

      await h.core.runtime.createSession(SessionSpec(cwd: '/proj'));

      final fs = mcp.requests.single.servers.single as McpStdioServerConfig;
      expect(fs.env, {'K': 'v', 'TOKEN': 'Bearer $_token'});
    });

    test(
      'a client server keeps a literal \${secret:…}; the store is not read',
      () async {
        final h = build(config: const []);

        await h.core.runtime.createSession(
          SessionSpec(
            cwd: '/proj',
            mcpServers: [
              McpHttpServerConfig(
                name: 'client',
                url: Uri.parse('https://client.example.com/mcp'),
                headers: const [('Authorization', r'${secret:codelab/openai}')],
              ),
            ],
          ),
        );

        final client =
            mcp.requests.single.servers.single as McpHttpServerConfig;
        expect(client.headers, [
          ('Authorization', r'${secret:codelab/openai}'),
        ]);
        expect(secrets.reads, isEmpty);
      },
    );

    test('servers are expanded in parallel: one read per name', () async {
      final h = build(
        config: [
          _gh(),
          _gh(name: 'gh2'),
        ],
      );

      await h.core.runtime.createSession(SessionSpec(cwd: '/proj'));

      expect(mcp.requests.single.servers, hasLength(2));
      expect(secrets.reads, [_name]);
    });
  });

  group('failures', () {
    test('a missing secret fails only its server', () async {
      final h = build(backend: FakeSecretStore());

      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );

      expect(session, isNotNull);
      expect([for (final s in mcp.requests.single.servers) s.name], ['docs']);
      final failed = h.logger.eventsOf('mcp.server.failed').single;
      expect(failed.level, LogLevel.warning);
      expect(failed.fields['server'], 'gh');
      expect(failed.fields['transport'], 'http');
      expect(failed.fields['reason'], 'secret $_name is not set');
    });

    test('an unavailable store fails its server with the backend', () async {
      final h = build(
        backend: FakeSecretStore(
          id: 'file',
          failWith: const SecretStoreUnavailableException(
            backend: 'file',
            reason: 'denied',
          ),
        ),
      );

      await h.core.runtime.createSession(SessionSpec(cwd: '/proj'));

      expect([for (final s in mcp.requests.single.servers) s.name], ['docs']);
      expect(
        h.logger.eventsOf('mcp.server.failed').single.fields['reason'],
        'secret $_name cannot be read: file is unavailable',
      );
    });

    test('without services.secrets the reason is no secret store', () async {
      final h = build(withSecrets: false);

      await h.core.runtime.createSession(SessionSpec(cwd: '/proj'));

      expect([for (final s in mcp.requests.single.servers) s.name], ['docs']);
      expect(
        h.logger.eventsOf('mcp.server.failed').single.fields['reason'],
        'no secret store',
      );
    });

    test('when every server fails the connector is not called', () async {
      final h = build(config: [_gh()], backend: FakeSecretStore());

      await h.core.runtime.createSession(SessionSpec(cwd: '/proj'));

      expect(mcp.requests, isEmpty);
      expect(h.logger.eventsOf('mcp.server.failed'), hasLength(1));
    });
  });

  group('loadSession', () {
    test('expands the secrets of the config servers too', () async {
      final first = build(config: const []);
      final created = await first.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      await created.close();
      final h = build();

      await h.core.runtime.loadSession(created.id, const SessionHostPorts());

      final gh = mcp.requests.last.servers.first as McpHttpServerConfig;
      expect(gh.headers, [
        ('X-Plain', 'v'),
        ('Authorization', 'Bearer $_token'),
      ]);
      expect(gh.secretValues, isEmpty);
    });
  });

  group('setMcpServers', () {
    McpHttpServerConfig client(String name, String value) =>
        McpHttpServerConfig(
          name: name,
          url: Uri.parse('https://$name.client.example.com/mcp'),
          headers: [('Authorization', value)],
        );

    test('a config server with a reference stays connected: same connection, '
        'the value comes from the cache', () async {
      final h = build(config: [_gh()]);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      final connected = mcp.requests.single.servers.single;

      await session.setMcpServers([client('other', 'plain')]);

      final replaced = mcp.sessions.single.replaced.single;
      expect([for (final s in replaced) s.name], ['gh', 'other']);
      final gh = replaced.first as McpHttpServerConfig;
      expect(gh.headers, contains(('Authorization', 'Bearer $_token')));
      // Коннектор решает «оставить или переподключить» по sameConnection:
      // раскрытые конфиги до и после смены совпадают, переподключения нет.
      expect(gh.sameConnection(connected), isTrue);
      expect(secrets.reads, [_name]);
      expect(h.logger.eventsOf('mcp.server.failed'), isEmpty);
    });

    test('a client server named like a config server with a reference gets '
        'no secret', () async {
      final h = build(config: [_gh()]);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );

      await session.setMcpServers([client('gh', r'${secret:codelab/other}')]);

      final replaced = mcp.sessions.single.replaced.single;
      final gh = replaced.single as McpHttpServerConfig;
      expect(gh.origin, McpServerOrigin.session);
      expect(gh.headers, [('Authorization', r'${secret:codelab/other}')]);
      expect(secrets.reads, [_name]);
    });

    test('close() during expansion ends quietly: no mcp.server.failed '
        'and no connector call', () async {
      // Секрета нет, первый сервер выпал; значение появится позже, и
      // смена наборов упрётся в хранилище (ненайденное не кэшируется).
      final backend = FakeSecretStore();
      final h = build(config: [_gh()], backend: backend);
      final session = await h.core.runtime.createSession(
        SessionSpec(cwd: '/proj'),
      );
      expect(h.logger.eventsOf('mcp.server.failed'), hasLength(1));
      final gate = Completer<void>();
      backend
        ..values[_name] = _token
        ..gate = gate;

      final changing = session.setMcpServers([client('other', 'plain')]);
      await pumpEventQueue();
      final closing = session.close();
      await pumpEventQueue();
      gate.complete();
      await changing;
      await closing;

      expect(h.logger.eventsOf('mcp.server.failed'), hasLength(1));
      expect(mcp.requests, isEmpty);
    });
  });

  group('dispose', () {
    test(
      'during expansion the result is discarded and connect is not called',
      () async {
        final gate = Completer<void>();
        final h = build(
          backend: FakeSecretStore(values: {_name: _token}, gate: gate),
        );

        final creating = h.core.runtime.createSession(
          SessionSpec(cwd: '/proj'),
        );
        final cancelled = expectLater(
          creating,
          throwsA(isA<CancelledException>()),
        );
        await pumpEventQueue();
        final disposing = h.core.runtime.dispose();
        // Отмена доходит до токена сессии микрозадачей (CAN-1): значение
        // приходит уже после неё, как у загрузки файлов проекта.
        await pumpEventQueue();
        gate.complete();

        await cancelled;
        await disposing;
        expect(mcp.requests, isEmpty);
      },
    );
  });
}
