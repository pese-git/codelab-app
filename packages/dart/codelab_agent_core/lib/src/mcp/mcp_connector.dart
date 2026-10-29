import '../cancel/cancel_token.dart';
import '../loop/agent_events.dart';
import '../tools/agent_tool.dart';
import '../util/logger.dart';
import 'mcp_server_config.dart';

/// Подключение MCP-серверов сессии — сервис `AgentCoreServices.mcp`
/// (`agent-core-architecture` §10.3; design.md change `add-agent-mcp-client`,
/// D3, D6).
///
/// Почему порт «по списку серверов даёт инструменты», а не фабрика
/// транспортов: MCP-клиент живёт в пакете над ядром, ядро создать его не
/// может. Хосту нужна одна точка, а фабрики транспортов уходят внутрь
/// реализации (`McpClientConnector`).
///
/// Как использовать: ядро зовёт [connect] в `createSession` / `loadSession`
/// до возврата сессии; при сборке (`buildAgentCore`) проверяет, что
/// [transports] покрывает транспорты capability `mcp` (HOST-3).
abstract interface class McpConnector {
  /// Какие транспорты (`stdio`, `http`) умеет открывать коннектор.
  Set<String> get transports;

  /// Подключает серверы параллельно, каждый в своём `connectTimeout`; сбой
  /// сервера — лог `mcp.server.failed` и отсутствие его инструментов, а не
  /// исключение.
  Future<McpSessionTools> connect(McpConnectRequest request);
}

/// Запрос на подключение серверов одной сессии.
final class McpConnectRequest {
  McpConnectRequest({
    required this.sessionId,
    required this.cwd,
    required List<McpServerConfig> servers,
    required Set<String> reservedNames,
    required this.logger,
    required this.cancel,
  }) : servers = List.unmodifiable(servers),
       reservedNames = Set.unmodifiable(reservedNames);

  final SessionId sessionId;

  /// Рабочая папка сессии: stdio-процесс стартует в ней.
  final String cwd;

  /// Уже слитый и отфильтрованный список (D6), в порядке регистрации.
  final List<McpServerConfig> servers;

  /// Имена базового реестра: имя MCP-инструмента, совпавшее с одним из них,
  /// отключает сервер (HOST-5).
  final Set<String> reservedNames;
  final Logger logger;

  /// Отменяется при `AgentRuntime.dispose()`: подключение, начатое до выхода
  /// хоста, прерывается. Закрытие отдельной сессии токен не отменяет.
  final CancelToken cancel;
}

/// Подключённые серверы одной сессии.
///
/// Как использовать: ядро кладёт [tools] в реестр сессии, берёт [servers]
/// для секции промпта `mcp`, на границе шага забирает [takeUpdate], в
/// `AgentSession.close()` зовёт [close].
abstract interface class McpSessionTools {
  /// В порядке регистрации (D6): серверы конфига, затем серверы клиента;
  /// внутри сервера — порядок `tools/list`.
  List<AgentTool> get tools;

  /// Подключённые серверы для секции промпта (§11.5).
  List<McpServerSummary> get servers;

  /// Ожидающий результат `notifications/tools/list_changed`; забирает и
  /// очищает (D6). Ядро зовёт его только на границе шага и перед ходом.
  McpToolsUpdate? takeUpdate();

  /// Приводит подключённые серверы к [servers] (повторный `session/load`,
  /// `AgentSession.setMcpServers`, D11): совпавшие по `name` и параметрам
  /// (`McpServerConfig.sameConnection`) остаются, исчезнувшие закрываются,
  /// новые подключаются.
  ///
  /// [servers] — полный желаемый список после слияния и фильтра ядра (D6):
  /// серверы конфига, затем серверы клиента в порядке регистрации. Серверы
  /// конфига в нём совпадают с уже подключёнными, поэтому остаются
  /// нетронутыми; сервер конфига, вытесненный клиентом, в списке отсутствует
  /// и закрывается. Новые серверы занимают имена инструментов последними
  /// (коллизия отключает новый, а не работающий сервер). Сбой сервера — лог
  /// `mcp.server.failed`, а не исключение.
  Future<void> replaceServers(List<McpServerConfig> servers);

  /// Идемпотентно; закрывает транспорты параллельно.
  Future<void> close();
}

/// Новый полный набор MCP-инструментов сессии вместо прежнего.
final class McpToolsUpdate {
  McpToolsUpdate({
    required List<AgentTool> tools,
    required List<McpServerSummary> servers,
  }) : tools = List.unmodifiable(tools),
       servers = List.unmodifiable(servers);

  final List<AgentTool> tools;
  final List<McpServerSummary> servers;
}

/// Строка секции промпта `mcp` (§11.5, D12): сервер, число его инструментов
/// и префикс их имён.
final class McpServerSummary {
  const McpServerSummary({required this.name, required this.toolCount});

  final String name;
  final int toolCount;
}
