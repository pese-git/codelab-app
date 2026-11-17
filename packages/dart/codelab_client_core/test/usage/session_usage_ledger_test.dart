// Журнал usage в `SessionView.usageLedger` и `refreshUsageLedger` (задача
// 3.3 change `add-usage-ledger`; spec acp-client-kit «Журнал usage сессии в
// клиенте»: «Агент без журнала», «Журнал загружен», «Слияние вызовов»,
// «Ответ старого соединения», «Ошибка агента»; design.md, D10, D12).
//
// Формы (согласованы с тестами фикстуры 3.5): `refreshUsageLedger(id,
// {rebuild})`; `SessionView.usageLedger` — `UsageLedgerUnavailable | Idle |
// Loading(previous) | Loaded(view) | Failed(reason, previous)`;
// `Failed.reason.kind` и `.code`. Записи журнала D12: `usage.ledger.requested`,
// `usage.ledger.received`, `usage.ledger.stale` (DEBUG), `usage.ledger.failed
// {session_id, code}` и `usage.ledger.decode_failed` (WARNING).
//
// Гонки собраны принудительным порядком кадров на `FakeAcpTransport`, без
// таймеров.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/usage_agent.dart';

const _ledgerMethod = '_codelab/session/usage/ledger';
const _sid = SessionId('s-1');

const _ledgerCapabilities = AgentCapabilities(
  loadSession: true,
  meta: {
    'codelab': {
      'usage': {'version': 1},
      'usageLedger': {'version': 1},
    },
  },
);

Map<String, Object?> _tokens([int input = 10]) => {
  'input': input,
  'output': 1,
  'cacheRead': 0,
  'cacheWrite': 0,
};

/// Ответ журнала D6 с двумя ходами и двумя шагами в первом.
Map<String, Object?> _ledger({int seq = 5, String sessionId = 's-1'}) => {
  'sessionId': sessionId,
  'seq': seq,
  'currency': 'USD',
  'total': {'turns': 2, 'steps': 3, 'tokens': _tokens(30), 'cost': '0.5'},
  'turns': [
    {
      'index': 1,
      'total': {'steps': 2, 'tokens': _tokens(20)},
      'steps': [
        {
          'index': 0,
          'tokens': _tokens(),
          'toolCallIds': ['c1'],
        },
        {'index': 1, 'tokens': _tokens(), 'toolCallIds': <String>[]},
      ],
    },
    {
      'index': 2,
      'total': {'steps': 1, 'tokens': _tokens()},
      'steps': [
        {'index': 0, 'tokens': _tokens(), 'toolCallIds': <String>[]},
      ],
    },
  ],
};

