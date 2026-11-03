# agent-slash-commands Specification

## Purpose
Шаблоны промптов и встроенные команды Dart-агента. Шаблоны — `*.md` из `$CODELAB_HOME/prompts/` и, только для доверенного проекта, из `<cwd>/.codelab/prompts/`: они публикуются клиенту через `available_commands_update`, а `/name args` разворачивается одним проходом подстановки `$ARGUMENTS` и `$1..$9`. Встроенные команды `config` (`reload | check`) и `mcp` (`list | reload [<id>] | enable <id> | disable <id>`) идут в списке первыми и исполняются без модели и без записи в журнал; `config` объявляется только при источнике конфигурации и `configCommand: true` (у `serve --ws` его нет), `mcp` — только при capability `mcp`. Список команд сессии строится при открытии и перезагрузкой конфигурации не меняется. Зарезервированные имена не переопределяются, `/x` без шаблона и без встроенной команды уходит модели как есть; журнал сессии хранит исходную команду шаблона (`MessageRecord.command`) для реплея и заголовка. MCP prompts — вне этой спецификации. Решения — `design.md` архивных change `add-agent-project-files` (D7–D9) и `add-config-writer-and-reload` (D9, D12), `agent-core-architecture` §17.2, §17.5.6, §17.5.7.
## Requirements
### Requirement: Каталоги шаблонов команд и доверие
Шаблоны команд SHALL читаться из `*.md` первого уровня, без рекурсии:
- `<cwd>/.codelab/prompts/` — только если канонический `cwd` сессии есть в `CoreConfig.trustedProjects`;
- `$CODELAB_HOME/prompts/` — всегда.

Если каталог проекта существует, а проект не доверенный, файлы НЕ SHALL читаться, а загрузчик SHALL дать одну диагностику `info` `untrusted_project`. При одинаковом имени шаблон проекта SHALL заменять пользовательский, а пользовательский — получать диагностику `info` `shadowed`.

#### Scenario: Недоверенный проект
- **WHEN** проект не в `trusted_projects`, а `<cwd>/.codelab/prompts/review.md` существует
- **THEN** команды `review` в `available_commands_update` нет, есть диагностика `untrusted_project`

#### Scenario: Проект перекрывает пользователя
- **WHEN** проект доверенный, `review.md` есть и в проекте, и в `$CODELAB_HOME/prompts`
- **THEN** `/review` разворачивается телом проектного файла, у пользовательского — диагностика `shadowed`

### Requirement: Формат шаблона и проверка
Имя команды SHALL быть именем файла без `.md` по правилу `^[a-z0-9][a-z0-9-]{0,63}$`; другое имя — диагностика `warning` `invalid_name`, файл пропущен. Frontmatter необязателен; если он есть, SHALL разбираться в строгом профиле CFG-21 и содержать только `description` (1–200 символов) и `argument-hint` (1–80 символов). Другой ключ — `error` `unknown_key`, нарушение профиля — `error` `profile` или `syntax` со строкой и столбцом; файл пропускается. Без `description` описанием SHALL быть первая непустая строка тела, обрезанная до 200 символов. Тело SHALL быть непустым и не больше 32 КиБ, файл — не больше 64 КиБ, файлов в каталоге — не больше 100 (лишние — `limit_exceeded`). Файл не в UTF-8 — `not_utf8`.

Ошибка файла НЕ SHALL прерывать создание сессии.

#### Scenario: Битый frontmatter
- **WHEN** `review.md` начинается с frontmatter, где ключ `description` повторён дважды
- **THEN** команды `review` нет, диагностика `profile` называет путь файла и обе позиции, сессия создана

#### Scenario: Неверное имя
- **WHEN** в каталоге лежат `Review.md` и `my_cmd.md`
- **THEN** обе команды отсутствуют, у каждого файла диагностика `invalid_name`

### Requirement: Резервные имена команд
Имена встроенных команд §13.4 (`compact`, `mode`, `model`, `status`, `usage`, `redact`, `config`, `mcp`, `rename`, `branches`, `branch`, `rewind`, `fork`, `label`, `approve`, `timer`, `memory`, `tasks`, `help`) и `skill` SHALL быть зарезервированы. Шаблон с таким именем НЕ SHALL загружаться и SHALL давать диагностику `warning` `reserved_name` (SKL-7).

