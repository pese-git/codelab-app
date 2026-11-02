## ADDED Requirements

### Requirement: Предконфигурация провайдера из окружения
Слой переменных `CODELAB_*` загрузчика `ConfigLoader` SHALL принимать предконфигурацию провайдера (`agent-core-architecture` §17.5.3; design.md, D3):
- `CODELAB_PROVIDER_TYPE` — `openai-compatible` или `anthropic`;
- `CODELAB_PROVIDER_CONFIG` — JSON-объект, или вместо него `CODELAB_PROVIDER_CONFIG_BASE64` — тот же JSON в base64 (стандартный или URL-safe алфавит, `=` необязательны).

**Поля JSON:**
- `id` — `[a-z0-9_-]+`, по умолчанию `env`;
- `base_url` — обязателен для `openai-compatible`;
- `model` и `context_window` — обязательны;
- необязательные: `max_output_tokens`, `name`, `image`, `reasoning`, ровно одно из `api_key_env` и `api_key_secret` (или ни одного), `auth_header`, `headers`, `connect_timeout`, `idle_timeout`.

Результат — таблица `providers.<id>` с `kind` и моделью `<model>`, а также `agent.default_model = "<id>/<model>"`. Внутри слоя 6 предконфигурация SHALL применяться первой, `CODELAB_MODEL` — после неё. Внутри слоя 7 (флаги) предконфигурация флагов SHALL применяться первой, `--model` — после неё; поэтому `CODELAB_MODEL` проигрывает предконфигурации флагов, а `--model` её побеждает. Таблица сливается с файловыми слоями по ключам, поля окружения побеждают. Правила доверия §15.3 к слою НЕ SHALL применяться. Источник в `ConfigLoadResult.sources` — `env:CODELAB_PROVIDER_CONFIG` (или `env:CODELAB_PROVIDER_CONFIG_BASE64`).

**Ошибки** — `ConfigIssue` без строки и столбца, источник — имя переменной. Текст SHALL называть переменную и поле и НЕ SHALL цитировать значение переменной, фрагмент JSON или текст исключения парсера:
- обе переменные `CONFIG` и `CONFIG_BASE64` сразу;
- только одна из пары `TYPE`/`CONFIG`;
- неизвестный тип провайдера — со списком допустимых;
- не base64;
- неверный JSON — со смещением;
- корень не объект;
- неизвестное поле — с подсказкой ближайшего;
- неверный тип поля — с ожидаемым типом;
- поле `api_key`, `apiKey`, `key`, `token`, `secret` или `password` — проблема `inlineSecret` с `suggestedSecretName` `codelab/<id>` (CFG-9);
- значение секретного заголовка `headers` (нормализованное правило требования «Запись конфига ConfigWriter») без `${secret:…}` и `${VAR}` — проблема `inlineSecret`.

Если хост передал флаги предконфигурации (capability `agent-binary`), переменные `CODELAB_PROVIDER_*` НЕ SHALL читаться, а лог SHALL содержать `config.preconfig.shadowed {by: "flags"}`.

#### Scenario: Провайдер без файла конфига
- **WHEN** `CODELAB_HOME` пуст, окружение содержит `CODELAB_PROVIDER_TYPE=openai-compatible` и `CODELAB_PROVIDER_CONFIG={"id":"gw","base_url":"https://llm.internal/v1","model":"qwen3-coder","context_window":131072,"api_key_env":"GW_KEY"}`
- **THEN** загрузка успешна, каталог содержит `gw/qwen3-coder`, `agent.default_model` равен `gw/qwen3-coder`, `sources` содержит `env:CODELAB_PROVIDER_CONFIG` (`core/provider-preconfig-from-env`, L-25)

#### Scenario: base64 даёт тот же конфиг
- **WHEN** тот же JSON передан в `CODELAB_PROVIDER_CONFIG_BASE64` без `=` в конце
- **THEN** `CoreConfig` совпадает с конфигом из `CODELAB_PROVIDER_CONFIG`

#### Scenario: Окружение сильнее файла, CODELAB_MODEL сильнее предконфигурации
- **WHEN** `config.yaml` задаёт `agent.default_model: openai/gpt-4o` и провайдера `openai`, предконфигурация — провайдера `gw` с моделью `m1`, а `CODELAB_MODEL=openai/gpt-4o`
- **THEN** каталог содержит обе модели, `agent.default_model` — `openai/gpt-4o`; без `CODELAB_MODEL` — `gw/m1`

