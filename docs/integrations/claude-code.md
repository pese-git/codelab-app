# Интеграция с Claude Code (через ACP)

Документ описывает, как CodeLab работает с агентом Claude Code по ACP и **чем фактическое поведение этого агента отличается от эталонного протокола ACP**.

* **Эталон (reference)** — вендоренный снапшот официальной спецификации в `docs/acp/protocol/` (схема — `17-Schema.md`). Это источник истины ACP для проекта (AGENTS.md §3.4).
* **Агент** — отдельный процесс, который CodeLab запускает по stdio. Claude Code напрямую ACP не говорит: его оборачивает ACP-совместимый адаптер.

Последняя проверка: 2026-10-09 (macOS, stdio). Снимок ответов агента, на котором основаны таблицы ниже, воспроизводится рецептом из раздела 7.

---

## 1. Какие агенты проверены

| Пакет (npm) | Версия | Статус |
|---|---|---|
| `@zed-industries/claude-code-acp` | 0.16.2 | **Устарел**, переименован в `@agentclientprotocol/claude-agent-acp` (npm: *deprecated*). Проверено: `initialize`, `session/new`, prompt turn (`stopReason endTurn`). |
| `@agentclientprotocol/claude-agent-acp` | 0.88.0 | Актуальный. Проверено: `initialize`, `session/new`, селекторы Mode / Model / Effort, prompt turn (`stopReason end_turn`, ответ доходит до таймлайна; см. 3.5). Сквозной прогон через UI CodeLab (2026-10-09): Connect → проект → `/new` → смена модели селектором → prompt → `Prompt completed with stopReason endTurn`, ошибок нет. |

Рекомендуется актуальный пакет: он объявляет настройки сессии через `configOptions` (разд. 3.3), и CodeLab показывает их селекторами в композере.

---

## 2. Как подключить

В диалоге подключения (**Configure connection**), транспорт **stdio**:

| Поле | Значение |
|---|---|
| Command | `/opt/homebrew/bin/npx` (абсолютный путь, см. примечание) |
| Args | `--yes @agentclientprotocol/claude-agent-acp` |

Затем **Close** → **Connect**, открыть проект, создать сессию (`/new`).

Условия, которые не относятся к протоколу, но без них подключение не работает:

1. **Переменная `CLAUDECODE` не должна быть задана** в окружении CodeLab. Агент отказывается запускаться «внутри другой сессии Claude Code» и отвечает на `session/new` ошибкой (см. 3.6). Это случается, если приложение запущено из терминала/IDE, где работает Claude Code. Запускайте приложение из обычного терминала либо через `env -u CLAUDECODE …`.
2. **PATH.** Агент — Node-скрипт (`#!/usr/bin/env node`). Приложение, запущенное двойным кликом, получает урезанный PATH: используйте абсолютные пути к `npx`/`node`.
3. **Авторизация.** `initialize` и создание сессии проходят без неё; для ответов модели нужны учётные данные Claude Code (логин через CLI `claude` либо `ANTHROPIC_API_KEY`). Prompt расходует лимиты аккаунта.

---

## 3. Отличия от эталонного ACP

Колонка «CodeLab» показывает, как мы это обрабатываем. Принцип один: **ничего не придумываем** — незнакомое поле или метод не интерпретируется, не сохраняется и не делает ответ невалидным (AGENTS.md §3.4).

### 3.1. `initialize` — capabilities вне эталона

В эталоне `SessionCapabilities` содержит только `list` (и `_meta`). Агент объявляет больше:

| Где | Поле | Версии | CodeLab |
|---|---|---|---|
| `agentCapabilities.sessionCapabilities` | `fork`, `resume` | 0.16.2, 0.88.0 | игнорируется |
| `agentCapabilities.sessionCapabilities` | `additionalDirectories`, `close`, `delete`, `subagents` | 0.88.0 | игнорируется |
| `agentCapabilities` | `auth: {logout}`, `providers` | 0.88.0 | игнорируется |
| `agentCapabilities._meta` | `claudeCode.promptQueueing`, `authStatus` | 0.88.0 | `_meta` — штатное поле эталона; его содержимое CodeLab не использует |

Совместимые с эталоном части (`loadSession`, `promptCapabilities.image/embeddedContext`, `mcpCapabilities.http/sse`, `agentInfo`, `authMethods`) читаются как обычно. Другие агенты вправе объявлять собственные флаги так же; поэтому неизвестные поля **не считаются ошибкой** (OpenSpec: `fix-acp-capability-forward-compat`, `tolerate-unknown-agent-response-fields`).

