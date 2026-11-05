# cli-scenario-driver Specification

## Purpose
Драйвер фикстур `codelab test-scenario` проигрывает golden-фикстуры ACP против агента любого профиля (`codelab-agent`, сторонний агент, агент-повторитель) тем же алгоритмом, что тесты агента, и печатает `PASS|FAIL|SKIP` с расхождением кадров (H-04). Устройство — `docs/architecture/proposals/dart-agent-and-clients/09-11-stage-6-cli-mvp.md`, формат фикстур — `docs/architecture/proposals/agent-core/14-golden-fixtures.md`.
## Requirements
### Requirement: Команда test-scenario
`codelab test-scenario <файл-или-папка>... [--agent <профиль>] [--filter <glob по id>] [--timeout <длительность>]` SHALL проигрывать golden-фикстуры ACP (формат `agent-core-architecture` §14, загрузчик `codelab_acp_testing`) против агента, которого задаёт профиль подключения, через `runAgentFixtureOver` (H-04).

Без `--agent` агент SHALL выбираться так же, как во всём CLI (capability `codelab-cli`, «Профили подключения CLI»; design.md change `add-app-settings-shell`, D21; D13, п. 7 change `add-embedded-agent-mode`): всегда встроенный агент, как с `--agent embedded`; `--agent default` — алиас `--agent embedded`: встроенный агент; запись из `profiles.json` для выбора не используется. Файл читается только ради предупреждения о старой записи `default` (codelab-cli), и любая ошибка этого чтения игнорируется. Без `--agent` драйвер НЕ SHALL читать `profiles.json`; битый `profiles.json` при `--agent <id>` SHALL давать код `64` с причиной. О неявном выборе встроенного агента драйвер не сообщает отдельной строкой (D13, п. 8).

Для каждой фикстуры SHALL:
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

#### Scenario: Без --agent и без профиля default
- **WHEN** выполняется `codelab test-scenario packages/dart/codelab_acp_testing/fixtures/acp` с временным `CODELAB_HOME` без `profiles.json`
- **THEN** фикстуры играются против встроенного агента, как с `--agent embedded`: ни одна не даёт `FAIL`, код `0`, ни один дочерний процесс агента не запущен

#### Scenario: Без --agent при профиле default
- **WHEN** `profiles.json` содержит профиль `default` с агентом-повторителем и `{fixture}` в аргументах, и `test-scenario` запускается без `--agent`
- **THEN** фикстуры играются против встроенного агента, процесс из профиля `default` не запускается

#### Scenario: --agent default — встроенный агент
- **WHEN** тот же `profiles.json`, и `test-scenario` запускается с `--agent default`
- **THEN** фикстуры играются против встроенного агента, как с `--agent embedded`; процесс из записи `default` не запускается, а stderr содержит одно предупреждение о проигнорированной записи

#### Scenario: Без --agent битый profiles.json
- **WHEN** `profiles.json` в `CODELAB_HOME` — не JSON, и `test-scenario` запускается без `--agent`
- **THEN** фикстуры играются против встроенного агента, код выхода не `64`

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

### Requirement: Вывод и коды выхода test-scenario
Драйвер SHALL печатать в stdout строку `PASS|FAIL|SKIP <id> (<время>)` на фикстуру в порядке id, дифф `FAIL` — под строкой фикстуры, и итог `<passed> passed, <failed> failed, <skipped> skipped`. Код выхода SHALL быть:
- `0` — нет `FAIL` и сыграна хотя бы одна фикстура (`PASS`);
- `1` — есть хотя бы один `FAIL`, агент не запустился или не сыграна ни одна фикстура: все пропущены (`SKIP`) или фильтр не выбрал ни одной. Последний случай — для любого агента; в stderr SHALL печататься `codelab: no fixtures were played`, итоговая строка в stdout остаётся. Иначе прогон, который ничего не проверил (забытый `{fixture}`, опечатка в `--filter`), выглядел бы успешным (design.md change `add-embedded-agent-mode`, D13, п. 10);
- `64` — ошибка использования (нет пути, путь не существует, неверный профиль, битый файл фикстуры, битый `profiles.json`).

#### Scenario: Битая фикстура
- **WHEN** путь указывает на файл, который не проходит загрузчик фикстур
- **THEN** в stderr — путь и причина `FixtureFormatException`, код выхода `64`

#### Scenario: Все фикстуры пропущены
- **WHEN** `test-scenario` проигрывает только `acp/mcp-stdio-tool-call` против `--agent embedded`
- **THEN** строка фикстуры — `SKIP` с причиной, итог `0 passed, 0 failed, 1 skipped`, в stderr — `codelab: no fixtures were played`, код выхода `1`

#### Scenario: Фильтр не выбрал фикстур
- **WHEN** передан `--filter 'acp/no-such-*'`, которому не соответствует ни одна фикстура
- **THEN** итог `0 passed, 0 failed, 0 skipped`, в stderr — `codelab: no fixtures were played`, код выхода `1`