#### Scenario: Битый JSON не цитируется
- **WHEN** `CODELAB_PROVIDER_CONFIG={"id":"gw","headers":{"Authorization":"Bearer sk-live-123"` (JSON обрезан)
- **THEN** загрузка даёт проблему с источником `env:CODELAB_PROVIDER_CONFIG` и смещением; ни проблема, ни одна запись лога не содержат `sk-live-123`

#### Scenario: Ключ значением
- **WHEN** JSON предконфигурации содержит поле `api_key`
- **THEN** проблема `inlineSecret` называет `codelab secret set codelab/<id>` и не содержит значения поля

#### Scenario: Флаги и модель
- **WHEN** `config.yaml` объявляет модель `m2` провайдера `a`, окружение задаёт `CODELAB_MODEL=openai/gpt-4o`, а флаги — предконфигурацию провайдера `a` с моделью `m1` (таблица `providers.a` сливается с файлом, каталог содержит `a/m1` и `a/m2`); второй запуск добавляет `--model a/m2`
- **THEN** в первом запуске `agent.default_model` — `a/m1`, во втором — `a/m2`

#### Scenario: Литеральный токен в заголовке предконфигурации
- **WHEN** JSON предконфигурации содержит `"headers":{"Authorization":"Bearer sk-live-1"}`
- **THEN** проблема `inlineSecret` для `headers.Authorization`, текст не содержит `sk-live-1`

#### Scenario: Опечатка в поле
- **WHEN** JSON содержит `contex_window` вместо `context_window`
- **THEN** проблема называет `CODELAB_PROVIDER_CONFIG.contex_window` и подсказывает `context_window`

### Requirement: Реестр настроек
Ядро SHALL предоставлять `SettingsRegistry` (`codelab_agent_core/lib/src/config/settings_registry.dart`, чистый Dart) со списком `SettingDescriptor {key, type, defaultValue, scope, fileOnlyReason, section, label, description, secret, restartRequired, enumValues, min, max, layers}` в порядке показа (`agent-core-architecture` §17.5.2, §17.5.8; design.md, D4).

`SettingsRegistry.lookup(key)` SHALL находить дескриптор с учётом `*` и покрытия поддерева ключами типа `map`/`mapList`. Более конкретный дескриптор побеждает `*` и «прочие».

**Тест полноты** `settings_registry_complete_test.dart` SHALL проверять:
1. каждый листовой путь схемы валидатора (имена — `*`) покрыт ровно одним дескриптором;
2. путь каждого дескриптора есть в схеме, его `type` и `enumValues` совпадают со схемой; `min`/`max` каждого `int` совпадают с поведением валидатора (граница принимается, значение за ней отклоняется); `defaultValue` ключа, который ядро применяет, совпадает с разрешённым `CoreConfig` пустой конфигурации, а умолчания остальных ключей перечислены явной константой теста «только по §15.4» (в узлах схемы умолчаний и диапазонов нет, design.md, D4);
3. `scope == fileOnly` тогда и только тогда, когда `fileOnlyReason` не пуст; `label` и `description` не пусты;
4. каждый ключ верхнего уровня схемы покрыт;
5. `restartRequired` истинен ровно для ключей «только после перезапуска» (capability `agent-runtime`, «Живая перезагрузка конфигурации»);
6. `layers` — подмножество слоёв, которые правила доверия §15.3 разрешают ключу;
7. дескриптор со `scope: shared` покрывает только узлы схемы с `applied: true`.

Разделы схемы после MVP (непрозрачные узлы) SHALL иметь по одному дескриптору `map` со `scope: fileOnly`; непрозрачный узел внутри раздела хоста (`logging.llm_snapshot`) SHALL наследовать `restartRequired` и слои своего раздела. Ключ, чей узел схемы не применяется (`applied: false`: `agent.fallback`, `agent.summary_model`, `permissions.timeout`, `tools.disabled` и др.), SHALL иметь `scope: fileOnly` с причиной `not applied in this version`. Типы дескрипторов SHALL совпадать с узлами схемы этой сборки (`tools.untrusted_paths` — `stringList`; `tools.project_context.max_bytes`, `loop.empty_response_retries` — `int`). Ключ схемы без дескриптора SHALL ронять тест с сообщением `config key <path> has no SettingDescriptor: declare it shared or fileOnly with a reason` (CFG-19, E-15).

