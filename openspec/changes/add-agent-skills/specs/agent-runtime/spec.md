## MODIFIED Requirements

### Requirement: Профили хостов и сужение
`HostProfile.of(name)` SHALL знать профили `agent-serve`, `embedded-app-desktop` и `embedded-cli` с явным состоянием каждой capability ядра по таблице §10.4 документа ядра (HOST-1):
- `shellExec`, `fileListing`, `interactiveApproval` — как в этапе 2; в `embedded-app-desktop` — те же состояния, что в `embedded-cli`: `shellExec` и `fileListing` — transport `local`, `interactiveApproval` — transport `acp` (design.md change `add-embedded-agent-mode`, D4);
- `sessionPersistence` — transport `jsonl-file` во всех трёх профилях;
- `compaction` — `on` во всех трёх профилях;
- `mcp` — transport `{stdio, http}` во всех трёх профилях (design.md change `add-agent-mcp-client`, D3);
- `skills` — `on` во всех трёх профилях (design.md change `add-agent-skills`, D11); сужает её только `profile.<name>.skills: off`; выключенная — нет ни секции каталога, ни инструмента `skill`, ни команд `skill:*` (SKL-5, HOST-4). Отсутствие порта `skillFiles` capability не сужает (D16). Ключ `skills.enabled` capability НЕ SHALL сужать ни в `buildAgentCore`, ни у сессии другой папки: он действует на сессию, и `skills.enabled: false` в `CoreConfig` сессии — в том числе сессии в корне запуска — даёт этой сессии пустой снимок навыков без вызова порта (требование «Конфигурация сессии вне корня запуска», решения Q44, Q45).

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

#### Scenario: Навыки выключены конфигом
- **WHEN** ядро собирается в профиле `agent-serve` с `skills.enabled: false`, и клиент создаёт сессию
- **THEN** `CorePlan.offReasons` не содержит `skills`, порт `skillFiles` при открытии сессии не вызывается, у сессии нет секции каталога, инструмента `skill` и команд `skill:*`

#### Scenario: Навыки выключены профилем
- **WHEN** профиль `agent-serve` сужается до `skills: CapabilityOff(…)`
- **THEN** `CorePlan.offReasons` содержит причину для `skills`, порт `skillFiles` при открытии сессии не вызывается

### Requirement: Конфигурация сессии вне корня запуска
Если `CoreConfig.projectRoot` задан и канонический `cwd` новой или загружаемой сессии ему не равен, `AgentRuntime` SHALL строить для сессии конфигурацию **её папки** — полный `CoreConfig` из слоёв папки и свою функцию модели — а не брать снимок корня запуска (design.md change `require-project-folder`, D21; заменяет D9 change `add-agent-configuration`).

**На сессию** SHALL браться всё, что входит в `CoreConfig`:
- провайдеры (`providers.*`) и каталог моделей (`model_catalog.*`);
- модель по умолчанию;
- `effort`;
- режим и правила разрешений (`permissions.*`);
- бюджет хода, пороги сжатия (`compaction.*`, кроме `compaction.enabled`);
- MCP-серверы конфигурации;
- `redact.*`;
- `tools.project_context.max_bytes`;
- `skills.*` (design.md change `add-agent-skills`, D11, решение Q44): `extra_roots`, `disabled`, пределы и `skills.enabled`; корни навыков проекта и `projectTrusted` запроса к порту `skillFiles` считаются по каноническому `cwd` сессии. `skills.enabled: false` папки выключает навыки только сессий этой папки — и для корня запуска, и для других папок: порт `skillFiles` не вызывается, снимок пуст, capability `skills` в `CorePlan` не меняется (решение Q45).

Функция модели (`StreamFunction`) и каталог сессии SHALL строиться функцией хоста `modelsFor` по `CoreConfig` сессии.

