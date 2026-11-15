import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' hide SessionId;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// agent-acp-server «initialize», «Соединение ACP-сервера» (задача 2.2,
/// §13.2).
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  test('the answer has exactly the fields of §13.2', () async {
    h = await ServerHarness.start();

    final response = await h.initialize();

    expect(response.result, {
      'protocolVersion': 1,
      'agentCapabilities': {
        'loadSession': true,
        'promptCapabilities': {
          'image': true,
          'audio': false,
          'embeddedContext': true,
        },
        // Ядро без MCP (`AgentCoreServices.mcp == null`): HTTP-серверы не
        // подключаются, поэтому `http: false` (design.md `add-agent-mcp-client`, D11).
        'mcpCapabilities': {'http': false, 'sse': false},
        'sessionCapabilities': {'list': <String, Object?>{}},
      },
      'agentInfo': {
        'name': 'codelab-agent',
        'title': 'CodeLab Agent',
        'version': '0.1.0',
      },
      'authMethods': <Object?>[],
    });
  });

  // agent-acp-server «initialize», «Ответ codelab-app»: `http` — по плану
  // ядра (capability `mcp` с транспортом `http`), `sse` — всегда `false`
  // (`02-Initialization.md#mcp-capabilities`).
  McpConnector fakeConnector(Clock clock) => McpClientConnector(
    transports: McpTransports(
      stdio: FakeMcpTransportFactory({}),
      http: FakeMcpTransportFactory({}),
    ),
    clock: clock,
  );

  test('http is true when the core plan has the mcp transport http', () async {
    h = await ServerHarness.start(mcp: fakeConnector);

    final caps =
        (await h.initialize()).resultMap['agentCapabilities']!
            as Map<String, Object?>;

    expect(caps['mcpCapabilities'], {'http': true, 'sse': false});
  });

  test('http is false when the profile narrows mcp to stdio', () async {
    h = await ServerHarness.start(
      mcp: fakeConnector,
      narrow: const {
        HostCapability.mcp: CapabilityTransport({'stdio'}, 'тест'),
      },
    );

    final caps =
        (await h.initialize()).resultMap['agentCapabilities']!
            as Map<String, Object?>;

    expect(caps['mcpCapabilities'], {'http': false, 'sse': false});
  });

  test('http is false when the mcp capability is off', () async {
    h = await ServerHarness.start(
      mcp: fakeConnector,
      narrow: const {HostCapability.mcp: CapabilityOff('тест')},
    );

    final caps =
        (await h.initialize()).resultMap['agentCapabilities']!
            as Map<String, Object?>;

    expect(caps['mcpCapabilities'], {'http': false, 'sse': false});
  });

  test('without sessionPersistence there is no load and no list', () async {
    h = await ServerHarness.start(
      narrow: const {HostCapability.sessionPersistence: CapabilityOff('тест')},
    );

    final caps =
        (await h.initialize()).resultMap['agentCapabilities']!
            as Map<String, Object?>;

    expect(caps['loadSession'], isFalse);
    // Поля list нет; сам объект кодек пишет всегда (§13.2).
    expect(caps['sessionCapabilities'], isEmpty);
  });

  test('a version above 1 is still answered with 1', () async {
    h = await ServerHarness.start();

    final response = await h.client.request('initialize', {
      'protocolVersion': 7,
    });

    expect(response.resultMap['protocolVersion'], 1);
  });

  test('a second initialize is -32600 already initialized', () async {
    h = await ServerHarness.start();
    await h.initialize();

    final again = await h.initialize();

    expect(again.errorCode, jsonRpcInvalidRequestCode);
    expect(again.error!.message, contains('already initialized'));
  });

  test('session/* before initialize is -32600 initialize required', () async {
    h = await ServerHarness.start();

    final response = await h.client.request('session/new', {
      'cwd': '/work/demo',
      'mcpServers': <Object?>[],
    });

    expect(response.errorCode, jsonRpcInvalidRequestCode);
    expect(response.error!.message, contains('initialize required'));
    expect((await h.initialize()).error, isNull);
  });

  // agent-acp-server «initialize», «Ответ codelab-app» (design.md change
  // `add-subagents-and-tasks`, D9): клиент без `_meta` получает прежний ответ
  // «ровно эти поля» — блока объявлений нет ни у `agentCapabilities`, ни
  // у корня ответа. Тест охраняет сторонних клиентов (Zed) от регрессии.
  test('without a client _meta there is no codelab block', () async {
    h = await ServerHarness.start();

    final result = (await h.initialize()).resultMap;

    final caps = result['agentCapabilities']! as Map<String, Object?>;
    expect(caps, isNot(contains('_meta')));
    expect(result, isNot(contains('_meta')));
  });

  // «Клиент CodeLab объявил расширения, дерево вызовов (итерация 5)»:
  // блок идёт только по объявлению клиента; субагенты включены по умолчанию
  // (`subagents.enabled: true`, `max_depth: 3`), поэтому рядом с `tasks`
  // объявлен `subagents` с `maxDepth` равным `max_depth` (3): потомки
  // запускают своих детей до этой глубины (D9, D37, D45 Т9); с задачей 5.2
  // адаптер проецирует вызовы потомков и объявляет `subagentToolCalls`
  // (D9, D47 Т12). Красный до 5.2: ключа в блоке ещё нет.
  test('an empty client _meta.codelab gets tasks and subagents', () async {
    h = await ServerHarness.start();

    final response = await h.initialize(
      clientCapabilities: {
        'fs': {'readTextFile': true, 'writeTextFile': true},
        'terminal': true,
        '_meta': {'codelab': <String, Object?>{}},
      },
    );

    final caps =
        response.resultMap['agentCapabilities']! as Map<String, Object?>;
    expect(caps['_meta'], {
      'codelab': {
        'subagents': {'version': 1, 'maxDepth': 3},
        'subagentToolCalls': {'version': 1},
        'tasks': {'version': 1},
      },
    });
    // Стандартные поля блок не меняет (D9).
    expect(caps['loadSession'], isTrue);
    expect(caps['mcpCapabilities'], {'http': false, 'sse': false});
  });

  // Состав блока не зависит от того, что объявил клиент (D9): ни объявленный
  // `subagentToolCalls`, ни версия `subagents` его не расширяют и не
  // сужают; клиент без этого ключа получает тот же блок. Агент объявляет
  // `subagentToolCalls`, потому что умеет проецировать вызовы потомков
  // (итерация 5, задача 5.2).
  test('subagentToolCalls is declared whatever the client declared', () async {
    h = await ServerHarness.start();

    final response = await h.initialize(
      clientCapabilities: {
        'terminal': true,
        '_meta': {
          'codelab': {
            'tasks': {'version': 1},
            'subagents': {'version': 1},
            'subagentToolCalls': {'version': 1},
          },
        },
      },
    );

    final caps =
        response.resultMap['agentCapabilities']! as Map<String, Object?>;
    const withToolCalls = {
      'codelab': {
        'subagents': {'version': 1, 'maxDepth': 3},
        'subagentToolCalls': {'version': 1},
        'tasks': {'version': 1},
      },
    };
    expect(caps['_meta'], withToolCalls);
  });

  // Согласие клиента на вызовы потомков агент читает отдельно (D47 Т3), а
  // состав ответа от него не зависит: клиент без `subagentToolCalls` получает
  // тот же блок, что и клиент с ним.
  test('a client without subagentToolCalls gets the same block', () async {
    h = await ServerHarness.start();

    final response = await h.initialize(
      clientCapabilities: {
        'terminal': true,
        '_meta': {
          'codelab': {
            'tasks': {'version': 1},
            'subagents': {'version': 1},
          },
        },
      },
    );

    final caps =
        response.resultMap['agentCapabilities']! as Map<String, Object?>;
    expect(caps['_meta'], {
      'codelab': {
        'subagents': {'version': 1, 'maxDepth': 3},
        'subagentToolCalls': {'version': 1},
        'tasks': {'version': 1},
      },
    });
  });

  // «неизвестные ключи и значения в clientCapabilities._meta.codelab SHALL
  // игнорироваться без ошибки» (forward compatibility, 15-Extensibility.md).
  test(
    'unknown keys and values of the client _meta.codelab are ignored',
    () async {
      h = await ServerHarness.start();

      final response = await h.initialize(
        clientCapabilities: {
          'terminal': true,
          '_meta': {
            'codelab': {
              'tasks': {'version': 2, 'x': 1},
              'future': true,
              'board': 'yes',
            },
          },
        },
      );

      expect(response.error, isNull);
      final caps =
          response.resultMap['agentCapabilities']! as Map<String, Object?>;
      // Блок тот же, что при известном объявлении (итерация 5, D9).
      expect(caps['_meta'], {
        'codelab': {
          'subagents': {'version': 1, 'maxDepth': 3},
          'subagentToolCalls': {'version': 1},
          'tasks': {'version': 1},
        },
      });
    },
  );

  // `_meta` клиента без ключа `codelab` — не объявление CodeLab: блок
  // отправляется, только если клиент прислал именно объект `codelab`.
  test('a client _meta without codelab gets no block', () async {
    h = await ServerHarness.start();

    final response = await h.initialize(
      clientCapabilities: {
        'terminal': true,
        '_meta': {'traceparent': '00-abc-def-01'},
      },
    );

    final caps =
        response.resultMap['agentCapabilities']! as Map<String, Object?>;
    expect(caps, isNot(contains('_meta')));
  });

  test('missing clientCapabilities is logged', () async {
    h = await ServerHarness.start();

    await h.client.request('initialize', {'protocolVersion': 1});

    expect(h.logger.eventsOf('acp.client_capabilities.absent'), hasLength(1));
  });
}
