## ADDED Requirements

### Requirement: Живая перезагрузка конфигурации
`AgentCoreServices` SHALL принимать необязательный порт `ConfigSource {ConfigLoadResult initial; Future<ConfigLoadResult> load(); Stream<void> changes}` (design.md, D7, D8). `initial` — результат стартовой загрузки, с которым хост собрал ядро; `load()` SHALL оценивать доверие проектам по `initial.config.trustedProjects` до перезапуска (через `CoreConfig.fromLayers(..., pinnedTrustedProjects:)`). Если порт передан, `buildAgentCore` SHALL требовать параметр `modelsFor` — функцию хоста, которая строит функцию модели и каталог по `CoreConfig`; без него — `HostWiringException`. Без порта перезагрузки нет, команда `/config` не объявляется.

`buildAgentCore` SHALL сохранять обязательный `streamFunction` — функцию модели начального снимка; начальный каталог — `AgentCoreServices.models`. `modelsFor` при сборке НЕ SHALL вызываться: его вызывает только перезагрузка на каждом применённом снимке. Без `ConfigSource` `modelsFor` не требуется.

`ConfigLoadResult` SHALL нести плоскую карту листьев итогового дерева `values` (пути как у `SettingsRegistry`; элемент `mcp.servers` — целиком под `mcp.servers[<name>]`); по ней перезагрузка строит список изменённых ключей. Рантайм SHALL хранить `values` и `HostSettings` применённого снимка.

`AgentRuntime` SHALL предоставлять:
- `reloadConfig()` → `ConfigApplyReport {outcome: applied | unchanged | failed, issues, changedKeys, restartRequiredKeys}`;
- `checkConfig()` → результат загрузки без применения — по закреплённому доверию из `initial`; новое значение `trusted_projects` и другие отложенные ключи SHALL попадать в `Restart required`;
- `configStatus()` → `{loadedAt, sources, lastFailureAt, lastIssues, pendingRestartKeys}`.

Сигнал `ConfigSource.changes` SHALL запускать `reloadConfig()`. Подписка принадлежит рантайму и SHALL отменяться в `dispose()`.

**Порядок `reloadConfig()`:**
1. **Коалесценция.** Если перезагрузка уже идёт, вызов SHALL ставить не больше одного повтора и получать его итог.
2. **Загрузка.** Вызывается `ConfigSource.load()`. После `dispose()` результат SHALL отбрасываться: снимок не меняется, уведомлений и замен MCP нет.
3. **Невалидный конфиг.** Прежний снимок SHALL оставаться целиком (CFG-15). Клиентам НЕ SHALL уходить ни одно уведомление. `configStatus` получает `lastFailureAt` и `lastIssues`, лог — `config.reload.failed` с источниками, строками и путями ключей, без значений. Итог — `failed`.
4. **Ключи перезапуска.** Отложенными SHALL быть:
   - ключи с `restartRequired` в реестре настроек: `sessions.*`, `logging.*`, `profile.*`, `secrets.backend`, `config.*`;
   - ключи, ослабляющие права (R0-1): `permissions.*`, `trusted_projects`; включённый элемент `mcp.servers[<name>]` с `type: stdio`, для которого в применённом снимке нет элемента `old` с `old.enabled && old.sameConnection(new)` (новый, включённый из `enabled: false`, сменивший тип `http` → `stdio`, с другими `command`, `args` или `env`, в том числе шаблонами `${secret:…}`);
   - правки, способные направить секрет на другой адрес (R0-4). «Ссылка на секрет» определяется по значению: любая подстановка `${…}` — `${secret:…}` или `${VAR}`. Отложены: включённый элемент `mcp.servers[<name>]` с `type: http` без прежнего `old.enabled && old.sameConnection(new)`, если в `url`, `headers` или `env` есть подстановка; провайдер `providers.<id>` с ключом (в прежнем или новом снимке есть `api_key_secret`, `api_key_env`, подстановка в `base_url`, `headers` или `auth_header` или литеральный секретный заголовок), если он новый или изменилось поле группы `kind`, `base_url`, `headers`, `auth_header`, `api_key_secret`, `api_key_env` — группа атомарна: её поля прежние, модели новые; каждая ссылка на модели нового отложенного провайдера (`agent.default_model`; с потребителем — `agent.fallback`, `agent.summary_model`, `llm.roles.*`, модели субагентов).

   Отложенные ключи SHALL браться из применённого снимка (design.md, D8, «Пересборка снимка с отложенными ключами»): доверие закрепляет ядро — `CoreConfig.fromLayers(..., pinnedTrustedProjects:)` получает список из `initial` и строит по нему и проектные слои, и `CoreConfig.trustedProjects` (с `withoutProject`), по которому новая сессия читает `prompts` и `agents`; остальное подставляет `CoreConfig.withDeferred` (`permissions`, элементы серверов, группа полей провайдера с прежними `key` и `headerTemplates`), а прежние `HostSettings` и `values` — рантайм; затем снимок проверяется семантически заново. Отложенная ссылка на модель нового провайдера НЕ SHALL давать итог `failed`. Ключи SHALL попадать в `restartRequiredKeys` и `pendingRestartKeys`; лог — `config.reload.restart_required {keys}`. Удаление и выключение серверов и провайдеров, модели, провайдеры без ключа и HTTP-серверы без подстановок SHALL применяться без перезапуска.
