## Why

Dart-агент принимает `mcpServers` в `session/new` и `session/load`, но с этапа 4 только пропускает их с логом `mcp.server.skipped` (R-02), а в `initialize` объявляет `mcpCapabilities.http: false`. Это прямое отклонение от ACP: спецификация требует, чтобы каждый агент подключал MCP-серверы по stdio (`docs/protocols/acp/protocol/03-Session Setup.md`, «MCP Servers»; отклонение записано в §13.15 документа ядра). Пока MCP нет, внешние инструменты недоступны модели, а Must-строки матрицы P-01, P-16, E-02, E-03, E-05 и R-24 остаются красными.

Этап 8 (`docs/architecture/proposals/dart-agent-and-clients/09-13-stage-8-mcp-config.md`) закрывает это задачами 8.1–8.4: свой MCP-клиент, stdio- и streamable HTTP-транспорты, проекция MCP-инструментов в общий реестр, подключение серверов из ACP. Главное требование безопасности — MCP-инструмент проходит ту же точку исполнения и ту же политику разрешений, что встроенный, а его результат всегда огорожен как недоверенный (P-01, P-16; agent-core-architecture §6.3.1, §6.3.6, §6.4).

## What Changes

- **Решение о библиотеке MCP (D1).** Чек-лист плана заполнен по `dart_mcp` 0.5.2, `mcp_dart` 2.4.3 и девяти менее зрелым пакетам; у каждого есть хотя бы одно «нет». Пишется свой минимальный клиент; сторонний код не копируется (`AGENTS.md` §5).
- **Новый пакет `packages/dart/codelab_agent_mcp` (8.1).** Без `dart:io`, web-безопасный. Содержит:
  - свой минимальный кодек JSON-RPC 2.0 и модели MCP по нормативной спецификации `docs/protocols/mcp/specification/` (modern `2026-07-28`) и `docs/protocols/mcp/specification/2025-11-25/` (legacy);
  - `McpClient` — соединение с одним сервером, **клиент dual-era** (D2):
    - modern `2026-07-28` предпочтителен: без рукопожатия, `_meta` протокола в каждом запросе, `server/discover`, `subscriptions/listen` для `tools/list_changed`;
    - legacy-ветка `initialize` + `notifications/initialized` для серверов `2025-11-25`, `2025-06-18`, `2025-03-26`;
    - эпоха определяется пробой `server/discover` по `basic/versioning.md` и кэшируется;
    - несовместимая версия — сервер пропускается с диагностикой, сессия создаётся;
  - `tools/list` с пагинацией, `tools/call`, `notifications/tools/list_changed`; отмена по транспорту (stdio — `notifications/cancelled`, modern HTTP — закрытие потока ответа); таймауты; ответ на legacy-`ping`;
  - транспорт streamable HTTP на внедрённом `http.Client` (`MockClient` в тестах);
  - `McpClientConnector` — реализация порта ядра на сессию;
  - `lib/testing.dart` с собственным fake-сервером `FakeMcpServer` для тестов и фикстур.
- **Порты MCP в ядре.** Новый каталог `codelab_agent_core/lib/src/mcp/`:
  - `McpServerConfig` (stdio | http);
  - порт транспорта `McpTransport` / `McpTransportFactory`;
  - порт `McpConnector` с объектом сессии `McpSessionTools`;
  - правило имён `mcpToolName` (SHA-256 из `crypto` — пакет уже в allowlist ядра, PKG-2).

  `AgentCoreServices.mcp: McpConnector?`. Capability `mcp` в `HostProfile`: transport `{stdio, http}` в `agent-serve` и `embedded-cli`. Реестр инструментов собирается на сессию: базовые инструменты плюс MCP-инструменты её серверов. Секция промпта `mcp`. Обновление по `tools/list_changed` применяется на границе шага.
- **stdio-транспорт MCP (8.2)** — `codelab_agent_io/lib/src/mcp/stdio_process_transport.dart`. Процесс получает базовое окружение §4.5 и `env` сервера, родительское окружение не наследует (ENV-6). Кадры — строки NDJSON с лимитом длины, stderr дренируется. При закрытии сессии: закрыть stdin, затем `SIGTERM` дереву процессов, затем `SIGKILL`.
- **Проекция в инструменты (8.3)** — `McpTool` (`AgentTool`):
  - имя `mcp__<сервер>__<инструмент>`: замена символов на `_`; длиннее 64 — первые 56 символов, `_` и 7 hex SHA-256 полного имени;
  - коллизия имени отключает сервер с причиной, называющей оба источника, а сессия создаётся (HOST-5);
  - `kind` — по аннотациям, `tier` — всегда `exec`; аннотациям не доверяем;
  - результат всегда `untrusted` и в одной ограде; точка исполнения огораживает каждый `mcp__*` независимо от `outputTrust`;
  - описание инструмента передаётся модели как есть, но не длиннее 2048 символов с пометкой об обрезке;
  - проекция содержимого `text`, `image`, `audio`, `resource`, `resource_link`;
  - отмена хода доходит до сервера сигналом своего транспорта; таймаут `tools/call` — константа 10 минут; после обрыва потока повторяются только `tools/list` и `server/discover`, `tools/call` — никогда; таймаут, сбой сервера и ошибка JSON-RPC дают результат-ошибку, а не падение хода.
