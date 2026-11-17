/// Тип транспорта MCP-сервера и его вывод из элемента `mcp.servers`
/// (design.md change `add-provider-setup-ui`, D11).
library;

/// Тип транспорта MCP-сервера: поле `type` элемента `mcp.servers`.
enum McpTransportKind { stdio, http }

/// Тип транспорта сырого элемента `mcp.servers`.
///
/// Почему одна функция: форма (`McpServerDraft.fromElement`) и строка страницы
/// (`McpServerEntryView`) обязаны одинаково читать элемент без `type`; две
/// копии разошлись бы. Явный `type: http` — `http`; без `type` элемент с
/// `url` и без `command` считается `http`; остальное — `stdio`.
McpTransportKind mcpTransportKindOf(Map<String, Object?> element) {
  final type = element['type'];
  if (type == 'http') {
    return McpTransportKind.http;
  }
  if (type == null && element['url'] is String && element['command'] == null) {
    return McpTransportKind.http;
  }
  return McpTransportKind.stdio;
}
