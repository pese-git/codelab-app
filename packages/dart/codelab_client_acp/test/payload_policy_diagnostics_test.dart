// Политика payload в ветках обработки и диагностики (ревью change
// `redesign-protocol-pane`, пп. 2–4; design.md, D3).
//
// Красные тесты: при базовой `metadataOnly` ни запись категории `protocol`, ни
// диагностика (поток `diagnostics`, сессия, журнал) не должны нести сырые
// `params`/`result`/`payload` — только метод и размер; при `full` остаются как
// прежде. Позднее разрешение при отменяемом ходе проходит через ту же точку
// кадров, что и остальные исходящие сообщения.

import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

const _session = SessionId('s1');
const _marker = 'MARKER-private-prompt-text';

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;
  late List<Map<String, dynamic>> logged;
  late List<ProtocolFrame> frames;

  Future<void> start(
    ProtocolPayloadPolicy policy, {
    TextFileReader? reader,
  }) async {
    logged = [];
    frames = [];
    configureCodeLabLogging(
      applicationOutput: (entry, level) {},
      protocolTraceOutput: (entry, level) {},
      inAppViewerOutput: (entry, level) => logged.add(entry),
    );
    transport = FakeAcpTransport();
    await transport.start();
    client = AcpClientApplication(
      transport: transport,
      textFileReader: reader,
      protocolPayloads: policy,
    );
    client.protocolFrames.listen(frames.add);
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
    frames.clear();
  }

  tearDown(() async {
    await client.dispose();
    await transport.close();
    StructlogConfiguration.reset();
  });

  /// Всё, что хост может увидеть о сообщении: журнал и диагностика.
  String observable() => jsonEncode({
    'log': logged,
    'diagnostics': [
      for (final d in client.diagnostics) {'m': d.message, 'c': d.context},
    ],
  }, toEncodable: (o) => o.toString());

  Future<void> startPrompt() async {
    client
        .sendPrompt(
          const SendPromptCommand(
            sessionId: _session,
            prompt: [ContentBlock.text(text: 'go')],
          ),
        )
        .then<void>((_) {}, onError: (_) {});
    await pumpEventQueue();
  }

  group('неподдерживаемый sessionUpdate (п. 2)', () {
    void emit() => transport.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: {
          'sessionId': _session.value,
          'update': {'sessionUpdate': 'vendor_new_kind', 'text': _marker},
        },
      ),
    );

    test('metadataOnly: запись без payload', () async {
      await start(ProtocolPayloadPolicy.metadataOnly);
      emit();
      await pumpEventQueue();

      final skipped = logged.where(
        (e) => e['event'] == 'Skipped unsupported ACP session update.',
      );
      expect(skipped, isNotEmpty);
      for (final e in skipped) {
        expect(e.containsKey('payload'), isFalse);
      }
      expect(observable(), isNot(contains(_marker)));
    });

    test('full: запись с payload в категории protocol', () async {
      await start(ProtocolPayloadPolicy.full);
      emit();
      await pumpEventQueue();

      expect(
        logged.any(
          (e) =>
              e['category'] == 'protocol' &&
              e['event'] == 'Skipped unsupported ACP session update.' &&
              e.containsKey('payload'),
        ),
        isTrue,
      );
    });
  });

  group('ответ cancelled на позднее разрешение (п. 3)', () {
    test('идёт через точку кадров: кадр и protocol_message', () async {
      await start(ProtocolPayloadPolicy.metadataOnly);
      setProtocolTracingEnabled(true);
      addTearDown(() => setProtocolTracingEnabled(false));
      await startPrompt();
      await client.cancelTurn(const CancelTurnCommand(sessionId: _session));
      await pumpEventQueue();
      frames.clear();
      logged.clear();

      transport.emitInbound(
        JsonRpcMessage.request(
          id: const JsonRpcId.integer(41),
          method: sessionRequestPermissionMethod,
          params: RequestPermissionRequest(
            sessionId: _session,
            toolCall: const ToolCallUpdate(
              toolCallId: ToolCallId('c1'),
              title: 'Run',
              kind: ToolKind.execute,
              status: ToolCallStatus.pending,
            ),
            options: const [
              PermissionOption(
                optionId: PermissionOptionId('allow'),
                name: 'Allow',
                kind: PermissionOptionKind.allowOnce,
              ),
            ],
          ).toJson(),
        ),
      );
      await pumpEventQueue();

      final reply = frames.singleWhere(
        (f) =>
            f.direction == ProtocolFrameDirection.outbound &&
            f.kind == ProtocolFrameKind.result,
      );
      expect(reply.method, sessionRequestPermissionMethod);
      expect(reply.id, const JsonRpcId.integer(41));
      expect(reply.detail, 'cancelled');
      expect(
        logged.any(
          (e) =>
              e['event'] == 'protocol_message' &&
              e['direction'] == 'outbound' &&
              e['method'] == sessionRequestPermissionMethod,
        ),
        isTrue,
      );
    });
  });

  group('ветки ошибок не пишут сырые params и result (п. 4)', () {
    // `session/prompt` с ответом неверной формы: декодирование результата
    // падает, диагностика несёт `result`.
    Future<void> failDecode() async {
      client
          .sendPrompt(
            const SendPromptCommand(
              sessionId: _session,
              prompt: [ContentBlock.text(text: 'go')],
            ),
          )
          .then<void>((_) {}, onError: (_) {});
      await pumpEventQueue();
      transport.emitInbound(
        JsonRpcMessage.response(
          id: (transport.sentMessages.last as JsonRpcRequest).id,
          result: const {'stopReason': 'no_such_reason', 'note': _marker},
        ),
      );
      await pumpEventQueue();
    }

    void failPermission() => transport.emitInbound(
      const JsonRpcMessage.request(
        id: JsonRpcId.integer(7),
        method: sessionRequestPermissionMethod,
        params: {'sessionId': 's1', 'toolCall': 42, 'note': _marker},
      ),
    );

    void failSessionUpdate() => transport.emitInbound(
      const JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: {
          'sessionId': 's1',
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': _marker,
          },
        },
      ),
    );

    final branches = <String, (Future<void> Function(), String)>{
      'декодирование результата': (failDecode, 'Failed to decode ACP response'),
      'запрос разрешения': (
        () async {
          failPermission();
          await pumpEventQueue();
        },
        'Failed to handle ACP permission request.',
      ),
      'обновление сессии': (
        () async {
          failSessionUpdate();
          await pumpEventQueue();
        },
        'Failed to handle ACP session update.',
      ),
    };

    for (final entry in branches.entries) {
      test('metadataOnly: ${entry.key} — только method и size', () async {
        await start(ProtocolPayloadPolicy.metadataOnly);
        await entry.value.$1();

        final diag = client.diagnostics.where(
          (d) => d.message.startsWith(entry.value.$2),
        );
        expect(diag, isNotEmpty, reason: 'ветка должна сработать');
        for (final d in diag) {
          expect(d.context.containsKey('result'), isFalse);
          expect(d.context.containsKey('params'), isFalse);
          expect(d.context['method'], isNotNull);
          expect(d.context['size'], isA<int>());
        }
        expect(observable(), isNot(contains(_marker)));
      });

      test('full: ${entry.key} — как прежде, с сырыми данными', () async {
        await start(ProtocolPayloadPolicy.full);
        await entry.value.$1();

        final diag = client.diagnostics.where(
          (d) => d.message.startsWith(entry.value.$2),
        );
        expect(diag, isNotEmpty);
        expect(
          diag.any(
            (d) =>
                d.context.containsKey('result') ||
                d.context.containsKey('params'),
          ),
          isTrue,
        );
      });
    }
  });

  group('причина сбоя (cause) не несёт данных агента (итерация 3, п. 3)', () {
    // Адаптер чтения бросает исключение, текст которого содержит данные:
    // `cause.toString()` попал бы в диагностику, сессию и журнал.
    Future<void> failRead() async {
      transport.emitInbound(
        JsonRpcMessage.request(
          id: const JsonRpcId.integer(9),
          method: fsReadTextFileMethod,
          params: {'sessionId': _session.value, 'path': '/workspace/a.txt'},
        ),
      );
      await pumpEventQueue();
    }

    DiagnosticEntry failure() => client.diagnostics.singleWhere(
      (d) => d.message.startsWith('Failed to handle ACP fs/read_text_file'),
    );

    test('metadataOnly: только класс ошибки, без cause.toString()', () async {
      await start(
        ProtocolPayloadPolicy.metadataOnly,
        reader: _ThrowingReader(),
      );
      await failRead();

      final diag = failure();
      expect(diag.cause, isNotNull);
      expect(diag.cause, contains('_ReaderFailure'));
      expect(diag.cause, isNot(contains(_marker)));
      expect(observable(), isNot(contains(_marker)));
    });

    test('full: замаскированный текст причины, как прежде', () async {
      await start(ProtocolPayloadPolicy.full, reader: _ThrowingReader());
      await failRead();

      expect(failure().cause, contains(_marker));
    });
  });

  group('внутренняя причина сбоя транспорта (D3, observability.md §48а)', () {
    // Внутренняя причина `AcpTransportException` — `SocketException`,
    // `JsonRpcProtocolException` с фрагментом кадра, путь процесса агента:
    // её текст не должен уходить в `context` диагностики при `metadataOnly`
    // (observability.md §48а; D3 change `redesign-protocol-pane`).
    void failTransport() => transport.fail(
      AcpTransportException(
        code: AcpTransportErrorCode.protocolViolation,
        message: 'Agent wrote invalid ACP JSON-RPC to stdout.',
        cause: _FrameFailure(),
      ),
    );

    DiagnosticEntry failure() =>
        client.diagnostics.singleWhere((d) => d.source == 'transport');

    test('metadataOnly: code и класс причины, без её текста', () async {
      await start(ProtocolPayloadPolicy.metadataOnly);
      failTransport();
      await pumpEventQueue();

      final diag = failure();
      expect(
        diag.context['code'],
        AcpTransportErrorCode.protocolViolation.name,
      );
      expect(diag.context['inner_cause'], '_FrameFailure');
      expect(observable(), isNot(contains(_marker)));
    });

    test('full: замаскированный текст причины, как прежде', () async {
      await start(ProtocolPayloadPolicy.full);
      failTransport();
      await pumpEventQueue();

      final diag = failure();
      expect(
        diag.context['code'],
        AcpTransportErrorCode.protocolViolation.name,
      );
      expect(diag.context['inner_cause'], contains(_marker));
    });
  });
}

final class _FrameFailure implements Exception {
  @override
  String toString() => '_FrameFailure: frame fragment $_marker';
}

final class _ReaderFailure implements Exception {
  @override
  String toString() => '_ReaderFailure: file said $_marker';
}

final class _ThrowingReader implements TextFileReader {
  @override
  Future<String> readText({
    required String path,
    int? line,
    int? limit,
  }) async => throw _ReaderFailure();
}
