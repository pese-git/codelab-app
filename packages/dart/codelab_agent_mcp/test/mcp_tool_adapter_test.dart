// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/src/mcp_tool.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// Подключает клиента к fake-серверу и строит инструменты сессии.
Future<List<McpTool>> _tools(
  McpHarness h,
  List<FakeMcpTool> tools, {
  Map<String, FakeToolResponse> responses = const {},
  String server = 'fake',
}) async {
  final fake = FakeMcpServer(tools: tools, responses: responses);
  final client = await h.connect(fake, name: server);
  return [
    for (final definition in client.tools)
      ?McpTool.create(
        server: server,
        definition: definition,
        client: client,
        logger: h.logger,
        sessionId: const SessionId('s1'),
      ),
  ];
}

ToolContext _ctx(McpHarness h, {bool supportsImages = false}) => ToolContext(
  env: MemoryExecutionEnv(cwd: '/'),
  cancel: CancelToken.none,
  onUpdate: (_) {},
  toolCallId: 'tc-1',
  services: ToolServices(clock: h.clock, logger: h.logger),
  supportsImages: supportsImages,
);

Future<ToolExecutionResult> _run(
  McpHarness h,
  Map<String, Object?> result, {
  bool supportsImages = false,
}) async {
  final tools = await _tools(
    h,
    [const FakeMcpTool('t')],
    responses: {'t': FakeToolResponse.result(result)},
  );
  return tools.single.execute(
    const {},
    _ctx(h, supportsImages: supportsImages),
  );
}

String _text(ToolExecutionResult result) =>
    (result.content.whereType<TextContent>().single).text;

