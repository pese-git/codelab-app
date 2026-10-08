## 1. Терпимость `session/update` в `acp_protocol`

- [x] 1.1 В `acp_method_codec.dart` `decodeAcpNotificationParams` для метода `session/update` выполняет decode внутри `tolerateUnknownRootFields`; для других уведомлений и для `decodeAcpParams`/`decodeAcpRequestParams` поведение не меняется
- [x] 1.2 Doc-комментарии у `decodeAcpNotificationParams` и `tolerateUnknownRootFields`: терпимость распространяется на `session/update`; запросы агента (`session/request_permission`, `fs/*`, `terminal/*`) остаются строгими
- [x] 1.3 В `session_update.dart` добавить множество известных видов обновления и функцию `String? unsupportedSessionUpdateKind(Object? params)` (возвращает вид, если params — объект, `update` — объект, `sessionUpdate` — строка вне множества; иначе `null`); экспортируется через барелл пакета
- [x] 1.4 `SessionUpdate.fromJson` для неизвестного вида по-прежнему бросает `invalidShape`

## 2. Пропуск неизвестного вида в `acp_client_core`

- [x] 2.1 `_handleSessionUpdate`: если `unsupportedSessionUpdateKind(notification.params)` не `null` — записать DEBUG в структурный логгер (`component=protocol`, `session_id`, `sessionUpdate`; без содержимого и без `_recordDiagnostic`) и вернуться без изменения состояния
- [x] 2.2 Остальные ошибки decode обрабатываются как раньше (диагностика `error`, обновление не применяется)

## 3. Тесты `acp_protocol`

- [x] 3.1 `decodeAcpNotificationParams`: `agent_message_chunk` с `messageId` на корне `update` decode'ится, текст сохранён; лишнее поле на корне уведомления и во вложенных объектах (content-блок, tool call, plan entry) тоже игнорируется
- [x] 3.2 Остаётся ошибкой в терпимом decode: отсутствие `content`, неверный тип поля, неизвестный `type` content-блока, неизвестный `status` tool call, `update` не объект
- [x] 3.3 Остаётся строгим: `decodeAcpParams(sessionUpdateMethod, …)` и `SessionUpdate.fromJson` с лишним полем; `decodeAcpNotificationParams`/`decodeAcpRequestParams` для `session/request_permission`, `fs/*`, `terminal/*` с лишним полем; тесты существующей строгости не ломаются
- [x] 3.4 Терпимость не «протекает» после `decodeAcpNotificationParams` (в том числе после брошенного исключения)
- [x] 3.5 `unsupportedSessionUpdateKind`: `usage_update` → `usage_update`; известные виды, не-объект, нет `update`, нет `sessionUpdate`, не-строка → `null`; тест-страж синхронности: каждый вид из множества не приводит к «is not supported» в `SessionUpdate.fromJson`, выдуманный — приводит

## 4. Тесты `acp_client_core`

- [x] 4.1 Последовательность реального 0.88.0 (`available_commands_update`, `usage_update`, `agent_message_chunk` с `messageId`, `usage_update` с `cost`, ответ `session/prompt` с `stopReason: end_turn`): текст чанка появляется в сессии, turn завершается, диагностик уровня error нет, состояние от `usage_update` не меняется
- [x] 4.2 Пропуск `usage_update` пишет ровно одну DEBUG-запись без содержимого и не добавляет запись в `diagnostics` сессии
- [x] 4.3 Структурно невалидное обновление известного вида по-прежнему даёт диагностику `error` и не меняет сессию

## 5. Документация и проверка

- [x] 5.1 `docs/integrations/claude-code.md`: разд. 3.5 (`usage_update`, `messageId`), разд. 4 (таблица строгости), разд. 5.1 (ограничение снято для `session/update`), разд. 1 (prompt turn на 0.88.0 проверен)
- [x] 5.2 `fvm dart format`, `fvm dart analyze`, `fvm dart test` для `acp_protocol`, `acp_client_core`, `acp_transports`; `fvm flutter test` для `codelab_app`
- [x] 5.3 Повторный прогон реального prompt turn на 0.88.0 через `scripts`-рецепт из docs (сырые сообщения → `decodeAcpNotificationParams`): все 10 сообщений принимаются или пропускаются
- [x] 5.4 `openspec validate tolerate-unknown-session-updates --strict`
