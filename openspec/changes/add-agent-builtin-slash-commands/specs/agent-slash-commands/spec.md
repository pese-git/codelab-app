## ADDED Requirements

### Requirement: Встроенные команды MVP
`AgentSession` SHALL объявлять и исполнять встроенные команды `compact`, `mode`, `model`, `status` и `help` (`agent-core-architecture` §13.4, §13.6; design.md change `add-agent-builtin-slash-commands`, D1–D7). Команда распознаётся по тем же правилам, что `/config` и `/mcp`: первый символ первого текстового блока — `/`, слово до первого пробельного символа или конца блока — имя, остаток после ведущих пробелов без завершающего `\r?\n` — аргумент `raw`. Общие правила требования «Встроенные команды config и mcp» — события хода без шагов модели, отказ команды (`AgentError` класса `hook`), журнал (ни промпт, ни ответ не пишутся), слот хода, отмена, доставка событий до возврата `prompt` и обрезка строк пользователя до 64 символов по рунам — SHALL действовать и для этих команд. Тексты ответов — фиксированные английские строки ниже; строки соединяются `\n`, после последней `\n` нет.

**Объявление** (элементы — `agent-core-architecture` §13.4):
- `compact` — `{"name":"compact","description":"Compact the session history","input":{"hint":"[focus]"}}`, только при включённой capability `compaction` профиля;
- `mode` — `{"name":"mode","description":"Switch the session mode","input":{"hint":"plan | ask | standard | accept-edits | bypass"}}`;
- `model` — `{"name":"model","description":"Switch the model","input":{"hint":"provider/model"}}`;
- `status` — `{"name":"status","description":"Show the model, mode, working directory and MCP servers"}`;
- `help` — `{"name":"help","description":"List commands"}`.

**`/compact [focus]`** — ручное сжатие с триггером `manual` (capability `agent-compaction`, «Точки срабатывания сжатия»): непустой `raw` SHALL передаваться как `SummaryRequest.focus`, пустой — без `focus`. Команда SHALL ждать завершения фонового сжатия `afterTurn`, если оно идёт. Ответ:
- сжатие выполнено — `Compacted: <tokensBefore> → <tokensAfter> tokens.` (`→` — U+2192; `agent-core-architecture` §13.7); запись `compaction` пишется в журнал по правилам `agent-compaction`, сама команда — нет;
- `NothingToCompact` — `Nothing to compact.`;
- `CompactionFailed` — событие `AgentError` класса `compaction` без `retrying`, затем `TurnEnded` с `failed`, без сообщения агента; журнал не меняется (CMP-3);
- отмена во время генерации резюме — `TurnEnded` с `cancelled` без сообщения агента, записи `compaction` нет.

**`/mode [<id>]`**:
- `<id>` — режим таблицы `agent-core-architecture` §13.6 или его устаревший синоним; синоним нормализуется, `autopilot` режимом сессии не является (§10.5). Команда SHALL вызывать `AgentSession.setMode` — тот же путь, что `session/set_config_option` с `configId: "mode"`: запись `mode_change` и событие `ModeChanged`, — затем отвечать `Mode: <id>.` с основным id;
- без аргумента — `Mode: <текущий id>. Available: plan, ask, standard, accept-edits, bypass.`;
- неизвестный `<id>` — `Unknown mode: <id>. Available: plan, ask, standard, accept-edits, bypass.`, режим не меняется.

**`/model [<provider/model>]`**:
- модель есть в `ModelCatalog` — `AgentSession.setModel` (запись `model_change`, событие `ConfigOptionChanged` с полным снимком опций, правила `effort` §13.6), затем ответ `Model: <provider/model>.`;
- без аргумента — `Model: <текущая модель>. Run /model <provider/model> to switch.`;
- модели нет в каталоге или аргумент начинается с `--` (форма `--role` — после MVP, §17.10.5) — `Unknown model: <аргумент>. Run /status to see the current model.`, модель не меняется.

**`/status`** — строки по порядку:
- `Model: <provider/model>`;
- `Mode: <id>`;
- `Working directory: <cwd сессии>`;
- `MCP servers: none` без серверов, иначе `MCP servers: <id> (<state>), …` в порядке `McpSessionTools.servers`;
- только если в сессии объявлена команда `config`: `Config: ok`, либо при непустом `ConfigStatus.lastIssues` — `Config: reload failed at <lastFailureAt в ISO 8601 UTC> (1 issue). Run /config check.` при одной проблеме и `(<n> issues)` при нескольких; затем при непустом `pendingRestartKeys` — `Restart required: <k1>, <k2>`.
Аргументы `/status` игнорируются.

**`/help`** — первая строка `Commands:`, затем по строке на каждую команду `AgentSession.commands` в её порядке: `/<name>` и, при `inputHint`, пробел и подсказка, затем ` - ` и описание; у команды шаблона в конце ` (template)` (`agent-core-architecture` §17.2.9). Аргументы `/help` игнорируются.

