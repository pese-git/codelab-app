// Ожидания одобрений корня хода в `SessionView.approvalWaits` (задача 2.3
// `[client]` change `fix-usage-pane-live-cards`; spec acp-client-kit
// «Ожидания одобрений корня хода», все сценарии; design.md, D3).
//
// Красные тесты: у `SessionView` нет `approvalWaits`, нет вида
// `ApprovalWaitView`, нет проекции `approvalWaitViews(AcpSession)` рядом с
// `pendingApprovalViews` (задача 2.4) — файл не компилируется. Имена
// предложены design.md, D3 («имена — исполнителю, здесь — `approvalWaits` и
// `ApprovalWaitView(requestedAt, resolvedAt?)`»); `approvalWaitViews` —
// предложение этого теста, по образцу `pendingApprovalViews`
// (`lib/src/transcript/transcript_projector.dart`).
//
// Метки времени ставит домен `codelab_client_acp` (`DateTime.now`), kit их не
// ставит (D3, «Часы»): тесты сверяют вид с метками одобрений домена
// (`AcpClientApplication.sessions`), а не с часами теста. Случай «решённое
// без `resolvedAt`» домен сам не создаёт, поэтому он проверяется на
// собранной вручную `AcpSession` через `approvalWaitViews`.
//
// Гонок без таймеров нет: кадры агента подаются принудительным порядком,
// ожидание — `pumpEventQueue`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_core/src/transcript/transcript_projector.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

/// `_meta.codelab.subagent` запроса разрешения потомка (D8, D43 п. 1).
Map<String, Object?> _requesterMeta() => {
  'codelab': {
    'subagent': {
      'id': 'sub_a1',
      'type': 'review',
      'description': 'Check the diff',
      'depth': 1,
      'path': const <String>[],
      'parentToolCallId': 'call_3',
    },
  },
};

ApprovalRequest _approval(
  String id, {
  required DateTime? requestedAt,
  DateTime? resolvedAt,
  ApprovalStatus status = ApprovalStatus.pending,
  Map<String, Object?>? subagentRequester,
}) => ApprovalRequest(
  id: ApprovalRequestId(id),
  sessionId: const SessionId('s-1'),
  turnId: const PromptTurnId('t-1'),
  toolCall: ToolCallRecord(id: ToolCallId(id), title: 'Run $id'),
  options: const [],
  status: status,
  requestedAt: requestedAt,
  resolvedAt: resolvedAt,
  subagentRequester: subagentRequester,
);

PromptTurn _turn(String id, List<ApprovalRequest> approvals) => PromptTurn(
  id: PromptTurnId(id),
  sessionId: const SessionId('s-1'),
  prompt: const [],
  approvals: {for (final approval in approvals) approval.id: approval},
);

