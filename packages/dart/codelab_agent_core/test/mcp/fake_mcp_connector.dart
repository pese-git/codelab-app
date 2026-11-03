import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Подставной [McpConnector] для тестов ядра: ядро не знает протокола MCP
/// (design.md change `add-agent-mcp-client`, D3), поэтому о подключении
/// серверов договаривается только через порт.
///
/// Как использовать: [transports] задаёт то, что умеет «коннектор»;
/// [connect] запоминает запросы в [requests], а возвращённый набор
/// инструментов берётся из [toolsOf] (по умолчанию пустой).
final class FakeMcpConnector implements McpConnector {
  FakeMcpConnector({
    Set<String> transports = const {'stdio', 'http'},
    this.toolsOf,
    this.onClose,
    this.failWith,
    this.toolsOnReplace,
    this.failReplaceWith,
    this.replaceBlocksUntilCancel = false,
    this.failToolsReadAfterReplace = false,
  }) : transports = Set.unmodifiable(transports);

  @override
  final Set<String> transports;

  /// Инструменты по запросу; `null` — серверов нет.
  final List<AgentTool> Function(McpConnectRequest request)? toolsOf;

  /// Зовётся при `McpSessionTools.close()` — порядок закрытия в тестах.
  final void Function()? onClose;

  /// Если задан, [connect] бросает его: сбой коннектора целиком.
  final Object? failWith;

  /// Набор инструментов после `replaceServers(servers)`: что оставил бы
  /// настоящий коннектор (оставить совпавшие, закрыть исчезнувшие, подключить
  /// новые, D11). `null` — набор не меняется.
  final List<AgentTool> Function(List<McpServerConfig> servers)? toolsOnReplace;

  /// Если задан, `replaceServers` сессии бросает его.
  final Object? failReplaceWith;

  /// `replaceServers` не возвращается, пока не отменён токен запроса
  /// подключения: имитация подключения нового сервера, зависшего до
  /// `connectTimeout`.
  final bool replaceBlocksUntilCancel;

  /// После `replaceServers` чтение `tools` бросает (сбой чужой реализации).
  final bool failToolsReadAfterReplace;

  final requests = <McpConnectRequest>[];
  final sessions = <FakeMcpSessionTools>[];

  /// Серверы каждого `connect` после раскрытия секретов — то, что получила бы
  /// попытка подключения настоящего коннектора (D11): шаблоны раскрыты
  /// замыканием запроса, а сервер, чей секрет не раскрыт, в списке есть
  /// только в [requests] (настоящий коннектор делает его `failed`).
  final expanded = <List<McpServerConfig>>[];

  /// Причины отказа раскрытия по имени сервера для каждого `connect`.
  final expandFailures = <Map<String, String>>[];

  @override
  Future<McpSessionTools> connect(McpConnectRequest request) async {
    requests.add(request);
    if (failWith case final error?) {
      throw error;
    }
    final failures = <String, String>{};
    expanded.add(await expandServers(request, request.servers, failures));
    expandFailures.add(failures);
    final tools = toolsOf?.call(request) ?? const <AgentTool>[];
    final session = FakeMcpSessionTools(
      tools: tools,
      onClose: onClose,
      toolsOnReplace: toolsOnReplace,
      failReplaceWith: failReplaceWith,
      blockReplaceUntil: replaceBlocksUntilCancel ? request.cancel : null,
      request: request,
      failToolsReadAfterReplace: failToolsReadAfterReplace,
      servers: [
        for (final s in request.servers)
          McpServerSummary(
            name: s.name,
            toolCount: tools
                .where((t) => t.name.startsWith(mcpServerPrefix(s.name)))
                .length,
          ),
      ],
    );
    sessions.add(session);
    return session;
  }
}

/// Раскрывает секреты [servers] замыканием запроса, как перед попыткой
/// подключения; отказ пишет в [failures] (лог `mcp.server.failed` — дело настоящего
/// коннектора, тесты его пакета).
Future<List<McpServerConfig>> expandServers(
  McpConnectRequest request,
  List<McpServerConfig> servers,
  Map<String, String> failures,
) async {
  final out = <McpServerConfig>[];
  for (final server in servers) {
    final expand = request.expandSecrets;
    if (expand == null || server.secretValues.isEmpty) {
      out.add(server);
      continue;
    }
    try {
      out.add(await expand(server));
    } on McpSecretsException catch (error) {
      failures[server.name] = error.reason;
    }
  }
  return out;
}

final class FakeMcpSessionTools implements McpSessionTools {
  FakeMcpSessionTools({
    required List<AgentTool> tools,
    required this.servers,
    this.onClose,
    this.toolsOnReplace,
    this.failReplaceWith,
    this.blockReplaceUntil,
    this.failToolsReadAfterReplace = false,
    this.request,
  }) : _tools = tools;

  /// Запрос подключения сессии: из него берётся замыкание раскрытия секретов
  /// для [replacedExpanded].
  final McpConnectRequest? request;

  /// Серверы каждого `replaceServers` после раскрытия секретов.
  final replacedExpanded = <List<McpServerConfig>>[];

  /// Если задан, `replaceServers` ждёт его завершения (медленное
  /// подключение).
  Completer<void>? replaceGate;

  final CancelToken? blockReplaceUntil;
  final bool failToolsReadAfterReplace;
  var _replacedOnce = false;

  final void Function()? onClose;
  final List<AgentTool> Function(List<McpServerConfig> servers)? toolsOnReplace;
  final Object? failReplaceWith;

  List<AgentTool> _tools;

  @override
  List<AgentTool> get tools {
    if (failToolsReadAfterReplace && _replacedOnce) {
      throw StateError('tools are unreadable');
    }
    return _tools;
  }

  set tools(List<AgentTool> value) => _tools = value;

  @override
  List<McpServerSummary> servers;

  /// Аргументы каждого вызова `replaceServers`, по порядку.
  final replaced = <List<McpServerConfig>>[];

  var closed = 0;
  McpToolsUpdate? pending;

  /// Имена из каждого вызова `reconnect` (D11), по порядку.
  final reconnected = <String>[];

  /// `(имя, enabled)` из каждого вызова `setEnabled` (D11), по порядку.
  final enabledCalls = <(String, bool)>[];

  @override
  McpToolsUpdate? takeUpdate() {
    final update = pending;
    pending = null;
    return update;
  }

  @override
  Future<void> replaceServers(List<McpServerConfig> servers) async {
    replaced.add(servers);
    if (request case final request?) {
      replacedExpanded.add(await expandServers(request, servers, {}));
    }
    await replaceGate?.future;
    await blockReplaceUntil?.onCancel;
    _replacedOnce = true;
    if (failReplaceWith case final error?) {
      throw error;
    }
    if (toolsOnReplace case final next?) {
      tools = next(servers);
      this.servers = [
        for (final s in servers)
          McpServerSummary(
            name: s.name,
            toolCount: tools
                .where((t) => t.name.startsWith(mcpServerPrefix(s.name)))
                .length,
          ),
      ];
    }
  }

  @override
  Future<void> reconnect(String name) async => reconnected.add(name);

  @override
  Future<void> setEnabled(String name, bool enabled) async =>
      enabledCalls.add((name, enabled));

  @override
  Future<void> close() async {
    closed++;
    onClose?.call();
  }
}
