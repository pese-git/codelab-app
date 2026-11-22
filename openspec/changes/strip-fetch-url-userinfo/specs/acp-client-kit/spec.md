## MODIFIED Requirements

### Requirement: Строка инструмента без сырого JSON
`ToolCallView` SHALL нести `rawInput`, пути `locations` и текст текстовых элементов `content` вызова. `ToolRowFormatter.format` SHALL быть чистой функцией `ToolCallItem` и `cwd` сессии, возвращающей `ToolRowView` с меткой, деталью и необязательной второй строкой по `dart-agent-and-clients` §12.1.6, без поля времени.

Метка SHALL определяться видом вызова: `read` → `Read`, `edit` → `Edit`, `delete` → `Delete`, `move` → `Move`, `search` → `Search`, `execute` → `Run`, `fetch` → `Fetch`, `think` → `Think`, `switch_mode` → `Mode`, `other` → `title` вызова. Вызов, чей строковый `kind` клиент не знает, имеет вид `other` (требование «Неизвестный вид вызова инструмента» acp-protocol-client) и получает метку по `title`. У `switch_mode` нет своих полей `rawInput`: его деталь берётся общим правилом из `title` (design.md change `tolerate-unknown-tool-kind`, D7).

Деталь SHALL браться первым подходящим правилом §12.1.6 из скалярных полей `rawInput` или `locations` и никогда не из сериализации объекта; путь внутри `cwd` SHALL показываться относительно `cwd`; у `fetch` SHALL отбрасываться схема, ведущие `/`, `\` и пробелы, userinfo, query-строка и фрагмент: перед разбором SHALL удаляться табы и переводы строк и обрезаться пробелы (в том числе юникодные) и управляющие символы по краям; userinfo — всё до последнего `@` в authority, то есть до первого `/`, `?` или `#` после схемы и ведущих `/`, `\` и пробелов (или от начала адреса, если схемы нет); `\` границей authority не считается, а `@` в пути, query и фрагменте userinfo не считается; управляющие символы SHALL заменяться пробелом; значение SHALL проходить маскирование секретов и SHALL быть не длиннее 160 символов с `…`. Если деталь пуста или совпадает с меткой, а `title` отличается от метки, деталью SHALL становиться `title`.

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

#### Scenario: Адрес fetch теряет userinfo
- **WHEN** форматируется вызов `fetch` с `rawInput.url` "https://user:pass@example.com/x?t=1"
- **THEN** деталь `example.com/x`, и строки `user` и `pass` не попадают в `ToolRowView`

#### Scenario: Пароль адреса fetch с символом @
- **WHEN** форматируется вызов `fetch` с `rawInput.url` "https://user:p@ss@example.com/x"
- **THEN** деталь `example.com/x`, и строки `user`, `p@ss` и `ss@` не попадают в `ToolRowView`

#### Scenario: Символ @ в пути адреса fetch
- **WHEN** форматируется вызов `fetch` с `rawInput.url` "https://example.com/a@b"
- **THEN** деталь `example.com/a@b`

#### Scenario: Адрес fetch без схемы с userinfo
- **WHEN** форматируется вызов `fetch` с `rawInput.url` "user:pass@example.com/x"
- **THEN** деталь `example.com/x`, и строки `user` и `pass` не попадают в `ToolRowView`

#### Scenario: Адрес fetch с ведущими слэшами
- **WHEN** форматируется вызов `fetch` с `rawInput.url` "//user:pass@host/x" или "https:///user:pass@host/x"
- **THEN** деталь `host/x`, и строка `pass` не попадает в `ToolRowView`

#### Scenario: Адрес fetch с пробелом в начале
- **WHEN** форматируется вызов `fetch` с `rawInput.url` " https://user:pass@host/x"
- **THEN** деталь `host/x`, и строка `pass` не попадает в `ToolRowView`

#### Scenario: Обратный слэш в authority адреса fetch
- **WHEN** форматируется вызов `fetch` с `rawInput.url` "https://h\user:pass@host/x"
- **THEN** деталь `host/x`, и строка `pass` не попадает в `ToolRowView`

#### Scenario: Инструмент без скалярных полей
- **WHEN** форматируется вызов `other` с `title` "mcp__db__stats" и `rawInput` `{"items": [1, 2]}`
- **THEN** метка `mcp__db__stats`, деталь пуста, JSON не показан

#### Scenario: Смена режима
- **WHEN** форматируется вызов `switch_mode` с `title` "Ready for implementation" и без `rawInput`
- **THEN** метка `Mode`, деталь `Ready for implementation`, слово `switch_mode` не показано

#### Scenario: Вызов незнакомого вида
- **WHEN** форматируется вызов, пришедший с `kind: "future_kind"` и `title` "Plan sync"
- **THEN** метка `Plan sync`, как у вида `other`, слово `future_kind` не показано
