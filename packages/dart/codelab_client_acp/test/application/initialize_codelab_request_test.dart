// Исходящий `initialize` клиента CodeLab объявляет расширения (задачи 1.1 и
// 2.1 «kit» change `add-subagents-and-tasks`; spec acp-protocol-client
// «Объявление расширений CodeLab при initialize», сценарии «Запрос
// initialize клиента CodeLab (итерация 1)» и «(итерация 2)»; design.md, D9,
// D21; задача 2.9a).
//
// Редакция итерации 2: к `tasks` добавляется `subagents: {version: 1}`
// (строка `agent` и запрос потомка клиент уже показывает); `subagentToolCalls`
// по-прежнему нет — клиент не умеет показывать дерево вызовов потомков
// (задача 5.4). Красный тест: клиент пока объявляет только `tasks` —
// падает на сравнении тела запроса. Фикстуру корпуса
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

  test('the initialize request declares tasks and subagents, but not '
      'subagentToolCalls, in clientCapabilities._meta.codelab', () async {
    transport = FakeAcpTransport();
    client = AcpClientApplication(transport: FakeAcpTransport());
    addTearDown(client.dispose);
    await client.connect(transport);

    final capabilities = sentCapabilities();
    expect(capabilities['_meta'], {
      'codelab': {
        'tasks': {'version': 1},
        'subagents': {'version': 1},
      },
    });
    // Дерево вызовов потомков клиент объявит только в задаче 5.4: иначе агент
    // слал бы кадры, которых клиент не умеет показывать (D9, D21).
    final codelab =
        (capabilities['_meta']! as Map)['codelab']! as Map<String, Object?>;
    expect(codelab, isNot(contains('subagentToolCalls')));
    // Других полей вне `_meta` для этого нет, прежние — как раньше.
    expect(capabilities.keys.toSet(), {'fs', 'terminal', '_meta'});
  });
}
