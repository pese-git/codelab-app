## MODIFIED Requirements

### Requirement: MCP-инструменты
Инструмент MCP-сервера SHALL регистрироваться в реестре сессии как `McpTool` (`AgentTool` пакета `codelab_agent_mcp`, agent-core-architecture §6.4; design.md change `add-agent-mcp-client`, D7).

- **Имя.** `mcpToolName(server, tool)` ядра:
  - `mcp__<server>__<tool>`, символы вне `[A-Za-z0-9_-]` заменены на `_`;
  - имя длиннее 64 символов — первые 56 символов, `_` и первые 7 hex-символов SHA-256 от UTF-8 полного имени до замены символов, ровно 64 символа;
  - сокращение детерминировано между запусками.
- **Схема.** `description` — описание инструмента, иначе `title`, иначе имя, передаётся модели как есть, но не длиннее 2048 символов: длиннее — первые 2048 символов (по границе символа) и суффикс `\n[Description truncated: <n> characters omitted.]`, лог `mcp.tool.description_truncated` (design.md change `add-agent-mcp-client`, D7). `parameters` — `inputSchema` сервера. Инструмент без имени или с `inputSchema` не-объектом пропускается с `mcp.tool.invalid`. `McpTool` SHALL при регистрации проверять форму всей схемы той же функцией формы ядра, что и валидатор, рекурсивно. Инструмент, у которого ключевое слово схемы, понятное валидатору §6.3.2, имеет неверный тип (`type` — не строка и не список строк, `required` — не список строк, `enum` — не список, `properties` — не объект) в корне или во вложенной схеме (`properties`, схема-объект `items`), либо вложенность больше 32 уровней (корень — уровень 0), SHALL пропускаться с `mcp.tool.invalid` и `reason: malformed inputSchema` (`server/tools.md`: `inputSchema` MUST be a valid JSON Schema object). Значение свойства и `items`, не являющиеся объектом (boolean-схема, tuple-форма `items: [...]`), инструмент НЕ SHALL отклонять. Поле `tool` события — имя от сервера, не длиннее 64 символов по рунам. Нестроковые `title` и `description` SHALL игнорироваться как отсутствующие, инструмент регистрируется.
- **Вид** SHALL быть всегда `other`, независимо от аннотаций сервера: аннотации — недоверенные подсказки (`server/tools.md`, «Tool Annotations»), и вид, показываемый клиенту в `tool_call` и `session/request_permission`, НЕ SHALL выдавать инструмент уровня `exec` за чтение или правку (решение пользователя 2026-11-08, design.md change `add-provider-setup-ui`, Q32). Аннотации на вид, уровень, политику и доверие не влияют.
- **Уровень и доверие.** `tier` SHALL быть всегда `exec`, `outputTrust` — всегда `untrusted`. Аннотации НЕ SHALL менять `tier`, решения `PermissionPolicy` и доверие.
- **Представление.** `present()` даёт `title`, равный полному имени инструмента. `permissionPattern` — канонический JSON аргументов (§7.5).
- **Исполнение** — только через `ToolExecutor` (TOOL-1), отдельного пути нет.

#### Scenario: Замена символов
- **WHEN** сервер `my.srv` отдаёт инструмент `get issue`
- **THEN** имя в реестре — `mcp__my_srv__get_issue` (`core/mcp-tool-name-sanitized`, E-05)

#### Scenario: Длинное имя
- **WHEN** полное имя `mcp__<server>__<tool>` имеет 100 символов, и второе имя совпадает с ним в первых 56 символах
- **THEN** оба имени ровно 64 символа, первые 56 символов, `_` и 7 hex SHA-256 полного имени, и имена различаются

#### Scenario: Вид не зависит от аннотаций
- **WHEN** инструменты имеют аннотации `{readOnlyHint: true}`, `{destructiveHint: true, openWorldHint: false}`, `{destructiveHint: true}` и не имеют аннотаций
- **THEN** `kind` у всех — `other`, а `tier` у всех — `exec`; `tool_call` и `session/request_permission` агента несут `kind: other`

#### Scenario: Длинное описание обрезается
- **WHEN** сервер отдаёт инструмент с описанием из 5 000 символов
- **THEN** `description` схемы — первые 2048 символов и строка `[Description truncated: 2952 characters omitted.]`, лог `mcp.tool.description_truncated`; описание из 2048 символов не меняется

#### Scenario: Нестроковое описание
- **WHEN** сервер отдаёт инструмент `t` с `description: 42` и без `title`
- **THEN** инструмент зарегистрирован, `description` схемы — `t`

#### Scenario: Кривая схема инструмента
- **WHEN** сервер отдаёт инструменты `bad` с `inputSchema: {"type":"object","required":"path"}`, `deep` с `properties.a.items.type: 5` и `ok` с `properties.flag: true`
- **THEN** `bad` и `deep` не зарегистрированы, по каждому лог `mcp.tool.invalid` с `reason: malformed inputSchema`; `ok` зарегистрирован

#### Scenario: Boolean и tuple-форма items допустимы
- **WHEN** сервер отдаёт инструменты со свойствами `{"type":"array","items":true}`, `{"type":"array","items":false}` и `{"type":"array","items":[{"type":"string"}]}`
- **THEN** все три зарегистрированы, `mcp.tool.invalid` нет; вызов с массивом в этом свойстве не даёт нарушения по `items`

#### Scenario: Граница глубины схемы
- **WHEN** сервер отдаёт инструмент со схемой ровно 32 уровней вложенности `properties` под корнем (корень — уровень 0) и инструмент с 33 уровнями
- **THEN** первый зарегистрирован, второй пропущен с `mcp.tool.invalid` и `reason: malformed inputSchema`

#### Scenario: Подсказка «только чтение» не снимает одобрения
- **WHEN** в режиме `standard` модель вызывает MCP-инструмент с `readOnlyHint: true`
- **THEN** политика спрашивает человека так же, как для `exec`