`SettingsRegistry.parseCliValue(descriptor, raw)` SHALL разбирать строку значения по типу дескриптора (списки и отображения — JSON). Ошибка разбора — исключение ядра `ConfigValueException {key, expected}` с ожидаемым форматом (design.md, D4); подкоманда переводит его в код `64`. Значение в текст ошибки НЕ SHALL попадать.

`restartRequired` SHALL быть истинным и для `permissions.*` и `trusted_projects` (R0-1). Пока раздел `config` непрозрачен (итерация 2), он покрыт одним дескриптором `map`/`fileOnly`.

#### Scenario: Ключ схемы без дескриптора
- **WHEN** тест добавляет в копию схемы лист `budget.max_widgets`
- **THEN** проверка полноты падает с сообщением `config key budget.max_widgets has no SettingDescriptor: declare it shared or fileOnly with a reason` (`core/settings-registry-complete`)

#### Scenario: Расхождение умолчаний
- **WHEN** дескриптор `budget.max_steps` объявляет умолчание, отличное от разрешённого `CoreConfig` пустой конфигурации
- **THEN** проверка полноты падает и называет ключ

#### Scenario: Ключ без потребителя не показывается в UI
- **WHEN** тест подставляет в копию таблицы дескриптор `tools.disabled` со `scope: shared`, а узел схемы `tools.disabled` — `applied: false`
- **THEN** проверка полноты падает и называет ключ; в настоящей таблице `tools.disabled` — `fileOnly` с причиной `not applied in this version`

#### Scenario: Более конкретный дескриптор
- **WHEN** вызывается `lookup("providers.openai.api_key_secret")`
- **THEN** возвращается дескриптор `providers.*.api_key_secret` с `secret: true`, а не дескриптор `providers`

#### Scenario: Разбор значения CLI
- **WHEN** `parseCliValue` получает `compaction.enabled` со значением `yes` и `permissions.deny` со значением `["exec:rm -rf *"]`
- **THEN** первое — `ConfigValueException` с подсказкой `true or false`, второе — список из одной строки

### Requirement: Запись конфига ConfigWriter
Программная запись конфигурации SHALL выполняться только `ConfigWriter` (`codelab_agent_io/lib/src/config/config_writer.dart`) над правками ядра `ConfigEdit` (`SetValue`, `UnsetValue`, `UpsertMcpServer`, `RemoveMcpServer`, `RemoveTable`) и целью `ConfigTarget` (`user`, `project`, `projectLocal`). Алгоритм — `agent-core-architecture` §17.5.5 с уточнениями design.md, D5. `ConfigWriter.apply(base, edits)` SHALL:
- **Реестр.** Отклонять `SetValue` и `UpsertMcpServer` с ключом вне `SettingsRegistry` и ключ, чей дескриптор не разрешает слой цели. `UnsetValue` SHALL принимать и ключ вне реестра, если он есть в файле.
- **Доверие.** Отклонять правку проектного слоя, которую правило доверия §15.3 проигнорировало бы. Текст SHALL подсказывать `--local` или `trusted_projects`.
- **Секреты.** Отклонять `ConfigInlineSecretException` (с `suggestedSecretName`):
  - значение-секрет по правилу CFG-9, п. 1;
  - по итоговому поддереву документа после всех правок на любой глубине, независимо от типа правки (`SetValue`, `UpsertMcpServer`) и от того, записан лист или значение-отображение целиком: каждое изменённое значение в `providers.*.headers`, `mcp.servers[*].headers`, `mcp.servers[*].env`, `exec.env`, чьё имя после нормализации (нижний регистр, без `-` и `_`) содержит `token`, `secret`, `password`, `apikey`, `auth`, `cookie`, `key` или `privatetoken`, — если в значении нет ни `${secret:…}`, ни `${VAR}`.
