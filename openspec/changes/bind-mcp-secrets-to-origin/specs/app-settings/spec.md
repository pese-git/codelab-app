## ADDED Requirements

### Requirement: Непривязанный MCP-сервер на странице MCP servers
Сервер проектного слоя, заблокированный правилом привязки (capability `agent-secrets`, «Ссылки MCP-сервера проектного слоя привязаны к адресу»; design.md change `bind-mcp-secrets-to-origin`, D4, D5), SHALL показываться на странице «MCP servers» существующими средствами, без новых элементов:
- панель «Agent status» встроенного агента SHALL показывать строку сервера с состоянием `failed` и в `LAST ERROR` — текст причины агента как есть (`key bound to another address: move the server to config.local.yaml or the user config (<reference>)`);
- строка списка серверов SHALL оставаться прежней (источник `this project` или `defined in <file>`); InfoBar `mcp-rejected` НЕ SHALL показываться: непривязанная ссылка — предупреждение загрузки, а не проблема;
- сервер, записанный страницей с целью «This project only» (`config.local.yaml` доверенного проекта) или «Save to User config», SHALL подключаться без блокировки, если остальные условия подключения выполнены.

Ни экран, ни журнал приложения (`mcp_settings.*`) НЕ SHALL содержать значение секрета или переменной непривязанной ссылки.

#### Scenario: Заблокированный сервер в панели Agent status
- **WHEN** встроенный агент открыл сессию в доверенном проекте, чей `config.yaml` задаёт HTTP-сервер `relay` с `headers.Authorization: "Bearer ${secret:codelab/mcp/github/authorization}"` и чужим адресом, секрет хранит значение `sk-test-leak-0123456789`, и пользователь открывает «MCP servers»
- **THEN** таблица «Agent status» показывает `relay` в состоянии `failed` и в `LAST ERROR` — `key bound to another address: move the server to config.local.yaml or the user config (secret codelab/mcp/github/authorization)`; `mcp-rejected` не показан; маркера нет ни на экране, ни в журнале приложения

#### Scenario: Сервер «This project only» не блокируется
- **WHEN** пользователь добавляет на странице HTTP-сервер `team` с секретным заголовком `Authorization` и целью «This project only» в доверенном проекте, затем открывает новую сессию этого проекта
- **THEN** `config.local.yaml` содержит `team` со ссылкой `${secret:codelab/mcp/team/authorization}`, баннер `saved` без предупреждения о привязке, «Agent status» показывает `team` не в состоянии `failed` с причиной блокировки
