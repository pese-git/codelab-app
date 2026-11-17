/// Правило имени MCP-сервера (design.md change `add-provider-setup-ui`, D11,
/// решение Q20).
library;

final _nameFormat = RegExp(r'^[^\s\[\]"]+$');

/// Годится ли [name] именем сервера `mcp.servers`: непустое, без пробельных
/// символов, `[`, `]` и `"`.
///
/// Почему в ядре: имя становится частью пути ключа `mcp.servers[<name>]`, и
/// `a]` или `a b` превратились бы в чужой путь. Правило одно на
/// `codelab mcp add|remove` (`codelab_agent_io`) и форму сервера клиентов
/// (`McpServerDraft` моста `codelab_setup`): две копии разошлись бы. Тексты
/// ошибок остаются за вызывающим — у подкоманды и формы они разные.
///
/// Как использовать: `isValidMcpServerName(name)`; уникальность имени
/// проверяет вызывающий.
bool isValidMcpServerName(String name) => _nameFormat.hasMatch(name);
