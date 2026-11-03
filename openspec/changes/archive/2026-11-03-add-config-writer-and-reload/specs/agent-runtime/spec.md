## ADDED Requirements

### Requirement: Живая перезагрузка конфигурации
`AgentCoreServices` SHALL принимать необязательный порт `ConfigSource {ConfigLoadResult initial; Future<ConfigLoadResult> load({bool rebase = true}); Stream<void> changes}` (design.md, D7, D8). `initial` — результат стартовой загрузки, с которым хост собрал ядро; `load()` SHALL оценивать доверие проектам по `initial.config.trustedProjects` до перезапуска (через `CoreConfig.fromLayers(..., pinnedTrustedProjects:)`). Если порт передан, `buildAgentCore` SHALL требовать параметр `modelsFor` — функцию хоста, которая строит функцию модели и каталог по `CoreConfig`; без него — `HostWiringException`. Без порта перезагрузки нет, команда `/config` не объявляется.

`buildAgentCore` SHALL сохранять обязательный `streamFunction` — функцию модели начального снимка; начальный каталог — `AgentCoreServices.models`. `modelsFor` при сборке НЕ SHALL вызываться: его вызывает только перезагрузка на каждом применённом снимке. Без `ConfigSource` `modelsFor` не требуется.

`ConfigLoadResult` SHALL нести плоскую карту листьев итогового дерева `values` (пути как у `SettingsRegistry`; элемент `mcp.servers` — целиком под `mcp.servers[<name>]`); по ней перезагрузка строит список изменённых ключей. Рантайм SHALL хранить `values` и `HostSettings` применённого снимка.

`AgentRuntime` SHALL предоставлять:
- `reloadConfig()` → `ConfigApplyReport {outcome: applied | unchanged | failed, issues, changedKeys, restartRequiredKeys}`. `changedKeys` — применённые листья; `restartRequiredKeys` — ключи показа (лист, `mcp.servers[<name>]`, `providers.<id>`); оба SHALL быть отсортированы. `reloadConfig()` НЕ SHALL бросать при проблемах конфига и исключениях загрузки или сборки модели;
- `checkConfig()` → `ConfigLoadResult` загрузки без применения — по закреплённому доверию из `initial`; состояние рантайма НЕ SHALL меняться. Валидную загрузку `checkConfig()` SHALL прогонять тем же планом, что перезагрузка, и `CoreConfig.withDeferred(...)` с `validateSnapshot()`: ошибка повторной проверки — проблема результата, как у `reloadConfig()`. Загрузка проверки НЕ SHALL сдвигать базу сравнения наблюдателя: `ConfigSource.load(rebase: false)`, `rebase()` — только на пути перезагрузки (design.md, D7, D8). Новое значение `trusted_projects` и другие отложенные ключи SHALL приходить предупреждениями результата с `event: 'config.reload.restart_required'` и ключом показа в `key`; по ним команда `/config check` печатает строку `Restart required`. Исключение загрузки уходит вызывающему;
- `configStatus()` → `{loadedAt, sources, lastFailureAt, lastIssues, pendingRestartKeys}`; работает и без `ConfigSource`.

Без `ConfigSource` `reloadConfig()` и `checkConfig()` SHALL бросать `StateError`.

Сигнал `ConfigSource.changes` SHALL запускать `reloadConfig()`. Подписка принадлежит рантайму и SHALL отменяться в `dispose()`.