5. **Сброс.** `AgentCoreServices.secrets?.invalidate()` и `modelsFor(next)` SHALL выполняться при каждой успешной загрузке, даже без изменённых ключей.
6. **Замена.** Полный снимок, снимок без проекта, функция модели и каталог SHALL заменяться одной атомарной операцией. Шаг, ход или проверка разрешения читают их один раз и НЕ SHALL видеть смесь двух снимков.
7. **Итог.** Без изменённых ключей — `unchanged` и `config.reload.noop`; иначе — `applied` и `config.reload.applied {keys, restart_required}`.

**Когда действует новое значение** (CFG-16):
- `providers.*` и модели — со следующего шага любой сессии. Сессия, чья текущая модель исчезла из каталога, SHALL продолжать работать на функции модели прежнего снимка до смены модели; рантайм пишет `config.reload.model_orphaned {session_id, model}` один раз на сессию и модель;
- `budget.*`, `compaction.*` — со следующего хода;
- `agent.default_model`, `agent.effort`, `tools.disabled`, `tools.project_context.*` и файлы проекта — для новых сессий;
- `mcp.servers` — требование «Серверы конфигурации при перезагрузке»;
- `permissions.*`, `trusted_projects`, новые или изменённые stdio-серверы и правки R0-4 — только после перезапуска (шаг 4).

Идущий вызов инструмента и идущий запрос разрешения SHALL доигрывать со старыми значениями.

Если каталог моделей изменил список моделей, каждая живая сессия SHALL получить событие `ModelOptionsChanged`. Живая сессия — возвращённая вызывающему до замены и не закрытая. Сессия, создание или загрузка которой началось до замены, SHALL получить снимок начала целиком.

Ошибка перезагрузки, запущенной сигналом, НЕ SHALL теряться и НЕ SHALL уходить в зону хоста: она пишется `config.reload.failed` с `error_class`.

#### Scenario: Права не меняются на лету
- **WHEN** сессия идёт в режиме `standard`, и перезагрузка меняет `permissions.tools.exec` на `allow`, `permissions.mode` на `bypass` и добавляет проект в `trusted_projects`
- **THEN** следующий `exec` спрашивается как прежде; `restartRequiredKeys` и `pendingRestartKeys` содержат `permissions.tools.exec`, `permissions.mode` и `trusted_projects`; лог `config.reload.restart_required` (`config_reload_test.dart`)

#### Scenario: Проект добавлен в trusted_projects
- **WHEN** проект `/w/p` не доверен при старте, его `.codelab/config.yaml` задаёт провайдера `pp` и HTTP-сервер `ph`, и перезагрузка добавляет `/w/p` в `trusted_projects`
- **THEN** в снимке нет ни `pp`, ни `ph`, `CoreConfig.trustedProjects` прежний, новая сессия в `/w/p` не читает `.codelab/prompts` и `.codelab/agents` проекта; `pendingRestartKeys` содержит `trusted_projects`, ответ `/config reload` — со строкой `Restart required: trusted_projects`

#### Scenario: Доверие снято
- **WHEN** проект `/w/p` доверен при старте, его конфиг задаёт `permissions.tools.exec: allow` и HTTP-сервер `ph`, и перезагрузка удаляет `/w/p` из `trusted_projects`
- **THEN** проектные слои по-прежнему оцениваются как доверенные до перезапуска, `pendingRestartKeys` содержит `trusted_projects`

