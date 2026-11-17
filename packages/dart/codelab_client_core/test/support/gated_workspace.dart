// Рабочее пространство с резолвером, у которого завершением каждого `open`
// управляет тест (change `require-project-folder`, итерация B, D15, D17).
//
// Почему: `ensureAgent`, вытеснение и гонки списка проверяются принудительным
// порядком завершений (`concurrency.md` §69–§70), а не таймерами. Резолвер
// записывает папку, которую получил, — по ней проверяется корень процесса
// агента (`agentDirectory`).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart' show TestFailure;

/// Профиль stdio-агента для тестов.
const gatedProfile = StdioProfile(
  id: 'agent',
  label: 'Agent',
  command: 'codelab-agent',
  args: ['serve', '--stdio'],
);

/// Резолвер с вентилями: каждый `open` берёт очередной вентиль, заведённый
/// [next]; без заведённого вентиля `open` возвращает свежий транспорт
/// с [capabilities].
final class GatedResolver implements TransportResolver {
  GatedResolver({this.capabilities = const AgentCapabilities()});

  /// Что объявляют транспорты, созданные без вентиля.
  final AgentCapabilities capabilities;

  /// Папки, с которыми вызван `open`, по порядку вызовов.
  final directories = <String>[];

  /// Транспорты, отданные `open` (и созданные, и выданные вентилями).
  final opened = <FakeAcpTransport>[];

  final _gates = <Completer<FakeAcpTransport>>[];

  /// Заводит вентиль для очередного `open`.
  Completer<FakeAcpTransport> next() {
    final gate = Completer<FakeAcpTransport>();
    _gates.add(gate);
    return gate;
  }

  /// Транспорт, который агент «запустил» с [capabilities].
  FakeAcpTransport transport([AgentCapabilities? capabilities]) =>
      FakeAcpTransport()
        ..initializeAgentCapabilities = capabilities ?? this.capabilities;

  @override
  bool supports(ConnectionProfile profile) => profile is StdioProfile;

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async {
    directories.add(projectDirectory);
    // Вентили выдаются по порядку заведения тем `open`, которые вызваны
    // после; вызов без заведённого вентиля получает свежий транспорт.
    final FakeAcpTransport transport = _gates.isEmpty
        ? this.transport()
        : await _gates.removeAt(0).future;
    opened.add(transport);
    return transport;
  }
}

/// Рабочее пространство поверх [GatedResolver].
final class GatedWorkspace {
  GatedWorkspace({AgentCapabilities capabilities = const AgentCapabilities()})
    : resolver = GatedResolver(capabilities: capabilities) {
    workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: [resolver],
    );
  }

  final GatedResolver resolver;
  final application = AcpClientApplication(transport: FakeAcpTransport());
  late final ClientWorkspace workspace;

  /// Последний транспорт, открытый резолвером.
  FakeAcpTransport get transport => resolver.opened.last;

  /// Запросы метода [method], отправленные [on] (по умолчанию — последним
  /// транспортом).
  List<JsonRpcRequest> requests(String method, {FakeAcpTransport? on}) => [
    for (final message in (on ?? transport).sentMessages)
      if (message is JsonRpcRequest && message.method == method) message,
  ];

  /// Ждёт запрос [method] на [on] с порядковым номером [index]: уже
  /// отправленный возвращается сразу, иначе ждёт следующий.
  Future<JsonRpcRequest> nextRequest(
    String method,
    FakeAcpTransport on, {
    int index = 0,
  }) async {
    final existing = requests(method, on: on);
    if (existing.length > index) {
      return existing[index];
    }
    final request =
        await on.sent
                .where(
                  (message) =>
                      message is JsonRpcRequest && message.method == method,
                )
                .elementAt(index - existing.length)
                // Страховка от зависания красного теста: запрос не пришёл.
                // Порядок событий задан Completer-ами, а не этим таймером.
                .timeout(
                  const Duration(seconds: 3),
                  onTimeout: () =>
                      throw TestFailure('No $method request #$index was sent.'),
                )
            as JsonRpcRequest;
    // Future потокового `elementAt` завершается синхронно внутри `add`
    // транспорта; без прыжка в микрозадачу вызывающий продолжил бы внутри
    // доставки события, и его следующая отправка упала бы с «Cannot fire new
    // event».
    await Future<void>.value();
    return request;
  }

  void respond(FakeAcpTransport on, JsonRpcRequest request, Object? result) =>
      on.emitInbound(JsonRpcMessage.response(id: request.id, result: result));

  Future<void> dispose() async {
    await workspace.dispose();
    await application.dispose();
  }
}
