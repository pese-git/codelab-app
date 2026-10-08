## MODIFIED Requirements

### Requirement: Инициализация и capabilities
CodeLab SHALL выполнять `initialize` перед настройкой сессии и SHALL учитывать согласованную версию протокола и capabilities. Незнакомые корневые поля внутри capability-объектов `initialize` (`agentCapabilities` и всё, что вложено под ним — `sessionCapabilities`, `mcpCapabilities`, `promptCapabilities` и их дочерние объекты) SHALL игнорироваться при decode, а не приводить к отказу всего `initialize`.

#### Scenario: Совместимая версия протокола
- **WHEN** агент отвечает на `initialize` поддерживаемой `protocolVersion`
- **THEN** CodeLab сохраняет информацию об агенте, capabilities и переходит в состояние готовности к созданию сессии

#### Scenario: Неподдерживаемая версия протокола
- **WHEN** агент отвечает неподдерживаемой `protocolVersion`
- **THEN** CodeLab закрывает соединение и показывает пользователю понятную ошибку несовместимости

#### Scenario: Незнакомое поле внутри capability-объекта
- **WHEN** ответ на `initialize` содержит внутри `agentCapabilities` (включая вложенные `sessionCapabilities`/`mcpCapabilities`/`promptCapabilities`) поле, которого нет в типизированной модели CodeLab
- **THEN** CodeLab decode'ит остальную, понятную часть `agentCapabilities` без ошибки, молча игнорируя незнакомое поле, и продолжает handshake как при совместимой версии протокола

#### Scenario: Незнакомое поле вне capability-объектов
- **WHEN** ответ на `initialize`, любое ACP-сообщение sessions/prompt/tool_call/permission/fs/terminal или сам верхний уровень `InitializeRequest`/`InitializeResponse` содержит незнакомое корневое поле вне capability-объектов, описанных в предыдущем сценарии
- **THEN** CodeLab продолжает выдавать типизированную протокольную ошибку, как и для любой другой невалидной формы ACP-сообщения
