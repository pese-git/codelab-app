> Метки исполнителей — по `CLAUDE.md`:
> - `[protocol]` — `codelab_agent_acp` (`acp-protocol-engineer`);
> - `[agent]` — `codelab_agent_core`, `codelab_agent_mcp` и `apps/codelab_agent` (`agent-core-engineer`);
> - `[client]` — `apps/codelab_cli` (`client-engineer`).
>
> Документацию пакетов и приложений пишет `docs-writer` — это отмечено в задаче.
>
> Задачи идут парами «тест → реализация», красный тест первым (`packages/dart/codelab_agent_core/AGENTS.md` §2). Красные процессные тесты бинаря (раздел 5) пишутся до кода бинаря (разделы 6–7).
>
> Q1–Q4 design.md решены пользователем 2026-11-25: везде (а); удалённая папка в клиентах — отдельный change `add-client-remote-workspace`.

## 0. Документы до кода

- [ ] 0.1 `[agent]` Документ ядра:
  - §10.4 — строки `fileListing`, `mcp` и абзац «Как работает `fileListing`»: исключение `--local-exec`;
  - §13.1 — `AcpServerConfig.workspaceRoots`, `WorkspaceRoot`, `localEnv` бинаря;
  - §13.5 — допуск заголовка журнала, фильтр `session/list`;
  - §13.10 — владелец сессии (D4, «Момент проверки»);
  - §13.15 — отступление MCP по WebSocket действует только без `--local-exec`;
  - §15.6 — строка `--local-exec` без `exec.local_fallback`, флаг `--workspace-root`, длина токена;
  - `15-configuration.md`, таблица раздела `exec` — описание `local_fallback` (Q4);
  - §17.9.2 — фоновые команды при `--local-exec` без ключа;
  - §12.3 — события D10.

  Также `docs/architecture/proposals/dart-agent-and-clients/12-8-phone-and-tablet.md` (§12.8.2 и таблица решений): телефону доступен агент с `--local-exec` только по `wss://` через TLS-прокси (D3).

## 1. Ядро: функции путей и допуск журнала (D2, D12)

- [ ] 1.1 `[agent]` Тест `codelab_agent_core`: `normalizePath` и `isInside` доступны из `package:codelab_agent_core/codelab_agent_core.dart`; `/w/../etc` лежит вне `/w`, `/proj_evil` — вне `/proj`. Красный.
- [ ] 1.2 `[agent]` Экспорт `normalizePath` и `isInside` (`show`) из основного бареля; doc-комментарии функций по-русски (§15). 1.1 зелёный, `web-compile` зелёный.
- [ ] 1.3 `[agent]` Тесты рантайма по agent-runtime «Допуск папки журнала при загрузке»: «Журнал чужой папки не открывается» (функция вызвана один раз с `cwd` заголовка; нет `AgentSession`, подключения MCP и вызова модели), «Без параметра». Красные.
- [ ] 1.4 `[agent]` Параметр `admitJournalCwd` у `AgentRuntime.loadSession` и исключение `SessionCwdNotAdmitted`; вызов сразу после `_store.open`. 1.3 зелёные.
- [ ] 1.5 `[agent]` Тест `codelab_agent_mcp`: сценарий «Источник сервера в логе» (agent-mcp-client «Наблюдаемость MCP без секретов»). Красный. Затем поле `origin` в `_log` коннектора для `mcp.server.connect` и `mcp.server.failed`. Зелёный.

## 2. ACP-сервер: корни рабочих папок (agent-acp-server «Корни рабочих папок сервера», «session/list»)

- [ ] 2.1 `[protocol]` Тесты `codelab_agent_acp/test/workspace_roots_test.dart` на `MemoryExecutionEnv` с шпионом `PathResolver`. Сценарии:
  - «cwd внутри корня»;
  - «cwd вне корней»: нет `stat` и `realpath`, корни не в тексте;
  - «Корень за символической ссылкой»;
  - «Символическая ссылка наружу»;
  - «Ошибка realpath при заданных корнях»: `PathResolver` даёт `Err`, а `stat` — `Ok`;
  - «Заголовок журнала вне корня, запрос внутри»;
  - «Нарушение проводки»: три случая;
  - «Сессии вне корней не видны»: страница короче 50 с `nextCursor`;
  - событие `acp.session.cwd_rejected`, оба значения `reason`.

  Красные.