#### Scenario: Секрет на новый адрес
- **WHEN** у провайдера `p` есть `api_key_secret`, и перезагрузка меняет его `base_url` и добавляет модель `p/m2`; одновременно добавляется HTTP-сервер `h` с заголовком `Authorization: "Bearer ${secret:codelab/mcp/h/authorization}"` и HTTP-сервер `h2` без ссылок
- **THEN** модель `p/m2` в каталоге, запросы идут на прежний `base_url`, `h` не подключается, `h2` подключается; `pendingRestartKeys` содержит `providers.p` и `mcp.servers[h]`

#### Scenario: Подстановка по значению
- **WHEN** перезагрузка добавляет HTTP-сервер `a` с заголовком `X-Gw: ${secret:gw}`, HTTP-сервер `b` с `Authorization: Bearer ${GITHUB_TOKEN}` и меняет `base_url` провайдера `q`, у которого `auth_header: "Bearer ${Q_KEY}"`
- **THEN** `a`, `b` и адрес `q` отложены, `pendingRestartKeys` содержит `mcp.servers[a]`, `mcp.servers[b]`, `providers.q`

#### Scenario: Подстановка в base_url
- **WHEN** у провайдера `g` нет `api_key_*` и секретных заголовков, но `base_url: "https://${GW_HOST}/v1"`, и перезагрузка меняет его `headers`
- **THEN** правка отложена, `pendingRestartKeys` содержит `providers.g`

#### Scenario: Новый провайдер с ключом и ссылки на его модели
- **WHEN** перезагрузка добавляет провайдера `n` с `api_key_secret` и модель `n/m`, меняет `agent.default_model` на `n/m` и `budget.max_steps`
- **THEN** итог `applied`, не `failed`; `budget.max_steps` применён; `n` и `agent.default_model` прежние, `pendingRestartKeys` содержит `providers.n` и `agent.default_model`

#### Scenario: Атомарность группы полей провайдера
- **WHEN** у провайдера `p` с ключом одна перезагрузка меняет `base_url` и добавляет модель, а следующая меняет только `headers`
- **THEN** после первой модели новые, а адрес, заголовки и ключ прежние; после второй провайдер целиком прежний; оба раза `pendingRestartKeys` содержит `providers.p`

#### Scenario: Включение stdio-сервера из enabled: false
- **WHEN** stdio-сервер `d` был `enabled: false`, и перезагрузка ставит `enabled: true` без других изменений
- **THEN** `d` не запускается, `pendingRestartKeys` содержит `mcp.servers[d]`

#### Scenario: Смена типа на stdio
- **WHEN** HTTP-сервер `s` конфига меняется на `type: stdio`, а у stdio-сервера `t` в `env` меняется ссылка `${secret:a}` на `${secret:b}`
- **THEN** оба остаются в прежнем виде, `pendingRestartKeys` содержит `mcp.servers[s]` и `mcp.servers[t]`

#### Scenario: Новый stdio-сервер ждёт перезапуска
- **WHEN** перезагрузка добавляет stdio-сервер `x` и HTTP-сервер `h` и удаляет сервер `old`
- **THEN** `h` подключается, `old` закрывается, `x` не запускается, а `pendingRestartKeys` содержит `mcp.servers[x]`

#### Scenario: modelsFor не вызывается при сборке
- **WHEN** ядро собрано с `ConfigSource`, `streamFunction` и `modelsFor`, затем идёт ход, затем перезагрузка с итогом `unchanged`, затем ещё ход
- **THEN** `modelsFor` вызван ровно один раз — перезагрузкой; первый ход шёл на `streamFunction`, второй — на функции из `modelsFor`

#### Scenario: Модель по умолчанию — только новым сессиям
- **WHEN** перезагрузка меняет `agent.default_model` с `a/m1` на `a/m2`
- **THEN** модель идущей сессии остаётся `a/m1`, новая сессия получает `a/m2`

#### Scenario: Невалидная правка
- **WHEN** после ручной правки файл содержит `budget.max_steps: 0`, и срабатывает `changes`
- **THEN** итог `failed`, снимок прежний, ни одно событие сессий не опубликовано, `configStatus().lastIssues` содержит `budget.max_steps`, лог `config.reload.failed` не содержит значений

