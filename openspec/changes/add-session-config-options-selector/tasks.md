## 1. Протокол (acp_protocol)

- [x] 1.1 Добавить `SetSessionConfigOptionRequest` (`sessionId`, `configId`, `value`) и `SetSessionConfigOptionResponse` (`configOptions`) в `session.dart`, по образцу `NewSessionRequest`/`NewSessionResponse`
- [x] 1.2 Зарегистрировать `session/set_config_option` как request-response метод в `acp_method_codec.dart` (`sessionSetConfigOptionMethod`, `acpSessionSetConfigOption`, запись в `acpMethodRegistry`)
- [x] 1.3 Тесты кодека: encode/decode запроса и ответа, невалидные поля (`configId`/`value` отсутствуют или не строки)

## 2. Domain и application (acp_client_core)

- [x] 2.1 Добавить `case ConfigOptionUpdate(...)` в `SessionStateMachine._applyUpdate`, применяющий обновление к `AcpSession.configOptions` независимо от наличия активного turn — по образцу уже существующего `case AvailableCommandsUpdate(...)`
- [x] 2.2 Добавить `SetSessionConfigOptionCommand` и `Future<AcpSession> setSessionConfigOption(...)` в `AcpClientApplication`, обновляющий `configOptions` сессии из ответа (по образцу `createSession`/`loadSession`)
- [x] 2.3 Добавить use case `SetSessionConfigOption` в application-слое, координирующий вызов и маппинг ошибок, по образцу `CreateSession`/`SendPrompt`
- [x] 2.4 Тесты state machine: `configOptionUpdate` применяется без активного turn, применяется во время активного turn (и попадает в историю turn), несколько последовательных обновлений заменяют список целиком
- [x] 2.5 Тесты `AcpClientApplication`/use case: успешный `setSessionConfigOption`, ошибка агента не меняет `configOptions` и не оставляет сессию в неопределённом состоянии

## 3. Приложение (codelab_app)

- [x] 3.1 Добавить `CodeLabShellCubit.setSessionConfigOption(String configId, String value)`, вызывающий use case; отражение нового `configOptions` идёт через уже существующий путь `sessionChanges` → `_handleSessionChange` (реализовано как отдельное поле `CodeLabShellState.configOptions`, по образцу `agentCommands` — design.md допускал оба варианта, выбран этот для консистентности с уже устоявшимся паттерном)
- [x] 3.2 Учесть гонку двойного клика по одному чипу, пока предыдущий `session/set_config_option` не завершился (реализовано как `isRespondingToConfigOption: bool`, по образцу `isRespondingToApproval`)

## 4. UI-компонент (acp_ui)

- [x] 4.1 Добавить в `AcpPromptComposer` опциональные параметры `configOptions: List<...>` и `onConfigOptionSelected: void Function(String configId, String value)?` (реализовано через новую UI-модель `AcpConfigOption`/`AcpConfigOptionValue` в `acp_ui` — `acp_ui` не зависит от `acp_protocol`, поэтому `SessionConfigOption` не может быть передан напрямую; маппинг делает `CodeLabShellCubit`, как и для `AvailableCommand` → `AcpCommandAction`)
- [x] 4.2 Реализовать ряд chip-виджетов с dropdown (`fluent_ui` `DropDownButton`/`MenuFlyoutItem`), рендерящийся строкой над полем ввода внутри той же карточки композера; при пустом `configOptions` ряд не рендерится вообще (условие в `Column`, не `SizedBox.shrink()`)
- [x] 4.3 Название и варианты чипа берутся из `option.name`/`option.values` как есть, без сопоставления с локальными именами `readOnly`/`ask`/`plan`/`autoEdits`

## 5. Тесты — UI

- [x] 5.1 Widget-тест: пустой `configOptions` не рендерит ряд селекторов
- [x] 5.2 Widget-тест: непустой `configOptions` рендерит по одному чипу на опцию, в присланном порядке, с `currentValue`
- [x] 5.3 Widget-тест: выбор значения из dropdown вызывает `onConfigOptionSelected` с правильными `configId`/`value`
- [x] 5.4 Widget-тест: обновление `configOptions` (новый список) обновляет отображаемые чипы целиком

## 6. Тесты — сквозной сценарий (codelab_app)

- [ ] 6.1 Widget-тест: `session/new` с `configOptions` в ответе показывает селекторы в композере
- [ ] 6.2 Widget-тест: выбор значения отправляет `session/set_config_option` и обновляет чип из ответа
- [ ] 6.3 Widget-тест: `configOptionUpdate`, пришедший без активного turn, обновляет селекторы
- [ ] 6.4 Widget-тест: смена активной сессии показывает `configOptions` именно новой сессии (переиспользовать паттерн session isolation из `selectSession`/`createSession`)

## 7. Проверка

- [ ] 7.1 `fvm dart run melos run format`
- [ ] 7.2 `fvm dart run melos run analyze`
- [ ] 7.3 `fvm dart run melos run test`
