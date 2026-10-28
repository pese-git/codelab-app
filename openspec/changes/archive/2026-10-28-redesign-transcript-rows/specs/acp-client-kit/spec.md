## ADDED Requirements

### Requirement: Строка инструмента без сырого JSON
`ToolCallView` SHALL нести `rawInput`, пути `locations` и текст текстовых элементов `content` вызова. `ToolRowFormatter.format` SHALL быть чистой функцией `ToolCallItem` и `cwd` сессии, возвращающей `ToolRowView` с меткой, деталью и необязательной второй строкой по `dart-agent-and-clients` §12.1.6, без поля времени.

Метка SHALL определяться видом вызова: `read` → `Read`, `edit` → `Edit`, `delete` → `Delete`, `move` → `Move`, `search` → `Search`, `execute` → `Run`, `fetch` → `Fetch`, `think` → `Think`, `other` → `title` вызова.

Деталь SHALL браться первым подходящим правилом §12.1.6 из скалярных полей `rawInput` или `locations` и никогда не из сериализации объекта; путь внутри `cwd` SHALL показываться относительно `cwd`; у `fetch` SHALL отбрасываться схема и query-строка; управляющие символы SHALL заменяться пробелом; значение SHALL проходить маскирование секретов и SHALL быть не длиннее 160 символов с `…`. Если деталь пуста или совпадает с меткой, а `title` отличается от метки, деталью SHALL становиться `title`.

Вторая строка SHALL быть первой непустой строкой первого текстового элемента у вызова в статусе `failed` и отсутствовать у остальных. Проекция с новыми полями SHALL сохранять равенство инкрементальной проекции и проекции с нуля (требование «Инкрементальная проекция транскрипта»).

#### Scenario: Команда из нескольких строк
- **WHEN** форматируется вызов `execute` с `rawInput.command` "npm test --\n  --watch=false"
- **THEN** `ToolRowView` — метка `Run`, деталь `npm test -- --watch=false`, второй строки нет

#### Scenario: Чтение диапазона внутри проекта
- **WHEN** форматируется вызов `read` с `rawInput` `{"path": "/work/app/lib/a.dart", "offset": 10, "limit": 20}` в сессии с `cwd` `/work/app`
- **THEN** метка `Read`, деталь `lib/a.dart:10-29`

#### Scenario: URL без query-строки
- **WHEN** форматируется вызов `fetch` с `rawInput.url` "https://example.com/docs?token=abc"
- **THEN** деталь `example.com/docs`, и строка `token=abc` не попадает в `ToolRowView`

#### Scenario: Инструмент без скалярных полей
- **WHEN** форматируется вызов `other` с `title` "mcp__db__stats" и `rawInput` `{"items": [1, 2]}`
- **THEN** метка `mcp__db__stats`, деталь пуста, JSON не показан