#### Scenario: Шаблон с именем встроенной команды
- **WHEN** в `$CODELAB_HOME/prompts` лежит `help.md`
- **THEN** команды `help` из шаблона нет, есть диагностика `reserved_name`, промпт `/help` не разворачивается этим файлом

### Requirement: Список команд сессии
`AgentSession.commands` SHALL возвращать сначала встроенные команды сессии (требование «Встроенные команды config и mcp») в порядке §13.4, затем команды шаблонов `SlashCommand {name, description, inputHint, source: template}` в байтовом порядке имён. `inputHint` шаблона SHALL быть `argument-hint`, иначе `"arguments"`, если тело содержит `$ARGUMENTS` или `$1`…`$9`, иначе `null`. Список строится при открытии сессии и НЕ SHALL меняться до её закрытия, в том числе при перезагрузке конфигурации (design.md change `add-config-writer-and-reload`, D9). Инструменты модели в список НЕ SHALL попадать (R-07).

#### Scenario: Подсказка ввода
- **WHEN** у `review.md` нет `argument-hint`, а тело содержит `$1`, у `test.md` нет ни подсказки, ни плейсхолдеров
- **THEN** у `review` `inputHint == "arguments"`, у `test` — `null`

#### Scenario: Встроенные команды идут первыми
- **WHEN** ядро собрано с `ConfigSource` и capability `mcp`, а у сессии есть шаблон `review`
- **THEN** список — `config`, `mcp`, `review`

#### Scenario: Перезагрузка не меняет список
- **WHEN** после открытия сессии перезагрузка добавляет проект в `trusted_projects`, и у проекта есть `.codelab/prompts/fix.md`
- **THEN** список живой сессии не изменился; новая сессия того же `cwd` тоже без `fix` до перезапуска (доверие закреплено, R0-1); `/config reload` отвечает строкой `Restart required: trusted_projects`

### Requirement: Разворачивание команды
`AgentSession.prompt` SHALL разбирать только первый текстовый блок промпта. Если блок начинается с `/`, а слово до первого пробельного символа соответствует `^[A-Za-z0-9][A-Za-z0-9:_-]*$` и совпадает с именем шаблона, тело шаблона с подставленными аргументами SHALL заменить этот блок; остальные блоки идут после него в исходном порядке. Иначе промпт SHALL уходить модели без изменений.

Подстановка SHALL выполняться одним проходом слева направо:
- `$ARGUMENTS` → остаток строки как введён (`raw`: после ведущих пробелов, без завершающего `\r?\n`);
- `$1`…`$9` → аргументы `splitArguments`, отсутствующий — пустая строка;
- `$$` → `$`;
- `$10` → первый аргумент и `0`;
- `$` перед другим символом остаётся литералом.

Подставленные значения НЕ SHALL сканироваться повторно; `{{…}}` в теле не обрабатывается. Без плейсхолдеров в теле при непустом `raw` SHALL дописываться `\n\nARGUMENTS: <raw>`. `splitArguments`: разделитель — пробельные символы; `"…"` и `'…'` группируют слово; внутри `"…"` экранируются `\"` и `\\`; вне кавычек `\` даёт следующий символ; незакрытая кавычка закрывается концом ввода (D8). Разбор НЕ SHALL исполнять shell и читать файлы (SKL-8).

#### Scenario: Шаблон с аргументами
- **WHEN** тело `review.md` — `Review $1 focusing on $2. All: $ARGUMENTS`, а промпт — `/review lib/parser "error handling"`
- **THEN** модель получает сообщение пользователя `Review lib/parser focusing on error handling. All: lib/parser "error handling"` (`acp/prompt-template-command`, E-07)

#### Scenario: Значение не разворачивается повторно
- **WHEN** тело — `X $1`, а промпт — `/t '$ARGUMENTS'`
- **THEN** модель получает `X $ARGUMENTS`

#### Scenario: Незакрытая кавычка
- **WHEN** тело — `[$1]`, а промпт — `/t "error handling`
- **THEN** модель получает `[error handling]`

#### Scenario: Завершающий CRLF
- **WHEN** тело — `[$ARGUMENTS|$1]`, а промпт клиента на Windows — `/t lib\r\n`
- **THEN** модель получает `[lib|lib]`, без `\r` и `\n`

#### Scenario: Не команда
- **WHEN** промпт — `/usr/bin/foo is broken` или `/nope x`, а шаблонов `usr` и `nope` нет
- **THEN** модель получает текст без изменений

