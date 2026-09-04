## 1. Протокольные модели (acp_protocol)

- [x] 1.1 Создать `packages/dart/acp_protocol/lib/src/acp/fs.dart` с типизированными моделями `ReadTextFileRequest`/`ReadTextFileResponse`/`WriteTextFileRequest`/`WriteTextFileResponse` (freezed, `fromJson`/`toJson`), по образцу `permission.dart`/`session.dart`
- [x] 1.2 Зарегистрировать `fs/read_text_file` и `fs/write_text_file` в `acpMethodRegistry` (`acp_method_codec.dart`) как `AcpMethodDefinition.request`
- [x] 1.3 Экспортировать новые модели через `lib/acp_protocol.dart`
- [x] 1.4 Unit-тесты кодирования/декодирования для обеих моделей, включая невалидные формы (не-абсолютный path, отсутствующие обязательные поля)

## 2. Domain и application (acp_client_core)

- [x] 2.1 Добавить типизированные ошибки для fs-операций (path escape, IO failure) в `packages/dart/acp_client_core/lib/src/domain/`
- [x] 2.2 Реализовать application-level path resolution: канонизация `path` из запроса и проверка принадлежности working directory активной сессии, до похода в infrastructure
- [x] 2.3 Подключить обработку входящих `fs/read_text_file`/`fs/write_text_file` в `AcpClientApplication` (диспетчеризация server→client запросов): проверка working directory → вызов infrastructure adapter → ответ, без approval-шага

## 3. Infrastructure (platform adapter)

- [x] 3.1 Создать узкий adapter для текстового файлового I/O в `apps/codelab_app/lib/core/platform/` (чтение с `line`/`limit`, запись с созданием файла при отсутствии), инкапсулирующий `dart:io` File
- [x] 3.2 Подключить adapter в composition root (CherryPick) и передать его в `AcpClientApplication`/соответствующий use case через порт/интерфейс

## 4. Capabilities announcement

- [x] 4.1 Изменить построение `InitializeRequest` в `acp_client_application.dart`: отправлять `clientCapabilities.fs.readTextFile`/`writeTextFile` как `true`, если соответствующие обработчики зарегистрированы, иначе `false`
- [x] 4.2 Тест: `initialize` отправляет корректные `clientCapabilities.fs` при полной и при частичной поддержке методов

## 5. Тесты

- [x] 5.1 Расширить `acp_testing` fake agent/transport возможностью симулировать входящие `fs/read_text_file`/`fs/write_text_file` запросы (уже поддержано существующим `FakeAcpTransport.emitInbound` — не потребовалось нового кода, только тесты, использующие его так же, как для `session/request_permission`)
- [x] 5.2 Тест: успешное чтение файла внутри working directory
- [x] 5.3 Тест: чтение с `path` вне working directory отклоняется без обращения к файловой системе
- [x] 5.4 Тест: успешная запись файла внутри working directory выполняется немедленно, без создания approval-запроса/ожидания решения пользователя
- [x] 5.5 Тест: запись с `path` вне working directory отклоняется без обращения к файловой системе
- [x] 5.6 Тест: IO-ошибка при записи (мок файловой системы) возвращается агенту как типизированная ошибка, не приводя к падению

## 6. Документация (обязательна для непротиворечивости архитектурных документов)

- [x] 6.1 Обновить `docs/architecture/permissions.md` §2: явно исключить `fs/*`/`terminal/*` (ACP client-side RPC) из списка операций, требующих client-side approval-гейта, с обоснованием (протокол делает permission ответственностью агента; working-directory containment — компенсирующий контроль)
- [x] 6.2 Обновить `AGENTS.md §10`: добавить явную оговорку/исключение для ACP `fs/*`/`terminal/*` RPC-методов относительно требования "Опасные действия agent ДОЛЖНЫ проходить через application-level permission policy"

## 7. Проверка

- [x] 7.1 `fvm dart run melos run format`
- [x] 7.2 `fvm dart run melos run analyze`
- [x] 7.3 `fvm dart run melos run test`
