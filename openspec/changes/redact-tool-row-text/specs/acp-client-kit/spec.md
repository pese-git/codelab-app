## MODIFIED Requirements

### Requirement: Строка инструмента без сырого JSON
`ToolCallView` SHALL нести `rawInput`, пути `locations` и текст текстовых элементов `content` вызова. `ToolRowFormatter.format` SHALL быть чистой функцией `ToolCallItem` и `cwd` сессии, возвращающей `ToolRowView` с меткой, деталью и необязательной второй строкой по `dart-agent-and-clients` §12.1.6, без поля времени.

Метка SHALL определяться видом вызова: `read` → `Read`, `edit` → `Edit`, `delete` → `Delete`, `move` → `Move`, `search` → `Search`, `execute` → `Run`, `fetch` → `Fetch`, `think` → `Think`, `switch_mode` → `Mode`, `other` → `title` вызова после очистки (ниже). Вызов, чей строковый `kind` клиент не знает, имеет вид `other` (требование «Неизвестный вид вызова инструмента» acp-protocol-client) и получает метку по `title`. У `switch_mode` нет своих полей `rawInput`: его деталь берётся общим правилом из `title` (design.md change `tolerate-unknown-tool-kind`, D7).

Деталь SHALL браться первым подходящим правилом §12.1.6 из скалярных полей `rawInput` или `locations` и никогда не из сериализации объекта; путь внутри `cwd` SHALL показываться относительно `cwd`; у `fetch` SHALL отбрасываться схема, ведущие `/`, `\` и пробелы, userinfo, query-строка и фрагмент: перед разбором SHALL удаляться табы и переводы строк и обрезаться пробелы (в том числе юникодные) и управляющие символы по краям; userinfo — всё до последнего `@` в authority, то есть до первого `/`, `?` или `#` после схемы и ведущих `/`, `\` и пробелов (или от начала адреса, если схемы нет); `\` границей authority не считается, а `@` в пути, query и фрагменте userinfo не считается. Если деталь пуста или совпадает с меткой, а `title` отличается от метки, деталью SHALL становиться `title`.

Очистка SHALL применяться к детали, к метке вида `other` и ко второй строке: ESC-последовательности и управляющие символы SHALL заменяться пробелом, пробелы SHALL схлопываться, значение SHALL проходить маскирование секретов и затем SHALL быть не длиннее 160 символов с `…`. Маскирование SHALL выполняться до усечения, чтобы усечение не разрезало секрет мимо шаблона.

Вторая строка SHALL быть у вызова в статусе `failed`, в том числе у вызова `agent`, и отсутствовать у остальных. Она SHALL быть первой строкой первого текстового элемента, которая непуста после очистки; если такой строки нет, второй строки нет. Проекция с новыми полями SHALL сохранять равенство инкрементальной проекции и проекции с нуля (требование «Инкрементальная проекция транскрипта»).

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

#### Scenario: Вторая строка упавшего вызова без учётных данных
- **WHEN** форматируется вызов `fetch` в статусе `failed` с текстовым выводом "Error: request to https://user:pass@host/x failed\n    at fetch (node:internal)"
- **THEN** вторая строка — `Error: request to https://<redacted>@host/x failed`, и строки `user:pass` и `pass@` не попадают в `ToolRowView`

#### Scenario: Вторая строка без управляющих символов
- **WHEN** форматируется вызов в статусе `failed` с текстовым выводом "\u001b[31mError:\tboom\u001b[0m"
- **THEN** вторая строка — `Error: boom`, без символа ESC и табуляции

#### Scenario: Строка из одних управляющих символов пропускается
- **WHEN** форматируется вызов в статусе `failed` с текстовым выводом "\u001b[0m\nreal error"
- **THEN** вторая строка — `real error`

#### Scenario: Длинная вторая строка усечена после маскирования
- **WHEN** форматируется вызов в статусе `failed`, первая строка вывода которого — 130 символов `a`, пробел, `https://user:password@host/x/` и 40 символов `b` (200 символов)
- **THEN** вторая строка — 160 символов и кончается `…`, содержит `https://<redacted>@`, и ни `user`, ни `passw` в ней нет

#### Scenario: Вторая строка вызова agent
- **WHEN** форматируется вызов `agent` (`subagentCall`) в статусе `failed` с текстовым выводом "auth failed for https://user:pass@host/x"
- **THEN** вторая строка — `auth failed for https://<redacted>@host/x`

