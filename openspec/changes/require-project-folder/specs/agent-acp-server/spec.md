## ADDED Requirements

### Requirement: Ошибка проектного конфига сессии
Если `AgentRuntime` отказывает в `session/new` или `session/load` из-за `ProjectConfigException`, сервер SHALL отвечать ошибкой JSON-RPC `-32603` с `data.codelab.reason: "projectConfigInvalid"`. Сообщение ошибки SHALL быть одной строкой: все проблемы через `; ` в форме `<source>:<line>:<column>: <key>: <message>`, без значений секретов; других полей в `data`, кроме `codelab.reason`, нет. Новых кодов ошибок сервер НЕ SHALL вводить, причину уточняет `data.codelab.reason`, как у остальных ошибок сервера. При `session/new` сессия НЕ SHALL создаваться и НЕ SHALL попадать в `session/list`; при `session/load` журнал сессии НЕ SHALL меняться, сессия остаётся незагруженной (design.md change `require-project-folder`, D21).

#### Scenario: session/new в папке с битым конфигом
- **WHEN** клиент отправляет `session/new` с `cwd`, чей `.codelab/config.yaml` не разбирается
- **THEN** ответ — `-32603` с `data.codelab.reason: "projectConfigInvalid"` и однострочным `message` с проблемой и путём файла; соединение и другие сессии продолжают работать

### Requirement: Модели сессии по её каталогу
`configOptions` `model` сессии SHALL перечислять модели каталога этой сессии: для сессии вне корня процесса — каталога, построенного из конфигурации её папки (spec agent-runtime «Конфигурация сессии вне корня запуска»). Источник — `AgentSession.models`, а не каталог рантайма. `session/set_config_option` с `configId: "model"` SHALL проверять значение по тому же каталогу: модель вне каталога сессии — `-32602`. Опции разных сессий одного соединения МОГУТ различаться (design.md change `require-project-folder`, D21). `config_option_update` после перезагрузки конфигурации корня (требование «Уведомления после перезагрузки конфигурации») SHALL уходить только сессиям, которые получили `ModelOptionsChanged`; сессиям других папок он не уходит (spec agent-runtime «Сессии других папок при перезагрузке корня»).

#### Scenario: Две сессии разных папок
- **WHEN** в одном соединении открыты сессия `/A` (каталог без `local`) и сессия `/B` (каталог с `local/m`)
- **THEN** `configOptions` `model` сессии `/B` содержит `local/m`, сессии `/A` — нет; `session/set_config_option` с `local/m` для сессии `/A` даёт `-32602`

#### Scenario: Перезагрузка корня и сессия другой папки
- **WHEN** в одном соединении открыты сессии `/A` (корень) и `/B`, и перезагрузка конфигурации корня добавляет модель в каталог
- **THEN** `config_option_update` получает только сессия `/A`
