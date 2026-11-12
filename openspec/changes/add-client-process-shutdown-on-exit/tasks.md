Задачи кода идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). Сначала красный тест, затем код. В скобках — требование спецификации и сценарий или решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[protocol]` — `packages/dart/codelab_acp_transports`;
- `[client]` — `packages/dart/codelab_client_acp`, `packages/dart/codelab_client_io`;
- `[desktop]` — `apps/codelab_desktop` (`lib/app/`, `test/app/`, `AGENTS.md` приложения);
- `[agent]` — задач нет: `codelab_embedded` и `codelab_agent_*` не меняются (D8, Q3).

Порядок: 1 и 2 независимы и идут параллельно; 3 зависит от 2.3–2.4 (параметр `closeTimeout`). Один PR в `develop` из `feature/add-client-process-shutdown-on-exit`.

Проверки — только затронутого (`AGENTS.md` §21):
- `fvm dart format --set-exit-if-changed` изменённых файлов;
- `fvm dart analyze` в `codelab_acp_transports`, `codelab_client_io`, `codelab_client_acp`. Публичный API `codelab_client_acp` меняется совместимо — ещё `codelab_client_core` и `apps/codelab_cli`. `fvm flutter analyze` в `apps/codelab_desktop`;
- тесты: `fvm dart test` в трёх пакетах; `fvm flutter test test/app/` в `apps/codelab_desktop`; тесты `apps/codelab_cli`, использующие `AcpClientApplication.dispose` и stdio-транспорт;
- `protocol-conformance` и `conformance:client` — меняются транспорт и клиентский ACP-слой;
- `test:e2e:cli:dart-agent` — меняется клиентский слой CLI;
- `web-compile` — затронут web-безопасный `codelab_client_acp`;
- `guard` не нужен: `pubspec.yaml` и импорты между пакетами не меняются;
- `test:e2e:app:*` — не запускается, только `release/*`. Полный `melos run check` — только по просьбе пользователя.

## 1. Транспорт stdio `[protocol]`

- [x] 1.1 `[protocol]` Красный тест `packages/dart/codelab_acp_transports/test/io/stdio_acp_transport_close_test.dart` (agent-transports «Stdio transport», сценарии «Агент выходит по закрытию stdin», «Агент игнорирует EOF и SIGTERM»; D3). Реальный процесс `sh -c "trap '' TERM; while :; do sleep 1; done"`, игнорирующий EOF:
  - `close(timeout: 200 ms)` завершается ≤ 3 s;
  - процесс завершился (`exitCode` процесса пришёл);
  - агент, выходящий по EOF, сигналов не получает, события `failure` нет;
  - повторный `close()` — no-op.

  POSIX-тест с `testOn: '!windows'`.
- [x] 1.2 `[protocol]` `StdioAcpTransport.close` (`lib/src/io/stdio_acp_transport.dart`): после `timeout` — `SIGTERM`, ожидание ≤ 2 s, затем `SIGKILL` без дальнейшего ожидания кода выхода (D3). Doc-комментарий `close` и `_waitForProcessExit` по `AGENTS.md` §15: почему ограничено и откуда 2 s. 1.1 зелёный.

## 2. Клиентский слой `[client]`

- [x] 2.1 `[client]` Красный тест `packages/dart/codelab_client_io/test/platform/terminal_process_runner_kill_test.dart` (acp-terminal-client «Принудительное завершение terminal-процесса», все сценарии; D4):
  - процесс с `trap '' TERM` после `kill()` мёртв, `kill()` завершился ≤ 3 s, `state` — `exited` с `signal: SIGKILL`;
  - `sleep 30` выходит по `SIGTERM` с `signal: SIGTERM`, `kill()` завершился сразу после выхода;
  - повторный `kill()` не меняет статус.

  `testOn: '!windows'`.
- [x] 2.2 `[client]` `IoTerminalProcessRunner`: `kill()` — `SIGTERM`, ожидание кода выхода ≤ 2 s, `SIGKILL`; признак фактического сигнала для `TerminalProcessState.exited(signal:)` (D4). Doc-комментарий порта `TerminalProcessHandle.kill()` в `codelab_client_acp/lib/src/domain/terminal_access.dart` — уточнить «SIGTERM, затем принудительно; завершается не позже ~2 s». 2.1 зелёный.
- [x] 2.3 `[client]` Красные тесты `packages/dart/codelab_client_acp/test/application/dispose_shutdown_test.dart` (acp-terminal-client «Завершение активных процессов при disconnect/dispose», сценарии «Выход из приложения по запросу ОС», «Завершение процессов не задерживает закрытие транспорта»; D4, D6):
  - `dispose(closeTimeout: 2 s)` передаёт `timeout` в `AcpTransport.close`; без параметра — `null`, как сейчас;
  - фейковый `TerminalProcessHandle` с `kill()` на ручном `Completer` и фейковый транспорт: `close` вызван до завершения `kill`, `dispose` завершается после обоих;
  - лог содержит `terminal_processes_killed {count, reason: dispose}`, а при переходе в `disconnected` — `reason: connection_closed`; при пустом реестре события нет; в событии нет команды, `cwd` и `terminalId`;
  - повторный `dispose()` не вызывает `kill`.
- [x] 2.4 `[client]` `AcpClientApplication.dispose({Duration? closeTimeout})`: `_killAllTerminalProcesses(reason)` и `_transport.close(timeout: closeTimeout)` параллельно (`Future.wait`), событие `terminal_processes_killed` (D4, D6). Doc-комментарий `dispose` (`AGENTS.md` §15): почему параллельно, ссылка на D4. 2.3 зелёный.

## 3. Composition root desktop `[desktop]`

- [x] 3.1 `[desktop]` Красные тесты `apps/codelab_desktop/test/app/root_lifecycle_shutdown_test.dart` (agent-workbench-ui «Выход из приложения завершает процессы клиента», сценарии «Сбой шага закрытия», «Вкладки Terminal не задерживают закрытие клиента», «Повторный запрос выхода»; D2, D5):
  - зависший `closeAll()` вкладок не задерживает вызов `AcpClientApplication.dispose` (фейковый launcher, `fakeAsync`);
  - исключение `ClientWorkspace.dispose` → `app.shutdown_step_failed {step: workspace, error_type}`, резолвер встроенного агента и ядро клиента закрыты;
  - повторный `dispose()` возвращает тот же `Future`, владельцы вызваны один раз;
  - ядро клиента получает `closeTimeout` 2 s;
  - `pendingSteps` содержит имя зависшего шага.
- [x] 3.2 `[desktop]` `CodeLabRootLifecycle` (`lib/app/app_scope.dart`):
  - `_disposing ??= _dispose()`;
  - ветка терминала параллельно клиентской;
  - помощник `_step(name, body)` с изоляцией и `pendingSteps`;
  - логгер `codelab_desktop.app` — необязательный параметр конструктора `Logger? logger` (шов тестов), по умолчанию логгер приложения;
  - константа `transportCloseTimeout = Duration(seconds: 2)` рядом с `defaultEmbeddedCloseTimeout`.

  Комментарии полей о порядке обновить (D2, D5). 3.1 зелёный.
- [x] 3.3 `[desktop]` Красные тесты `apps/codelab_desktop/test/app/terminal_exit_test.dart` (переименовать в `app_exit_handler_test.dart` или дополнить) и `app_exit_wiring_test.dart` (agent-workbench-ui «Выход из приложения завершает процессы клиента», сценарии «Закрытие не уложилось в предел», «Повторный запрос выхода»; D2, D5, D6):
  - `closeRoot` завершился → `app.exit_closed {duration_ms}`, ответ `exit`;
  - `closeRoot` висит → через 5 s (`fakeAsync`) `app.exit_timeout {timeout_ms: 5000, pending}`, затем сброс журнала и `exit`;
  - `closeRoot` бросил → `app.exit_close_failed {error_type}`, `exit`;
  - второй вызов `onExitRequested` во время первого — тот же `Future`, `closeRoot` вызван один раз;
  - проводка: `onExitRequested` из `CodeLabBootstrap` вызывает `CodeLabRootLifecycle.dispose`;
  - в событиях нет путей и текстов ошибок.
- [x] 3.4 `[desktop]` `AppExitHandler` (`lib/app/app_exit_handler.dart`):
  - параметр `closeRoot` вместо `terminalTabs`;
  - `exitTimeout = Duration(seconds: 5)`;
  - мемоизация `onExitRequested`;
  - события D6.

  Проводка в `_CodeLabBootstrapState.initState`: `closeRoot: _scope.resolve<CodeLabRootLifecycle>().dispose`. Doc-комментарий класса переписать (`AGENTS.md` §15): почему теперь весь root lifecycle, а не только терминал (ссылка на этот change, D1, D2), предел и что происходит по его истечении. 3.3 зелёный.
- [x] 3.5 `[desktop]` `apps/codelab_desktop/AGENTS.md`:
  - пункт о встроенном агенте (ожидание `close()` 10 с) — дополнить: при выходе действует общий предел 5 с;
  - пункт «Владелец процессов» терминала — `closeAll()` вызывается из `CodeLabRootLifecycle.dispose()` параллельно с клиентской веткой, в том числе при выходе.
- [x] 3.6 `[desktop]` Ручная проверка на macOS (`fvm flutter run -d macos --profile`; D9). Это не `test:e2e:app:*`.
  - Встроенный агент с MCP stdio-сервером и ходом `exec` `sleep 600` → Cmd+Q.
  - Внешний stdio-агент (`codelab-agent serve --stdio`) с `terminal/create` `sleep 600` → закрытие последнего окна.
  - Открытая вкладка Terminal → Cmd+Q.
  - Каждый раз: `ps -A -o pid,ppid,command` — сирот нет; app вышел ≤ 6 s; в журнале `app.exit_closed` или `app.exit_timeout`.
  - Итог записать в design.md, раздел D9.

## 4. Документы и закрытие

- [x] 4.1 `docs/architecture/concurrency.md` §45–§46, `platform-integration.md` §22–§23, `observability.md` (события `app.*`, §40), `session-lifecycle.md` §42 — внесено вместе с change (правило «сначала документ, потом код»).
- [x] 4.2 `[desktop]` В `openspec/changes/add-integrated-terminal/design.md`, D4 «Выход из app», — строка-ссылка: с change `add-client-process-shutdown-on-exit` обработчик выхода вызывает весь `CodeLabRootLifecycle.dispose()`, а не только `closeAll()`. Если `add-integrated-terminal` к этому моменту архивирован — ничего не делать: требование `integrated-terminal` о 3 s не меняется.
- [ ] 4.3 Проверки затронутого (шапка) и PR в `develop`. В описании PR:
  - какие проверки запускались локально;
  - что полный `melos run check` не запускался;
  - итог ручной проверки 3.6.

  `openspec validate add-client-process-shutdown-on-exit --strict`.

## 5. Исправления по ревью реализации

Решения — design.md, D10–D15; отклонённые находки G и H — там же, раздел «Отклонённые находки ревью», задач по ним нет. Публичный API не меняется (D8): сигнатуры `AcpClientApplication.dispose`, `AcpTransport.start`/`close`, `TerminalProcessHandle`, `TerminalProcessState` прежние.

Порядок: 5.1–5.2 `[protocol]`, 5.3–5.4 `[client]` (адаптер) и 5.5–5.8 `[client]` (ядро клиента) независимы и идут параллельно. 5.9–5.12 `[desktop]` от них не зависят: тесты root lifecycle — на двойниках. 5.13 — мелочи каждого исполнителя, после его основных задач. 5.14 — проверки и `openspec validate`.

Проверки затронутого — как в шапке. Дополнительно: `conformance:client` и `protocol-conformance` обязательны — меняется статус выхода в ответах `terminal/*` (D14) и отправка ответов (D15); `test:e2e:cli:dart-agent` — CLI получает D12, D13 через общие пакеты.

### `[protocol]` — `codelab_acp_transports`

- [x] 5.1 `[protocol]` Красные тесты в `packages/dart/codelab_acp_transports/test/io/stdio_acp_transport_close_test.dart` (agent-transports «Stdio transport», сценарии «Повторное закрытие с меньшим пределом», «Закрытие во время запуска»; D13). POSIX, `testOn: '!windows'`; агент — `sh -c "trap '' TERM; echo ready >&2; while :; do sleep 1; done"` (дождаться `ready` в событиях stderr с дедлайном).
  - Мемоизация: `close(timeout: 5 s)`, через 100 ms `close(timeout: 200 ms)` — оба `Future` завершаются, второй — не раньше первого; от первого вызова до завершения проходит меньше ~3 s (а не 5 + 2), процесс мёртв. Повторный вызов после завершения возвращается сразу.
  - Более поздний предел не продлевает: `close(timeout: 200 ms)`, затем `close(timeout: 10 s)` — завершение не позже ~3 s.
  - Закрытие во время запуска: `start()` без `await`, сразу `close()`. `start()` завершается `AcpTransportException` с кодом `closed`; событий `stateChanged(connected)` нет. Агент первым действием пишет свой pid во временный файл (`echo $$ > <tmp>`); после `close()` файл прочитан (с дедлайном) и `kill -0 <pid>` завершается ненулевым кодом — процесс мёртв, как в 1.1.
- [x] 5.2 `[protocol]` `StdioAcpTransport` (`lib/src/io/stdio_acp_transport.dart`; D13):
  - `close({timeout})` → `_closing ??= _close()`; дедлайн ожидания EOF — поле, повторный вызов сокращает его, пока `SIGTERM` не послан (таймер ожидания перезапускается на меньший остаток; `Future.any` выхода процесса и сигнала «дедлайн»); фаза после `SIGTERM` не сокращается;
  - `start()` сохраняет `Future` запуска; `_close` сначала `await` его, игнорируя ошибку;
  - в `start()` после `Process.start`: если закрытие уже начато — сохранить `_process`/`_exitCode` для эскалации `close`, без `_listenToProcess` и `_setState`, бросить `AcpTransportException(code: AcpTransportErrorCode.closed, message: 'Stdio ACP transport was closed while starting.')`;
  - doc-комментарии `close` и `start` (`AGENTS.md` §15): почему мемоизирован и почему срок только сокращается — ссылка на D13. 5.1 зелёный, 1.1 зелёный.

### `[client]` — `codelab_client_io`

- [x] 5.3 `[client]` Красные тесты в `packages/dart/codelab_client_io/test/platform/terminal_process_runner_kill_test.dart` (acp-terminal-client «Принудительное завершение terminal-процесса», сценарии «Процесс выходит по SIGTERM», «Процесс игнорирует SIGTERM», «Процесс обрабатывает SIGTERM и выходит с кодом», «Ни один статус выхода не содержит отрицательного кода»; D14):
  - `exec sleep 30` + `kill()` → `exited(exitCode: null, signal: 'SIGTERM')`;
  - `trap '' TERM` + `kill()` → `exited(exitCode: null, signal: 'SIGKILL')`;
  - `trap 'exit 0' TERM; echo ready; while :; do sleep 1; done` + `kill()` → `exited(exitCode: 0, signal: null)`;
  - процесс, убитый извне (`Process.killPid(pid, ProcessSignal.sigkill)` — pid из `echo $$`), без `kill()` адаптера → `exitCode: null, signal: 'SIGKILL'`;
  - естественный выход `exit 3` → `exitCode: 3, signal: null`;
  - ни в одном тесте `exitCode` не отрицателен.

  Pid тест читает из вывода процесса (`echo $$`), а не из адаптера: публичный API адаптера не расширяется.
- [x] 5.4 `[client]` `IoTerminalProcessRunner` (`lib/src/platform/terminal_process_runner.dart`; D14): `_handleExit` строит статус из кода выхода — `< 0` → `exitCode: null`, `signal` по номеру `-code` (таблица портируемых имён D14, иначе `SIG<n>`), `≥ 0` → `signal: null`. Поле `_lastSignal` удалить. Таблица — приватная функция файла с doc-комментарием: почему только портируемые номера (D14). Doc-комментарий `TerminalProcessState.exited` в `codelab_client_acp/lib/src/domain/terminal_access.dart` уточнить: `exitCode` при выходе по сигналу — `null`, не отрицателен (по-русски, `AGENTS.md` §15). 5.3 зелёный, 2.1 зелёный (сценарии 2.1 с `signal` — дополнить проверкой `exitCode: null`).

### `[client]` — `codelab_client_acp`

- [x] 5.5 `[client]` Красные тесты в `packages/dart/codelab_client_acp/test/application/dispose_shutdown_test.dart` (acp-protocol-client «Закрытие ядра клиента во время подключения», все сценарии; acp-terminal-client «Завершение активных процессов при disconnect/dispose», сценарий «terminal/create запускается во время dispose»; D12). Двойники транспорта с ручными `Completer` для `start` и `close`, фабрика транспорта на `Completer`:
  - `reconnect` ждёт фабрику → `dispose()` → фабрика возвращает транспорт: `start` не вызван, `close` нового вызван, на `inbound`/`events` нового никто не подписан, `reconnect` бросает `AcpClientApplicationException`;
  - `reconnect` ждёт `close` прежнего → `dispose()` → `close` прежнего завершается: новый не привязан и не запущен, `reconnect` бросает;
  - `connect` ждёт `start` → `dispose()`: `close` транспорта вызван `dispose`, `connect` бросает `AcpClientApplicationException` после завершения `start`;
  - повторный `dispose()` — тот же `Future` (`identical`), `close` транспорта вызван один раз;
  - `terminal/create`: фейковый runner с `start` на `Completer` → `dispose()` → `start` завершается: `kill()` handle вызван, ответа на `terminal/create` в исходящих нет, `dispose` завершается только после `kill()`.
- [x] 5.6 `[client]` `AcpClientApplication` (`lib/src/application/acp_client_application.dart`; D12): `_disposed` и `_disposing ??= _dispose()`; проверки после `await` в `reconnect` (после фабрики), `_replaceTransport` (после `close` прежнего, до `_bindTransport`), `_establishConnection` (после `start`); в `terminal/create` — поколение до `await runner.start`, после него при закрытом ядре или сменённом поколении `kill()` без регистрации и ответа, `_logStaleEvent('terminal_create_result', generation)`; множество незавершённых стартов, `dispose` ждёт его в общем `Future.wait` с `_killAllTerminalProcesses` и закрытием транспорта. Doc-комментарий `dispose` дополнить (мемоизация, окончательность для идущих подключений — D12). 5.5 зелёный, 2.3 зелёный.
- [x] 5.7 `[client]` Красные тесты `packages/dart/codelab_client_acp/test/application/terminal_stale_response_test.dart` (acp-terminal-client «Ответ на terminal-запрос только в соединение запроса», все сценарии; «Завершение активных процессов при disconnect/dispose», сценарий «Сбой журнала не оставляет процессы живыми»; D15):
  - `terminal/kill` с `kill()` на `Completer` → `reconnect` к новому двойнику транспорта → `kill()` завершается: в исходящих нового транспорта нет ответа с id запроса, в журнале `event_ignored {reason: stale_generation, kind: terminal_response}` с поколением запроса;
  - то же для `terminal/wait_for_exit` (выход процесса — после замены) и `terminal/release`;
  - ошибка (`UnknownTerminalFailure` после замены) тоже не отправляется в новый транспорт;
  - после `dispose` ответ не отправляется, и диагностика об ошибке отправки не пишется;
  - логгер, бросающий на `terminal_processes_killed`: `dispose` завершается без исключения, `kill()` у всех handle вызван.
- [x] 5.8 `[client]` `AcpClientApplication` (D15): приватный помощник ответа на `terminal/*` с проверкой «ядро не закрыто и поколение то же», используемый для результата и ошибки во всех пяти обработчиках; `_killAllTerminalProcesses`: сначала запустить все `kill()`, затем записать событие в `try` с игнорированием сбоя, затем ждать `kill()`; второй `_terminals.clear()` убрать; `reason` — приватный enum (`connectionClosed`, `dispose`) с именем для журнала. 5.7 зелёный.

### `[desktop]` — `apps/codelab_desktop`

- [x] 5.9 `[desktop]` Красные тесты в `apps/codelab_desktop/test/app/root_lifecycle_shutdown_test.dart` (agent-workbench-ui «Выход из приложения завершает процессы клиента», сценарий «Не начатые шаги видны в pending»; D10):
  - до `dispose()` — `pendingSteps` пуст;
  - `ClientWorkspace.dispose` висит: сразу после `dispose()` `pendingSteps` содержит `workspace`, `embedded`, `migration_offer`, `transport`, `client` (и `terminal`, если вкладки тоже висят) — в порядке закрытого набора;
  - после завершения прохода — пуст;
  - сбой шага убирает его имя из `pendingSteps`.
- [x] 5.10 `[desktop]` `CodeLabRootLifecycle` (`lib/app/app_scope.dart`; D10): `_dispose()` первым синхронным действием заполняет `_pendingSteps` всем набором; `_step` только удаляет имя. Doc-комментарий `pendingSteps`: «не завершены, в том числе не начаты». 5.9 зелёный.
- [x] 5.11 `[desktop]` Красные тесты в `apps/codelab_desktop/test/app/root_lifecycle_shutdown_test.dart` (agent-workbench-ui «Выход из приложения завершает процессы клиента», сценарии «Зависшая остановка встроенного агента не задерживает внешнего агента», «Выход во время переподключения» — уровень root lifecycle; D11):
  - `EmbeddedTransportResolver.close()` висит (открыватель на `Completer`, открытие в полёте) → `AcpClientApplication.dispose(closeTimeout: 2 s)` и закрытие начального транспорта вызваны без ожидания резолвера (`fakeAsync`, без продвижения времени);
  - `SecretMigrationOffer.close()` вызывается только после завершения `close()` резолвера;
  - `ClientWorkspace.dispose()` завершается раньше, чем начинаются `embedded` и `client`;
  - `embedded.close_timeout` через 10 s пишется по-прежнему (сценарий «Зависшая остановка встроенного агента» требования о встроенном агенте).
- [x] 5.12 `[desktop]` `CodeLabRootLifecycle._closeClient` (D11): после `workspace` — `Future.wait` двух подветвей (`embedded` → `migration_offer`; `transport` → `client`). Обновить комментарии полей `_workspace`, `_embedded`, `_secretMigrationOffer` и doc-комментарий класса (порядок и почему подветви параллельны — embedded-agent «Жизненный цикл встроенного агента», D11). `apps/codelab_desktop/AGENTS.md`, раздел «Встроенный агент», пункт о `close()` резолвера: «до `AcpClientApplication` (D9)» заменить на «параллельно с закрытием ядра клиента, после рабочего пространства (`add-client-process-shutdown-on-exit`, D11)». 5.11 зелёный, 3.1 зелёный.

### Мелочи ревью (без спецификаций)

- [x] 5.13 Мелкие правки, по одной задаче на исполнителя:
  - `[client]` `codelab_client_acp`:
    - перевести на русский doc-комментарий `TerminalProcessHandle.kill` (`lib/src/domain/terminal_access.dart`, ~54) и `_killAllTerminalProcesses` (`acp_client_application.dart`, ~1846–1857) по `AGENTS.md` §15;
    - двойной `_terminals.clear()` и `reason` как приватный enum — входят в 5.8, здесь не повторять.
  - `[client]` `codelab_client_io`, `test/platform/terminal_process_runner_kill_test.dart`:
    - цикл ожидания `ready` (~26) — с дедлайном (например, 5 s, затем `fail`);
    - повторный `kill()` (~52) — проверять, что он возвращается немедленно (`Stopwatch` < 100 ms), а не только что статус не изменился.
  - `[desktop]` `apps/codelab_desktop`:
    - `appLogger()` в `lib/app/app_scope.dart` сделать приватным (`_appLogger`): используется только в этом файле;
    - `test/app/root_lifecycle_shutdown_test.dart`: опрос `until` через `Future.delayed` (~138) заменить на `pumpEventQueue()` или `fakeAsync`; убрать тавтологию `expect(transportCloseTimeout, const Duration(seconds: 2))` (~166);
    - `test/app/app_exit_handler_test.dart`: сбрасывать `pending` в `setUp` (~60); шапку файла поправить — проводку `closeRoot` к `CodeLabRootLifecycle.dispose` проверяет `app_exit_wiring_test.dart`, а здесь `closeRoot` — двойник, вызывающий `closeAll()` вкладок;
    - в задаче 3.2 логгер `CodeLabRootLifecycle` сделан необязательным параметром конструктора (`Logger? logger`), а не через `EmbeddedCloseSettings` — так и оставить. Формулировка 3.2 исправлена в этом документе, кода не требует.

## 6. Закрытие после исправлений

- [x] 6.1 Проверки затронутого (шапка и раздел 5), повторная ручная проверка 3.6 с добавленным случаем: Cmd+Q во время переключения со stdio-профиля на встроенный агент (открытие ещё идёт) при работающем `terminal/create` `sleep 600` — сирот нет, в журнале `app.exit_closed` или `app.exit_timeout` с `pending` без `client`.
  - Ручная часть пройдена 2026-11-13 (D9, «Итог ручной проверки»): сирот нет, выход 0,3 с, `app.exit_closed`. Но выход пришёлся на уже открытый встроенный агент: открытие длится ~1 мс, окно «открытие ещё идёт» вручную недостижимо и покрыто тестами. Пункт отмечен по решению пользователя (2026-11-13).
- [x] 6.2 `openspec validate add-client-process-shutdown-on-exit --strict`.

## 7. Исправления по повторному ревью

- [x] 7.1 `[client]` `codelab_client_acp` (D4, D12): `dispose` ждёт и массовые завершения, уже запущенные разрывом соединения (`_transitionConnection` → `_killAllTerminalProcesses(connectionClosed)` через `unawaited`): приватное множество идущих завершений по образцу `_pendingTerminalStarts`, `_dispose` ждёт его в том же `Future.wait`. Красный тест в `dispose_shutdown_test.dart`: переход в `disconnected` при `kill()` на `Completer`, затем `dispose()` не завершается, пока `kill` не завершён.
- [x] 7.2 `[client]` `codelab_client_acp` (D15, §9): `terminal/release` после `await handle.kill()` удаляет запись реестра, только если в ней тот же handle (`identical`). Красный тест рядом с `terminal_stale_response_test.dart`: release ждёт `kill()` → reconnect → новый `terminal/create` с тем же id → `kill()` завершается → новый процесс остаётся в реестре.
- [x] 7.3 `[client]` `codelab_client_acp`: тесты на устаревший из-за Reconnect `terminal/create` (ветка `generation != _generation`: `kill()` вызван, ответа в новом транспорте нет, `event_ignored {kind: terminal_create_result}`) и на устаревший ответ `terminal/output`. В `event_ignored` для `terminal_response`/`terminal_create_result` добавить метод и `request_id` (§16; не секреты).
- [x] 7.4 `[client]` `codelab_client_io` (D14): трактовка отрицательного кода выхода как сигнала — только POSIX. На Windows отрицательный код (NTSTATUS) — `exitCode` как беззнаковое 32-битное значение, `signal: null`; выбор платформы изолирован в адаптере (§11). Тест на чистую функцию преобразования кода для обеих веток.
- [x] 7.5 `[client]` Комментарии по-русски (§15): doc-комментарий `TerminalProcessHandle.kill` (`terminal_access.dart`), doc-комментарии изменённых обработчиков `terminal/*` в `acp_client_application.dart`.
- [x] 7.6 `[protocol]` `codelab_acp_transports` (D3, D13): дедлайн EOF в `StdioAcpTransport` — по монотонному `Stopwatch`, а не `DateTime.now()`; комментарий `// The process may already have exited.` перевести.
- [x] 7.7 `[desktop]` `apps/codelab_desktop`: комментарий `app_exit_handler.dart` (~24) о «каждый владелец уже послал сигналы» — привести к D2/D10/D11; `root_lifecycle_shutdown_test.dart` — закрывать все созданные `lifecycle`/`hanging` в `tearDown`, шапка с 5.9, 5.11, D10, D11. Проверить, закрывает ли владелец проверки профиля (`profile_probe.dart`, Cubit настроек) свою проверку в шаге `cubits`; если нет — пункт в Risks design.md (не исправлять в этом change).