**На процесс** SHALL оставаться:
- `HostSettings` (`secrets.*`, в том числе бэкенд, `sessions.*`, `logging.*`, `config.*`, `profile.*`), а также `exec.*` и `compaction.enabled` (capability `compaction`);
- `trusted_projects`;
- capability и сужение профиля, в том числе capability `skills`: её сужает только `profile.<name>.skills: off` (требование «Профили хостов и сужение»), а не `skills.enabled` (решение Q45);
- резолвер секретов, HTTP-клиент, журнал сессий и память последней модели.

**Порт.** `AgentCoreServices` SHALL принимать необязательный порт `ProjectConfigLoader { Future<ConfigLoadResult> loadForProject(String canonicalCwd) }` (поле `projectConfig`). Порт загружает слои `user`, `<cwd>/.codelab/config.yaml`, `<cwd>/.codelab/config.local.yaml`, `--config`, окружения и флагов тем же загрузчиком и окружением, что при старте, с доверием проектам, закреплённым по `initial.config.trustedProjects`; относительный путь `--config` SHALL разрешаться от корня запуска, а не от папки сессии. Если порт передан без `modelsFor`, `buildAgentCore` SHALL бросать `HostWiringException`.

**Порядок.** На каждый вызов `createSession` и `loadSession` сессии вне корня, без кэша, `AgentRuntime` SHALL выполнять шаги по порядку, до создания журнала новой сессии:
1. канонизировать `cwd`;
2. вызвать `loadForProject`;
3. проверить снимок (`validateSnapshot`);
4. вызвать `modelsFor`;
5. выбрать модель сессии по существующему правилу, с памятью последней модели процесса;
6. только потом читать файлы проекта и подключать MCP-серверы.

Каталог сессии SHALL быть доступен как `AgentSession.models` и служить источником вариантов `configOptions` `model`, проверки `session/set_config_option`, выбора модели новой сессии (требование «Модель новой сессии»: «каталог сессии») и модели журнала при `loadSession`. Правка проектных файлов SHALL применяться к следующему `session/new` или `session/load` этой папки; живой перезагрузки проектных слоёв других папок у открытых сессий нет. Перезагрузка конфигурации корня (`reloadConfig`) НЕ SHALL менять функцию модели и конфигурацию сессий других папок.

**Ключи процесса из папки сессии.** Ключи процесса, которые слои папки сессии задают иначе, чем применённый снимок, НЕ SHALL применяться. Сравниваются только ключи, которые есть в `values` загрузки папки и отличаются от применённых; ключ, который задаёт только корень, предупреждения не даёт. По одному разу на папку SHALL писаться `config.session.process_keys_ignored {session_id, keys}` — только ключи показа, без значений.

**Проблемы (fail closed).** Если загрузка, проверка снимка или `modelsFor` дали проблемы или исключение, сессия НЕ SHALL создаваться или загружаться: журнал новой сессии не создаётся (её нет в `listSessions`), журнал загружаемой не меняется. Ни снимок корня, ни снимок без проекта НЕ SHALL подставляться. `AgentRuntime` SHALL бросать типизированную ошибку `ProjectConfigException {cwd, issues}`. Её текст — проблемы в форме `config check`, без значений секретов и подставленных переменных.

**Отмена.** Остановка рантайма во время этих шагов SHALL прерывать ожидание. Сессия при этом не создаётся, MCP-процессы не стартуют.

**Канонизация `cwd`.** Перед сравнением (`CoreConfig.forSessionCwd`) `cwd` сессии SHALL канонизироваться портом `PathResolver.realpath` базового окружения; ядро само путь не раскрывает. Если путь не раскрылся, сравнивается нормализованная запись пути, и `loadForProject` получает её же. Сравнивается равенство канонических путей по компонентам, а не вложенность: подкаталог корня — своя папка.

**Лог.** На каждую такую папку SHALL писаться один лог `config.session.project {session_id, cwd, config_root, trusted}` уровня `info`. Отказ SHALL писаться `config.session.project_invalid {cwd, issues}` уровня `error`; `issues` — источник, строка, столбец, путь ключа и класс проблемы, без текстов и значений.

