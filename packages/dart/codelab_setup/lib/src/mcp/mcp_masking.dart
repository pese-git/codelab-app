/// Правило маски значений MCP-сервера в списке страницы (design.md change
/// `add-provider-setup-ui`, D11, D17; SETUP-1). Внутренний файл моста.
///
/// Почему отдельно: строка списка (`McpServerEntryView`) и черновик формы
/// (`McpServerDraft.maskedValues`) обязаны маскировать одни и те же значения —
/// иначе форма покажет в поле то, что список скрыл (или наоборот). Правило
/// ядра: `displaySafeConfigValue` по имени и шаблону, `maskMcpArgs` для
/// аргументов, для `headers` — `hidesConfigLiteral` (ревью 5a).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        KeyPath,
        displaySafeConfigValue,
        hidesConfigLiteral,
        maskMcpArgs,
        redactedMask;

/// Сегмент ключа `env`/`headers` в пути `KeyPath` (экранирует точки и
/// скобки): часть поля [mcpDisplayValue] вида `env.<сегмент>`.
String mcpKeySegment(String key) => KeyPath.root.child(key).value;

/// Путь листа сервера [name] в формате `KeyPath`: `mcp.servers[<name>].<поле>`.
/// Для правила имён `displaySafeConfigValue`.
String mcpLeafPath(String name, String field) =>
    '${KeyPath.root.child('mcp').child('servers').at(name).value}.$field';

/// Значение `command`, `url` или `env.<KEY>` в том виде, в каком его
/// показывает список (`displaySafeConfigValue` по пути листа).
///
/// Почему: имя ключа и шаблон значения решают, секрет это или нет; одна
/// функция для списка и формы не даёт им разойтись.
///
/// Как использовать: [field] — `command`, `url` или `env.<сегмент>`, где
/// сегмент получен [mcpKeySegment]; заголовки — [mcpDisplayHeader]. Если
/// результат не равен [raw], значение замаскировано.
String mcpDisplayValue(String name, String field, String raw) =>
    displaySafeConfigValue(mcpLeafPath(name, field), raw) as String;

/// Значение заголовка в списке: показывается только чистая ссылка `${…}`
/// (токен бывает и под нейтральным именем, ревью 5a). Не равно [raw] —
/// замаскировано.
String mcpDisplayHeader(String raw) =>
    hidesConfigLiteral(raw) ? redactedMask : raw;

/// Аргументы в списке (`maskMcpArgs`): значения после ключей вида
/// `--api-key` и встроенные токены. Длина и порядок сохраняются.
List<String> mcpDisplayArgs(List<Object?> args) => [
  for (final item in maskMcpArgs(args)) '$item',
];
