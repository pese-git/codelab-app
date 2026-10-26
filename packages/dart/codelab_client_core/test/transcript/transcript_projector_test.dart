// Тесты проекции транскрипта (tasks 3.1; spec acp-client-kit
// «Инкрементальная проекция транскрипта», design D5).
//
// Эталон — `projectTranscript`: пересчёт транскрипта сессии с нуля, перенос
// алгоритма `CodeLabShellCubit` до change. `TranscriptProjector` строит тот
// же результат по шагам и обязан совпадать с эталоном на каждом изменении
// сессии.

import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_core/src/transcript/transcript_projector.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

void main() {
  group('incremental projection equals full rebuild for every fixture', () {
    for (final fixture in loadFixtureCorpus()) {
      test(fixture.id, () async {
        final projectors = <SessionId, TranscriptProjector>{};
        var compared = 0;
        late ClientFixtureUser user;
        StreamSubscription<AcpSession>? subscription;
        final result = await runClientFixture<AcpClientApplication>(fixture, (
          env,
        ) {
          user = ClientFixtureUser(env);
          subscription = user.app.sessionChanges.listen((session) {
            final projector = projectors.putIfAbsent(
              session.id,
              TranscriptProjector.new,
            );
            projector.apply(session);
            expect(
              projector.items,
              projectTranscript(session),
              reason: 'change ${compared + 1} of ${session.id.value}',
            );
            compared++;
          });
          return user.app;
        }, onBeforeExpect: (step) => user.act(step));
        await subscription?.cancel();
        if (result.skipped) {
          markTestSkipped(result.skipReason!);
          return;
        }
        addTearDown(user.app.dispose);

        if (user.app.sessions.any((session) => session.turns.isNotEmpty)) {
          expect(compared, greaterThan(0));
        }
      });
    }
  });

  group('algorithm', () {
    late _Agent agent;

    setUp(() async {
      agent = _Agent();
      await agent.start();
    });
    tearDown(() => agent.dispose());

    test('the prompt becomes a user item; consecutive chunks of one kind '
        'grow one item with a stable id', () async {
      final turn = await agent.prompt('hello');
      agent.update(_message('Hel'));
      final first = agent.items.last;
      agent.update(_message('lo there'));

      expect(agent.items, hasLength(2));
      expect(agent.items.first, isA<UserItem>());
      expect((agent.items.first as UserItem).text, 'hello');
      expect(agent.items.last, isA<AgentTextItem>());
      expect((agent.items.last as AgentTextItem).text, 'Hello there');
      expect(agent.items.last.id, first.id);

      await agent.end(turn);
    });

    test('a thought chunk and a tool call each start a new item', () async {
      final turn = await agent.prompt('go');
      agent
        ..update(_message('one'))
        ..update(_thought('thinking'))
        ..update(_toolCall('call-1', 'Read file'))
        ..update(_message('two'));

      expect(agent.items.skip(1).map((item) => item.runtimeType), [
        AgentTextItem,
        ThoughtItem,
        ToolCallItem,
        AgentTextItem,
      ]);

      await agent.end(turn);
    });

    test('whitespace-only chunks produce no item until text arrives', () async {
      final turn = await agent.prompt('go');
      agent.update(_message('  '));
      expect(agent.items, hasLength(1));

      agent.update(_message('text'));
      expect((agent.items.last as AgentTextItem).text, 'text');

      await agent.end(turn);
    });

    test('a repeated tool_call keeps one item at its position with the '
        'fields of the second frame', () async {
      final turn = await agent.prompt('go');
      agent
        ..update(_toolCall('call-1', 'Read file'))
        ..update(_message('between'))
        ..update(_toolCall('call-1', 'Read README.md'));

      final tools = agent.items.whereType<ToolCallItem>().toList();
      expect(tools, hasLength(1));
      expect(agent.items[1], same(tools.single));
      expect(tools.single.title, 'Read README.md');

      await agent.end(turn);
    });

    test('tool_call_update changes the status of the existing item', () async {
      final turn = await agent.prompt('go');
      agent
        ..update(_toolCall('call-1', 'Run tests'))
        ..update({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-1',
          'status': 'completed',
        });

      final tool = agent.items.whereType<ToolCallItem>().single;
      expect(tool.details?.status, ToolCallStatusView.succeeded);
      expect(tool.details?.kind, ToolKind.execute);

      await agent.end(turn);
    });

    test('a permission request binds to its tool call; the answer resolves '
        'it in place', () async {
      final turn = await agent.prompt('go');
      agent
        ..update(_toolCall('call-1', 'Run tests'))
        ..requestPermission(id: 1, toolCallId: 'call-1');

      final pending =
          agent.items.whereType<ToolCallItem>().single.approval!
              as PendingApprovalView;
      expect(pending.focused, isTrue);
      expect(pending.command, 'dart test');
      expect(pending.options.map((option) => option.optionId.value), [
        'allow-once',
        'reject-once',
      ]);

      await agent.application.respondToPermission(
        RespondToPermissionCommand.selected(
          sessionId: agent.sessionId,
          approvalId: const ApprovalRequestId('permission-1'),
          optionId: const PermissionOptionId('allow-once'),
        ),
      );

      final tools = agent.items.whereType<ToolCallItem>().toList();
      expect(tools, hasLength(1));
      expect(
        tools.single.approval,
        const ApprovalStateView.resolved(label: 'Allow once'),
      );

      await agent.end(turn);
    });

    test('only the earliest pending approval is focused', () async {
      final turn = await agent.prompt('go');
      agent
        ..update(_toolCall('call-1', 'First'))
        ..update(_toolCall('call-2', 'Second'))
        ..requestPermission(id: 1, toolCallId: 'call-1')
        ..requestPermission(id: 2, toolCallId: 'call-2');

      final focused = [
        for (final tool in agent.items.whereType<ToolCallItem>())
          (tool.approval! as PendingApprovalView).focused,
      ];
      expect(focused, [true, false]);

      await agent.application.respondToPermission(
        RespondToPermissionCommand.selected(
          sessionId: agent.sessionId,
          approvalId: const ApprovalRequestId('permission-1'),
          optionId: const PermissionOptionId('allow-once'),
        ),
      );
      final second = agent.items.whereType<ToolCallItem>().last.approval;
      expect((second! as PendingApprovalView).focused, isTrue);

      await agent.application.respondToPermission(
        RespondToPermissionCommand.selected(
          sessionId: agent.sessionId,
          approvalId: const ApprovalRequestId('permission-2'),
          optionId: const PermissionOptionId('allow-once'),
        ),
      );
      await agent.end(turn);
    });

    test('an approval for an unannounced tool call stays at the end of its '
        'turn', () async {
      final turn = await agent.prompt('go');
      agent
        ..update(_message('before'))
        ..requestPermission(id: 1, toolCallId: 'ghost')
        ..update(_thought('after'));

      expect(agent.items.skip(1).map((item) => item.runtimeType), [
        AgentTextItem,
        ThoughtItem,
        ToolCallItem,
      ]);

      await agent.application.respondToPermission(
        RespondToPermissionCommand.selected(
          sessionId: agent.sessionId,
          approvalId: const ApprovalRequestId('permission-1'),
          optionId: const PermissionOptionId('reject-once'),
        ),
      );
      await agent.end(turn);
    });

    test('a turn that ends without output gets an empty-turn notice', () async {
      final turn = await agent.prompt('go');
      expect(agent.items, hasLength(1));

      await agent.end(turn);

      final notice = agent.items.last as NoticeItem;
      expect(notice.kind, NoticeKind.emptyTurn);
      expect(notice.text, 'Completed with stopReason endTurn.');
    });

    test('a failed prompt gets an error notice without the exception '
        'type', () async {
      final turn = await agent.prompt('go');
      agent.transport.emitInbound(
        JsonRpcMessage.response(
          id: turn.request.id,
          error: const JsonRpcError(code: -32603, message: 'agent crashed'),
        ),
      );
      await turn.done.then<void>((_) {}, onError: (_) {});

      final notice = agent.items.last as NoticeItem;
      expect(notice.kind, NoticeKind.error);
      expect(notice.text, startsWith('Failed to send prompt: '));
      expect(notice.text, isNot(contains('Exception:')));
    });

    test('a failed prompt without agent output gets only the error notice, '
        'not an emptyTurn one', () async {
      final turn = await agent.prompt('go');
      agent.transport.emitInbound(
        JsonRpcMessage.response(
          id: turn.request.id,
          error: const JsonRpcError(code: -32603, message: 'agent crashed'),
        ),
      );
      await turn.done.then<void>((_) {}, onError: (_) {});

      final notices = agent.items.whereType<NoticeItem>().toList();
      expect(notices.map((n) => n.kind), [NoticeKind.error]);
    });

    test('applying the same session again changes nothing', () async {
      final turn = await agent.prompt('go');
      agent.update(_message('text'));
      final session = agent.application.sessionById(agent.sessionId)!;
      final items = agent.items;

      expect(agent.projector.apply(session), isFalse);
      expect(agent.projector.items, same(items));

      await agent.end(turn);
    });
  });
}

