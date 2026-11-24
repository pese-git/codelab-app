import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
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
    // Тот же текст в записи буфера `diagnostics` замаскирован одним проходом.
    expect(
      client.diagnostics.single.message,
      'Authorization: Bearer $redactedSecret',
    );
    expect(
      client.diagnostics.single.message,
      isNot(contains('transport-token')),
    );
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
    expect(readyEntry['component'], 'client');
    expect(readyEntry['from'], isA<String>());
    expect(readyEntry['from'], isNot('ClientConnectionReady'));
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

  // structured-logging «Ограниченная (bounded) история diagnostic-событий»,
  // сценарий «Диагностика не меняет снимок сессии» (задача 2.1 change
  // `align-cross-cutting-specs`, D3): единственный буфер — `client.diagnostics`.
  test('diagnostics do not change the session snapshot', () async {
    await _createSession(client, transport);
    final before = client.sessionById(const SessionId('session-1'))!;
    final changes = <AcpSession>[];
    final subscription = client.sessionChanges.listen(changes.add);
    addTearDown(subscription.cancel);

    transport.emitDiagnostic(message: 'stderr line', source: 'stderr');
    await _pump();

    expect(client.diagnostics.map((e) => e.message), contains('stderr line'));
    expect(
      identical(client.sessionById(const SessionId('session-1')), before),
      isTrue,
    );
    expect(changes, isEmpty);
  });

  test('protocol tracing sink is off by default', () async {
    await _createSession(client, transport);

    expect(captured.where((e) => e['category'] == 'protocol'), isEmpty);
  });

  test(
    'explicit enable routes full ACP payload to the protocol-trace sink',
    () async {
      setProtocolTracingEnabled(true);
      addTearDown(() => setProtocolTracingEnabled(false));

      // Политика payload по умолчанию — `metadataOnly` (D3 change
      // `redesign-protocol-pane`): тест, проверяющий `payload`, просит
      // `full` явно.
      final fullTransport = FakeAcpTransport();
      await fullTransport.start();
      final fullClient = AcpClientApplication(
        transport: fullTransport,
        protocolPayloads: ProtocolPayloadPolicy.full,
      );
      addTearDown(() async {
        await fullClient.dispose();
        await fullTransport.close();
      });
      await _createSession(fullClient, fullTransport);

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

      expect(viewerCaptured.any((e) => e['category'] == 'application'), isTrue);
      // Protocol-trace events reach the in-app viewer unconditionally —
      // no capture-side toggle — even though the file sink is still off.
      expect(viewerCaptured.any((e) => e['category'] == 'protocol'), isTrue);
      expect(captured.any((e) => e['category'] == 'protocol'), isFalse);
    },
  );

  group('protocol_message и политика payload (D3 change '
      '`redesign-protocol-pane`)', () {
    // Задача 1.5 `[client]`. Красные тесты: сейчас запись всегда несёт
    // `payload`, у неё нет `kind`, `method`, `request_id`, `size`; файл не
    // компилируется до добавления `protocolPayloads` (задача 1.4).
    const promptText = 'my secret prompt text';

    setUp(() => setProtocolTracingEnabled(true));
    tearDown(() => setProtocolTracingEnabled(false));

    Future<void> sendPromptVia(
      AcpClientApplication app,
      FakeAcpTransport fake,
    ) async {
      await _createSession(app, fake);
      fake.drainSentMessages();
      captured.clear();
      app
          .sendPrompt(
            const SendPromptCommand(
              sessionId: SessionId('session-1'),
              prompt: [ContentBlock.text(text: promptText)],
            ),
          )
          .then<void>((_) {}, onError: (_) {});
      await _pump();
    }

    Future<(AcpClientApplication, FakeAcpTransport)> build(
      ProtocolPayloadPolicy? policy,
    ) async {
      final fake = FakeAcpTransport();
      await fake.start();
      final app = AcpClientApplication(
        transport: fake,
        protocolPayloads: policy ?? ProtocolPayloadPolicy.metadataOnly,
      );
      addTearDown(() async {
        await app.dispose();
        await fake.close();
      });
      return (app, fake);
    }

    test('metadataOnly: запись без payload, с direction, kind, method, '
        'request_id и size', () async {
      final (app, fake) = await build(null);
      await sendPromptVia(app, fake);

      final entry = captured.singleWhere(
        (e) => e['event'] == 'protocol_message' && e['direction'] == 'outbound',
      );
      expect(entry.containsKey('payload'), isFalse);
      expect(entry['kind'], 'request');
      expect(entry['method'], sessionPromptMethod);
      final sent = fake.sentMessages.single as JsonRpcRequest;
      expect(entry['request_id'], isA<String>());
      expect(entry['request_id'], sent.id.toJsonValue().toString());
      expect(entry['size'], isA<int>());
      expect(entry['size'], greaterThan(0));
      expect(entry['connection_generation'], 0);
      expect(entry.toString(), isNot(contains(promptText)));
    });

    test('metadataOnly: входящая запись тоже без payload', () async {
      final (app, fake) = await build(null);
      await sendPromptVia(app, fake);
      fake.emitInbound(
        JsonRpcMessage.response(
          id: (fake.sentMessages.single as JsonRpcRequest).id,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await _pump();

      final entry = captured.singleWhere(
        (e) => e['event'] == 'protocol_message' && e['direction'] == 'inbound',
      );
      expect(entry.containsKey('payload'), isFalse);
      expect(entry['kind'], 'result');
      expect(entry['method'], sessionPromptMethod);
    });

    test('full: запись с замаскированным payload', () async {
      final (app, fake) = await build(ProtocolPayloadPolicy.full);
      await sendPromptVia(app, fake);
      captured.clear();
      app
          .createSession(
            const CreateSessionCommand(
              cwd: '/workspace',
              mcpServers: [
                McpServer.http(
                  name: 'github',
                  url: 'https://example.test/mcp',
                  headers: [
                    HttpHeader(name: 'Authorization', value: 'ghp_abc123'),
                  ],
                ),
              ],
            ),
          )
          .then<void>((_) {}, onError: (_) {});
      await _pump();

      final entry = captured.singleWhere(
        (e) => e['event'] == 'protocol_message' && e['direction'] == 'outbound',
      );
      expect(entry['payload'], isA<Map>());
      expect((entry['payload'] as Map)['method'], sessionNewMethod);
      expect(entry.toString(), contains(redactedSecret));
      expect(entry.toString(), isNot(contains('ghp_abc123')));
    });

    test('Trace при базовой metadataOnly не пишет payload в журнал', () async {
      final (app, fake) = await build(null);
      app.setFrameTrace(true);
      await sendPromptVia(app, fake);

      final entry = captured.singleWhere(
        (e) => e['event'] == 'protocol_message' && e['direction'] == 'outbound',
      );
      expect(entry.containsKey('payload'), isFalse);
      expect(entry['method'], sessionPromptMethod);
    });
  });

  test('httpOutput sink (local-dev-only structured_log_remote_sync) receives '
      'application events like the console/file sink, and is absent when '
      'not supplied', () async {
    final httpCaptured = <Map<String, dynamic>>[];
    configureCodeLabLogging(
      applicationOutput: (entry, level) => captured.add(entry),
      protocolTraceOutput: (entry, level) => captured.add(entry),
      httpOutput: (entry, level) => httpCaptured.add(entry),
    );

    final httpTransport = FakeAcpTransport();
    await httpTransport.start();
    final httpClient = AcpClientApplication(transport: httpTransport);
    addTearDown(() async {
      await httpClient.dispose();
      await httpTransport.close();
    });

    httpTransport.emitDiagnostic(message: 'stderr line', source: 'stderr');

    expect(httpCaptured, isNotEmpty);
    expect(httpCaptured.every((e) => e['category'] == 'application'), isTrue);
  });
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