Команды `mode` и `model` меняют состояние сессии, поэтому их записи `mode_change` и `model_change` SHALL попадать в журнал и восстанавливаться `session/load`, как после `session/set_config_option`; текст промпта и ответ команды в журнал НЕ SHALL попадать.

#### Scenario: /compact с указанием
- **WHEN** в сессии достаточно истории для среза, и приходит `/compact API changes`
- **THEN** запрос к суммаризатору содержит блок `<focus>` с `API changes`, в журнале новая запись `compaction`, ответ — одно сообщение `Compacted: <X> → <Y> tokens.` с `X > Y`, `TurnEnded` с `endTurn`; записи с текстом `/compact` в журнале нет (`acp/slash-compact`, K-02)

#### Scenario: Нечего сжимать
- **WHEN** в новой сессии без истории приходит `/compact`
- **THEN** ответ — ровно `Nothing to compact.`, суммаризатор не вызван, журнал без новых записей

#### Scenario: Отмена /compact
- **WHEN** во время генерации резюме по `/compact` приходит `session/cancel`
- **THEN** `TurnEnded` с `cancelled` без сообщения агента, записи `compaction` нет, слот хода свободен

#### Scenario: /mode plan
- **WHEN** сессия в режиме `standard`, и приходит `/mode plan`
- **THEN** события хода — `ModeChanged(plan)`, затем сообщение `Mode: plan.`, затем `TurnEnded` с `endTurn`; в журнале запись `mode_change` и нет записи с текстом `/mode plan`; модель не вызвана (`acp/slash-mode-plan`, R-08)

#### Scenario: Неизвестный режим
- **WHEN** приходит `/mode autopilot` или `/mode turbo`
- **THEN** ответ — `Unknown mode: <аргумент>. Available: plan, ask, standard, accept-edits, bypass.`, режим и журнал не изменились

#### Scenario: Неизвестная модель
- **WHEN** в каталоге нет `x/y`, и приходит `/model x/y`
- **THEN** ответ — `Unknown model: x/y. Run /status to see the current model.`, `ConfigOptionChanged` нет

#### Scenario: /help перечисляет команды
- **WHEN** у сессии объявлены встроенные команды и шаблон `review` с `argument-hint: "<path> [focus]"`, и приходит `/help`
- **THEN** ответ начинается строкой `Commands:`, строки команд идут в порядке `AgentSession.commands`, строка шаблона — `/review <path> [focus] - <описание> (template)`, модель не вызвана (`acp/slash-help`, R-08)

#### Scenario: /status без конфига
- **WHEN** ядро собрано без `ConfigSource`, у сессии нет MCP-серверов, и приходит `/status`
- **THEN** ответ — ровно четыре строки `Model: …`, `Mode: …`, `Working directory: <cwd>`, `MCP servers: none`; строк `Config` и `Restart required` нет

#### Scenario: Состояние mode и model переживает session/load
- **WHEN** после `/mode plan` и `/model <другая модель>` сессия загружается в новом соединении
- **THEN** текущий режим — `plan`, текущая модель — выбранная; реплей не содержит `user_message_chunk` с текстами `/mode plan` и `/model …`

### Requirement: Неизвестная команда
Если первый текстовый блок промпта начинается с `/`, слово до первого пробельного символа соответствует `^[A-Za-z0-9][A-Za-z0-9:_-]*$`, но не является ни объявленной в сессии встроенной командой, ни именем шаблона, `AgentSession.prompt` НЕ SHALL отправлять промпт модели и SHALL отвечать без модели одним сообщением агента `Unknown command: /<name>. Run /help to list commands.` (`agent-core-architecture` §13.6, правило 3; §17.2.6, шаг 7; R-08); `<name>` обрезается до 64 символов по рунам. Ход — по общим правилам встроенных команд: `TurnEnded` с `endTurn`, ни промпт, ни ответ в журнал не пишутся, слот хода занят на время ответа. Лог — `command.unknown {session_id, name_bytes}` (info), без имени и аргументов: имя пришло от пользователя (`AGENTS.md` §16).

Слово, которое не соответствует регулярному выражению (`/usr/bin/foo`), и блок с ведущим пробелом командой не являются и уходят модели без изменений (требование «Разворачивание команды»). Имя MCP prompt (`<server>:<prompt>`) в этой версии неизвестная команда: MCP prompts — вне этой спецификации (строка матрицы E-24).

#### Scenario: Неизвестная команда не уходит модели
- **WHEN** шаблонов `nope` нет, и приходит `/nope x`
- **THEN** ответ — ровно `Unknown command: /nope. Run /help to list commands.`, `TurnEnded` с `endTurn`, scripted-модель не получила запросов, журнал без новых записей (R-08)