void main() {
  late UsageAgent agent;
  late SessionHandle session;

  tearDown(() => agent.dispose());

  Future<void> connected(AgentCapabilities capabilities) async {
    agent = UsageAgent(capabilities: capabilities);
    await agent.start();
    session = await agent.newSession('s-1');
  }

  UsageLedgerState state() => session.current.usageLedger;

  Iterable<JsonRpcRequest> ledgerRequests(FakeAcpTransport on) => on
      .sentMessages
      .whereType<JsonRpcRequest>()
      .where((r) => r.method == _ledgerMethod);

  /// Запускает обновление и возвращает кадр запроса (подписка раньше вызова).
  Future<(Future<void>, JsonRpcRequest)> refresh({bool rebuild = false}) async {
    final frame = agent.next(_ledgerMethod);
    final done = agent.workspace.refreshUsageLedger(_sid, rebuild: rebuild);
    return (done, await frame);
  }

  group('availability', () {
    test('an agent without usageLedger: no request, unavailable '
        '(scenario «Агент без журнала»)', () async {
      await connected(usageCapabilities);

      expect(state(), isA<UsageLedgerUnavailable>());
      await agent.workspace.refreshUsageLedger(_sid);
      await pumpEventQueue();

      expect(ledgerRequests(agent.transport), isEmpty);
      expect(state(), isA<UsageLedgerUnavailable>());
    });

    test('an agent that declared usageLedger starts idle', () async {
      await connected(_ledgerCapabilities);

      expect(state(), isA<UsageLedgerIdle>());
    });
  });

  group('loading', () {
    test('idle -> loading -> loaded with the ledger of the reply '
        '(scenario «Журнал загружен»)', () async {
      await connected(_ledgerCapabilities);
      final seen = <UsageLedgerState>[];
      final sub = session.view.listen((v) => seen.add(v.usageLedger));
      addTearDown(sub.cancel);

      final (done, request) = await refresh();
      expect(request.params, {'sessionId': 's-1'});
      expect(state(), isA<UsageLedgerLoading>());
      expect((state() as UsageLedgerLoading).previous, isNull);

      agent.respond(request, _ledger(seq: 12));
      await done;

      final loaded = state() as UsageLedgerLoaded;
      expect(loaded.view.seq, 12);
      expect(loaded.view.turns, hasLength(2));
      expect(loaded.view.turns.first.steps, hasLength(2));
      expect(loaded.view.turns.first.steps.first.toolCallIds, ['c1']);
      expect(loaded.view.total.cost!.micros, 500000);
      expect(seen.first, isA<UsageLedgerLoading>());
      expect(seen.last, isA<UsageLedgerLoaded>());
      final requested = agent.logger.where('usage.ledger.requested').single;
      expect(requested.level, 'debug');
      expect(requested.context['session_id'], 's-1');
      expect(requested.context['rebuild'], false);
      final received = agent.logger.where('usage.ledger.received').single;
      expect(received.context['seq'], 12);
      expect(received.context['turns'], 2);
    });

    test('a second refresh shows loading with the previous ledger', () async {
      await connected(_ledgerCapabilities);
      var (done, request) = await refresh();
      agent.respond(request, _ledger(seq: 1));
      await done;

      (done, request) = await refresh(rebuild: true);

      expect(request.params, {'sessionId': 's-1', 'rebuild': true});
      final loading = state() as UsageLedgerLoading;
      expect(loading.previous!.seq, 1);
      agent.respond(request, _ledger(seq: 2));
      await done;
      expect((state() as UsageLedgerLoaded).view.seq, 2);
    });

    test('calls during a flight merge into one next request, rebuild wins '
        '(scenario «Слияние вызовов»)', () async {
      await connected(_ledgerCapabilities);
      final (first, request) = await refresh();
      final second = agent.workspace.refreshUsageLedger(_sid);
      final third = agent.workspace.refreshUsageLedger(_sid, rebuild: true);
      await pumpEventQueue();
      expect(ledgerRequests(agent.transport), hasLength(1));

      final next = agent.next(_ledgerMethod);
      agent.respond(request, _ledger(seq: 1));
      final merged = await next;

      expect(merged.params, {'sessionId': 's-1', 'rebuild': true});
      agent.respond(merged, _ledger(seq: 2));
      await Future.wait([first, second, third]);

      expect(ledgerRequests(agent.transport), hasLength(2));
      expect((state() as UsageLedgerLoaded).view.seq, 2);
    });

    test('rebuild wins in the opposite order too: true first, then false '
        '(scenario «Слияние вызовов»)', () async {
      await connected(_ledgerCapabilities);
      final (first, request) = await refresh();
      final second = agent.workspace.refreshUsageLedger(_sid, rebuild: true);
      final third = agent.workspace.refreshUsageLedger(_sid);
      await pumpEventQueue();
      expect(ledgerRequests(agent.transport), hasLength(1));

      final next = agent.next(_ledgerMethod);
      agent.respond(request, _ledger(seq: 1));
      final merged = await next;

      expect(merged.params, {'sessionId': 's-1', 'rebuild': true});
      agent.respond(merged, _ledger(seq: 2));
      await Future.wait([first, second, third]);

      expect(ledgerRequests(agent.transport), hasLength(2));
      expect((state() as UsageLedgerLoaded).view.seq, 2);
    });

    test('a merged call is dropped when the connection changed: reconnect to '
        'an agent without usageLedger gives unavailable, no frame '
        '(review: re-check before the merged request)', () async {
      await connected(_ledgerCapabilities);
      final seen = <UsageLedgerState>[];
      final sub = session.view.listen((v) => seen.add(v.usageLedger));
      addTearDown(sub.cancel);
      final (first, _) = await refresh();
      unawaited(first.then((_) {}, onError: (_) {}));
      final second = agent.workspace.refreshUsageLedger(_sid);

      agent.restartAgent(capabilities: usageLoadCapabilities);
      final load = agent.next(sessionLoadMethod);
      final reconnecting = agent.workspace.reconnect();
      agent.respond(await load, const <String, Object?>{});
      await reconnecting;
      await second;
      await pumpEventQueue();

      expect(state(), isA<UsageLedgerUnavailable>());
      expect(ledgerRequests(agent.transport), isEmpty);
      // Ни `failed`, ни записи об отказе: слитый вызов не доходит до запроса.
      expect(seen.whereType<UsageLedgerFailed>(), isEmpty);
      expect(agent.logger.where('usage.ledger.failed'), isEmpty);
    });

    test('a merged call of the old connection is dropped after reconnect to '
        'an agent with usageLedger: idle, no frame', () async {
      await connected(_ledgerCapabilities);
      final (first, _) = await refresh();
      unawaited(first.then((_) {}, onError: (_) {}));
      final second = agent.workspace.refreshUsageLedger(_sid);

      agent.restartAgent(capabilities: _ledgerCapabilities);
      final load = agent.next(sessionLoadMethod);
      final reconnecting = agent.workspace.reconnect();
      agent.respond(await load, const <String, Object?>{});
      await reconnecting;
      await second;
      await pumpEventQueue();

      expect(state(), isA<UsageLedgerIdle>());
      expect(ledgerRequests(agent.transport), isEmpty);
    });

    test('a merged call after dispose sends no frame and completes', () async {
      await connected(_ledgerCapabilities);
      final (first, request) = await refresh();
      final second = agent.workspace.refreshUsageLedger(_sid);
      unawaited(first.then((_) {}, onError: (_) {}));

      await agent.workspace.dispose();
      agent.respond(request, _ledger(seq: 1));
      await second;
      await pumpEventQueue();

      expect(ledgerRequests(agent.transport), hasLength(1));
    });

    test('a call for an unknown session fails with ClientWorkspaceException '
        'and sends no frame (scenario «Журнал неизвестной сессии»)', () async {
      await connected(_ledgerCapabilities);

      await expectLater(
        agent.workspace.refreshUsageLedger(const SessionId('ghost')),
        throwsA(isA<ClientWorkspaceException>()),
      );
      await pumpEventQueue();

      expect(ledgerRequests(agent.transport), isEmpty);
    });
  });

  group('stale replies (D10, §9)', () {
    test('a reply after reconnect is dropped, usage.ledger.stale, state is '
        'idle (scenario «Ответ старого соединения»)', () async {
      await connected(_ledgerCapabilities);
      final (done, _) = await refresh();
      unawaited(done.then((_) {}, onError: (_) {}));

      agent.restartAgent(capabilities: _ledgerCapabilities);
      final load = agent.next(sessionLoadMethod);
      final reconnecting = agent.workspace.reconnect();
      agent.respond(await load, const <String, Object?>{});
      await reconnecting;
      await pumpEventQueue();

      // Старый транспорт закрыт, ответ по нему прийти не может: ожидавший
      // запрос завершается ошибкой замены соединения и считается устаревшим.
      expect(state(), isA<UsageLedgerIdle>());
      final stale = agent.logger.where('usage.ledger.stale').single;
      expect(stale.level, 'debug');
      expect(stale.context['session_id'], 's-1');
      // Только корреляция, без данных ответа (§16).
      expect(
        stale.context.keys.toSet().intersection({'seq', 'turns', 'result'}),
        isEmpty,
      );
    });

    test('a reply after session/load of the same session is dropped', () async {
      await connected(_ledgerCapabilities);
      final (done, request) = await refresh();
      unawaited(done.then((_) {}, onError: (_) {}));

      final load = agent.next(sessionLoadMethod);
      final loading = agent.workspace.loadSession(_sid, cwd: '/work');
      agent.respond(await load, const <String, Object?>{});
      await loading;
      agent.respond(request, _ledger(seq: 9));
      await pumpEventQueue();

      expect(state(), isA<UsageLedgerIdle>());
      expect(agent.logger.where('usage.ledger.stale'), hasLength(1));
    });
  });

  group('failures', () {
    for (final code in [-32002, -32601]) {
      test('agent error $code: failed with the code, WARNING '
          'usage.ledger.failed (scenario «Ошибка агента»)', () async {
        await connected(_ledgerCapabilities);
        final (done, request) = await refresh();

        agent.transport.emitInbound(
          JsonRpcMessage.response(
            id: request.id,
            error: JsonRpcError(code: code, message: 'no'),
          ),
        );
        await done;

        final failed = state() as UsageLedgerFailed;
        expect(failed.reason.kind, UsageLedgerFailureKind.agentError);
        expect(failed.reason.code, code);
        expect(failed.previous, isNull);
        final entry = agent.logger.where('usage.ledger.failed').single;
        expect(entry.level, 'warning');
        expect(entry.context['session_id'], 's-1');
        expect(entry.context['code'], code);
      });
    }

    test('failed keeps the previous ledger', () async {
      await connected(_ledgerCapabilities);
      var (done, request) = await refresh();
      agent.respond(request, _ledger(seq: 3));
      await done;

      (done, request) = await refresh();
      agent.transport.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          error: JsonRpcError(code: -32002, message: 'gone'),
        ),
      );
      await done;

      expect((state() as UsageLedgerFailed).previous!.seq, 3);
    });

    test('a reply that does not decode: failed(decode), the warning is '
        'logged once per session and field', () async {
      await connected(_ledgerCapabilities);
      for (var i = 0; i < 2; i++) {
        final (done, request) = await refresh();
        agent.respond(request, <String, Object?>{'sessionId': 's-1'});
        await done;
      }

      expect(
        (state() as UsageLedgerFailed).reason.kind,
        UsageLedgerFailureKind.decode,
      );
      final warnings = agent.logger.where('usage.ledger.decode_failed');
      expect(warnings, hasLength(greaterThanOrEqualTo(1)));
      expect(warnings.every((w) => w.level == 'warning'), isTrue);
      // Одно предупреждение на сессию и поле, а не на ответ.
      final fields = warnings.map((w) => w.context['field']).toList();
      expect(fields.toSet(), hasLength(fields.length));
      expect(warnings.first.context['session_id'], 's-1');
    });

    test('a reply for another session is failed(decode) with a mismatch '
        'warning without the value', () async {
      await connected(_ledgerCapabilities);
      final (done, request) = await refresh();

      agent.respond(request, _ledger(seq: 4, sessionId: 'other-session'));
      await done;

      final failed = state() as UsageLedgerFailed;
      expect(failed.reason.kind, UsageLedgerFailureKind.decode);
      final warning = agent.logger.where('usage.ledger.decode_failed').single;
      expect(warning.level, 'warning');
      expect(warning.context['field'], 'sessionId');
      expect(warning.context['reason'], 'mismatch');
      expect(
        warning.context.values.map((v) => '$v'),
        everyElement(isNot(contains('other-session'))),
      );
    });

    test(
      'a reply that is not an object is failed(decode), not request',
      () async {
        await connected(_ledgerCapabilities);
        final (done, request) = await refresh();

        agent.respond(request, const <Object?>[1, 2]);
        await done;

        expect(
          (state() as UsageLedgerFailed).reason.kind,
          UsageLedgerFailureKind.decode,
        );
      },
    );
  });

  group('reset', () {
    test('reconnect resets a loaded ledger to idle', () async {
      await connected(_ledgerCapabilities);
      final (done, request) = await refresh();
      agent.respond(request, _ledger());
      await done;

      agent.restartAgent(capabilities: _ledgerCapabilities);
      final load = agent.next(sessionLoadMethod);
      final reconnecting = agent.workspace.reconnect();
      agent.respond(await load, const <String, Object?>{});
      await reconnecting;

      expect(state(), isA<UsageLedgerIdle>());
    });

    test(
      'reconnect to an agent without usageLedger gives unavailable',
      () async {
        await connected(_ledgerCapabilities);
        final (done, request) = await refresh();
        agent.respond(request, _ledger());
        await done;

        agent.restartAgent(capabilities: usageLoadCapabilities);
        final load = agent.next(sessionLoadMethod);
        final reconnecting = agent.workspace.reconnect();
        agent.respond(await load, const <String, Object?>{});
        await reconnecting;

        expect(state(), isA<UsageLedgerUnavailable>());
      },
    );

    test('session/load resets a loaded ledger to idle', () async {
      await connected(_ledgerCapabilities);
      final (done, request) = await refresh();
      agent.respond(request, _ledger());
      await done;

      final load = agent.next(sessionLoadMethod);
      final loading = agent.workspace.loadSession(_sid, cwd: '/work');
      agent.respond(await load, const <String, Object?>{});
      await loading;

      expect(state(), isA<UsageLedgerIdle>());
    });
  });
}