- **ACP (8.4).**
  - `session/new` и `session/load` передают `mcpServers` в сессию (R-24). **Изменение поведения R-02:** серверы больше не пропускаются; `mcp.server.skipped` остаётся только для неподдерживаемого транспорта (`sse` везде, транспорт вне capability профиля), **неизвестного `type`** (`reason: unknown transport`) и неверных описаний; сессия создаётся. Для неизвестного `type` модель `codelab_acp_protocol` получает вариант `McpServer.unknown` — сейчас такой сервер роняет весь `session/new` с `-32602`.
  - `initialize` объявляет `mcpCapabilities.http: true` при capability `mcp` с транспортом `http`; `sse` по-прежнему `false`. Флага stdio в ACP нет: stdio обязателен для всех агентов.
  - Повторный `session/load` открытой сессии применяет новый набор серверов на границе хода.
- **Бинарь `codelab-agent`** подключает `McpClientConnector` со stdio-транспортом из `codelab_agent_io` и streamable HTTP на HTTP-клиенте хоста.
- **Фикстуры и тесты DoD.**
  - Фикстуры `acp/session-new-with-mcp`, `acp/mcp-tool-permission`, `acp/mcp-stdio-tool-call`, `acp/mcp-http-tool-call`, `acp/mcp-result-fenced`, `acp/set-mode-plan-rejects-mcp-write`. Формат фикстуры получает `setup.mcp` и `after.mcpCalls`. Ожидаемый кадр `acp/initialize-capabilities` меняется на `mcpCapabilities.http: true`.
  - Тесты `mcp_tool_goes_through_policy_test.dart` и `streamable_http_test.dart` на `MockClient`.
  - e2e реального процесса stdio-сервера через бинарь.
- **Сторож.** Правило `codelab_agent_mcp` (webUnsafe + запрет ACP и клиентских пакетов) и allowlist `{codelab_agent_core, http, meta, async}`. `codelab_agent_mcp` добавляется в allowlist бинаря и в `workspace:`.

Не входит:
- конфигурация `mcp.servers` из YAML и правило доверия проекту — change `add-agent-configuration` (8.5). Здесь только поле `CoreConfig.mcpServers` и правило слияния «сервер клиента побеждает» (§13.4);
- переподключение, `McpSupervisor`, команда `/mcp`, живая перезагрузка (E-04, 8.10, Should);
- MCP prompts как slash-команды (`acp/mcp-prompt-command`, R-08) — change `add-project-instructions-and-commands`;
- редакция секретов и `addExactSecret` для токенов MCP (8.11, Should). Здесь значения `env` и `headers` только не попадают в логи и журнал;
- resources, prompts, sampling, roots, elicitation, logging, MRTR-ввод (`input_required` даёт результат-ошибку), расширения (tasks, apps), OAuth-авторизация MCP, deprecated HTTP+SSE и `2024-11-05`, возобновление GET-потока уведомлений legacy (возобновление прерванного потока ответа legacy `2025-11-25` по `Last-Event-ID` входит), перезапуск упавшего stdio-сервера;
- ключ конфигурации `mcp.servers.*.call_timeout` — change `add-agent-configuration` (8.5); здесь таймаут — константа 10 минут;
- окружение stdio-сервера на Windows (`SYSTEMROOT` и подобные): Windows не целевая платформа агента;
- автоматический повтор `tools/call` после обрыва потока (отступление от п. 9 `changelog.md` `2026-07-28` в пользу целостности данных);
- вынос огромного результата в файл: MCP-результат усекается по общему правилу до change `add-agent-core-output-spill`;
- клиентские изменения: клиенты CodeLab по-прежнему шлют пустой `mcpServers`, UI настройки MCP — этап 9+ (E-13). Задач `[client]` и `[desktop]` нет.

## Capabilities

### New Capabilities
- `agent-mcp-client`:
  - MCP-клиент Dart-агента: решение о библиотеке, кодек JSON-RPC, клиент dual-era (определение эпохи, версии, кэш);
  - транспорты stdio (окружение по allowlist, завершение процесса) и streamable HTTP;
  - `tools/list`, `tools/call`, `tools/list_changed`, отмена и таймауты;
  - проекция содержимого результата, наблюдаемость `mcp.*` без секретов, fake-сервер для тестов.

