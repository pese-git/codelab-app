## MODIFIED Requirements

### Requirement: session/new
`session/new` SHALL выполнять алгоритм §13.4:
1. `cwd` не абсолютный → `-32602`; при локальном листинге несуществующий каталог → `-32602` (design.md change `add-dart-agent-acp-server`, D5).
2. `mcpServers` декодируются и отображаются в `McpServerConfig` с `origin: session` (design.md change `add-agent-mcp-client`, D11):
   - сервер `sse` пропускается с логом `mcp.server.skipped` и причиной `transport sse is not supported`;
   - сервер `http`, чей `url` не разбирается (`Uri.tryParse` → `null`), пропускается с логом `mcp.server.skipped` и причиной `invalid url`;
   - сервер неизвестного `type` (вариант `McpServer.unknown`) пропускается с логом `mcp.server.skipped` и причиной `unknown transport`;
   - `mcp.server.skipped` адаптера SHALL нести `session_id`, а строки клиента `type` и `name` в нём SHALL обрезаться до 64 символов по рунам;
   - остальные правила (capability, транспорт профиля, дубликаты, коллизии имён) применяет ядро;
   - сбой или пропуск сервера НЕ SHALL быть ошибкой запроса.
3. Сессия создаётся через `AgentRuntime.createSession` с env и `AcpPermissionGate` соединения, хуком `markInProgress` и серверами шага 2. Создание ждёт подключения серверов (параллельно, каждый — не дольше своего `connectTimeout`).
4. Ответ `NewSessionResponse(sessionId, modes, configOptions)`.
5. После ответа — `available_commands_update` с командами `AgentSession.commands` в их порядке: сначала встроенные команды сессии (`config`, `mcp` — capability `agent-slash-commands`, «Встроенные команды config и mcp»), затем шаблоны. Элемент — `AvailableCommand {name, description, input: {hint}?}`, поле `input` — только при `inputHint` (`14-Slash Commands.md`; design.md change `add-agent-project-files`, D9; design.md change `add-config-writer-and-reload`, D12). Без команд список пуст. Инструменты модели в список НЕ SHALL попадать (R-07).

До ответа на `session/new` уведомления этой сессии НЕ SHALL отправляться (ACP-8). Инструменты подключённых серверов SHALL быть доступны модели с первого хода этой сессии (R-24). Это заменяет поведение этапа 4, в котором каждый сервер пропускался (R-02).

#### Scenario: Режимы и опции новой сессии
- **WHEN** клиент создаёт сессию с абсолютным `cwd`
- **THEN** ответ содержит `modes` с пятью режимами и `configOptions` `mode` и `model`, а следующий кадр — `available_commands_update`; если у сессии нет ни шаблонов команд, ни встроенных команд (ядро без `ConfigSource` и без capability `mcp`), список пуст

#### Scenario: Относительный cwd
- **WHEN** `session/new` приходит с `cwd: "work/demo"`
- **THEN** ответ — `-32602`, сессия не создана

#### Scenario: Инструмент сервера доступен модели
- **WHEN** `session/new` содержит stdio-сервер `fake` эпохи modern и stdio-сервер `old` эпохи legacy, оба с инструментом `echo`, затем клиент присылает `session/prompt`
- **THEN** первый запрос к модели содержит схемы `mcp__fake__echo` и `mcp__old__echo` (фикстура `acp/session-new-with-mcp`, R-24)

#### Scenario: Сервер без общей версии протокола
- **WHEN** `session/new` содержит сервер, который на `server/discover` отвечает `-32022` без `2026-07-28` в `data.supported`
- **THEN** ответ `session/new` успешен, сервер пропущен с `mcp.server.failed` и списком его версий, остальные серверы подключены

#### Scenario: Сервер неподдерживаемого типа
- **WHEN** `session/new` содержит HTTP-сервер `web` и сервер `legacy` типа `sse`
- **THEN** ответ содержит `sessionId`, `legacy` пропущен с `mcp.server.skipped`, инструменты `web` доступны модели (фикстура `acp/mcp-http-tool-call`, E-03)