#### Scenario: Наблюдаемость
- **WHEN** разворачивается `/review secret-token-123`
- **THEN** лог `command.expanded` содержит `name: review`, `source: template`, `args_bytes` и не содержит `secret-token-123`

### Requirement: Исходный текст команды в журнале
Запись `message` сообщения пользователя, полученного разворачиванием, SHALL нести поле записи `command: {"source": "template", "name": <имя>, "args": <raw>}`. Модель поле НЕ SHALL видеть. `replay()` для такой записи SHALL отдавать первым блоком текст `/<name>` (или `/<name> <args>` при непустом `args`), затем остальные блоки сообщения, кроме развёрнутого текста.

#### Scenario: Реплей показывает команду
- **WHEN** сессия с ходом `/review lib/parser "error handling"` загружается в новом соединении
- **THEN** реплей содержит `user_message_chunk` с текстом `/review lib/parser "error handling"`, а не развёрнутое тело

### Requirement: Встроенные команды config и mcp
Если первый текстовый блок промпта начинается с `/config` или `/mcp` — первый символ блока `/` (ведущие пробелы не пропускаются, как у шаблонов), слово до первого пробельного символа или до конца блока — и команда объявлена в сессии, `AgentSession.prompt` SHALL исполнять её без модели (design.md change `add-config-writer-and-reload`, D12; `agent-core-architecture` §17.5.6, §17.5.7):
- **События.** `TurnStarted`, ответ одним сообщением агента (`MessageStarted`, `MessageDelta`, `MessageEnded`), `TurnEnded` с `endTurn`. Шагов и запросов к модели нет.
- **Отказ.** Исключение внутри команды (кроме сбоя загрузки у `/config check`, который становится текстом ответа) SHALL завершать ход `AgentError` с классом `hook`, текстом `the built-in command failed (<Type>)` и `retrying: false`, затем `TurnEnded` с `failed`, без сообщения агента; слот SHALL освобождаться (design.md, D12, «Отказ команды»).
- **Журнал.** Ни промпт, ни ответ НЕ SHALL записываться в журнал сессии (CFG-18).
- **Тексты** — фиксированные английские, побайтово по §17.5.6 и §17.5.7. Строки, пришедшие от пользователя (`<id>`, неизвестный аргумент), SHALL обрезаться до 64 символов по рунам; строки проблем конфига (`ConfigIssue.toString()`) НЕ SHALL обрезаться.
- **Наблюдаемость.** Лог `command.builtin {session_id, name, subcommand}` без аргументов; отмена — `command.builtin.cancelled {session_id, name, subcommand}` (info); сбой загрузки у `/config check` — `config.check.failed {session_id, error_class}` (warning); отказ команды — `command.builtin.failed {session_id, name, subcommand, error_class}` (warning); сбой ручного действия `/mcp` — `mcp.server.failed {session_id, server, transport, action, reason}` (warning), где `action` — `reconnect`, `enable` или `disable`, а `reason` — `MCP action failed: <runtimeType>`. Тексты исключений НЕ SHALL попадать ни в ответ, ни в поля лога.

**Объявление:**
- `config` — `{"name":"config","description":"Reload or check the agent config","input":{"hint":"reload | check"}}`, только если ядру передан `ConfigSource` и `buildAgentCore` вызван с `configCommand: true` (по умолчанию). Хост `serve --ws` SHALL передавать `configCommand: false` (R0-3): ответ раскрывал бы пути и тексты проблем конфига машины агента клиенту по сети;
- `mcp` — `{"name":"mcp","description":"List, reload, enable or disable MCP servers","input":{"hint":"list | reload [<id>] | enable <id> | disable <id>"}}`, только при включённой capability `mcp`.

Необъявленная команда (`/config` без `ConfigSource` или при `configCommand: false`) и `/x` для любого другого `x` без шаблона SHALL уходить модели без изменений, как прежде.

**`/config`:**
- `reload` — `reloadConfig()` и строка итога по исходу (design.md, D12, R7-1, R7-2):
  - `applied` с непустым `changedKeys` — `Config reloaded: 1 key changed.` при одном ключе, иначе `Config reloaded: <n> keys changed.`;
  - `applied` с пустым `changedKeys` (все изменённые ключи отложены до перезапуска) — `Config reloaded: no keys applied now.`;
  - `unchanged` — `Config unchanged.`;
  - `failed` — `Config reload failed (1 issue). Current settings kept. Run /config check.` при одной проблеме, иначе `Config reload failed (<n> issues). Current settings kept. Run /config check.`;
  - затем при непустом `restartRequiredKeys` этой перезагрузки — строка `Restart required: <k1>, <k2>`;
