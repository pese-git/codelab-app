import 'dart:convert';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

JsonRpcNotification _update(String json) =>
    JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: jsonDecode(json),
        )
        as JsonRpcNotification;

SessionNotification _decode(String json) =>
    decodeAcpNotificationParams(_update(json)) as SessionNotification;

void expectInvalidShape(void Function() decode) {
  expect(
    decode,
    throwsA(
      isA<JsonRpcProtocolException>().having(
        (error) => error.kind,
        'kind',
        JsonRpcProtocolErrorKind.invalidShape,
      ),
    ),
  );
}

// What @agentclientprotocol/claude-agent-acp 0.88.0 really sends.
const _realAgentMessageChunk =
    '{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk",'
    '"content":{"type":"text","text":"pong"},"messageId":"msg_011"}}';
const _realUsageUpdate =
    '{"sessionId":"s","update":{"sessionUpdate":"usage_update","used":37758,'
    '"size":1000000,"cost":{"amount":0.75,"currency":"USD"},'
    '"_meta":{"_claude/model":"x"}}}';

void main() {
  group(
    'decodeAcpNotificationParams tolerates unknown fields in session/update',
    () {
      test('agent_message_chunk with the real agent `messageId`', () {
        final notification = _decode(_realAgentMessageChunk);

        expect(notification.sessionId, const SessionId('s'));
        expect(
          notification.update,
          isA<AgentMessageChunk>().having(
            (update) => update.content,
            'content',
            const ContentBlock.text(text: 'pong'),
          ),
        );
      });

      test('unknown field on the notification root', () {
        final notification = _decode(
          '{"sessionId":"s","futureRoot":1,"update":'
          '{"sessionUpdate":"agent_message_chunk",'
          '"content":{"type":"text","text":"hi"}}}',
        );

        expect(notification.update, isA<AgentMessageChunk>());
      });

      test('unknown fields in nested objects', () {
        final toolCall = _decode(
          '{"sessionId":"s","update":{"sessionUpdate":"tool_call",'
          '"toolCallId":"c1","title":"Read","kind":"read","status":"pending",'
          '"vendorFlag":true,"locations":[{"path":"/a","vendor":1}],'
          '"content":[{"type":"content","vendor":1,'
          '"content":{"type":"text","text":"x","vendor":2}}]}}',
        );
        expect(toolCall.update, isA<ToolCallSessionUpdate>());

        final plan = _decode(
          '{"sessionId":"s","update":{"sessionUpdate":"plan","entries":'
          '[{"content":"a","priority":"high","status":"pending","vendor":1}]}}',
        );
        expect((plan.update as PlanUpdate).entries, hasLength(1));
      });
    },
  );

  group('session/update still rejects invalid shapes', () {
    test('a missing required field', () {
      expectInvalidShape(
        () => _decode(
          '{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk"}}',
        ),
      );
    });

    test('a known field of the wrong type', () {
      expectInvalidShape(
        () => _decode(
          '{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk",'
          '"content":"pong"}}',
        ),
      );
    });

    test('an unknown discriminator inside a known update kind', () {
      expectInvalidShape(
        () => _decode(
          '{"sessionId":"s","update":{"sessionUpdate":"agent_message_chunk",'
          '"content":{"type":"made_up","text":"x"}}}',
        ),
      );
      expectInvalidShape(
        () => _decode(
          '{"sessionId":"s","update":{"sessionUpdate":"tool_call",'
          '"toolCallId":"c1","title":"t","status":"made_up"}}',
        ),
      );
    });

    test('an update that is not an object', () {
      expectInvalidShape(() => _decode('{"sessionId":"s","update":"oops"}'));
    });

    test(
      'an unknown update kind is not decodable (it is skipped upstream)',
      () {
        expectInvalidShape(() => _decode(_realUsageUpdate));
      },
    );
  });

  group('everything else stays strict', () {
    test('decodeAcpParams and SessionUpdate.fromJson', () {
      expectInvalidShape(
        () => decodeAcpParams(
          sessionUpdateMethod,
          jsonDecode(_realAgentMessageChunk),
        ),
      );
      expectInvalidShape(
        () => SessionUpdate.fromJson(
          (jsonDecode(_realAgentMessageChunk) as Map)['update'],
        ),
      );
    });

    test('requests the agent initiates', () {
      final permission =
          JsonRpcMessage.request(
                id: const JsonRpcId.integer(1),
                method: sessionRequestPermissionMethod,
                params: jsonDecode(
                  '{"sessionId":"s","customRoot":true,'
                  '"toolCall":{"toolCallId":"c1"},'
                  '"options":[{"optionId":"o","name":"Allow","kind":"allow_once"}]}',
                ),
              )
              as JsonRpcRequest;
      expectInvalidShape(() => decodeAcpRequestParams(permission));

      final read =
          JsonRpcMessage.request(
                id: const JsonRpcId.integer(2),
                method: fsReadTextFileMethod,
                params: jsonDecode(
                  '{"sessionId":"s","path":"/a","customRoot":true}',
                ),
              )
              as JsonRpcRequest;
      expectInvalidShape(() => decodeAcpRequestParams(read));
    });

    test('tolerance does not leak out of decodeAcpNotificationParams', () {
      _decode(_realAgentMessageChunk);
      expectInvalidShape(
        () => SessionUpdate.fromJson(
          (jsonDecode(_realAgentMessageChunk) as Map)['update'],
        ),
      );

      // ... including after a decode that threw.
      expectInvalidShape(() => _decode('{"sessionId":"s","update":"oops"}'));
      expectInvalidShape(
        () => SessionUpdate.fromJson(
          (jsonDecode(_realAgentMessageChunk) as Map)['update'],
        ),
      );
    });
  });

  group('unsupportedSessionUpdateKind', () {
    test('returns the kind of an update this client does not know', () {
      expect(
        unsupportedSessionUpdateKind(jsonDecode(_realUsageUpdate)),
        'usage_update',
      );
    });

    test('returns null for known kinds and for malformed params', () {
      expect(
        unsupportedSessionUpdateKind(jsonDecode(_realAgentMessageChunk)),
        isNull,
      );
      for (final params in <Object?>[
        null,
        'oops',
        <String, dynamic>{},
        {'update': 'oops'},
        {'update': <String, dynamic>{}},
        {
          'update': {'sessionUpdate': 1},
        },
      ]) {
        expect(unsupportedSessionUpdateKind(params), isNull, reason: '$params');
      }
    });

    test('knownKinds matches what SessionUpdate.fromJson understands', () {
      // A known kind may fail for other reasons (missing fields), but never as
      // "not supported"; a made-up kind fails exactly that way.
      String? unsupportedMessage(String kind) {
        try {
          SessionUpdate.fromJson({'sessionUpdate': kind});
        } on JsonRpcProtocolException catch (error) {
          return error.message.contains('is not supported')
              ? error.message
              : null;
        }
        return null;
      }

      for (final kind in SessionUpdate.knownKinds) {
        expect(unsupportedMessage(kind), isNull, reason: kind);
      }
      expect(unsupportedMessage('usage_update'), isNotNull);
    });
  });
}
