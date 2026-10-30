// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/src/mcp_client.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

const _echo = FakeMcpTool('echo');

Map<String, Object?> _text(String text) => {
  'content': [
    {'type': 'text', 'text': text},
  ],
};

/// Идентификатор последнего `tools/call`, принятого сервером.
Object _lastCallId(FakeMcpServer server) =>
    server.requests.lastWhere((r) => r['method'] == 'tools/call')['id']!;

String _errorText(McpCallOutcome outcome) => (outcome as McpCallError).text;

void main() {
  late McpHarness h;
  setUp(() => h = McpHarness());

  test('callTimeout of the options is a 10 minute default for servers without '
      'their own call_timeout (change `add-agent-configuration`, D10)', () {
    expect(const McpClientOptions().callTimeout, const Duration(minutes: 10));
  });

  group('result', () {
    for (final era in [FakeMcpEra.modern, FakeMcpEra.legacy]) {
      test('a call returns the server result (${era.name})', () async {
        final server = FakeMcpServer(
          era: era,
          tools: [_echo],
          responses: {'echo': FakeToolResponse.result(_text('hi'))},
        );
        final client = await h.connect(server);

        final outcome = await client.callTool('echo', {
          'text': 'hi',
        }, cancel: CancelToken.none);

        final result = (outcome as McpCallDone).result;
        expect(result.content.single['text'], 'hi');
        expect(result.isError, isFalse);
        expect(server.calls, [
          {
            'name': 'echo',
            'arguments': {'text': 'hi'},
          },
        ]);
        final call = server.requests.last['params'] as Map;
        expect(call.containsKey('_meta'), era == FakeMcpEra.modern);
      });
    }

    test('isError is passed through as a result', () async {
      final server = FakeMcpServer(
        tools: [_echo],
        responses: {'echo': FakeToolResponse.text('not found', isError: true)},
      );
      final client = await h.connect(server);

      final outcome = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect((outcome as McpCallDone).result.isError, isTrue);
    });

    test(
      'a response that arrived before the cancel is a normal result',
      () async {
        final gate = Completer<Map<String, Object?>>();
        final server = FakeMcpServer(
          tools: [_echo],
          responses: {'echo': FakeToolResponse.gated(gate)},
        );
        final client = await h.connect(server);
        final source = CancelTokenSource();
        final call = client.callTool('echo', const {}, cancel: source.token);

        gate.complete(_text('first'));
        final outcome = await call;
        source.cancel();
        await h.clock.elapse(Duration.zero);

        expect((outcome as McpCallDone).result.content.single['text'], 'first');
        expect(server.cancelledRequestIds, isEmpty);
      },
    );

    test('an already cancelled token sends nothing', () async {
      final server = FakeMcpServer(tools: [_echo]);
      final client = await h.connect(server);
      final source = CancelTokenSource()..cancel();

      await expectLater(
        client.callTool('echo', const {}, cancel: source.token),
        throwsA(isA<CancelledException>()),
      );

      expect(server.calls, isEmpty);
    });
  });

  group('cancel signal by transport and era (D8)', () {
    Future<(FakeMcpServer, Object)> startAndCancel({
      required String kind,
      required FakeMcpEra era,
      required McpHarness harness,
    }) async {
      final gate = Completer<Map<String, Object?>>();
      final server = FakeMcpServer(
        era: era,
        tools: [_echo],
        responses: {'echo': FakeToolResponse.gated(gate)},
      );
      final client = await harness.connect(server, kind: kind);
      final source = CancelTokenSource();
      final call = client.callTool(
        'echo',
        const {},
        cancel: source.token,
        toolCallId: 'tc-1',
      );
      final failed = expectLater(call, throwsA(isA<CancelledException>()));
      await harness.clock.elapse(Duration.zero);
      final id = _lastCallId(server);

      source.cancel();
      await failed;
      return (server, id);
    }

    for (final era in [FakeMcpEra.modern, FakeMcpEra.legacy]) {
      test('stdio (${era.name}): one notifications/cancelled', () async {
        final (server, id) = await startAndCancel(
          kind: 'stdio',
          era: era,
          harness: h,
        );

        expect(server.cancelledRequestIds, [id]);
        expect(server.abandoned, isEmpty);
      });
    }

    test('http modern: only the response stream is closed', () async {
      final (server, id) = await startAndCancel(
        kind: 'http',
        era: FakeMcpEra.modern,
        harness: h,
      );

      expect(server.cancelledRequestIds, isEmpty);
      expect(server.abandoned, [id]);
    });

    test('http legacy: the notification and the closed stream', () async {
      final (server, id) = await startAndCancel(
        kind: 'http',
        era: FakeMcpEra.legacy,
        harness: h,
      );

      expect(server.cancelledRequestIds, [id]);
      expect(server.abandoned, [id]);
    });

    test('the cancel is logged with the tool call and request ids', () async {
      final (_, id) = await startAndCancel(
        kind: 'stdio',
        era: FakeMcpEra.modern,
        harness: h,
      );

      final fields = h.logged('mcp.call.cancelled');
      expect(fields['tool_call_id'], 'tc-1');
      expect(fields['request_id'], id);
      expect(fields['server'], 'fake');
    });

    test('a response after the cancel is ignored as late_response', () async {
      final (server, id) = await startAndCancel(
        kind: 'stdio',
        era: FakeMcpEra.modern,
        harness: h,
      );

      server.answerLate(id, _text('too late'));
      await h.clock.elapse(Duration.zero);

      final ignored = h.logger
          .eventsOf('mcp.message.ignored')
          .where((r) => r.fields['kind'] == 'late_response');
      expect(ignored, hasLength(1));
    });
  });

  group('timeout', () {
    test('the same cancel signal and the text of D8', () async {
      final gate = Completer<Map<String, Object?>>();
      final server = FakeMcpServer(
        tools: [_echo],
        responses: {'echo': FakeToolResponse.gated(gate)},
      );
      final client = await h.connect(server);

      final call = client.callTool('echo', const {}, cancel: CancelToken.none);
      await h.clock.elapse(const Duration(minutes: 9, seconds: 59));
      expect(server.cancelledRequestIds, isEmpty);
      await h.clock.elapse(const Duration(seconds: 1));
      final outcome = await call;

      expect(
        _errorText(outcome),
        'MCP server fake did not answer tools/call within 600 s.',
      );
      expect(server.cancelledRequestIds, [_lastCallId(server)]);
      expect(h.logger.eventsOf('mcp.call.timeout'), hasLength(1));
    });

    test('the timeout is taken from the options', () async {
      final gate = Completer<Map<String, Object?>>();
      final server = FakeMcpServer(
        tools: [_echo],
        responses: {'echo': FakeToolResponse.gated(gate)},
      );
      final client = await h.connect(
        server,
        options: const McpClientOptions(callTimeout: Duration(seconds: 30)),
      );

      final call = client.callTool('echo', const {}, cancel: CancelToken.none);
      await h.clock.elapse(const Duration(seconds: 30));

      expect(_errorText(await call), contains('within 30 s.'));
    });
  });

  group('failures are values', () {
    test('the transport closes during the call', () async {
      final gate = Completer<Map<String, Object?>>();
      final server = FakeMcpServer(
        tools: [_echo],
        responses: {'echo': FakeToolResponse.gated(gate)},
      );
      final client = await h.connect(server);
      final call = client.callTool('echo', const {}, cancel: CancelToken.none);
      await h.clock.elapse(Duration.zero);

      server.crash(reason: 'process exited with code 1');
      final outcome = await call;

      expect(
        _errorText(outcome),
        'MCP server fake disconnected during the call: '
        'process exited with code 1',
      );
      expect(server.calls, hasLength(1));
    });

    test('a call after the crash says the server is not connected', () async {
      final server = FakeMcpServer(tools: [_echo]);
      final client = await h.connect(server);
      server.crash();
      await h.clock.elapse(Duration.zero);

      final outcome = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect(
        _errorText(outcome),
        'MCP server fake is not connected. Continue without it.',
      );
      expect(client.isConnected, isFalse);
    });

    test('a call after close says the server is not connected', () async {
      final server = FakeMcpServer(tools: [_echo]);
      final client = await h.connect(server);
      await client.close();

      final outcome = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect(_errorText(outcome), contains('is not connected'));
    });

    test('a JSON-RPC error carries the message and the code', () async {
      final server = FakeMcpServer(
        tools: [_echo],
        responses: {
          'echo': const FakeToolResponse.error(-32602, 'Unknown tool'),
        },
      );
      final client = await h.connect(server);

      final outcome = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect(
        _errorText(outcome),
        'MCP server fake returned an error: Unknown tool (code -32602)',
      );
    });

    test('a result off the schema is invalid', () async {
      final server = FakeMcpServer(
        tools: [_echo],
        responses: {
          'echo': const FakeToolResponse.raw({'content': 'oops'}),
        },
      );
      final client = await h.connect(server);

      final outcome = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect(
        _errorText(outcome),
        'MCP server fake returned an invalid tools/call result.',
      );
    });

    test('an unknown resultType is invalid', () async {
      final server = FakeMcpServer(
        tools: [_echo],
        responses: {
          'echo': const FakeToolResponse.raw({
            'resultType': 'streaming',
            'content': <Object?>[],
          }),
        },
      );
      final client = await h.connect(server);

      final outcome = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect(_errorText(outcome), contains('invalid tools/call result'));
    });

    test('input_required is an error without a retry', () async {
      final server = FakeMcpServer(
        tools: [_echo],
        responses: {
          'echo': const FakeToolResponse.raw({'resultType': 'input_required'}),
        },
      );
      final client = await h.connect(server);

      final outcome = await client.callTool(
        'echo',
        const {},
        cancel: CancelToken.none,
      );

      expect(
        _errorText(outcome),
        'MCP server fake asked for client input, which is not supported.',
      );
      expect(server.calls, hasLength(1));
    });

    test('a broken response stream of tools/call is not retried', () async {
      final gate = Completer<Map<String, Object?>>();
      final server = FakeMcpServer(
        tools: [_echo],
        responses: {'echo': FakeToolResponse.gated(gate)},
      );
      final client = await h.connect(server, kind: 'http');
      final call = client.callTool('echo', const {}, cancel: CancelToken.none);
      await h.clock.elapse(Duration.zero);

      server.abortResponse(_lastCallId(server));
      final outcome = await call;

      expect(
        _errorText(outcome),
        'MCP server fake disconnected during the call: '
        'response stream closed',
      );
      expect(server.calls, hasLength(1));
    });

    test(
      'a broken response stream of tools/list is retried once with a new id',
      () async {
        final server = FakeMcpServer(tools: [_echo], listChanged: true);
        final seen = <int>[];
        await h.connect(
          server,
          kind: 'http',
          onToolsChanged: (tools) => seen.add(tools.length),
        );
        final before = server.requests.length;
        server.abortListResponses = 1;

        server.notifyToolsListChanged(
          newTools: [_echo, const FakeMcpTool('b')],
        );
        await h.clock.elapse(Duration.zero);

        final lists = server.requests
            .skip(before)
            .where((r) => r['method'] == 'tools/list')
            .toList();
        expect(lists, hasLength(2));
        expect(lists[0]['id'], isNot(lists[1]['id']));
        expect(seen, [2]);
      },
    );
  });

  group('close', () {
    test('stdio cancels the subscription once', () async {
      final server = FakeMcpServer(tools: [_echo], listChanged: true);
      final client = await h.connect(server);
      final listenId = server.requests.firstWhere(
        (r) => r['method'] == 'subscriptions/listen',
      )['id']!;

      await client.close();
      await client.close();

      expect(server.cancelledRequestIds, [listenId]);
      expect(server.closedTransports, 1);
    });

    test('a legacy server gets no cancellation on close', () async {
      final server = FakeMcpServer(era: FakeMcpEra.legacy, tools: [_echo]);
      final client = await h.connect(server);

      await client.close();

      expect(server.cancelledRequestIds, isEmpty);
      expect(server.closedTransports, 1);
    });

    test('pending calls end without a cancellation notice', () async {
      final gate = Completer<Map<String, Object?>>();
      final server = FakeMcpServer(
        era: FakeMcpEra.legacy,
        tools: [_echo],
        responses: {'echo': FakeToolResponse.gated(gate)},
      );
      final client = await h.connect(server);
      final call = client.callTool('echo', const {}, cancel: CancelToken.none);
      await h.clock.elapse(Duration.zero);

      await client.close();
      final outcome = await call;

      expect(_errorText(outcome), contains('disconnected during the call'));
      expect(server.cancelledRequestIds, isEmpty);
    });
  });
}