#### Scenario: Метка вызова other без секрета
- **WHEN** форматируется вызов `other` с `title` "curl https://user:pass@host/x" и без `rawInput`
- **THEN** метка `curl https://<redacted>@host/x`, деталь пуста, строка `pass` не попадает в `ToolRowView`

#### Scenario: Метка вызова other без управляющих символов
- **WHEN** форматируется вызов `other` с `title` "mcp\u001b[2J__db__stats"
- **THEN** метка не содержит символа ESC

## ADDED Requirements

### Requirement: Хвост вывода строки инструмента
`ToolRowFormatter.outputTail(item, maxLines:)` SHALL быть чистой функцией, возвращающей хвост вывода вызова для показа под строкой инструмента или `null`. У вызова `agent` (`subagentCall`) она SHALL возвращать `null`: его тело — замаскированный `report`. Иначе она SHALL брать окно из последних `maxLines + 1` строк текстовых элементов вызова, склеенных переводом строки, без хвостовых пробелов и переводов строк. Окно SHALL проходить маскирование секретов целиком, и хвостом SHALL становиться последние `maxLines` строк замаскированного окна. Так шаблон, переходящий через перевод строки, не рвётся на границе хвоста. Если в окне есть `-----END <…> PRIVATE KEY-----`, а выше него в окне нет `-----BEGIN <…> PRIVATE KEY-----`, то участок окна от начала до этого END включительно SHALL заменяться маской `<redacted>` до остального маскирования. Переводы строк и пробелы SHALL сохраняться. Пустой хвост SHALL давать `null`.

Функция SHALL возвращать `null`, если хвост — ровно одна строка, непустая после очистки строки инструмента, и её очистка без усечения равна второй строке вызова. В остальных случаях — замаскированный хвост: строка, которой нет во второй строке, НЕ SHALL пропадать. Работа функции SHALL зависеть от размера окна, а не от объёма всего вывода: обход SHALL идти с конца элементов без разбиения и склейки всего вывода.

#### Scenario: Хвост без учётных данных
- **WHEN** вызов `execute` завершён с выводом "line 1\nDATABASE_URL=postgres://user:pass@db/app\nline 3", `maxLines` 20
- **THEN** хвост — "line 1\nDATABASE_URL=postgres://<redacted>@db/app\nline 3", строки `pass` нет

#### Scenario: Только последние строки
- **WHEN** вывод — 30 строк `l1`…`l30`, `maxLines` 20
- **THEN** хвост — строки `l11`…`l30`

#### Scenario: Токен на границе хвоста
- **WHEN** вывод — 10 строк: `ok1`…`ok4`, `Authorization: Bearer`, `t0k3n-value`, `ok7`…`ok10`, и `maxLines` 5 (строка с токеном — первая строка хвоста, имя `Bearer` — строкой выше)
- **THEN** хвост не содержит `t0k3n-value`, содержит `<redacted>` и кончается `ok10`

#### Scenario: Приватный ключ длиннее хвоста
- **WHEN** вывод — `-----BEGIN RSA PRIVATE KEY-----`, 40 строк тела ключа `MIIEow…`, `-----END RSA PRIVATE KEY-----` и строка `done`, `maxLines` 20
- **THEN** хвост не содержит строк тела ключа, содержит `<redacted>` и `done`

#### Scenario: Приватный ключ без конца
- **WHEN** вывод — `before`, `-----BEGIN OPENSSH PRIVATE KEY-----` и строки тела ключа без `-----END`, `maxLines` 10
- **THEN** хвост — `before` и `<redacted>`, строк тела ключа нет

#### Scenario: Однострочная ошибка не повторяется
- **WHEN** вызов `fetch` упал с единственной строкой вывода "Error:\trequest to https://user:pass@host/x failed"
- **THEN** вторая строка — `Error: request to https://<redacted>@host/x failed`, а хвост — `null`

#### Scenario: Отличная строка не пропадает
- **WHEN** вызов упал с выводом "Error: boom\n    at main (a.dart:1)"
- **THEN** вторая строка — `Error: boom`, хвост — весь вывод из двух строк

#### Scenario: Усечённая вторая строка оставляет вывод
- **WHEN** вызов упал с единственной строкой вывода длиной 300 символов
- **THEN** вторая строка усечена до 160 символов с `…`, а хвост — вся строка

#### Scenario: Вызов agent без хвоста
- **WHEN** вызывается `outputTail` для вызова с `subagentCall`
- **THEN** результат — `null`
