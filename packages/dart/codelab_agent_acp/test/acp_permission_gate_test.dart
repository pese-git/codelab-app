import 'package:acp_protocol/acp_protocol.dart' show JsonRpcId, JsonRpcRequest;
import 'package:codelab_agent_acp/src/acp_permission_gate.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/client_channel.dart';

/// agent-acp-server «Запросы агента к клиенту», `AcpPermissionGate`
/// (задача 3.5; §7.8, §13.9; PERM-4, PERM-6, PERM-7).
void main() {
  late ClientChannel ch;
  late AcpPermissionGate gate;

  setUp(() async {
    ch = await ClientChannel.open();
    gate = AcpPermissionGate(ch.link, logger: ch.logger);
  });

  PermissionRequest edit({
    bool allowAlways = true,
    String? reason,
    String? criticalLabel,
  }) => PermissionRequest(
    toolCallId: 'call_2',
    tool: 'edit',
    kind: ToolKind.edit,
    tier: ToolTier.write,
    title: 'Edit README.md',
    rawInput: const {'path': 'README.md', 'oldText': 'foo', 'newText': 'bar'},
    locations: const [Location('/work/demo/README.md', line: 3)],
    diffs: const [
      FileDiff(
        path: '/work/demo/README.md',
        oldText: '# foo\n',
        newText: '# bar\n',
      ),
    ],
    pattern: 'README.md',
    reason: reason,
    criticalLabel: criticalLabel,
    allowAlwaysOffered: allowAlways,
  );

  void answer(Object? Function(JsonRpcRequest request) reply) =>
      ch.client.handlers['session/request_permission'] = reply;

  Object selected(String optionId) => {
    'outcome': {'outcome': 'selected', 'optionId': optionId},
  };

  test('the request matches §13.9: toolCall, diff and four options', () async {
    answer((_) => selected('allow_once'));

    final decision = await gate.request(edit(), CancelToken.none);

    expect(decision, PermissionDecision.allowOnce);
    final request = ch.client.requests.single;
    expect(request.id, JsonRpcId.string('perm-1'));
    expect(request.params, {
      'sessionId': 'sess_1',
      'toolCall': {
        'toolCallId': 'call_2',
        'title': 'Edit README.md',
        'kind': 'edit',
        'status': 'pending',
        'rawInput': {'path': 'README.md', 'oldText': 'foo', 'newText': 'bar'},
        'locations': [
          {'path': '/work/demo/README.md', 'line': 3},
        ],
        'content': [
          {
            'type': 'diff',
            'path': '/work/demo/README.md',
            'oldText': '# foo\n',
            'newText': '# bar\n',
          },
        ],
      },
      'options': [
        {'optionId': 'allow_once', 'name': 'Allow once', 'kind': 'allow_once'},
        {
          'optionId': 'allow_always',
          'name': 'Always allow README.md',
          'kind': 'allow_always',
        },
        {'optionId': 'reject_once', 'name': 'Reject', 'kind': 'reject_once'},
        {
          'optionId': 'reject_always',
          'name': 'Always reject README.md',
          'kind': 'reject_always',
        },
      ],
    });
  });

  test('each option maps to its decision', () async {
    const expected = {
      'allow_once': PermissionDecision.allowOnce,
      'allow_always': PermissionDecision.allowAlways,
      'reject_once': PermissionDecision.rejectOnce,
      'reject_always': PermissionDecision.rejectAlways,
    };
    for (final MapEntry(key: optionId, value: decision) in expected.entries) {
      answer((_) => selected(optionId));

      expect(await gate.request(edit(), CancelToken.none), decision);
    }
  });

  test(
    'a critical command: no allow_always, reason first, _meta.codelab.critical',
    () async {
      answer((_) => selected('reject_once'));

      await gate.request(
        edit(
          allowAlways: false,
          reason: 'critical command: recursive delete of a protected path',
          criticalLabel: 'recursive delete of a protected path',
        ),
        CancelToken.none,
      );

      final params = ch.client.paramsOf('session/request_permission');
      final toolCall = params['toolCall']! as Map<String, Object?>;
      expect(toolCall['_meta'], {
        'codelab': {
          'critical': true,
          'label': 'recursive delete of a protected path',
        },
      });
      expect((toolCall['content']! as List<Object?>).first, {
        'type': 'content',
        'content': {
          'type': 'text',
          'text': 'critical command: recursive delete of a protected path',
        },
      });
      expect(
        [
          for (final o in params['options']! as List<Object?>)
            (o! as Map)['kind'],
        ],
        ['allow_once', 'reject_once', 'reject_always'],
      );
    },
  );

  test('an unknown optionId is rejectOnce with a warning', () async {
    answer((_) => selected('maybe'));

    expect(
      await gate.request(edit(), CancelToken.none),
      PermissionDecision.rejectOnce,
    );
    expect(ch.logger.eventsOf('acp.permission.unknown_option'), hasLength(1));
  });

  test('a JSON-RPC error is rejectOnce with the reason in the log', () async {
    answer((_) => throw const ClientFailure(-32603, 'dialog failed'));

    expect(
      await gate.request(edit(), CancelToken.none),
      PermissionDecision.rejectOnce,
    );
    expect(ch.logger.eventsOf('acp.permission.failed'), hasLength(1));
  });

  test('a lost connection is rejectOnce', () async {
    final decision = gate.request(edit(), CancelToken.none);
    await ch.client.arrival('session/request_permission');

    await ch.client.close();

    expect(await decision, PermissionDecision.rejectOnce);
  });

  test('outcome cancelled is cancelled', () async {
    answer(
      (_) => {
        'outcome': {'outcome': 'cancelled'},
      },
    );

    expect(
      await gate.request(edit(), CancelToken.none),
      PermissionDecision.cancelled,
    );
  });

  test('cancel of the turn: cancelled, a late answer is ignored', () async {
    final cancel = CancelTokenSource();
    final decision = gate.request(edit(), cancel.token);
    final request = await ch.client.arrival('session/request_permission');

    cancel.cancel();

    expect(await decision, PermissionDecision.cancelled);
    await ch.client.respond(request, selected('allow_once'));
    await pumpEventQueue();
    expect(ch.logger.eventsOf('acp.frame.bad'), hasLength(1));
  });

  test('an already cancelled turn sends nothing', () async {
    final cancel = CancelTokenSource()..cancel();

    expect(
      await gate.request(edit(), cancel.token),
      PermissionDecision.cancelled,
    );
    await pumpEventQueue();
    expect(ch.client.requests, isEmpty);
  });
}
