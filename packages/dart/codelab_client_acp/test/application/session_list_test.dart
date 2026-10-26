// Тесты исходящего `session/list` (tasks 1.1 change
// `add-session-list-and-reload`; spec acp-protocol-client «Исходящий
// session/list»; design D1).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

const _withList = AgentCapabilities(
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;

  Future<void> connect(AgentCapabilities capabilities) async {
    transport = FakeAcpTransport()..initializeAgentCapabilities = capabilities;
    client = AcpClientApplication(transport: FakeAcpTransport());
    addTearDown(client.dispose);
    await client.connect(transport);
    transport.drainSentMessages();
  }

  JsonRpcRequest sentList() {
    final request = transport.sentMessages.single as JsonRpcRequest;
    expect(request.method, sessionListMethod);
    return request;
  }

  void respond(JsonRpcRequest request, ListSessionsResponse response) =>
      transport.emitInbound(
        JsonRpcMessage.response(id: request.id, result: response.toJson()),
      );

  test('returns the page and nextCursor for the project cwd', () async {
    await connect(_withList);

    final page = client.listSessions(cwd: '/work/app');
    await _pump();
    final request = sentList();
    expect(
      ListSessionsRequest.fromJson(request.params),
      const ListSessionsRequest(cwd: '/work/app'),
    );
    respond(
      request,
      const ListSessionsResponse(
        sessions: [
          SessionInfo(
            sessionId: SessionId('sess-2'),
            cwd: '/work/app',
            title: 'Fix tests',
            updatedAt: '2026-10-26T10:00:00Z',
          ),
          SessionInfo(sessionId: SessionId('sess-1'), cwd: '/work/app'),
        ],
        nextCursor: 'opaque-1',
      ),
    );

    final result = await page;
    expect(result.sessions.map((session) => session.sessionId.value), [
      'sess-2',
      'sess-1',
    ]);
    expect(result.sessions.first.title, 'Fix tests');
    expect(result.nextCursor, 'opaque-1');
  });

  test('sends the cursor back unchanged; no nextCursor is the last '
      'page', () async {
    await connect(_withList);

    final page = client.listSessions(cwd: '/work/app', cursor: 'eyJwIjogMn0=');
    await _pump();
    final request = sentList();
    expect(ListSessionsRequest.fromJson(request.params).cursor, 'eyJwIjogMn0=');
    respond(request, const ListSessionsResponse(sessions: []));

    final result = await page;
    expect(result.sessions, isEmpty);
    expect(result.nextCursor, isNull);
  });

  test('without sessionCapabilities.list nothing is sent and the call '
      'fails', () async {
    await connect(const AgentCapabilities());

    await expectLater(
      client.listSessions(cwd: '/work/app'),
      throwsA(isA<AcpClientApplicationException>()),
    );
    expect(transport.sentMessages, isEmpty);
  });

  test('before initialize nothing is sent and the call fails', () async {
    transport = FakeAcpTransport();
    client = AcpClientApplication(transport: transport);
    addTearDown(client.dispose);

    await expectLater(
      client.listSessions(),
      throwsA(isA<AcpClientApplicationException>()),
    );
    expect(transport.sentMessages, isEmpty);
  });
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);
