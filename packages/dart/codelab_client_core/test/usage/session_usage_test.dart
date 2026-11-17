// Свёртка usage в `SessionView.usage` (задача 2.5 change
// `add-usage-extension`; spec acp-client-kit «Usage сессии»: «Агент без
// расширения», «Два хода», «Дубль и опоздание», «Деньги без накопления
// ошибки», «Скорое сжатие», «Переподключение»; VIEW-6; design.md, D7, D8,
// D14, D21 Т2, Т4, Т5).
//
// Красные тесты: `SessionView.usage`, `UsageView`, `UsageSupport`,
// `UsagePartial` и необязательный `Logger` у `ClientWorkspace` ещё нет
// (задача 2.9); `AcpClientApplication.usageNotifications` — задача 2.8.
// Файл не компилируется. Событий журнала D14 в этом тесте три:
// `usage.stale {session_id, seq, last_seq}` (DEBUG),
// `usage.decode_failed {session_id, field, reason}` (WARNING, не чаще раза
// на сессию и поле) и DEBUG об отбросе снимка неизвестной сессии
// (`context['session_id']`; имя события — на усмотрение 2.9).
//
// Гонки собраны принудительным порядком кадров на `FakeAcpTransport`, без
// таймеров.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/usage_agent.dart';

void main() {
  late UsageAgent agent;

  tearDown(() => agent.dispose());

  Future<SessionHandle> connected(
    AgentCapabilities capabilities, [
    String id = 's-1',
  ]) async {
    agent = UsageAgent(capabilities: capabilities);
    await agent.start();
    return agent.newSession(id);
  }

  group('support', () {
    test('an agent without the extension: unknown, no numbers, not zeros '
        '(scenario «Агент без расширения», VIEW-6)', () async {
      final session = await connected(const AgentCapabilities());

      final usage = session.current.usage;
      expect(usage.support, UsageSupport.unknown);
      expect(usage.lastTurn, isNull);
      expect(usage.session, isNull);
      expect(usage.context, isNull);
      expect(usage.lastSeq, 0);
    });

    test(
      'an agent that declared usage: awaiting until the first snapshot',
      () async {
        final session = await connected(usageCapabilities);

        expect(session.current.usage.support, UsageSupport.awaiting);

        agent.usage(usageParams(sessionId: 's-1', seq: 1));

        expect(session.current.usage.support, UsageSupport.reported);
      },
    );

    test(
      'a snapshot from an agent that did not declare usage is still '
      'applied (D3: the declaration only picks the pre-snapshot text)',
      () async {
        final session = await connected(const AgentCapabilities());

        agent.usage(usageParams(sessionId: 's-1', seq: 1));

        expect(session.current.usage.support, UsageSupport.reported);
        expect(session.current.usage.session!.tokens.input, 100);
      },
    );
  });

  group('folding', () {
    test('two turns: lastTurn is the last turn, session is the last sum '
        '(scenario «Два хода»)', () async {
      final session = await connected(usageCapabilities);

      agent.usage(
        usageParams(
          sessionId: 's-1',
          seq: 1,
          turnId: 'A',
          turnTokens: 100,
          sessionTokens: 100,
          turnMicros: 1000,
          sessionMicros: 1000,
        ),
      );
      agent.usage(
        usageParams(
          sessionId: 's-1',
          seq: 2,
          turnId: 'B',
          turnTokens: 40,
          sessionTokens: 140,
          turnMicros: 500,
          sessionMicros: 1500,
        ),
      );

      final usage = session.current.usage;
      expect(usage.support, UsageSupport.reported);
      expect(usage.lastTurn!.tokens.input, 40);
      expect(usage.lastTurn!.cost!.micros, 500);
      expect(usage.session!.tokens.input, 140);
      expect(usage.session!.cost!.micros, 1500);
      expect(usage.lastSeq, 2);
    });

    test('a compaction snapshot (no turnId) changes only session and '
        'context', () async {
      final session = await connected(usageCapabilities);
      agent.usage(usageParams(sessionId: 's-1', seq: 1, turnId: 'A'));

      agent.usage(
        usageParams(
          sessionId: 's-1',
          seq: 2,
          trigger: 'compaction',
          turnId: null,
          sessionTokens: 250,
          sessionMicros: 2500,
          context: {'used': 90000, 'size': 200000},
        ),
      );

      final usage = session.current.usage;
      expect(usage.lastTurn!.tokens.input, 100, reason: 'ход A не заменён');
      expect(usage.session!.tokens.input, 250);
      expect(usage.context!.used, 90000);
    });

    test(
      'seq 3, 5, 4, 5: only 3 and 5 are applied, lastSeq is 5 and a '
      'dropped snapshot makes no revision (scenario «Дубль и опоздание»)',
      () async {
        final session = await connected(usageCapabilities);

        agent.usage(usageParams(sessionId: 's-1', seq: 3, sessionTokens: 30));
        final afterThree = session.current.revision;
        agent.usage(usageParams(sessionId: 's-1', seq: 5, sessionTokens: 50));
        final afterFive = session.current.revision;
        expect(afterFive, afterThree + 1, reason: 'одна ревизия на снимок');

        agent.usage(usageParams(sessionId: 's-1', seq: 4, sessionTokens: 40));
        agent.usage(usageParams(sessionId: 's-1', seq: 5, sessionTokens: 99));

        final usage = session.current.usage;
        expect(usage.lastSeq, 5);
        expect(usage.session!.tokens.input, 50);
        expect(session.current.revision, afterFive);
        final stale = agent.logger.where('usage.stale').toList();
        expect(stale, hasLength(2));
        expect(stale.first.level, 'debug');
        expect(stale.first.context['seq'], 4);
        expect(stale.first.context['last_seq'], 5);
        expect(stale.last.context['seq'], 5);
        expect(stale.last.context['session_id'], 's-1');
      },
    );

    test('1 000 snapshots growing by "0.000001": the last equals its string '
        'exactly (scenario «Деньги без накопления ошибки»)', () async {
      final session = await connected(usageCapabilities);

      for (var i = 1; i <= 1000; i++) {
        agent.usage(usageParams(sessionId: 's-1', seq: i, sessionMicros: i));
      }

      expect(session.current.usage.session!.cost!.micros, 1000);
      expect(session.current.usage.lastSeq, 1000);
    });

    test(
      'compactionSoon follows compactAt (scenario «Скорое сжатие»)',
      () async {
        final session = await connected(usageCapabilities);

        agent.usage(
          usageParams(
            sessionId: 's-1',
            seq: 1,
            context: {'used': 168000, 'size': 200000, 'compactAt': 183616},
          ),
        );
        expect(session.current.usage.context!.compactionSoon, isTrue);

        agent.usage(
          usageParams(
            sessionId: 's-1',
            seq: 2,
            context: {'used': 168000, 'size': 200000},
          ),
        );
        expect(session.current.usage.context!.compactionSoon, isFalse);
        expect(session.current.usage.context!.fraction, 0.84);
      },
    );

    test('a partial reason set is translated and unknown ones are dropped '
        '(scenario «Причины неполноты»)', () async {
      final session = await connected(usageCapabilities);

      agent.usage(
        usageParams(
          sessionId: 's-1',
          seq: 1,
          partial: ['beforeLoad', 'future'],
        ),
      );

      expect(session.current.usage.session!.partial, {UsagePartial.beforeLoad});
    });

    test('a snapshot that does not decode changes nothing and makes no '
        'revision; the warning is logged once per session and field', () async {
      final session = await connected(usageCapabilities);
      agent.usage(usageParams(sessionId: 's-1', seq: 1));
      final revision = session.current.revision;

      // Без обязательного `session`: снимок отброшен целиком.
      agent.usage({'sessionId': 's-1', 'seq': 2, 'trigger': 'turn'});
      agent.usage({'sessionId': 's-1', 'seq': 3, 'trigger': 'turn'});

      expect(session.current.revision, revision);
      expect(session.current.usage.lastSeq, 1);
      final warnings = agent.logger.where('usage.decode_failed').toList();
      expect(warnings, isNotEmpty);
      expect(warnings.every((w) => w.level == 'warning'), isTrue);
      expect(warnings.first.context['session_id'], 's-1');
      // Не чаще раза на сессию и поле (D14).
      expect(warnings, hasLength(1));
    });

    test('a snapshot of an unknown session is dropped with a DEBUG entry and '
        'changes nothing', () async {
      final session = await connected(usageCapabilities);
      final revision = session.current.revision;
      final workspaceBefore = agent.workspace.current;

      agent.usage(usageParams(sessionId: 'ghost', seq: 1));

      expect(session.current.revision, revision);
      expect(session.current.usage.support, UsageSupport.awaiting);
      expect(agent.workspace.current, workspaceBefore);
      final entries = agent.logger.where('usage.unknown_session').toList();
      expect(entries, hasLength(1));
      expect(entries.single.level, 'debug');
      expect(entries.single.context['session_id'], 'ghost');
      expect(entries.single.context['connection_generation'], isA<int>());
    });

    test('usage.stale and usage.decode_failed carry connection_generation '
        '(D14)', () async {
      await connected(usageCapabilities);

      agent.usage(usageParams(sessionId: 's-1', seq: 2));
      agent.usage(usageParams(sessionId: 's-1', seq: 2));
      agent.usage({'sessionId': 's-1', 'seq': 3, 'trigger': 'turn'});

      expect(
        agent.logger
            .where('usage.stale')
            .single
            .context['connection_generation'],
        isA<int>(),
      );
      expect(
        agent.logger
            .where('usage.decode_failed')
            .first
            .context['connection_generation'],
        isA<int>(),
      );
    });

    test('a snapshot after workspace.dispose is not published and does not '
        'throw (TEST-005)', () async {
      final session = await connected(usageCapabilities);
      final revision = session.current.revision;
      final entries = agent.logger.entries.length;

      await agent.workspace.dispose();
      agent.usage(usageParams(sessionId: 's-1', seq: 1));

      expect(session.current.revision, revision);
      expect(session.current.usage.support, UsageSupport.awaiting);
      expect(agent.logger.entries.length, entries);
    });

    test('one SessionView revision per applied snapshot, observed on the '
        'view stream', () async {
      final session = await connected(usageCapabilities);
      final revisions = <int>[];
      final subscription = session.view.listen(
        (view) => revisions.add(view.revision),
      );
      addTearDown(subscription.cancel);

      agent.usage(usageParams(sessionId: 's-1', seq: 1));
      agent.usage(usageParams(sessionId: 's-1', seq: 1)); // дубль
      agent.usage(usageParams(sessionId: 's-1', seq: 2));

      expect(revisions, hasLength(2));
      expect(revisions[1], revisions[0] + 1);
    });
  });

  group('connection change and session/load', () {
    test('reconnect resets usage; a new agent starting from seq 1 is '
        'applied (scenario «Переподключение»)', () async {
      final session = await connected(usageLoadCapabilities);
      agent.usage(usageParams(sessionId: 's-1', seq: 9, sessionTokens: 900));
      expect(session.current.usage.lastSeq, 9);

      agent.restartAgent(capabilities: usageLoadCapabilities);
      final load = agent.next(sessionLoadMethod);
      final reconnecting = agent.workspace.reconnect();
      agent.respond(await load, const <String, Object?>{});
      await reconnecting;

      expect(session.current.usage.support, UsageSupport.awaiting);
      expect(session.current.usage.session, isNull);
      expect(session.current.usage.lastSeq, 0);

      agent.usage(usageParams(sessionId: 's-1', seq: 1, sessionTokens: 7));

      expect(session.current.usage.lastSeq, 1);
      expect(session.current.usage.session!.tokens.input, 7);
    });

    test('a snapshot of the old agent that arrives after reconnect began but '
        'before the transport is replaced does not block seq 1 of the new '
        'agent (D21 Т2)', () async {
      final session = await connected(usageLoadCapabilities);
      agent.usage(usageParams(sessionId: 's-1', seq: 9));

      agent.restartAgent(capabilities: usageLoadCapabilities);
      // `suspend` сессий уже прошёл, поколение ещё прежнее: кадр старого
      // агента приходит ровно в этом окне.
      agent.beforeOpen = (previous) => agent.usage(
        usageParams(sessionId: 's-1', seq: 10, sessionTokens: 1000),
        on: previous,
      );
      final load = agent.next(sessionLoadMethod);
      final reconnecting = agent.workspace.reconnect();
      agent.respond(await load, const <String, Object?>{});
      await reconnecting;
      agent.beforeOpen = null;

      agent.usage(usageParams(sessionId: 's-1', seq: 1, sessionTokens: 7));

      expect(session.current.usage.lastSeq, 1);
      expect(session.current.usage.session!.tokens.input, 7);
    });

    test('a detached session after reconnect is reset too', () async {
      // Новый агент не умеет `loadSession`: сессия становится detached.
      final session = await connected(usageLoadCapabilities);
      agent.usage(usageParams(sessionId: 's-1', seq: 9));

      agent.restartAgent(capabilities: usageCapabilities);
      await agent.workspace.reconnect();

      expect(session.current.status, SessionStatusView.detached);
      expect(session.current.usage.support, UsageSupport.awaiting);
      expect(session.current.usage.session, isNull);
      expect(session.current.usage.lastSeq, 0);
    });

    test(
      'reconnect to an agent that did not declare usage gives unknown',
      () async {
        final session = await connected(usageLoadCapabilities);
        agent.usage(usageParams(sessionId: 's-1', seq: 9));

        agent.restartAgent(capabilities: const AgentCapabilities());
        await agent.workspace.reconnect();

        expect(session.current.usage.support, UsageSupport.unknown);
        expect(session.current.usage.session, isNull);
      },
    );

    test('session/load of an open session resets its usage', () async {
      final session = await connected(usageLoadCapabilities);
      agent.usage(usageParams(sessionId: 's-1', seq: 5));
      expect(session.current.usage.lastSeq, 5);

      final load = agent.next(sessionLoadMethod);
      final loading = agent.workspace.loadSession(
        const SessionId('s-1'),
        cwd: '/work',
      );
      agent.respond(await load, const <String, Object?>{});
      await loading;

      expect(session.current.usage.support, UsageSupport.awaiting);
      expect(session.current.usage.lastSeq, 0);

      agent.usage(usageParams(sessionId: 's-1', seq: 1));
      expect(session.current.usage.lastSeq, 1);
    });
  });

  // Снимок `trigger: "load"` после ответа на `session/load` (change
  // `add-usage-ledger`, D8, D10; spec acp-client-kit «Usage сессии»: «Снимок
  // load после загрузки», «Снимок load до регистрации сессии», «Загрузка
  // сорвалась»). Порядок между потоком сессий и потоком уведомлений ядра
  // клиента не гарантирован (`AGENTS.md` §9), поэтому кадр уведомления
  // отправляется синхронно сразу за ответом, до любого ожидания: kit
  // обрабатывает его раньше обновления сессии по ответу. Без таймеров.
  group('the load snapshot (add-usage-ledger, D10)', () {
    /// Параметры снимка `load`: без `turnId`, агрегат сессии.
    Map<String, Object?> loadParams(
      String sessionId, {
      int seq = 1,
      int tokens = 777,
    }) => usageParams(
      sessionId: sessionId,
      seq: seq,
      trigger: 'load',
      turnId: null,
      sessionTokens: tokens,
      sessionMicros: 4200,
    );

    test('trigger load is a known trigger (UsageTrigger.load)', () {
      final snapshot = const UsageDecoder().decode(
        loadParams('s-1'),
        onWarning: (_, _) {},
      )!;

      expect(snapshot.trigger, UsageTrigger.load);
      expect(snapshot.turnId, isNull);
    });

    test('a load snapshot changes session and context, lastTurn stays '
        '(scenario «Снимок load после загрузки»)', () async {
      final session = await connected(usageLoadCapabilities);
      agent.usage(usageParams(sessionId: 's-1', seq: 1, turnId: 'A'));

      agent.usage(
        usageParams(
          sessionId: 's-1',
          seq: 2,
          trigger: 'load',
          turnId: null,
          sessionTokens: 300,
          context: {'used': 5, 'size': 100},
        ),
      );

      final usage = session.current.usage;
      expect(usage.lastTurn!.tokens.input, 100, reason: 'ход A не заменён');
      expect(usage.session!.tokens.input, 300);
      expect(usage.context!.used, 5);
    });

    test('reattach: the snapshot handled before the session update by the '
        'response is not wiped by the load reset', () async {
      final session = await connected(usageLoadCapabilities);
      agent.usage(usageParams(sessionId: 's-1', seq: 5, sessionTokens: 50));

      final load = agent.next(sessionLoadMethod);
      final loading = agent.workspace.loadSession(
        const SessionId('s-1'),
        cwd: '/work',
      );
      agent.respond(await load, const <String, Object?>{});
      // Сразу за ответом, в том же синхронном отрезке.
      agent.usage(loadParams('s-1', seq: 6));
      await loading;
      await pumpEventQueue();

      final usage = session.current.usage;
      expect(usage.support, UsageSupport.reported);
      expect(usage.session!.tokens.input, 777);
      expect(usage.session!.cost!.micros, 4200);
      expect(usage.lastTurn, isNull);
      expect(usage.lastSeq, 6);
    });

    test('reattach: the order «update by the response, then snapshot» keeps '
        'working', () async {
      final session = await connected(usageLoadCapabilities);
      agent.usage(usageParams(sessionId: 's-1', seq: 5));

      final load = agent.next(sessionLoadMethod);
      final loading = agent.workspace.loadSession(
        const SessionId('s-1'),
        cwd: '/work',
      );
      agent.respond(await load, const <String, Object?>{});
      await loading;
      agent.usage(loadParams('s-1', seq: 6));

      expect(session.current.usage.session!.tokens.input, 777);
      expect(session.current.usage.lastSeq, 6);
    });

    test('first load of a listed session: the snapshot waits for the '
        'registration, no usage.unknown_session '
        '(scenario «Снимок load до регистрации сессии»)', () async {
      await connected(usageLoadCapabilities);

      final load = agent.next(sessionLoadMethod);
      final loading = agent.workspace.loadSession(
        const SessionId('listed-1'),
        cwd: '/work',
      );
      agent.respond(await load, const <String, Object?>{});
      agent.usage(loadParams('listed-1'));
      final session = await loading;
      await pumpEventQueue();

      final usage = session.current.usage;
      expect(usage.support, UsageSupport.reported);
      expect(usage.session!.tokens.input, 777);
      expect(usage.lastTurn, isNull);
      expect(agent.logger.where('usage.unknown_session'), isEmpty);
    });

    test('a snapshot that waits keeps only the latest by seq', () async {
      await connected(usageLoadCapabilities);

      final load = agent.next(sessionLoadMethod);
      final loading = agent.workspace.loadSession(
        const SessionId('listed-1'),
        cwd: '/work',
      );
      agent.usage(loadParams('listed-1', seq: 2, tokens: 20));
      agent.usage(loadParams('listed-1', seq: 4, tokens: 40));
      agent.usage(loadParams('listed-1', seq: 3, tokens: 30));
      agent.respond(await load, const <String, Object?>{});
      final session = await loading;

      expect(session.current.usage.session!.tokens.input, 40);
      expect(session.current.usage.lastSeq, 4);
    });

    test('a failed load: the waiting snapshot is dropped with '
        'usage.unknown_session and the workspace is unchanged '
        '(scenario «Загрузка сорвалась»)', () async {
      await connected(usageLoadCapabilities);
      final before = agent.workspace.current;

      final load = agent.next(sessionLoadMethod);
      final loading = agent.workspace.loadSession(
        const SessionId('listed-1'),
        cwd: '/work',
      );
      final failure = expectLater(loading, throwsA(anything));
      agent.usage(loadParams('listed-1'));
      // Пока загрузка идёт, снимок только ждёт: отброса ещё нет.
      final whileLoading = agent.logger.where('usage.unknown_session').length;
      agent.transport.emitInbound(
        JsonRpcMessage.response(
          id: (await load).id,
          error: JsonRpcError(code: -32002, message: 'Session not found'),
        ),
      );
      await failure;
      await pumpEventQueue();

      expect(whileLoading, 0, reason: 'до исхода загрузки снимок ждёт');
      final dropped = agent.logger.where('usage.unknown_session').single;
      expect(dropped.level, 'debug');
      expect(dropped.context['session_id'], 'listed-1');
      expect(dropped.context['connection_generation'], isA<int>());
      expect(agent.workspace.session(const SessionId('listed-1')), isNull);
      expect(agent.workspace.current.sessions, before.sessions);
    });

    test('a failed reload of an open session leaves the reset in place: the '
        'old numbers do not come back, the ledger is idle '
        '(R10, «Сорвавшаяся загрузка открытой сессии»)', () async {
      final session = await connected(
        const AgentCapabilities(
          loadSession: true,
          meta: {
            'codelab': {
              'usage': {'version': 1},
              'usageLedger': {'version': 1},
            },
          },
        ),
      );
      agent.usage(usageParams(sessionId: 's-1', seq: 5, sessionTokens: 50));
      expect(session.current.usage.support, UsageSupport.reported);

      final load = agent.next(sessionLoadMethod);
      final loading = agent.workspace.loadSession(
        const SessionId('s-1'),
        cwd: '/work',
      );
      final failure = expectLater(loading, throwsA(anything));
      agent.transport.emitInbound(
        JsonRpcMessage.response(
          id: (await load).id,
          error: JsonRpcError(code: -32002, message: 'Session not found'),
        ),
      );
      await failure;
      await pumpEventQueue();

      final usage = session.current.usage;
      expect(usage.support, UsageSupport.awaiting);
      expect(usage.session, isNull);
      expect(usage.lastSeq, 0);
      expect(session.current.usageLedger, isA<UsageLedgerIdle>());
    });

    test('a snapshot of a session that is not loading is still dropped at '
        'once', () async {
      await connected(usageLoadCapabilities);

      agent.usage(loadParams('ghost'));

      expect(agent.logger.where('usage.unknown_session'), hasLength(1));
    });
  });
}