void main() {
  late McpHarness h;
  setUp(() => h = McpHarness());

  group('identity', () {
    test(
      'the name follows mcpToolName and parameters are the schema',
      () async {
        final tools = await _tools(h, [
          const FakeMcpTool(
            'get issue',
            inputSchema: {
              'type': 'object',
              'properties': {
                'id': {'type': 'string'},
              },
            },
          ),
        ], server: 'my.srv');

        final tool = tools.single;
        expect(tool.name, 'mcp__my_srv__get_issue');
        expect(
          tool.parameters['properties'],
          containsPair('id', {'type': 'string'}),
        );
      },
    );

    test(
      'kind comes from explicit annotations only, tier is always exec',
      () async {
        final tools = await _tools(h, [
          const FakeMcpTool('r', annotations: {'readOnlyHint': true}),
          const FakeMcpTool(
            'e',
            annotations: {'destructiveHint': true, 'openWorldHint': false},
          ),
          const FakeMcpTool('x', annotations: {'destructiveHint': true}),
          const FakeMcpTool('o'),
          // Подсказка «только чтение» сильнее остальных.
          const FakeMcpTool(
            'both',
            annotations: {'readOnlyHint': true, 'destructiveHint': true},
          ),
        ]);

        expect(
          [for (final t in tools) t.kind],
          [
            ToolKind.read,
            ToolKind.edit,
            ToolKind.execute,
            ToolKind.other,
            ToolKind.read,
          ],
        );
        expect(tools.map((t) => t.tier).toSet(), {ToolTier.exec});
        expect(tools.map((t) => t.tierOf(const {})).toSet(), {ToolTier.exec});
      },
    );

    test('the output is untrusted whatever the annotations say', () async {
      final tools = await _tools(h, [
        const FakeMcpTool('r', annotations: {'readOnlyHint': true}),
        const FakeMcpTool('o'),
      ]);

      for (final tool in tools) {
        expect(tool.outputTrust(const {}), ContentTrust.untrusted);
      }
    });

    test('present() titles the call with the full name', () async {
      final tool = (await _tools(h, [const FakeMcpTool('echo')])).single;

      final presented = await tool.present(const {'a': 1}, _ctx(h));

      expect(presented.title, 'mcp__fake__echo');
      expect(presented.locations, isEmpty);
    });

    test('permissionPattern is the canonical JSON of the arguments', () async {
      final tool = (await _tools(h, [const FakeMcpTool('echo')])).single;

      expect(
        tool.permissionPattern({
          'b': 1,
          'a': {'z': true, 'y': null},
        }, '/proj'),
        '{"a":{"y":null,"z":true},"b":1}',
      );
    });

    test('description falls back to title and then to the name', () async {
      final tools = await _tools(h, [
        const FakeMcpTool('a', description: 'Does a', title: 'A'),
        const FakeMcpTool('b', title: 'B tool'),
        const FakeMcpTool('c'),
      ]);

      expect([for (final t in tools) t.description], ['Does a', 'B tool', 'c']);
    });
  });

  group('invalid tools', () {
    test('a non-object inputSchema is skipped with mcp.tool.invalid', () async {
      final tools = await _tools(h, [
        const FakeMcpTool('bad', inputSchema: 'string'),
        const FakeMcpTool('good'),
      ]);

      expect([for (final t in tools) t.name], ['mcp__fake__good']);
      final fields = h.logger.eventsOf('mcp.tool.invalid').single.fields;
      expect(fields['tool'], 'bad');
      expect(fields['reason'], 'inputSchema is not an object');
      expect(fields['server'], 'fake');
    });

    for (final (label, schema) in <(String, Object)>[
      ('required is not a list', {'type': 'object', 'required': 'x'}),
      (
        'required has a non-string',
        {
          'type': 'object',
          'required': [1],
        },
      ),
      ('properties is not an object', {'type': 'object', 'properties': []}),
      ('type is a number', {'type': 5}),
      (
        'type is a list with a number',
        {
          'type': ['string', 5],
        },
      ),
      (
        'items is not an object',
        {
          'type': 'object',
          'properties': {
            'a': {'type': 'array', 'items': 'string'},
          },
        },
      ),
      (
        'enum is not a list',
        {
          'type': 'object',
          'properties': {
            'a': {'enum': 'x'},
          },
        },
      ),
    ]) {
      test('a malformed inputSchema ($label) is skipped', () async {
        final tools = await _tools(h, [
          FakeMcpTool('bad', inputSchema: schema),
          const FakeMcpTool('good'),
        ]);

        expect([for (final t in tools) t.name], ['mcp__fake__good']);
        final fields = h.logger.eventsOf('mcp.tool.invalid').single.fields;
        expect(fields['tool'], 'bad');
        expect(fields['reason'], 'malformed inputSchema');
      });
    }

    test('a boolean property schema is allowed', () async {
      final tools = await _tools(h, [
        const FakeMcpTool(
          'flagged',
          inputSchema: {
            'type': 'object',
            'properties': {'flag': true},
          },
        ),
      ]);

      expect([for (final t in tools) t.name], ['mcp__fake__flagged']);
      expect(h.logger.eventsOf('mcp.tool.invalid'), isEmpty);
    });

    test('a schema nested deeper than 32 levels is malformed', () async {
      Map<String, Object?> nested(int levels) {
        var schema = <String, Object?>{'type': 'string'};
        for (var i = 0; i < levels; i++) {
          schema = {
            'type': 'object',
            'properties': {'p': schema},
          };
        }
        return schema;
      }

      final tools = await _tools(h, [
        FakeMcpTool('deep', inputSchema: nested(40)),
        FakeMcpTool('shallow', inputSchema: nested(5)),
      ]);

      expect([for (final t in tools) t.name], ['mcp__fake__shallow']);
      final fields = h.logger.eventsOf('mcp.tool.invalid').single.fields;
      expect(fields['tool'], 'deep');
      expect(fields['reason'], 'malformed inputSchema');
    });

    test('a tool without a name is skipped', () async {
      final tools = await _tools(h, [const FakeMcpTool('')]);

      expect(tools, isEmpty);
      expect(h.logger.eventsOf('mcp.tool.invalid'), hasLength(1));
    });
  });

  group('description limit', () {
    test('5000 characters become 2048 plus the notice', () async {
      final long = 'x' * 5000;

      final tool = (await _tools(h, [
        FakeMcpTool('t', description: long),
      ])).single;

      expect(
        tool.description,
        '${'x' * 2048}\n[Description truncated: 2952 characters omitted.]',
      );
      final fields = h.logger
          .eventsOf('mcp.tool.description_truncated')
          .single
          .fields;
      expect(fields['tool'], 't');
      expect(fields['length'], 5000);
    });

    test('exactly 2048 characters stay as they are', () async {
      final exact = 'y' * 2048;

      final tool = (await _tools(h, [
        FakeMcpTool('t', description: exact),
      ])).single;

      expect(tool.description, exact);
      expect(h.logger.eventsOf('mcp.tool.description_truncated'), isEmpty);
    });

    test('a surrogate pair on the boundary is never torn', () async {
      // 2047 символов + эмодзи — ровно 2048 рун (2049 кодовых единиц UTF-16).
      final fits = '${'a' * 2047}\u{1F600}';
      final over = '${'a' * 2047}\u{1F600}tail';

      final tools = await _tools(h, [
        FakeMcpTool('fits', description: fits),
        FakeMcpTool('over', description: over),
      ]);

      expect(tools[0].description, fits);
      expect(
        tools[1].description,
        '$fits\n[Description truncated: 4 characters omitted.]',
      );
    });
  });

  group('projection of CallToolResult (D7)', () {
    test('text blocks are joined with a newline', () async {
      final result = await _run(h, {
        'content': [
          {'type': 'text', 'text': 'a'},
          {'type': 'text', 'text': 'b'},
        ],
      });

      expect(result.content, hasLength(1));
      expect(_text(result), 'a\nb');
      expect(result.isError, isFalse);
    });

    test('mixed content keeps the order of blocks', () async {
      final result = await _run(h, {
        'content': [
          {'type': 'text', 'text': 'a'},
          {'type': 'resource_link', 'uri': 'file:///x', 'name': 'x'},
          {
            'type': 'resource',
            'resource': {'uri': 'file:///y', 'text': 'b'},
          },
        ],
      });

      expect(
        _text(result),
        'a\n[resource link: file:///x (x)]\n'
        '<resource uri="file:///y">\nb\n</resource>',
      );
    });

    test('a binary resource and audio are described, not shown', () async {
      final bytes = base64.encode(List.filled(6, 1));
      final result = await _run(h, {
        'content': [
          {
            'type': 'resource',
            'resource': {'uri': 'file:///z.bin', 'blob': bytes},
          },
          {'type': 'audio', 'data': bytes, 'mimeType': 'audio/wav'},
        ],
      });

      expect(
        _text(result),
        '[binary resource file:///z.bin, 6 bytes, not shown]\n'
        '[audio omitted: audio/wav, 6 bytes]',
      );
    });

    test('an unknown block type is described by its type', () async {
      final result = await _run(h, {
        'content': [
          {'type': 'hologram'},
        ],
      });

      expect(_text(result), '[unsupported content: hologram]');
    });

    test(
      'an image goes as ImageContent for a model that accepts images',
      () async {
        final result = await _run(h, {
          'content': [
            {'type': 'text', 'text': 'see'},
            {'type': 'image', 'data': 'AAAA', 'mimeType': 'image/png'},
          ],
        }, supportsImages: true);

        expect(result.content, hasLength(2));
        expect(_text(result), 'see');
        final image = result.content.whereType<ImageContent>().single;
        expect((image.base64, image.mimeType), ('AAAA', 'image/png'));
      },
    );

    test('an image for a model without images is a note', () async {
      final result = await _run(h, {
        'content': [
          {'type': 'image', 'data': 'AAAA', 'mimeType': 'image/png'},
        ],
      });

      expect(result.content.whereType<ImageContent>(), isEmpty);
      expect(
        _text(result),
        '[image omitted: the model does not accept images (image/png)]',
      );
    });

    test(
      'empty content falls back to structuredContent as canonical JSON',
      () async {
        final result = await _run(h, {
          'content': <Object?>[],
          'structuredContent': {'b': 1, 'a': 2},
        });

        expect(_text(result), '{"a":2,"b":1}');
      },
    );

    test('empty content without structuredContent has a placeholder', () async {
      final result = await _run(h, {'content': <Object?>[]});

      expect(_text(result), '[MCP tool returned no content]');
    });

    test('isError becomes an error result with the text', () async {
      final result = await _run(h, {
        'content': [
          {'type': 'text', 'text': 'not found'},
        ],
        'isError': true,
      });

      expect(result.isError, isTrue);
      expect(_text(result), 'not found');
    });
  });

  group('execute', () {
    test('calls the server with the original tool name', () async {
      final fake = FakeMcpServer(tools: [const FakeMcpTool('get issue')]);
      final client = await h.connect(fake, name: 'my.srv');
      final tool = McpTool.create(
        server: 'my.srv',
        definition: client.tools.single,
        client: client,
        logger: h.logger,
        sessionId: const SessionId('s1'),
      )!;

      await tool.execute({'id': 7}, _ctx(h));

      expect(fake.calls, [
        {
          'name': 'get issue',
          'arguments': {'id': 7},
        },
      ]);
    });

    test('an MCP error becomes an error result, not an exception', () async {
      final tools = await _tools(
        h,
        [const FakeMcpTool('t')],
        responses: {'t': const FakeToolResponse.error(-32602, 'Unknown tool')},
      );

      final result = await tools.single.execute(const {}, _ctx(h));

      expect(result.isError, isTrue);
      expect(
        _text(result),
        'MCP server fake returned an error: Unknown tool (code -32602)',
      );
    });

    test('a cancelled token ends with CancelledException', () async {
      final tools = await _tools(h, [const FakeMcpTool('t')]);
      final source = CancelTokenSource()..cancel();
      final ctx = ToolContext(
        env: MemoryExecutionEnv(cwd: '/'),
        cancel: source.token,
        onUpdate: (_) {},
        toolCallId: 'tc-1',
        services: ToolServices(clock: h.clock, logger: h.logger),
      );

      await expectLater(
        tools.single.execute(const {}, ctx),
        throwsA(isA<CancelledException>()),
      );
    });
  });
}
