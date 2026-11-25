## Why

`codelab-agent serve` сейчас всегда работает через клиента: `read`, `write`, `edit` идут клиенту запросами `fs/*`, `exec` — запросами `terminal/*`. Пока клиент и агент на одной машине, это нормально. Если агент запущен на удалённой машине (сервер разработки, контейнер, виртуальная машина), всё перевёрнуто: модель видит файлы и запускает команды на машине клиента, а не там, где лежит проект. По WebSocket к тому же выключены `ls`, `search`, MCP и файлы проекта: агент не знает, на какой машине лежит `cwd` (`agent_host.dart`, `narrowing`).

Пользователь хочет обратного: агент на удалённой машине сам читает и пишет файлы, сам запускает команды, листинг и поиск, сам подключает MCP-серверы, а клиент остаётся тонким. Клиент показывает поток ответа, карточки вызовов и вопросы о разрешении и отвечает на них.

Механизм уже есть и проверен во встроенном агенте. `AcpServerConfig.localEnv` ставит сессии `LocalExecutionEnv`. Gate остаётся `AcpPermissionGate`, вопрос уходит клиенту. Containment по `cwd` даёт `BoundedEnv` (change `add-embedded-agent-mode`, D4). Бинарь его не включает никогда. Флаг `--local-exec` описан в архитектуре (§10.4 `shellExec: local`, §15.6), но не реализован.

## What Changes

