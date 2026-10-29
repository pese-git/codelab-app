import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'mcp_client.dart';
import 'protocol.dart';
import 'text.dart';

/// Предел описания инструмента в схеме для модели, в рунах Unicode (D7).
const mcpDescriptionLimit = 2048;

/// Инструмент MCP-сервера как `AgentTool` (`agent-core-architecture` §6.4;
/// design.md change `add-agent-mcp-client`, D7).
///
/// Почему отдельный класс: MCP-инструмент должен идти той же дорогой, что
/// встроенные, — через единую точку исполнения с политикой разрешений
/// (TOOL-1, P-01), — но решения о нём принимает не модель и не сервер: сервер
/// недоверен. Поэтому `tier` всегда `exec`, `outputTrust` всегда `untrusted`,
/// а аннотации сервера влияют только на `kind` (отображение).
///
/// Как использовать: коннектор вызывает [create] для каждого определения из
/// `tools/list`; `null` — инструмент заведомо непригоден и уже записан в лог
/// `mcp.tool.invalid`. Исполняет вызов только `ToolExecutor`.
final class McpTool extends AgentTool {
  McpTool._({
    required this.serverName,
    required this.definition,
    required McpClient client,
    required String name,
    required String description,
    required Map<String, Object?> parameters,
    required ToolKind kind,
  }) : _client = client,
       _name = name,
       _description = description,
       _parameters = parameters,
       _kind = kind;

  /// Строит инструмент или возвращает `null` с логом `mcp.tool.invalid`
  /// (нет имени, `inputSchema` не объект) — остальные инструменты сервера
  /// регистрируются (D7).
  static McpTool? create({
    required String server,
    required McpToolDefinition definition,
    required McpClient client,
    required Logger logger,
    required SessionId sessionId,
  }) {
    void invalid(String reason) => logger.log(
      LogLevel.warning,
      'mcp.tool.invalid',
      fields: {
        'session_id': sessionId.value,
        'server': server,
        // Имя приходит от недоверенного сервера (D13).
        'tool': truncateRunes(definition.name, 64),
        'reason': reason,
      },
    );

    if (definition.name.isEmpty) {
      invalid('tool has no name');
      return null;
    }
    final schema = definition.inputSchema;
    if (schema is! Map) {
      invalid('inputSchema is not an object');
      return null;
    }
    if (schemaKeywordViolations(schema).isNotEmpty) {
      invalid('malformed inputSchema');
      return null;
    }
    final base = _firstNonEmpty([
      definition.description,
      definition.title,
      definition.name,
    ]);
    final runes = base.runes.toList();
    var description = base;
    if (runes.length > mcpDescriptionLimit) {
      description =
          '${String.fromCharCodes(runes.take(mcpDescriptionLimit))}\n'
          '[Description truncated: ${runes.length - mcpDescriptionLimit} '
          'characters omitted.]';
      logger.log(
        LogLevel.info,
        'mcp.tool.description_truncated',
        fields: {
          'session_id': sessionId.value,
          'server': server,
          'tool': definition.name,
          'length': runes.length,
        },
      );
    }
    return McpTool._(
      serverName: server,
      definition: definition,
      client: client,
      name: mcpToolName(server, definition.name),
      description: description,
      parameters: Map<String, Object?>.from(schema),
      kind: _kindOf(definition.annotations),
    );
  }

  /// `name` сервера (часть префикса).
  final String serverName;
  final McpToolDefinition definition;
  final McpClient _client;
  final String _name;
  final String _description;
  final Map<String, Object?> _parameters;
  final ToolKind _kind;

  @override
  String get name => _name;

  @override
  String get description => _description;

  @override
  Map<String, Object?> get parameters => _parameters;

  /// Вид только по явным значениям аннотаций, без умолчаний спецификации
  /// MCP; это подсказка для отображения, а не для решений политики (D7).
  @override
  ToolKind get kind => _kind;

  @override
  ToolTier get tier => ToolTier.exec;

  @override
  ContentTrust outputTrust(Map<String, Object?> args) => ContentTrust.untrusted;

  /// Заголовок вызова — полное имя: критерий E-02 «имя инструмента в
  /// `title`».
  @override
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => ToolPresentation(title: _name);

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final outcome = await _client.callTool(
      definition.name,
      args,
      cancel: ctx.cancel,
      toolCallId: ctx.toolCallId,
    );
    return switch (outcome) {
      McpCallError(:final text) => ToolExecutionResult([
        TextContent(text),
      ], isError: true),
      McpCallDone(:final result) => _project(result, ctx.supportsImages),
    };
  }

  static String _firstNonEmpty(List<String?> candidates) =>
      candidates.firstWhere((c) => c != null && c.isNotEmpty)!;

  static ToolKind _kindOf(Map<String, Object?>? annotations) {
    if (annotations == null) {
      return ToolKind.other;
    }
    if (annotations['readOnlyHint'] == true) {
      return ToolKind.read;
    }
    if (annotations['destructiveHint'] == true) {
      return annotations['openWorldHint'] == false
          ? ToolKind.edit
          : ToolKind.execute;
    }
    return ToolKind.other;
  }
}

/// Сводит блоки `CallToolResult` в один `TextContent` в порядке блоков, так
/// весь результат попадает в одну ограду (P-16; таблица D7). Картинки — отдельные
/// `ImageContent` при поддержке моделью.
ToolExecutionResult _project(CallToolResult result, bool supportsImages) {
  final parts = <String>[];
  final images = <ImageContent>[];
  for (final block in result.content) {
    switch (block['type']) {
      case 'text':
        parts.add('${block['text'] ?? ''}');
      case 'image':
        final mime = '${block['mimeType'] ?? ''}';
        if (supportsImages) {
          images.add(
            ImageContent(base64: '${block['data'] ?? ''}', mimeType: mime),
          );
        } else {
          parts.add(
            '[image omitted: the model does not accept images ($mime)]',
          );
        }
      case 'audio':
        parts.add(
          '[audio omitted: ${block['mimeType'] ?? ''}, '
          '${_byteCount('${block['data'] ?? ''}')} bytes]',
        );
      case 'resource':
        parts.add(_resource(block['resource']));
      case 'resource_link':
        parts.add(
          '[resource link: ${block['uri'] ?? ''} (${block['name'] ?? ''})]',
        );
      default:
        // Совместимость вперёд: неизвестный тип не ломает разбор (D7).
        parts.add('[unsupported content: ${block['type']}]');
    }
  }
  if (result.content.isEmpty) {
    parts.add(
      result.structuredContent != null
          ? canonicalJson(result.structuredContent)
          : '[MCP tool returned no content]',
    );
  }
  return ToolExecutionResult([
    if (parts.isNotEmpty) TextContent(parts.join('\n')),
    ...images,
  ], isError: result.isError);
}

String _resource(Object? resource) {
  if (resource is! Map) {
    return '[unsupported content: resource]';
  }
  final uri = '${resource['uri'] ?? ''}';
  if (resource['text'] is String) {
    return '<resource uri="$uri">\n${resource['text']}\n</resource>';
  }
  return '[binary resource $uri, '
      '${_byteCount('${resource['blob'] ?? ''}')} bytes, not shown]';
}

/// Размер декодированных данных base64; битая строка считается по длине.
int _byteCount(String base64Text) {
  try {
    return base64.decode(base64Text).length;
  } on FormatException {
    return base64Text.length;
  }
}
