## ADDED Requirements

### Requirement: Ошибка проектного конфига сессии
Если `AgentRuntime` отказывает в `session/new` или `session/load` из-за `ProjectConfigException`, сервер SHALL отвечать ошибкой JSON-RPC `-32603` с `data.codelab.reason: "projectConfigInvalid"`. Сообщение ошибки — текст исключения: проблемы в форме `config check`, без значений секретов. Новых кодов ошибок сервер НЕ SHALL вводить, причину уточняет `data.codelab.reason`, как у остальных ошибок сервера. Сессия НЕ SHALL создаваться и НЕ SHALL попадать в `session/list` (design.md change `require-project-folder`, D21).

#### Scenario: session/new в папке с битым конфигом
- **WHEN** клиент отправляет `session/new` с `cwd`, чей `.codelab/config.yaml` не разбирается
- **THEN** ответ — `-32603` с `data.codelab.reason: "projectConfigInvalid"` и проблемой с путём файла; соединение и другие сессии продолжают работать

### Requirement: Модели сессии по её каталогу
`configOptions` `model` сессии SHALL перечислять модели каталога этой сессии: для сессии вне корня процесса — каталога, построенного из конфигурации её папки (spec agent-runtime «Конфигурация сессии вне корня запуска»). `session/set_config_option` с `configId: "model"` SHALL проверять значение по тому же каталогу: модель вне каталога сессии — `-32602`. Опции разных сессий одного соединения МОГУТ различаться (design.md change `require-project-folder`, D21).

#### Scenario: Две сессии разных папок
- **WHEN** в одном соединении открыты сессия `/A` (каталог без `local`) и сессия `/B` (каталог с `local/m`)
- **THEN** `configOptions` `model` сессии `/B` содержит `local/m`, сессии `/A` — нет; `session/set_config_option` с `local/m` для сессии `/A` даёт `-32602`
