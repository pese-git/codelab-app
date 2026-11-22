// Кадры ACP клиента (задача 1.3 `[client]` change `redesign-protocol-pane`;
// design.md, D2, D3, D17; spec acp-protocol-client «Кадры ACP клиента»).
//
// Красный тест: файл не компилируется, пока задача 1.4 не добавит
// `ProtocolFrame`, `ProtocolFrameDirection`, `ProtocolFrameKind`,
// `ProtocolPayloadPolicy`, `ProtocolPayloadOmitted`,
// `AcpClientApplication.protocolFrames`, параметр конструктора
// `protocolPayloads` и метод `setFrameTrace`. Имена перечислений значений и
// поле `payloadOmitted` взяты из таблицы D2; тип `payload` — JSON-объект
// (`Map`), его читают приведением к `Map`.
//
// Часы для тестов (D2) здесь не используются: порядок проверяется по `seq`.

import 'dart:async';
import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:structured_log/structured_log.dart';
import 'package:test/test.dart';

const _session = SessionId('s_7f3a');

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;
  late List<ProtocolFrame> frames;
  late List<Map<String, dynamic>> logged;
  StreamSubscription<ProtocolFrame>? framesSub;

  Future<void> start({
    ProtocolPayloadPolicy? policy,
    TextFileReader? reader,
  }) async {
    transport = FakeAcpTransport();
    await transport.start();
    client = AcpClientApplication(
      transport: transport,
      textFileReader: reader,
      protocolPayloads: policy ?? ProtocolPayloadPolicy.metadataOnly,
    );
    frames = [];
    framesSub = client.protocolFrames.listen(frames.add);
  }

  setUp(() {
    logged = [];
    configureCodeLabLogging(
      applicationOutput: (entry, level) {},
      protocolTraceOutput: (entry, level) {},
      inAppViewerOutput: (entry, level) => logged.add(entry),
    );
  });

  tearDown(() async {
    await framesSub?.cancel();
    await client.dispose();
    await transport.close();
    StructlogConfiguration.reset();
  });

  /// Создаёт сессию [_session] и сбрасывает накопленные кадры.
  Future<void> openSession({String cwd = '/workspace'}) async {
    final created = client.createSession(CreateSessionCommand(cwd: cwd));
    await pumpEventQueue();
    transport.emitInbound(
      JsonRpcMessage.response(
        id: (transport.sentMessages.last as JsonRpcRequest).id,
        result: const NewSessionResponse(sessionId: _session).toJson(),
      ),
    );
    await created;
    await pumpEventQueue();
    frames.clear();
  }

  /// Запускает ход и возвращает id отправленного `session/prompt`.
  Future<JsonRpcId> startPrompt() async {
    // Ошибка хода при `dispose` в `tearDown` не должна уходить в зону теста.
    client
        .sendPrompt(
          const SendPromptCommand(
            sessionId: _session,
            prompt: [ContentBlock.text(text: 'hello')],
          ),
        )
        .then<void>((_) {}, onError: (_) {});
    await pumpEventQueue();
    return (transport.sentMessages.last as JsonRpcRequest).id;
  }

  group('метаданные кадра', () {
    setUp(start);

    test('ответ получает метод и сессию своего запроса', () async {
      await openSession();
      final id = await startPrompt();
      transport.emitInbound(
        JsonRpcMessage.response(
          id: id,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await pumpEventQueue();

      final request = frames.singleWhere(
        (f) => f.kind == ProtocolFrameKind.request,
      );
      expect(request.direction, ProtocolFrameDirection.outbound);
      expect(request.method, sessionPromptMethod);
      expect(request.sessionId, _session.value);

      final reply = frames.singleWhere(
        (f) => f.kind == ProtocolFrameKind.result,
      );
      expect(reply.direction, ProtocolFrameDirection.inbound);
      expect(reply.method, sessionPromptMethod);
      expect(reply.id, id);
      expect(reply.sessionId, _session.value);
      expect(reply.connectionGeneration, 0);
    });

    test(
      'ответ клиента на session/request_permission несёт optionId',
      () async {
        await openSession();
        await startPrompt();
        transport.emitInbound(
          JsonRpcMessage.request(
            id: const JsonRpcId.string('a9'),
            method: sessionRequestPermissionMethod,
            params: RequestPermissionRequest(
              sessionId: _session,
              toolCall: const ToolCallUpdate(
                toolCallId: ToolCallId('call_1'),
                title: 'Run dart test',
                kind: ToolKind.execute,
                status: ToolCallStatus.pending,
              ),
              options: const [
                PermissionOption(
                  optionId: PermissionOptionId('allow_once'),
                  name: 'Allow once',
                  kind: PermissionOptionKind.allowOnce,
                ),
              ],
            ).toJson(),
          ),
        );
        await pumpEventQueue();
        await client.respondToPermission(
          const RespondToPermissionCommand.selected(
            sessionId: _session,
            approvalId: ApprovalRequestId('permission-a9'),
            optionId: PermissionOptionId('allow_once'),
          ),
        );
        await pumpEventQueue();

        final reply = frames.singleWhere(
          (f) =>
              f.direction == ProtocolFrameDirection.outbound &&
              f.kind == ProtocolFrameKind.result,
        );
        expect(reply.method, sessionRequestPermissionMethod);
        expect(reply.id, const JsonRpcId.string('a9'));
        expect(reply.sessionId, _session.value);
        expect(reply.detail, 'allow_once');
      },
    );

    test('результат session/new берёт сессию из result.sessionId', () async {
      final created = client.createSession(
        const CreateSessionCommand(cwd: '/workspace'),
      );
      await pumpEventQueue();
      final request = transport.sentMessages.last as JsonRpcRequest;
      transport.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          result: const NewSessionResponse(sessionId: _session).toJson(),
        ),
      );
      await created;
      await pumpEventQueue();

      final outbound = frames.firstWhere(
        (f) =>
            f.method == sessionNewMethod && f.kind == ProtocolFrameKind.request,
      );
      // Запрос ещё не знает сессии: привязку делает буфер kit (D6).
      expect(outbound.sessionId, isNull);
      final reply = frames.singleWhere(
        (f) => f.kind == ProtocolFrameKind.result,
      );
      expect(reply.method, sessionNewMethod);
      expect(reply.sessionId, _session.value);
    });

    test('session/update даёт подробность sessionUpdate', () async {
      await openSession();
      transport.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: {
            'sessionId': _session.value,
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'hi'},
            },
          },
        ),
      );
      await pumpEventQueue();

      final frame = frames.single;
      expect(frame.kind, ProtocolFrameKind.notification);
      expect(frame.method, sessionUpdateMethod);
      expect(frame.sessionId, _session.value);
      expect(frame.detail, 'agent_message_chunk');
    });

    test('незнакомый метод даёт кадр без подробности', () async {
      transport.emitInbound(
        const JsonRpcMessage.notification(
          method: '_vendor/custom',
          params: {'anything': 1},
        ),
      );
      await pumpEventQueue();

      final frame = frames.single;
      expect(frame.method, '_vendor/custom');
      expect(frame.kind, ProtocolFrameKind.notification);
      expect(frame.detail, isNull);
      expect(frame.sessionId, isNull);
    });

    test('seq растёт строго, в том числе через поколения', () async {
      await openSession();
      final before = frames.length;
      transport.emitInbound(
        const JsonRpcMessage.notification(method: '_vendor/a'),
      );
      await pumpEventQueue();
      final replacement = FakeAcpTransport();
      await client.reconnect(
        ReconnectCommand(transportFactory: () => replacement),
      );
      await pumpEventQueue();
      replacement.emitInbound(
        const JsonRpcMessage.notification(method: '_vendor/b'),
      );
      await pumpEventQueue();
      addTearDown(replacement.close);

      expect(before, 0);
      final seqs = [for (final f in frames) f.seq];
      expect(seqs, isNotEmpty);
      for (var i = 1; i < seqs.length; i++) {
        expect(seqs[i], greaterThan(seqs[i - 1]));
      }
      expect(frames.first.connectionGeneration, 0);
      expect(frames.last.connectionGeneration, 1);
    });
  });

  group('поколения и учёт запросов', () {
    setUp(start);

    test('кадр старого поколения не публикуется', () async {
      final old = transport;
      final replacement = FakeAcpTransport();
      addTearDown(replacement.close);
      await client.reconnect(
        ReconnectCommand(transportFactory: () => replacement),
      );
      await pumpEventQueue();
      frames.clear();

      // Старый транспорт закрыт и подписка на него снята до привязки нового:
      // поздний кадр до обработчика не доходит (AGENTS.md §9; design.md D2).
      expect(
        () => old.emitInbound(
          const JsonRpcMessage.notification(method: '_vendor/late'),
        ),
        throwsA(isA<AcpTransportException>()),
      );
      await pumpEventQueue();

      expect(frames.where((f) => f.method == '_vendor/late'), isEmpty);
    });

    test('смена поколения очищает учёт: ответ без метода запроса', () async {
      await openSession();
      final id = await startPrompt();
      final replacement = FakeAcpTransport();
      addTearDown(replacement.close);
      await client.reconnect(
        ReconnectCommand(transportFactory: () => replacement),
      );
      await pumpEventQueue();
      frames.clear();

      replacement.emitInbound(
        JsonRpcMessage.response(
          id: id,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await pumpEventQueue();

      final reply = frames.singleWhere(
        (f) => f.kind == ProtocolFrameKind.result,
      );
      expect(reply.id, id);
      expect(reply.method, isNull);
      expect(reply.sessionId, isNull);
      expect(reply.connectionGeneration, 1);
    });

    test('учёт запросов без ответа ограничен 1024 записями', () async {
      // Тысяча запросов `session/new` без ответа; ответы приходят позже.
      for (var i = 0; i < 1030; i++) {
        client
            .createSession(const CreateSessionCommand(cwd: '/workspace'))
            .then<void>((_) {}, onError: (_) {});
      }
      await pumpEventQueue();
      final requests = transport.sentMessages
          .whereType<JsonRpcRequest>()
          .where((r) => r.method == sessionNewMethod)
          .toList();
      expect(requests, hasLength(1030));
      frames.clear();

      transport.emitInbound(
        JsonRpcMessage.response(id: requests.first.id, result: const {}),
      );
      transport.emitInbound(
        JsonRpcMessage.response(id: requests.last.id, result: const {}),
      );
      await pumpEventQueue();

      final replies = frames
          .where((f) => f.kind == ProtocolFrameKind.result)
          .toList();
      // Самый старый запрос вытеснен из учёта, самый новый — нет.
      expect(replies.first.id, requests.first.id);
      expect(replies.first.method, isNull);
      expect(replies.last.id, requests.last.id);
      expect(replies.last.method, sessionNewMethod);
    });

    test('сбой построения кадра не ломает обработку сообщения', () async {
      setProtocolTracingEnabled(true);
      addTearDown(() => setProtocolTracingEnabled(false));
      // `Object()` не кодируется в JSON: размер кадра посчитать нельзя.
      transport.emitInbound(
        JsonRpcMessage.request(
          id: const JsonRpcId.integer(77),
          method: '_vendor/feature',
          params: {'bad': Object()},
        ),
      );
      await pumpEventQueue();

      // Агенту всё равно ушёл ответ `Method not found`.
      final response = transport.sentMessages
          .whereType<JsonRpcResponse>()
          .singleWhere((r) => r.id == const JsonRpcId.integer(77));
      expect(response.error?.code, jsonRpcMethodNotFoundCode);
      final failure = logged.singleWhere(
        (e) => e['event'] == 'protocol_frame.build_failed',
      );
      expect(failure['method'], '_vendor/feature');
      expect(failure['error_class'], isNotNull);
      // Кадр не публикуется (D2), а запись трассы идёт без size и payload.
      expect(
        frames.where(
          (f) =>
              f.method == '_vendor/feature' &&
              f.direction == ProtocolFrameDirection.inbound,
        ),
        isEmpty,
      );
      final traced = logged.singleWhere(
        (e) =>
            e['event'] == 'protocol_message' &&
            e['direction'] == 'inbound' &&
            e['method'] == '_vendor/feature',
      );
      expect(traced.containsKey('size'), isFalse);
      expect(traced.containsKey('payload'), isFalse);
    });
  });

  group('политика по умолчанию (metadataOnly)', () {
    setUp(start);

    test(
      'ошибка агента: код и стандартное имя, без текста и payload',
      () async {
        await openSession();
        final id = await startPrompt();
        transport.emitInbound(
          JsonRpcMessage.response(
            id: id,
            error: const JsonRpcError(
              code: -32603,
              message: 'failed at /Users/dev/secret-project',
            ),
          ),
        );
        await pumpEventQueue();

        final frame = frames.singleWhere(
          (f) => f.kind == ProtocolFrameKind.error,
        );
        expect(frame.errorCode, -32603);
        expect(frame.detail, 'Internal error');
        expect(frame.payload, isNull);
        expect(frame.payloadOmitted, ProtocolPayloadOmitted.policy);
        expect(frame.size, greaterThan(0));
        expect(frame.toString(), isNot(contains('/Users/dev')));
        expect(frame.detail, isNot(contains('secret-project')));
      },
    );

    test('незнакомый код ошибки — без подробности', () async {
      await openSession();
      final id = await startPrompt();
      transport.emitInbound(
        JsonRpcMessage.response(
          id: id,
          error: const JsonRpcError(code: -31999, message: 'vendor text'),
        ),
      );
      await pumpEventQueue();

      final frame = frames.singleWhere(
        (f) => f.kind == ProtocolFrameKind.error,
      );
      expect(frame.errorCode, -31999);
      expect(frame.detail, isNull);
    });

    test(
      'исходящий кадр не несёт payload, размер — исходного сообщения',
      () async {
        await openSession();
        await startPrompt();

        final sent = transport.sentMessages.last;
        final frame = frames.singleWhere(
          (f) => f.direction == ProtocolFrameDirection.outbound,
        );
        expect(frame.payload, isNull);
        expect(frame.payloadOmitted, ProtocolPayloadOmitted.policy);
        expect(frame.size, utf8.encode(jsonEncode(sent.toJson())).length);
      },
    );
  });

  group('политика full', () {
    setUp(() => start(policy: ProtocolPayloadPolicy.full));

    test('маскирует payload до хранения, size — исходный', () async {
      final created = client.createSession(
        const CreateSessionCommand(
          cwd: '/workspace',
          mcpServers: [
            McpServer.http(
              name: 'github',
              url: 'https://example.test/mcp',
              headers: [HttpHeader(name: 'Authorization', value: 'ghp_abc')],
            ),
          ],
        ),
      );
      created.then<void>((_) {}, onError: (_) {});
      await pumpEventQueue();

      final sent = transport.sentMessages.last as JsonRpcRequest;
      final frame = frames.singleWhere(
        (f) =>
            f.method == sessionNewMethod && f.kind == ProtocolFrameKind.request,
      );
      final text = jsonEncode(frame.payload);
      expect(text, contains(redactedSecret));
      expect(text, isNot(contains('ghp_abc')));
      expect(frame.payloadOmitted, isNull);
      expect(frame.size, utf8.encode(jsonEncode(sent.toJson())).length);
    });

    test(
      'detail ошибки — замаскированный текст не длиннее 120 символов',
      () async {
        await openSession();
        final id = await startPrompt();
        transport.emitInbound(
          JsonRpcMessage.response(
            id: id,
            error: JsonRpcError(code: -32603, message: 'x' * 300),
          ),
        );
        await pumpEventQueue();

        final frame = frames.singleWhere(
          (f) => f.kind == ProtocolFrameKind.error,
        );
        expect(frame.detail, isNotNull);
        expect(frame.detail!.length, lessThanOrEqualTo(120));
        expect(frame.payload, isNotNull);
      },
    );
  });

  group('большой payload', () {
    test('ответ на fs/read_text_file в 1 MiB — tooLarge без payload', () async {
      await start(
        policy: ProtocolPayloadPolicy.full,
        reader: _FakeReader('a' * (1024 * 1024)),
      );
      await openSession();

      transport.emitInbound(
        JsonRpcMessage.request(
          id: const JsonRpcId.integer(5),
          method: fsReadTextFileMethod,
          params: {'sessionId': _session.value, 'path': '/workspace/big.txt'},
        ),
      );
      await pumpEventQueue();

      final reply = frames.singleWhere(
        (f) =>
            f.direction == ProtocolFrameDirection.outbound &&
            f.kind == ProtocolFrameKind.result,
      );
      expect(reply.method, fsReadTextFileMethod);
      expect(reply.payload, isNull);
      expect(reply.payloadOmitted, ProtocolPayloadOmitted.tooLarge);
      expect(reply.size, greaterThan(1024 * 1024));
      expect(reply.id, const JsonRpcId.integer(5));
    });
  });

  group('режим Trace (D17)', () {
    setUp(start);

    test('выключен при создании: кадры по базовой политике', () async {
      await openSession();
      await startPrompt();

      final frame = frames.singleWhere(
        (f) => f.direction == ProtocolFrameDirection.outbound,
      );
      expect(frame.payload, isNull);
      expect(frame.payloadOmitted, ProtocolPayloadOmitted.policy);
    });

    test('сбой транспорта и ошибка протокола Trace не включают', () async {
      await openSession();
      final id = await startPrompt();
      transport.emitInbound(
        JsonRpcMessage.response(
          id: id,
          error: const JsonRpcError(code: -32603, message: 'boom'),
        ),
      );
      await pumpEventQueue();
      transport.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.sendFailed,
          message: 'boom',
        ),
      );
      await pumpEventQueue();

      expect(frames, isNotEmpty);
      expect(frames.where((f) => f.payload != null), isEmpty);
    });

    test('включение даёт payload при базовой metadataOnly, выключение — '
        'возвращает metadataOnly', () async {
      await openSession();

      client.setFrameTrace(true);
      await startPrompt();
      final traced = frames.singleWhere(
        (f) => f.direction == ProtocolFrameDirection.outbound,
      );
      expect(traced.payload, isNotNull);
      expect((traced.payload! as Map)['method'], sessionPromptMethod);
      expect(traced.payloadOmitted, isNull);

      frames.clear();
      client.setFrameTrace(false);
      transport.emitInbound(
        const JsonRpcMessage.notification(method: '_vendor/after'),
      );
      await pumpEventQueue();
      final after = frames.singleWhere((f) => f.method == '_vendor/after');
      expect(after.payload, isNull);
      expect(after.payloadOmitted, ProtocolPayloadOmitted.policy);
    });

    test('payload в Trace замаскирован тем же правилом', () async {
      client.setFrameTrace(true);
      client
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
      await pumpEventQueue();

      final frame = frames.singleWhere(
        (f) =>
            f.method == sessionNewMethod && f.kind == ProtocolFrameKind.request,
      );
      final text = jsonEncode(frame.payload);
      expect(text, contains(redactedSecret));
      expect(text, isNot(contains('ghp_abc123')));
    });

    test('двойное включение пишет одно событие', () async {
      client.setFrameTrace(true);
      client.setFrameTrace(true);
      client.setFrameTrace(false);
      client.setFrameTrace(false);

      final events = logged
          .where((e) => e['event'] == 'protocol_frames.policy')
          .map((e) => e['reason'])
          .toList();
      expect(events, ['trace_on', 'trace_off']);
    });

    test('смена режима пишет protocol_frames.policy с причиной', () async {
      client.setFrameTrace(true);
      client.setFrameTrace(false);

      final events = logged
          .where((e) => e['event'] == 'protocol_frames.policy')
          .toList();
      expect(events, hasLength(2));
      expect(events[0]['policy'], 'full');
      expect(events[0]['reason'], 'trace_on');
      expect(events[1]['policy'], 'metadataOnly');
      expect(events[1]['reason'], 'trace_off');
    });
  });

  group('Trace при базовой full', () {
    setUp(() => start(policy: ProtocolPayloadPolicy.full));

    test('traceAvailable ложен, setFrameTrace — no-op без события', () async {
      expect(client.traceAvailable, isFalse);

      client.setFrameTrace(true);
      client.setFrameTrace(false);

      expect(
        logged.where((e) => e['event'] == 'protocol_frames.policy'),
        isEmpty,
      );
      transport.emitInbound(
        const JsonRpcMessage.notification(method: '_vendor/x'),
      );
      await pumpEventQueue();
      expect(frames.single.payload, isNotNull);
    });
  });

  group('ограничение длины строк кадра (ревью, п. 6)', () {
    setUp(start);

    test('sessionUpdate и метод обрезаются до 120 символов', () async {
      transport.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: {
            'sessionId': 's1',
            'update': {'sessionUpdate': 'k' * 300},
          },
        ),
      );
      transport.emitInbound(
        JsonRpcMessage.notification(method: '_vendor/${'m' * 300}'),
      );
      await pumpEventQueue();

      expect(frames[0].detail!.length, 120);
      expect(frames[1].method!.length, 120);
    });

    test('обрезка не разрезает суррогатную пару', () async {
      // 119 символов и эмодзи (две кодовые единицы) на границе 120.
      final text = '${'a' * 119}\u{1F600}tail';
      transport.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: {
            'sessionId': 's1',
            'update': {'sessionUpdate': text},
          },
        ),
      );
      await pumpEventQueue();

      final detail = frames.single.detail!;
      // Строка без «одинокого» суррогата кодируется в UTF-8 без замены U+FFFD.
      expect(utf8.decode(utf8.encode(detail)), detail);
      expect(detail.codeUnits.last, isNot(inInclusiveRange(0xD800, 0xDBFF)));
      expect(detail, 'a' * 119);
    });
  });

  group('ключ учёта запросов различает тип id (ревью, п. 7)', () {
    setUp(start);

    test(
      'ответ со строковым id "1" не сопоставляется с запросом id 1',
      () async {
        final created = client.createSession(
          const CreateSessionCommand(cwd: '/workspace'),
        );
        created.then<void>((_) {}, onError: (_) {});
        await pumpEventQueue();
        final request = transport.sentMessages.last as JsonRpcRequest;
        expect(request.id, isA<JsonRpcIntId>());
        frames.clear();

        transport.emitInbound(
          JsonRpcMessage.response(
            id: JsonRpcId.string(request.id.toJsonValue().toString()),
            result: const {},
          ),
        );
        await pumpEventQueue();

        expect(frames.single.method, isNull);
      },
    );
  });

  group('ProtocolFrame.withoutPayload (ревью, п. 5)', () {
    test('снимает payload и текст ошибки', () {
      final frame = ProtocolFrame(
        seq: 1,
        time: DateTime.utc(2026),
        direction: ProtocolFrameDirection.inbound,
        connectionGeneration: 0,
        kind: ProtocolFrameKind.error,
        errorCode: jsonRpcInternalErrorCode,
        detail: 'at /Users/dev',
        size: 10,
        payload: {'a': 1},
      );

      final stripped = frame.withoutPayload();

      expect(stripped.payload, isNull);
      expect(stripped.payloadOmitted, ProtocolPayloadOmitted.policy);
      expect(stripped.detail, 'Internal error');
      expect(stripped.seq, 1);
      expect(stripped.size, 10);
    });

    test('tooLarge не заменяется на policy', () {
      final frame = ProtocolFrame(
        seq: 1,
        time: DateTime.utc(2026),
        direction: ProtocolFrameDirection.inbound,
        connectionGeneration: 0,
        kind: ProtocolFrameKind.result,
        size: 10,
        payloadOmitted: ProtocolPayloadOmitted.tooLarge,
      );

      expect(
        frame.withoutPayload().payloadOmitted,
        ProtocolPayloadOmitted.tooLarge,
      );
    });
  });

  test('protocolFrames закрывается в dispose', () async {
    await start();
    final done = client.protocolFrames.drain<void>();
    await client.dispose();
    await done.timeout(const Duration(seconds: 5));
  });
}

final class _FakeReader implements TextFileReader {
  _FakeReader(this.content);

  final String content;

  @override
  Future<String> readText({
    required String path,
    int? line,
    int? limit,
  }) async => content;
}
