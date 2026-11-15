// Исходящий `initialize` клиента CodeLab объявляет расширения (задачи 1.1 и
// 2.1 «kit» change `add-subagents-and-tasks`; spec acp-protocol-client
// «Объявление расширений CodeLab при initialize», сценарии «Запрос
// initialize клиента CodeLab (итерация 1)» и «(итерация 2)»; design.md, D9,
// D21; задача 2.9a).
//
// Редакция итерации 2: к `tasks` добавляется `subagents: {version: 1}`
// (строка `agent` и запрос потомка клиент уже показывает).
//
// Редакция задачи 5.4 (сценарий «Запрос initialize клиента CodeLab (задача
// 5.4)»; design.md, D9): к ним добавляется `subagentToolCalls: {version: 1}`
// — согласие получать вызовы потомков, которые клиент показывает деревом.
// Тест охраняет точное тело запроса из `codelabClientExtensionsMeta`; кадр
// собран в самом тесте, корпус проверяет то же фикстурой
// `acp/initialize-codelab-extensions`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;

  Map<String, Object?> sentCapabilities() {
    final request =
        transport.sentMessages.firstWhere(
              (message) =>
                  message is JsonRpcRequest &&
                  message.method == initializeMethod,
            )
            as JsonRpcRequest;
    return (request.params! as Map)['clientCapabilities']!
        as Map<String, Object?>;
  }

  test(
    'the initialize request declares tasks, subagents and '
    'subagentToolCalls in clientCapabilities._meta.codelab (task 5.4)',
    () async {
      transport = FakeAcpTransport();
      client = AcpClientApplication(transport: FakeAcpTransport());
      addTearDown(client.dispose);
      await client.connect(transport);

      final capabilities = sentCapabilities();
      expect(capabilities['_meta'], {
        'codelab': {
          'tasks': {'version': 1},
          'subagents': {'version': 1},
          'subagentToolCalls': {'version': 1},
        },
      });
      // Других полей вне `_meta` для этого нет, прежние — как раньше.
      expect(capabilities.keys.toSet(), {'fs', 'terminal', '_meta'});
    },
  );
}
