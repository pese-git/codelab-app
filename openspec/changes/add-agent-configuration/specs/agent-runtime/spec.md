## ADDED Requirements

### Requirement: Конфигурация сессии вне корня запуска
Если `CoreConfig.projectRoot` задан и канонический `cwd` новой или загружаемой сессии ему не равен, `AgentRuntime` SHALL брать ключи сессии из `CoreConfig.withoutProject` — снимка без проектных слоёв 3–4 (design.md change `add-agent-configuration`, D9). Ключи сессии: модель по умолчанию, `effort`, режим и правила разрешений, бюджет хода, пороги сжатия, MCP-серверы конфигурации и `redact`. Сравнивается равенство путей по компонентам, а не вложенность. Ключи сборки — каталог провайдеров, capability, сужение профиля — общие для процесса. На каждый такой `cwd` SHALL писаться один лог `config.session.outside_root {session_id, cwd, config_root}`. Без `projectRoot` или без `withoutProject` поведение прежнее: все сессии получают `CoreConfig`.

#### Scenario: Проектные серверы не попадают в чужой проект
- **WHEN** ядро собрано с `projectRoot: /A`, `CoreConfig.mcpServers` содержит сервер проекта `/A`, а `withoutProject.mcpServers` пуст, и клиент создаёт сессию с `cwd: /B`
- **THEN** сессия `/B` не подключает сервер проекта `/A`, лог `config.session.outside_root` с `cwd: /B`

#### Scenario: Подкаталог — другой корень
- **WHEN** доверенный проект `/A` задаёт `permissions.tools.exec: allow` в `config.local.yaml`, а сессия создана с `cwd: /A/sub`
- **THEN** правило `allow` к сессии не применяется, режим и правила — из снимка без проекта

#### Scenario: Сессия в корне запуска
- **WHEN** сессия создана с `cwd`, равным `projectRoot`
- **THEN** она получает модель, режим, правила и серверы полного снимка, лога `config.session.outside_root` нет