#### Scenario: Неразбираемый url HTTP-сервера
- **WHEN** `session/new` содержит сервер `type: "http"` с `url`, который `Uri.tryParse` не разбирает, и stdio-сервер `fake`
- **THEN** ответ успешен, первый сервер пропущен с `mcp.server.skipped` и причиной `invalid url`, `fake` подключён

#### Scenario: Сервер не подключился
- **WHEN** процесс stdio-сервера из `mcpServers` не запускается
- **THEN** ответ `session/new` успешен, лог `mcp.server.failed`, инструментов сервера в сессии нет

#### Scenario: Команды шаблонов после session/new
- **WHEN** у сессии есть встроенные инструменты, fake MCP-сервер с инструментом `echo` и шаблон `.codelab/prompts/review.md` доверенного проекта (`trusted_projects` с `${cwd}`) с `argument-hint: "<path> [focus]"`, а ядро собрано без `ConfigSource`
- **THEN** кадр после ответа `session/new` — `available_commands_update` ровно с двумя командами: `mcp` (встроенная, capability `mcp` включена) и `{"name":"review","description":…,"input":{"hint":"<path> [focus]"}}`, без имён `read`, `exec` и `mcp__fake__echo` (фикстура `acp/available-commands-no-tools`, R-07)

Шаблон лежит в проекте, а не в `$CODELAB_HOME/prompts/`: формат фикстур пишет файлы только в `cwd` через `setup.files` (acp-golden-fixtures). Пользовательскую область (`$CODELAB_HOME/prompts/*.md`) покрывает тест хоста `apps/codelab_agent/test/agent_host_project_files_test.dart`.

## ADDED Requirements

### Requirement: Уведомления после перезагрузки конфигурации
Событие сессии `ModelOptionsChanged` (capability `agent-runtime`, «Живая перезагрузка конфигурации») адаптер SHALL отображать в `config_option_update` с полным снимком опций сессии (`13-Session Config Options.md`; design.md change `add-config-writer-and-reload`, D8). `switch` проекции событий SHALL оставаться исчерпывающим.

Правила отправки:
- **Порядок.** Уведомление НЕ SHALL отправляться сессии до ответа на её `session/new` или `session/load` (ACP-8).
- **Неудача.** Неудачная перезагрузка НЕ SHALL порождать ни одного кадра.
- **Ход.** Во время хода уведомление SHALL идти в общем порядке событий сессии.
- **Опция `model`.** Текущее значение — модель сессии, даже если её больше нет в каталоге: такая модель SHALL оставаться в `options`.

Ответ встроенной команды SHALL уходить кадрами `agent_message_chunk` с текстом и ответом `session/prompt` со `stopReason: end_turn` (или `cancelled`), без `tool_call`, `plan` и `usage_update`. Новых методов, полей и `_meta` адаптер НЕ SHALL вводить.

#### Scenario: Список моделей изменился
- **WHEN** у соединения две живые сессии, и перезагрузка добавляет модель в каталог
- **THEN** каждая сессия получает ровно одно `config_option_update`, опция `model` содержит новую модель, `currentValue` сессии прежний (`config_reload_notifications_test.dart`)

#### Scenario: Неудачная перезагрузка
- **WHEN** перезагрузка завершается итогом `failed`
- **THEN** клиент не получает ни одного кадра

#### Scenario: Модель сессии удалена
- **WHEN** перезагрузка удаляет из каталога текущую модель сессии
- **THEN** `config_option_update` содержит её как `currentValue` и в `options`, следующий ход идёт на неё

#### Scenario: Ответ встроенной команды
- **WHEN** клиент присылает `session/prompt` с текстом `/mcp list`
- **THEN** кадры — `agent_message_chunk` с таблицей, затем ответ `{"stopReason":"end_turn"}`
