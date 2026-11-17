# acp-terminal-client Specification

## Purpose
Клиентская сторона ACP-методов `terminal/*` (`create`, `output`, `wait_for_exit`, `kill`, `release`): CodeLab запускает команды агента и управляет жизненным циклом процесса. Отдельного подтверждения клиент не запрашивает — разрешение остаётся решением агента (`AGENTS.md` §10, исключение для `terminal/*`); компенсирующий контроль — ограничение `cwd` рабочей директорией сессии. Вывод ограничивается `outputByteLimit`, активные процессы завершаются при отключении и dispose, запуск процессов изолирован за platform-boundary. Нормативный источник — `docs/protocols/acp/protocol/10-Terminal.md`.
## Requirements
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
CodeLab SHALL завершать (kill) все активные terminal-процессы ACP-сессии при disconnect этой сессии и все активные terminal-процессы всех сессий при завершении приложения, в том числе при выходе по запросу ОС (Cmd+Q, закрытие последнего окна), когда дерево виджетов не размонтируется (agent-workbench-ui «Выход из приложения завершает процессы клиента»).

При `dispose` ядра ACP-клиента завершение terminal-процессов и закрытие транспорта SHALL идти параллельно, а `dispose` SHALL ждать завершения обоих (design.md change `add-client-process-shutdown-on-exit`, D4). Каждое завершение — по требованию «Принудительное завершение terminal-процесса». `dispose` SHALL также дожидаться запусков `terminal/create`, начатых до него: процесс, запущенный после очистки реестра, SHALL завершаться и SHALL NOT регистрироваться (D12). После этого реестр SHALL быть пуст, а повторный `dispose` SHALL ждать то же закрытие и SHALL NOT слать сигналы. Завершение с непустым реестром SHALL записывать событие `terminal_processes_killed` с полями `count` и `reason` (`connection_closed` или `dispose`), без команд, аргументов, путей и идентификаторов терминалов (D6). Событие SHALL записываться после того, как сигналы отправлены; сбой записи SHALL NOT мешать завершению процессов (D15).

#### Scenario: Сессия отключается с активными процессами
- **WHEN** ACP-сессия переходит в disconnected при наличии `terminalId` в состоянии `running`
- **THEN** CodeLab убивает эти процессы, не оставляя висящих child-процессов

#### Scenario: Приложение закрывается с активными процессами
- **WHEN** приложение завершает работу при наличии активных terminal-процессов в любой сессии
- **THEN** CodeLab убивает все эти процессы перед завершением

#### Scenario: Выход из приложения по запросу ОС
- **WHEN** пользователь нажимает Cmd+Q при работающем terminal-процессе внешнего агента
- **THEN** процесс завершён до выхода процесса CodeLab, в журнале есть `terminal_processes_killed` с `count: 1` и `reason: dispose`

#### Scenario: terminal/create запускается во время dispose
- **WHEN** агент прислал `terminal/create`, и `dispose` ядра клиента вызван, пока процесс ещё запускается
- **THEN** после запуска процесс завершается, `terminalId` не регистрируется, ответ на `terminal/create` не отправляется, `dispose` завершается после завершения процесса

#### Scenario: Сбой журнала не оставляет процессы живыми
- **WHEN** запись события `terminal_processes_killed` бросает исключение при `dispose` с работающим terminal-процессом
- **THEN** процесс всё равно завершён, а `dispose` завершается без исключения

#### Scenario: Завершение процессов не задерживает закрытие транспорта
- **WHEN** `dispose` вызывается при работающем terminal-процессе, игнорирующем `SIGTERM`, и подключённом stdio-агенте
- **THEN** закрытие транспорта начинается, не дожидаясь завершения terminal-процесса, а `dispose` завершается после того, как завершены оба

### Requirement: Изоляция process execution за platform-boundary
Реализация запуска и управления процессами SHALL находиться в infrastructure-слое приложения и SHALL NOT быть доступна напрямую из `domain`, `application` или `presentation`, и SHALL оставаться независимой от `TerminalProcessFactory`, используемого локальной интерактивной terminal-панелью.

#### Scenario: Domain/application не содержат прямых вызовов dart:io Process
- **WHEN** запускается статический анализ `packages/dart/codelab_client_acp`
- **THEN** пакет не импортирует `dart:io` для управления процессами напрямую, а обращается к ним через порт/интерфейс, реализуемый в `apps/codelab_desktop`