- `check` — загрузка без применения: первая строка ровно `Config: valid` или `Config: invalid (issues: <n>)` — та же строка, что итог `config check` CLI, без склонения и при `n = 1`, затем по строке на проблему `- ` + `ConfigIssue.toString()`, то есть `- <source>[:<line>:<column>]: <key>: <message>` (без `<key>: ` при пустом ключе; формат `config check`), затем `Sources: …` и при наличии `Restart required: …`. Если загрузка бросила исключение (сбой чтения, а не проблемы конфига), ответ SHALL быть ровно `Config check failed (<ErrorType>). See the agent log.`, где `<ErrorType>` — тип исключения, а снимок агента НЕ SHALL меняться;
- иначе — `Usage: /config reload | /config check`.

**`/mcp`:**
- `list` (и без аргумента) — таблица §17.5.7 (формат ниже); без серверов — ровно `No MCP servers.` без блока;
- `reload` — `reloadConfig()`, затем при исходе `applied` или `unchanged` немедленная попытка подключения всех серверов в `failed`; при исходе `failed` серверы НЕ SHALL будиться (прежний снимок остаётся целиком, серверы `failed` пробуются по своему расписанию); затем строки итога перезагрузки — те же, что у `/config reload`, включая `Config reloaded: no keys applied now.` и `Restart required: …`, кроме исхода `failed`: `Config reload failed (1 issue); MCP servers unchanged. Run /config check.` при одной проблеме, иначе `Config reload failed (<n> issues); MCP servers unchanged. Run /config check.` — и таблица;
- `reload <id>` — `reconnect(id)` без перечитывания конфига, затем таблица;
- `enable <id>`, `disable <id>` — `setEnabled` только в этой сессии и в памяти, затем таблица; после `session/load` действует конфиг. `<id>` SHALL искаться только среди серверов применённого снимка: новый сервер, отложенный до перезапуска, — `Unknown MCP server`, у отложенного изменённого включается прежний вариант;
- неизвестный `<id>` — `Unknown MCP server: <id>. Run /mcp list.`;
- иначе — `Usage: /mcp list | /mcp reload [<id>] | /mcp enable <id> | /mcp disable <id>`.

**Таблица `/mcp list`** (design.md, D12; образец — фикстура `acp/slash-mcp-list`):
- текст SHALL быть ```` ```text ```` и `\n`, шапка `MCP servers (<n>)` (`n` — число серверов) и `\n`, строки таблицы через `\n`, затем `\n` и закрывающая ограда ```` ``` ````; после ограды `\n` НЕ SHALL быть;
- первая строка таблицы — заголовки `ID`, `SOURCE`, `TRANSPORT`, `STATE`, `TOOLS`, `LAST ERROR`; каждая колонка, кроме последней, SHALL дополняться пробелами справа до длины самой длинной ячейки колонки (с заголовком) в рунах плюс два; последняя колонка НЕ SHALL дополняться пробелами;
- `LAST ERROR` — `lastError`, а при `lastError == null` — `-` в любом состоянии, в том числе у сервера с `enabled: false` в конфиге; только у `failed` с назначенным повтором к ячейке дописывается ` (retry in <n>s)`, где `n` — `retryIn`, округлённый до целых секунд, но не меньше `1`;
- строки SHALL идти в порядке `McpSessionTools.servers`: серверы применённого снимка конфига, затем серверы клиента ACP.

**Слот хода и ход модели** (design.md, D12):
- встроенная команда SHALL занимать слот хода сессии так же, как ход модели: второй `AgentSession.prompt` той же сессии во время команды SHALL отклоняться тем же путём, что во время хода модели. Правило держит `AgentSession`, поэтому оно действует и вне моста ACP (встроенный агент, `codelab`);
- встроенная команда — не ход модели: отсрочку замены серверов конфига до `TurnEnded` она НЕ SHALL вызывать, и замена, вызванная ею, SHALL применяться до ответа.

