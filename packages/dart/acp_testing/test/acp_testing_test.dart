import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

void main() {
  test('exports testing package boundaries', () {
    expect(acpTestingPackageName, 'acp_testing');
    expect(acpClientCorePackageName, 'acp_client_core');
    expect(acpProtocolPackageName, 'acp_protocol');
    expect(acpTransportsPackageName, 'acp_transports');
  });

  test('exports codelab-compatible stdio agent source', () {
    expect(
      codelabCompatibleStdioAgentSource(),
      allOf(
        contains("args[0] != 'serve' || args[1] != '--stdio'"),
        contains('codelab-compatible test agent ready'),
        contains("_writeNotification('session/update'"),
        contains("'stopReason': 'end_turn'"),
      ),
    );
    expect(
      codelabCompatibleStdioAgentSource(
        mode: CodelabCompatibleStdioAgentMode.invalidStdout,
      ),
      contains("const _mode = 'invalid_stdout';"),
    );
  });

  test(
    'FakeAcpTransport captures outbound messages deterministically',
    () async {
      final transport = FakeAcpTransport();
      addTearDown(transport.close);

      final sent = <JsonRpcMessage>[];
      final subscription = transport.sent.listen(sent.add);
      addTearDown(subscription.cancel);

      await transport.start();

      final request = JsonRpcMessage.request(
        id: const JsonRpcId.integer(1),
        method: 'initialize',
        params: {'protocolVersion': 1},
      );

      await transport.send(request);

      expect(sent, [request]);
      expect(transport.sentMessages, [request]);
      expect(transport.drainSentMessages(), [request]);
      expect(transport.sentMessages, isEmpty);
    },
  );

  test(
    'FakeAcpTransport emits inbound messages and lifecycle events',
    () async {
      final transport = FakeAcpTransport();
      addTearDown(transport.close);

      final inbound = <JsonRpcMessage>[];
      final events = <AcpTransportEvent>[];
      final inboundSubscription = transport.inbound.listen(inbound.add);
      final eventSubscription = transport.events.listen(events.add);
      addTearDown(inboundSubscription.cancel);
      addTearDown(eventSubscription.cancel);

      await transport.start();

      const notification = JsonRpcMessage.notification(
        method: 'session/update',
        params: {'sessionId': 'session-1'},
      );
      transport.emitInbound(notification);
      transport.emitDiagnostic(
        message: 'stderr line',
        severity: AcpTransportDiagnosticSeverity.warning,
        source: 'stderr',
      );
      transport.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.disconnected,
          message: 'agent exited',
        ),
      );

      expect(inbound, [notification]);
      expect(transport.state, AcpTransportState.failed);
      expect(
        events.whereType<AcpTransportStateChanged>().map(
          (event) => event.state,
        ),
        [
          AcpTransportState.connecting,
          AcpTransportState.connected,
          AcpTransportState.failed,
        ],
      );
      expect(
        events.whereType<AcpTransportDiagnostic>().single,
        isA<AcpTransportDiagnostic>()
            .having((event) => event.message, 'message', 'stderr line')
            .having(
              (event) => event.severity,
              'severity',
              AcpTransportDiagnosticSeverity.warning,
            )
            .having((event) => event.source, 'source', 'stderr'),
      );
      expect(
        events.whereType<AcpTransportFailure>().single.error,
        isA<AcpTransportException>()
            .having(
              (error) => error.code,
              'code',
              AcpTransportErrorCode.disconnected,
            )
            .having((error) => error.message, 'message', 'agent exited'),
      );
    },
  );

  test('FakeAcpTransport closes deterministically', () async {
    final transport = FakeAcpTransport();

    await transport.start();
    await transport.close();

    expect(transport.state, AcpTransportState.closed);
    expect(
      () => transport.emitInbound(
        const JsonRpcMessage.notification(method: 'session/update'),
      ),
      throwsA(
        isA<AcpTransportException>().having(
          (error) => error.code,
          'code',
          AcpTransportErrorCode.closed,
        ),
      ),
    );
  });
}
