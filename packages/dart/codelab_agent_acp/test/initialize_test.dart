import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' hide SessionId;
import 'package:codelab_agent_core/codelab_agent_core.dart';
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
        // MCP — этап 8: до него HTTP-серверы не подключаются (design.md, D12).
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

  test('missing clientCapabilities is logged', () async {
    h = await ServerHarness.start();

    await h.client.request('initialize', {'protocolVersion': 1});

    expect(h.logger.eventsOf('acp.client_capabilities.absent'), hasLength(1));
  });
}