**Порядок `reloadConfig()`:**
1. **Коалесценция.** Если перезагрузка уже идёт, вызов SHALL ставить не больше одного повтора и получать его итог.
2. **Загрузка.** Вызывается `ConfigSource.load()`. После `dispose()` результат SHALL отбрасываться с итогом `unchanged`: снимок и `configStatus` не меняются, уведомлений и замен MCP нет.
3. **Невалидный конфиг.** Прежний снимок SHALL оставаться целиком (CFG-15). Клиентам НЕ SHALL уходить ни одно уведомление. `configStatus` получает `lastFailureAt` и `lastIssues`, лог — `config.reload.failed` с источниками, строками и путями ключей, без значений. Итог — `failed`. Исключение `load()` или `modelsFor` SHALL давать тот же итог `failed` (снимок прежний, `lastFailureAt` и `lastIssues` обновлены) и лог `config.reload.failed {error_class}`; текст исключения НЕ SHALL попадать ни в лог, ни в `lastIssues`.
4. **Ключи перезапуска.** Ключи diff — листья итогового дерева; список сравнивается целиком и даёт один ключ, по элементам развёрнут только `mcp.servers[<name>]`. Отложенными SHALL быть:
   - ключи с `restartRequired` в реестре настроек: `sessions.*`, `logging.*`, `profile.*`, `secrets.backend`, `config.*`;
   - ключ diff, для которого реестр настроек не нашёл дескриптора (fail closed);
   - ключи, ослабляющие права (R0-1): `permissions.*`, `trusted_projects`; элемент `mcp.servers[<name>]` с `type: stdio`, для которого в применённом снимке нет элемента `old` с `old.sameConnection(new) && (old.enabled || !new.enabled)` (новый, в том числе сразу с `enabled: false`; включённый из `enabled: false`; сменивший тип `http` → `stdio`; с другими `command`, `args` или `env`, в том числе шаблонами `${secret:…}`). Правило SHALL действовать и для выключенного сервера (R6-1): правка параметров соединения сервера с `enabled: false` откладывается так же, как у включённого. Если правка одновременно выключает сервер и меняет параметры соединения, выключение SHALL применяться сразу, а в применённом снимке SHALL оставаться прежний элемент с `enabled: false`;
   - правки, способные направить секрет на другой адрес (R0-4). «Ссылка на секрет» определяется по значению: любая подстановка `${…}` — `${secret:…}` или `${VAR}`. Отложены: элемент `mcp.servers[<name>]` с `type: http` без прежнего `old` с `old.sameConnection(new) && (old.enabled || !new.enabled)`, если в `url`, `headers` или `env` есть подстановка, — в том числе выключенный (R6-1); провайдер `providers.<id>` с ключом (в прежнем или новом снимке есть `api_key_secret`, `api_key_env`, подстановка в `base_url`, `headers` или `auth_header` или литеральный секретный заголовок), если он новый или изменилось поле группы `kind`, `base_url`, `headers`, `auth_header`, `api_key_secret`, `api_key_env` — группа атомарна: её поля прежние, модели новые; каждая ссылка на модели нового отложенного провайдера (`agent.default_model`; с потребителем — `agent.fallback`, `agent.summary_model`, `llm.roles.*`, модели субагентов).

   План SHALL строиться по обоим снимкам — полному и `withoutProject` (сессии вне корня запуска получают второй): ключ отложен, если он отложен по сравнению любого из них. Ключ, который в полном снимке перекрыт проектным слоем, а в `withoutProject` изменился, SHALL откладываться так же. Набор отложенного SHALL передаваться в `CoreConfig.withDeferred` структурированно (признак `permissions`, имена серверов и провайдеров, ссылки на модели), а не строками ключей показа с повторным разбором: имя сервера может содержать `]`.

   Отложенные ключи SHALL браться из применённого снимка (design.md, D8, «Пересборка снимка с отложенными ключами»): доверие закрепляет ядро — `CoreConfig.fromLayers(..., pinnedTrustedProjects:)` получает список из `initial` и строит по нему и проектные слои, и `CoreConfig.trustedProjects` (с `withoutProject`), по которому новая сессия читает `prompts` и `agents`; остальное подставляет `CoreConfig.withDeferred` (`permissions`, элементы серверов, группа полей провайдера с прежними `key` и `headerTemplates`), а прежние `HostSettings` и `values` — рантайм; затем снимок проверяется семантически заново. Отложенная ссылка на модель нового провайдера НЕ SHALL давать итог `failed`. Ключи SHALL попадать в `restartRequiredKeys` и `pendingRestartKeys`; лог — `config.reload.restart_required {keys}`. `pendingRestartKeys` SHALL равняться `restartRequiredKeys` последней успешной перезагрузки: это ключи, которые в файлах ещё отличаются от применённого снимка. Ключ, отложенный раньше и не возвращённый в файле, SHALL оставаться в наборе (применённый снимок хранит его прежнее значение, поэтому он снова отличается); ключ, возвращённый в файле к применённому значению, SHALL уходить из набора. Итог `failed` набор не меняет. Удаление и выключение (`enabled: true → false`) серверов, удаление провайдеров, модели, провайдеры без ключа и HTTP-серверы без подстановок (включённые и выключенные) SHALL применяться без перезапуска.
