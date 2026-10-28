## MODIFIED Requirements

### Requirement: Поддержка fs/read_text_file
CodeLab SHALL реализовывать входящий ACP-метод `fs/read_text_file`, если и только если `ClientCapabilities.fs.readTextFile` заявлена как `true` при `initialize`, и SHALL возвращать содержимое файла по абсолютному пути с учётом опциональных `line`/`limit`. Отсутствующий файл SHALL отклоняться JSON-RPC ошибкой `-32002` «Resource not found» (ACP `ErrorCode` resource_not_found, `docs/protocols/acp/protocol/17-Schema.md`): по этому коду агент отличает «файла нет» от прочих сбоев и создаёт файл (design.md change `add-dart-agent-acp-server`, D15).

#### Scenario: Валидный запрос на чтение файла
- **WHEN** агент отправляет `fs/read_text_file` с абсолютным `path`, находящимся внутри working directory активной сессии
- **THEN** CodeLab читает файл и возвращает `ReadTextFileResponse` с его текстовым содержимым (с учётом `line`/`limit`, если заданы)

#### Scenario: Путь выходит за пределы working directory
- **WHEN** агент отправляет `fs/read_text_file` с `path`, который после канонизации не находится внутри working directory активной сессии
- **THEN** CodeLab отклоняет запрос типизированной protocol/security-ошибкой и не читает файл

#### Scenario: Файл не существует
- **WHEN** `path` указывает на несуществующий файл
- **THEN** CodeLab отклоняет запрос ошибкой `-32002` «Resource not found», не приводя к падению приложения

#### Scenario: Файл недоступен
- **WHEN** `path` указывает на файл без прав на чтение или чтение срывается
- **THEN** CodeLab отклоняет запрос типизированной ошибкой, отражающей причину IO-сбоя, не приводя к падению приложения