- [ ] 2.2 `[protocol]` Тип `WorkspaceRoot`, поле `AcpServerConfig.workspaceRoots`, проверки в конструкторе, шаги 1–5 в `_checkCwd` (fail closed при ошибке `realpath`), `admitJournalCwd` в `_sessionLoad` (сопоставление `SessionCwdNotAdmitted` → `-32602`), фильтр в `_sessionList`. Doc-комментарии по §15 и D2. 2.1 зелёные.

## 3. ACP-сервер: владелец сессии (agent-acp-server «Сессия управляется соединением-владельцем» и MODIFIED-требования; REV-35, #514)

- [ ] 3.1 `[protocol]` Тесты `codelab_agent_acp/test/session_owner_test.dart` с двумя соединениями на паре транспортов в памяти. Сценарии:
  - «Промпт в чужую сессию»;
  - «Отмена из чужого соединения»: уведомление и терпимый запрос `session/cancel`, ход не отменён;
  - «Загрузка передаёт владение» с событием `acp.session.owner_changed`;
  - «Загрузка во время смены режима» (S6);
  - «Журнал чужой сессии» (`_codelab/session/usage/ledger`);
  - `set_config_option` из чужого соединения;
  - отсоединённый владелец (`detached`) тоже чужой;
  - «Одно соединение не замечает правила»;
  - поле `method` события `acp.session.not_owned` обрезается до 64 рун — модульный тест функции обрезки.

  Красные.
- [ ] 3.2 `[protocol]` Проверка владельца в `_bridge` (параметр соединения) и в `_cancel`, до первого `await`; `AcpRequestError.notFound` с `data.codelab.reason: "sessionNotOwned"`; события `acp.session.not_owned` и `acp.session.owner_changed` (в `reattach` при смене живого или отсоединённого владельца). 3.1 зелёные. Остальные тесты пакета (`detach_test.dart`, `session_load_*` и прочие) остаются зелёными без изменений.

## 4. ACP-сервер: журнал стороны исполнения (agent-acp-server «Сторона исполнения сессии в журнале»)

- [ ] 4.1 `[protocol]` Тесты: «Ветка хоста», «Ветка клиента без листинга», случай `localListing` → `listing: "local"`. Событие пишется после `session/load`, создавшего мост, и не пишется при `reattach`. Красные.
- [ ] 4.2 `[protocol]` `acp.session.execution` в `_sessionNew` и в ветке `_sessionLoad` с новым мостом. 4.1 зелёные.

## 5. Бинарь: красные тесты до кода (agent-binary, agent-skills)

- [ ] 5.1 `[agent]` Тесты разбора `serve` в `apps/codelab_agent/test/`:
  - «Без корня», «Корень без флага режима»;
  - несуществующий корень и файл вместо каталога;
  - относительный корень от каталога процесса, повторяемый `--workspace-root`, пара `path`/`resolved` для корня за ссылкой;
  - «Не-loopback адрес»: `0.0.0.0` и `192.168.1.5` отклоняются, `localhost`, `127.0.0.2` и `::1` допустимы;
  - «IPv4 в IPv6-записи»;
  - справка содержит оба флага.

  Красные.
- [ ] 5.2 `[agent]` Тесты `serve_ws` (S3, S5):
  - «Короткий токен»: значение не в stderr и не в логе;
  - адрес после привязки не loopback (шов: подставной результат `bind`) — сокет закрыт, код `64`, подключений нет.

  Красные.
- [ ] 5.3 `[agent]` Тесты `agent_host_local_exec_test.dart` (уровень `AgentHost.build`):
  - таблица D5 для четырёх сочетаний транспорта и флага: `localEnv`, `localListing`, `workspaceRoots`, `fileListing`, `mcp`, `projectFiles`, `skillFiles`, `hostFiles`, `projectConfig`, `configCommand`;
  - «WebSocket с локальным исполнением читает файлы проекта»;
  - «WebSocket с локальным исполнением видит навыки» (agent-skills, A1);
  - событие `serve.local_exec`;
  - PERM-11: `write` в `<cwd>/.codelab/config.yaml` сессии по `--ws --local-exec` критичен (S9);
  - без `--local-exec` поведение прежнее: существующие тесты `agent_host_*` и сценарий «WebSocket без навыков» не меняются.

  Красные.
