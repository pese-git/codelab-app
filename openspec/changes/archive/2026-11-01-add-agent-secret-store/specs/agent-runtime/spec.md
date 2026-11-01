## MODIFIED Requirements

### Requirement: MCP-серверы сессии
`createSession(SessionSpec)` и `loadSession(id, ports, mcpServers: …)` SHALL подключать MCP-серверы сессии до возврата сессии (design.md change `add-agent-mcp-client`, D6).

1. **Список.** Серверы `CoreConfig.mcpServers`, затем `SessionSpec.mcpServers`. Сервер клиента с тем же `name` заменяет сервер конфига (§13.4, шаг 2); сервер конфига пропускается с `mcp.server.skipped` и причиной `replaced by a server of the client with the same name`. Второй сервер с тем же `name` внутри одного источника (`duplicate server name in the same source`) и сервер с пустым `name` (`empty server name`) пропускаются с `mcp.server.skipped`.
2. **Фильтр.** При выключенной capability `mcp` каждый сервер пропускается с `mcp.server.skipped` и причиной выключения. Сервер с транспортом вне набора capability пропускается с причиной, называющей транспорт и профиль.
3. **Подключение.** Перед `services.mcp.connect` шаблоны `${secret:<name>}` в значениях `env`/`headers` серверов конфига SHALL раскрываться через `AgentCoreServices.secrets` (capability `agent-secrets`, «Секреты MCP-серверов конфигурации»; design.md change `add-agent-secret-store`, D4) — параллельно по серверам, в токене отмены создания или загрузки сессии. Секрет не найден, хранилище недоступно или у ядра нет резолвера → сервер SHALL не подключаться с `mcp.server.failed {server, transport, reason}`; причина называет имя секрета и бэкенд (`secret <name> is not set`, `secret <name> cannot be read: <backend> is unavailable`, `no secret store`) и НЕ SHALL содержать значение секрета. Остальные серверы подключаются, сессия создаётся. `AgentRuntime.dispose()` во время раскрытия SHALL отбрасывать результат: `connect` не вызывается, `mcp.server.failed` не пишется. Заголовки после раскрытия SHALL идти в порядке файла конфига. Серверы клиента не раскрываются: `${secret:…}` в них — литерал. Затем `services.mcp.connect` подключает серверы параллельно, каждый в своём `connectTimeout`. Сбой сервера SHALL давать `mcp.server.failed` и сессию без его инструментов. Исключение `connect` целиком SHALL давать `mcp.server.failed` с причиной `MCP connector failed: <runtimeType>` и сессию без MCP-инструментов, а не ошибку `createSession` / `loadSession`.
4. **Регистрация.** После всех подключений, в порядке списка, внутри сервера — в порядке `tools/list`, в реестр сессии поверх копии базового реестра.
5. **Коллизия имени** MCP-инструмента со встроенным или с уже зарегистрированным SHALL отключать весь более поздний сервер (транспорт закрыт, инструменты не зарегистрированы) с `mcp.server.failed`, причина которого называет оба источника. Сессия SHALL создаваться (HOST-5). Независимо от проверки коннектора ядро SHALL отклонять с `mcp.tool.invalid` инструмент коннектора без префикса `mcp__` или с именем встроенного инструмента (защита в глубину).
6. **Изоляция.** Инструменты одной сессии НЕ SHALL быть видны другим сессиям.
7. **Закрытие.** `AgentSession.close()` и `AgentRuntime.dispose()` SHALL закрывать транспорты серверов сессии после остановки хода. Если `createSession` / `loadSession` падает после подключения серверов, подключения SHALL закрываться до проброса ошибки: сессия, не возвращённая вызывающему, не оставляет живых процессов.
8. **Обновление набора.** Ожидающее обновление `McpSessionTools.takeUpdate()` ядро SHALL применять на границе шага через `prepareNextStep` полями `StepUpdate.tools` и `StepUpdate.systemPrompt` (транскрипт цикла не меняется), а между ходами — перед началом хода.
9. **Журнал.** Описания серверов НЕ SHALL записываться в журнал.

`AgentSession.setMcpServers(servers)` SHALL заменять серверы с `origin: session`:
- список проходит те же слияние, фильтр и раскрытие секретов серверов конфига (шаг 3), что при `createSession`; в `McpSessionTools.replaceServers` уходит полный желаемый список (серверы конфига, затем клиента); сервер конфига с ненайденным секретом в него не входит и даёт `mcp.server.failed`;
- серверы конфига не трогаются; совпавшие по `name` и параметрам (`sameConnection`) остаются; исчезнувшие закрываются, новые подключаются и занимают имена инструментов последними (коллизия отключает новый сервер); отключённый или не подключившийся сервер пробуется заново;
- без хода — набор меняется до завершения возвращённого `Future`; во время хода вызов возвращается сразу, набор применяется после `TurnEnded`, последний вызов за ход побеждает, следующий `prompt` дожидается применения;
- на закрытой сессии — `StateError`;
- сбой коннектора НЕ SHALL пробрасываться: прежний набор остаётся, лог `mcp.server.failed`;
- «последний вызов побеждает» SHALL обеспечиваться счётчиком поколений: результат устаревшей замены, завершившейся позже, НЕ SHALL перекрывать новую;
- `AgentSession.close()` SHALL отменять идущую замену токеном отмены уровня сессии, в том числе ожидание секретов: `connect` не вызывается, `mcp.server.failed` не пишется.

