import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:test/test.dart';

/// `session/set_mode` по схеме `docs/protocols/acp/protocol/17-Schema.md`
/// (`SetSessionModeRequest`, `SetSessionModeResponse`) и
/// `12-Session Model.md`; design.md change `add-dart-agent-acp-server`, D2.
void main() {
  test('the request round-trips with sessionId and modeId', () {
    const request = SetSessionModeRequest(
      sessionId: SessionId('session-1'),
      modeId: SessionModeId('plan'),
    );

    expect(request.toJson(), {'sessionId': 'session-1', 'modeId': 'plan'});
    expect(SetSessionModeRequest.fromJson(request.toJson()), request);
  });

  test('the request keeps _meta and rejects unknown fields', () {
    expect(
      SetSessionModeRequest.fromJson({
        'sessionId': 'session-1',
        'modeId': 'plan',
        '_meta': {'x': 1},
      }).meta,
      {'x': 1},
    );
    expect(
      () => SetSessionModeRequest.fromJson({
        'sessionId': 'session-1',
        'modeId': 'plan',
        'extra': true,
      }),
      throwsA(isA<JsonRpcProtocolException>()),
    );
    expect(
      () => SetSessionModeRequest.fromJson({'sessionId': 'session-1'}),
      throwsA(isA<JsonRpcProtocolException>()),
    );
  });

  test('the response is an empty object', () {
    const response = SetSessionModeResponse();

    expect(response.toJson(), isEmpty);
    expect(SetSessionModeResponse.fromJson(<String, Object?>{}), response);
  });

  test('the method is in the registry', () {
    expect(sessionSetModeMethod, 'session/set_mode');
    expect(
      decodeAcpParams(sessionSetModeMethod, {
        'sessionId': 'session-1',
        'modeId': 'ask',
      }),
      const SetSessionModeRequest(
        sessionId: SessionId('session-1'),
        modeId: SessionModeId('ask'),
      ),
    );
    expect(
      encodeAcpResult(sessionSetModeMethod, const SetSessionModeResponse()),
      isEmpty,
    );
  });
}
