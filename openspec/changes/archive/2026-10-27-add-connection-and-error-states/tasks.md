## 1. Типизированный сбой хода в codelab_client_acp

- [x] 1.1 Красные тесты разбора: `data.codelab` из фикстуры `acp/prompt-failed-provider-auth`, ошибка без `data`, незнакомый `errorClass`, `retryable` не `bool`, `data.codelab` не объект
- [x] 1.2 Ввести sealed `PromptFailure` (`agent`, `request`, `connectionLost`, `unknown`) и функцию разбора `JsonRpcError` на границе ACP (design D2); doc-комментарии на русском
- [x] 1.3 Добавить `PromptTurn.failure`; `PromptTurnStateMachine.fail` и `SessionStateMachine.failTurn` принимают `failure` вместе с `message`; `sendPrompt` классифицирует исключение, обрыв транспорта даёт `connectionLost`
- [x] 1.4 Тест: ход, прерванный отказом транспорта, имеет `PromptFailure.connectionLost`; требование «Ход, прерванный заменой транспорта» не затронуто — существующие тесты зелёные
- [x] 1.5 Перегенерировать `*.freezed.dart`, прогнать тесты и conformance пакета

## 2. Автомат соединения и повтор в codelab_client_core

- [x] 2.1 Красные тесты `ClientWorkspace`: сбой транспорта в `Connected` даёт `ConnectionLost`; неудачный `connect()` даёт `ConnectionFailed`; `reconnect()` из `ConnectionLost` проходит `Reconnecting(attempt: 1)` → `Connected`
- [x] 2.2 Добавить `ConnectionView.lost` и переход в `client_workspace.dart` по развилке «вне своего `connect`/`reconnect`» (design D1)
- [x] 2.3 `NoticeItem` вида `error` получает `failure`, `SessionView` — `canRetry` по правилам D4; тест на свойство «инкрементальная проекция = проекция с нуля» остаётся зелёным
- [x] 2.4 Красные тесты `retry()`: повтор после `network`, отказ при `retryable: false`, при `connectionLost`, при занятой сессии
- [x] 2.5 Реализовать `SessionHandle.retry()` через обычный путь отправки; сессия с сорвавшимся ходом принимает новый ход (design D4)

## 3. Виджеты codelab_ui

- [x] 3.1 Добавить `lost` в `CodeLabConnectionStatus`, обновить `CodeLabConnectionStatusRow` и `CodeLabConnectionScreen` (цвет как у `failed`)
- [x] 3.2 Молекула `CodeLabConnectionBanner` на `InfoBar` (design D6): статусы `lost`, `failed`, `reconnecting`, действия Reconnect и Connection settings, индикатор прогресса; превью в каталоге
- [x] 3.3 Заметка о сбое хода в `CodeLabTranscriptPanel`: заголовок, тело, свёрнутые Details, необязательное действие Retry; превью в каталоге
- [x] 3.4 Виджет-тесты: действия баннера по статусам, отсутствие крестика закрытия, Details свёрнуты по умолчанию, Retry виден только при переданном обработчике

## 4. Desktop

- [x] 4.1 `ui_mappers.dart`: `ConnectionLost` → `lost`; заголовки заметки по `errorClass` по таблице D3; тело и Details; тесты маппера на каждый класс
- [x] 4.2 `WorkbenchMainPane`: баннер над непустой лентой при `lost`, `failed`, `reconnecting`; при пустой ленте — прежний экран подключения
- [x] 4.3 Действие Retry в Cubit-е сессии вызывает `SessionHandle.retry()`
- [x] 4.4 Тесты `widget_test.dart` и `connection_and_error_states_test.dart` на сценарии спецификации `agent-workbench-ui`: падение агента посреди сессии, Reconnect из баннера (успех и неудача), пустая лента, сбой `auth`, Retry после `server`, ход, прерванный обрывом, ошибка стороннего агента
- [x] 4.5 Статус `lost` в тестах: обновлены `connection_test.dart` и `widget_test.dart`; характеризационный `reconnect_test.dart` проверяет явный `reconnect()` и правки не потребовал

## 5. Проверка

- [x] 5.1 `fvm dart format` изменённых файлов, `fvm exec melos analyze`
- [x] 5.2 `fvm exec melos run check` (общие пакеты и ACP затронуты; интеграционные тесты — только Dart VM, §21)
- [x] 5.3 Ручная проверка сборки macOS: падение агента посреди хода, баннер, Reconnect, заметка о сбое со скриншотами
- [x] 5.4 `openspec validate add-connection-and-error-states --strict`