Map<String, Object?> _message(String text) => {
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': text},
};

Map<String, Object?> _thought(String text) => {
  'sessionUpdate': 'agent_thought_chunk',
  'content': {'type': 'text', 'text': text},
};

Map<String, Object?> _toolCall(String id, String title) => {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': title,
  'kind': 'execute',
  'status': 'in_progress',
  'rawInput': {'command': 'dart test'},
};

typedef _Turn = ({JsonRpcRequest request, Future<PromptTurn> done});

/// Агент на `FakeAcpTransport` и проектор, применяемый к каждому изменению
/// сессии в ядре клиента.
final class _Agent {
  final transport = FakeAcpTransport();
  final application = AcpClientApplication(transport: FakeAcpTransport());
  final projector = TranscriptProjector();
  final sessionId = const SessionId('s-1');
  StreamSubscription<AcpSession>? _subscription;

  List<TranscriptItem> get items => projector.items;

  Future<void> start() async {
    await application.connect(transport);
    _subscription = application.sessionChanges.listen(projector.apply);
    final request = _next(sessionNewMethod);
    final created = application.createSession(
      const CreateSessionCommand(cwd: '/work'),
    );
    transport.emitInbound(
      JsonRpcMessage.response(
        id: (await request).id,
        result: {'sessionId': sessionId.value},
      ),
    );
    await created;
  }

