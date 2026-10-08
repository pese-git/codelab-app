## Context

`session/update` декодируется в одном месте клиента: `AcpClientApplication._handleSessionUpdate` → `decodeAcpNotificationParams(notification)` → `SessionNotification.fromJson` → `SessionUpdate.fromJson`. Корневые ключи там проверяет `requireOnlyRootKeys` (`allowedKeys` — объединение полей всех видов обновлений), а неизвестный `sessionUpdate` даёт `JsonRpcProtocolException.invalidShape('sessionUpdate "…" is not supported.')`. Любая ошибка превращается в `_recordDiagnostic(severity: error)` и обновление теряется.

`tolerate-unknown-agent-response-fields` ввёл `tolerateUnknownRootFields` (zone-значение) и применил его в `decodeAcpResult`. Механизм готов; здесь он подключается ко второму входу — уведомлению `session/update`.

Реальные сообщения 0.88.0 (лог `prompt_turn_0_88_0.log`, 2026-10-09): `agent_message_chunk` с `messageId` на корне `update`; `usage_update {used, size, cost?, _meta}` (видов `usage_update` нет в `docs/acp/protocol/17-Schema.md`); `available_commands_update` — штатный.

## Goals / Non-Goals

**Goals:**
- Ответ агента (`agent_message_chunk`) доходит до таймлайна, даже если агент добавил к нему поля, которых нет в вендоренной схеме.
- Неизвестный вид обновления не порождает ошибок и не меняет состояние сессии.
- Строгость сохраняется там, где она защищает: запросы агента (`session/request_permission`, `fs/*`, `terminal/*`), исходящие параметры, структура известных полей.

**Non-Goals:**
- Не поддерживаем `messageId` и `usage_update` как функциональность (AGENTS.md §3.4: не придумываем семантику ACP).
- Не меняем `session/request_permission`, `fs/*`, `terminal/*`: на них нужен ответ, а `permission` и файловая система — зона безопасности (AGENTS.md §10); неожиданное поле там остаётся сигналом ошибки.
- Не меняем публичный API `acp_protocol` сверх одной функции-предиката (см. ниже) и не добавляем вариант в `SessionUpdate`.

## Decisions

- **Терпимость включается в `decodeAcpNotificationParams` для метода `session/update`**, через уже существующий `tolerateUnknownRootFields`. Прямой `decodeAcpParams`, `decodeAcpRequestParams` и `Model.fromJson` остаются строгими, как и тесты, которые на них опираются. Клиент использует именно `decodeAcpNotificationParams`, поэтому продакшен-поведение меняется, а низкоуровневые вызовы — нет.
  - *Альтернатива — терпимость на уровне отдельных моделей `ContentChunk`/`ToolCall`:* ~10 мест, легко пропустить новый вид обновления; общие вложенные модели уже решены zone-подходом.
- **Неизвестный вид обновления определяется предикатом `unsupportedSessionUpdateKind(params)`** в `session_update.dart`: возвращает значение `sessionUpdate`, если params — объект, `update` — объект, а его `sessionUpdate` — строка вне множества известных видов; иначе `null`. Клиент вызывает его до decode и пропускает такое обновление.
  - *Альтернатива А — новый вариант `SessionUpdate.unknown`:* заставляет обновить все исчерпывающие `switch` (state machine, UI), хотя состояние неизвестное обновление не меняет; размывает типизацию.
  - *Альтернатива Б — подкласс исключения/новое значение `JsonRpcProtocolErrorKind`:* `JsonRpcProtocolException` — `final class` (не наследуется), новое значение enum затрагивает исчерпывающие `switch` в `AcpProtocolError.fromException` и публичный API ради одного случая.
  - Множество известных видов дублирует `switch` в `SessionUpdate.fromJson`; рассинхрон ловит тест (каждый вид из множества не даёт ошибки «is not supported», выдуманный — даёт).
  - Строгий путь не меняется: `SessionUpdate.fromJson` с неизвестным видом по-прежнему бросает `invalidShape`.
- **Логирование.** Пропущенный вид обновления пишется одной записью DEBUG прямо в структурный логгер (`component=protocol`, `session_id`, поле `sessionUpdate`; без содержимого — там может быть текст пользователя). Через `_recordDiagnostic` НЕ пишем: он добавляет запись в список диагностик каждой сессии и в панель, а `usage_update` приходит несколько раз за turn — это зашумило бы Debug log и вытеснило полезные записи из ограниченного буфера.
- **Что терпим, а что нет.** Только лишние корневые ключи объектов внутри `session/update` и целиком неизвестный вид обновления. Не-объект, отсутствие обязательного поля, неверный тип, неизвестный discriminator внутри известного вида (`ContentBlock.type`, `ToolCallStatus`, `ToolKind`, …) — по-прежнему ошибка с диагностикой `error`.

## Risks / Trade-offs

- [Опечатка агента в имени необязательного поля внутри известного обновления теряет это поле молча] → обязательные поля остаются обязательными; теряется только то, чего CodeLab не знает; игнорируемые поля не логируются (шум на каждый chunk).
- [Терпимость не должна ослабить безопасность] → `session/update` не несёт решений о правах и доступе к ФС: разрешения идут через `session/request_permission`, операции — через `fs/*`/`terminal/*`, все они остаются строгими. Tool call из `session/update` только отображается и классифицируется (`ApprovalPolicy`), его неизвестные поля не читаются.
- [Рассинхрон множества известных видов с `switch`] → тест-страж (см. выше).
- [Тот же агент может прислать другие нестандартные запросы/уведомления] → запросы получают `-32601` (change `reply-method-not-found-to-unknown-agent-requests`), нестандартные уведомления игнорируются.

## Migration Plan

Правка внутри `acp_protocol` и `acp_client_core`, без изменения данных и публичных контрактов отправляемых сообщений. Откат — revert коммита.

## Open Questions

- Нужна ли индикация использования контекста по `usage_update` (прогресс токенов, стоимость)? Отдельный change по запросу продукта; сначала нужно, чтобы поле попало в вендоренную спеку или было оформлено как расширение.
