// Типизированная причина заметки транскрипта (задача 3.1 change
// `add-desktop-localization`; spec acp-client-kit «Типизированная причина
// заметки транскрипта»; design D6).
//
// Красные тесты: поле `NoticeItem.reason` и типы `NoticeReason` пока
// заглушки (задача 3.2 заполняет их в `TranscriptProjector` и
// `ClientWorkspace`), поэтому тесты компилируются и падают на `expect`
// причины, а не на компиляции. Поле `text` не меняется: его значения
// проверяют существующие тесты и сценарий «CLI не меняется».

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_core/src/transcript/transcript_projector.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

const _withLoad = AgentCapabilities(loadSession: true);

void main() {
  group('turn notices', () {
    late FakeAcpTransport transport;
    late AcpClientApplication application;
    late TranscriptProjector projector;
    const session = SessionId('s-1');

    setUp(() async {
      transport = FakeAcpTransport();
      application = AcpClientApplication(transport: FakeAcpTransport());
      projector = TranscriptProjector();
      final subscription = application.sessionChanges.listen(projector.apply);
      addTearDown(() async {
        await subscription.cancel();
        await application.dispose();
      });
      await application.connect(transport);
      final request = _next(transport, sessionNewMethod);
      final created = application.createSession(
        const CreateSessionCommand(cwd: '/work'),
      );
      transport.emitInbound(
        JsonRpcMessage.response(
          id: (await request).id,
          result: {'sessionId': session.value},
        ),
      );
      await created;
    });

    /// Живой ход, завершённый ответом [result]; [output] — вывод агента.
    Future<List<NoticeItem>> turn(
      Map<String, Object?> result, {
      bool output = true,
    }) async {
      final requested = _next(transport, sessionPromptMethod);
      final done = application.sendPrompt(
        const SendPromptCommand(
          sessionId: session,
          prompt: [ContentBlock.text(text: 'go')],
        ),
      );
      final request = await requested;
      if (output) {
        transport.emitInbound(
          JsonRpcMessage.notification(
            method: sessionUpdateMethod,
            params: {
              'sessionId': session.value,
              'update': {
                'sessionUpdate': 'agent_message_chunk',
                'content': {'type': 'text', 'text': 'partial'},
              },
            },
          ),
        );
      }
      transport.emitInbound(
        JsonRpcMessage.response(id: request.id, result: result),
      );
      await done;
      return projector.items.whereType<NoticeItem>().toList();
    }

    Map<String, Object?> maxTurn(Object? limit) => {
      'stopReason': 'max_turn_requests',
      '_meta': {
        'codelab': {'budgetExceeded': limit},
      },
    };

    for (final (wire, stop) in [
      ('max_tokens', StopReason.maxTokens),
      ('refusal', StopReason.refusal),
    ]) {
      test('$wire: turnStopped carries the stop reason, no limit', () async {
        final notice = (await turn({'stopReason': wire})).single;

        expect(notice.kind, NoticeKind.turnStopped);
        expect(notice.reason, TurnStoppedReason(stop));
      });
    }

    test('max_turn_requests with a known limit names the limit and keeps '
        'the text', () async {
      final notice = (await turn(maxTurn('tokens'))).single;

      expect(
        notice.reason,
        const TurnStoppedReason(
          StopReason.maxTurnRequests,
          budgetLimit: 'tokens',
        ),
      );
      expect(notice.text, 'The turn stopped: budget exceeded: tokens.');
    });

    test('max_turn_requests without a limit has no limit name', () async {
      final notice = (await turn({'stopReason': 'max_turn_requests'})).single;

      expect(
        notice.reason,
        const TurnStoppedReason(StopReason.maxTurnRequests),
      );
    });

    test('an unknown limit gives a reason without the limit name, as the '
        'text does', () async {
      final notice = (await turn(maxTurn('gpu_hours'))).single;

      expect(
        notice.reason,
        const TurnStoppedReason(StopReason.maxTurnRequests),
      );
      expect(notice.text, 'The turn reached the limit of model requests.');
    });

    test('emptyTurn carries the stop reason of the turn', () async {
      final notice = (await turn({
        'stopReason': 'end_turn',
      }, output: false)).single;

      expect(notice.kind, NoticeKind.emptyTurn);
      expect(notice.reason, const EmptyTurnReason(StopReason.endTurn));
      expect(notice.text, 'Completed with stopReason endTurn.');
    });

    test('emptyTurn of a replayed turn has no stop reason', () async {
      final request = _next(transport, sessionLoadMethod);
      final loading = application.loadSession(
        const LoadSessionCommand(sessionId: SessionId('s-2'), cwd: '/work'),
      );
      final sent = await request;
      transport
        ..emitInbound(
          JsonRpcMessage.notification(
            method: sessionUpdateMethod,
            params: {
              'sessionId': 's-2',
              'update': {
                'sessionUpdate': 'user_message_chunk',
                'content': {'type': 'text', 'text': 'hello'},
              },
            },
          ),
        )
        ..emitInbound(
          JsonRpcMessage.response(
            id: sent.id,
            result: const <String, Object?>{},
          ),
        );
      await loading;

      final notice = projector.items.whereType<NoticeItem>().single;
      expect(notice.kind, NoticeKind.emptyTurn);
      expect(notice.reason, const EmptyTurnReason(null));
      expect(notice.text, 'Completed with stopReason unknown.');
    });

    test(
      'incremental projection and a full rebuild give equal reasons',
      () async {
        await turn(maxTurn('cost'));
        await turn({'stopReason': 'refusal'});
        await turn({'stopReason': 'end_turn'}, output: false);

        final rebuilt = projectTranscript(application.sessionById(session)!);
        List<NoticeReason?> reasons(List<TranscriptItem> items) => [
          for (final notice in items.whereType<NoticeItem>()) notice.reason,
        ];
        expect(reasons(projector.items), [
          const TurnStoppedReason(
            StopReason.maxTurnRequests,
            budgetLimit: 'cost',
          ),
          const TurnStoppedReason(StopReason.refusal),
          const EmptyTurnReason(StopReason.endTurn),
        ]);
        expect(reasons(rebuilt), reasons(projector.items));
      },
    );
  });

  group('session restore notices', () {
    late KitAgent agent;

    tearDown(() => agent.dispose());

    NoticeItem lastNotice(SessionHandle handle) =>
        handle.current.transcript.whereType<NoticeItem>().last;

    test(
      'an agent without loadSession: detached, agent cannot restore',
      () async {
        agent = KitAgent(capabilities: _withLoad);
        await agent.start();
        final handle = await agent.newSession('s-a');

        agent.restartAgent();
        await agent.workspace.reconnect();

        final notice = lastNotice(handle);
        expect(notice.kind, NoticeKind.detached);
        expect(
          notice.reason,
          const SessionRestoreReason(SessionRestoreCause.agentCannotRestore),
        );
        expect(
          notice.text,
          'The agent cannot restore sessions after reconnecting.',
        );
      },
    );

    test(
      'a failed session/load: detached, restore failed with the id',
      () async {
        agent = KitAgent(capabilities: _withLoad);
        await agent.start();
        final handle = await agent.newSession('s-a');

        agent.restartAgent(capabilities: _withLoad);
        final load = agent.next(sessionLoadMethod);
        final reconnecting = agent.workspace.reconnect();
        agent.fail(await load, 'Resource not found');
        await reconnecting;

        final notice = lastNotice(handle);
        expect(notice.kind, NoticeKind.detached);
        expect(
          notice.reason,
          const SessionRestoreReason(
            SessionRestoreCause.restoreFailed,
            sessionId: SessionId('s-a'),
          ),
        );
        expect(
          notice.text,
          'Session s-a could not be restored after reconnecting.',
        );
      },
    );

    test(
      'restart without loadSession: reconnected, agent cannot restore',
      () async {
        final store = InMemoryWorkspaceSnapshotStore(_snapshot);
        agent = KitAgent(snapshots: store);
        await agent.workspace.restoreProject();

        final create = agent.next(sessionNewMethod);
        final connecting = agent.start();
        agent.respond(await create, {'sessionId': 's-new'});
        await connecting;

        final notice = lastNotice(
          agent.workspace.session(const SessionId('s-new'))!,
        );
        expect(notice.kind, NoticeKind.reconnected);
        expect(
          notice.reason,
          const SessionRestoreReason(SessionRestoreCause.agentCannotRestore),
        );
      },
    );

    test('restart with a failed session/load: reconnected, restore failed '
        'with the old id', () async {
      final store = InMemoryWorkspaceSnapshotStore(_snapshot);
      agent = KitAgent(capabilities: _withLoad, snapshots: store);
      await agent.workspace.restoreProject();

      final load = agent.next(sessionLoadMethod);
      final create = agent.next(sessionNewMethod);
      final connecting = agent.start();
      agent.fail(await load, 'Resource not found');
      agent.respond(await create, {'sessionId': 's-new'});
      await connecting;

      final notice = lastNotice(
        agent.workspace.session(const SessionId('s-new'))!,
      );
      expect(notice.kind, NoticeKind.reconnected);
      expect(
        notice.reason,
        const SessionRestoreReason(
          SessionRestoreCause.restoreFailed,
          sessionId: SessionId('s-42'),
        ),
      );
      expect(
        notice.text,
        'Session s-42 could not be restored; a new session was started.',
      );
    });
  });
}

/// Снимок прошлого запуска: проект `/work`, открыта и активна `s-42`.
const _snapshot =
    '{"version":1,"windows":{"main":{"projectDirectory":"/work",'
    '"activeSessionId":"s-42","openSessions":[{"id":"s-42","cwd":"/work"}]}}}';

Future<JsonRpcRequest> _next(FakeAcpTransport transport, String method) async =>
    await transport.sent.firstWhere(
          (message) => message is JsonRpcRequest && message.method == method,
        )
        as JsonRpcRequest;