5. **Сброс.** `AgentCoreServices.secrets?.invalidate()` и `modelsFor(next)` SHALL выполняться при каждой успешной загрузке, даже без изменённых ключей.
6. **Замена.** Полный снимок, снимок без проекта, функция модели и каталог SHALL заменяться одной атомарной операцией. Шаг, ход или проверка разрешения читают их один раз и НЕ SHALL видеть смесь двух снимков.
7. **Итог.** `unchanged` и `config.reload.noop` — только если ни один ключ не изменился (пустой diff); иначе — `applied` и `config.reload.applied {keys, restart_required}`, в том числе когда все изменённые ключи отложены.

**Когда действует новое значение** (CFG-16):
- `providers.*` и модели — со следующего шага любой сессии. Сессия, чья текущая модель исчезла из каталога, SHALL продолжать работать на функции модели прежнего снимка до смены модели; рантайм пишет `config.reload.model_orphaned {session_id, model}` один раз на сессию и модель;
- `budget.*`, `compaction.*` — со следующего хода: сессия берёт их из применённого снимка на границе хода, идущий ход доигрывает с прежними;
- `agent.default_model`, `agent.effort`, `tools.project_context.*` и файлы проекта — для новых сессий;
- ключи без потребителя (`tools.disabled`, `exec.*`, `redact.*` и другие узлы `applied: false`) перезагрузкой не применяются (`config.key.not_applied`);
- `mcp.servers` — требование «Серверы конфигурации при перезагрузке»;
- `permissions.*`, `trusted_projects`, новые или изменённые stdio-серверы (в том числе выключенные, R6-1) и правки R0-4 — только после перезапуска (шаг 4).

Идущий вызов инструмента и идущий запрос разрешения SHALL доигрывать со старыми значениями.

Если каталог моделей изменил список моделей, каждая живая сессия SHALL получить событие `ModelOptionsChanged`. Живая сессия — возвращённая вызывающему до замены и не закрытая. Событие SHALL публиковаться в момент замены, вне очереди агента (в том числе во время хода), НЕ SHALL записываться в журнал сессии и НЕ SHALL буферизоваться в истории хода: подписчик, подключившийся к ходу позже, его не получает (design.md, D8, шаг 7b). Сессия, создание или загрузка которой началось до замены, SHALL получить снимок начала целиком.

Ошибка перезагрузки, запущенной сигналом или вызовом, НЕ SHALL теряться и НЕ SHALL уходить в зону хоста: она пишется `config.reload.failed` с `error_class`.

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

#### Scenario: Правка выключенного stdio-сервера
- **WHEN** stdio-сервер `d` с `enabled: false` есть в применённом снимке, перезагрузка меняет у него `command` (сервер остаётся выключенным), затем человек вызывает `/mcp enable d`
- **THEN** `pendingRestartKeys` содержит `mcp.servers[d]`; `setEnabled("d", true)` запускает процесс с прежней `command` применённого снимка, новая `command` не запускается до перезапуска (R6-1)

#### Scenario: Новый выключенный stdio-сервер
- **WHEN** перезагрузка добавляет stdio-сервер `n` с `enabled: false`
- **THEN** `n` не попадает в применённый снимок, `/mcp list` его не показывает, `/mcp enable n` отвечает `Unknown MCP server: n. Run /mcp list.`, `pendingRestartKeys` содержит `mcp.servers[n]`

#### Scenario: Выключение применяется сразу
- **WHEN** включённый stdio-сервер `s` и HTTP-сервер `h` с заголовком `X-Gw: ${secret:gw}` подключены, и перезагрузка ставит обоим `enabled: false`, а у `s` вдобавок меняет `args`
- **THEN** без хода оба закрыты до итога `reloadConfig` и находятся в `disabled`; `mcp.servers[s]` в `pendingRestartKeys`, а в применённом снимке `s` — с прежними `args` и `enabled: false`; `mcp.servers[h]` в `pendingRestartKeys` нет

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

#### Scenario: Ключ вне реестра ждёт перезапуска
- **WHEN** фейковый `ConfigSource` отдаёт `values` с ключом, для которого `SettingsRegistry.lookup` не находит дескриптора, и перезагрузка меняет его значение
- **THEN** ключ попадает в `restartRequiredKeys` и `pendingRestartKeys`, а в `values` применённого снимка остаётся его прежнее значение