**Отмена** (design.md, D12, «Отмена встроенной команды»): `session/cancel` и закрытие сессии во время команды SHALL завершать её `TurnEnded` с `cancelled` без сообщения агента и освобождать слот. Начатая перезагрузка и уже исполняемое ручное действие доводятся до конца; новых действий отменённая команда НЕ SHALL начинать — в том числе `/mcp reload` после отмены НЕ SHALL будить серверы `failed`, а её действие, ещё ждавшее в очереди замен, НЕ SHALL исполняться.

Ручные `reconnect` и `setEnabled` НЕ SHALL менять набор инструментов и системный промпт посреди шага модели: действие, завершившееся во время хода модели, SHALL применяться на границе шага (design.md, D11).

К возврату `AgentSession.prompt` встроенной команды все события её хода SHALL быть доставлены подписчикам `events` (ACP-3).

#### Scenario: /mcp list без модели
- **WHEN** у сессии сервер `session/new` и два сервера конфига, один из них `enabled: false`, и приходит промпт `/mcp list`
- **THEN** ответ — одно сообщение с таблицей, `TurnEnded` с `endTurn`, scripted-модель не получила запросов, журнал сессии без новых записей (`acp/slash-mcp-list`)

#### Scenario: /mcp disable только в сессии
- **WHEN** приходит `/mcp disable github`
- **THEN** строка `github` в таблице — `disabled`, `config.yaml` не изменён, после `session/load` сервер снова по конфигу

#### Scenario: Неверный аргумент
- **WHEN** приходит `/mcp frob` или `/config frob`
- **THEN** ответ — соответствующая строка `Usage: …`, модель не вызвана

#### Scenario: /config check после ручной ошибки
- **WHEN** файл конфига содержит опечатку `compaction.reserve_token`, и приходит `/config check`
- **THEN** первая строка — `Config: invalid (issues: 1)`, затем строка `- <путь файла>:<строка>:<столбец>: compaction.reserve_token: unknown key (did you mean reserve_tokens?)`; снимок агента не изменён

#### Scenario: Один изменённый ключ
- **WHEN** в файле конфига изменён только `budget.max_steps`, и приходит `/config reload`
- **THEN** ответ — ровно `Config reloaded: 1 key changed.` без строки `Restart required`; при двух применённых ключах — `Config reloaded: 2 keys changed.`

#### Scenario: Перезагрузка только с отложенными ключами
- **WHEN** в файле конфига изменены только `permissions.tools.exec` и `trusted_projects` (оба отложены до перезапуска, R0-1), и приходит `/config reload`
- **THEN** ответ — две строки: `Config reloaded: no keys applied now.` и `Restart required: permissions.tools.exec, trusted_projects`; строки `Config unchanged.` и `0 keys changed` нет

#### Scenario: Повторная перезагрузка без правок
- **WHEN** после предыдущего сценария файл не менялся, и снова приходит `/config reload`
- **THEN** ответ снова `Config reloaded: no keys applied now.` и `Restart required: permissions.tools.exec, trusted_projects`: ожидающие ключи по-прежнему отличают файлы от работающего процесса; после перезапуска и `/config reload` без правок — ровно `Config unchanged.`

#### Scenario: Одна проблема при перезагрузке
- **WHEN** файл конфига содержит одну ошибку загрузки, и приходят `/config reload` и `/mcp reload`
- **THEN** первая строка ответа `/config reload` — `Config reload failed (1 issue). Current settings kept. Run /config check.`, ответа `/mcp reload` — `Config reload failed (1 issue); MCP servers unchanged. Run /config check.`; при двух проблемах — `(2 issues)` в обеих строках

#### Scenario: /mcp reload только с отложенными ключами
- **WHEN** перезагрузка добавляет только stdio-сервер `x` (отложен, R0-1), и приходит `/mcp reload`
- **THEN** ответ — `Config reloaded: no keys applied now.`, `Restart required: mcp.servers[x]`, затем таблица без `x`

#### Scenario: enable отложенного сервера
- **WHEN** перезагрузка добавила stdio-сервер `x` (отложен), а у stdio-сервера `y` изменила `command` (отложено), и `y` выключен командой; приходят `/mcp enable x` и `/mcp enable y`
- **THEN** первая — `Unknown MCP server: x. Run /mcp list.`; вторая подключает `y` с прежними `command` и `env`

