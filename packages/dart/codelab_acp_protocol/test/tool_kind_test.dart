import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:test/test.dart';

/// Мягкий разбор вида вызова инструмента (change `tolerate-unknown-tool-kind`,
/// D1–D4; требование acp-protocol-client «Неизвестный вид вызова
/// инструмента»). Незнакомая строка `kind` — подсказка отображения из
/// будущей версии ACP (`17-Schema.md#toolkind`), поэтому сводится к `other`,
/// а не ломает весь `tool_call` или запрос разрешения.
SessionUpdate _decodeUpdate(Map<String, Object?> update) {
  final notification =
      decodeAcpNotificationParams(
            JsonRpcMessage.notification(
                  method: sessionUpdateMethod,
                  params: {'sessionId': 's', 'update': update},
                )
                as JsonRpcNotification,
          )
          as SessionNotification;
  return notification.update;
}

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

void main() {
  group('ToolKind.fromJson', () {
    test('switch_mode is a known kind (D2)', () {
      expect(ToolKind.fromJson('switch_mode'), ToolKind.switchMode);
      expect(ToolKind.switchMode.toJson(), 'switch_mode');
    });

    test('an unknown or empty string becomes other (D1)', () {
      expect(ToolKind.fromJson('future_kind'), ToolKind.other);
      expect(ToolKind.fromJson(''), ToolKind.other);
    });

    test('a non-string is an invalid shape, not a future value (D1)', () {
      for (final value in <Object?>[
        7,
        true,
        <String, Object?>{},
        <Object?>[],
      ]) {
        expectInvalidShape(() => ToolKind.fromJson(value));
      }
    });
  });

  group('session/update with an unknown tool kind', () {
    test('tool_call with an unknown kind decodes to other', () {
      final update = _decodeUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'title': 'Future tool',
        'kind': 'future_kind',
        'status': 'pending',
      });

      final call = (update as ToolCallSessionUpdate).toolCall;
      expect(call.kind, ToolKind.other);
    });

    test('tool_call without kind is other (unchanged)', () {
      final update = _decodeUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'title': 'No kind',
      });

      expect((update as ToolCallSessionUpdate).toolCall.kind, ToolKind.other);
    });

    test('tool_call with a non-string kind is an invalid shape', () {
      expectInvalidShape(
        () => _decodeUpdate({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call-1',
          'title': 'Bad kind',
          'kind': 7,
        }),
      );
    });

    test(
      'tool_call_update: unknown kind is other, null and absent are null',
      () {
        ToolCallUpdate decode(Map<String, Object?> extra) {
          final update = _decodeUpdate({
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'call-1',
            'status': 'completed',
            ...extra,
          });
          return (update as ToolCallUpdateSessionUpdate).toolCallUpdate;
        }

        expect(decode({'kind': 'future_kind'}).kind, ToolKind.other);
        expect(decode({'kind': null}).kind, isNull);
        expect(decode({}).kind, isNull);
      },
    );

    test('toJson of a decoded unknown kind writes other (D3)', () {
      final update = _decodeUpdate({
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'title': 'Future tool',
        'kind': 'future_kind',
      });

      final json = (update as ToolCallSessionUpdate).toolCall.toJson();
      expect(json['kind'], 'other');
    });
  });

  group('session/request_permission with an unknown tool kind', () {
    test('toolCall.kind future_kind decodes (D1)', () {
      final request =
          decodeAcpRequestParams(
                JsonRpcMessage.request(
                      id: const JsonRpcId.integer(1),
                      method: sessionRequestPermissionMethod,
                      params: {
                        'sessionId': 's',
                        'toolCall': {
                          'toolCallId': 'call-1',
                          'kind': 'future_kind',
                        },
                        'options': [
                          {
                            'optionId': 'reject',
                            'name': 'Reject',
                            'kind': 'reject_once',
                          },
                        ],
                      },
                    )
                    as JsonRpcRequest,
              )
              as RequestPermissionRequest;

      expect(request.toolCall.kind, ToolKind.other);
      expect(request.toJson()['toolCall'], containsPair('kind', 'other'));
    });
  });

  group('unrecognizedToolKind (D4)', () {
    test('returns the raw string of a kind missing from ToolKind', () {
      expect(unrecognizedToolKind({'kind': 'future_kind'}), 'future_kind');
    });

    test('returns null for known kinds, absent or non-string kind', () {
      expect(unrecognizedToolKind({'kind': 'read'}), isNull);
      expect(unrecognizedToolKind({'kind': 'switch_mode'}), isNull);
      expect(unrecognizedToolKind({'kind': null}), isNull);
      expect(unrecognizedToolKind({'kind': 7}), isNull);
      expect(unrecognizedToolKind(<String, Object?>{}), isNull);
    });

    test('returns null for a non-object', () {
      expect(unrecognizedToolKind(null), isNull);
      expect(unrecognizedToolKind('x'), isNull);
      expect(unrecognizedToolKind(<Object?>[]), isNull);
    });

    test('works on a JSON-decoded payload', () {
      final raw = jsonDecode('{"kind":"future_kind","toolCallId":"c"}');
      expect(unrecognizedToolKind(raw), 'future_kind');
    });
  });
}
