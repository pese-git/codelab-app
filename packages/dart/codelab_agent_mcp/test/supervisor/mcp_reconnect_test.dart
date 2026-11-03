// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import '../support/supervisor_rig.dart';

/// Переподключение серверов сессии (agent-mcp-client «Переподключение и
/// состояние серверов сессии»; design.md change
/// `add-config-writer-and-reload`, D11; E-04, CFG-17): задержки, сброс
/// счётчика, вызовы, граница шага, закрытие сессии, логи. Время — `FakeClock`,
/// случайность — `Random(0)`, серверы — `FakeMcpServer` (PKG-6).
void main() {
  ToolContext ctx(SupervisorRig rig) => ToolContext(
    env: MemoryExecutionEnv(cwd: '/'),
    cancel: CancelToken.none,
    onUpdate: (_) {},
    toolCallId: 'tc-1',
    services: ToolServices(clock: rig.clock, logger: rig.logger),
  );

  String text(ToolExecutionResult result) =>
      result.content.whereType<TextContent>().map((c) => c.text).join();

  group('delays', () {
    test('retries come after about 1, 2, 4, 8, 16, 30 and 30 s, each delay '
        'within [base, base + 20 %] and never over 30 s (scenario "Задержки '
        'повторов"; core/mcp-reconnect-after-crash)', () async {
      final rig = SupervisorRig({
        'docs': fakeServer(['t']),
      });
      final session = await rig.connect([stdio('docs')]);

      for (var attempt = 0; attempt < 7; attempt++) {
        await rig.crash('docs');
        final summary = summaryOf(session, 'docs');
        expect(summary.state, McpServerState.failed, reason: '#$attempt');
        final delay = summary.retryIn!;
        expect(
          delayWithinBounds(delay, attempt),
          isTrue,
          reason: 'delay #$attempt was $delay',
        );
        final opened = rig.spy.opened.length;

        await rig.clock.elapse(delay - const Duration(milliseconds: 1));
        expect(rig.spy.opened, hasLength(opened), reason: 'not yet #$attempt');
        await rig.clock.elapse(const Duration(milliseconds: 1));

        expect(rig.spy.opened, hasLength(opened + 1), reason: '#$attempt');
        expect(summaryOf(session, 'docs').state, McpServerState.connected);
      }
    });

    test('a server that was never connected is retried in the background; '
        'connect only waits for the first attempt', () async {
      final rig = SupervisorRig(
        {
          'docs': fakeServer(['t']),
        },
        failures: {'docs': 'spawn failed: no such file'},
      );

      final session = await rig.connect([stdio('docs')]);

      final failed = summaryOf(session, 'docs');
      expect(failed.state, McpServerState.failed);
      expect(failed.lastError, 'spawn failed: no such file');
      expect(failed.toolCount, 0);
      expect(session.tools, isEmpty);

      rig.failures.clear();
      await rig.clock.elapse(failed.retryIn!);

      expect(summaryOf(session, 'docs').state, McpServerState.connected);
      expect(session.tools, isEmpty, reason: 'registered at the step boundary');
      expect(session.takeUpdate()!.tools.map((t) => t.name), ['mcp__docs__t']);
    });

    test(
      'a failed connection attempt counts towards the delays as well',
      () async {
        final rig = SupervisorRig(
          {
            'docs': fakeServer(['t']),
          },
          failures: {'docs': 'spawn failed: boom'},
        );
        final session = await rig.connect([stdio('docs')]);

        for (var attempt = 0; attempt < 4; attempt++) {
          final delay = summaryOf(session, 'docs').retryIn!;
          expect(
            delayWithinBounds(delay, attempt),
            isTrue,
            reason: '#$attempt',
          );
          await rig.clock.elapse(delay);
        }
      },
    );
  });

  group('reset of the counter', () {
    Future<(SupervisorRig, McpSessionTools)> afterThreeFailures() async {
      final rig = SupervisorRig({
        'docs': fakeServer(['t']),
      });
      final session = await rig.connect([stdio('docs')]);
      for (var i = 0; i < 3; i++) {
        await rig.crash('docs');
        await rig.clock.elapse(summaryOf(session, 'docs').retryIn!);
      }
      expect(summaryOf(session, 'docs').state, McpServerState.connected);
      return (rig, session);
    }

    test('a connection that lived 10 s starts the delays over (scenario '
        '"Сброс после стабильного соединения")', () async {
      final (rig, session) = await afterThreeFailures();

      await rig.clock.elapse(const Duration(seconds: 10));
      await rig.crash('docs');

      expect(
        delayWithinBounds(summaryOf(session, 'docs').retryIn!, 0),
        isTrue,
        reason: '${summaryOf(session, 'docs').retryIn}',
      );
    });

    test('a connection that lived less than 10 s does not', () async {
      final (rig, session) = await afterThreeFailures();

      await rig.clock.elapse(
        const Duration(seconds: 10) - const Duration(milliseconds: 1),
      );
      await rig.crash('docs');

      expect(
        delayWithinBounds(summaryOf(session, 'docs').retryIn!, 3),
        isTrue,
        reason: '${summaryOf(session, 'docs').retryIn}',
      );
    });
  });

  group('calls', () {
    test('a call in flight ends with isError and is not repeated; a call '
        'during the outage does not reach the transport; the tool works '
        'again after the reconnect (scenario "Вызов в полёте и вызов во '
        'время простоя")', () async {
      final fake = FakeMcpServer(
        tools: const [FakeMcpTool('search'), FakeMcpTool('lookup')],
        responses: {
          'search': const FakeToolResponse.crash(),
          'lookup': FakeToolResponse.text('found'),
        },
      );
      final rig = SupervisorRig({'docs': fake});
      final session = await rig.connect([stdio('docs')]);
      final search = session.tools.firstWhere(
        (t) => t.name == 'mcp__docs__search',
      );
      final lookup = session.tools.firstWhere(
        (t) => t.name == 'mcp__docs__lookup',
      );

      final first = await search.execute(const {}, ctx(rig));
      await rig.settle();

      expect(first.isError, isTrue);
      expect(
        text(first),
        'MCP server docs disconnected during the call: '
        'process exited with code 1',
      );

      final second = await lookup.execute(const {}, ctx(rig));

      expect(second.isError, isTrue);
      expect(
        text(second),
        'MCP server docs is not connected (retry in 1s). '
        'Continue without it or try later.',
      );
      expect(fake.calls, hasLength(1), reason: 'nothing was sent again');
      expect(
        session.tools.map((t) => t.name),
        containsAll(['mcp__docs__search', 'mcp__docs__lookup']),
        reason: 'tools of a failed server stay in the registry',
      );

      await rig.clock.elapse(summaryOf(session, 'docs').retryIn!);
      final third = await lookup.execute(const {}, ctx(rig));

      expect(third.isError, isFalse);
      expect(text(third), 'found');
    });

    test('the retry time of the message follows the clock', () async {
      final rig = SupervisorRig({
        'docs': fakeServer(['t']),
      });
      final session = await rig.connect([stdio('docs')]);
      await rig.crash('docs');
      await rig.clock.elapse(summaryOf(session, 'docs').retryIn!);
      await rig.crash('docs'); // задержка ≈2 с
      await rig.clock.elapse(const Duration(milliseconds: 500));

      final result = await session.tools.single.execute(const {}, ctx(rig));

      expect(text(result), contains('(retry in 2s)'));
    });
  });

  group('tools after the reconnect', () {
    test(
      'the new set reaches the registry only through takeUpdate at the '
      'step boundary (scenario "Новый набор после переподключения")',
      () async {
        final fake = fakeServer(['a']);
        final rig = SupervisorRig({'docs': fake});
        final session = await rig.connect([stdio('docs')]);
        await rig.crash('docs');
        fake.notifyToolsListChanged(
          newTools: const [FakeMcpTool('a'), FakeMcpTool('b')],
        );

        await rig.clock.elapse(summaryOf(session, 'docs').retryIn!);

        expect(summaryOf(session, 'docs').state, McpServerState.connected);
        expect(session.tools.map((t) => t.name), ['mcp__docs__a']);
        final update = session.takeUpdate()!;
        expect(update.tools.map((t) => t.name), [
          'mcp__docs__a',
          'mcp__docs__b',
        ]);
        expect(session.tools.map((t) => t.name), [
          'mcp__docs__a',
          'mcp__docs__b',
        ]);
        expect(session.takeUpdate(), isNull);
      },
    );

    test('an unchanged set after the reconnect gives no update', () async {
      final rig = SupervisorRig({
        'docs': fakeServer(['a']),
      });
      final session = await rig.connect([stdio('docs')]);
      await rig.crash('docs');

      await rig.clock.elapse(summaryOf(session, 'docs').retryIn!);

      expect(session.takeUpdate(), isNull);
    });
  });

  group('closing', () {
    test('close during the wait cancels the timer: no new process, no more '
        'mcp.server.retry (scenario "Закрытие сессии во время ожидания '
        'повтора")', () async {
      final rig = SupervisorRig({
        'docs': fakeServer(['t']),
      });
      final session = await rig.connect([stdio('docs')]);
      await rig.crash('docs');
      final opened = rig.spy.opened.length;
      final retries = rig.log.eventsOf('mcp.server.retry').length;

      await session.close();
      await rig.clock.elapse(const Duration(minutes: 5));

      expect(rig.clock.pendingTimers, 0);
      expect(rig.spy.opened, hasLength(opened));
      expect(rig.log.eventsOf('mcp.server.retry'), hasLength(retries));
    });

    test('a connection that finishes after close is closed at once and its '
        'tools are not registered (scenario "Подключение завершилось после '
        'закрытия")', () async {
      final fake = fakeServer(['t']);
      final rig = SupervisorRig({'docs': fake});
      final session = await rig.connect([stdio('docs')]);
      await rig.crash('docs');
      final gate = Completer<void>();
      rig.spy.gate = gate;
      await rig.clock.elapse(summaryOf(session, 'docs').retryIn!);
      expect(summaryOf(session, 'docs').state, McpServerState.connecting);
      final messages = fake.requests.length;

      await session.close();
      gate.complete();
      await rig.settle();

      expect(fake.closedTransports, 2, reason: 'crashed one and the late one');
      expect(fake.requests, hasLength(messages), reason: 'no handshake');
      expect(rig.clock.pendingTimers, 0);
    });
  });

  group('logs', () {
    test('mcp.server.failed on the 1st and every 10th failure in a row, '
        'mcp.server.retry on the rest (scenario "Логи")', () async {
      final rig = SupervisorRig(
        {
          'docs': fakeServer(['t']),
        },
        failures: {'docs': 'spawn failed: no such file'},
      );
      final session = await rig.connect([stdio('docs')]);
      for (var i = 0; i < 11; i++) {
        await rig.clock.elapse(summaryOf(session, 'docs').retryIn!);
      }

      // 12 сбоев: первая попытка и 11 повторов.
      final failed = rig.log.eventsOf('mcp.server.failed');
      expect(failed, hasLength(2));
      expect(failed.first.level, LogLevel.warning);
      expect(failed.first.fields, {
        'session_id': 's1',
        'server': 'docs',
        'transport': 'stdio',
        'reason': 'spawn failed: no such file',
      });
      final retries = rig.log.eventsOf('mcp.server.retry');
      expect(retries, hasLength(10));
      expect(retries.first.level, LogLevel.info);
      expect(retries.first.fields['server'], 'docs');
      expect(retries.first.fields['session_id'], 's1');
      expect(
        [for (final r in retries) r.fields['attempt']],
        [2, 3, 4, 5, 6, 7, 8, 9, 11, 12],
      );
      final firstDelay = retries.first.fields['delay_ms']! as int;
      expect(firstDelay, inInclusiveRange(2000, 2400));
      expect(retries.last.fields['delay_ms'], 30000);
    });

    test('state transitions are logged at debug, a success at info with '
        'mcp.server.connect', () async {
      final rig = SupervisorRig({
        'docs': fakeServer(['t']),
      });
      final session = await rig.connect([stdio('docs')]);
      await rig.crash('docs');
      await rig.clock.elapse(summaryOf(session, 'docs').retryIn!);

      final states = rig.log.eventsOf('mcp.server.state');
      expect(
        [for (final s in states) '${s.fields['from']}>${s.fields['to']}'],
        [
          'connecting>connected',
          'connected>failed',
          'failed>connecting',
          'connecting>connected',
        ],
      );
      expect(states.every((s) => s.level == LogLevel.debug), isTrue);
      expect(states.first.fields['server'], 'docs');
      expect(states.first.fields['session_id'], 's1');
      expect(rig.log.eventsOf('mcp.server.connect'), hasLength(2));
    });

    test(
      'the failure log of a crash carries the reason of the transport',
      () async {
        final rig = SupervisorRig({
          'docs': fakeServer(['t']),
        });
        await rig.connect([stdio('docs')]);

        await rig.crash('docs', reason: 'process exited with code 7');

        final failed = rig.log.eventsOf('mcp.server.failed').single.fields;
        expect(failed['reason'], 'process exited with code 7');
        expect(failed['server'], 'docs');
      },
    );
  });
}