- **Блокировка и отпечаток.** Брать эксклюзивный `<path>.lock` с содержимым `<pid> <nonce>`. Lock старше 10 с снимается через `rename` в уникальное имя с повторной проверкой возраста и содержимого и `config.write.stale_lock`; свежий lock другого писателя возвращается на место, а запись получает `ConfigConflictException`. Занятый lock или отпечаток sha256 файла, отличный от `base.fingerprint`, дают `ConfigConflictException`.
- **Правка.** Применять правки к байтам файла через `YamlEditor` (`package:yaml_edit`). Комментарии, пустые строки, порядок ключей, flow-стиль и перевод строк (LF/CRLF) вне изменённых узлов SHALL сохраняться побайтово. Новый ключ SHALL добавляться в конец своего отображения, недостающие предки — в блочном стиле с отступом файла. Строку, которая по профилю §15.5 прочиталась бы не строкой (`off`, `yes`, `${VAR}`), SHALL писать в двойных кавычках. Отказ `YamlEditor` SHALL давать `ConfigException` с `cannot edit <key> automatically; edit the file manually`.
- **Проверка.** Проверять итог `ConfigLoader.validateCandidate` по всем слоям с заменой целевого. Незаданная `${VAR}` — предупреждение результата, а не ошибка. Невалидный итог — `ConfigException(issues)`.
- **Замена.** Эксклюзивно создавать пустой `<path>.tmp-<pid>-<rand>` в каталоге цели, выставлять на него права исходного файла (кроме Windows) через `SecretProcessRunner` **до** записи содержимого, затем писать, сбрасывать на диск и атомарно переименовывать поверх цели. Сбой смены прав SHALL давать `ConfigException`, удалять tmp и не выполнять `rename`. Символическую ссылку SHALL раскрывать: правится цель, ссылка остаётся.
- **Итог.** Писать лог `config.write {path, keys}` и возвращать `ConfigWriteResult {path, fingerprint, warnings, restartRequiredKeys}`.

При любой ошибке файл НЕ SHALL меняться, tmp и lock SHALL удаляться (CFG-13). Значения ключей НЕ SHALL попадать в лог и тексты ошибок. TOML писатель НЕ SHALL писать никогда.

#### Scenario: Сохранение формата
- **WHEN** файл содержит комментарий над `agent:`, хвостовой комментарий у `default_model`, flow-список `fallback: [a/b]` и переводы строк CRLF, и применяется `SetValue("agent.default_model", "anthropic/claude-sonnet-4")`
- **THEN** изменилась только строка `default_model`, её хвостовой комментарий на месте, остальные байты файла совпадают с исходными (`config_writer_test.dart`)

#### Scenario: Ключ модели с точкой
- **WHEN** применяется `SetValue` ключа `providers.local.models."qwen2.5-coder-32b".context_window`
- **THEN** в YAML появляется один ключ `qwen2.5-coder-32b`, а загрузка возвращает модель `local/qwen2.5-coder-32b` с этим окном

#### Scenario: Удаление таблицы провайдера
- **WHEN** применяется `RemoveTable("providers.local")`, а под ним есть модели и комментарии
- **THEN** поддерево и комментарии внутри удалены, комментарий над следующим ключом сохранён; `RemoveTable` несуществующего ключа — `ConfigException`

#### Scenario: Сервер MCP по имени
- **WHEN** применяется `UpsertMcpServer` с `name: github` при существующем элементе `github` и `UpsertMcpServer` с `name: docs` без него
- **THEN** элемент `github` изменён на месте, `docs` добавлен в конец списка `mcp.servers`

#### Scenario: Конфликт с ручной правкой
- **WHEN** файл изменён другим процессом между `read` и `apply`
- **THEN** `apply` бросает `ConfigConflictException`, содержимое файла — правка другого процесса

#### Scenario: Невалидный итог не пишется
- **WHEN** `SetValue("budget.max_steps", 0)`
- **THEN** `ConfigException` с проблемой `budget.max_steps`, байты файла не изменены, tmp и lock отсутствуют

#### Scenario: Недоверенный проект
- **WHEN** проект не в `trusted_projects`, и применяется `UpsertMcpServer` к слою `project`
- **THEN** `ConfigException` с подсказкой `--local` или `trusted_projects`, файл не создан; `SetValue("trusted_projects", …)` в слой `project` — отказ по слоям ключа

#### Scenario: Литеральный токен MCP
- **WHEN** `UpsertMcpServer` задаёт заголовок `Authorization: "Bearer ghp_abc"` серверу `github`
- **THEN** `ConfigInlineSecretException` с `suggestedSecretName` `codelab/mcp/github/authorization`, текст не содержит `ghp_abc`, файл не изменён

