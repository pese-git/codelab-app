import 'dart:convert';

import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

// The messages @agentclientprotocol/claude-agent-acp 0.88.0 sends during a
// prompt turn (captured 2026-10-09), trimmed to what matters.
const _sessionId = SessionId('session-1');

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;
  late List<Map<String, dynamic>> captured;

  setUp(() async {
    captured = <Map<String, dynamic>>[];
    configureCodeLabLogging(
      applicationOutput: (entry, level) => captured.add(entry),
      protocolTraceOutput: (entry, level) => captured.add(entry),
      protocolTracingEnabledByDefault: true,
    );
    transport = FakeAcpTransport();
    await transport.start();
    client = AcpClientApplication(transport: transport);

    final future = client.createSession(
      const CreateSessionCommand(cwd: '/workspace'),
    );
    await _pump();
    final request = transport.sentMessages.single as JsonRpcRequest;
    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const NewSessionResponse(sessionId: _sessionId).toJson(),
      ),
    );
    await future;
    transport.drainSentMessages();
    captured.clear();
  });

  tearDown(() async {
    await client.dispose();
    await transport.close();
    StructlogConfiguration.reset();
  });

  void emitUpdate(Map<String, Object?> update) {
    transport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: {'sessionId': _sessionId.value, 'update': update},
      ),
    );
  }

  Future<PromptTurn> startPrompt() => client.sendPrompt(
    const SendPromptCommand(
      sessionId: _sessionId,
      prompt: [ContentBlock.text(text: 'ping')],
    ),
  );

  Future<PromptTurn> finishPrompt(Future<PromptTurn> turn) {
    final request = transport.sentMessages.single as JsonRpcRequest;
    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const PromptResponse(stopReason: StopReason.endTurn).toJson(),
      ),
    );
    return turn;
  }

  test('a real 0.88.0 prompt turn delivers the reply and completes', () async {
    final turn = startPrompt();
    await _pump();

    emitUpdate({
      'sessionUpdate': 'available_commands_update',
      'availableCommands': <Object?>[],
    });
    emitUpdate({
      'sessionUpdate': 'usage_update',
      'used': 37758,
      'size': 1000000,
    });
    emitUpdate({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'pong'},
      'messageId': 'msg_011',
    });
    emitUpdate({
      'sessionUpdate': 'usage_update',
      'used': 37758,
      'size': 1000000,
      'cost': {'amount': 0.75, 'currency': 'USD'},
    });

    final completed = await finishPrompt(turn);
    expect(completed.status, PromptTurnStatus.completed);
    final chunks = completed.updates.whereType<AgentMessageChunk>().toList();
    expect(chunks, hasLength(1));
    expect(chunks.single.content, const ContentBlock.text(text: 'pong'));

    expect(
      client.diagnostics.where((e) => e.severity == DiagnosticSeverity.error),
      isEmpty,
    );
  });

  const skippedEvent = 'Skipped unsupported ACP session update.';

  test(
    'an unsupported update kind changes nothing and adds no diagnostics',
    () async {
      final before = client.sessionById(_sessionId);

      emitUpdate({'sessionUpdate': 'usage_update', 'used': 1, 'size': 2});
      await _pump();

      expect(client.sessionById(_sessionId), before);
      expect(client.diagnostics, isEmpty);
      expect(client.sessionById(_sessionId)?.diagnostics, isEmpty);
    },
  );

  test(
    'the application record names the kind but carries no payload',
    () async {
      emitUpdate({
        'sessionUpdate': 'usage_update',
        'used': 1,
        'size': 2,
        'note': 'user-visible-text',
      });
      await _pump();

      final entry = captured.singleWhere(
        (e) => e['event'] == skippedEvent && e['category'] == 'application',
      );
      expect(entry['level'], 'debug');
      expect(entry['component'], 'protocol');
      expect(entry['sessionUpdate'], 'usage_update');
      expect(entry['session_id'], 'session-1');
      expect(entry.containsKey('payload'), isFalse);
      expect(jsonEncode(entry), isNot(contains('user-visible-text')));
    },
  );

  test(
    'the protocol-trace record carries the payload with secrets masked',
    () async {
      emitUpdate({
        'sessionUpdate': 'usage_update',
        'used': 37758,
        'size': 1000000,
        'secret': 'sk-secret-value',
      });
      await _pump();

      final entry = captured.singleWhere(
        (e) => e['event'] == skippedEvent && e['category'] == 'protocol',
      );
      expect(entry['sessionUpdate'], 'usage_update');
      expect(entry['session_id'], 'session-1');
      final payload = entry['payload'] as Map<String, dynamic>;
      expect(payload['sessionId'], 'session-1');
      final update = payload['update'] as Map<String, dynamic>;
      expect(update['used'], 37758);
      expect(update['size'], 1000000);
      expect(update['secret'], redactedSecret);
      expect(jsonEncode(captured), isNot(contains('sk-secret-value')));
    },
  );

  test('a structurally invalid update of a known kind is still an error '
      'and is not applied', () async {
    final turn = startPrompt();
    await _pump();
    final before = client.sessionById(_sessionId);

    emitUpdate({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'made_up', 'text': 'x'},
    });
    await _pump();

    expect(client.sessionById(_sessionId)?.turns, before?.turns);
    final errors = client.diagnostics.where(
      (e) => e.severity == DiagnosticSeverity.error,
    );
    expect(errors, hasLength(1));
    expect(errors.single.message, 'Failed to handle ACP session update.');

    await finishPrompt(turn);
  });
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);
