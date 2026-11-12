// Объявление расширений CodeLab при `initialize` (задача 1.1, «kit» change
// `add-subagents-and-tasks`; spec acp-protocol-client «Объявление расширений
// CodeLab при initialize»; design.md, D9, D21).
//
// Красные тесты: `ClientConnectionReady.codelabExtensions` ещё нет (задача
// 1.6); файл не компилируется. Исходящий кадр проверен отдельно в
// `initialize_codelab_request_test.dart`. Фикстуру корпуса `acp/initialize-codelab-extensions` ведёт протокольный
// исполнитель; здесь кадры собраны в самом тесте.
//
// Имя `ClientConnectionReady.codelabExtensions` (согласованные возможности
// соединения) — предложение этой задачи: spec требует лишь «доступны
// приложению» и имени не задаёт.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;

  Future<ClientConnectionReady> connect([
    AgentCapabilities capabilities = const AgentCapabilities(),
  ]) async {
    transport = FakeAcpTransport()..initializeAgentCapabilities = capabilities;
    client = AcpClientApplication(transport: FakeAcpTransport());
    addTearDown(client.dispose);
    await client.connect(transport);
    return client.connectionState as ClientConnectionReady;
  }

  test('an agent without agentCapabilities._meta: initialize succeeds and '
      'no CodeLab extensions are negotiated', () async {
    final ready = await connect();

    expect(ready.capabilities.meta, isNull);
    expect(ready.codelabExtensions.tasks, isFalse);
    expect(ready.codelabExtensions.subagentsMaxDepth, isNull);
  });

  test('a future extension version and unknown keys are ignored without '
      'failing initialize', () async {
    final ready = await connect(
      const AgentCapabilities(
        meta: {
          'codelab': {
            'tasks': {'version': 2, 'x': 1},
            'board': true,
          },
        },
      ),
    );

    expect(client.connectionState, isA<ClientConnectionReady>());
    // Версия больше известной: расширение не согласовано, ошибки нет.
    expect(ready.codelabExtensions.tasks, isFalse);
  });

  test('known values are available as negotiated capabilities', () async {
    final ready = await connect(
      const AgentCapabilities(
        meta: {
          'codelab': {
            'tasks': {'version': 1},
            'subagents': {'version': 1, 'maxDepth': 3},
          },
        },
      ),
    );

    expect(ready.codelabExtensions.tasks, isTrue);
    expect(ready.codelabExtensions.subagentsMaxDepth, 3);
  });

  test('wrong value shapes are ignored without failing initialize', () async {
    final ready = await connect(
      const AgentCapabilities(
        meta: {
          'codelab': {
            'tasks': 'yes',
            'subagents': {'version': 1.5, 'maxDepth': 'deep'},
          },
        },
      ),
    );

    expect(client.connectionState, isA<ClientConnectionReady>());
    expect(ready.codelabExtensions.tasks, isFalse);
    expect(ready.codelabExtensions.subagentsMaxDepth, isNull);
  });

  test('a non-integer version (1.0) is not accepted', () async {
    final ready = await connect(
      const AgentCapabilities(
        meta: {
          'codelab': {
            'tasks': {'version': 1.0},
          },
        },
      ),
    );

    expect(ready.codelabExtensions.tasks, isFalse);
  });
}
