## Why

Агент может объявить набор конфигурируемых опций сессии (`AcpSession.configOptions`/`modes`, из `SessionUpdate.configOptionUpdate`/`session/new`) — типично селекторы модели (`category: "model"`) и режима (`category: "mode"`), по нормативной ACP-спеке `docs/acp/protocol/13-Session Config Options.md`. Домен-слой (`acp_client_core`) уже парсит и хранит эти данные, но пользователь никак их не видит и не может изменить: `AcpPromptComposer` не показывает ни один селектор, а исходящий метод `session/set_config_option` вообще не реализован в `acp_protocol` — то есть даже если бы UI показал текущее значение, отправить выбор пользователя агенту сегодня нечем. Design-канвас (`docs/design/ui-canvas/SessionOptionsRow.dc.html`, `Main.dc.html`) давно фиксирует этот UI как желаемый, но остаётся непривязанным ни к одному change.

## What Changes

- В `acp_protocol` добавляется исходящий метод `session/set_config_option` (params: `sessionId`, `configId`, `value`) и типизированный ответ — полный список `ConfigOption` с обновлёнными `currentValue`, по образцу уже существующих исходящих методов (`session/new`, `session/prompt`, `session/cancel`).
- В `acp_client_core` добавляется use case `SetSessionConfigOption` (или аналог), обновляющий `AcpSession.configOptions` из ответа/из входящего `config_option_update`. Устаревший канал `SessionMode`/`current_mode_update`/`SessionModeState` **не переиспользуется и не расширяется** — по ACP-спеке (`13-Session Config Options.md`, раздел "Relationship to Session Modes") `configOptions` полностью замещает `modes` там, где агент их предоставляет; клиент, поддерживающий config options, обязан игнорировать `modes`.
- `CodeLabShellCubit` получает метод `setSessionConfigOption(String configId, String value)`, вызывающий use case и отражающий актуальные `configOptions` в `CodeLabShellState`.
- `AcpPromptComposer` (`acp_ui`) получает новый опциональный ряд селекторов над toolbar'ом: одна `chip`-кнопка с dropdown на каждый `ConfigOption` из `configOptions`, отсортированные в порядке, присланном агентом (order significant по спеке). Если `configOptions` пуст (агент их не предоставляет — типичный случай для минимальных тестовых агентов), ряд не рендерится вообще — это не заглушка "coming soon", а честное отсутствие UI там, где агенту нечего конфигурировать.
- Дизайн селектора (chip + dropdown, позиция в toolbar под текстом) берётся из `docs/design/ui-canvas/SessionOptionsRow.dc.html`/`Main.dc.html` как визуальный референс, не как спецификация один-в-один.

## Capabilities

### New Capabilities

_(нет — используются существующие `acp-protocol-client` и `agent-workbench-ui`)_

### Modified Capabilities

- `acp-protocol-client`: добавляется требование про исходящий `session/set_config_option` и обработку `config_option_update` — новая часть жизненного цикла сессии, ранее не специфицированная (спека до этого молчала про config options целиком).
- `agent-workbench-ui`: композер получает требование показывать и изменять `configOptions` активной сессии, когда агент их объявил — новое поведение поверх уже описанного "Agent workbench interaction patterns".

## Impact

- `packages/dart/acp_protocol/lib/src/acp/session.dart` (или соседний файл исходящих методов) — новый метод `session/set_config_option` + response DTO.
- `packages/dart/acp_client_core/lib/src/application/` — новый use case `SetSessionConfigOption`, обновление `acp_client_application.dart` для обработки `config_option_update`.
- `packages/dart/acp_client_core/lib/src/domain/domain_models.dart` — `AcpSession.configOptions` уже существует, изменений в модели, вероятно, не требуется (уточняется в design.md).
- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` — новый метод `setSessionConfigOption`, поле в `CodeLabShellState` (если понадобится сверх уже читаемого из `AcpSession`).
- `packages/flutter/acp_ui/lib/src/molecules/acp_prompt_composer.dart` — новый опциональный параметр (список `ConfigOption`-подобных моделей + callback), новый ряд chip-селекторов.
- Тесты: `acp_protocol` (кодек нового метода), `acp_client_core` (use case, обработка notification), `acp_ui` (рендер/выбор селектора), `codelab_app` (сквозной сценарий выбора модели/режима).