- [ ] 5.4 `[agent]` Процессные тесты (Dart VM, `--llm-script`), красные до разделов 6–7:
  - `local_exec_ws_process_test.dart` — настоящий процесс `serve --ws --port 0 --local-exec` и клиент `WebSocketAcpTransport` на loopback:
    - «Файлы и команды на машине агента по WebSocket»;
    - «Вопрос о разрешении остаётся у клиента»;
    - «Листинг и поиск по WebSocket»;
    - «Предупреждение при старте»;
    - «Разрыв во время команды»: pid потомка не жив ≤ 5 с;
    - `-32602 cwdOutsideWorkspaceRoots` для `cwd` вне корня;
  - `local_exec_stdio_process_test.dart` — «Режим по stdio» (клиент без `fs` и `terminal`);
  - сценарий «MCP по WebSocket с локальным исполнением» в `config_mcp_ws_test.dart` — fake stdio-сервер, pid после `SIGTERM`. Сценарий «WS-профиль не запускает MCP-серверы» без флага остаётся зелёным;
  - сценарий «serve --ws --local-exec читает конфиг папки сессии» в `agent_host_project_config_test.dart`.

## 6. Бинарь: флаги и сеть (D1, D3)

- [ ] 6.1 `[agent]` `ServeOptions.localExec`, `ServeOptions.workspaceRoots`; разбор и проверки в `serve_args.dart`: коды `64`, loopback до привязки, раскрытие корней и `toCorePath` до сборки ядра. 5.1 зелёные.
- [ ] 6.2 `[agent]` `serve_ws.dart`: длина токена под `--local-exec` и проверка `HttpServer.address.isLoopback` после привязки. 5.2 зелёные.

## 7. Бинарь: сборка хоста (D5)

- [ ] 7.1 `[agent]` `AgentHost.build`:
  - признак `agentSide = stdio || localExec` для сужений;
  - `localEnv` и `workspaceRoots` в `AcpServerConfig`;
  - `skillFiles` и `hostFiles` по `--ws --local-exec`;
  - событие `serve.local_exec`.

  Обновить doc-комментарий `AgentHost` и `apps/codelab_agent/AGENTS.md` §2 (строки о `--ws`). 5.3 и 5.4 зелёные.

## 8. Клиент: приёмка без изменения кода (D9)

- [ ] 8.1 `[client]` E2E CLI (`test:e2e:cli:dart-agent`). Клиент `codelab -p … -a ws://127.0.0.1:<port>` с токеном длиной не меньше 32 байт работает против `codelab-agent serve --ws --local-exec --workspace-root <tmp> --llm-script <сценарий>`, общая папка — `<tmp>`. Ожидается:
  - `exec` с одобрением `--approve allow-all` печатает вывод команды;
  - файл создан на стороне агента;
  - в `--verbose`-журнале клиента нет ни одного `terminal/*` и `fs/*`.

  Код клиента не меняется. Если тест требует правки клиента — остановиться и вернуть вопрос архитектору.

## 9. Документация (`docs-writer`, стандарт `.claude/skills/codelab-docs/SKILL.md`)

Всё, где сейчас записано «по WebSocket нельзя», получает исключение `--local-exec`.

- [ ] 9.1 `[agent]` (`docs-writer`) `packages/dart/codelab_agent_core/doc/`:
  - `algorithms/execution-sides.md`:
    - столбец `serve --local-exec` в матрице и ветка в схеме выбора;
    - псевдокод А, разобранный пример `--ws --local-exec` по логам задачи 5.4;
    - снять строку «Не реализовано: `--local-exec`»;
    - владелец сессии и допуск журнала в граничных случаях;
    - `exec` в каталоге навыка вне корней (S8);
  - `02-assembly-and-hosts.md` — раздел «Что меняет транспорт» и таблица хостов;
  - `13-troubleshooting.md` — нет `ls`/MCP по WebSocket, `cwdOutsideWorkspaceRoots`, `sessionNotOwned`.