**Без порта** поведение прежнее: сессия вне корня получает `CoreConfig.withoutProject`, пишется лог `config.session.outside_root {session_id, cwd, config_root}`. Без `projectRoot` все сессии получают `CoreConfig`.

#### Scenario: Запреты проекта сессии применяются вне корня запуска
- **WHEN** ядро собрано с `projectRoot: /A` и портом, проект `/B` доверенный, `/B/.codelab/config.yaml` задаёт `permissions.deny: ["exec:rm -rf"]`, и клиент создаёт сессию с `cwd: /B`
- **THEN** у сессии `/B` действует запрет `exec:rm -rf`, правила `/A` к ней не применяются, лог `config.session.project` с `cwd: /B`

#### Scenario: Недоверенный проект сессии только ужесточает
- **WHEN** проект `/B` недоверенный, задаёт `permissions.mode: bypass`, `permissions.deny: ["write:.env"]` и `providers.evil`, и сессия создаётся с `cwd: /B`
- **THEN** режим — из глобального слоя, запрет `write:.env` действует, провайдера `evil` в каталоге сессии нет (`config.project.untrusted_key`)

#### Scenario: Провайдер проекта работает в его сессиях без перезапуска
- **WHEN** агент запущен с корнем `/A`, доверенный `/B/.codelab/config.local.yaml` задаёт провайдера `local` и `agent.default_model: local/m`, и клиент создаёт сессию с `cwd: /B`
- **THEN** модель сессии `/B` — `local/m`, `configOptions` `model` содержит `local/m`, а у сессии `/A` в каталоге нет `local`

#### Scenario: Проектные серверы не попадают в чужой проект
- **WHEN** ядро собрано с `projectRoot: /A`, `CoreConfig.mcpServers` содержит сервер проекта `/A`, проект `/B` своих серверов не задаёт, и клиент создаёт сессию с `cwd: /B`
- **THEN** сессия `/B` не подключает сервер проекта `/A`

#### Scenario: Ключи процесса из папки сессии игнорируются
- **WHEN** `/B/.codelab/config.local.yaml` задаёт `sessions.dir` и `logging.level`
- **THEN** сессия `/B` создаётся, журнал и логи — процесса, лог `config.session.process_keys_ignored` с ключами и без значений

#### Scenario: Ключ процесса задаёт только корень
- **WHEN** доверенный `config.local.yaml` корня `/A` задаёт `logging.level: debug`, а `/B` ключей процесса не задаёт, и клиент создаёт сессию с `cwd: /B`
- **THEN** лога `config.session.process_keys_ignored` нет

#### Scenario: Битый конфиг проекта сессии
- **WHEN** `/B/.codelab/config.yaml` не разбирается, и клиент создаёт сессию с `cwd: /B`
- **THEN** сессия не создаётся, `AgentRuntime` бросает `ProjectConfigException` с проблемой и путём файла; снимок без проекта не подставлен, журнала сессии нет (`listSessions` её не возвращает), лог `config.session.project_invalid`

#### Scenario: Правка проекта применяется к следующей сессии
- **WHEN** сессия `/B` открыта, затем в `/B/.codelab/config.yaml` добавлен запрет, и клиент создаёт вторую сессию в `/B`
- **THEN** вторая сессия получает новый запрет без перезагрузки и перезапуска, первая — прежние правила

#### Scenario: Перезагрузка корня не трогает сессии других папок
- **WHEN** открыта сессия `/B` с моделью `local/m`, и `reloadConfig()` применяет новый снимок корня `/A`, где нет провайдера `local`
- **THEN** сессия `/B` по-прежнему ходит в `local/m`

#### Scenario: Остановка во время загрузки
- **WHEN** `loadForProject` для `/B` ещё не завершился, и рантайм останавливается
- **THEN** `session/new` завершается ошибкой, сессии нет, MCP-серверы `/B` не запускались

