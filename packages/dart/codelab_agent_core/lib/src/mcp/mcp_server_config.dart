/// Описание MCP-сервера сессии (`agent-core-architecture` §1.2, §6.4;
/// design.md change `add-agent-mcp-client`, D3).
///
/// Почему в ядре: серверы приходят из трёх источников — `session/new` ACP,
/// конфигурации и встроенного режима, — и все они должны проходить одни и те
/// же правила слияния и фильтра по capability (D6). Ядро знает только «что
/// запускать», а не протокол MCP.
library;

/// Откуда пришёл сервер: сервер клиента заменяет сервер конфига с тем же
/// именем (§13.4, шаг 2), а `AgentSession.setMcpServers` меняет только
/// серверы `session` (D11).
enum McpServerOrigin { config, session }

/// Сервер MCP: общая часть и две ветки транспорта.
///
/// Как использовать: хост (ACP-адаптер, конфигурация) создаёт значения и
/// передаёт в `SessionSpec.mcpServers` / `CoreConfig.mcpServers`. [name] —
/// ключ слияния и часть имён инструментов; [connectTimeout] — предел всего
/// подключения одного сервера (по умолчанию 10 с, §13.4, §15).
///
/// Значения [McpStdioServerConfig.env] и [McpHttpServerConfig.headers] —
/// секреты: их нельзя писать в логи и журнал (D6, D13), поэтому
/// `toString()` ветвей их не раскрывает.
sealed class McpServerConfig {
  const McpServerConfig({
    required this.name,
    this.origin = McpServerOrigin.session,
    this.connectTimeout = defaultMcpConnectTimeout,
  });

  final String name;
  final McpServerOrigin origin;
  final Duration connectTimeout;

  /// Ключ транспорта для capability `mcp`: `stdio` или `http`.
  String get transport;

  /// Совпадают ли параметры подключения (без [origin]): по ним
  /// `setMcpServers` решает, оставить ли уже подключённый сервер (D11).
  bool sameConnection(McpServerConfig other);
}

/// Предел подключения одного сервера по умолчанию (§13.4, §15).
const defaultMcpConnectTimeout = Duration(seconds: 10);

/// Локальный процесс, говорящий с агентом по stdin/stdout (ACP: stdio —
/// обязательный транспорт, `03-Session Setup.md`).
final class McpStdioServerConfig extends McpServerConfig {
  const McpStdioServerConfig({
    required super.name,
    required this.command,
    this.args = const [],
    this.env = const {},
    super.origin,
    super.connectTimeout,
  });

  final String command;
  final List<String> args;

  /// Переменные окружения сервера поверх базового набора §4.5 (ENV-6).
  final Map<String, String> env;

  @override
  String get transport => 'stdio';

  @override
  bool sameConnection(McpServerConfig other) =>
      other is McpStdioServerConfig &&
      other.name == name &&
      other.command == command &&
      _listEquals(other.args, args) &&
      _mapEquals(other.env, env);

  @override
  String toString() => 'McpStdioServerConfig($name)';
}

/// Удалённый сервер streamable HTTP.
final class McpHttpServerConfig extends McpServerConfig {
  const McpHttpServerConfig({
    required super.name,
    required this.url,
    this.headers = const [],
    super.origin,
    super.connectTimeout,
  });

  final Uri url;

  /// Заголовки в порядке, присланном клиентом.
  final List<(String, String)> headers;

  @override
  String get transport => 'http';

  @override
  bool sameConnection(McpServerConfig other) =>
      other is McpHttpServerConfig &&
      other.name == name &&
      other.url == url &&
      _listEquals(other.headers, headers);

  @override
  String toString() => 'McpHttpServerConfig($name)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