#### Scenario: Ключ перезапуска
- **WHEN** перезагрузка меняет `logging.file` и `budget.max_steps`
- **THEN** `budget.max_steps` применён, `logging.file` — прежний, `restartRequiredKeys` и `pendingRestartKeys` содержат `logging.file`

#### Scenario: Смена списка моделей
- **WHEN** перезагрузка добавляет модель `a/m3` в каталог
- **THEN** каждая живая сессия получает одно `ModelOptionsChanged`, следующий шаг использует новую функцию модели

#### Scenario: Отложенные ключи накапливаются по построению
- **WHEN** одна перезагрузка меняет `sessions.fsync`, следующая — `logging.file`, а третья возвращает `logging.file` к значению при старте
- **THEN** после второй `pendingRestartKeys` — `logging.file`, `sessions.fsync`; после третьей — только `sessions.fsync`

#### Scenario: Изменены только отложенные ключи
- **WHEN** перезагрузка меняет только `logging.file`
- **THEN** итог `applied`, `changedKeys` пуст, `restartRequiredKeys` — `logging.file`, лог `config.reload.applied`, а не `config.reload.noop`

#### Scenario: Исключение загрузки
- **WHEN** `ConfigSource.load()` бросает исключение, в тексте которого есть значение
- **THEN** `reloadConfig()` возвращает `failed`, снимок прежний, лог `config.reload.failed` с `error_class` не содержит текста исключения, ошибок в зоне хоста нет

#### Scenario: Проверка без применения
- **WHEN** в файле добавлен проект в `trusted_projects` и изменён `budget.max_steps`, и вызывается `checkConfig()`
- **THEN** результат без `issues`, его предупреждения содержат `config.reload.restart_required` с ключом `trusted_projects`; бюджет и `pendingRestartKeys` рантайма не изменились

#### Scenario: Проверка ловит ошибку повторной проверки снимка
- **WHEN** фейковый `ConfigSource` отдаёт валидную загрузку, на которой `validateSnapshot()` после `withDeferred` находит проблему, и вызывается `checkConfig()`
- **THEN** результат содержит эту проблему, как `reloadConfig()` на той же загрузке дал бы `failed`; состояние рантайма не изменилось; `load` вызван с `rebase: false`

#### Scenario: Проектный слой перекрывает ключ
- **WHEN** доверенный проект корня запуска задаёт `permissions.tools.exec: ask`, а перезагрузка меняет в глобальном конфиге `permissions.tools.exec` на `allow` и добавляет глобальный stdio-сервер `x`, который проект перекрывает своим `x`
- **THEN** полный снимок не изменился, но `withoutProject` изменился: `permissions.tools.exec` и `mcp.servers[x]` отложены, в `pendingRestartKeys`; сессия вне корня запуска по-прежнему спрашивает `exec`, глобальный `x` для неё не запускается (`config_reload_test.dart`)

#### Scenario: Имя сервера с ]
- **WHEN** в конфиге вручную задан stdio-сервер с именем `a]b`, и перезагрузка меняет его `command`
- **THEN** сервер `a]b` остаётся прежним в обоих снимках, `pendingRestartKeys` содержит `mcp.servers[a]b]`; набор отложенного дошёл до `withDeferred` по имени, без разбора строки ключа

#### Scenario: ModelOptionsChanged не проигрывается новому подписчику
- **WHEN** во время хода перезагрузка меняет список моделей, а затем к истории того же хода подключается новый подписчик
- **THEN** первый подписчик получил одно `ModelOptionsChanged`, новый — ни одного

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
- **THEN** подписки нет, `/config` не объявлена, поведение прежнее; `reloadConfig()` и `checkConfig()` бросают `StateError`, `configStatus()` отвечает