- [ ] 9.2 `[agent]` (`docs-writer`) Руководство и эксплуатация `apps/codelab_agent`:
  - `README.md`;
  - `doc/user/00-overview.md` — таблица способов запуска;
  - `doc/user/01-install-and-run.md` — запуск `--ws`, флаги;
  - `doc/user/02-connect-clients.md` — раздел «Агент на другой машине»: SSH + `--stdio`, туннель + `--ws`, общий путь папки;
  - `doc/user/04-tools.md` — `ls`, `search` по WebSocket;
  - `doc/user/06-project-context.md` — файлы проекта и навыки по WebSocket;
  - `doc/user/08-mcp.md` — MCP по WebSocket, `origin`;
  - `doc/user/11-troubleshooting.md` — `cwdOutsideWorkspaceRoots`, `sessionNotOwned`, короткий токен;
  - `doc/operations.md`:
    - флаги и коды `64`;
    - только loopback и схемы доступа (D3);
    - токен ≥ 32 байт и «токен = оболочка» (R1);
    - `exec` в каталоге навыка вне корней (S8);
    - REV-36 — не запускать второй процесс над теми же сессиями;
    - события D10.
- [ ] 9.3 `[protocol]` (`docs-writer`) Документы ACP-слоя и архитектуры:
  - `packages/dart/codelab_agent_acp/doc/03-projection-and-client-requests.md` и `02-session-bridge.md` — `workspaceRoots`, допуск журнала, владелец сессии;
  - `docs/architecture/acp-boundary.md` — значения `data.codelab.reason`: `cwdOutsideWorkspaceRoots`, `sessionNotOwned`;
  - `docs/architecture/platform-integration.md` — строка «Файлы и команды» с `--local-exec`.
- [ ] 9.4 `[agent]` (`docs-writer`) `docs/user/configuration.md` — описание ключей `exec` и `exec.local_fallback` по ответу на Q4.
- [ ] 9.5 `[client]` (`docs-writer`) Если в `apps/codelab_cli/doc/user/` или `apps/codelab_desktop/doc/user/` описано подключение к `ws://` — ссылка на раздел 9.2 и ограничение «путь папки совпадает на обеих машинах» и обход: та же папка по тому же пути на клиенте, CLI работает полностью, desktop — без дерева файлов (Q2, решение (а)).
- [ ] 9.6 `[agent]` При архивировании change — поправить Purpose `openspec/specs/agent-binary/spec.md` (фраза «`--local-exec` — этап 8») и Purpose `agent-acp-server` (отступление MCP по WebSocket — только без `--local-exec`): дельта Purpose не меняет.

## 10. Проверки (AGENTS.md §21)

- [ ] 10.1 `[agent]` Форматирование и анализ:
  - `fvm dart format --set-exit-if-changed` изменённых файлов;
  - `fvm dart analyze` в `codelab_agent_core`, `codelab_agent_mcp`, `codelab_agent_acp`, `apps/codelab_agent`;
  - `fvm dart analyze` в пакетах, зависимых от бареля ядра: `codelab_agent_io`, `codelab_embedded`, `codelab_setup`.
- [ ] 10.2 `[agent]` Тесты изменённых пакетов (`fvm dart test` в `codelab_agent_core`, `codelab_agent_mcp`, `codelab_agent_acp`, `apps/codelab_agent`) и в `codelab_embedded` — потребителе `AcpServerConfig` и `loadSession`.
- [ ] 10.3 `[agent]` Скрипты и проверки:
  - `conformance:agent`, `conformance:embedded`, `protocol-conformance` (ACP-проекция агента);
  - `test:e2e:cli:dart-agent`, `test:e2e:cli:embedded`;
  - `web-compile` (барель ядра);
  - `guard` — импорты не меняются, прогон это подтверждает;
  - `openspec validate add-agent-remote-exec --strict`.
- [ ] 10.4 `[agent]` Двойное ревью (`architecture-reviewer`, `acp-safety-reviewer`) с упором на D2, D3, D4 и R1–R3a. В PR — список запущенных проверок и пометка, что полный `melos run check` не запускался.
