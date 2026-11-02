## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Встроенные команды config и mcp
Если первый текстовый блок промпта — `/config` или `/mcp` (слово до первого пробельного символа или до конца блока) и команда объявлена в сессии, `AgentSession.prompt` SHALL исполнять её без модели (design.md change `add-config-writer-and-reload`, D12; `agent-core-architecture` §17.5.6, §17.5.7):
- **События.** `TurnStarted`, ответ одним сообщением агента (`MessageStarted`, `MessageDelta`, `MessageEnded`), `TurnEnded` с `endTurn`. Шагов и запросов к модели нет.
- **Журнал.** Ни промпт, ни ответ НЕ SHALL записываться в журнал сессии (CFG-18).
- **Тексты** — фиксированные английские, побайтово по §17.5.6 и §17.5.7. Строки, пришедшие от пользователя (`<id>`, неизвестный аргумент), SHALL обрезаться до 64 символов по рунам; строки проблем конфига (`ConfigIssue.toString()`) НЕ SHALL обрезаться.
- **Наблюдаемость.** Лог `command.builtin {session_id, name, subcommand}` без аргументов.

**Объявление:**
- `config` — `{"name":"config","description":"Reload or check the agent config","input":{"hint":"reload | check"}}`, только если ядру передан `ConfigSource` и `buildAgentCore` вызван с `configCommand: true` (по умолчанию). Хост `serve --ws` SHALL передавать `configCommand: false` (R0-3): ответ раскрывал бы пути и тексты проблем конфига машины агента клиенту по сети;
- `mcp` — `{"name":"mcp","description":"List, reload, enable or disable MCP servers","input":{"hint":"list | reload [<id>] | enable <id> | disable <id>"}}`, только при включённой capability `mcp`.

Необъявленная команда (`/config` без `ConfigSource` или при `configCommand: false`) и `/x` для любого другого `x` без шаблона SHALL уходить модели без изменений, как прежде.

**`/config`:**
- `reload` — `reloadConfig()` и строка итога: `Config reloaded: <n> keys changed.`, `Config unchanged.` или `Config reload failed (<n> issues). Current settings kept. Run /config check.`; при отложенных ключах — строка `Restart required: <keys>`;
- `check` — загрузка без применения: первая строка ровно `Config: valid` или `Config: invalid (issues: <n>)` — та же строка, что итог `config check` CLI, затем по строке на проблему `- ` + `ConfigIssue.toString()`, то есть `- <source>[:<line>:<column>]: <key>: <message>` (без `<key>: ` при пустом ключе; формат `config check`), затем `Sources: …` и при наличии `Restart required: …`;
- иначе — `Usage: /config reload | /config check`.

**`/mcp`:**
- `list` (и без аргумента) — таблица §17.5.7 в блоке ```` ```text ```` (колонки `ID`, `SOURCE`, `TRANSPORT`, `STATE`, `TOOLS`, `LAST ERROR`, выравнивание пробелами по самой длинной ячейке плюс два пробела, у `failed` — суффикс ` (retry in <n>s)`); без серверов — `No MCP servers.`;
- `reload` — `reloadConfig()`, затем немедленная попытка подключения всех серверов в `failed`, затем строка итога перезагрузки (при ошибке — `Config reload failed (<n> issues); MCP servers unchanged. Run /config check.`) и таблица;
- `reload <id>` — `reconnect(id)` без перечитывания конфига, затем таблица;
- `enable <id>`, `disable <id>` — `setEnabled` только в этой сессии и в памяти, затем таблица; после `session/load` действует конфиг. `<id>` SHALL искаться только среди серверов применённого снимка: новый сервер, отложенный до перезапуска, — `Unknown MCP server`, у отложенного изменённого включается прежний вариант;
- неизвестный `<id>` — `Unknown MCP server: <id>. Run /mcp list.`;
- иначе — `Usage: /mcp list | /mcp reload [<id>] | /mcp enable <id> | /mcp disable <id>`.

**Слот хода и ход модели** (design.md, D12):
- встроенная команда SHALL занимать слот хода сессии так же, как ход модели: второй `AgentSession.prompt` той же сессии во время команды SHALL отклоняться тем же путём, что во время хода модели. Правило держит `AgentSession`, поэтому оно действует и вне моста ACP (встроенный агент, `codelab`);
- встроенная команда — не ход модели: отсрочку замены серверов конфига до `TurnEnded` она НЕ SHALL вызывать, и замена, вызванная ею, SHALL применяться до ответа.

`session/cancel` во время команды SHALL завершать её `TurnEnded` с `cancelled` без текста и освобождать слот; начатая перезагрузка доводится до конца.

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

#### Scenario: enable отложенного сервера
- **WHEN** перезагрузка добавила stdio-сервер `x` (отложен), а у stdio-сервера `y` изменила `command` (отложено), и `y` выключен командой; приходят `/mcp enable x` и `/mcp enable y`
- **THEN** первая — `Unknown MCP server: x. Run /mcp list.`; вторая подключает `y` с прежними `command` и `env`

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