#### Scenario: Литеральный токен через config set
- **WHEN** применяется `SetValue("mcp.servers", [{"name":"gh","type":"http","url":"https://h","headers":{"X-Api-Key":"k-1"}}])` или `SetValue("providers.p.headers", {"Cookie":"s=1"})`
- **THEN** `ConfigInlineSecretException`, текст не содержит `k-1` и `s=1`, файл не изменён

#### Scenario: Литеральный секрет во вложенном значении
- **WHEN** применяется `SetValue("exec", {"env":{"GITHUB_TOKEN":"ghp_x"}})` или `SetValue` значения-отображения с вложенным листом `token: "t-1"`
- **THEN** `ConfigInlineSecretException`, текст не содержит `ghp_x` и `t-1`, файл не изменён

#### Scenario: Сбой смены прав
- **WHEN** фейковый `SecretProcessRunner` возвращает ненулевой код на `chmod` tmp
- **THEN** `ConfigException` с `cannot set permissions`, исходный файл не изменён, tmp удалён, содержимое в tmp не записывалось

#### Scenario: Сбой между tmp и переименованием
- **WHEN** запись прерывается после записи tmp и до `rename` (тестовый шов)
- **THEN** исходный файл цел, а следующая запись удаляет брошенный tmp (`config_writer_atomic_test.dart`)

#### Scenario: Символическая ссылка и права
- **WHEN** `$CODELAB_HOME/config.yaml` — символическая ссылка на файл с правами `0600`
- **THEN** после записи ссылка осталась ссылкой, изменена цель, права цели — `0600`

### Requirement: Подкоманды записи и чтения конфига
Общая реализация `codelab_agent_io/lib/src/cli/` SHALL предоставлять подкоманды (design.md, D6):
- `ConfigCommands`: `path`, `get`, `set`, `unset` (а также существующий `check`);
- `ProviderCommands`: `add`, `list`, `remove`;
- `McpServerCommands`: `add`, `list`, `remove`.

Результат каждой подкоманды — `{exitCode, stdout, stderr}`. Набор флагов и действия — таблица §17.5.5. Аргументы разбирает каждое приложение. Вывод и коды выхода SHALL быть общими для `codelab-agent` и `codelab`.

**Правила:**
- **Слой.** По умолчанию — `user`; `--project` и `--local` — слои 3 и 4 для `cwd`. `cwd` — `--cwd` подкоманды, иначе каталог процесса; канонизирует его загрузчик.
- **`config get`** SHALL печатать сырое значение слоя-источника и имя слоя. Подстановки `${VAR}` и `${secret:…}` НЕ SHALL раскрываться ни при каком `--layer`, включая `merged`.
- **Маскирование** (R0-2; design.md, D6) — в `config get` и `provider list`:
  - значение любого листа, чьё имя — ключ из `inlineSecretKeys` или секретное по нормализованному правилу требования «Запись конфига ConfigWriter» (на любой глубине дерева, не только в `headers` и `env`), без `${secret:…}` и `${VAR}` SHALL печататься как `<redacted>`; значение со ссылкой — как есть;
  - непрозрачное поддерево схемы (`providers.*.auth`, `providers.*.key_rotation`, разделы после MVP и другие узлы без схемы листьев) SHALL печататься как `<opaque: edit the file>` без содержимого;
  - значение из слоя окружения SHALL заменяться именем источника: `<from env:CODELAB_PROVIDER_CONFIG>`, `<from env:CODELAB_MODEL>`;
  - userinfo SHALL удаляться из URL (`base_url`, `url`);
  - отображения и списки маскируются поэлементно.
- **`config set`** SHALL разбирать значение через `SettingsRegistry.parseCliValue`.
- **`provider list`** SHALL первой строкой печатать `Secrets: <backend>`, затем по провайдеру итогового конфига — id, kind, base_url, модели и источник ключа без значения (`secret <name>: found|not set|unavailable`, `env <VAR>: set|not set`).
- **`mcp list`** SHALL печатать серверы файлов по слоям (name, type, layer, enabled) без подключения к ним.
- **`provider add --api-key-stdin`**:
  1. проверить кандидат конфига без записи;
  2. проверить хранилище `SecretAdmin.checkStore("codelab/<id>")`;
  3. прочитать ключ через `SecretInput`;
  4. сохранить ключ `SecretAdmin.store`;
  5. записать `api_key_secret: codelab/<id>`.

  В конфиг SHALL попадать только имя секрета. Ошибка записи конфига после сохранения ключа SHALL называть сохранённый секрет в stderr. Если секрет `codelab/<id>` уже был, stdout SHALL содержать `warning: replaced the existing secret codelab/<id>`.
