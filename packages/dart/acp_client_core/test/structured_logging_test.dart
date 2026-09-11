import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;
  late List<Map<String, dynamic>> captured;

  setUp(() async {
    captured = <Map<String, dynamic>>[];
    // Explicit configure()/reset() per test — see design.md Decision 7's
    // residual risk: several AcpClientApplication instances in this file
    // would otherwise share process-global logging state.
    configureCodeLabLogging(
      applicationOutput: (entry, level) => captured.add(entry),
      protocolTraceOutput: (entry, level) => captured.add(entry),
    );
    transport = FakeAcpTransport();
    await transport.start();
    client = AcpClientApplication(transport: transport);
  });

  tearDown(() async {
    await client.dispose();
    await transport.close();
    StructlogConfiguration.reset();
  });

  test('masks secrets in structured log output', () async {
    transport.emitDiagnostic(
      message: 'Authorization: Bearer transport-token',
      severity: AcpTransportDiagnosticSeverity.warning,
      source: 'stderr',
    );

    final entry = captured.singleWhere((e) => e['source'] == 'stderr');
    expect(entry['event'], 'Authorization: Bearer $redactedSecret');
  });

  test('tags transport diagnostics with component=transport', () async {
    transport.emitDiagnostic(message: 'stderr line', source: 'stderr');

    final entry = captured.singleWhere((e) => e['source'] == 'stderr');
    expect(entry['component'], 'transport');
    expect(entry['category'], 'application');
  });

  test('tags protocol send failures with component=protocol', () async {
    transport.failNextSend(
      const AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'boom',
      ),
    );

    await expectLater(
      client.createSession(const CreateSessionCommand(cwd: '/workspace')),
      throwsA(isA<AcpClientApplicationException>()),
    );

    final entry = captured.singleWhere((e) => e['component'] == 'protocol');
    expect(entry['level'], 'error');
    expect(entry['event'], 'Failed to send ACP request $sessionNewMethod.');
  });

  test('reconnect logs the current connection_generation', () async {
    final replacement = FakeAcpTransport();
    await client.reconnect(
      ReconnectCommand(transportFactory: () => replacement),
    );

    final readyEntry = captured.lastWhere(
      (e) =>
          e['event'] == 'connection_state_changed' &&
          e['to'] == 'ClientConnectionReady',
    );
    expect(readyEntry['connection_generation'], 1);
    expect(client.generation, 1);

    await replacement.close();
  });

  test('stale operation result is logged with its own (superseded) generation, '
      'and is not applied to current state', () async {
    await _createSession(client, transport);
    transport.drainSentMessages();

    final promptFuture = client.sendPrompt(
      const SendPromptCommand(
        sessionId: SessionId('session-1'),
        prompt: [ContentBlock.text(text: 'hello')],
      ),
    );
    final promptExpectation = expectLater(
      promptFuture,
      throwsA(isA<AcpClientApplicationException>()),
    );
    await _pump();

    final replacement = FakeAcpTransport();
    await client.reconnect(
      ReconnectCommand(transportFactory: () => replacement),
    );
    expect(client.generation, 1);

    await promptExpectation;

    final staleEntry = captured.singleWhere(
      (e) => e['reason'] == 'stale_generation',
    );
    expect(staleEntry['connection_generation'], 0);
    expect(
      client.sessionById(const SessionId('session-1'))?.activeTurn?.status,
      PromptTurnStatus.running,
    );

    await replacement.close();
  });

  test(
    'bounds in-memory diagnostics while structured output stays complete',
    () async {
      for (var i = 0; i < 520; i++) {
        transport.emitDiagnostic(message: 'diag-$i', source: 'stderr');
      }

      expect(client.diagnostics.length, 500);
      expect(client.diagnostics.first.message, 'diag-20');
      expect(client.diagnostics.last.message, 'diag-519');
      expect(captured.where((e) => e['source'] == 'stderr').length, 520);
    },
  );

  test('protocol tracing sink is off by default', () async {
    await _createSession(client, transport);

    expect(captured.where((e) => e['category'] == 'protocol'), isEmpty);
  });

  test(
    'explicit enable routes full ACP payload to the protocol-trace sink',
    () async {
      setProtocolTracingEnabled(true);
      addTearDown(() => setProtocolTracingEnabled(false));

      await _createSession(client, transport);

      final traceEntries = captured
          .where((e) => e['category'] == 'protocol')
          .toList();
      expect(traceEntries, isNotEmpty);
      expect(traceEntries.any((e) => e['direction'] == 'outbound'), isTrue);
      expect(traceEntries.any((e) => e['direction'] == 'inbound'), isTrue);

      final outboundPayload =
          traceEntries.firstWhere(
                (e) => e['direction'] == 'outbound',
              )['payload']
              as Map;
      expect(outboundPayload['method'], sessionNewMethod);

      // sessionId is a plain correlation identifier, not a secret — the
      // masking processor must not redact it (see SecretRedactor's
      // session[_-]?(token|cookie|secret|key) narrowing).
      final inboundPayload =
          traceEntries.firstWhere((e) => e['direction'] == 'inbound')['payload']
              as Map;
      final result = inboundPayload['result'] as Map;
      expect(result['sessionId'], 'session-1');
    },
  );

  test(
    'in-app viewer sink always captures both application and protocol-trace '
    'events, independent of the file sink\'s own off-by-default toggle',
    () async {
      // BoundLogger reads the config once at construction — reconfigure
      // before building a client so its loggers pick up the new sink.
      final viewerCaptured = <Map<String, dynamic>>[];
      configureCodeLabLogging(
        applicationOutput: (entry, level) => captured.add(entry),
        protocolTraceOutput: (entry, level) => captured.add(entry),
        inAppViewerOutput: (entry, level) => viewerCaptured.add(entry),
      );

      final viewerTransport = FakeAcpTransport();
      await viewerTransport.start();
      final viewerClient = AcpClientApplication(transport: viewerTransport);
      addTearDown(() async {
        await viewerClient.dispose();
        await viewerTransport.close();
      });

      // File sink stays off by default — its own, independent toggle.
      expect(isProtocolTracingEnabled(), isFalse);

      viewerTransport.emitDiagnostic(message: 'stderr line', source: 'stderr');
      await _createSession(viewerClient, viewerTransport);

      expect(
        viewerCaptured.any((e) => e['category'] == 'application'),
        isTrue,
      );
      // Protocol-trace events reach the in-app viewer unconditionally —
      // no capture-side toggle — even though the file sink is still off.
      expect(viewerCaptured.any((e) => e['category'] == 'protocol'), isTrue);
      expect(captured.any((e) => e['category'] == 'protocol'), isFalse);
    },
  );
}

Future<void> _createSession(
  AcpClientApplication client,
  FakeAcpTransport transport,
) async {
  final future = client.createSession(
    const CreateSessionCommand(cwd: '/workspace'),
  );
  await _pump();
  final request = transport.sentMessages.single as JsonRpcRequest;
  transport.emitInbound(
    JsonRpcMessage.response(
      id: request.id,
      result: const NewSessionResponse(
        sessionId: SessionId('session-1'),
      ).toJson(),
    ),
  );
  await future;
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);
