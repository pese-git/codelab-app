## ADDED Requirements

### Requirement: Исходящий session/set_config_option
CodeLab SHALL поддерживать исходящий метод `session/set_config_option` (request: `sessionId`, `configId`, `value`; response: полный обновлённый список `configOptions`) для изменения ранее объявленного агентом `SessionConfigOption`.

#### Scenario: Пользователь меняет значение опции
- **WHEN** активная сессия имеет `SessionConfigOption` с `id`, и пользователь выбирает новое значение из его `options`
- **THEN** CodeLab отправляет `session/set_config_option` с этим `configId` и выбранным `value`, и по ответу заменяет весь список `configOptions` сессии присланным агентом

#### Scenario: Агент отклоняет значение
- **WHEN** агент отвечает на `session/set_config_option` ошибкой JSON-RPC
- **THEN** CodeLab не изменяет `configOptions` сессии и показывает диагностику ошибки, не оставляя UI в неопределённом состоянии

### Requirement: Config option update применяется независимо от активного turn
CodeLab SHALL применять `SessionUpdate.configOptionUpdate` к `configOptions` сессии независимо от того, есть ли у сессии активный prompt turn — по ACP-спеке агент может прислать это обновление в любой момент сессии, а не только во время turn.

#### Scenario: Обновление приходит без активного turn
- **WHEN** сессия не имеет активного prompt turn, и агент присылает `SessionUpdate.configOptionUpdate`
- **THEN** CodeLab заменяет `configOptions` сессии присланным списком

#### Scenario: Обновление приходит во время активного turn
- **WHEN** у сессии есть активный prompt turn, и агент присылает `SessionUpdate.configOptionUpdate`
- **THEN** CodeLab заменяет `configOptions` сессии присланным списком и дополнительно записывает обновление в историю активного turn (для инспектора), не завершая и не изменяя статус самого turn

### Requirement: Устаревший канал session modes не используется при наличии config options
CodeLab SHALL игнорировать `SessionModeState`/`SessionUpdate.currentModeUpdate`, если та же сессия предоставляет `configOptions` — по ACP-спеке эти два канала взаимоисключающие для клиентов, поддерживающих config options.

#### Scenario: Агент присылает оба канала одновременно
- **WHEN** ответ `session/new` содержит одновременно непустые `modes` и `configOptions`
- **THEN** CodeLab отображает и использует только `configOptions`, не показывая никакого UI на основе `modes`
