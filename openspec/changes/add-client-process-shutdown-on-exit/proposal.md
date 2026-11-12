## Why

При штатном выходе из CodeLab desktop (Cmd+Q, закрытие последнего окна; macOS `NSApplication terminate:`) движок останавливается без размонтирования дерева виджетов. Поэтому `dispose` у `CodeLabBootstrap` не выполняется, и root scope не закрывается: не вызываются `CodeLabRootLifecycle.dispose`, `ClientWorkspace.dispose`, `EmbeddedTransportResolver.close` и `AcpClientApplication.dispose` (change `add-integrated-terminal`, D4 «Выход из app», D15 п. 9).

Обработчик выхода `AppExitHandler` (PR #296) закрывает только вкладки панели Terminal. Остальные дочерние процессы клиента остаются работать после выхода app:

1. процессы ACP `terminal/*` внешнего агента (`IoTerminalProcessRunner`);
2. процессы инструмента `exec` встроенного агента (`LocalExecutionEnv` из `codelab_agent_io`);
3. stdio-серверы MCP встроенного агента (`StdioProcessTransport`);
4. процесс внешнего stdio-агента (`StdioAcpTransport`).

Процессы 2–4 при выходе app получают EOF на stdin, но выходить по нему не обязаны: `exec` запускает команды пользователя и модели (`npm run dev`, `sleep`), а внуки обёрток вроде `npx` EOF не видят. Процессы `terminal/*` stdin не читают вовсе.

Это расходится с требованиями и документами:
- `acp-terminal-client` «Завершение активных процессов при disconnect/dispose»: при завершении приложения CodeLab убивает все terminal-процессы;
- `workspace-architecture` «CherryPick как dependency injection», сценарий «Жизненный цикл root scope»: root scope закрывается при shutdown;
- `docs/architecture/platform-integration.md` §23: shutdown flow должен включать cleanup process resources, сирот быть не должно;
- `docs/architecture/session-lifecycle.md` §42: нельзя уничтожить Flutter tree и надеяться, что процессы завершатся сами.

Есть и второе последствие. При выходе посреди хода встроенный агент не дописывает журнал сессии (`EmbeddedAgent.dispose` не вызывается), а `ClientWorkspace` не сбрасывает последний снимок рабочего места. Тот же путь закрытия это исправляет.

## What Changes

- **Обработчик выхода закрывает весь root scope с общим пределом.** `AppExitHandler.onExitRequested` вызывает `CodeLabRootLifecycle.dispose()`, а не только `TerminalTabsCubit.closeAll()`. Общий предел ожидания закрытия — **5 с** от запроса выхода. По истечении предела ответ всё равно `AppExitResponse.exit`, отмены выхода нет. Затем сброс журнала (≤500 мс), как сейчас.
- **Терминал и клиентские процессы закрываются параллельно.** `CodeLabRootLifecycle.dispose()` запускает `closeAll()` вкладок (hangUp → 3 с → kill) и цепочку «Cubit-ы → рабочее пространство → встроенный агент → ядро клиента» одновременно. Порядок внутри цепочки прежний.
- **Шаги закрытия изолированы.** Сбой одного шага не отменяет следующие. `dispose()` повторного вызова ждёт тот же проход, сигналы повторно не шлются.
- **Внешний stdio-агент.** Закрытие root scope передаёт `AcpClientApplication.dispose(closeTimeout: 2 с)`. `StdioAcpTransport.close` после EOF и `closeTimeout` шлёт `SIGTERM`, через 2 с — `SIGKILL`. Сейчас после `SIGTERM` транспорт ждёт выхода без предела.
- **ACP `terminal/*`.** `kill()` адаптера `IoTerminalProcessRunner`: `SIGTERM`, через 2 с без выхода — `SIGKILL`. `AcpClientApplication.dispose` завершает terminal-процессы и закрывает транспорт параллельно.
- **Встроенный агент** закрывается своим `EmbeddedAgent.dispose` (отмена ходов → `terminateTree` процессов `exec`, закрытие MCP-серверов). Сам `codelab_embedded` и ядро агента не меняются.
- **Журнал.** Новые события без содержимого (по образцу D9 `add-integrated-terminal`):
  - `app.exit_closed {duration_ms}`;
  - `app.exit_timeout {timeout_ms, pending}`;
  - `app.shutdown_step_failed {step, error_type}`;
  - `terminal_processes_killed {count, reason}` в `codelab_client_acp`.
- **ACP.** Новых сообщений нет. `session/cancel` перед выходом не отправляется. Завершение stdio-агента следует `16-Transports.md`: «Close stdin, terminate subprocess».
- **Исправления по ревью реализации (design.md, D10–D15).**
  - `pending` в `app.exit_timeout` перечисляет и не начатые шаги.
  - После рабочего пространства остановка встроенного агента и закрытие ядра клиента идут параллельно: зависший встроенный агент не задерживает сигналы `terminal/*` и stdio-агенту.
  - `dispose` ядра клиента окончателен для идущих Connect и Reconnect: новый транспорт после него не привязывается и не запускается.
  - `StdioAcpTransport.close` мемоизирован, сокращает ожидание по более раннему пределу и закрывает процесс, запущенный во время закрытия.
  - Статус выхода `terminal/*` выводится из кода выхода ОС: `exitCode` не бывает отрицательным (схема ACP).
  - Ответ на `terminal/*` не уходит в чужое соединение.

## Не входит

- Завершение дерева потомков процесса `terminal/*` (внуки команды агента). `IoTerminalProcessRunner` шлёт сигнал только корню, как сейчас. Хелпер дерева процессов есть только в `codelab_agent_io`, а `codelab_client_io` от него зависеть не может (ADR-0002). Отдельный вопрос — Q2.
- Укорочение grace встроенного агента при выходе (`server.shutdown(grace: 5 s)`, закрытие MCP-серверов до 14 с). API `EmbeddedAgent.dispose()` не меняется. Остаток — в Risks, вопрос Q3.
- Блокировка ввода или индикатор «Quitting…» на время закрытия (до 5 с) — UX, отдельная задача.
- Выход CLI: `CliRuntime.dispose` уже выполняется при завершении `codelab` (spec `codelab-cli` «Выход»).
- Аварийное завершение app (крах, `SIGKILL`): обработчик выхода в нём не вызывается, сети безопасности нет. Это остаточный риск, как и до change.
- Новые методы, поля и semantics ACP.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-workbench-ui`: новое требование «Выход из приложения завершает процессы клиента».
- `acp-terminal-client`: изменено «Завершение активных процессов при disconnect/dispose» — выход из приложения, параллельно с закрытием транспорта; новое требование «Принудительное завершение terminal-процесса».
- `agent-transports`: изменено «Stdio transport» — ограниченное закрытие с `SIGTERM` и `SIGKILL`, мемоизированное закрытие, закрытие во время запуска.
- `acp-terminal-client`: новое требование «Ответ на terminal-запрос только в соединение запроса»; статус выхода по коду выхода ОС.
- `acp-protocol-client`: новое требование «Закрытие ядра клиента во время подключения».

## Impact

- `apps/codelab_desktop/lib/app/`: `app_exit_handler.dart`, `app_scope.dart` (`CodeLabRootLifecycle`, `CodeLabBootstrap`), тесты `test/app/`; `apps/codelab_desktop/AGENTS.md` (раздел о выходе).
- `packages/dart/codelab_client_acp`: `AcpClientApplication.dispose({Duration? closeTimeout})` — добавлен необязательный параметр, совместимо; параллельное завершение; событие `terminal_processes_killed`; по ревью — мемоизированный `dispose`, проверки после `await` в подключении и `terminal/create`, отказ от ответа `terminal/*` в чужое соединение (без изменения публичного API).
- `packages/dart/codelab_client_io`: `IoTerminalProcessRunner` — эскалация `kill()`; статус выхода из кода выхода ОС.
- `packages/dart/codelab_acp_transports`: `StdioAcpTransport.close` — эскалация до `SIGKILL`, мемоизация и сокращение срока, закрытие во время `start` (`io.dart`, не web-барель).
- `codelab_client_core`, `codelab_embedded`, `codelab_agent_*`, `apps/codelab_cli`, `apps/codelab_agent` не меняются. CLI получает эскалацию транспорта и адаптера бесплатно.
- Зависимости и правила сторожа не меняются. Граф пакетов в `README.md` не меняется.
- Документы: `docs/architecture/concurrency.md` §45–§46, `platform-integration.md` §22–§23, `observability.md` (события `app.*`, §40), `session-lifecycle.md` §42.
