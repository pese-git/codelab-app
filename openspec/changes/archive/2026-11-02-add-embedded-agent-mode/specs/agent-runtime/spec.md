## MODIFIED Requirements

### Requirement: Профили хостов и сужение
`HostProfile.of(name)` SHALL знать профили `agent-serve`, `embedded-app-desktop` и `embedded-cli` с явным состоянием каждой capability ядра по таблице §10.4 документа ядра (HOST-1):
- `shellExec`, `fileListing`, `interactiveApproval` — как в этапе 2; в `embedded-app-desktop` — те же состояния, что в `embedded-cli`: `shellExec` и `fileListing` — transport `local`, `interactiveApproval` — transport `acp` (design.md change `add-embedded-agent-mode`, D4);
- `sessionPersistence` — transport `jsonl-file` во всех трёх профилях;
- `compaction` — `on` во всех трёх профилях;
- `mcp` — transport `{stdio, http}` во всех трёх профилях (design.md change `add-agent-mcp-client`, D3).

Для неизвестного имени `of` бросает `ArgumentError`. Состояния `off` и `transport` SHALL нести непустую причину.

Режим новой сессии по умолчанию во всех трёх профилях — `standard` (§10.5).

`narrowed(overrides)` SHALL принимать только сужение: `on` → `transport` → `off` и `transport(A)` → `transport(B)` при `B ⊆ A`. Расширение SHALL давать `HostWiringException` с именем capability (HOST-2).

#### Scenario: Расширение запрещено
- **WHEN** у профиля с `fileListing: off` вызывается `narrowed({fileListing: CapabilityOn()})`
- **THEN** вызов бросает `HostWiringException`, называющий `fileListing`

#### Scenario: Журнал в памяти для тестов
- **WHEN** профиль `agent-serve` сужается до `sessionPersistence: off` и собирается над `MemorySessionStore`
- **THEN** сборка не бросает исключения, а `CorePlan.offReasons` содержит причину для `sessionPersistence`

#### Scenario: Сужение транспортов MCP
- **WHEN** у `agent-serve` вызывается `narrowed({mcp: CapabilityTransport({'http'}, …)})`, а затем `narrowed({mcp: CapabilityTransport({'http', 'stdio'}, …)})`
- **THEN** первое сужение принято, второе бросает `HostWiringException`, называющий `mcp`

#### Scenario: Профиль встроенного агента приложения
- **WHEN** вызывается `HostProfile.of('embedded-app-desktop')`
- **THEN** состояния всех capability и режим по умолчанию совпадают с `embedded-cli`, а golden-матрица `test/host/profiles/embedded-app-desktop.golden.json` (схемы инструментов, секции промпта, slash-команды) совпадает с матрицей `embedded-cli`

#### Scenario: Паритет профилей
- **WHEN** один сценарий модели («прочитай файл, измени, покажи план») проходит через ядро в профилях `agent-serve`, `embedded-app-desktop` и `embedded-cli` с одинаковыми ответами на запросы разрешений
- **THEN** последовательности `AgentEvent` трёх прогонов совпадают; различаются только env и gate хоста (§10.12)
