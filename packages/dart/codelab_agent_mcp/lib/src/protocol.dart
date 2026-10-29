/// Модели сообщений MCP, нужные клиенту инструментов (design.md change
/// `add-agent-mcp-client`, D2, D5, D7).
///
/// Источник — нормативный текст `docs/protocols/mcp/specification/`
/// (`2026-07-28`) и `2025-11-25/` (legacy). Поля, которых там нет, не вводятся.
/// Разбор терпим к неизвестным полям (совместимость вперёд), но строг к
/// форме обязательных: нарушение — [McpSchemaException].
library;

/// Эпоха сервера (`basic/versioning.md`): modern — версия и capabilities в
/// `_meta` каждого запроса, legacy — рукопожатие `initialize`.
enum McpEra { modern, legacy }

/// Единственная modern-версия клиента и предпочтительная вообще (D2).
const modernProtocolVersion = '2026-07-28';

/// Версия, которую клиент просит в `initialize` (D2).
const legacyRequestedVersion = '2025-11-25';

/// Версии legacy, принимаемые в ответе `initialize` (D2).
const legacyAcceptedVersions = {'2025-11-25', '2025-06-18', '2025-03-26'};

/// Коды modern-ошибок, по которым распознаётся modern-сервер (D4).
const mcpHeaderMismatch = -32020;
const mcpMissingClientCapability = -32021;
const mcpUnsupportedProtocolVersion = -32022;

bool isModernErrorCode(int code) =>
    code == mcpHeaderMismatch ||
    code == mcpMissingClientCapability ||
    code == mcpUnsupportedProtocolVersion;

/// Ответ сервера не соответствует схеме.
final class McpSchemaException implements Exception {
  const McpSchemaException(this.message);

  final String message;

  @override
  String toString() => 'McpSchemaException: $message';
}

/// `resultType` результата (`basic/index.md`, «ResultType»).
enum ResultType { complete, inputRequired }

/// Отсутствующий `resultType` — `complete` (ответ legacy-сервера),
/// неизвестный — ответ не по схеме.
ResultType parseResultType(Map<String, Object?> result) =>
    switch (result['resultType']) {
      null || 'complete' => ResultType.complete,
      'input_required' => ResultType.inputRequired,
      _ => throw const McpSchemaException('unknown resultType'),
    };

Map<String, Object?>? _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : null;

/// Строка или `null`: поле неверного типа не должно ронять разбор списка.
String? _string(Object? value) => value is String ? value : null;

/// Результат `server/discover` (`server/discover.md`).
final class DiscoverResult {
  const DiscoverResult({
    required this.supportedVersions,
    required this.capabilities,
    this.serverInfo,
  });

  factory DiscoverResult.fromJson(Map<String, Object?> json) {
    final versions = json['supportedVersions'];
    if (versions is! List || versions.any((v) => v is! String)) {
      throw const McpSchemaException('supportedVersions is not a string list');
    }
    return DiscoverResult(
      supportedVersions: List<String>.from(versions),
      capabilities: _map(json['capabilities']) ?? const {},
      serverInfo: _map(
        _map(json['_meta'])?['io.modelcontextprotocol/serverInfo'],
      ),
    );
  }

  final List<String> supportedVersions;
  final Map<String, Object?> capabilities;

  /// Самоописание сервера: только для лога, поведение от него не зависит.
  final Map<String, Object?>? serverInfo;

  bool get hasTools => capabilities['tools'] is Map;
  bool get toolsListChanged =>
      _map(capabilities['tools'])?['listChanged'] == true;
}

/// Результат legacy-`initialize` (`2025-11-25/basic/lifecycle.md`).
final class InitializeResult {
  const InitializeResult({
    required this.protocolVersion,
    required this.capabilities,
    this.serverInfo,
  });

  factory InitializeResult.fromJson(Map<String, Object?> json) {
    final version = json['protocolVersion'];
    if (version is! String) {
      throw const McpSchemaException('protocolVersion is not a string');
    }
    return InitializeResult(
      protocolVersion: version,
      capabilities: _map(json['capabilities']) ?? const {},
      serverInfo: _map(json['serverInfo']),
    );
  }

  final String protocolVersion;
  final Map<String, Object?> capabilities;
  final Map<String, Object?>? serverInfo;

  bool get hasTools => capabilities['tools'] is Map;
  bool get toolsListChanged =>
      _map(capabilities['tools'])?['listChanged'] == true;

  /// Сервер объявил поддержку `tools/call` как задачи (legacy `tasks`).
  bool get tasksForToolsCall =>
      _map(_map(_map(capabilities['tasks'])?['requests'])?['tools'])?['call'] !=
      null;
}

/// Определение инструмента сервера (`server/tools.md`, `Tool`).
///
/// Хранит сырые схему и аннотации: решения по ним (вид, имя, пропуск) принимает
/// `McpTool` и коннектор (D7), а клиент только отбрасывает заведомо
/// непригодные (D5, шаг 4).
final class McpToolDefinition {
  const McpToolDefinition({
    required this.name,
    required this.inputSchema,
    this.title,
    this.description,
    this.annotations,
    this.taskSupport,
    this.raw = const {},
  });

  factory McpToolDefinition.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    return McpToolDefinition(
      name: name is String ? name : '',
      title: _string(json['title']),
      description: _string(json['description']),
      inputSchema: json['inputSchema'],
      annotations: _map(json['annotations']),
      taskSupport: _string(_map(json['execution'])?['taskSupport']),
      raw: json,
    );
  }

  /// Пустая строка — инструмент без имени (его пропускает `McpTool`).
  final String name;
  final String? title;
  final String? description;

  /// Как прислал сервер; не-объект — повод пропустить инструмент (D7).
  final Object? inputSchema;
  final Map<String, Object?>? annotations;

  /// `execution.taskSupport` (legacy).
  final String? taskSupport;
  final Map<String, Object?> raw;
}

/// Страница `tools/list`.
final class ListToolsResult {
  const ListToolsResult(this.tools, this.nextCursor);

  factory ListToolsResult.fromJson(Map<String, Object?> json) {
    final tools = json['tools'];
    if (tools is! List) {
      throw const McpSchemaException('tools is not a list');
    }
    final next = json['nextCursor'];
    if (next != null && next is! String) {
      throw const McpSchemaException('nextCursor is not a string');
    }
    return ListToolsResult([
      for (final t in tools)
        if (t is Map) McpToolDefinition.fromJson(Map<String, Object?>.from(t)),
    ], next as String?);
  }

  final List<McpToolDefinition> tools;

  /// Курсор непрозрачен: пустая строка — допустимый курсор, а не конец;
  /// конец — `null` (`pagination.md`, D5).
  final String? nextCursor;
}

/// Результат `tools/call` (`CallToolResult`).
final class CallToolResult {
  const CallToolResult({
    required this.content,
    this.structuredContent,
    this.isError = false,
  });

  factory CallToolResult.fromJson(Map<String, Object?> json) {
    final content = json['content'];
    if (content is! List) {
      throw const McpSchemaException('content is not a list');
    }
    final isError = json['isError'];
    if (isError != null && isError is! bool) {
      throw const McpSchemaException('isError is not a bool');
    }
    return CallToolResult(
      content: [
        for (final block in content)
          if (block is Map)
            Map<String, Object?>.from(block)
          else
            throw const McpSchemaException('content block is not an object'),
      ],
      structuredContent: json['structuredContent'],
      isError: isError == true,
    );
  }

  /// Блоки как прислал сервер: проекцию в текст делает `McpTool` (D7).
  final List<Map<String, Object?>> content;
  final Object? structuredContent;
  final bool isError;
}
