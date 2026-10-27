## 1. Типизированный сбой хода в codelab_client_acp

- [ ] 1.1 Красные тесты разбора: `data.codelab` из фикстуры `acp/prompt-failed-provider-auth`, ошибка без `data`, незнакомый `errorClass`, `retryable` не `bool`, `data.codelab` не объект
- [ ] 1.2 Ввести sealed `PromptFailure` (`agent`, `request`, `connectionLost`, `unknown`) и функцию разбора `JsonRpcError` на границе ACP (design D2); doc-комментарии на русском
- [ ] 1.3 Добавить `PromptTurn.failure`; `PromptTurnStateMachine.fail` и `SessionStateMachine.failTurn` принимают `failure` вместе с `message`; `sendPrompt` классифицирует исключение, обрыв транспорта даёт `connectionLost`
- [ ] 1.4 Тест: ход, прерванный отказом транспорта, имеет `PromptFailure.connectionLost`; требование «Ход, прерванный заменой транспорта» не затронуто — существующие тесты зелёные
- [ ] 1.5 Перегенерировать `*.freezed.dart`, прогнать тесты и conformance пакета

## 2. Автомат соединения и повтор в codelab_client_core

- [ ] 2.1 Красные тесты `ClientWorkspace`: сбой транспорта в `Connected` даёт `ConnectionLost`; неудачный `connect()` даёт `ConnectionFailed`; `reconnect()` из `ConnectionLost` проходит `Reconnecting(attempt: 1)` → `Connected`
- [ ] 2.2 Добавить `ConnectionView.lost` и переход в `client_workspace.dart` по развилке «вне своего `connect`/`reconnect`» (design D1)
- [ ] 2.3 `NoticeItem` вида `error` получает `failure` и `canRetry`; `TranscriptProjector` вычисляет `canRetry` по правилам D4; тест на свойство «инкрементальная проекция = проекция с нуля» остаётся зелёным
- [ ] 2.4 Красные тесты `retryTurn`: повтор после `network`, отказ при `retryable: false`, при `connectionLost`, при занятой сессии и вне `Connected`
- [ ] 2.5 Реализовать `ClientWorkspace.retryTurn(sessionId)` через обычный путь отправки и очередь (design D4)

## 3. Виджеты codelab_ui

- [ ] 3.1 Добавить `lost` в `CodeLabConnectionStatus`, обновить `CodeLabConnectionStatusRow` и `CodeLabConnectionScreen` (цвет как у `failed`)
- [ ] 3.2 Молекула `CodeLabConnectionBanner` на `InfoBar` (design D6): статусы `lost`, `failed`, `reconnecting`, действия Reconnect и Connection settings, индикатор прогресса; превью в каталоге
- [ ] 3.3 Заметка о сбое хода в `CodeLabTranscriptPanel`: заголовок, тело, свёрнутые Details, необязательное действие Retry; превью в каталоге
- [ ] 3.4 Виджет-тесты: действия баннера по статусам, отсутствие крестика закрытия, Details свёрнуты по умолчанию, Retry виден только при переданном обработчике

## 4. Desktop

- [ ] 4.1 `ui_mappers.dart`: `ConnectionLost` → `lost`; заголовки заметки по `errorClass` по таблице D3; тело и Details; тесты маппера на каждый класс
- [ ] 4.2 `WorkbenchMainPane`: баннер над непустой лентой при `lost`, `failed`, `reconnecting`; при пустой ленте — прежний экран подключения
- [ ] 4.3 Действие Retry в Cubit-е сессии вызывает `ClientWorkspace.retryTurn`
- [ ] 4.4 Виджет-тесты `widget_test.dart` на сценарии спецификации `agent-workbench-ui`: падение агента посреди сессии, Reconnect из баннера (успех и неудача), пустая лента, сбой `auth`, Retry после `server`, ход, прерванный обрывом, ошибка стороннего агента
- [ ] 4.5 Обновить характеризационный тест `reconnect_test.dart` под статус `lost`

## 5. Проверка

- [ ] 5.1 `fvm dart format` изменённых файлов, `fvm exec melos analyze`
- [ ] 5.2 `fvm exec melos run check` (общие пакеты и ACP затронуты; интеграционные тесты — только Dart VM, §21)
- [ ] 5.3 Ручная проверка сборки macOS: падение агента посреди хода, баннер, Reconnect, заметка о сбое со скриншотами
- [ ] 5.4 `openspec validate add-connection-and-error-states --strict`