  Future<_Turn> prompt(String text) async {
    final request = _next(sessionPromptMethod);
    final done = application.sendPrompt(
      SendPromptCommand(
        sessionId: sessionId,
        prompt: [ContentBlock.text(text: text)],
      ),
    );
    return (request: await request, done: done);
  }

  void update(Map<String, Object?> update) => transport.emitInbound(
    JsonRpcMessage.notification(
      method: sessionUpdateMethod,
      params: {'sessionId': sessionId.value, 'update': update},
    ),
  );

  void requestPermission({required int id, required String toolCallId}) {
    transport.emitInbound(
      JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: sessionId,
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId(toolCallId),
            title: 'Run $toolCallId',
            kind: ToolKind.execute,
            status: ToolCallStatus.inProgress,
            rawInput: const {'command': 'dart test'},
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
  }

  Future<void> end(_Turn turn) async {
    transport.emitInbound(
      JsonRpcMessage.response(
        id: turn.request.id,
        result: const {'stopReason': 'end_turn'},
      ),
    );
    await turn.done;
  }

  Future<JsonRpcRequest> _next(String method) async =>
      await transport.sent.firstWhere(
            (message) => message is JsonRpcRequest && message.method == method,
          )
          as JsonRpcRequest;

  Future<void> dispose() async {
    await _subscription?.cancel();
    await application.dispose();
  }
}
