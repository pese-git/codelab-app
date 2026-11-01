## MODIFIED Requirements

### Requirement: Команда test-scenario
`codelab test-scenario <файл-или-папка>... --agent <профиль> [--filter <glob по id>] [--timeout <длительность>]` SHALL проигрывать golden-фикстуры ACP (формат `agent-core-architecture` §14, загрузчик `codelab_acp_testing`) против агента, которого задаёт профиль подключения, через `runAgentFixtureOver` (H-04). Для каждой фикстуры SHALL:
1. пропускать с пометкой `SKIP` и причиной фикстуру без роли `agent` и фикстуру с `setup.transport` (её играет транспортный драйвер `codelab-agent` против процесса бинаря);
2. запускать агента по профилю заново для каждой фикстуры:
   - **`{fixture}`.** Подстрока `{fixture}` в аргументах профиля `stdio:` SHALL заменяться путём файла фикстуры: такой агент (например, агент-повторитель) получает фикстуру целиком, и её блок `llm` не требует передачи.
   - **`codelab-agent`.** Для профиля `stdio:`, команда которого — `codelab-agent`, блок `llm` SHALL записываться во временный файл и передаваться флагом `--llm-script` вместе с временным журналом сессий `--sessions-dir`, `setup.mode` — флагом `--permission-mode`.
   - **`embedded`.** Для профиля `embedded` агент SHALL открываться в процессе CLI открывателем `scriptedEmbeddedAgentOpener` (`package:codelab_embedded/testing.dart`, импорт только из `lib/src/scenario/`):
     - блок `llm` фикстуры передаётся как сценарий модели;
     - профиль хоста — `setup.profile` фикстуры (по умолчанию `agent-serve`: файлы и команды через клиента-драйвер, как у бинаря по stdio);
     - режим — `setup.mode`;
     - журнал сессий и `CODELAB_HOME` — во временной папке фикстуры, которая удаляется после неё вместе с `dispose` агента (design.md change `add-embedded-agent-mode`, D8).
   - **Пропуски `codelab-agent` и `embedded`.** Фикстура с `setup.sessions`, `setup.config`, `setup.web` или профилем вне множества, которое поддерживает агент, SHALL пропускаться с причиной. Для `codelab-agent` это множество — `agent-serve`, для `embedded` — `agent-serve` и `embedded-cli`.
   - **Сторонний агент.** Для другого агента без `{fixture}` фикстура с блоком `llm` SHALL пропускаться с причиной.
   - **`setup.mcp`.** Фикстура с непустым `setup.mcp` SHALL пропускаться для любого агента, который не получает фикстуру через `{fixture}` (`codelab-agent`, `embedded`, сторонний агент, профиль `ws:`), с причиной `setup.mcp cannot be passed to the agent process`: fake MCP-серверы живут в памяти агентского прогона и агенту не передаются (design.md change `add-agent-mcp-client`, D15). Агент-повторитель с `{fixture}` такую фикстуру играет;
3. проигрывать кадры клиента и сравнивать нормализованные кадры агента по правилам корпуса; при первом расхождении — `FAIL` с диффом ожидаемого и фактического кадра.

`--timeout` (по умолчанию `30s`) SHALL ограничивать ожидание кадра агента.

#### Scenario: Корпус против агента-повторителя
- **WHEN** `test-scenario` запускается на корпусе против процессного `FixtureReplayAgent` с `{fixture}` в аргументах профиля
- **THEN** каждая фикстура с ролью `agent` без `setup.transport` даёт `PASS`, остальные — `SKIP`, код выхода `0`

#### Scenario: Корпус против встроенного агента
- **WHEN** выполняется `codelab test-scenario packages/dart/codelab_acp_testing/fixtures/acp --agent embedded`
- **THEN** ни одна фикстура не даёт `FAIL`, пропущенные имеют причину, код выхода `0`, ни один дочерний процесс агента не запущен

#### Scenario: Сторонний агент и сценарий модели
- **WHEN** профиль — сторонний агент без `{fixture}`, а у фикстуры есть блок `llm`
- **THEN** строка фикстуры — `SKIP` с причиной, агент не запускается

#### Scenario: Испорченный ожидаемый кадр
- **WHEN** у фикстуры изменён ожидаемый кадр агента
- **THEN** строка фикстуры — `FAIL` с диффом кадров, код выхода `1`

#### Scenario: Фильтр
- **WHEN** передан `--filter 'acp/session-*'`
- **THEN** проигрываются только фикстуры с подходящим id

#### Scenario: Фикстура с fake MCP-серверами
- **WHEN** `test-scenario` проигрывает `acp/mcp-stdio-tool-call` (непустой `setup.mcp`) против профиля `stdio:` с командой `codelab-agent` или против `embedded`
- **THEN** строка фикстуры — `SKIP` с причиной `setup.mcp cannot be passed to the agent process`, агент не запускается

#### Scenario: Повторитель играет фикстуру с MCP
- **WHEN** профиль — агент-повторитель с `{fixture}` в аргументах, а у фикстуры непустой `setup.mcp`
- **THEN** фикстура проигрывается, а не пропускается