void main() {
  late KitAgent agent;
  late SessionHandle session;
  late JsonRpcRequest prompt;
  var nextRequestId = 7;

  setUp(() async {
    agent = KitAgent();
    await agent.start();
    session = await agent.newSession('s-1');
    prompt = (await agent.prompt(session, 'go')).request;
    nextRequestId = 7;
  });
  tearDown(() => agent.dispose());

  /// Запрос разрешения; [meta] — `toolCall._meta` (`null` — запрос корня).
  Future<int> ask(String toolCallId, {Map<String, Object?>? meta}) async {
    final id = nextRequestId++;
    agent.transport.emitInbound(
      JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: const SessionId('s-1'),
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId(toolCallId),
            title: 'Run $toolCallId',
            kind: ToolKind.execute,
            status: ToolCallStatus.pending,
            rawInput: const {'command': 'dart test'},
            meta: meta,
          ),
          options: const [
            PermissionOption(
              optionId: PermissionOptionId('allow-once'),
              name: 'Allow once',
              kind: PermissionOptionKind.allowOnce,
            ),
            PermissionOption(
              optionId: PermissionOptionId('reject-once'),
              name: 'Reject',
              kind: PermissionOptionKind.rejectOnce,
            ),
          ],
        ).toJson(),
      ),
    );
    await pumpEventQueue();
    return id;
  }

  /// Одобрения последнего хода по домену, в порядке прихода: источник меток.
  List<ApprovalRequest> domainApprovals() => agent.application.sessions
      .singleWhere((s) => s.id == const SessionId('s-1'))
      .turns
      .last
      .approvals
      .values
      .toList();

  /// Ответ пользователя на единственное ожидающее одобрение корня.
  Future<void> allow() async {
    final approval = session.current.pendingApprovals.singleWhere(
      (pending) => pending.subagent == null,
    );
    await session.respond(
      approval.approvalId,
      const PermissionOptionId('allow-once'),
    );
    await pumpEventQueue();
  }

  group('root approvals of the current turn', () {
    test('a pending and a resolved approval: two intervals in arrival '
        'order, the marks are those of the domain (scenario «Ожидающее и '
        'решённое одобрения корня»)', () async {
      await ask('call_1');
      await allow();
      await ask('call_2');

      final domain = domainApprovals();
      final waits = session.current.approvalWaits;
      expect(waits, hasLength(2));
      expect(waits[0].requestedAt, domain[0].requestedAt);
      expect(waits[0].resolvedAt, domain[0].resolvedAt);
      expect(waits[0].requestedAt, isNotNull);
      expect(waits[0].resolvedAt, isNotNull);
      expect(waits[1].requestedAt, domain[1].requestedAt);
      expect(waits[1].resolvedAt, isNull);
      expect(waits[0].requestedAt.isAfter(waits[1].requestedAt), isFalse);
    });

    test('a pending approval has resolvedAt == null', () async {
      await ask('call_1');

      expect(session.current.approvalWaits, hasLength(1));
      expect(session.current.approvalWaits.single.resolvedAt, isNull);
      expect(session.current.pendingApprovals, hasLength(1));
    });

    test('before any request the list is empty', () {
      expect(session.current.approvalWaits, isEmpty);
    });

    test('the response closes the interval with the domain mark and the '
        'list stays after the turn is answered by the agent', () async {
      await ask('call_1');
      await allow();

      final resolved = domainApprovals().single;
      expect(resolved.resolvedAt, isNotNull);
      expect(
        session.current.approvalWaits.single.resolvedAt,
        resolved.resolvedAt,
      );
      expect(session.current.pendingApprovals, isEmpty);
    });
  });

  group('a child request (scenario «Одобрение субагента»)', () {
    test('is not in approvalWaits but stays in pendingApprovals', () async {
      await ask('call_3/call_1', meta: _requesterMeta());

      expect(session.current.approvalWaits, isEmpty);
      expect(session.current.pendingApprovals, hasLength(1));
      expect(session.current.pendingApprovals.single.subagent, isNotNull);
    });

    test('next to a root request only the root one is listed', () async {
      await ask('call_3/call_1', meta: _requesterMeta());
      await ask('call_2');

      final waits = session.current.approvalWaits;
      expect(waits, hasLength(1));
      expect(waits.single.requestedAt, domainApprovals().last.requestedAt);
      expect(waits.single.resolvedAt, isNull);
      expect(session.current.pendingApprovals, hasLength(2));
    });

    test('a resolved child request is not listed either', () async {
      await ask('call_3/call_1', meta: _requesterMeta());
      final childApproval = session.current.pendingApprovals.single;
      await session.respond(
        childApproval.approvalId,
        const PermissionOptionId('allow-once'),
      );
      await pumpEventQueue();

      expect(session.current.approvalWaits, isEmpty);
    });
  });

  group('turn boundaries', () {
    test(
      'a new turn starts with an empty list (scenario «Новый ход»)',
      () async {
        await ask('call_1');
        await allow();
        expect(session.current.approvalWaits, hasLength(1));
        agent.respond(prompt, const {'stopReason': 'end_turn'});
        await pumpEventQueue();

        await agent.prompt(session, 'next');
        await pumpEventQueue();

        expect(session.current.approvalWaits, isEmpty);
      },
    );

    test('cancelling the turn closes a pending interval with the domain '
        'mark', () async {
      await ask('call_1');
      expect(session.current.approvalWaits.single.resolvedAt, isNull);

      await session.cancel();
      agent.respond(prompt, const {'stopReason': 'cancelled'});
      await pumpEventQueue();

      final domain = domainApprovals().single;
      expect(domain.resolvedAt, isNotNull);
      expect(session.current.approvalWaits, hasLength(1));
      expect(
        session.current.approvalWaits.single.resolvedAt,
        domain.resolvedAt,
      );
      expect(session.current.pendingApprovals, isEmpty);
    });

    test('a lost connection closes a pending interval, nothing stays '
        'waiting', () async {
      await ask('call_1');

      agent.transport.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.closed,
          message: 'agent process exited',
        ),
      );
      await pumpEventQueue();

      final domain = domainApprovals().single;
      expect(domain.resolvedAt, isNotNull);
      expect(session.current.pendingApprovals, isEmpty);
      expect(
        session.current.approvalWaits.where((wait) => wait.resolvedAt == null),
        isEmpty,
      );
    });
  });

  group('approvalWaitViews on a hand-built session', () {
    final t0 = DateTime.utc(2026, 11, 18, 10);

    AcpSession sessionOf(List<PromptTurn> turns) =>
        AcpSession(id: const SessionId('s-1'), cwd: '/work', turns: turns);

    test('a resolved approval without resolvedAt is not listed: the host '
        'would take it for a pending one', () {
      final waits = approvalWaitViews(
        sessionOf([
          _turn('t-1', [
            _approval('a', requestedAt: t0, status: ApprovalStatus.selected),
            _approval(
              'b',
              requestedAt: t0.add(const Duration(seconds: 5)),
              resolvedAt: t0.add(const Duration(seconds: 9)),
              status: ApprovalStatus.selected,
            ),
          ]),
        ]),
      );

      expect(waits, [
        ApprovalWaitView(
          requestedAt: t0.add(const Duration(seconds: 5)),
          resolvedAt: t0.add(const Duration(seconds: 9)),
        ),
      ]);
    });

    test('an approval without requestedAt is not listed (the source needs '
        'a known requestedAt)', () {
      final waits = approvalWaitViews(
        sessionOf([
          _turn('t-1', [_approval('a', requestedAt: null)]),
        ]),
      );

      expect(waits, isEmpty);
    });

    test('the list is ordered by requestedAt, not by map order', () {
      final waits = approvalWaitViews(
        sessionOf([
          _turn('t-1', [
            _approval('late', requestedAt: t0.add(const Duration(seconds: 8))),
            _approval('early', requestedAt: t0),
          ]),
        ]),
      );

      expect(waits.map((wait) => wait.requestedAt), [
        t0,
        t0.add(const Duration(seconds: 8)),
      ]);
    });

    test('only the last turn counts', () {
      final waits = approvalWaitViews(
        sessionOf([
          _turn('t-1', [
            _approval(
              'old',
              requestedAt: t0,
              resolvedAt: t0.add(const Duration(seconds: 3)),
              status: ApprovalStatus.selected,
            ),
          ]),
          _turn('t-2', const []),
        ]),
      );

      expect(waits, isEmpty);
    });

    test('a child request of the last turn is not listed', () {
      final waits = approvalWaitViews(
        sessionOf([
          _turn('t-1', [
            _approval(
              'child',
              requestedAt: t0,
              subagentRequester:
                  _requesterMeta()['codelab'] as Map<String, Object?>,
            ),
          ]),
        ]),
      );

      expect(waits, isEmpty);
    });

    test('views and the list compare by value', () {
      List<ApprovalWaitView> build() => approvalWaitViews(
        sessionOf([
          _turn('t-1', [
            _approval(
              'a',
              requestedAt: t0,
              resolvedAt: t0.add(const Duration(seconds: 2)),
              status: ApprovalStatus.selected,
            ),
            _approval('b', requestedAt: t0.add(const Duration(seconds: 4))),
          ]),
        ]),
      );

      expect(build(), build());
      expect(build().first, build().first);
      expect(build().first.hashCode, build().first.hashCode);
      expect(
        ApprovalWaitView(requestedAt: t0),
        isNot(ApprovalWaitView(requestedAt: t0, resolvedAt: t0)),
      );
    });
  });

  group('revisions without a change of the approvals', () {
    test('agent chunks after a request leave approvalWaits equal by value '
        '(scenario «Ревизия без изменения ожиданий»)', () async {
      await ask('call_1');
      final before = session.current;

      agent.update('s-1', {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'Waiting for you'},
      });
      await pumpEventQueue();
      agent.update('s-1', {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': ' to decide'},
      });
      await pumpEventQueue();

      final after = session.current;
      expect(after.revision, greaterThan(before.revision));
      expect(after.approvalWaits, before.approvalWaits);
      expect(after.approvalWaits.single, before.approvalWaits.single);
      expect(after.approvalWaits.single.resolvedAt, isNull);
    });
  });
}
