# Backlog: находки smoke-теста встроенных команд `/config` и `/mcp` 2026-11-03

Smoke-тест сборки из `develop` @ `d4a79cf` после архивирования change `add-config-writer-and-reload` (итерация 7, D12;
PR [#229](https://github.com/pese-git/codelab-app/pull/229)). Бинари `codelab`, `codelab-agent` и fake MCP-серверы
(`apps/codelab_agent/test/support/fake_mcp_stdio_server.dart`, `fake_mcp_crashing_server.dart`) собраны
`fvm dart compile exe`. Всё запускалось с изолированным `CODELAB_HOME` и `secrets.backend: file`. Значение ключа
фиктивное, модель не вызывалась.

В конфиге пять MCP-серверов: `fs` и `crashy` (stdio, fake), `off` (`enabled: false`), `broken` (команды нет), `gh`
(HTTP, заголовок с незаданным `${secret:…}`).

Прогнаны:
- `codelab-agent serve --stdio` с клиентом на Python по ACP, одна сессия:
  - `available_commands_update` — `config`, `mcp`;
  - `/config check|reload|frob`, `/mcp`, `/mcp list|disable|enable|reload [<id>]|frob`, неизвестный id из 80 символов
    (обрезан до 64);
  - падение `crashy` по SIGUSR1 и переподключение;
  - правка `permissions.mode` — `Config reloaded: no keys applied now.` + `Restart required` (R7-1); правка
    `budget.max_steps` — `Config reloaded: 1 key changed.` (R7-2);
  - опечатка `compaction.reserve_token` — `Config: invalid (issues: 1)` с `did you mean`, `Config reload failed (1 issue)`,
    `/mcp reload` не будит серверы в `failed`;
  - все ответы — `end_turn`; выход `0` по закрытию stdin, процессов fake-серверов не осталось; ключа в stderr нет.
- REPL `codelab` (`--ui line`), ручной прогон пользователя: `/mcp list` (таблица блоком ```` ```text ````), `/mcp disable fs`,
  `/mcp reload` (ручное выключение держится, R6-2), `/agent:config check|reload`, клиентский `/config`
  (режим не меняется до перезапуска, R0-1), правки через `codelab config set` при работающем REPL.

Поведение агента совпало со спецификациями `agent-slash-commands`, `agent-mcp-client` и `agent-runtime`.

Не проверялись:
- `--ui tui` и палитра codelab-app;
- падение `crashy` и опечатка конфига в REPL (проверены по ACP);
- `serve --ws` (`/config` там не объявляется, R0-3; покрыто тестом `agent_host_ws_commands_test.dart`).

Приоритеты и колонки — как в [smoke-2026-10-30.md](smoke-2026-10-30.md).

## Сводка

| ID | P | Тип | Область | Кратко | OpenSpec | Issue |
|---|---|---|---|---|---|---|
| SMK-37 | P3 | ux | client | В истории REPL `/agent:config …` показан как `/config …` | нет | — |
| SMK-38 | P3 | bug | agent | У сервера `failed` после падения в `/mcp list` прежнее число инструментов | нет | — |
| SMK-39 | P3 | ux | agent | `codelab mcp add` печатает предупреждение о чужом выключенном сервере | нет | — |

## Карточки

### SMK-37. В истории REPL `/agent:config …` показан как `/config …` (P3)

**Где:** `apps/codelab_cli/lib/src/repl/command_router.dart` (`route`, ветка `/agent:<имя>` → `AgentPromptRoute('/<имя> …')`)
и `apps/codelab_cli/lib/src/repl/repl.dart` (`_submit`: `PromptRoute` и `AgentPromptRoute` не эхоируются, на экране
остаётся промпт, отправленный агенту).

**Шаги:** REPL `codelab` с агентом, объявляющим `config` → `/agent:config check` → `/config`.

**Факт:** в истории две строки `> /config check` и `> /config`. Первая получила ответ агента (`Config: valid …`), вторая —
клиентский список опций. По экрану не видно, какая команда выполнялась. Так же `/agent:config` без подкоманды выглядит как
`> /config` с ответом `Usage: /config reload | /config check`, будто клиентская команда ответила чужим текстом.

**Ожидание:** в истории остаётся введённая строка (`> /agent:config check`), а агенту уходит `/config check`. Либо
промпт агента помечается так же, как в slash-меню (`(agent)`).

**Риск:** нет. Путает при разборе стенограммы и при сообщении об ошибке.

### SMK-38. У сервера `failed` после падения в `/mcp list` прежнее число инструментов (P3)

**Где:** `packages/dart/codelab_agent_mcp/lib/src/connector.dart` (`McpServerSummary`, `toolCount` берётся из
`tools.length` для всех состояний, кроме `disabled`).

**Шаги:** сервер `crashy` подключён (2 инструмента) → процесс падает (`kill -USR1`) → `/mcp list`.

**Факт:** строка `crashy  config  stdio  failed  2  process exited (retry in 1s)`. У сервера, который не смог
подключиться (`broken`), в колонке `TOOLS` — `0`.

**Ожидание:** у `failed` в `TOOLS` — `0`: инструменты упавшего сервера недоступны модели до переподключения. Если
прежний набор держится намеренно (для границы шага, D11), таблица должна это показывать иначе, а не числом доступных
инструментов.

**Риск:** нет. Таблица говорит, что инструменты есть, хотя вызвать их нельзя.

### SMK-39. `codelab mcp add` печатает предупреждение о чужом выключенном сервере (P3)

**Где:** вывод предупреждений итога после записи (`packages/dart/codelab_agent_io/lib/src/cli/config_edit_runner.dart`,
`config_output.dart`); предупреждение — `packages/dart/codelab_agent_core/lib/src/config/resolve.dart`
(`the server is disabled in the config`).

**Шаги:** в конфиге есть сервер `off` с `enabled: false` → `codelab mcp add broken --type stdio --command …`.

**Факт:** после `Updated mcp.servers[broken] …` печатается `warning: mcp.servers[off]: the server is disabled in the
config`, и так после каждого `mcp add` другого сервера. `codelab config set permissions.mode …` и
`config set budget.max_steps …` этого предупреждения не печатали — похоже, вывод после записи показывает предупреждения
всего поддерева `mcp.servers`.

**Ожидание:** после записи показываются предупреждения, связанные с изменённым элементом (`mcp.servers[broken]`), а остальные — в `config check`.
Выключенный сервер — осознанная настройка, а не проблема, и уровень `note` для `config check` подошёл бы лучше.

**Риск:** нет. Шум прячет полезные предупреждения о только что изменённом ключе.