Поддержка самих `fork`/`resume`/`close`/`delete`/`subagents` в CodeLab **не реализована**.

### 3.2. `session/new` — `models` (только 0.16.2)

Агент 0.16.2 присылает в ответе корневое поле, которого нет в эталоне:

```json
"models": { "availableModels": [{ "modelId": "default", "name": "…", "description": "…" }],
            "currentModelId": "default" }
```

Эталонная модель `NewSessionResponse` знает только `sessionId`, `modes`, `configOptions`, `_meta`. Раньше это приводило к `unsupported root field "models"` и **невозможности создать сессию** (сессия на стороне агента уже существовала). Сейчас поле игнорируется; выбор модели через `models` не поддерживается — для этого используйте актуальный агент (3.3).

### 3.3. Настройки сессии: `modes` и `configOptions`

| Версия | `modes` | `configOptions` | Что видит пользователь |
|---|---|---|---|
| 0.16.2 | есть (`default`, `acceptEdits`, `plan`, `dontAsk`, `bypassPermissions`) | **нет** | селекторов нет |
| 0.88.0 | есть, и дублирует `mode` | `mode`, `model`, `effort` | три селектора |

`configOptions` 0.88.0 (id → категория): `mode` → `mode`, `model` → `model`, `effort` → `thought_level` («уровень усилия/интеллекта»; значения `default`, `low`, `medium`, `high`, `xhigh`, `max`). Категории входят в эталон (`13-Session Config Options.md`) — это **не** расхождение, а штатная семантика.

Расхождения в поведении CodeLab, которые из этого следуют:

* Когда в ответе есть и `modes`, и `configOptions`, CodeLab использует **только** `configOptions` (по эталону они взаимоисключающие; требование «Устаревший канал session modes не используется при наличии config options»).
* UI для одного лишь `modes` без `configOptions` **нет** — поэтому на 0.16.2 селекторов нет.

### 3.4. Нестандартные уведомления

Агент 0.88.0 шлёт `_auth/status_update` сразу после `initialize`. Имя с `_` — допустимое расширение по эталону (`15-Extensibility.md`: «Custom Notifications»). CodeLab такие уведомления **молча игнорирует** (`acp_client_application.dart`, ветка `JsonRpcNotification()`): на notification по JSON-RPC не отвечают.

Если агент пришлёт неподдерживаемый **запрос** (в том числе кастомный `_vendor/...`), CodeLab отвечает на него стандартной ошибкой `-32601 Method not found` с тем же `id` и пишет WARNING (только метод и `requestId`, без параметров). Так предписывает эталон (`15-Extensibility.md`, «Custom Requests»); агент не остаётся в ожидании ответа.

### 3.5. `session/update`

`available_commands_update` — штатный (`14-Slash Commands.md`), расхождений нет. В prompt turn на 0.88.0 агент присылает два нестандартных элемента:

| Что | Где | CodeLab |
|---|---|---|
| поле `messageId` | корень `update` у `agent_message_chunk` | игнорируется; текст чанка применяется как обычно |
| вид обновления `usage_update` (`used`, `size`, `cost`) | `update.sessionUpdate` | пропускается: состояние сессии не меняется, ошибки нет, в application-журнал пишется одна запись DEBUG (вид и `sessionId`, без содержимого); полный payload (секреты замаскированы) пишется отдельной записью с тем же текстом `Skipped unsupported ACP session update.` в журнал `category=protocol` — его видно в Debug log приложения, а в `protocol.log` он попадает при включённой трассировке. В release-журналы и на сервер логов payload не уходит |

Раньше оба случая отвергались строгой валидацией: текст ответа модели терялся с диагностикой `unsupported root field "messageId"` (OpenSpec: `tolerate-unknown-session-updates`). Поддержки `messageId` и индикатора использования контекста по `usage_update` в CodeLab **нет**: эти поля не входят в вендоренную спеку, семантику не придумываем.

### 3.6. Поведение вне протокола: отказ внутри другой сессии Claude Code

Если задана `CLAUDECODE`, `initialize` проходит, а `session/new` завершается ошибкой JSON-RPC:

```
-32603 Internal error, data.details: "Query closed before response received"
```