### Requirement: Серверы конфигурации при перезагрузке
Применённый снимок с изменённым `mcp.servers` SHALL передаваться каждой живой сессии существующей заменой `McpSessionTools.replaceServers` с полным желаемым списком: серверы нового конфига, затем текущие серверы `session/new` (design.md, D10).
- Сервер клиента с тем же `name` SHALL затенять сервер конфига, как при создании.
- Серверы `session/new` НЕ SHALL переподключаться и закрываться перезагрузкой (CFG-17).
- Неизменённые серверы (`sameConnection`) НЕ SHALL переподключаться. Неизменённый сервер в состоянии `failed` SHALL пробоваться сразу.
- Без хода замена SHALL завершаться до итога `reloadConfig`. Во время хода модели замена SHALL применяться после `TurnEnded`.
- Замены от перезагрузки и от `setMcpServers` SHALL идти через одну очередь сессии со счётчиком поколений: последний желаемый набор побеждает, а результат устаревшей замены НЕ SHALL перекрывать новую.
- Шаблоны `${secret:…}` серверов конфига SHALL раскрываться заново, по правилам требования «MCP-серверы сессии».
- Новые и изменённые stdio-серверы и HTTP-серверы со ссылками на секреты (R0-1, R0-4), в том числе выключенные (R6-1), в желаемый список НЕ SHALL попадать до перезапуска (требование «Живая перезагрузка конфигурации», шаг 4): вместо них идёт элемент применённого снимка, если он был.
- Серверы с `enabled: false` SHALL передаваться коннектору с признаком `enabled: false` (`McpServerConfig.enabled`): коннектор держит их в состоянии `disabled` без подключения; лог загрузки `mcp.server.skipped {server, reason: disabled in config}` сохраняется. Проблемы построения выключенного сервера НЕ SHALL делать конфиг невалидным; элемент без `type` либо без `command`/`url` SHALL выпадать из списка с тем же `mcp.server.skipped`. `ConfigLoadResult.values` SHALL содержать лист `mcp.servers[<name>]` и выключенных серверов списка. `McpServerConfig.sameConnection` НЕ SHALL учитывать `enabled`: сервер остаётся прежним, только если совпали и параметры соединения, и `enabled`.
- `setEnabled(name, true)` (`/mcp enable`) SHALL подключать сервер с параметрами применённого снимка (R6-1).
- **Ручной выбор** `setEnabled` (`/mcp enable|disable`) SHALL сохраняться при перезагрузке, пока элемент этого сервера в применённом снимке не изменился — параметры соединения (`sameConnection`), `enabled` и сроки `connect_timeout`/`call_timeout` прежние (R6-2). Правка сроков у сервера с ручным выбором SHALL сбрасывать выбор и пересоздавать соединение (у stdio — перезапуск процесса); у сервера без ручного выбора правка одних сроков НЕ SHALL переподключать его. Правки других ключей и серверов выбор НЕ SHALL сбрасывать; сервер, выключенный `/mcp disable`, при этом НЕ SHALL будиться вместе с `failed`. Применённая правка самого сервера, в том числе `enabled`, SHALL давать новое состояние из конфига. Отложенная правка (R0-1, R0-4, R6-1) применённый элемент не меняет и выбор НЕ SHALL сбрасывать.

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

#### Scenario: Ручной выбор переживает правку других ключей
- **WHEN** человек выключил HTTP-сервер `a` командой `/mcp disable a` и включил выключенный конфигом сервер `b` командой `/mcp enable b`, а перезагрузка меняет `budget.max_steps` и `url` другого HTTP-сервера `c`
- **THEN** `a` остаётся `disabled` с `lastError` `disabled by /mcp disable` и не подключался, `b` остаётся `connected` без переподключения, переподключён только `c` (R6-2)

#### Scenario: Правка самого сервера сбрасывает ручной выбор
- **WHEN** HTTP-серверы `a` и `e` без подстановок выключены командами `/mcp disable a` и `/mcp disable e`; перезагрузка меняет `url` у `a` и ставит `e` `enabled: false`, а следующая перезагрузка ставит `e` `enabled: true`
- **THEN** после первой перезагрузки `a` подключён по новому `url`, `e` в `disabled` без `lastError` `disabled by /mcp disable`; после второй `e` подключён (R6-2)

#### Scenario: Правка сроков и ручной выбор
- **WHEN** HTTP-сервер `a` выключен `/mcp disable a`, HTTP-сервер `b` не трогали, и перезагрузка меняет `connect_timeout` у обоих
- **THEN** `a` пересоздан по конфигу и подключён с новым сроком (ручной выбор сброшен); соединение `b` не переподключалось (R6-2)