#### Scenario: Ключ перезапуска
- **WHEN** перезагрузка меняет `logging.file` и `budget.max_steps`
- **THEN** `budget.max_steps` применён, `logging.file` — прежний, `restartRequiredKeys` и `pendingRestartKeys` содержат `logging.file`

#### Scenario: Смена списка моделей
- **WHEN** перезагрузка добавляет модель `a/m3` в каталог
- **THEN** каждая живая сессия получает одно `ModelOptionsChanged`, следующий шаг использует новую функцию модели

#### Scenario: Коалесценция
- **WHEN** во время идущей перезагрузки приходят три сигнала `changes`
- **THEN** `load()` вызывается ещё ровно один раз, и все вызовы получают итог этой загрузки

#### Scenario: dispose во время загрузки
- **WHEN** `load()` ещё не завершился, а рантайм получает `dispose()`
- **THEN** снимок не заменён, событий сессиям и замен MCP нет, исключений в зоне хоста нет

#### Scenario: Замена ключа в хранилище секретов
- **WHEN** ключ провайдера прочитан и закэширован, затем в `secrets.yaml` записано новое значение, и перезагрузка завершается итогом `unchanged`
- **THEN** следующий запрос к провайдеру несёт новое значение ключа

#### Scenario: Хост без источника
- **WHEN** ядро собрано без `ConfigSource` (сценарий `--llm-script`)
- **THEN** подписки нет, `/config` не объявлена, поведение прежнее

### Requirement: Серверы конфигурации при перезагрузке
Применённый снимок с изменённым `mcp.servers` SHALL передаваться каждой живой сессии существующей заменой `McpSessionTools.replaceServers` с полным желаемым списком: серверы нового конфига, затем текущие серверы `session/new` (design.md, D10).
- Сервер клиента с тем же `name` SHALL затенять сервер конфига, как при создании.
- Серверы `session/new` НЕ SHALL переподключаться и закрываться перезагрузкой (CFG-17).
- Неизменённые серверы (`sameConnection`) НЕ SHALL переподключаться. Неизменённый сервер в состоянии `failed` SHALL пробоваться сразу.
- Без хода замена SHALL завершаться до итога `reloadConfig`. Во время хода модели замена SHALL применяться после `TurnEnded`.
- Замены от перезагрузки и от `setMcpServers` SHALL идти через одну очередь сессии со счётчиком поколений: последний желаемый набор побеждает, а результат устаревшей замены НЕ SHALL перекрывать новую.
- Шаблоны `${secret:…}` серверов конфига SHALL раскрываться заново, по правилам требования «MCP-серверы сессии».
- Новые и изменённые stdio-серверы и HTTP-серверы со ссылками на секреты (R0-1, R0-4) в желаемый список НЕ SHALL попадать до перезапуска (требование «Живая перезагрузка конфигурации», шаг 4).
- Серверы с `enabled: false` SHALL передаваться коннектору с признаком `enabled: false` (`McpServerConfig.enabled`): коннектор держит их в состоянии `disabled` без подключения; лог загрузки `mcp.server.skipped` с причиной `disabled in config` сохраняется.

#### Scenario: Изменён адрес одного сервера
- **WHEN** у сессии серверы конфига `a` и `b`, и перезагрузка меняет `url` у `b`
- **THEN** переподключён только `b`, процесс или соединение `a` не трогались (`mcp_apply_config_test.dart`)

#### Scenario: Удаление во время хода
- **WHEN** во время хода перезагрузка удаляет сервер `b`, а модель вызывает `mcp__b__t`
- **THEN** вызов завершается по прежнему набору, после `TurnEnded` сервер `b` закрыт, следующий запрос к модели не содержит `mcp__b__t`

#### Scenario: Сервер клиента не тронут
- **WHEN** у сессии сервер `session/new` `github` и сервер конфига `github`, и перезагрузка меняет конфиговый `github`
- **THEN** сервер клиента не переподключался, сервер конфига по-прежнему затенён

#### Scenario: Последний побеждает
- **WHEN** во время хода две перезагрузки подряд дают наборы HTTP-серверов `{a}` и `{a, c}`
- **THEN** после `TurnEnded` применён `{a, c}`
