## 1. Scoped-терпимость в `acp_protocol`

- [ ] 1.1 В `packages/dart/acp_protocol/lib/src/acp/acp_validation.dart` добавить zone-ключ и функцию `T tolerateUnknownRootFields<T>(T Function() decode)`, которая выполняет `decode` в `Zone.current.fork(zoneValues: {…: true})`
- [ ] 1.2 `requireOnlyRootKeys` пропускает проверку ключей, когда флаг zone выставлен (`Zone.current[…] == true`); вне zone поведение не меняется
- [ ] 1.3 Doc-комментарии у обеих функций: что терпится (только лишние корневые ключи), что НЕ терпится (не-объект, обязательные поля, типы, discriminators), почему zone, а не флаг/параметр (см. design.md, Decisions)

## 2. Подключение к `decodeAcpResult`

- [ ] 2.1 В `acp_method_codec.dart` `decodeAcpResult` вызывает `definition.decodeResult(result)` внутри `tolerateUnknownRootFields` (`decodeAcpResponseResult` идёт через него — отдельной правки не требует)
- [ ] 2.2 Doc-комментарий `decodeAcpResult`: терпимость привязана к декодированию result; прямой `Model.fromJson(...)` и `decodeAcpParams`/`decodeAcpRequestParams`/`decodeAcpNotificationParams` остаются строгими
- [ ] 2.3 Убедиться, что `requireAcpCapabilityObject` и существующие тесты `fix-acp-capability-forward-compat` остаются рабочими без изменений

## 3. Тесты `acp_protocol`

- [ ] 3.1 `session/new`: результат из реального ответа `claude-code-acp` (`sessionId`, `models: {availableModels, currentModelId}`, `modes`) decode'ится через `decodeAcpResult`, `sessionId` и `modes` прочитаны корректно
- [ ] 3.2 Незнакомое поле во вложенных объектах результата (например, внутри элемента `modes.availableModes[]` и внутри `configOptions[]`) тоже игнорируется
- [ ] 3.3 `initialize`: незнакомое поле на корне результата decode'ится через `decodeAcpResult`, а `InitializeResponse.fromJson` напрямую с тем же полем по-прежнему бросает `invalidShape`
- [ ] 3.4 Остаётся ошибкой внутри терпимого decode: не-объект вместо result, отсутствие обязательного поля (`sessionId`), неверный тип, неизвестный `stopReason` в `session/prompt`
- [ ] 3.5 Остаётся строгим: `decodeAcpParams` для `session/prompt`/`initialize` с лишним полем; `session/update` с лишним полем на корне и во вложенном `config_option_update`
- [ ] 3.6 Терпимость не «протекает»: после `decodeAcpResult` (в том числе после брошенного исключения) прямой `fromJson` с лишним полем снова строгий
- [ ] 3.7 Существующие тесты строгой валидации (`acp_method_codec_test`, `protocol_conformance_test`, `session_test`, `prompt_test`, `fs_test`, `terminal_test`) не сломаны

## 4. Тест `acp_client_core`

- [ ] 4.1 Регрессионный тест (на `FakeAcpTransport`): `createSession` с ответом `session/new`, содержащим `models`, завершается успешно, сессия создана, `sessionId` из ответа

## 5. Проверка

- [ ] 5.1 Ручная проверка в приложении с настоящим `@zed-industries/claude-code-acp` (запуск без `CLAUDECODE`: `env -u CLAUDECODE fvm flutter run -d macos`): Connect → открыть проект → `/new` — сессия создаётся, ошибки `unsupported root field "models"` нет
- [ ] 5.2 `fvm dart format`, `fvm dart analyze`, `fvm dart test` для `acp_protocol`, `acp_client_core`, `acp_transports`; `fvm flutter test` для `codelab_app`
- [ ] 5.3 `openspec validate tolerate-unknown-agent-response-fields --strict`
- [ ] 5.4 Дождаться мёржа `fix-acp-capability-forward-compat` (PR #2) и архивировать change после него (см. design.md, Migration Plan)
