// Исходящий `initialize` клиента CodeLab объявляет расширения (задача 1.1,
// «kit» change `add-subagents-and-tasks`; spec acp-protocol-client «Объявление
// расширений CodeLab при initialize», сценарий «Запрос initialize клиента
// CodeLab»; design.md, D9, D21).
//
// Красный тест: клиент пока шлёт `clientCapabilities` без `_meta` (задача
// 1.6) — падает на сравнении тела запроса. Фикстуру корпуса
// `acp/initialize-codelab-extensions` ведёт протокольный исполнитель; здесь
// кадр собран в самом тесте.

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

  test('the initialize request declares only tasks in '
      'clientCapabilities._meta.codelab (subagents come with iterations 2 '
      'and 5)', () async {
    transport = FakeAcpTransport();
    client = AcpClientApplication(transport: FakeAcpTransport());
    addTearDown(client.dispose);
    await client.connect(transport);

    final capabilities = sentCapabilities();
    expect(capabilities['_meta'], {
      'codelab': {
        'tasks': {'version': 1},
      },
    });
    // Других полей вне `_meta` для этого нет, прежние — как раньше.
    expect(capabilities.keys.toSet(), {'fs', 'terminal', '_meta'});
  });
}
