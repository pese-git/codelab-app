## Why

`tolerate-unknown-session-updates` пропускает `session/update` неизвестного вида (например, `usage_update`) и пишет об этом одну запись DEBUG без содержимого. При ручной проверке с агентом 0.88.0 по такой записи нельзя понять, *что именно* пропущено: видно только вид обновления. Разработчику нужен payload пропущенного обновления в логе, чтобы решить, нужна ли ему поддержка этого вида.

Класть payload в application-запись нельзя: sink `application` принимает уровень DEBUG и пишет в console, в `application.log` в release-сборке и (по opt-in) на удалённый сервер логов, а `docs/architecture/observability.md` §11 и AGENTS.md §16 запрещают включать сырые протокольные дампы в release по умолчанию. Для полного payload в проекте уже есть выделенный developer-only канал `category=protocol` (файл `protocol.log` выключен по умолчанию, Debug log в приложении захватывает его всегда).

## What Changes

- При пропуске `session/update` неизвестного вида в канал `category=protocol` пишется дополнительная запись с тем же текстом события, видом обновления, `sessionId` и **полным payload** уведомления; секреты маскируются общим процессором (как для остальных protocol-записей).
- Запись `category=application` (DEBUG, вид и `sessionId`, без содержимого) остаётся без изменений: она попадает в console, `application.log` и на сервер логов, поэтому payload в неё не добавляется.
- Состояние сессии, диагностики сессии и обработка известных видов не меняются.
- **BREAKING**: нет.

## Capabilities

### New Capabilities
_Нет._

### Modified Capabilities
- `acp-protocol-client`: сценарий «Незнакомый вид обновления пропускается» (требование «Жизненный цикл prompt turn») уточняется — payload пишется только в developer-only protocol-канал.

## Impact

- `packages/dart/acp_client_core`: `acp_client_application.dart` (`_skipUnsupportedSessionUpdate`); тест в `test/unsupported_session_updates_test.dart`.
- `docs/integrations/claude-code.md`: разд. 3.5 (где смотреть payload пропущенных обновлений).
- Порядок: change опирается на спеку из `tolerate-unknown-session-updates` (PR #9) — архивировать после неё.