Настоящая причина приходит только в **stderr** агента (`Claude Code cannot be launched inside another Claude Code session… unset the CLAUDECODE environment variable`). CodeLab пишет stderr агента в лог уровнем INFO (`component=transport`, `source=stderr`) — искать причину нужно там, а не в тексте ошибки.

### 3.7. Служебные строки в stderr агента

Агент 0.88.0 пишет в stderr, помимо прогресса создания сессии (`[session/create] … phase=…`), строки `Unexpected case: {"type":"system","subtype":"dev_intent"|"post_turn_summary", …}`. Это внутренние служебные сообщения его SDK, не ошибки протокола и не сбой CodeLab. CodeLab пишет stderr агента в лог уровнем INFO (`component=transport`, `source=stderr`), как и остальное (см. 3.6). Реагировать на них не нужно.

### 3.8. Стоимость первого prompt

Даже короткий prompt без инструментов (`Reply with exactly the word: pong`) на 0.88.0 дал ~37,8 тыс. токенов контекста (практически все — запись в кэш, `cachedWriteTokens`; собственно ввод — 2 токена) и ~$0,76 по оценке агента (`cost` в `usage_update`). Вероятно, в контекст сессии попадают системные инструкции и окружение Claude Code пользователя (в `available_commands_update` приходят его команды и скиллы). Учитывайте это при ручных проверках и автоматизации: каждая новая сессия расходует лимиты аккаунта, а не только сам prompt.

---

## 4. Что CodeLab принимает строго, а что терпимо

| Что | Правило |
|---|---|
| `result` ответов агента (любая вложенность) | неизвестные корневые поля игнорируются |
| Структура ответа: не объект, нет обязательного поля, неверный тип, неизвестный discriminator | `invalidShape` — ответ отвергается |
| Параметры запросов, которые отправляет CodeLab | строго |
| Уведомление `session/update` (любая вложенность) | неизвестные корневые поля игнорируются; неизвестный вид обновления пропускается; структура известных видов проверяется строго |
| Запросы агента (`session/request_permission`, `fs/*`, `terminal/*`) | строго по эталону (на них нужен ответ, они относятся к безопасности) |

Терпимость реализована централизованно в `acp_protocol` (`decodeAcpResult` и `decodeAcpNotificationParams` для `session/update` → `tolerateUnknownRootFields`), а не в каждой модели; пропуск неизвестного вида обновления — `unsupportedSessionUpdateKind` в клиенте.

---

## 5. Известные ограничения

1. **Запросы агента (`session/request_permission`, `fs/*`, `terminal/*`) остаются строгими.** Агент, присылающий в них нестандартные поля, получит ошибку. Prompt turn без запросов агента проверен на 0.16.2 и 0.88.0; сценарий с запросом разрешения на 0.88.0 не прогонялся.
2. `models` (0.16.2), `fork`, `resume`, `close`, `delete`, `subagents`, `additionalDirectories` игнорируются — как функциональность не поддерживаются.
3. Нет UI для `modes` без `configOptions`.
4. Версии пакетов быстро меняются (0.16 → 0.88): при обновлении агента повторите проверку (разд. 7) и дополните таблицы.

---

## 6. Связанные материалы

* Эталон протокола: `docs/acp/protocol/` (особенно `02-Initialization.md`, `03-Session Setup.md`, `13-Session Config Options.md`, `15-Extensibility.md`, `17-Schema.md`).
* Граница ACP в архитектуре: `docs/architecture/acp-boundary.md`.
* OpenSpec: `fix-acp-capability-forward-compat`, `tolerate-unknown-agent-response-fields`, требования `acp-protocol-client` и `agent-workbench-ui`.

---

## 7. Как воспроизвести снимок ответов агента

Сырой обмен без модели и без расхода лимитов (нужен Node; `CLAUDECODE` снимается; при первом запуске `npx` скачивает пакет — увеличьте паузы `sleep`):

```bash
(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":false,"writeTextFile":false},"terminal":false},"clientInfo":{"name":"codelab","version":"0.1.0"}}}'; sleep 8; \
 printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"session/new","params":{"cwd":"/tmp","mcpServers":[]}}'; sleep 15) \
| env -u CLAUDECODE npx --yes @agentclientprotocol/claude-agent-acp
```

В выводе смотрите: ответ на `id:1` (`agentCapabilities`), ответ на `id:2` (`modes`, `configOptions`, нет ли новых корневых полей) и уведомления без `id` (`method`).
