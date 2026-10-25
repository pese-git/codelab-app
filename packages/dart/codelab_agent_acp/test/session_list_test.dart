import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// agent-acp-server «session/list» (задача 2.4, §13.5).
void main() {
  late ServerHarness h;

  setUp(() async {
    h = await ServerHarness.start();
    await h.initialize();
  });

  tearDown(() => h.dispose());

  Future<String> newSession(String cwd) async =>
      (await h.client.request('session/new', {
            'cwd': cwd,
            'mcpServers': <Object?>[],
          })).resultMap['sessionId']!
          as String;

  test('filters by cwd, the newest first', () async {
    final a1 = await newSession('/work/a');
    await newSession('/work/b');
    final a2 = await newSession('/work/a');

    final response = await h.client.request('session/list', {'cwd': '/work/a'});

    final sessions = response.resultMap['sessions']! as List;
    expect([for (final s in sessions) (s as Map)['sessionId']], [a2, a1]);
    expect((sessions.first as Map)['cwd'], '/work/a');
    expect((sessions.first as Map)['updatedAt'], isA<String>());
    expect(response.resultMap.containsKey('nextCursor'), isFalse);
  });

  test('without cwd — all sessions', () async {
    await newSession('/work/a');
    await newSession('/work/b');

    final response = await h.client.request('session/list', {});

    expect(response.resultMap['sessions'], hasLength(2));
  });

  test('no matches — an empty list without nextCursor', () async {
    final response = await h.client.request('session/list', {'cwd': '/none'});

    expect(response.result, {'sessions': <Object?>[]});
  });

  test('a relative cwd and a broken cursor are -32602', () async {
    final relative = await h.client.request('session/list', {'cwd': 'a'});
    final cursor = await h.client.request('session/list', {'cursor': 'nope'});

    expect(relative.errorCode, jsonRpcInvalidParamsCode);
    expect(cursor.errorCode, jsonRpcInvalidParamsCode);
  });
}