### Requirement: Принудительное завершение terminal-процесса
Завершение terminal-процесса — по `terminal/kill`, `terminal/release`, при disconnect и `dispose` — SHALL сначала посылать процессу `SIGTERM`. Если процесс не вышел за 2 s, SHALL посылаться `SIGKILL` (design.md change `add-client-process-shutdown-on-exit`, D4). Операция завершения SHALL заканчиваться после выхода процесса или после отправки `SIGKILL`, не дольше чем примерно через 2 s. Ответ на `terminal/kill` SHALL отправляться после неё.

Статус выхода SHALL выводиться из результата выхода, который сообщила ОС, а не из того, какой сигнал CodeLab послал (design.md change `add-client-process-shutdown-on-exit`, D14):
- процесс вышел с кодом выхода — `exitCode` равен этому коду (не меньше 0), `signal` — `null`, даже если перед этим процессу посылался `SIGTERM`;
- процесс завершён сигналом — `exitCode` равен `null`, `signal` — имя этого сигнала (`SIGTERM`, `SIGKILL`; для номеров, различающихся между платформами, — `SIG` и номер).

`exitCode` в `TerminalExitStatus` SHALL NOT быть отрицательным (`docs/protocols/acp/protocol/17-Schema.md`, `TerminalExitStatus`: `minimum: 0`). Завершение уже вышедшего процесса SHALL оставаться no-op и SHALL NOT менять зафиксированный статус. Сигнал получает только сам процесс команды, его потомки — нет (design.md, Q2).

#### Scenario: Процесс выходит по SIGTERM
- **WHEN** агент вызывает `terminal/kill` для процесса, который завершается по `SIGTERM`
- **THEN** ответ приходит после выхода процесса, `terminal/wait_for_exit` возвращает `exitCode: null` и `signal: SIGTERM`, `SIGKILL` не отправлялся

#### Scenario: Процесс игнорирует SIGTERM
- **WHEN** агент вызывает `terminal/kill` для процесса, игнорирующего `SIGTERM`
- **THEN** через 2 s процесс получает `SIGKILL`, ответ на `terminal/kill` приходит не позже чем примерно через 2 s, процесс завершён, `terminal/wait_for_exit` возвращает `exitCode: null` и `signal: SIGKILL`

#### Scenario: Процесс обрабатывает SIGTERM и выходит с кодом
- **WHEN** агент вызывает `terminal/kill` для процесса, который по `SIGTERM` сам завершается с кодом 0 (`trap 'exit 0' TERM`)
- **THEN** `terminal/wait_for_exit` возвращает `exitCode: 0` и `signal: null`, `SIGKILL` не отправлялся

#### Scenario: Ни один статус выхода не содержит отрицательного кода
- **WHEN** terminal-процесс завершён сигналом — по `terminal/kill` или извне
- **THEN** ответы `terminal/output` и `terminal/wait_for_exit` содержат `exitCode: null` и имя сигнала, а не отрицательный `exitCode`

#### Scenario: Повторное завершение
- **WHEN** `terminal/kill` вызывается для процесса, уже завершённого предыдущим `terminal/kill`
- **THEN** сигналы не отправляются, ошибки нет, статус выхода не меняется

### Requirement: Ответ на terminal-запрос только в соединение запроса
Ответ на `terminal/create`, `terminal/output`, `terminal/wait_for_exit`, `terminal/kill` и `terminal/release` — и результат, и ошибка — SHALL отправляться только в то соединение, из которого пришёл запрос (design.md change `add-client-process-shutdown-on-exit`, D15). Если за время обработки транспорт заменён (Connect, Reconnect) или ядро ACP-клиента закрыто, CodeLab SHALL NOT отправлять ответ и SHALL записывать в журнал событие отброшенного устаревшего результата (`event_ignored`, `reason: stale_generation`) с поколением соединения запроса, без команды и путей.

#### Scenario: Reconnect во время terminal/kill
- **WHEN** агент вызвал `terminal/kill` для процесса, игнорирующего `SIGTERM`, и до ответа пользователь выполняет Reconnect к новому агенту
- **THEN** процесс завершён, ответ на `terminal/kill` не отправляется ни старому, ни новому агенту, в журнале есть `event_ignored` с `reason: stale_generation`

#### Scenario: Reconnect во время terminal/wait_for_exit
- **WHEN** агент ждёт `terminal/wait_for_exit`, и транспорт заменяется до выхода процесса
- **THEN** процесс завершён заменой соединения, ответ на `terminal/wait_for_exit` новому агенту не отправляется

#### Scenario: Reconnect во время запуска terminal/create
- **WHEN** агент прислал `terminal/create`, и транспорт заменяется, пока процесс запускается
- **THEN** запущенный процесс завершается, `terminalId` не регистрируется, ответ новому агенту не отправляется