- **Флаг `codelab-agent serve --local-exec`** работает с `--stdio` и `--ws`. Сервер получает `localEnv`: файлы, команды, листинг и поиск исполняет процесс агента, запросы `fs/*` и `terminal/*` клиенту не уходят, даже если клиент их объявил. Без флага поведение прежнее.
- **Обязательный флаг `--workspace-root <dir>`** (повторяемый) вместе с `--local-exec`. `cwd` из `session/new` и `session/load` должен существовать на машине агента и лежать внутри одного из корней после раскрытия символических ссылок. Иначе ответ — `-32602` с `data.codelab.reason: "cwdOutsideWorkspaceRoots"` (или прежний `cwd does not exist`), сессия не создаётся. Ошибка `realpath` при корнях — отказ. `session/load` проверяет ещё и `cwd` из заголовка журнала, а `session/list` не показывает сессии вне корней. Пути не сопоставляются: `cwd` используется как есть (`03-Session Setup.md`: cwd MUST быть рабочей папкой сессии).
- **В режиме `--local-exec` по WebSocket сужения по транспорту снимаются.** Включаются `fileListing` (`ls`, `search`), `mcp` (серверы конфигурации и серверы клиента; `mcpCapabilities.http: true`), файлы проекта (`AGENTS.md`, шаблоны, агенты), навыки с корнями только для чтения, `exec` в каталоге навыка (`execOnHost`) и проектный конфиг папки сессии. `/config` по WebSocket остаётся выключенной.
- **`--local-exec --ws` слушает только loopback.** Не-loopback `--host` даёт ошибку использования, код `64`. Адрес проверяется до привязки и ещё раз после неё. Токен под этим режимом — не короче 32 байт. Удалённый доступ — через SSH (`ssh host codelab-agent serve --stdio --local-exec …` или туннель `ssh -L` к `--ws`) или через обратный прокси с TLS на машине агента. Без `--local-exec` не-loopback `--host` по-прежнему даёт только предупреждение.
- **Сессией управляет только соединение-владелец** (дефект REV-35, issue #514; предусловие режима). `session/prompt`, `session/set_mode`, `session/set_config_option` и `_codelab/session/usage/ledger` к сессии, которую соединение не создало и не загрузило, дают `-32002` с `data.codelab.reason: "sessionNotOwned"`. Уведомление `session/cancel` от чужого соединения игнорируется с записью в лог. Правило действует для любого сервера и транспорта.
- **Наблюдаемость.** При старте с `--local-exec` пишется предупреждение `serve.local_exec` с транспортом и корнями. На каждую собранную сессию — `acp.session.execution` (`exec: local | client`). Отказы пишутся как `acp.session.cwd_rejected` и `acp.session.not_owned`, перехват сессии — как `acp.session.owner_changed`. События MCP-коннектора получают поле `origin`.
- **Документы.** `execution-sides.md` получает четвёртый столбец матрицы (`serve --local-exec`). Обновляются руководство и эксплуатация `codelab-agent`, §10.4, §13.1, §13.10, §13.15, §15.6 и §17.9.2 документа ядра, `acp-boundary.md`.

ACP не меняется: новых методов, полей и состояний нет. `initialize` не меняется. По WebSocket с `--local-exec` `mcpCapabilities.http` принимает значение `true`, как у `--stdio`, по существующему правилу «по плану ядра». Новые значения `data.codelab.reason` (`cwdOutsideWorkspaceRoots`, `sessionNotOwned`) расширяют существующее расширение `data.codelab.reason` (change `add-dart-agent-acp-server`).

## Не входит

- **«Удалённая папка» в клиентах.** В CLI `--cwd`/`-C` проверяет папку на локальной машине, а desktop показывает локальное дерево файлов. В первой версии путь `cwd` должен совпадать на обеих машинах: общий абсолютный путь, контейнер с `-v $PWD:$PWD`, смонтированная ФС. Отдельный change — Q2 в design.md.
- **TLS в бинаре** (`--tls-cert`, `--tls-key`, `--allow-remote`) — Q1.
- **Ключи `exec.shell`, `exec.default_timeout`, `exec.max_timeout`, `exec.env`, `exec.secrets`.** Они остаются с `applied: false`: применить их нужно ко всем хостам сразу, отдельным change. `exec.local_fallback` не реализуется — Q4.
- **Возобновление хода после разрыва.** `detachGrace` бинаря остаётся нулём (change `cancel-turn-on-ws-disconnect`, D1): разрыв отменяет ход и убивает запущенную команду.
- **Блокировка писателя журнала между процессами** (REV-36, issue #515), маскирование токена в `toString` конфигурации WebSocket и политика `ws://` на удалённый адрес в клиенте (REV-31, issue #508), окружение `terminal/create` у клиента (REV-29, issue #506), очередь записи клиентского stdio-транспорта (REV-41, issue #521), вопрос до проверки возможностей клиента (REV-42, issue #522). Почему это не блокеры режима — design.md, D11.
- Изменения в клиентах (`codelab_client_*`, `apps/codelab_cli`, `apps/codelab_desktop`), в `codelab_acp_protocol` и `codelab_acp_transports`.

## Capabilities

### Modified Capabilities
- `agent-binary`: флаги `--local-exec` и `--workspace-root`, локальное исполнение в `serve`, только loopback для `--local-exec --ws`, MCP, файлы проекта и проектный конфиг в этом режиме.
- `agent-acp-server`: корни рабочих папок сервера, владелец сессии, журнал стороны исполнения сессии.
- `agent-execution-env`: уточнение, когда хост передаёт `ListingOverlayEnv`.
- `agent-runtime`: допуск папки журнала при загрузке (`admitJournalCwd`).
- `agent-skills`: навыки по `--ws --local-exec`.
- `agent-mcp-client`: поле `origin` в событиях `mcp.server.connect` и `mcp.server.failed`.

## Impact

- `codelab_agent_acp`: поле `AcpServerConfig.workspaceRoots` (`WorkspaceRoot {path, resolved}`), проверка `cwd` по корням в `_checkCwd`, проверка заголовка журнала в `session/load`, фильтр `session/list`, проверка владельца в `_bridge` и в обработчике `session/cancel`, событие `acp.session.execution`. `dart:io` не появляется: `realpath` идёт через порт `PathResolver` окружения `localEnv`.
- `codelab_agent_core`: основной барель дополнительно экспортирует `normalizePath` и `isInside` (`src/util/posix_path.dart`). Это нужно для проверки корней без второй реализации путей. `AgentRuntime.loadSession` получает параметр `admitJournalCwd`, добавляется исключение `SessionCwdNotAdmitted`.
- `codelab_agent_mcp`: поле `origin` в событиях коннектора.
- `apps/codelab_agent`: разбор `--local-exec` и `--workspace-root` и проверка loopback до привязки (`serve_args.dart`), проверки при старте, сборка в `AgentHost.build`: `localEnv`, корни, снятие сужений, `serve.local_exec`. В `serve_ws.dart` — длина токена и повторная проверка адреса после привязки.
- Сторож: новых пакетов, зависимостей и правил нет. Граф пакетов в `README.md` не меняется.
- Клиенты: изменений кода нет. Вывод команды приходит текстом в `tool_call_update`, как у встроенного агента. Это уже отображают desktop, REPL и TUI `codelab`.
- Документы — полный список в задачах 0.1 и 9: `packages/dart/codelab_agent_core/doc/algorithms/execution-sides.md`, `02-assembly-and-hosts.md`, `13-troubleshooting.md`, руководство `codelab-agent` (`README.md`, `01`, `02`, `04`, `06`, `08`, `11`), `docs/user/configuration.md`, `docs/architecture/proposals/dart-agent-and-clients/12-8-phone-and-tablet.md`, `apps/codelab_agent/doc/user/02-connect-clients.md`, `apps/codelab_agent/doc/operations.md`, `apps/codelab_agent/AGENTS.md` §2, `docs/architecture/acp-boundary.md`, `docs/architecture/platform-integration.md`, документ ядра (§10.4, §13.1, §13.10, §13.15, §15.6, §17.9.2).
