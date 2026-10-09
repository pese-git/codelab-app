## Context

`_skipUnsupportedSessionUpdate` пишет одну запись `component=protocol`, `category=application`, уровень DEBUG. Sink `application` (default `minLevel = debug`) пишет в console (debug-сборка), в `application.log` (release) и в `RemoteSyncLogOutput` (opt-in). Полный payload каждого входящего сообщения и так трассируется в `category=protocol` (`_traceProtocolMessage`), но отдельной записью `protocol_message`, не связанной с событием пропуска.

## Goals / Non-Goals

**Goals:** по событию пропуска видеть payload пропущенного обновления, не нарушая правило «сырые дампы не попадают в release по умолчанию».

**Non-Goals:** не меняем состав application-записи; не добавляем payload в диагностики сессии и Debug-панель через `_recordDiagnostic`; не меняем конфигурацию sink'ов.

## Decisions

- **Payload только в `category=protocol`.** Вторая запись с тем же текстом `Skipped unsupported ACP session update.` пишется через `_protocolTraceLogger` (уровень DEBUG). Sink `protocol` по умолчанию выключен (`protocol.log`), in-app Debug log захватывает его всегда, application-sink'и (console, `application.log`, сервер логов) эту категорию не получают.
  - *Альтернатива — payload в application-записи:* payload попал бы в release-логи и на сервер логов, что запрещено `observability.md` §11 / AGENTS.md §16.
  - *Альтернатива — полагаться на уже существующую трассировку `protocol_message`:* payload есть, но не связан с пропуском; нужно искать соседнюю запись по времени.
- **Маскирование.** Общий `secretRedactionProcessor` обрабатывает все записи, поэтому payload маскируется так же, как остальные protocol-записи; отдельной обработки не добавляется.
- **Одинаковый текст события** у обеих записей: поиск по тексту находит обе, категория отличает их.

## Risks / Trade-offs

- [Payload может содержать пользовательский текст] → только developer-only канал, секреты маскируются, в release по умолчанию файл выключен.
- [В Debug log появляется две записи на один пропуск] → разные категории, фильтр по категории разделяет их; пропуски редки (`usage_update` несколько раз за turn).

## Migration Plan

Правка внутри `acp_client_core`, без изменения контрактов и данных. Откат — revert коммита.
