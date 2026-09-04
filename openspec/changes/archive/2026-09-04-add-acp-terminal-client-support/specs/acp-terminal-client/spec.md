## ADDED Requirements

### Requirement: Поддержка terminal/create без client-side approval
CodeLab SHALL реализовывать входящий ACP-метод `terminal/create`, если и только если `ClientCapabilities.terminal` заявлена как `true` при `initialize`, и SHALL запускать процесс сразу после прохождения проверки working directory, без собственного approval-запроса — в соответствии с ACP, где `session/request_permission` является опциональным (`MAY`) решением агента, а не обязательным протокольным шагом перед `terminal/create`.

#### Scenario: Команда запускается немедленно
- **WHEN** агент отправляет `terminal/create` с `command`/`args`, и `cwd` (если задан) находится внутри working directory активной сессии
- **THEN** CodeLab запускает процесс в этом `cwd` (или в working directory сессии по умолчанию) и возвращает `CreateTerminalResponse` с новым `terminalId`, не запрашивая подтверждения пользователя и не дожидаясь завершения команды

#### Scenario: cwd выходит за пределы working directory
- **WHEN** `terminal/create` указывает `cwd`, который после канонизации не находится внутри working directory активной сессии
- **THEN** CodeLab отклоняет запрос типизированной protocol/security-ошибкой и не запускает процесс

#### Scenario: Команда не может быть запущена
- **WHEN** указанный `command` не найден или не может быть исполнен (ошибка ОС)
- **THEN** CodeLab отклоняет запрос типизированной ошибкой, отражающей причину сбоя, не приводя к падению приложения

### Requirement: Жизненный цикл terminal-процесса
CodeLab SHALL хранить состояние каждого созданного `terminalId` в рамках соответствующей ACP-сессии как явную state machine (`running`, `exited`), и SHALL корректно обрабатывать `terminal/output`, `terminal/wait_for_exit`, `terminal/kill`, `terminal/release` относительно этого состояния.

#### Scenario: Получение вывода работающего процесса
- **WHEN** агент вызывает `terminal/output` для `terminalId` работающего процесса
- **THEN** CodeLab возвращает накопленный вывод, `truncated: false` (если лимит не превышен) и `exitStatus: null`

#### Scenario: Ожидание завершения
- **WHEN** агент вызывает `terminal/wait_for_exit` для существующего `terminalId`
- **THEN** CodeLab возвращает управление только после завершения процесса, с его `exitCode`/`signal`

#### Scenario: Kill не освобождает terminalId
- **WHEN** агент вызывает `terminal/kill` для работающего процесса
- **THEN** CodeLab завершает процесс, но `terminalId` остаётся валидным для последующих `terminal/output`/`terminal/wait_for_exit`/`terminal/release`

#### Scenario: Kill уже завершившегося процесса — не ошибка
- **WHEN** агент вызывает `terminal/kill` для `terminalId`, чей процесс уже завершился естественным образом
- **THEN** CodeLab обрабатывает это как no-op, не возвращая ошибку и не изменяя уже зафиксированный exit-статус

#### Scenario: Release освобождает ресурсы
- **WHEN** агент вызывает `terminal/release` для существующего `terminalId`
- **THEN** CodeLab завершает процесс (если он ещё работает), освобождает связанные ресурсы, и последующие вызовы `terminal/*` с этим `terminalId` возвращают ошибку "unknown terminal"

#### Scenario: Обращение к неизвестному или уже освобождённому terminalId
- **WHEN** `terminal/output`, `terminal/wait_for_exit` или `terminal/kill` вызваны с `terminalId`, который не существует в рамках сессии или уже был освобождён
- **THEN** CodeLab возвращает типизированную ACP-ошибку, не приводя к падению приложения

### Requirement: Ограничение вывода по outputByteLimit
CodeLab SHALL ограничивать накопленный вывод terminal-процесса значением `outputByteLimit` из `terminal/create`, если оно задано, обрезая буфер с начала по границе допустимого символа.

#### Scenario: Вывод превышает лимит
- **WHEN** суммарный вывод процесса превышает заданный `outputByteLimit`
- **THEN** CodeLab обрезает начало буфера, чтобы уместиться в лимит, сохраняя валидность строки на границе символа, и `terminal/output` возвращает `truncated: true`

### Requirement: Завершение активных процессов при disconnect/dispose
CodeLab SHALL завершать (kill) все активные terminal-процессы ACP-сессии при disconnect этой сессии, и все активные terminal-процессы всех сессий при завершении приложения.

#### Scenario: Сессия отключается с активными процессами
- **WHEN** ACP-сессия переходит в disconnected при наличии `terminalId` в состоянии `running`
- **THEN** CodeLab убивает эти процессы, не оставляя висящих child-процессов

#### Scenario: Приложение закрывается с активными процессами
- **WHEN** приложение завершает работу при наличии активных terminal-процессов в любой сессии
- **THEN** CodeLab убивает все эти процессы перед завершением

### Requirement: Изоляция process execution за platform-boundary
Реализация запуска и управления процессами SHALL находиться в infrastructure-слое приложения и SHALL NOT быть доступна напрямую из `domain`, `application` или `presentation`, и SHALL оставаться независимой от `TerminalProcessFactory`, используемого локальной интерактивной terminal-панелью.

#### Scenario: Domain/application не содержат прямых вызовов dart:io Process
- **WHEN** запускается статический анализ `packages/dart/acp_client_core`
- **THEN** пакет не импортирует `dart:io` для управления процессами напрямую, а обращается к ним через порт/интерфейс, реализуемый в `apps/codelab_app`