#### Scenario: /mcp reload при невалидном конфиге не будит серверы
- **WHEN** у сессии сервер `docs` в `failed` с назначенным повтором, файл конфига содержит одну ошибку загрузки, и приходит `/mcp reload`
- **THEN** первая строка ответа — `Config reload failed (1 issue); MCP servers unchanged. Run /config check.`, `reconnect` не вызван ни для одного сервера, в таблице `docs` по-прежнему `failed` с суффиксом ` (retry in <n>s)`

#### Scenario: Отменённый /mcp reload
- **WHEN** `/mcp reload` ждёт загрузки конфига, у сессии сервер `a` в `failed` с назначенным повтором, приходит `session/cancel`, затем начинается ход модели и после этого загрузка завершается
- **THEN** команда завершилась `TurnEnded` с `cancelled` без сообщения агента, лог `command.builtin.cancelled {session_id, name: "mcp", subcommand: "reload"}`; `a` не переподключён немедленно (следующая попытка — по расписанию); набор инструментов идущего хода не изменился

#### Scenario: Закрытие сессии во время команды
- **WHEN** `/config reload` ждёт загрузки конфига, и сессию закрывают
- **THEN** `prompt` возвращает `cancelled`; перезагрузка рантайма доводится до конца

#### Scenario: Отказ встроенной команды
- **WHEN** сводка серверов бросает `StateError` с текстом `secret-detail`, и приходит `/mcp list`
- **THEN** события — `TurnStarted`, `AgentError` (`hook`, `the built-in command failed (StateError)`, без `retrying`), `TurnEnded` с `failed`; лог warning `command.builtin.failed {session_id, name: "mcp", subcommand: "list", error_class: "StateError"}`; `secret-detail` нет ни в событиях, ни в логе; мост ACP отвечает на `session/prompt` ошибкой `-32603`; следующий `/mcp list` отвечает таблицей

#### Scenario: Ведущий пробел — не команда
- **WHEN** первый текстовый блок промпта — ` /mcp list`
- **THEN** промпт уходит модели текстом без изменений, как у шаблонов

#### Scenario: Сбой загрузки при /config check
- **WHEN** загрузка конфига для `/config check` бросает `StateError` с текстом `boom`
- **THEN** ответ — ровно `Config check failed (StateError). See the agent log.`, лог warning `config.check.failed {session_id, error_class: "StateError"}`; текста `boom` нет ни в ответе, ни в логе

#### Scenario: Сбой ручного действия /mcp
- **WHEN** `reconnect` сервера `a` бросает исключение по `/mcp reload a`
- **THEN** лог warning `mcp.server.failed` с полями `session_id`, `server: "a"`, `transport`, `action: "reconnect"` и `reason` `MCP action failed: <тип>`; ответ — таблица

#### Scenario: Ячейки таблицы /mcp list
- **WHEN** у сессии сервер конфига `x` в `failed` с `lastError` `connection refused` и `retryIn` 7,6 с, сервер конфига `y` в `failed` с `retryIn` 0,2 с и сервер клиента `z` в `connected` без `lastError`, и приходит `/mcp list`
- **THEN** строки идут `x`, `y`, `z`; ячейки `LAST ERROR` — `connection refused (retry in 8s)`, `<lastError y> (retry in 1s)` и `-`; ни одна строка не кончается пробелом; текст кончается `\n` и закрывающей оградой без `\n` после неё

#### Scenario: Параллельный промпт во время /mcp reload
- **WHEN** `/mcp reload` ждёт загрузки конфига, и в ту же сессию приходит второй `prompt`
- **THEN** второй `prompt` отклонён тем же путём, что во время хода модели; `/mcp reload` отвечает строкой итога и таблицей

#### Scenario: /mcp reload после отложенной замены
- **WHEN** во время хода модели перезагрузка удалила HTTP-сервер `b` (замена отложена), ход завершился, и приходит `/mcp reload`, который добавляет HTTP-сервер `c`
- **THEN** таблица ответа не содержит `b` и содержит `c`: отложенная замена применена на `TurnEnded`, замена `/mcp reload` — до ответа

#### Scenario: WebSocket без /config
- **WHEN** ядро собрано с `ConfigSource` и `configCommand: false`, и приходит `/config check`
- **THEN** команды `config` в списке нет, промпт уходит модели как текст, перезагрузка по сигналу `changes` работает

#### Scenario: Без источника конфига
- **WHEN** ядро собрано без `ConfigSource`, и приходит `/config reload`
- **THEN** команды `config` в списке нет, промпт уходит модели как текст