- **Конфликт.** При `ConfigConflictException` подкоманда SHALL один раз перечитать файл и повторить правки; второй конфликт — код `1` с текстом `config file changed during the edit; run the command again`.
- **Коды выхода:**
  - `0` — успех;
  - `1` — невалидный итог, отказ доверия, `inlineSecret`, конфликт, хранилище секретов только для чтения или недоступно;
  - `64` — ошибка использования: неизвестный ключ `set`, неверное значение, недостающий обязательный флаг `provider add` (`--kind`, `--model`, `--context-window`), несовместимые флаги, лишние аргументы.
- **Вывод успешной записи** SHALL содержать путь файла, строки `warning:` предупреждений писателя и `note: restart the agent to apply: <keys>` для ключей `restartRequired`.

Значения секретов и раскрытые подстановки НЕ SHALL попадать в stdout, stderr и лог.

#### Scenario: config set и get
- **WHEN** `config set budget.max_steps 40`, затем `config get budget.max_steps`
- **THEN** первый — код `0` и `Updated budget.max_steps in <home>/config.yaml`, второй — `40` и слой `user`

#### Scenario: get не раскрывает переменную
- **WHEN** `providers.gw.headers.X-Token` в файле равен `"${GW_TOKEN}"`, окружение содержит `GW_TOKEN=t-123`, и вызывается `config get providers.gw.headers --layer merged`
- **THEN** stdout содержит `${GW_TOKEN}` и не содержит `t-123`

#### Scenario: get маскирует секреты
- **WHEN** файл содержит `providers.p.api_key: sk-1`, `providers.p.base_url: https://u:pw@h/v1`, `mcp.servers[gh].headers.Authorization: "Bearer lit"` и `mcp.servers[gh].env.GITHUB_TOKEN: "${GH}"`, а окружение — `CODELAB_MODEL=p/m`; вызываются `config get providers.p`, `config get mcp.servers --layer merged`, `config get agent.default_model`
- **THEN** вывод содержит `<redacted>` вместо `sk-1` и `Bearer lit`, `https://h/v1` без `u:pw`, `${GH}` как есть и `<from env:CODELAB_MODEL>`; ни `sk-1`, ни `pw`, ни `lit` в выводе нет (`config_output_test.dart`)

#### Scenario: Непрозрачные поддеревья
- **WHEN** файл содержит `providers.p.auth: {client_secret: s-1}` и `providers.p.key_rotation: {keys: [k-1]}`, и вызывается `config get providers.p`
- **THEN** оба поддерева выведены как `<opaque: edit the file>`, вывод не содержит `s-1` и `k-1`

#### Scenario: unset удаляет запрещённый ключ
- **WHEN** файл содержит `providers.openai.api_key: sk-1` (конфиг невалиден), и вызывается `config unset providers.openai.api_key`
- **THEN** ключ удалён, итог валиден, код `0`; stdout и stderr не содержат `sk-1`

#### Scenario: provider add с ключом из stdin
- **WHEN** `secrets.backend: file`, вызывается `provider add gw --kind openai-compatible --base-url https://x/v1 --model m --context-window 8192 --api-key-stdin --default`, ключ подаётся в stdin
- **THEN** `secrets.yaml` содержит `codelab/gw`, `config.yaml` — `api_key_secret: codelab/gw` и `agent.default_model: gw/m`, а ни один файл конфига и ни один вывод не содержат значения ключа (`cli_config_commands_test.dart`)

#### Scenario: provider add при бэкенде env
- **WHEN** `secrets.backend` не задан (`auto` = `env`), вызывается `provider add … --api-key-stdin`
- **THEN** код `1`, подсказка `secrets.backend: file` или переменной `CODELAB_SECRET_CODELAB_GW`; ключ не запрашивается, `config.yaml` не изменён

#### Scenario: provider remove со ссылкой
- **WHEN** `agent.default_model: gw/m`, вызывается `provider remove gw`
- **THEN** код `1`, проблема `agent.default_model` с подсказкой сменить модель, файл не изменён

#### Scenario: mcp add с литеральным токеном
- **WHEN** вызывается `mcp add github --type http --url https://h --header Authorization="Bearer ghp_x"`
- **THEN** код `1`, stderr подсказывает `${secret:codelab/mcp/github/authorization}` и `codelab secret set codelab/mcp/github/authorization`, не содержит `ghp_x`; файл не изменён

