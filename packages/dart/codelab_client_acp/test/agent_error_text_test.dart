// Текст ошибки агента в диагностике и журнале (change
// `redesign-protocol-pane`, tasks 7.1; design.md, D3, «Текст ошибки агента»;
// spec structured-logging «Ошибка агента в release», «Ошибка агента при явном
// включении», «Ключ причины не перекрывается»).
//
// `JsonRpcError.message` и `data` — payload агента: при базовой `metadataOnly`
// их нет ни в `DiagnosticEntry`, ни в записи логгера; текст для пользователя
// (`PromptTurn.failureMessage`, исключение вызывающему) сохраняет текст агента
// после маскирования. Порядок событий задаётся синхронными вызовами и
// `pumpEventQueue`, без `Future.delayed`.

import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

const _session = SessionId('s1');
const _msgMarker = 'AGENT_MSG_MARKER';
const _dataMarker = 'AGENT_DATA_MARKER';
const _token = 'sk-LEAKEDTOKEN123456';
const _agentMessage = '$_msgMarker /home/u/secret.txt api_key=$_token';
const _agentData = {'detail': _dataMarker};

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;
  late List<Map<String, dynamic>> logged;

  Future<void> start(ProtocolPayloadPolicy policy) async {
    logged = [];
    configureCodeLabLogging(
      applicationOutput: (entry, level) => logged.add(entry),
      protocolTraceOutput: (entry, level) => logged.add(entry),
      inAppViewerOutput: (entry, level) => logged.add(entry),
    );
    transport = FakeAcpTransport();
    await transport.start();
    client = AcpClientApplication(
      transport: transport,
      protocolPayloads: policy,
    );
    final created = client.createSession(
      const CreateSessionCommand(cwd: '/workspace'),
    );
    await pumpEventQueue();
    transport.emitInbound(
      JsonRpcMessage.response(
        id: (transport.sentMessages.single as JsonRpcRequest).id,
        result: const NewSessionResponse(sessionId: _session).toJson(),
      ),
    );
    await created;
    transport.drainSentMessages();
    logged.clear();
  }

  tearDown(() async {
    await client.dispose();
    await transport.close();
    StructlogConfiguration.reset();
  });

  /// Всё, что хост видит как журнал: запись логгера и диагностика ядра.
  String journal() => jsonEncode({
    'log': logged,
    'diagnostics': [
      for (final d in client.diagnostics)
        {'m': d.message, 'c': d.context, 'cause': d.cause},
    ],
    'session': [
      for (final d in client.sessionById(_session)!.diagnostics)
        {'m': d.message, 'c': d.context, 'cause': d.cause},
    ],
  }, toEncodable: (o) => o.toString());

  /// Отправляет `session/prompt`, отвечает ошибкой агента [code] и возвращает
  /// исключение вызывающего.
  Future<Object> failPrompt(int code, {Object? data = _agentData}) async {
    final outcome = client
        .sendPrompt(
          const SendPromptCommand(
            sessionId: _session,
            prompt: [ContentBlock.text(text: 'go')],
          ),
        )
        .then<Object>((_) => 'no error', onError: (Object e) => e);
    await pumpEventQueue();
    final request = transport.sentMessages.last as JsonRpcRequest;
    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        error: JsonRpcError(code: code, message: _agentMessage, data: data),
      ),
    );
    return outcome;
  }

  Map<String, dynamic> failureRecord() => logged.lastWhere(
    (e) => (e['event'] as String?)?.startsWith('ACP request') ?? false,
  );

  group('ошибка агента при metadataOnly', () {
    test('журнал без текста агента, есть метаданные -32603', () async {
      await start(ProtocolPayloadPolicy.metadataOnly);
      await failPrompt(-32603);

      final text = journal();
      expect(text, isNot(contains(_msgMarker)));
      expect(text, isNot(contains(_dataMarker)));
      expect(text, isNot(contains('secret.txt')));
      expect(text, isNot(contains(_token)));

      final entry = client.diagnostics.lastWhere(
        (d) => d.message.startsWith('ACP request'),
      );
      expect(entry.context['method'], sessionPromptMethod);
      expect(entry.context['requestId'], isNotNull);
      expect(entry.context['error_code'], -32603);
      expect(entry.context.containsKey('error'), isFalse);
      expect(entry.message, contains('Internal error'));

      final record = failureRecord();
      expect(record['method'], sessionPromptMethod);
      expect(record['error_code'], -32603);
      expect(record['event'], contains('Internal error'));
    });

    test('у незнакомого кода -32099 имени нет', () async {
      await start(ProtocolPayloadPolicy.metadataOnly);
      await failPrompt(-32099);

      final entry = client.diagnostics.lastWhere(
        (d) => d.message.startsWith('ACP request'),
      );
      expect(entry.context['error_code'], -32099);
      expect(entry.message, contains('JSON-RPC error -32099'));
      expect(entry.message, isNot(contains('(')));
      expect(journal(), isNot(contains(_msgMarker)));
    });

    test(
      'пользователь видит текст агента: failureMessage и исключение',
      () async {
        await start(ProtocolPayloadPolicy.metadataOnly);
        final error = await failPrompt(-32603);

        expect(error, isA<AcpClientApplicationException>());
        expect(
          (error as AcpClientApplicationException).message,
          contains(_msgMarker),
        );
        final turn = client.sessionById(_session)!.turns.last;
        expect(turn.failureMessage, contains(_msgMarker));
        // Токен в тексте для пользователя маскируется (SecretRedactor).
        expect(turn.failureMessage, isNot(contains(_token)));
      },
    );
  });

  group('ошибка агента при full', () {
    test('context[error] с обоими маркерами, токен замаскирован', () async {
      await start(ProtocolPayloadPolicy.full);
      final error = await failPrompt(-32603);

      final entry = client.diagnostics.lastWhere(
        (d) => d.message.startsWith('ACP request'),
      );
      final encoded = jsonEncode(entry.context['error']);
      expect(encoded, contains(_msgMarker));
      expect(encoded, contains(_dataMarker));
      final text = journal();
      expect(text, isNot(contains(_token)));
      expect(text, contains(_msgMarker));

      expect(error, isA<AcpClientApplicationException>());
      final turn = client.sessionById(_session)!.turns.last;
      expect(turn.failureMessage, contains(_msgMarker));
      expect(turn.failureMessage, isNot(contains(_token)));
    });
  });

  group('вытесненная попытка с ответом-ошибкой на initialize', () {
    /// Ответ-ошибка на `initialize` приходит и в том же такте поколение
    /// поднимает вторая попытка: продолжение первой видит вытеснение.
    Future<void> supersedeWithError(ProtocolPayloadPolicy policy) async {
      logged = [];
      configureCodeLabLogging(
        applicationOutput: (entry, level) => logged.add(entry),
        protocolTraceOutput: (entry, level) => logged.add(entry),
      );
      transport = FakeAcpTransport();
      client = AcpClientApplication(
        transport: FakeAcpTransport(),
        protocolPayloads: policy,
      );
      final stale = FakeAcpTransport()..autoRespondToInitialize = false;
      final sent = stale.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == initializeMethod,
      );
      final first = client.connect(stale);
      final firstOutcome = first.then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      final initialize = await sent as JsonRpcRequest;
      stale.emitInbound(
        JsonRpcMessage.response(
          id: initialize.id,
          error: JsonRpcError(
            code: -32603,
            message: _agentMessage,
            data: _agentData,
          ),
        ),
      );
      final second = client.connect(FakeAcpTransport());
      await firstOutcome;
      await second;
    }

    test('metadataOnly: error_class и error_code, без маркера', () async {
      await supersedeWithError(ProtocolPayloadPolicy.metadataOnly);

      final entry = logged.singleWhere(
        (e) => e['event'] == 'attempt_superseded',
      );
      expect(entry['phase'], 'initialize');
      expect(entry['error_class'], 'AcpClientApplicationException');
      expect(entry['error_code'], -32603);
      expect(entry.containsKey('error'), isFalse);
      expect(jsonEncode(entry), isNot(contains(_msgMarker)));
    });

    test('full: error с маркером, токен замаскирован', () async {
      await supersedeWithError(ProtocolPayloadPolicy.full);

      final entry = logged.singleWhere(
        (e) => e['event'] == 'attempt_superseded',
      );
      expect(entry['error'], contains(_msgMarker));
      expect(jsonEncode(entry), isNot(contains(_token)));
    });
  });

  group('сбой транспорта с вложенной причиной', () {
    Future<Map<String, dynamic>> failWithInner(
      ProtocolPayloadPolicy policy,
    ) async {
      await start(policy);
      transport.fail(
        AcpTransportException(
          code: AcpTransportErrorCode.receiveFailed,
          message: 'socket dropped',
          cause: StateError('inner boom api_key=$_token'),
        ),
      );
      await pumpEventQueue();
      return logged.lastWhere((e) => e['event'] == 'socket dropped');
    }

    test('metadataOnly: cause и inner_cause — классы, без текста', () async {
      final record = await failWithInner(ProtocolPayloadPolicy.metadataOnly);

      expect(record['cause'], isNotNull);
      expect(record['inner_cause'], 'StateError');
      expect(jsonEncode(record), isNot(contains('inner boom')));
      expect(record['code'], 'receiveFailed');
    });

    test('full: inner_cause с текстом, токен замаскирован', () async {
      final record = await failWithInner(ProtocolPayloadPolicy.full);

      expect(record['cause'], isNotNull);
      expect(record['inner_cause'], contains('inner boom'));
      expect(record['cause'], isNot(contains('inner boom')));
      expect(jsonEncode(record), isNot(contains(_token)));
    });
  });

  group('PromptFailure.message для пользователя маскируется', () {
    test('request: токен скрыт, маркер на месте', () async {
      await start(ProtocolPayloadPolicy.metadataOnly);
      await failPrompt(-32603);

      final failure = client.sessionById(_session)!.turns.last.failure;
      expect(failure, isA<RequestPromptFailure>());
      final message = (failure! as RequestPromptFailure).message;
      expect(message, contains(_msgMarker));
      expect(message, isNot(contains(_token)));
    });

    test('agent (data.codelab): токен скрыт, маркер на месте', () async {
      await start(ProtocolPayloadPolicy.metadataOnly);
      await failPrompt(
        -32603,
        data: const {
          'codelab': {'errorClass': 'tool', 'message': _agentMessage},
        },
      );

      final failure = client.sessionById(_session)!.turns.last.failure;
      expect(failure, isA<AgentPromptFailure>());
      final message = (failure! as AgentPromptFailure).message;
      expect(message, contains(_msgMarker));
      expect(message, isNot(contains(_token)));
    });
  });

  group('describeFailureMetadata', () {
    const jsonRpc = JsonRpcError(
      code: -32603,
      message: _agentMessage,
      data: _agentData,
    );

    test('JsonRpcError: код и стандартное имя', () {
      expect(
        describeFailureMetadata(jsonRpc),
        'JSON-RPC error -32603 (Internal error)',
      );
      expect(
        describeFailureMetadata(const JsonRpcError(code: -32099, message: 'x')),
        'JSON-RPC error -32099',
      );
    });

    test('исключение с причиной JsonRpcError: класс и код', () {
      final text = describeFailureMetadata(
        const AcpClientApplicationException(
          'ACP request x failed: $_agentMessage',
          cause: jsonRpc,
        ),
      );
      expect(
        text,
        'AcpClientApplicationException: JSON-RPC error -32603 (Internal error)',
      );
      expect(text, isNot(contains(_msgMarker)));
    });

    test('AcpTransportException: имя кода без текста', () {
      final text = describeFailureMetadata(
        const AcpTransportException(
          code: AcpTransportErrorCode.sendFailed,
          message: 'secret message',
        ),
      );
      expect(text, 'AcpTransportException(sendFailed)');
    });

    test('прочее: runtimeType', () {
      expect(describeFailureMetadata(StateError('private text')), 'StateError');
    });
  });

  group('protocolPayloads', () {
    for (final policy in ProtocolPayloadPolicy.values) {
      test('отдаёт переданную политику ($policy) и не зависит от Trace', () {
        final app = AcpClientApplication(
          transport: FakeAcpTransport(),
          protocolPayloads: policy,
        );
        addTearDown(app.dispose);
        expect(app.protocolPayloads, policy);
        app.setFrameTrace(true);
        expect(app.protocolPayloads, policy);
      });
    }

    test('по умолчанию metadataOnly', () {
      final app = AcpClientApplication(transport: FakeAcpTransport());
      addTearDown(app.dispose);
      expect(app.protocolPayloads, ProtocolPayloadPolicy.metadataOnly);
    });
  });
}
