## 1. Протокольные модели (acp_protocol)

- [x] 1.1 Создать `packages/dart/acp_protocol/lib/src/acp/terminal.dart` с типизированными моделями `CreateTerminalRequest`/`CreateTerminalResponse`, `TerminalOutputRequest`/`TerminalOutputResponse`, `WaitForTerminalExitRequest`/`WaitForTerminalExitResponse`, `KillTerminalCommandRequest`/`KillTerminalCommandResponse`, `ReleaseTerminalRequest`/`ReleaseTerminalResponse`, `TerminalExitStatus` (freezed, `fromJson`/`toJson`), по образцу `permission.dart`/`session.dart`
- [x] 1.2 Зарегистрировать все пять `terminal/*` методов в `acpMethodRegistry` (`acp_method_codec.dart`) как `AcpMethodDefinition.request`
- [x] 1.3 Экспортировать новые модели через `lib/acp_protocol.dart`
- [x] 1.4 Unit-тесты кодирования/декодирования для всех моделей, включая невалидные формы

## 2. Domain и application (acp_client_core)

- [x] 2.1 Добавить domain-модель `TerminalSession`/`TerminalProcessState` (immutable, state machine `running`/`exited`, отдельно от флагов killed/released) в `packages/dart/acp_client_core/lib/src/domain/`
- [x] 2.2 Добавить session-scoped registry `SessionId → Map<TerminalId, TerminalSession>` в application-слое
- [x] 2.3 Реализовать application-level проверку `cwd` из `terminal/create`: канонизация и проверка принадлежности working directory активной сессии (переиспользуя логику из `add-acp-fs-client-support`, если она уже реализована, иначе — параллельно по тому же паттерну)
- [x] 2.4 Подключить обработку входящих `terminal/create`/`terminal/output`/`terminal/wait_for_exit`/`terminal/kill`/`terminal/release` в `AcpClientApplication`: `create` — проверка working directory → запуск процесса → ответ, без approval-шага; остальные методы — операции над registry по `terminalId`
- [x] 2.5 Реализовать корректную обработку неизвестного/уже освобождённого `terminalId` во всех методах, кроме `create`, типизированной ACP-ошибкой

## 3. Infrastructure (platform adapter)

- [x] 3.1 Создать узкий adapter для запуска и управления процессом в `apps/codelab_app/lib/core/platform/` (старт с `command`/`args`/`env`/`cwd`, потоковая буферизация stdout+stderr, `kill`, ожидание exit-кода/сигнала), инкапсулирующий `dart:io` Process — независимый от `TerminalProcessFactory` из `add-integrated-terminal`
- [x] 3.2 Реализовать буферизацию вывода с обрезкой по `outputByteLimit` с начала буфера, на границе допустимого UTF-8 символа
- [x] 3.3 Подключить adapter в composition root (CherryPick) и передать его в `AcpClientApplication`/соответствующий use case через порт/интерфейс

## 4. Lifecycle и disposal

- [x] 4.1 Завершать (kill) все `running` terminal-процессы сессии при переходе этой ACP-сессии в disconnected
- [x] 4.2 Завершать (kill) все активные terminal-процессы всех сессий при shutdown приложения
- [x] 4.3 Тест: `terminal/kill` для уже завершившегося процесса — no-op, без ошибки и без повторной фиксации exit-статуса

## 5. Capabilities announcement

- [x] 5.1 Изменить построение `InitializeRequest` в `acp_client_application.dart`: отправлять `clientCapabilities.terminal = true` только если все пять `terminal/*` методов зарегистрированы, иначе `false`
- [x] 5.2 Тест: `initialize` отправляет корректный `clientCapabilities.terminal` при полной и при частичной поддержке методов

## 6. Тесты

- [x] 6.1 Расширить `acp_testing` fake agent/transport возможностью симулировать входящие `terminal/*` запросы и process lifecycle
- [x] 6.2 Тест: `terminal/create` запускает процесс немедленно, без создания approval-запроса, `terminalId` возвращён не дожидаясь завершения
- [x] 6.3 Тест: `terminal/create` с `cwd` вне working directory отклоняется без запуска процесса
- [x] 6.4 Тест: `terminal/output` возвращает накопленный вывод и `exitStatus: null` для работающего процесса
- [x] 6.5 Тест: `terminal/wait_for_exit` блокируется до завершения процесса и возвращает корректный `exitCode`/`signal`
- [x] 6.6 Тест: `terminal/kill` не освобождает `terminalId` — последующие `output`/`wait_for_exit`/`release` работают
- [x] 6.7 Тест: `terminal/release` освобождает ресурсы — последующие вызовы с этим `terminalId` возвращают ошибку "unknown terminal"
- [x] 6.8 Тест: вывод, превышающий `outputByteLimit`, обрезается с начала по границе символа, `truncated: true`
- [x] 6.9 Тест: disconnect сессии с активными процессами убивает их всех

## 7. Документация

- [x] 7.1 Обновить `docs/architecture/concurrency.md` — lifecycle terminal-процессов
- [x] 7.2 Правка `docs/architecture/permissions.md`/`AGENTS.md §10` выполнена в рамках `add-acp-fs-client-support` (задачи 6.1/6.2 там) и уже покрывает `terminal/*` — отдельного действия здесь не требуется

## 8. Проверка

- [x] 8.1 `fvm dart run melos run format`
- [x] 8.2 `fvm dart run melos run analyze`
- [x] 8.3 `fvm dart run melos run test`
