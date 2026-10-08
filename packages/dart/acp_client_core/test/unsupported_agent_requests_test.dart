import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;

  setUp(() async {
    transport = FakeAcpTransport();
    await transport.start();
    client = AcpClientApplication(transport: transport);
  });

  tearDown(() async {
    await client.dispose();
    await transport.close();
  });

  JsonRpcResponse onlyResponse() =>
      transport.sentMessages.single as JsonRpcResponse;

  test('a custom (`_`-prefixed) agent request gets `Method not found` with '
      'the same id', () async {
    transport.emitInbound(
      const JsonRpcMessage.request(
        id: JsonRpcId.integer(7),
        method: '_vendor/feature',
        params: {'token': 'sk-secret-value'},
      ),
    );
    await _pump();

    final response = onlyResponse();
    expect(response.id, const JsonRpcId.integer(7));
    expect(response.error?.code, jsonRpcMethodNotFoundCode);
    expect(response.result, isNull);
  });

  test('an unknown standard-looking method gets `Method not found`', () async {
    transport.emitInbound(
      const JsonRpcMessage.request(
        id: JsonRpcId.string('req-1'),
        method: 'session/does_not_exist',
      ),
    );
    await _pump();

    final response = onlyResponse();
    expect(response.id, const JsonRpcId.string('req-1'));
    expect(response.error?.code, jsonRpcMethodNotFoundCode);
  });

  test('the connection stays usable after rejecting a request', () async {
    final stateBefore = client.connectionState;
    transport.emitInbound(
      const JsonRpcMessage.request(
        id: JsonRpcId.integer(1),
        method: '_vendor/feature',
      ),
    );
    await _pump();
    transport.drainSentMessages();

    expect(client.connectionState, stateBefore);

    final future = client.createSession(
      const CreateSessionCommand(cwd: '/workspace'),
    );
    await _pump();
    final request = transport.sentMessages.single as JsonRpcRequest;
    expect(request.method, sessionNewMethod);
    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const NewSessionResponse(
          sessionId: SessionId('session-1'),
        ).toJson(),
      ),
    );
    await future;

    expect(client.sessionById(const SessionId('session-1')), isNotNull);
  });

  test('an unknown notification gets no reply and is not an error', () async {
    final stateBefore = client.connectionState;
    transport.emitInbound(
      const JsonRpcMessage.notification(
        method: '_auth/status_update',
        params: {'status': 'ok'},
      ),
    );
    await _pump();

    expect(transport.sentMessages, isEmpty);
    expect(client.connectionState, stateBefore);
    expect(client.diagnostics, isEmpty);
  });

  test(
    'the rejection is diagnosed by method and id, never by params',
    () async {
      transport.emitInbound(
        const JsonRpcMessage.request(
          id: JsonRpcId.integer(9),
          method: '_vendor/feature',
          params: {'token': 'sk-secret-value'},
        ),
      );
      await _pump();

      final entry = client.diagnostics.singleWhere(
        (entry) => entry.message.contains('_vendor/feature'),
      );
      expect(entry.severity, DiagnosticSeverity.warning);
      expect(entry.toString(), isNot(contains('sk-secret-value')));
    },
  );
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);