#### Scenario: Неизвестный ключ set
- **WHEN** вызывается `config set budget.max_stepz 10`
- **THEN** код `64`, stderr подсказывает `budget.max_steps`, файл не изменён

### Requirement: Ключи config.watch и config.poll_interval
Схема SHALL принимать и применять `config.watch` (`bool`, по умолчанию `true`) и `config.poll_interval` (`duration`, по умолчанию `2s`, допустимо `1s..60s`) в слоях `user`, `projectLocal` и `--config`/`CODELAB_CONFIG` (design.md, D7). В проектном слое 3 и в `config.local.yaml` недоверенного проекта раздел `config` SHALL отбрасываться с `config.project.untrusted_key`. Оба ключа SHALL быть `restartRequired`. Предупреждения `config.key.not_applied` они больше НЕ SHALL давать.

#### Scenario: Применяемые ключи
- **WHEN** глобальный конфиг задаёт `config.watch: false` и `config.poll_interval: 5s`
- **THEN** загрузка успешна без `config.key.not_applied`, `HostSettings` содержит оба значения

#### Scenario: Недопустимый интервал и проектный слой
- **WHEN** глобальный конфиг задаёт `config.poll_interval: 500ms`, а `<cwd>/.codelab/config.yaml` — `config.watch: false`
- **THEN** первое — проблема `config.poll_interval` с допустимым диапазоном, второе отброшено с `config.project.untrusted_key`

### Requirement: Наблюдение за файлами конфига
`ConfigWatcher` (`codelab_agent_io`) SHALL следить за файлами слоёв, которые загрузчик читает для корня запуска: `$CODELAB_HOME/config.yaml`, файл `--config`/`CODELAB_CONFIG`, `<root>/.codelab/config.yaml` и `config.local.yaml` (в том числе ещё не созданные), а при `secrets.backend: file` — `$CODELAB_HOME/secrets.yaml` (design.md, D7).

**Механизм:**
- события родительского каталога (`FileSystemEntity.watch`);
- если события недоступны или каталога нет — опрос раз в `config.poll_interval` по `(exists, mtime, size)` и sha256;
- после события — debounce 300 мс на часах `Clock`, новые события перезапускают таймер;
- если sha256 всех файлов совпадает с последней загрузкой, сигнала нет.

Поток событий каталога SHALL приходить через шов-фабрику (по умолчанию `Directory.watch`), чтобы unit-тесты подавали события без настоящей файловой системы; настоящий `watch` проверяет один интеграционный тест с пределом времени. `FileConfigSource implements ConfigSource` SHALL выдавать сигнал `changes` после debounce. Хост SHALL создавать его с результатом стартовой загрузки (`initial`), и каждая `load()` SHALL вызывать `ConfigLoader.load` с `pinnedTrustedProjects` из `initial.config.trustedProjects`. Загрузчик SHALL лишь передавать список в `CoreConfig.fromLayers(..., pinnedTrustedProjects:)`: доверие вычисляет ядро, и по закреплённому списку строятся проектные слои и `CoreConfig.trustedProjects`; новое значение `trusted_projects` попадает только в `values` (design.md, D8). `close()` SHALL останавливать наблюдение и таймеры; после `close()` сигналов нет. При `config.watch: false` наблюдатель НЕ SHALL создаваться. Ошибка потока событий SHALL переводить файл на опрос с `config.watch.fallback`, ошибка опроса — давать `config.watch.failed` без остановки опроса.

#### Scenario: Debounce
- **WHEN** файл записывается три раза за 200 мс
- **THEN** ровно один сигнал через 300 мс после последней записи (`config_watcher_test.dart`, `FakeClock`)

#### Scenario: Замена через rename и новый файл
- **WHEN** редактор заменяет `config.yaml` через `rename`, а позже создаётся отсутствовавший при старте `<root>/.codelab/config.local.yaml`
- **THEN** оба изменения дают по сигналу

#### Scenario: Те же байты
- **WHEN** файл перезаписывается теми же байтами
- **THEN** сигнала нет

#### Scenario: Режим опроса
- **WHEN** наблюдатель работает в режиме опроса с `poll_interval: 1s`, и файл меняется
- **THEN** сигнал приходит не позже интервала опроса плюс 300 мс
