import 'dart:convert';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

// `jsonDecode` yields the `Map<String, dynamic>` that `requireJsonObject`
// expects (an empty `{}` literal would infer `Map<dynamic, dynamic>`).
Object? _json(String source) => jsonDecode(source);

const _configOption =
    '{"id":"model","name":"Model","category":"model","type":"select",'
    '"currentValue":"a","options":[{"value":"a","name":"A"}]}';

// What @zed-industries/claude-code-acp 0.16.2 really answers to session/new.
const _realNewSessionResult =
    '{"sessionId":"92e5f32a","models":{"availableModels":['
    '{"modelId":"default","name":"Default","description":"Opus"}],'
    '"currentModelId":"default"},"modes":{"currentModeId":"default",'
    '"availableModes":[{"id":"default","name":"Default","description":"d"}]}}';

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
  group('decodeAcpResult tolerates unknown root fields', () {
    test('session/new with the real agent `models` field', () {
      final response =
          decodeAcpResult(sessionNewMethod, _json(_realNewSessionResult))
              as NewSessionResponse;

      expect(response.sessionId, const SessionId('92e5f32a'));
      expect(response.modes?.currentModeId, const SessionModeId('default'));
      expect(response.modes?.availableModes, hasLength(1));
    });

    test('unknown fields inside nested result objects', () {
      final response =
          decodeAcpResult(
                sessionNewMethod,
                _json(
                  '{"sessionId":"s","futureRoot":1,'
                  '"modes":{"currentModeId":"default","extra":true,'
                  '"availableModes":[{"id":"default","name":"D","extra":{}}]},'
                  '"configOptions":[{"id":"model","name":"Model",'
                  '"category":"model","type":"select","currentValue":"a",'
                  '"unknown":1,"options":[{"value":"a","name":"A","x":1}]}]}',
                ),
              )
              as NewSessionResponse;

      expect(response.sessionId, const SessionId('s'));
      expect(response.modes?.availableModes, hasLength(1));
      expect(response.configOptions, hasLength(1));
    });

    test('initialize result with an unknown root field', () {
      const raw = '{"protocolVersion":1,"agentCapabilities":{},"futureRoot":1}';

      final response =
          decodeAcpResult(initializeMethod, _json(raw)) as InitializeResponse;
      expect(response.protocolVersion, const ProtocolVersion(1));

      // A direct model decode stays strict.
      expectInvalidShape(() => InitializeResponse.fromJson(_json(raw)));
    });

    test('session/prompt result with an unknown field', () {
      final response =
          decodeAcpResult(
                sessionPromptMethod,
                _json('{"stopReason":"end_turn","usage":{"tokens":1}}'),
              )
              as PromptResponse;

      expect(response.stopReason, StopReason.endTurn);
    });

    test('decodeAcpResponseResult goes through the same tolerance', () {
      final response =
          JsonRpcMessage.response(
                id: const JsonRpcId.integer(2),
                result: _json(_realNewSessionResult),
              )
              as JsonRpcResponse;

      final decoded =
          decodeAcpResponseResult(method: sessionNewMethod, response: response)
              as NewSessionResponse;
      expect(decoded.sessionId, const SessionId('92e5f32a'));
    });
  });

  group('decodeAcpResult still rejects invalid shapes', () {
    test('a result that is not an object', () {
      expectInvalidShape(() => decodeAcpResult(sessionNewMethod, 'oops'));
    });

    test('a missing required field', () {
      expectInvalidShape(
        () => decodeAcpResult(sessionNewMethod, _json('{"models":{}}')),
      );
    });

    test('a known field of the wrong type', () {
      expectInvalidShape(
        () => decodeAcpResult(sessionNewMethod, _json('{"sessionId":1}')),
      );
    });

    test('an unknown discriminator value', () {
      expectInvalidShape(
        () => decodeAcpResult(
          sessionPromptMethod,
          _json('{"stopReason":"made_up"}'),
        ),
      );
    });
  });

  group('everything outside a response result stays strict', () {
    test('request params', () {
      expectInvalidShape(
        () => decodeAcpParams(
          sessionPromptMethod,
          _json(
            '{"sessionId":"s","prompt":[{"type":"text","text":"hi"}],'
            '"customRoot":true}',
          ),
        ),
      );
      expectInvalidShape(
        () => decodeAcpParams(
          initializeMethod,
          _json('{"protocolVersion":1,"customRoot":true}'),
        ),
      );
    });

    test(
      'session/update root and the nested objects it shares with results',
      () {
        expectInvalidShape(
          () => decodeAcpParams(
            sessionUpdateMethod,
            _json(
              '{"sessionId":"s","customRoot":true,"update":'
              '{"sessionUpdate":"config_option_update","configOptions":'
              '[$_configOption]}}',
            ),
          ),
        );
        // `SessionConfigOption` is lenient inside a result but strict here.
        expectInvalidShape(
          () => decodeAcpParams(
            sessionUpdateMethod,
            _json(
              '{"sessionId":"s","update":{"sessionUpdate":'
              '"config_option_update","configOptions":[{"id":"model",'
              '"name":"Model","category":"model","type":"select",'
              '"currentValue":"a","unknown":1,'
              '"options":[{"value":"a","name":"A"}]}]}}',
            ),
          ),
        );
      },
    );

    test('tolerance does not leak out of decodeAcpResult', () {
      decodeAcpResult(sessionNewMethod, _json(_realNewSessionResult));
      expectInvalidShape(
        () => NewSessionResponse.fromJson(_json(_realNewSessionResult)),
      );

      // ... including after a decode that threw.
      expectInvalidShape(() => decodeAcpResult(sessionNewMethod, 'oops'));
      expectInvalidShape(
        () => NewSessionResponse.fromJson(_json(_realNewSessionResult)),
      );
    });
  });
}
