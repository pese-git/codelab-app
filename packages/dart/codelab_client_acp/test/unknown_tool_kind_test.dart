import 'dart:convert';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

// Незнакомый и новый вид вызова инструмента (change
// `tolerate-unknown-tool-kind`, D1, D4, D5, D9; acp-protocol-client
// «Неизвестный вид вызова инструмента», approval-safety «Риск вызова
// неизвестного вида и смены режима»).
const _sessionId = SessionId('session-1');
const _warnEvent = 'Unknown ACP tool kind treated as other.';

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

    await _createSession(client, transport);
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

  void emitPermission(int id, Map<String, Object?> toolCall) {
    transport.emitInbound(
      JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: sessionRequestPermissionMethod,
        params: {
          'sessionId': _sessionId.value,
          'toolCall': toolCall,
          'options': [
            {
              'optionId': 'allow-once',
              'name': 'Allow once',
              'kind': 'allow_once',
            },
          ],
        },
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
    final request = transport.sentMessages.whereType<JsonRpcRequest>().single;
    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const PromptResponse(stopReason: StopReason.endTurn).toJson(),
      ),
    );
    return turn;
  }

  PromptTurn turnOf() => client.sessionById(_sessionId)!.turns.last;
  ToolCallRecord? callOf(String id) => turnOf().toolCalls[ToolCallId(id)];
  List<Map<String, dynamic>> warnings() => captured
      .where((e) => e['event'] == _warnEvent && e['category'] == 'application')
      .toList();

  bool answeredCancelled() => transport.sentMessages
      .whereType<JsonRpcResponse>()
      .any((r) => jsonEncode(r.result).contains('cancelled'));

  Iterable<Object> errors() =>
      client.diagnostics.where((e) => e.severity == DiagnosticSeverity.error);

  group('unknown kind in session/update and session/request_permission', () {
    test('tool_call, tool_call_update and a permission request with '
        'future_kind are tolerated and logged once each', () async {
      final turn = startPrompt();
      await _pump();

      emitUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'title': 'secret-title',
        'kind': 'future_kind',
        'status': 'pending',
        'rawInput': {'note': 'secret-raw-input'},
      });
      await _pump();

      expect(callOf('call-1')?.kind, ToolKind.other);
      expect(callOf('call-1')?.riskLevel, ApprovalRiskLevel.unknown);
      expect(errors(), isEmpty);

      emitUpdate({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'pong'},
      });
      await _pump();
      expect(turnOf().updates.whereType<AgentMessageChunk>(), hasLength(1));

      emitUpdate({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call-1',
        'kind': 'future_kind',
        'status': 'completed',
      });
      await _pump();
      expect(callOf('call-1')?.status, ToolCallStatus.completed);
      expect(callOf('call-1')?.kind, ToolKind.other);

      emitPermission(50, {
        'toolCallId': 'call-9',
        'title': 'secret-title',
        'kind': 'future_kind',
      });
      await _pump();

      final approval = turnOf().approvals.values.single;
      expect(approval.status, ApprovalStatus.pending);
      expect(approval.riskLevel, ApprovalRiskLevel.unknown);
      expect(answeredCancelled(), isFalse);
      expect(errors(), isEmpty);

      final entries = warnings();
      expect(entries, hasLength(3));
      expect(entries.map((e) => e['method']), [
        'session/update',
        'session/update',
        'session/request_permission',
      ]);
      expect(entries.map((e) => e['sessionUpdate']), [
        'tool_call',
        'tool_call_update',
        null,
      ]);
      expect(entries.map((e) => e['tool_call_id']), [
        'call-1',
        'call-1',
        'call-9',
      ]);
      for (final entry in entries) {
        expect(entry['session_id'], 'session-1');
        expect(entry['toolKind'], 'future_kind');
        expect(entry['component'], 'protocol');
        expect(entry['level'], 'warning');
        for (final banned in ['title', 'rawInput', 'content', 'payload']) {
          expect(entry.containsKey(banned), isFalse, reason: banned);
        }
        expect(jsonEncode(entry), isNot(contains('secret-title')));
        expect(jsonEncode(entry), isNot(contains('secret-raw-input')));
      }

      await finishPrompt(turn);
    });

    test('a 100-character kind is truncated to 64 in the record', () async {
      final turn = startPrompt();
      await _pump();

      emitUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'title': 'x',
        'kind': 'k' * 100,
      });
      await _pump();

      final kind = warnings().single['toolKind'] as String;
      expect(kind.length, lessThanOrEqualTo(64));
      expect(kind, startsWith('kkkk'));

      await finishPrompt(turn);
    });

    test('switch_mode in tool_call and permission request is switchMode '
        'without a warning', () async {
      final turn = startPrompt();
      await _pump();

      emitUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'title': 'Ready for implementation',
        'kind': 'switch_mode',
      });
      emitPermission(51, {'toolCallId': 'call-1', 'kind': 'switch_mode'});
      await _pump();

      expect(callOf('call-1')?.kind, ToolKind.switchMode);
      expect(callOf('call-1')?.riskLevel, ApprovalRiskLevel.unknown);
      final approval = turnOf().approvals.values.single;
      expect(approval.toolCall.kind, ToolKind.switchMode);
      expect(approval.riskLevel, ApprovalRiskLevel.unknown);
      expect(warnings(), isEmpty);
      expect(answeredCancelled(), isFalse);

      await finishPrompt(turn);
    });

    // acp-protocol-client «Неизвестный вид вызова инструмента»: запись при
    // приёме, до проверки хода; design.md «Risks», отмена.
    test('a future_kind permission request during cancelling is answered '
        'cancelled, logged once and creates no approval', () async {
      final turn = startPrompt();
      await _pump();
      await client.cancelTurn(const CancelTurnCommand(sessionId: _sessionId));
      expect(turnOf().status, PromptTurnStatus.cancelling);
      captured.clear();

      emitPermission(60, {'toolCallId': 'call-1', 'kind': 'future_kind'});
      await _pump();

      expect(answeredCancelled(), isTrue);
      expect(warnings(), hasLength(1));
      expect(warnings().single['method'], 'session/request_permission');
      expect(turnOf().approvals, isEmpty);

      await finishPrompt(turn);
    });

    test('tool_call without kind then tool_call_update with kind null: the '
        'kind of the record is other and nothing is logged', () async {
      final turn = startPrompt();
      await _pump();

      emitUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'title': 'x',
      });
      emitUpdate({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call-1',
        'kind': null,
        'status': 'in_progress',
      });
      await _pump();

      expect(callOf('call-1')?.kind, ToolKind.other);
      expect(callOf('call-1')?.status, ToolCallStatus.inProgress);
      expect(warnings(), isEmpty);
      expect(errors(), isEmpty);

      await finishPrompt(turn);
    });

    // D4: маскирование по полной строке, затем усечение; иначе PEM-блок
    // режется до того, как шаблон его узнает.
    test('a PEM block in kind is masked before truncation: the record has '
        'neither the header nor a body fragment', () async {
      final turn = startPrompt();
      await _pump();

      final body = 'MIIEowIBAAKCAQEA' * 8;
      emitUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'title': 'x',
        'kind':
            '-----BEGIN RSA PRIVATE KEY-----\n$body\n'
            '-----END RSA PRIVATE KEY-----',
      });
      await _pump();

      final entry = warnings().single;
      final dumped = jsonEncode(entry);
      expect(dumped, isNot(contains('BEGIN RSA PRIVATE KEY')));
      expect(dumped, isNot(contains('MIIEowIBAAKC')));

      await finishPrompt(turn);
    });

    test('tool_call with future_kind for an unknown session: one record '
        'with its session_id, the update is dropped', () async {
      emitUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'title': 'x',
        'kind': 'future_kind',
      });
      transport.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: {
            'sessionId': 'ghost-session',
            'update': {
              'sessionUpdate': 'tool_call',
              'toolCallId': 'call-2',
              'title': 'x',
              'kind': 'future_kind',
            },
          },
        ),
      );
      await _pump();

      final ghost = warnings().where((e) => e['session_id'] == 'ghost-session');
      expect(ghost, hasLength(1));
      expect(client.sessionById(const SessionId('ghost-session')), isNull);
    });

    test('a non-string kind keeps the old behaviour', () async {
      final turn = startPrompt();
      await _pump();

      emitUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'title': 'x',
        'kind': 7,
      });
      await _pump();

      expect(callOf('call-1'), isNull);
      expect(errors(), hasLength(1));
      expect(warnings(), isEmpty);

      emitPermission(52, {'toolCallId': 'call-1', 'kind': 7});
      await _pump();

      expect(turnOf().approvals, isEmpty);
      expect(answeredCancelled(), isTrue);

      await finishPrompt(turn);
    });
  });

  // D9: вид для отображения — из записи, риск — не ниже unknown.
  group('unknown kind keeps the kind of the record (D9)', () {
    test('an execute call stays execute/shell; an explicit other overwrites '
        'the kind without a new warning', () async {
      final turn = startPrompt();
      await _pump();

      emitUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-2',
        'title': 'Run',
        'kind': 'execute',
      });
      emitUpdate({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call-2',
        'kind': 'future_kind',
        'status': 'in_progress',
      });
      await _pump();

      expect(callOf('call-2')?.kind, ToolKind.execute);
      expect(callOf('call-2')?.riskLevel, ApprovalRiskLevel.shell);
      expect(warnings(), hasLength(1));

      emitUpdate({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call-2',
        'kind': 'other',
      });
      await _pump();

      expect(callOf('call-2')?.kind, ToolKind.other);
      expect(callOf('call-2')?.riskLevel, ApprovalRiskLevel.shell);
      expect(warnings(), hasLength(1));

      await finishPrompt(turn);
    });

    test('a read call lifted to unknown stays unknown after an explicit '
        'read', () async {
      final turn = startPrompt();
      await _pump();

      emitUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-6',
        'title': 'Read',
        'kind': 'read',
      });
      emitUpdate({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call-6',
        'kind': 'future_kind',
      });
      await _pump();

      expect(callOf('call-6')?.kind, ToolKind.read);
      expect(callOf('call-6')?.riskLevel, ApprovalRiskLevel.unknown);

      emitUpdate({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call-6',
        'kind': 'read',
      });
      await _pump();

      expect(callOf('call-6')?.riskLevel, ApprovalRiskLevel.unknown);

      await finishPrompt(turn);
    });

    test('a permission request with future_kind on a known read call keeps '
        'read and raises the risk to unknown', () async {
      final turn = startPrompt();
      await _pump();

      emitUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-3',
        'title': 'Read',
        'kind': 'read',
      });
      emitPermission(53, {'toolCallId': 'call-3', 'kind': 'future_kind'});
      await _pump();

      final approval = turnOf().approvals.values.single;
      expect(approval.toolCall.kind, ToolKind.read);
      expect(approval.riskLevel, ApprovalRiskLevel.unknown);
      expect(answeredCancelled(), isFalse);

      await finishPrompt(turn);
    });

    test('a permission request with future_kind on an unknown call is '
        'other/unknown', () async {
      final turn = startPrompt();
      await _pump();

      emitPermission(54, {'toolCallId': 'call-4', 'kind': 'future_kind'});
      await _pump();

      final approval = turnOf().approvals.values.single;
      expect(approval.toolCall.kind, ToolKind.other);
      expect(approval.riskLevel, ApprovalRiskLevel.unknown);

      await finishPrompt(turn);
    });

    test(
      'tool_call and tool_call_update with future_kind give other',
      () async {
        final turn = startPrompt();
        await _pump();

        emitUpdate({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call-5',
          'title': 'x',
          'kind': 'future_kind',
        });
        emitUpdate({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-5',
          'kind': 'future_kind',
        });
        await _pump();

        expect(callOf('call-5')?.kind, ToolKind.other);

        await finishPrompt(turn);
      },
    );

    test('a redelivered future_kind update neither duplicates the entry nor '
        'lowers the risk', () async {
      final turn = startPrompt();
      await _pump();

      emitUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-6',
        'title': 'Read',
        'kind': 'read',
      });
      const update = {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call-6',
        'kind': 'future_kind',
        'status': 'in_progress',
      };
      emitUpdate(update);
      await _pump();
      final once = callOf('call-6');
      final updatesOnce = turnOf().updates.length;

      emitUpdate(update);
      await _pump();

      expect(callOf('call-6'), once);
      expect(turnOf().updates, hasLength(updatesOnce));
      expect(callOf('call-6')?.kind, ToolKind.read);
      expect(callOf('call-6')?.riskLevel, ApprovalRiskLevel.unknown);

      await finishPrompt(turn);
    });
  });

  group('replay and early buffer', () {
    test(
      'session/load replay with future_kind keeps the degradation',
      () async {
        final future = client.loadSession(
          const LoadSessionCommand(sessionId: _sessionId, cwd: '/workspace'),
        );
        await _pump();
        final request = transport.sentMessages
            .whereType<JsonRpcRequest>()
            .single;
        captured.clear();

        emitUpdate({
          'sessionUpdate': 'user_message_chunk',
          'content': {'type': 'text', 'text': 'q'},
        });
        emitUpdate({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call-7',
          'title': 'x',
          'kind': 'future_kind',
        });
        emitUpdate({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call-8',
          'title': 'Read',
          'kind': 'read',
        });
        emitUpdate({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'call-8',
          'kind': 'future_kind',
        });
        transport.emitInbound(
          JsonRpcMessage.response(
            id: request.id,
            result: const LoadSessionResponse().toJson(),
          ),
        );
        await future;

        final turn = client.sessionById(_sessionId)!.turns.single;
        expect(
          turn.toolCalls[const ToolCallId('call-7')]?.kind,
          ToolKind.other,
        );
        expect(turn.toolCalls[const ToolCallId('call-8')]?.kind, ToolKind.read);
        expect(
          turn.toolCalls[const ToolCallId('call-8')]?.riskLevel,
          ApprovalRiskLevel.unknown,
        );
        // Запись WARN — на каждое сообщение с незнакомым видом (call-7 и
        // update call-8), в том числе в реплее; tool_call call-8 вида read
        // записи не даёт.
        expect(warnings(), hasLength(2));
      },
    );

    test('an early update with future_kind is logged and does not break '
        'session creation', () async {
      // Новая сессия: обновления приходят до ответа `session/new`.
      final future = client.createSession(
        const CreateSessionCommand(cwd: '/workspace'),
      );
      await _pump();
      final request = transport.sentMessages.whereType<JsonRpcRequest>().last;

      void emitFor(String sessionId, Map<String, Object?> update) {
        transport.emitInbound(
          JsonRpcMessage.notification(
            method: sessionUpdateMethod,
            params: {'sessionId': sessionId, 'update': update},
          ),
        );
      }

      emitFor('session-2', {
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-8',
        'title': 'Read',
        'kind': 'read',
      });
      emitFor('session-2', {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call-8',
        'kind': 'future_kind',
      });
      transport.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          result: const NewSessionResponse(
            sessionId: SessionId('session-2'),
          ).toJson(),
        ),
      );
      await future;

      // Состояние раннего буфера не наблюдаемо: у новой сессии нет активного
      // хода, и обновления вызовов отбрасываются (`session has no active
      // prompt turn`). Проверяем то, что наблюдаемо: сессия создана без
      // ошибок, а запись WARN сделана при приёме, до буфера (D4, D9).
      expect(client.sessionById(const SessionId('session-2')), isNotNull);
      expect(errors(), isEmpty);
      expect(warnings(), hasLength(1));
    });
  });
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

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
      result: const NewSessionResponse(sessionId: _sessionId).toJson(),
    ),
  );
  await future;
}
