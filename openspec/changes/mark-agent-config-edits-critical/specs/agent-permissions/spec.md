## ADDED Requirements

### Requirement: Пометка критичности вопроса о конфигурации агента
Вопрос о вызове с целью из путей конфигурации агента (requirement «Критические пути правок конфигурации агента», PERM-11) SHALL быть критическим так же, как вопрос о критической команде (design.md change `mark-agent-config-edits-critical`, D1–D4):
- `PermissionRequest.criticalLabel` SHALL быть `write to agent configuration` — та же метка, что у критического шаблона `exec` для записи в конфигурацию агента; строка метки SHALL задаваться в одном месте для обеих веток политики;
- `reason` SHALL оставаться `agent configuration: <path>`, где `<path>` — путь цели в том виде, в котором его показывает отказ `Editing agent configuration requires a human: <path>`;
- `allowAlwaysOffered` SHALL быть `false`; отказ в `autopilot` и без gate — без изменений (PERM-11).

Пометка SHALL ставиться для любого пути PERM-11 — проектного списка §7.6.1 и путей хоста `AgentCoreServices.agentConfigPaths`, — в любом режиме с человеком, в том числе у сессии с типом агента, режим которого задан определением агента.

Лог `permission.asked` SHALL писать поле `critical` равным `criticalLabel != null`: `true` у вопросов о критической команде и о конфигурации агента, `false` у остальных, в том числе у вопроса с `reason` без метки.

#### Scenario: write в проектный конфиг в bypass
- **WHEN** в режиме `bypass` модель вызывает `write` с путём `.codelab/config.yaml`
- **THEN** gate получает один запрос с `criticalLabel: 'write to agent configuration'`, `reason: 'agent configuration: .codelab/config.yaml'` и `allowAlwaysOffered: false`

#### Scenario: edit пути хоста
- **WHEN** хост передал `agentConfigPaths` с `$CODELAB_HOME/config.yaml`, и модель в режиме `accept-edits` вызывает `edit ~/.codelab/config.yaml`
- **THEN** запрос gate несёт `criticalLabel: 'write to agent configuration'` и не предлагает `allow_always`

#### Scenario: Одна метка для write и exec
- **WHEN** в режиме `bypass` модель вызывает `write .codelab/config.local.yaml`, затем `exec` с `echo x > .codelab/config.local.yaml`
- **THEN** у обоих запросов `criticalLabel` — одна и та же строка `write to agent configuration`; `reason` первого — `agent configuration: .codelab/config.local.yaml`, второго — `critical command: write to agent configuration`

#### Scenario: Обычная правка не критична
- **WHEN** в режиме `standard` модель вызывает `edit README.md`
- **THEN** запрос gate без `criticalLabel`, лог `permission.asked` с `critical: false`

#### Scenario: Поле лога
- **WHEN** в режиме `bypass` модель вызывает `write .codelab/agents/x.md`, а в режиме `standard` — `exec` с командой без критического шаблона
- **THEN** первый `permission.asked` содержит `critical: true`, второй — `critical: false`

#### Scenario: Тип агента с режимом bypass
- **WHEN** выбран тип агента с `mode: bypass`, и модель вызывает `exec rm -rf /`, затем `write .codelab/config.yaml`
- **THEN** оба запроса gate несут `criticalLabel`, второй — `write to agent configuration`, ни один не предлагает `allow_always`

#### Scenario: autopilot без изменений
- **WHEN** в `autopilot` модель вызывает `write .codelab/config.yaml`
- **THEN** вопроса нет, вызов отклонён с `Editing agent configuration requires a human: .codelab/config.yaml`
