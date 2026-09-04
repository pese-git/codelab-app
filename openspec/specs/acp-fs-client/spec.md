# acp-fs-client Specification

## Purpose
TBD - created by archiving change add-acp-fs-client-support. Update Purpose after archive.
## Requirements
### Requirement: Поддержка fs/read_text_file
CodeLab SHALL реализовывать входящий ACP-метод `fs/read_text_file`, если и только если `ClientCapabilities.fs.readTextFile` заявлена как `true` при `initialize`, и SHALL возвращать содержимое файла по абсолютному пути с учётом опциональных `line`/`limit`.

#### Scenario: Валидный запрос на чтение файла
- **WHEN** агент отправляет `fs/read_text_file` с абсолютным `path`, находящимся внутри working directory активной сессии
- **THEN** CodeLab читает файл и возвращает `ReadTextFileResponse` с его текстовым содержимым (с учётом `line`/`limit`, если заданы)

#### Scenario: Путь выходит за пределы working directory
- **WHEN** агент отправляет `fs/read_text_file` с `path`, который после канонизации не находится внутри working directory активной сессии
- **THEN** CodeLab отклоняет запрос типизированной protocol/security-ошибкой и не читает файл

#### Scenario: Файл не существует или недоступен
- **WHEN** `path` указывает на несуществующий файл или файл без прав на чтение
- **THEN** CodeLab отклоняет запрос типизированной ошибкой, отражающей причину IO-сбоя, не приводя к падению приложения

### Requirement: Поддержка fs/write_text_file без client-side approval
CodeLab SHALL реализовывать входящий ACP-метод `fs/write_text_file`, если и только если `ClientCapabilities.fs.writeTextFile` заявлена как `true` при `initialize`, и SHALL выполнять запись сразу после прохождения проверки working directory, без собственного approval-запроса — в соответствии с ACP, где `session/request_permission` является опциональным (`MAY`) решением агента, а не обязательным протокольным шагом перед `fs/write_text_file`.

#### Scenario: Валидный запрос на запись файла
- **WHEN** агент отправляет `fs/write_text_file` с абсолютным `path` внутри working directory активной сессии и текстовым `content`
- **THEN** CodeLab создаёт файл (если он не существует) или перезаписывает его содержимым из запроса и возвращает пустой `WriteTextFileResponse`, не запрашивая подтверждения пользователя

#### Scenario: Путь выходит за пределы working directory
- **WHEN** агент отправляет `fs/write_text_file` с `path`, который после канонизации не находится внутри working directory активной сессии
- **THEN** CodeLab отклоняет запрос типизированной protocol/security-ошибкой и не выполняет запись

#### Scenario: Ошибка записи
- **WHEN** файловая система возвращает ошибку при попытке записи (например, нет прав на уровне ОС, диск заполнен)
- **THEN** CodeLab отклоняет запрос типизированной ошибкой, отражающей причину IO-сбоя, не приводя к падению приложения

### Requirement: Изоляция файлового I/O за platform-boundary
Реализация чтения/записи файлов SHALL находиться в infrastructure-слое приложения и SHALL NOT быть доступна напрямую из `domain`, `application` или `presentation`.

#### Scenario: Domain/application не содержат прямых вызовов dart:io
- **WHEN** запускается статический анализ `packages/dart/acp_client_core`
- **THEN** пакет не импортирует `dart:io` для файловых операций напрямую, а обращается к ним через порт/интерфейс, реализуемый в `apps/codelab_app`