### Modified Capabilities
- `agent-acp-server`: «session/new» и «session/load и реплей» — `mcpServers` подключаются, а не пропускаются (R-24 вместо поведения R-02 этапа 4); набор серверов при повторной загрузке открытой сессии; новое требование «Неизвестный транспорт MCP-сервера» (вариант `McpServer.unknown` в `codelab_acp_protocol`, пропуск сервера вместо `-32602`).
- `agent-runtime`:
  - «Профили хостов и сужение» — capability `mcp`;
  - «Минимальная сборка buildAgentCore» — сервис `McpConnector`, сужение по транспортам, реестр на сессию;
  - новое требование «MCP-серверы сессии».
- `agent-tools`: новое требование «MCP-инструменты» (имена, коллизии, вид и уровень, исполнение); «Ограда недоверенного вывода» — MCP всегда огорожен одной оградой независимо от `outputTrust`.
- `agent-permissions`: новое требование «MCP-вызов только после решения политики» (P-01).
- `agent-prompts`: новое требование «Секция mcp».
- `acp-golden-fixtures`: «Формат golden-фикстуры ACP» — `setup.mcp` и `after.mcpCalls`; новое требование «MCP-фикстуры этапа 8».
- `workspace-architecture`: «Границы пакетов monorepo» и «Автоматический сторож границ пакетов» — пакет `codelab_agent_mcp`, его правило и allowlist, `codelab_agent_mcp` в allowlist бинаря.
- `agent-binary`: новое требование «MCP-серверы в бинаре».

## Impact

- **Новый пакет** `packages/dart/codelab_agent_mcp`:
  - `dependencies` — `codelab_agent_core`, `http`, `meta`, `async`;
  - dev — `test`, `lints`;
  - вложенный `AGENTS.md`.
- **`codelab_agent_core`**:
  - порты `lib/src/mcp/`, `HostCapability.mcp`, `AgentCoreServices.mcp`, `CoreConfig.mcpServers`, `SessionSpec.mcpServers`;
  - `AgentSession.setMcpServers` — набор серверов при повторном `session/load`;
  - реестр на сессию, правило ограды `mcp__*` в `ToolCallExecutor`, секция `prompts/mcp.md`;
  - экспорт `SseDecoder`;
  - новая зависимость `crypto` (уже в allowlist, PKG-2).
- **`codelab_agent_io`**: `lib/src/mcp/stdio_process_transport.dart` на существующем `process_tree.dart`; без новых зависимостей. dev — `codelab_agent_mcp`.
- **`codelab_agent_acp`**: отображение `acp.McpServer` → `McpServerConfig` (неизвестный `type` — пропуск), `mcpCapabilities.http` по плану ядра, `session/load` открытой сессии. Без новых зависимостей; dev — `codelab_agent_mcp`.
- **`apps/codelab_agent`**: зависимость `codelab_agent_mcp`, сборка `McpClientConnector`.
- **`codelab_acp_protocol`**: вариант `McpServer.unknown({type, name?, raw})` — неизвестный транспорт сервера разбирается, а не роняет запрос; известные типы проверяются строго, как раньше.
- **`codelab_acp_testing`**:
  - ключи `setup.mcp` и `after.mcpCalls` в `_schema.json` и загрузчике;
  - шесть новых фикстур;
  - правка ожидаемого кадра `acp/initialize-capabilities` со ссылкой `02-Initialization.md#mcp-capabilities`.
- **Сторож** `codelab_architecture_tests`: правило пакета в `rules.dart` (заменяет заготовку `// stage 8: codelab_agent_mcp — webUnsafe`), allowlist в `pubspec_allowlist_test.dart`.
- **Корень**: `workspace:` в `pubspec.yaml`.
- **ACP-контракт.** Новых методов, полей и расширений `_meta` нет. Меняются значение `mcpCapabilities.http`, поведение обработки `mcpServers` (определены спецификацией ACP) и допуск неизвестного `type` сервера (совместимость вперёд, `AGENTS.md` §7).
- **Документы:**
  - точечные правки `agent-core/01-layers-and-packages.md`, `06-tools.md` (§6.4), `10-core-assembly-and-profiles.md` (§10.3, §10.8), `11-prompts.md` (текст `mcp.md`), `12-observability-and-errors.md` (события `mcp.*`), `13-acp-adapter.md` (§13.4, §13.5, §13.15), `14-golden-fixtures.md`;
  - план этапа `09-13-stage-8-mcp-config.md` (порт транспорта, критерий E-05);
  - матрица `agent-parity-goals.md`;
  - нормативные спецификации MCP `2026-07-28` (`docs/protocols/mcp/specification/`) и legacy `2025-11-25` (`docs/protocols/mcp/specification/2025-11-25/`) уже в ветке; задача 0.1 — только сверка D2–D10 с ними.
