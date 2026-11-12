// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/supervisor_rig.dart';

/// Состояние серверов сессии, `reconnect` и `setEnabled`, раскрытие
/// `${secret:…}` перед каждой попыткой (agent-mcp-client «Переподключение и
/// состояние серверов сессии»; design.md change
/// `add-config-writer-and-reload`, D10, D11; CFG-17).
void main() {
  const secretName = 'codelab/mcp/gh/authorization';

  McpHttpServerConfig githubWithSecret() => McpHttpServerConfig(
    name: 'gh',
    url: Uri.parse('https://gh.example.com/mcp'),
    origin: McpServerOrigin.config,
    secretValues: {
      'headers.Authorization': SecretTemplate([
        const SecretLiteral('Bearer '),
        const SecretReference(secretName),
      ]),
    },
  );

  group('summary', () {
    test('lists every server in the order of the list with origin, '
        'transport, state, error and retry time (scenario "Состояние '
        'серверов")', () async {
      final rig = SupervisorRig({
        'github': fakeServer([for (var i = 0; i < 12; i++) 'tool$i']),
        'docs': fakeServer(['search']),
      });
      final github = McpHttpServerConfig(
        name: 'github',
        url: Uri.parse('https://github.example.com/mcp'),
        origin: McpServerOrigin.config,
      );
      final session = await rig.connect([github, stdio('docs')]);

      await rig.crash('docs', reason: 'process exited with code 1');

      final summaries = session.servers;
      expect(summaries.map((s) => s.name), ['github', 'docs']);
      final gh = summaries[0];
      expect(gh.origin, McpServerOrigin.config);
      expect(gh.transport, 'http');
      expect(gh.state, McpServerState.connected);
      expect(gh.toolCount, 12);
      expect(gh.lastError, isNull);
      expect(gh.retryIn, isNull);
      final docs = summaries[1];
      expect(docs.origin, McpServerOrigin.session);
      expect(docs.transport, 'stdio');
      expect(docs.state, McpServerState.failed);
      expect(docs.lastError, 'process exited with code 1');
      expect(delayWithinBounds(docs.retryIn!, 0), isTrue);
      expect(docs.toolCount, 1, reason: 'tools of a failed server stay');
    });

    test('a reconnecting server is connecting and has no retry time; '
        'success clears the error', () async {
      final rig = SupervisorRig({
        'docs': fakeServer(['t']),
      });
      final session = await rig.connect([stdio('docs')]);
      await rig.crash('docs');
      final gate = Completer<void>();
      rig.spy.gate = gate;

      await rig.clock.elapse(summaryOf(session, 'docs').retryIn!);

      final connecting = summaryOf(session, 'docs');
      expect(connecting.state, McpServerState.connecting);
      expect(connecting.retryIn, isNull);

      gate.complete();
      await rig.settle();

      final connected = summaryOf(session, 'docs');
      expect(connected.state, McpServerState.connected);
      expect(connected.lastError, isNull);
    });

    test(
      'lastError is a text of the CodeLab code of at most 200 characters',
      () async {
        final rig = SupervisorRig(
          {
            'docs': fakeServer(['t']),
          },
          failures: {'docs': 'spawn failed: ${'x' * 500}'},
        );

        final session = await rig.connect([stdio('docs')]);

        expect(
          summaryOf(session, 'docs').lastError!.length,
          lessThanOrEqualTo(200),
        );
      },
    );

    test('the summary has defaults for the new fields', () {
      const summary = McpServerSummary(name: 'a', toolCount: 1);

      expect(summary.origin, McpServerOrigin.session);
      expect(summary.transport, 'stdio');
      expect(summary.state, McpServerState.connected);
      expect(summary.lastError, isNull);
      expect(summary.retryIn, isNull);
    });
  });

  group('reconnect', () {
    test('drops the connection and connects at once, without waiting for '
        'the timer', () async {
      final fake = fakeServer(['t']);
      final rig = SupervisorRig({'docs': fake});
      final session = await rig.connect([stdio('docs')]);
      await rig.crash('docs');
      expect(summaryOf(session, 'docs').state, McpServerState.failed);

      await session.reconnect('docs');

      expect(summaryOf(session, 'docs').state, McpServerState.connected);
      expect(rig.spy.opened, ['docs', 'docs']);
      expect(rig.clock.pendingTimers, 0, reason: 'the old timer is cancelled');
    });

    test('a working server is closed and connected again', () async {
      final fake = fakeServer(['t']);
      final rig = SupervisorRig({'docs': fake});
      final session = await rig.connect([stdio('docs')]);

      await session.reconnect('docs');

      expect(fake.closedTransports, 1);
      expect(rig.spy.opened, ['docs', 'docs']);
      expect(summaryOf(session, 'docs').state, McpServerState.connected);
    });

    test('an unknown name changes nothing', () async {
      final rig = SupervisorRig({
        'docs': fakeServer(['t']),
      });
      final session = await rig.connect([stdio('docs')]);

      await session.reconnect('nope');

      expect(rig.spy.opened, ['docs']);
    });
  });

  group('secrets', () {
    test('are expanded again before every attempt; a new value is used '
        '(scenario "Секрет не задан при повторе")', () async {
      final rig = SupervisorRig({
        'gh': fakeServer(['t']),
      });
      var value = 'one';
      var calls = 0;
      final session = await rig.connect(
        [githubWithSecret()],
        expandSecrets: (server) async {
          calls++;
          return server.withSecrets({'headers.Authorization': 'Bearer $value'});
        },
      );
      expect(calls, 1);

      value = 'two';
      await rig.crash('gh');
      await rig.clock.elapse(summaryOf(session, 'gh').retryIn!);

      expect(calls, 2);
      final headers = [
        for (final c in rig.spy.configs) (c as McpHttpServerConfig).headers,
      ];
      expect(headers, [
        [('Authorization', 'Bearer one')],
        [('Authorization', 'Bearer two')],
      ]);
    });

    test('a missing secret is a failed attempt: failed, lastError without '
        'the value, then the usual delays', () async {
      final rig = SupervisorRig({
        'gh': fakeServer(['t']),
      });
      var present = true;
      final session = await rig.connect(
        [githubWithSecret()],
        expandSecrets: (server) async {
          if (!present) {
            throw const McpSecretsException('secret $secretName is not set');
          }
          return server.withSecrets({
            'headers.Authorization': 'Bearer sk-top-secret',
          });
        },
      );
      present = false;
      await rig.crash('gh');
      final opened = rig.spy.opened.length;

      await rig.clock.elapse(summaryOf(session, 'gh').retryIn!);

      final failed = summaryOf(session, 'gh');
      expect(failed.state, McpServerState.failed);
      expect(failed.lastError, 'secret $secretName is not set');
      expect(rig.spy.opened, hasLength(opened), reason: 'no process started');
      expect(
        delayWithinBounds(failed.retryIn!, 1),
        isTrue,
        reason: 'the schedule goes on: ${failed.retryIn}',
      );
      final logged = [
        for (final r in rig.log.records) '${r.event} ${r.fields}',
      ].join('\n');
      expect(logged, isNot(contains('sk-top-secret')));

      present = true;
      await rig.clock.elapse(failed.retryIn!);

      expect(summaryOf(session, 'gh').state, McpServerState.connected);
      expect(summaryOf(session, 'gh').lastError, isNull);
    });

    test('close() during the expansion ends quietly: no process, no failed '
        'record (the dispose of the runtime relies on it)', () async {
      final rig = SupervisorRig({
        'gh': fakeServer(['t']),
      });
      final gate = Completer<void>();
      var calls = 0;
      final session = await rig.connect(
        [githubWithSecret()],
        expandSecrets: (server) async {
          if (++calls > 1) {
            await gate.future;
          }
          return server.withSecrets({'headers.Authorization': 'Bearer x'});
        },
      );
      await rig.crash('gh');
      await rig.clock.elapse(summaryOf(session, 'gh').retryIn!);
      final failed = rig.log.eventsOf('mcp.server.failed').length;
      final opened = rig.spy.opened.length;

      await session.close();
      gate.complete();
      await rig.settle();

      expect(rig.spy.opened, hasLength(opened));
      expect(rig.log.eventsOf('mcp.server.failed'), hasLength(failed));
    });

    test(
      'a server of the client (session/new) never goes through the '
      'expansion: agent-secrets, a reference from the client is a literal',
      () async {
        final rig = SupervisorRig({
          'gh': fakeServer(['t']),
        });
        var calls = 0;
        final clientServer = McpStdioServerConfig(
          name: 'gh',
          command: '/usr/bin/gh',
          secretValues: {
            'env.T': SecretTemplate([const SecretReference(secretName)]),
          },
        );

        final session = await rig.connect(
          [clientServer],
          expandSecrets: (server) async {
            calls++;
            return server.withSecrets({'env.T': 'leaked'});
          },
        );

        expect(calls, 0);
        expect(summaryOf(session, 'gh').state, McpServerState.connected);
        expect((rig.spy.configs.single as McpStdioServerConfig).env, isEmpty);
      },
    );

    test('an unreadable store gives its own text', () async {
      final rig = SupervisorRig({
        'gh': fakeServer(['t']),
      });
      final session = await rig.connect(
        [githubWithSecret()],
        expandSecrets: (server) async => throw const McpSecretsException(
          'secret $secretName cannot be read: keychain is unavailable',
        ),
      );

      expect(
        summaryOf(session, 'gh').lastError,
        'secret $secretName cannot be read: keychain is unavailable',
      );
      expect(rig.spy.opened, isEmpty);
    });
  });

  // change `bind-mcp-secrets-to-origin`, D4; agent-secrets «Ссылки MCP-сервера
  // проектного слоя привязаны к адресу», п. 4. Загрузка пометила сервер
  // причиной блокировки; коннектор переводит её в `failed` до функции
  // раскрытия и до фабрики транспорта.
  group('blocked', () {
    const reason =
        'key bound to another address: move the server to config.local.yaml '
        'or the user config (secret $secretName)';

    McpHttpServerConfig blocked({bool enabled = true}) => McpHttpServerConfig(
      name: 'gh',
      url: Uri.parse('https://evil.example/mcp'),
      origin: McpServerOrigin.config,
      enabled: enabled,
      blockedReason: reason,
    );

    test('goes to failed with the reason, without the expansion and the '
        'transport; the failed record has the same reason', () async {
      final rig = SupervisorRig({
        'gh': fakeServer(['t']),
      });
      var expansions = 0;

      final session = await rig.connect(
        [blocked()],
        expandSecrets: (server) async {
          expansions++;
          return server;
        },
      );

      final failed = summaryOf(session, 'gh');
      expect(failed.state, McpServerState.failed);
      expect(failed.lastError, reason);
      expect(expansions, 0);
      expect(rig.spy.configs, isEmpty, reason: 'the factory is not called');
      expect(rig.spy.opened, isEmpty);
      final records = rig.log.eventsOf('mcp.server.failed');
      expect(records.single.fields['reason'], reason);
    });

    test('the retry by the schedule is again without the transport and the '
        'expansion', () async {
      final rig = SupervisorRig({
        'gh': fakeServer(['t']),
      });
      var expansions = 0;
      final session = await rig.connect(
        [blocked()],
        expandSecrets: (server) async {
          expansions++;
          return server;
        },
      );

      await rig.clock.elapse(summaryOf(session, 'gh').retryIn!);
      await rig.clock.elapse(summaryOf(session, 'gh').retryIn!);

      expect(summaryOf(session, 'gh').state, McpServerState.failed);
      expect(summaryOf(session, 'gh').lastError, reason);
      expect(expansions, 0);
      expect(rig.spy.configs, isEmpty);
      expect(rig.log.eventsOf('mcp.server.retry'), isNotEmpty);
    });

    test('setEnabled(true) of a disabled blocked server gives failed with '
        'the reason (scenario "Выключенный заблокированный сервер '
        'включается командой")', () async {
      final rig = SupervisorRig({
        'gh': fakeServer(['t']),
      });
      final session = await rig.connect([blocked(enabled: false)]);
      expect(summaryOf(session, 'gh').state, McpServerState.disabled);

      await session.setEnabled('gh', true);

      expect(summaryOf(session, 'gh').state, McpServerState.failed);
      expect(summaryOf(session, 'gh').lastError, reason);
      expect(rig.spy.configs, isEmpty);
    });

    test('replaceServers: a connected server that becomes blocked is closed '
        'and goes to failed; once the binding is back it connects (scenario '
        '"Пользователь снимает привязку перезагрузкой")', () async {
      final fake = fakeServer(['t']);
      final rig = SupervisorRig({'gh': fake});
      final open = McpHttpServerConfig(
        name: 'gh',
        url: Uri.parse('https://gh.example.com/mcp'),
        origin: McpServerOrigin.config,
      );
      final session = await rig.connect([open]);
      expect(summaryOf(session, 'gh').state, McpServerState.connected);

      await session.replaceServers([blocked()]);

      expect(summaryOf(session, 'gh').state, McpServerState.failed);
      expect(summaryOf(session, 'gh').lastError, reason);
      expect(fake.closedTransports, 1);
      final opened = rig.spy.configs.length;

      await session.replaceServers([open]);

      expect(summaryOf(session, 'gh').state, McpServerState.connected);
      expect(rig.spy.configs, hasLength(opened + 1));
    });

    test('close() while waiting for the retry leaves no timers and no '
        'processes', () async {
      final rig = SupervisorRig({
        'gh': fakeServer(['t']),
      });
      final session = await rig.connect([blocked()]);
      expect(rig.clock.pendingTimers, 1, reason: 'the retry is scheduled');

      await session.close();

      expect(rig.clock.pendingTimers, 0);
      expect(rig.spy.configs, isEmpty);
    });
  });

  group('enabled', () {
    test('a server with enabled: false is disabled and has no process; '
        'setEnabled(true) connects it in this session (scenario "Выключенный '
        'конфигом сервер")', () async {
      final rig = SupervisorRig({
        'docs': fakeServer(['t']),
      });
      final session = await rig.connect([
        stdio('docs', origin: McpServerOrigin.config, enabled: false),
      ]);

      final off = summaryOf(session, 'docs');
      expect(off.state, McpServerState.disabled);
      expect(off.toolCount, 0);
      expect(off.origin, McpServerOrigin.config);
      expect(rig.spy.opened, isEmpty, reason: 'no process');
      expect(session.tools, isEmpty);

      await session.setEnabled('docs', true);

      expect(summaryOf(session, 'docs').state, McpServerState.connected);
      expect(rig.spy.opened, ['docs']);
      expect(session.tools.map((t) => t.name), ['mcp__docs__t']);
    });

    test('setEnabled(false) closes the transport, stops the timer and '
        'explains why', () async {
      final fake = fakeServer(['t']);
      final rig = SupervisorRig({'docs': fake});
      final session = await rig.connect([stdio('docs')]);

      await session.setEnabled('docs', false);

      final off = summaryOf(session, 'docs');
      expect(off.state, McpServerState.disabled);
      expect(off.lastError, 'disabled by /mcp disable');
      expect(fake.closedTransports, 1);
      expect(session.tools, isEmpty);
    });

    test('setEnabled(false) of a waiting server cancels its timer', () async {
      final rig = SupervisorRig({
        'docs': fakeServer(['t']),
      });
      final session = await rig.connect([stdio('docs')]);
      await rig.crash('docs');

      await session.setEnabled('docs', false);
      await rig.clock.elapse(const Duration(minutes: 1));

      expect(rig.spy.opened, ['docs']);
      expect(rig.clock.pendingTimers, 0);
    });

    test(
      'a server disabled by a collision is connected again by '
      'setEnabled(true); the collision repeats while the owner is there',
      () async {
        final rig = SupervisorRig({
          'my_srv': fakeServer(['t']),
          'my.srv': fakeServer(['t']),
        });
        final session = await rig.connect([stdio('my_srv'), stdio('my.srv')]);
        final collided = summaryOf(session, 'my.srv');
        expect(collided.state, McpServerState.disabled);
        expect(collided.lastError, 'tool name collision: mcp__my_srv__t');

        await session.setEnabled('my.srv', true);

        final again = summaryOf(session, 'my.srv');
        expect(again.state, McpServerState.disabled);
        expect(again.lastError, 'tool name collision: mcp__my_srv__t');
        expect(rig.spy.opened, ['my_srv', 'my.srv', 'my.srv']);
        expect(session.tools.map((t) => t.name), ['mcp__my_srv__t']);
      },
    );

    test(
      'once the owner is gone the collision-disabled server connects',
      () async {
        final rig = SupervisorRig({
          'my_srv': fakeServer(['t']),
          'my.srv': fakeServer(['t']),
        });
        final session = await rig.connect([stdio('my_srv'), stdio('my.srv')]);
        await session.setEnabled('my_srv', false);

        await session.setEnabled('my.srv', true);

        expect(summaryOf(session, 'my.srv').state, McpServerState.connected);
        expect(session.tools.map((t) => t.name), ['mcp__my_srv__t']);
      },
    );

    test('replaceServers: true to false closes the server, false to true '
        'connects a new one', () async {
      final fake = fakeServer(['t']);
      final rig = SupervisorRig({'docs': fake});
      final session = await rig.connect([stdio('docs')]);

      await session.replaceServers([stdio('docs', enabled: false)]);

      expect(summaryOf(session, 'docs').state, McpServerState.disabled);
      expect(fake.closedTransports, 1);

      await session.replaceServers([stdio('docs')]);

      expect(summaryOf(session, 'docs').state, McpServerState.connected);
      expect(rig.spy.opened, ['docs', 'docs']);
    });

    test('replaceServers wakes an unchanged failed server at once', () async {
      final rig = SupervisorRig({
        'docs': fakeServer(['t']),
      });
      final session = await rig.connect([stdio('docs')]);
      await rig.crash('docs');

      await session.replaceServers([stdio('docs')]);

      expect(summaryOf(session, 'docs').state, McpServerState.connected);
      expect(rig.spy.opened, ['docs', 'docs']);
    });
  });
  group('manual choice and the config (R6-2)', () {
    McpStdioServerConfig withTimeout(
      String name,
      Duration? timeout, {
      bool enabled = true,
    }) => McpStdioServerConfig(
      name: name,
      command: '/usr/bin/$name',
      origin: McpServerOrigin.config,
      callTimeout: timeout,
      enabled: enabled,
    );

    test('/mcp disable stays while the element of the server is unchanged, '
        'other edits of the file do not reset it', () async {
      final rig = SupervisorRig({
        'a': fakeServer(['t']),
        'b': fakeServer(['t']),
      });
      final session = await rig.connect([stdio('a')]);
      await session.setEnabled('a', false);

      await session.replaceServers([stdio('a'), stdio('b')]);

      expect(summaryOf(session, 'a').state, McpServerState.disabled);
      expect(summaryOf(session, 'b').state, McpServerState.connected);
    });

    test('/mcp enable of a server disabled in the config stays while the '
        'element is unchanged', () async {
      final rig = SupervisorRig({
        'a': fakeServer(['t']),
      });
      final session = await rig.connect([
        withTimeout('a', null, enabled: false),
      ]);
      await session.setEnabled('a', true);

      await session.replaceServers([withTimeout('a', null, enabled: false)]);

      expect(summaryOf(session, 'a').state, McpServerState.connected);
      expect(rig.spy.opened, ['a'], reason: 'no reconnect');
    });

    test('an edit of the server itself starts from the config again: even a '
        'timeout resets the manual choice', () async {
      final rig = SupervisorRig({
        'a': fakeServer(['t']),
      });
      final session = await rig.connect([withTimeout('a', null)]);
      await session.setEnabled('a', false);

      await session.replaceServers([
        withTimeout('a', const Duration(seconds: 30)),
      ]);

      expect(summaryOf(session, 'a').state, McpServerState.connected);
    });

    test('a changed enabled in the file wins over the manual choice', () async {
      final rig = SupervisorRig({
        'a': fakeServer(['t']),
      });
      final session = await rig.connect([
        withTimeout('a', null, enabled: false),
      ]);
      await session.setEnabled('a', true);

      await session.replaceServers([withTimeout('a', null)]);
      expect(summaryOf(session, 'a').state, McpServerState.connected);

      await session.replaceServers([withTimeout('a', null, enabled: false)]);
      expect(summaryOf(session, 'a').state, McpServerState.disabled);
    });

    test('a timeout-only edit of a server nobody touched keeps the '
        'connection', () async {
      final rig = SupervisorRig({
        'a': fakeServer(['t']),
      });
      final session = await rig.connect([withTimeout('a', null)]);

      await session.replaceServers([
        withTimeout('a', const Duration(seconds: 30)),
      ]);

      expect(rig.spy.opened, ['a']);
      expect(summaryOf(session, 'a').state, McpServerState.connected);
    });
  });
}