#### Scenario: Закрытие во время замены
- **WHEN** `setMcpServers` подключает новый сервер, а сессия закрывается до конца подключения
- **THEN** подключение отменено, транспорт нового сервера закрыт, набор сессии не изменился после `close()`

#### Scenario: Секрет сервера конфига не найден
- **WHEN** `CoreConfig.mcpServers` содержит http-сервер `gh` с `headers.Authorization: "Bearer ${secret:codelab/mcp/gh/authorization}"` и stdio-сервер `docs` без ссылок, секрета нет ни в хранилище, ни в `CODELAB_SECRET_CODELAB_MCP_GH_AUTHORIZATION`
- **THEN** `createSession` возвращает сессию, `docs` подключён, `connect` для `gh` не вызван, лог `mcp.server.failed {server: gh, transport: http, reason: "secret codelab/mcp/gh/authorization is not set"}`; лог и журнал не содержат значений секретов

#### Scenario: Хранилище недоступно при загрузке сессии
- **WHEN** `loadSession` восстанавливает сессию, а хранилище бросает `SecretStoreUnavailableException(backend: "file", …)` для секрета сервера `gh`
- **THEN** сессия загружена без инструментов `gh`, лог `mcp.server.failed` с причиной `secret codelab/mcp/gh/authorization cannot be read: file is unavailable`

#### Scenario: Закрытие во время раскрытия секретов
- **WHEN** `read` хранилища для сервера конфига не завершается, а рантайм получает `dispose()` (или сессия — `close()` во время `setMcpServers`)
- **THEN** `connect` для этого сервера не вызван, записи `mcp.server.failed` для него нет, процессов серверов не осталось

#### Scenario: Замена во время хода
- **WHEN** во время хода `setMcpServers` вызывается дважды с разными наборами
- **THEN** оба вызова возвращаются сразу, инструменты хода не меняются, после `TurnEnded` применён набор второго вызова, следующий `prompt` видит его

#### Scenario: Сервер конфига не тронут
- **WHEN** у сессии сервер конфига `cfg` и сервер клиента `a`, и `setMcpServers` получает `[b]`
- **THEN** `cfg` не переподключался, `a` закрыт, `b` подключён

#### Scenario: Сервер клиента побеждает сервер конфига
- **WHEN** `CoreConfig.mcpServers` содержит `github` (http), а `SessionSpec.mcpServers` — `github` (stdio)
- **THEN** подключается только stdio-сервер клиента

#### Scenario: Коллизия двух серверов
- **WHEN** `mcpServers` содержит серверы `my.srv` и затем `my_srv`, оба с инструментом `t`, а `my_srv` подключается раньше
- **THEN** оба дают имя `mcp__my_srv__t`; сервер `my_srv`, стоящий в списке позже, отключён с `mcp.server.failed`, причина называет `my_srv` и `my.srv`; сессия создана и содержит `mcp__my_srv__t` сервера `my.srv` (`core/mcp-tool-name-sanitized`, E-05)

#### Scenario: Коллизия внутри одного сервера
- **WHEN** сервер `x` отдаёт инструменты `get issue` и `get_issue`
- **THEN** сервер `x` отключён с причиной о коллизии `mcp__x__get_issue`, сессия создана

#### Scenario: Сессии не видят чужих инструментов
- **WHEN** сессия A подключает сервер `fake`, а сессия B создана без серверов
- **THEN** запрос к модели сессии B не содержит схем `mcp__`

#### Scenario: Процессы закрываются вместе с сессией
- **WHEN** сессия с stdio-сервером закрывается `AgentSession.close()`
- **THEN** `close()` транспорта вызван после окончания хода, лог `mcp.server.closed`

#### Scenario: Сбой после подключения закрывает серверы
- **WHEN** сессия подключила stdio-сервер, а запись журнала в `createSession` бросает исключение
- **THEN** `createSession` пробрасывает ошибку, а `close()` транспорта сервера вызван до этого

#### Scenario: Коннектор бросил
- **WHEN** `McpConnector.connect` бросает исключение
- **THEN** `createSession` возвращает сессию без инструментов `mcp__`, лог `mcp.server.failed` с причиной `MCP connector failed: <runtimeType>`

#### Scenario: Коннектор отдал инструмент без префикса
- **WHEN** fake `McpConnector` возвращает инструменты `read` и `mcp__x__t`
- **THEN** в реестре сессии только `mcp__x__t` от коннектора, встроенный `read` не подменён, лог `mcp.tool.invalid` для `read`

#### Scenario: Capability выключена
- **WHEN** ядро собрано без `services.mcp`, а `SessionSpec.mcpServers` содержит сервер
- **THEN** сервер пропущен с `mcp.server.skipped` и причиной «сервис MCP не передан», сессия создана