#### Scenario: Подкаталог — своя папка
- **WHEN** доверенный проект `/A` задаёт `permissions.tools.exec: allow` в `config.local.yaml`, у `/A/sub` своего `.codelab/` нет, и сессия создана с `cwd: /A/sub`
- **THEN** правило `allow` проекта `/A` к сессии не применяется, конфигурация — из глобальных слоёв

#### Scenario: Сессия в корне запуска
- **WHEN** сессия создана с `cwd`, равным `projectRoot`
- **THEN** она получает применённый снимок и функцию модели процесса, `loadForProject` не вызывается, лога `config.session.project` нет

#### Scenario: cwd через symlink
- **WHEN** ядро собрано с `projectRoot: /A` и портом, `/L` — symlink на `/A`, `/M` — symlink на доверенный `/B`
- **THEN** сессия с `cwd: /L` получает применённый снимок, `loadForProject` не вызывается; сессия с `cwd: /M` получает конфигурацию `loadForProject('/B')` — канонического пути

#### Scenario: Без порта — прежнее поведение
- **WHEN** ядро собрано без `ProjectConfigLoader`, с `projectRoot: /A`, и сессия создана с `cwd: /B`
- **THEN** сессия получает `withoutProject`, лог `config.session.outside_root`

#### Scenario: Навыки сессии вне корня запуска
- **WHEN** ядро собрано с `projectRoot: /A`, портом `ProjectConfigLoader` и портом `skillFiles`, `/A/.codelab/config.yaml` задаёт `skills.disabled: [pdf]`, доверенный `/B/.codelab/config.local.yaml` — `skills.disabled: [notes]` и `skills.extra_roots: [/opt/b]`, порт навыков находит `pdf` и `notes`, и клиент создаёт сессию с `cwd: /B`
- **THEN** запрос к порту навыков — `cwd: /B`, `projectTrusted: true`, `extraRoots: [/opt/b]`; в каталоге сессии `/B` есть `pdf` и нет `notes`, а у сессии `/A` нет `pdf`

#### Scenario: Навыки выключены только в сессиях папки
- **WHEN** ядро собрано с `projectRoot: /A` и портом, конфигурация корня навыки не выключает, доверенный `/B/.codelab/config.yaml` задаёт `skills.enabled: false`, и клиент создаёт сессии с `cwd: /B` и `cwd: /A`
- **THEN** для сессии `/B` порт навыков не вызывается и её каталог пуст, сессия `/A` получает навыки, `CorePlan.offReasons` не содержит `skills`, лога `config.session.process_keys_ignored` с ключом `skills.enabled` нет

#### Scenario: Недоверенный проект сессии не расширяет навыки
- **WHEN** глобальный слой задаёт `skills.disabled: [pdf]` и `skills.max_skills: 50`, недоверенный `/B/.codelab/config.local.yaml` — `skills.disabled: [notes]`, `skills.max_skills: 1000` и `skills.extra_roots: [/opt/evil]`, и клиент создаёт сессию с `cwd: /B`
- **THEN** запрос к порту навыков — `projectTrusted: false`, без `/opt/evil` в `extraRoots`; в конфигурации сессии `skills.disabled` — `[pdf, notes]`, `skills.max_skills` — `50`, есть `config.project.untrusted_key` по `skills.max_skills` и `skills.extra_roots` (решения Q40, Q43)

#### Scenario: Навыки выключены в корне запуска
- **WHEN** ядро собрано с `projectRoot: /A` и портом, `/A/.codelab/config.yaml` задаёт `skills.enabled: false`, доверенный `/B` задаёт `skills.enabled: true` (или ключа не задаёт), порт навыков находит `pdf`, и клиент создаёт сессии с `cwd: /A` и `cwd: /B`
- **THEN** `CorePlan.offReasons` не содержит `skills`; для сессии `/A` порт навыков не вызывается и её каталог пуст; сессия `/B` получает `pdf` (решение Q45)
