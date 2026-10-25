import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

import '../support/server_harness.dart';

/// agent-acp-server «Правила протокольного уровня» (задача 2.1, §13.10,
/// ACP-4). Кадры, которые не разбираются в JSON или в JSON-RPC, до
/// сервера не доходят: их разбирает транспорт (design.md, D12), поэтому
/// здесь — всё, что приходит сообщением.
void main() {
  late ServerHarness h;

  setUp(() async {
    h = await ServerHarness.start();
    await h.initialize();
  });

  tearDown(() => h.dispose());

  Future<void> expectAlive() async {
    final response = await h.client.request('session/list', {});
    expect(response.error, isNull);
  }

  test('an unknown method is -32601 and the connection lives', () async {
    final response = await h.client.request('session/fly', {});

    expect(response.errorCode, jsonRpcMethodNotFoundCode);
    await expectAlive();
  });

  test('authenticate is -32601: there are no auth methods (§13.3)', () async {
    final response = await h.client.request('authenticate', {'methodId': 'x'});

    expect(response.errorCode, jsonRpcMethodNotFoundCode);
  });

  test('params that do not decode are -32602', () async {
    final array = await h.client.request('session/new', ['/work/demo']);
    final missing = await h.client.request('session/new', {'cwd': 7});

    expect(array.errorCode, jsonRpcInvalidParamsCode);
    expect(missing.errorCode, jsonRpcInvalidParamsCode);
    await expectAlive();
  });

  test('an unknown notification is logged and ignored', () async {
    await h.client.notify('session/whatever', {'x': 1});

    expect(await h.client.drain(), isEmpty);
    expect(h.logger.eventsOf('acp.notification.unknown'), hasLength(1));
    await expectAlive();
  });

  test('a response to an unknown id is logged as acp.frame.bad', () async {
    await h.client.raw(
      const JsonRpcMessage.response(
        id: JsonRpcId.string('perm-99'),
        result: {},
      ),
    );

    expect(await h.client.drain(), isEmpty);
    expect(h.logger.eventsOf('acp.frame.bad'), hasLength(1));
    await expectAlive();
  });

  test('a notification with a broken session/cancel is logged', () async {
    await h.client.notify('session/cancel', {'sessionId': 42});

    expect(await h.client.drain(), isEmpty);
    expect(h.logger.eventsOf('acp.frame.bad'), hasLength(1));
  });
}
