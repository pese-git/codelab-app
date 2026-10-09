## 1. Код

- [x] 1.1 `_skipUnsupportedSessionUpdate`: помимо application-записи (без содержимого) писать через `_protocolTraceLogger` запись DEBUG с тем же текстом, `sessionUpdate`, `session_id` и `payload` (params уведомления)
- [x] 1.2 Doc-комментарий: почему payload только в protocol-канале (release-правило `observability.md` §11)

## 2. Тесты `acp_client_core`

- [x] 2.1 При включённой трассировке есть запись `category=protocol` с `payload` пропущенного обновления; значение под чувствительным ключом (например, `secret`) замаскировано
- [x] 2.2 Запись `category=application` по-прежнему без payload и без содержимого; в application-категорию payload не попадает
- [x] 2.3 Состояние сессии и диагностики не меняются (существующие тесты зелёные)

## 3. Документация и проверка

- [x] 3.1 `docs/integrations/claude-code.md` разд. 3.5: где смотреть payload пропущенных обновлений (Debug log, категория protocol; `protocol.log`)
- [x] 3.2 `fvm dart format`, `fvm dart analyze`, `fvm dart test` для `acp_client_core`; `fvm flutter test` для `codelab_app`
- [x] 3.3 `openspec validate trace-skipped-session-update-payload --strict`