#### Scenario: Отложенная правка не сбрасывает ручной выбор
- **WHEN** выключенный конфигом stdio-сервер `d` включён командой `/mcp enable d`, и перезагрузка ставит ему в файле `enabled: true` и меняет `args`
- **THEN** `d` не переподключался и работает прежним процессом, `mcp.servers[d]` в `pendingRestartKeys` (R6-2, R0-1)

## MODIFIED Requirements

### Requirement: MCP-серверы сессии
`createSession(SessionSpec)` и `loadSession(id, ports, mcpServers: …)` SHALL подключать MCP-серверы сессии до возврата сессии (design.md change `add-agent-mcp-client`, D6).

1. **Список.** Серверы `CoreConfig.mcpServers`, затем `SessionSpec.mcpServers`. Сервер клиента с тем же `name` заменяет сервер конфига (§13.4, шаг 2); сервер конфига пропускается с `mcp.server.skipped` и причиной `replaced by a server of the client with the same name`. Второй сервер с тем же `name` внутри одного источника (`duplicate server name in the same source`) и сервер с пустым `name` (`empty server name`) пропускаются с `mcp.server.skipped`.
2. **Фильтр.** При выключенной capability `mcp` каждый сервер пропускается с `mcp.server.skipped` и причиной выключения. Сервер с транспортом вне набора capability пропускается с причиной, называющей транспорт и профиль.
3. **Подключение.** Ядро SHALL передавать `services.mcp.connect` серверы конфига с шаблонами `${secret:<name>}` в значениях `env`/`headers` и функцию раскрытия `McpConnectRequest.expandSecrets` (`McpSecretExpander`) над `AgentCoreServices.secrets` (capability `agent-secrets`, «Секреты MCP-серверов конфигурации»; design.md change `add-agent-secret-store`, D4; design.md change `add-config-writer-and-reload`, D11). Коннектор SHALL вызывать её перед каждой попыткой подключения сервера с шаблонами, в том числе первой, и использовать раскрытую копию только в этой попытке. Секрет не найден, хранилище недоступно или у ядра нет резолвера → функция SHALL бросать `McpSecretsException(reason)`, транспорт сервера НЕ SHALL открываться, сервер SHALL оставаться в списке сессии в состоянии `failed` с `lastError` — `reason` и повторяться по расписанию задержек (capability `agent-mcp-client`, «Переподключение и состояние серверов сессии»); на первом сбое — `mcp.server.failed {server, transport, reason}`. Причина называет имя секрета и бэкенд (`secret <name> is not set`, `secret <name> cannot be read: <backend> is unavailable`, `no secret store`) и НЕ SHALL содержать значение секрета. Остальные серверы подключаются, сессия создаётся. `AgentRuntime.dispose()` или `AgentSession.close()` во время раскрытия SHALL отбрасывать попытку: транспорт не открывается, `mcp.server.failed` не пишется, сервер — `failed` с `lastError` `connection cancelled` без таймера повтора. Заголовки после раскрытия SHALL идти в порядке файла конфига. Серверы клиента не раскрываются: `${secret:…}` в них — литерал. `services.mcp.connect` подключает серверы параллельно, каждый в своём `connectTimeout`. Сбой сервера SHALL давать `mcp.server.failed` и сессию без его инструментов. Исключение `connect` целиком SHALL давать `mcp.server.failed` с причиной `MCP connector failed: <runtimeType>` и сессию без MCP-инструментов, а не ошибку `createSession` / `loadSession`.
4. **Регистрация.** После всех подключений, в порядке списка, внутри сервера — в порядке `tools/list`, в реестр сессии поверх копии базового реестра.
5. **Коллизия имени** MCP-инструмента со встроенным или с уже зарегистрированным SHALL отключать весь более поздний сервер (транспорт закрыт, инструменты не зарегистрированы, состояние `disabled` с `lastError` `tool name collision: <имя инструмента>`) с `mcp.server.failed`, причина которого называет оба источника. Сессия SHALL создаваться (HOST-5). Независимо от проверки коннектора ядро SHALL отклонять с `mcp.tool.invalid` инструмент коннектора без префикса `mcp__` или с именем встроенного инструмента (защита в глубину).
6. **Изоляция.** Инструменты одной сессии НЕ SHALL быть видны другим сессиям.
7. **Закрытие.** `AgentSession.close()` и `AgentRuntime.dispose()` SHALL закрывать транспорты серверов сессии после остановки хода. Если `createSession` / `loadSession` падает после подключения серверов, подключения SHALL закрываться до проброса ошибки: сессия, не возвращённая вызывающему, не оставляет живых процессов.
8. **Обновление набора.** Ожидающее обновление `McpSessionTools.takeUpdate()` ядро SHALL применять на границе шага через `prepareNextStep` полями `StepUpdate.tools` и `StepUpdate.systemPrompt` (транскрипт цикла не меняется), а между ходами — перед началом хода.
9. **Журнал.** Описания серверов НЕ SHALL записываться в журнал.

