# AGENTS.md — codelab_acp_protocol

Правила этого пакета дополняют корневой `AGENTS.md`.

Источники:
- корневой `AGENTS.md` — §3.4, §5, §7, §15, §21;
- `docs/architecture/acp-boundary.md` — §3 (ответственность пакета), §18–§19 (неизвестные поля и методы);
- референс ACP — `docs/protocols/acp/protocol/` (`17-Schema.md` — схема); его НЕ ДОЛЖНЫ менять;
- `.claude/agents/acp-protocol-engineer.md` — «Правила зоны».

## 1. Назначение

Типизированные модели wire-протокола ACP поверх JSON-RPC 2.0: кодеки, проверка формы сообщений, типизированные ошибки. Пакет описывает только то, что идёт по проводу; API и состав — в `README.md`.

## 2. Границы

* Пакет — чистый Dart, без Flutter (корневой `AGENTS.md` §5, правило для `packages/dart/`). Состав зависимостей — `pubspec.yaml` и `README.md`; новая технология, меняющая архитектуру, требует явного архитектурного решения (§4).
* Пакет НЕ ДОЛЖЕН содержать BLoC, виджеты, permission dialogs, navigation, presentation state, application workflow и reconnect UX (`acp-boundary.md` §3).
* Публичный API экспортируется через `lib/codelab_acp_protocol.dart` (§15).

## 3. Правила

* Методы, сообщения, поля, состояния и semantics ACP НЕ ДОЛЖНЫ придумываться; источник — `17-Schema.md` и `openspec/specs/`. Если поведение не определено, остановиться и запросить уточнение (§3.4).
* Все ACP-сообщения ДОЛЖНЫ иметь типизированные модели (§7); в пакете это freezed-модели (`acp-protocol-engineer.md`, «Правила зоны»; `README.md`, «Как расширять», п. 2); Protocol DTO — не долгоживущий UI state (§7).
* Forward compatibility ДОЛЖНА сохраняться там, где этого требует ACP: неизвестные поля не дают fatal parsing error, если протокол разрешает их игнорировать или сохранять; неизвестное поле не получает известной семантики (`acp-boundary.md` §18). Неизвестный метод или сообщение обрабатывается явно (§19).
* Ошибки — типизированные, не `String` и не generic `Exception` (§15).
* Изменение моделей: после правки freezed-моделей запустить `build_runner` в пакете; `*.freezed.dart` не хранятся в репозитории (`README.md`, «Как расширять», п. 7).

## 4. Проверки

* `fvm dart test` в пакете; `melos run protocol-conformance` (запускает только тесты этого пакета, `pubspec.yaml` корня).
* Изменены модели — ещё и `melos run conformance:client`, `conformance:agent`; изменены импорты или `pubspec.yaml` — `melos run guard` (§21, «Проверка перед pull request»).