#### Scenario: Путь — не команда
- **WHEN** приходит `/usr/bin/foo is broken`
- **THEN** модель получает текст без изменений

#### Scenario: Длинное имя обрезается
- **WHEN** приходит `/` и имя из 100 символов `a`
- **THEN** ответ содержит `/` и ровно 64 символа `a`, лог `command.unknown` не содержит имени

## MODIFIED Requirements

### Requirement: Список команд сессии
`AgentSession.commands` SHALL возвращать сначала встроенные команды сессии (требования «Встроенные команды MVP» и «Встроенные команды config и mcp») в порядке §13.4 — `compact`, `mode`, `model`, `status`, `config`, `mcp`, `help`; отсутствующая команда пропускается, порядок остальных не меняется (design.md change `add-agent-builtin-slash-commands`, D2), — затем команды шаблонов `SlashCommand {name, description, inputHint, source: template}` в байтовом порядке имён. `inputHint` шаблона SHALL быть `argument-hint`, иначе `"arguments"`, если тело содержит `$ARGUMENTS` или `$1`…`$9`, иначе `null`. Список строится при открытии сессии и НЕ SHALL меняться до её закрытия, в том числе при перезагрузке конфигурации (design.md change `add-config-writer-and-reload`, D9). Инструменты модели в список НЕ SHALL попадать (R-07).

#### Scenario: Подсказка ввода
- **WHEN** у `review.md` нет `argument-hint`, а тело содержит `$1`, у `test.md` нет ни подсказки, ни плейсхолдеров
- **THEN** у `review` `inputHint == "arguments"`, у `test` — `null`

#### Scenario: Встроенные команды идут первыми
- **WHEN** ядро собрано с `ConfigSource`, capability `compaction` и capability `mcp`, а у сессии есть шаблон `review`
- **THEN** список — `compact`, `mode`, `model`, `status`, `config`, `mcp`, `help`, `review`

#### Scenario: Без capability compaction и без конфига
- **WHEN** ядро собрано без `ConfigSource`, с выключенными capability `compaction` и `mcp`, шаблонов нет
- **THEN** список — `mode`, `model`, `status`, `help`

#### Scenario: Перезагрузка не меняет список
- **WHEN** после открытия сессии перезагрузка добавляет проект в `trusted_projects`, и у проекта есть `.codelab/prompts/fix.md`
- **THEN** список живой сессии не изменился; новая сессия того же `cwd` тоже без `fix` до перезапуска (доверие закреплено, R0-1); `/config reload` отвечает строкой `Restart required: trusted_projects`

### Requirement: Разворачивание команды
`AgentSession.prompt` SHALL разбирать только первый текстовый блок промпта. Если блок начинается с `/`, а слово до первого пробельного символа соответствует `^[A-Za-z0-9][A-Za-z0-9:_-]*$` и совпадает с именем шаблона, тело шаблона с подставленными аргументами SHALL заменить этот блок; остальные блоки идут после него в исходном порядке. Встроенная команда с тем же именем проверяется раньше шаблона, но шаблон с именем встроенной команды не загружается (требование «Резервные имена команд»). Слово, которое соответствует выражению, но не является ни встроенной командой, ни шаблоном, — неизвестная команда (требование «Неизвестная команда»). Если блок не начинается с `/` или слово не соответствует выражению, промпт SHALL уходить модели без изменений.

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
- **WHEN** промпт — `/usr/bin/foo is broken`
- **THEN** модель получает текст без изменений

#### Scenario: Слово команды без шаблона
- **WHEN** промпт — `/nope x`, а шаблона `nope` нет
- **THEN** модель не вызвана, ответ — `Unknown command: /nope. Run /help to list commands.` (требование «Неизвестная команда»)

#### Scenario: Наблюдаемость
- **WHEN** разворачивается `/review secret-token-123`
- **THEN** лог `command.expanded` содержит `name: review`, `source: template`, `args_bytes` и не содержит `secret-token-123`

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

Необъявленная команда (`/config` без `ConfigSource` или при `configCommand: false`, `/mcp` без capability `mcp`) SHALL обрабатываться как неизвестная: ответ `Unknown command: /<name>. Run /help to list commands.` без модели (требование «Неизвестная команда»; design.md change `add-agent-builtin-slash-commands`, D4). Ответ не раскрывает ни путей, ни текстов проблем конфига, поэтому правило R0-3 сохраняется.

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
- **THEN** команды `config` в списке нет, ответ — `Unknown command: /config. Run /help to list commands.`, модель не вызвана, перезагрузка по сигналу `changes` работает

#### Scenario: Без источника конфига
- **WHEN** ядро собрано без `ConfigSource`, и приходит `/config reload`
- **THEN** команды `config` в списке нет, ответ — `Unknown command: /config. Run /help to list commands.`, модель не вызвана