`AgentSession.setMcpServers(servers)` SHALL заменять серверы с `origin: session`:
- список проходит те же слияние и фильтр, что при `createSession`; в `McpSessionTools.replaceServers` уходит полный желаемый список (серверы конфига с шаблонами, затем клиента); сервер конфига с ненайденным секретом входит в него и становится `failed` по шагу 3;
- серверы конфига не трогаются; совпавшие по `name`, параметрам (`sameConnection`) и `enabled` остаются; исчезнувшие закрываются, новые подключаются и занимают имена инструментов последними (коллизия отключает новый сервер); отключённый коллизией или не подключившийся (`failed`) сервер пробуется заново, а выключенный `setEnabled(name, false)` остаётся выключенным;
- без хода — набор меняется до завершения возвращённого `Future`; во время хода вызов возвращается сразу, набор применяется после `TurnEnded`, последний вызов за ход побеждает, следующий `prompt` дожидается применения;
- на закрытой сессии — `StateError`;
- сбой коннектора НЕ SHALL пробрасываться: прежний набор остаётся, лог `mcp.server.failed`;
- «последний вызов побеждает» SHALL обеспечиваться счётчиком поколений: результат устаревшей замены, завершившейся позже, НЕ SHALL перекрывать новую;
- `AgentSession.close()` SHALL отменять идущую замену токеном отмены уровня сессии, в том числе ожидание секретов: транспорт не открывается, `mcp.server.failed` не пишется.

#### Scenario: Закрытие во время замены
- **WHEN** `setMcpServers` подключает новый сервер, а сессия закрывается до конца подключения
- **THEN** подключение отменено, транспорт нового сервера закрыт, набор сессии не изменился после `close()`

#### Scenario: Секрет сервера конфига не найден
- **WHEN** `CoreConfig.mcpServers` содержит http-сервер `gh` с `headers.Authorization: "Bearer ${secret:codelab/mcp/gh/authorization}"` и stdio-сервер `docs` без ссылок, секрета нет ни в хранилище, ни в `CODELAB_SECRET_CODELAB_MCP_GH_AUTHORIZATION`
- **THEN** `createSession` возвращает сессию, `docs` подключён, транспорт для `gh` не открывался, `servers` содержит `gh` в состоянии `failed` с `lastError` `secret codelab/mcp/gh/authorization is not set` и `retryIn`, лог `mcp.server.failed {server: gh, transport: http, reason: "secret codelab/mcp/gh/authorization is not set"}`; лог и журнал не содержат значений секретов

#### Scenario: Хранилище недоступно при загрузке сессии
- **WHEN** `loadSession` восстанавливает сессию, а хранилище бросает `SecretStoreUnavailableException(backend: "file", …)` для секрета сервера `gh`
- **THEN** сессия загружена без инструментов `gh`, `gh` в состоянии `failed`, лог `mcp.server.failed` с причиной `secret codelab/mcp/gh/authorization cannot be read: file is unavailable`

#### Scenario: Секрет задан после создания сессии
- **WHEN** сессия создана, когда секрета `codelab/mcp/gh/authorization` сервера `gh` не было, а затем секрет записан в хранилище
- **THEN** очередная попытка по расписанию раскрывает его заново, `gh` подключается без перезагрузки конфига и перезапуска; значение секрета в коннекторе между попытками не хранится

#### Scenario: Закрытие во время раскрытия секретов
- **WHEN** `read` хранилища для сервера конфига не завершается, а рантайм получает `dispose()` (или сессия — `close()` во время `setMcpServers`)
- **THEN** транспорт этого сервера не открывался, записи `mcp.server.failed` для него нет, таймера повтора нет, процессов серверов не осталось

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
