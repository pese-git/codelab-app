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
- **Доверие.** Отклонять правку проектного слоя, которую правило доверия §15.3 проигнорировало бы. Текст SHALL подсказывать `--local` или `trusted_projects`. Доверие SHALL проверяться только при записи в проектный слой (`project`, `projectLocal`).
- **Секреты.** Отклонять `ConfigInlineSecretException` (с `suggestedSecretName`):
  - значение-секрет по правилу CFG-9, п. 1;
  - по итоговому поддереву документа после всех правок на любой глубине, независимо от типа правки (`SetValue`, `UpsertMcpServer`) и от того, записан лист или значение-отображение целиком: каждое изменённое значение в `providers.*.headers`, `mcp.servers[*].headers`, `mcp.servers[*].env`, `exec.env`, чьё имя после нормализации (нижний регистр, без `-` и `_`) содержит `token`, `secret`, `password`, `apikey`, `auth`, `cookie`, `key` или `privatetoken`, — если в значении нет ни `${secret:…}`, ни `${VAR}`;
  - в поддеревьях непрозрачных узлов схемы (`providers.*.auth`, `providers.*.key_rotation`, `tools.web`, `llm`, `hooks` и прочие разделы после MVP) — по тому же нормализованному правилу имён для любого листа;
  - лист с именем из `inlineSecretKeys` на любой глубине; имя SHALL сравниваться после той же нормализации (`API_KEY`, `Api-Key` — как `api_key`);
  - нестроковый скаляр (число, `bool`) под секретным именем SHALL считаться литералом;
  - изменённость элемента `mcp.servers` SHALL определяться по его номеру в списке, а не по `name`: при дублях `name` каждый элемент проверяется сам.
- **Блокировка и отпечаток.** Брать эксклюзивный `<path>.lock` с содержимым `<pid> <nonce>`. Lock старше порога устаревания (10 с) снимается через `rename` в уникальное имя с повторной проверкой возраста и содержимого и `config.write.stale_lock`; свежий lock другого писателя возвращается на место, а запись получает `ConfigConflictException`. Занятый lock или отпечаток sha256 файла, отличный от `base.fingerprint`, дают `ConfigConflictException`. Брошенные `<path>.tmp-*` SHALL удаляться только после взятия lock. Таймаут смены прав (`chmod`, 5 s) SHALL быть строго меньше порога устаревания lock (10 s). Непосредственно перед `rename` писатель SHALL перечитывать свой lock (в нём его nonce) и отпечаток цели (совпадает с прочитанным под lock); иначе — `ConfigConflictException`, tmp удаляется, цель и чужой lock не трогаются.
- **Правка.** Применять правки к байтам файла через `YamlEditor` (`package:yaml_edit`). Комментарии, пустые строки, порядок ключей, flow-стиль и перевод строк (LF/CRLF) вне изменённых узлов SHALL сохраняться побайтово. Новый ключ SHALL вставляться по правилу `YamlEditor` (R3-2): в отображение, ключи которого отсортированы по алфавиту, — на своё место по алфавиту, иначе — в конец отображения; новый элемент списка (`mcp.servers`) — в конец списка; недостающие предки — в блочном стиле с отступом файла. Известная граница: при вставке по алфавиту комментарий над следующим ключом оказывается над новым ключом; байты комментария сохраняются. Строку, которая по профилю §15.5 прочиталась бы не строкой (`off`, `yes`, `${VAR}`), SHALL писать в двойных кавычках. Отказ `YamlEditor` SHALL давать `ConfigException` с `cannot edit <key> automatically; edit the file manually`.
- **Проверка.** Проверять итог `ConfigLoader.validateCandidate` по всем слоям с заменой целевого. Незаданная `${VAR}` — предупреждение результата, а не ошибка. Незаданную `${VAR}` писатель SHALL узнавать по структурному признаку проблемы ядра, а не по тексту сообщения. Итог кандидата и исходный текст слоя проверять тем же методом в режиме полной проверки без обрыва ступеней (R3-3); если полную проверку кандидата не удалось довести до конца (вырезан предок вместо точного пути или весь слой, нет прогресса, исчерпан лимит кругов; правило доверия SHALL вычисляться по исходным слоям до вырезания), проверка SHALL давать служебную проблему `config.validation.incomplete`, и запись SHALL отклоняться (fail-closed), даже если такая проблема была и в базе; неполнота одной базы запись НЕ SHALL блокировать: база сравнения SHALL содержать проблемы всех ступеней, включая каскадные, а не только ступени, на которой оборвалась бы обычная загрузка; сравнивать проблемы до и после правки по сигнатуре `kind|key|source`, без значений и без позиции `line:column` (R3-1); сравнение SHALL учитывать число проблем каждой сигнатуры, поэтому проблемы с пустым ключом НЕ SHALL схлопываться в одну: проблема, которой не было до правки, SHALL давать `ConfigException` с новыми проблемами без записи; проблема, которая была и до правки, SHALL возвращаться в `ConfigWriteResult.warnings`, а запись — выполняться. Литеральный секрет, вносимый правкой, ключ вне реестра, слой, не разрешённый дескриптором, и ключ, отброшенный правилом доверия, SHALL отклоняться всегда, независимо от сравнения. Правка SHALL блокироваться, только если в кандидате есть проблема, которой нет в полном наборе базы; поэтому проблема поздней ступени, открывшаяся после исправления ранней ошибки, НЕ SHALL считаться новой. Обычная загрузка (`config check`, `serve`, перезагрузка) по поведению НЕ SHALL меняться: она по-прежнему останавливается на первой провалившейся ступени.
- **Замена.** Эксклюзивно создавать пустой `<path>.tmp-<pid>-<rand>` в каталоге цели, выставлять на него права исходного файла (кроме Windows) через `SecretProcessRunner` **до** записи содержимого, затем писать, сбрасывать на диск и атомарно переименовывать поверх цели. Сбой смены прав SHALL давать `ConfigException`, удалять tmp и не выполнять `rename`. Символическую ссылку SHALL раскрывать: правится цель, ссылка остаётся. Для слоя `user` ссылка MAY вести куда угодно (dotfiles). Для слоёв `project` и `projectLocal` раскрытая цель (и каталог `.codelab`, если он ссылка) SHALL лежать внутри канонического `<cwd>/.codelab`; иначе — `ConfigException` до взятия lock и до создания каталогов. Больше 32 переходов по ссылкам — `ConfigException` `too many symbolic links`. Каталог `$CODELAB_HOME`, созданный писателем, SHALL получать права `0700` (кроме Windows).
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
- **WHEN** конфиг без проблем загрузки, и применяется `SetValue("budget.max_steps", 0)`
- **THEN** `ConfigException` с новой проблемой `budget.max_steps`, байты файла не изменены, tmp и lock отсутствуют

#### Scenario: Первая запись в пустой конфиг
- **WHEN** `$CODELAB_HOME` пуст, и применяется `SetValue("budget.max_steps", 40)` или правки `provider add` без `--default`
- **THEN** файл записан, `ConfigWriteResult.warnings` содержит проблему `agent.default_model` (`required`), исключения нет

#### Scenario: Правка не вносит новую ошибку
- **WHEN** `agent.default_model: gw/m`, провайдер `gw` — единственный, и применяется `RemoveTable("providers.gw")`
- **THEN** `ConfigException` с проблемой `agent.default_model`, файл не изменён; при этом прежняя проблема другого ключа, бывшая в файле до правки, отказа не вызывает и возвращается предупреждением

#### Scenario: Проблемы без ключа не схлопываются
- **WHEN** исходный текст слоя даёт одну проблему без ключа некоторого вида, а правка вносит ещё одну проблему того же вида без ключа в том же источнике
- **THEN** проблем с сигнатурой `kind||source` стало две вместо одной: лишняя считается новой, `ConfigException`, файл не изменён

#### Scenario: Прежняя ошибка ниже вставки — предупреждение
- **WHEN** в файле есть проблема ключа ниже места вставки (например, `budget.max_steps: 0`), и `SetValue` добавляет новый ключ выше неё, сдвигая её строку
- **THEN** сигнатура `kind|key|source` не изменилась: проблема возвращается в `ConfigWriteResult.warnings`, запись выполнена

#### Scenario: Ошибка ранней ступени
- **WHEN** файл содержит неизвестный ключ `bogus_key` и `budget.max_steps: 0`, и применяется `UnsetValue("bogus_key")`
- **THEN** запись выполнена, `bogus_key` удалён, проблема `budget.max_steps` возвращается в `ConfigWriteResult.warnings`: полная проверка исходного текста (R3-3) видит её в базе, хотя обычная загрузка исходного файла остановилась бы на `bogus_key`

#### Scenario: Ранняя ошибка скрывает поздние
- **GIVEN** `$CODELAB_HOME/config.yaml` с провайдером `lm`, в котором литеральный `api_key: sk-fake-1` и `base_url: "https://u:p@ss@host/v1"`, и `agent.default_model`, ссылающимся на модель `lm`; `codelab-agent config check` сообщает одну проблему (литеральный секрет `providers.lm.api_key`)
- **WHEN** выполняется `codelab-agent config unset providers.lm.api_key`
- **THEN** код выхода `0`, stdout — `Removed providers.lm.api_key from <home>/config.yaml`, затем строки `warning:` для `providers.lm.base_url` и для `agent.default_model` (модели нет в каталоге) как прежних проблем базы
- **AND** ключа `api_key` в файле больше нет, остальные строки и комментарии не изменены
- **AND** строка `sk-fake-1` не встречается ни в stdout, ни в stderr, ни в логе

#### Scenario: Новая ошибка поздней ступени при ранней
- **WHEN** файл содержит неизвестный ключ `bogus_key` и корректный `budget.max_steps: 40`, и применяется `SetValue("budget.max_steps", 0)` (`codelab-agent config set budget.max_steps 0`)
- **THEN** `ConfigException` с новой проблемой `budget.max_steps` (CLI — код `1`), байты файла не изменены, tmp и lock отсутствуют: проблемы `budget.max_steps` нет в полном наборе базы, а прежняя проблема `bogus_key` новой не считается

#### Scenario: Порча слоя не отключает правило доверия
- **WHEN** проектный слой недоверенного проекта содержит испорченные элементы `mcp.servers` (имя не строкой, ключ с кавычкой, больше восьми дубликатов имени), и в этот слой применяется `SetValue("permissions.mode", "bypass")`
- **THEN** запись отклоняется: либо проблемой правила доверия `trusted_projects`, либо служебной `config.validation.incomplete`; байты файла не изменены

#### Scenario: Неполная проверка базы не мешает удалить порчу
- **WHEN** полная проверка исходного слоя неполна, а правка удаляет испорченный элемент, и кандидат проверяется полностью
- **THEN** запись проходит

#### Scenario: Порядок нового ключа
- **WHEN** `SetValue` добавляет новый ключ в отображение с ключами `a`, `c` (по алфавиту) и в отображение с ключами `c`, `a`
- **THEN** в первом новый ключ `b` встаёт между `a` и `c`, во втором — в конец; комментарии и остальные строки не изменены
- **AND** если над `c` в первом отображении стоит комментарий `# про c`, он оказывается над новым ключом `b` (граница `YamlEditor`, design.md D5), а его байты не меняются

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

#### Scenario: Литеральный секрет в непрозрачном поддереве
- **WHEN** правка записывает в `providers.p.auth` лист `client_secret: "cs-1"`, или лист `API_KEY: "k-2"` на любой глубине, или `token: 123456` (число)
- **THEN** каждая правка даёт `ConfigInlineSecretException`, текст не содержит значений, файл не изменён

#### Scenario: Дубли имени сервера MCP
- **WHEN** в `mcp.servers` уже есть элемент `name: gh` без заголовков, и правка добавляет второй элемент `name: gh` с заголовком `Authorization: "Bearer ghp_y"`
- **THEN** `ConfigInlineSecretException`: второй элемент сравнивается со своим прежним по номеру, а не с первым по `name`; файл не изменён

#### Scenario: Сбой смены прав
- **WHEN** фейковый `SecretProcessRunner` возвращает ненулевой код на `chmod` tmp
- **THEN** `ConfigException` с `cannot set permissions`, исходный файл не изменён, tmp удалён, содержимое в tmp не записывалось

#### Scenario: Сбой между tmp и переименованием
- **WHEN** запись прерывается после записи tmp и до `rename` (тестовый шов)
- **THEN** исходный файл цел, а следующая запись удаляет брошенный tmp (`config_writer_atomic_test.dart`)

#### Scenario: Символическая ссылка и права
- **WHEN** `$CODELAB_HOME/config.yaml` — символическая ссылка на файл с правами `0600`
- **THEN** после записи ссылка осталась ссылкой, изменена цель, права цели — `0600`

#### Scenario: Ссылка проектного слоя наружу
- **WHEN** `<cwd>/.codelab/config.local.yaml` — ссылка на `$CODELAB_HOME/config.yaml` (или `<cwd>/.codelab` — ссылка на каталог вне `<cwd>`), и применяется правка слоя `projectLocal`
- **THEN** `ConfigException` с путём, цель ссылки не изменена, lock, tmp и новые каталоги не созданы

#### Scenario: Цепочка ссылок и новый CODELAB_HOME
- **WHEN** путь цели проходит больше 32 символических ссылок (в том числе цикл), а в другом случае `$CODELAB_HOME` не существует
- **THEN** в первом случае `ConfigException` `too many symbolic links`, ничего не создано; во втором писатель создаёт `$CODELAB_HOME` с правами `0700` (кроме Windows) и записывает файл

#### Scenario: Lock снят во время записи
- **WHEN** после записи tmp и до `rename` (тестовый шов) lock писателя удалён или заменён lock другого писателя, либо файл цели изменён в обход lock
- **THEN** `ConfigConflictException`, правки писателя в цели нет (байты — исходные или чужой правки), tmp удалён, чужой lock на месте

#### Scenario: Брошенный tmp и занятый lock
- **WHEN** рядом с целью лежит `<path>.tmp-*` старше 10 с, а lock занят другим живым писателем
- **THEN** запись получает `ConfigConflictException`, и брошенный tmp этой записью не удаляется: чистка идёт только под lock

### Requirement: Подкоманды записи и чтения конфига
Общая реализация `codelab_agent_io/lib/src/cli/` SHALL предоставлять подкоманды (design.md, D6):
- `ConfigCommands`: `path`, `get`, `set`, `unset` (а также существующий `check`);
- `ProviderCommands`: `add`, `list`, `remove`;
- `McpServerCommands`: `add`, `list`, `remove`.

Результат каждой подкоманды — `{exitCode, stdout, stderr}`. Набор флагов и действия — таблица §17.5.5. Аргументы разбирает каждое приложение. Вывод и коды выхода SHALL быть общими для `codelab-agent` и `codelab`.

**Правила:**
- **Слой.** Подкоманды записи (`config set`, `config unset`, `provider add`, `provider remove`, `mcp add`, `mcp remove`) SHALL по умолчанию писать в слой `user`; `--project` и `--local` — слои 3 и 4 для `cwd`. `config get` без `--layer` SHALL читать `merged`.
- **`cwd`** — `--cwd` подкоманды (есть у `config path|get|set|unset|check`, `provider list`, `mcp list`), иначе каталог процесса; канонизирует его загрузчик.
- **`config get`** SHALL печатать сырое значение слоя-победителя (скаляр — одной строкой, отображение и список — JSON с отступом), затем строку `layer: <name>`, где `<name>` — `user`, `project`, `local`, `extra` (файл `CODELAB_CONFIG`/`--config`), `env` или `flags`. Победитель — старший слой, где ключ задан; его поддерево берётся целиком. Подстановки `${VAR}` и `${secret:…}` НЕ SHALL раскрываться ни при каком `--layer`, включая `merged`. Отсутствующий ключ — код `1`.
- **Удаление отсутствующей записи** (`config unset`, `provider remove`, `mcp remove`) SHALL завершаться кодом `0` без записи файла и печатать `<key> is not set in <path>`.
- **Наличие ключа** для `config get`, `config unset`, `provider remove` и `mcp remove` SHALL определяться по пути в документе слоя, а не по значению: ключ со значением `null` присутствует, и `config unset` SHALL его удалять.
- **`provider add <id>`** для существующего провайдера SHALL обновлять его (upsert): переданные флаги перезаписывают свои поля, остальные поля и модели сохраняются.
- **Источник ключа** (R4-4): `provider add` с любым из `--api-key-stdin`, `--api-key-secret`, `--api-key-env` SHALL заменять источник ключа целиком — поля другого источника (`api_key_secret`, `api_key_env`) удаляются той же записью. Пары `api_key_env` + `api_key_secret` у провайдера после команды НЕ SHALL быть. Без флага ключа источник не меняется.
- **Недостающие обязательные флаги** `provider add` (`--kind`, `--model`, `--context-window`) SHALL перечисляться все одной строкой stderr.
- **`provider remove`** при ссылке из `agent.*` SHALL завершаться кодом `1`, stderr SHALL содержать `change the model first: config set agent.default_model <provider>/<model>`.
- **`mcp add` и `mcp remove`** SHALL отклонять имя сервера с пробелом, `[`, `]` или `"` кодом `64`.
- **`mcp remove <name>`** SHALL искать сервер только по `name`, никогда по номеру элемента списка.
- **Ошибка разбора аргументов** `config set`, `config unset`, `provider` и `mcp` SHALL печатать фиксированную фразу (`invalid arguments for config set`, `invalid arguments for config unset`, `invalid arguments for provider`, `invalid arguments for mcp`) и справку, не цитируя слова argv.
- **Маскирование** (R0-2; design.md, D6) — в `config get` и `provider list`:
  - значение любого листа без дескриптора реестра и элемента отображения с произвольными ключами (`headers`, `env`), чьё имя — ключ из `inlineSecretKeys` или секретное по нормализованному правилу требования «Запись конфига ConfigWriter» (на любой глубине дерева), без `${secret:…}` и `${VAR}` SHALL печататься как `<redacted>`; значение со ссылкой — как есть; скалярный лист, описанный реестром (`api_key_secret`, `api_key_env`, `auth_header`), SHALL печататься как есть;
  - непрозрачное поддерево схемы (`providers.*.auth`, `providers.*.key_rotation`, разделы после MVP и другие узлы без схемы листьев) SHALL печататься как `<opaque: edit the file>` без содержимого;
  - значение из слоя окружения SHALL заменяться именем источника: `<from env:CODELAB_PROVIDER_CONFIG>`, `<from env:CODELAB_MODEL>`;
  - URL (`base_url`, `url`) SHALL разбираться как URI и печататься без userinfo (R4-5); неразбираемый URL и URL с `@` без авторитета (`user:pass@host`) SHALL печататься как `<redacted>`; значение query-параметра или пары `имя=значение` во фрагменте с секретным именем (то же нормализованное правило имён) без ссылки `${…}` SHALL печататься как `<redacted>`, значение-ссылка — как есть;
  - отображения и списки маскируются поэлементно.
- **`config set`** SHALL разбирать значение через `SettingsRegistry.parseCliValue`.
- **`config path`** без флага слоя SHALL печатать строки `user: <path> (exists|missing)`, `project: …`, `local: …` и при заданной `CODELAB_CONFIG` — `CODELAB_CONFIG: …`; с `--project`/`--local` — только путь.
- **`provider list`** SHALL первой строкой печатать `Secrets: <backend>`, затем по строке на провайдера итогового конфига `<id>  kind: …  base_url: …  models: a, b  key: <source>` (без `base_url` — `(default)`); источник ключа без значения (`secret <name>: found|not set|unavailable`, `env <VAR>: set|not set`).
- **`mcp list`** SHALL печатать серверы файлов по слоям строками `<name>  type: …  layer: …  enabled: true|false` без подключения к ним.
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
  - `1` — новая ошибка загрузки итога (R3-1), отказ доверия, `inlineSecret`, конфликт, хранилище секретов только для чтения или недоступно;
  - `64` — ошибка использования: неизвестный ключ `set`, неверное значение, недостающий обязательный флаг `provider add` (`--kind`, `--model`, `--context-window`), несовместимые флаги, лишние аргументы, недопустимое имя MCP-сервера.
- **Вывод успешной записи** SHALL содержать строку `Updated <key> in <path>` (`Updated providers.<id> in <path>`, `Updated mcp.servers[<name>] in <path>`) или `Removed <key> from <path>`, строки `warning:` предупреждений писателя и `note: restart the agent to apply: <keys>` для ключей `restartRequired`.

Значения секретов и раскрытые подстановки НЕ SHALL попадать в stdout, stderr и лог.

#### Scenario: config set и get
- **WHEN** в пустом `$CODELAB_HOME` вызывается `config set budget.max_steps 40`, затем `config get budget.max_steps`
- **THEN** первый — код `0`, `Updated budget.max_steps in <home>/config.yaml` и строка `warning: agent.default_model: required` (прежняя проблема конфига, R3-1), второй — `40` и слой `user`

#### Scenario: get не раскрывает переменную
- **WHEN** `providers.gw.headers.X-Token` в файле равен `"${GW_TOKEN}"`, окружение содержит `GW_TOKEN=t-123`, и вызывается `config get providers.gw.headers --layer merged`
- **THEN** stdout содержит `${GW_TOKEN}` и не содержит `t-123`

#### Scenario: get маскирует секреты
- **WHEN** файл содержит `providers.p.api_key: sk-1`, `providers.p.base_url: https://u:pw@h/v1`, `mcp.servers[gh].headers.Authorization: "Bearer lit"` и `mcp.servers[gh].env.GITHUB_TOKEN: "${GH}"`, а окружение — `CODELAB_MODEL=p/m`; вызываются `config get providers.p`, `config get mcp.servers --layer merged`, `config get agent.default_model`
- **THEN** вывод содержит `<redacted>` вместо `sk-1` и `Bearer lit`, `https://h/v1` без `u:pw`, `${GH}` как есть и `<from env:CODELAB_MODEL>`; ни `sk-1`, ни `pw`, ни `lit` в выводе нет (`config_output_test.dart`)

#### Scenario: Маскирование URL
- **WHEN** файл содержит `providers.p.base_url: "https://u:p@ss@host/v1?api_key=X&v=2"`, и вызываются `config get providers.p.base_url` и `provider list`
- **THEN** вывод не содержит `p@ss` и `X`, содержит `host/v1` и `v=2`

#### Scenario: Неразбираемый URL
- **WHEN** `providers.p.base_url` содержит строку, которую нельзя разобрать как URI, и вызывается `config get providers.p.base_url`
- **THEN** stdout содержит `<redacted>` вместо значения, код `0`

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
- **THEN** код `1`, проблема `agent.default_model` и строка `change the model first: config set agent.default_model <provider>/<model>` в stderr, файл не изменён

#### Scenario: get без --layer читает итог
- **WHEN** `budget.max_steps: 10` в `config.yaml`, `budget.max_steps: 20` в `.codelab/config.yaml` проекта, и вызывается `config get budget.max_steps --cwd <project>`
- **THEN** код `0`, stdout — `20` и `layer: project`

#### Scenario: get отсутствующего ключа
- **WHEN** ключ `budget.max_steps` не задан ни в одном слое, и вызывается `config get budget.max_steps`
- **THEN** код `1`, stdout пуст

#### Scenario: config unset отсутствующего ключа
- **WHEN** `config.yaml` не содержит `budget.max_steps`, и вызывается `config unset budget.max_steps`
- **THEN** код `0`, stdout — `budget.max_steps is not set in <home>/config.yaml`, файл не изменён

#### Scenario: provider remove отсутствующего провайдера
- **WHEN** `config.yaml` не содержит `providers.gw`, и вызывается `provider remove gw`
- **THEN** код `0`, stdout — `providers.gw is not set in <home>/config.yaml`, файл не изменён

#### Scenario: mcp remove отсутствующего сервера
- **WHEN** `config.yaml` не содержит сервера `github`, и вызывается `mcp remove github`
- **THEN** код `0`, stdout — `mcp.servers[github] is not set in <home>/config.yaml`, файл не изменён

#### Scenario: unset ключа со значением null
- **WHEN** `config.yaml` содержит `budget:` с вложенным `max_steps:` без значения, и вызывается `config unset budget.max_steps`
- **THEN** код `0`, stdout — `Removed budget.max_steps from <home>/config.yaml`, строки `max_steps:` в файле нет

#### Scenario: Флаг ключа заменяет источник ключа
- **WHEN** `secrets.backend: file`, `config.yaml` содержит `providers.gw` с `api_key_env: GW_KEY`, и вызывается `provider add gw --kind openai-compatible --model m --context-window 8192 --api-key-stdin` с ключом в stdin
- **THEN** код `0`, `providers.gw` содержит `api_key_secret: codelab/gw` и не содержит `api_key_env`

#### Scenario: provider add без обязательных флагов
- **WHEN** вызывается `provider add gw` без `--kind`, `--model` и `--context-window`
- **THEN** код `64`, одна строка stderr называет `--kind`, `--model` и `--context-window`; файлы не изменены

#### Scenario: mcp remove не ищет по номеру
- **WHEN** `mcp.servers` содержит один сервер `github`, и вызывается `mcp remove 0`
- **THEN** код `0`, stdout — `mcp.servers[0] is not set in <home>/config.yaml`, сервер `github` на месте, файл не изменён

#### Scenario: Недопустимое имя в mcp remove
- **WHEN** вызывается `mcp remove "my server"`
- **THEN** код `64`, файл не изменён

#### Scenario: provider add обновляет провайдера
- **WHEN** `config.yaml` содержит `providers.gw` с `base_url: https://x/v1` и `api_key_secret: codelab/gw`, хранилище `file` уже содержит секрет `codelab/gw`, и вызывается `provider add gw --kind openai-compatible --model m --context-window 8192 --api-key-stdin` с новым ключом в stdin
- **THEN** код `0`, секрет `codelab/gw` заменён новым значением, `base_url` сохранён; stdout содержит `warning: replaced the existing secret codelab/gw` и `Updated providers.gw in <home>/config.yaml`, ни старого, ни нового значения ключа в выводе нет

#### Scenario: Недопустимое имя MCP-сервера
- **WHEN** вызывается `mcp add "my server" --type http --url https://h`
- **THEN** код `64`, файл не изменён

#### Scenario: Ошибка разбора аргументов не цитирует argv
- **WHEN** вызывается `provider add gw --api-key sk-1`
- **THEN** код `64`, stderr содержит `invalid arguments for provider` и справку, не содержит `sk-1`

#### Scenario: Ошибка разбора аргументов config set не цитирует argv
- **WHEN** вызывается `config set budget.max_steps --sk-1`
- **THEN** код `64`, stderr содержит `invalid arguments for config set` и справку, не содержит `sk-1`

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
- события родительского каталога (`Directory.watch`), одна подписка на каталог;
- если каталога нет, фабрика событий бросила, поток вернул ошибку или завершился (`onDone`) — опрос раз в `config.poll_interval` по `(exists, mtime, size)` и sha256; отсутствующий каталог SHALL распознаваться до подписки (на macOS `watch` по нему молчит), а файл, переведённый на опрос, SHALL оставаться на опросе до `close()`;
- сигнал запускает только событие, у которого путь или цель `rename` имеет точное имя наблюдаемого файла;
- после события — debounce 300 мс на часах `Clock`, новые события перезапускают таймер;
- если sha256 всех файлов совпадает с базой, сигнала нет; отсутствующий файл и нечитаемый файл — два разных состояния, отличных от любого содержимого; файл больше лимита размера загрузчика (`maxConfigBytes`) SHALL сравниваться по `(size, mtime)` без чтения — загрузчик его всё равно отклонит;
- база SHALL обновляться при каждом сигнале и в `rebase()`, который `FileConfigSource.load()` вызывает перед чтением слоёв: собственное чтение НЕ SHALL давать повторного сигнала, правка во время чтения SHALL давать. Загрузка для проверки (`load(rebase: false)`, `/config check`) `rebase()` НЕ SHALL вызывать: иначе правка, ждущая debounce, совпала бы с базой и перезагрузка потерялась бы;
- для файла-ссылки SHALL наблюдаться и лексический путь, и каталог канонической цели ссылки; сигнал — по событию любого из них, содержимое сравнивается по лексическому пути, цель пересчитывается в `rebase()`.

Поток событий каталога SHALL приходить через шов-фабрику `Stream<DirectoryChange> Function(Directory)` с узкой структурой `DirectoryChange {path, destination}` (`FileSystemEvent` запечатан и в тестах не строится), а замер для опроса — через шов `ConfigFileProbe`; по умолчанию — настоящие `Directory.watch` и `stat`. Unit-тесты подают события без настоящей файловой системы; настоящий `watch` проверяет один интеграционный тест с пределом времени. `FileConfigSource implements ConfigSource` SHALL выдавать сигнал `changes` после debounce. Хост SHALL создавать его до сборки ядра, с результатом стартовой загрузки (`initial`), и каждая `load()` SHALL вызывать `ConfigLoader.load` с `pinnedTrustedProjects` из `initial.config.trustedProjects`. Загрузчик SHALL лишь передавать список в `CoreConfig.fromLayers(..., pinnedTrustedProjects:)`: доверие вычисляет ядро, и по закреплённому списку строятся проектные слои и `CoreConfig.trustedProjects`; новое значение `trusted_projects` попадает только в `values` (design.md, D8). `close()` SHALL останавливать наблюдение и таймеры; после `close()` сигналов нет. При `config.watch: false` наблюдатель НЕ SHALL создаваться. События по служебным файлам `ConfigWriter` (`config.yaml.lock`, `*.lock.stale-*`, `*.tmp-*`) в `$CODELAB_HOME` и `.codelab/` НЕ SHALL запускать перезагрузку; распознавать их SHALL предикат писателя (`config_write_lock.dart`), а не дублированные шаблоны. Ошибка потока событий SHALL переводить файлы каталога на опрос с `config.watch.fallback`; ошибка замера при опросе или чтения файла при сравнении — давать `config.watch.failed` без остановки опроса.

#### Scenario: Debounce
- **WHEN** файл записывается три раза за 200 мс
- **THEN** ровно один сигнал через 300 мс после последней записи (`config_watcher_test.dart`, `FakeClock`)

#### Scenario: Замена через rename и новый файл
- **WHEN** редактор заменяет `config.yaml` через `rename`, а позже создаётся отсутствовавший при старте `<root>/.codelab/config.local.yaml`
- **THEN** оба изменения дают по сигналу

#### Scenario: Запись ConfigWriter даёт один сигнал
- **WHEN** `ConfigWriter` записывает `$CODELAB_HOME/config.yaml` (создание и удаление `config.yaml.lock`, `config.yaml.tmp-*`) и отдельно в `.codelab/` появляется и исчезает `config.local.yaml.lock.stale-*`
- **THEN** запись даёт ровно один сигнал — по итоговому `rename`; события служебных файлов сами по себе сигнала не дают (`config_watcher_test.dart`, `FakeClock`)

#### Scenario: Те же байты
- **WHEN** файл перезаписывается теми же байтами
- **THEN** сигнала нет

#### Scenario: Режим опроса
- **WHEN** наблюдатель работает в режиме опроса с `poll_interval: 1s`, и файл меняется
- **THEN** сигнал приходит не позже интервала опроса плюс 300 мс

#### Scenario: Отсутствующий каталог уходит на опрос
- **WHEN** при старте нет каталога `<root>/.codelab/`, а позже он создаётся вместе с `config.yaml`
- **THEN** при старте пишется `config.watch.fallback` с путём файла, а создание файла даёт сигнал опросом, не позже `poll_interval` плюс 300 мс (`config_watcher_test.dart`, `FakeClock`)

#### Scenario: Собственное чтение не даёт сигнала
- **WHEN** `FileConfigSource.load()` читает слои после правки, уже давшей сигнал, а затем приходит запоздалое событие по тому же файлу без новых байтов
- **THEN** второго сигнала нет; правка, сделанная после `rebase()`, даёт сигнал (`file_config_source_test.dart`)

#### Scenario: /config check во время debounce не теряет перезагрузку
- **WHEN** наблюдаемый файл изменён, наблюдатель ждёт debounce, и в это время вызывается `checkConfig()` (`load(rebase: false)`)
- **THEN** проверка видит новое содержимое, база наблюдателя не сдвинута; по истечении debounce приходит сигнал, и перезагрузка применяет правку (`file_config_source_test.dart`, `FakeClock`)

#### Scenario: Поток каталога завершился
- **WHEN** поток событий каталога завершается без ошибки (`onDone`), а затем наблюдаемый файл меняется
- **THEN** файлы каталога переведены на опрос с `config.watch.fallback`, правка даёт сигнал не позже `poll_interval` плюс 300 мс

#### Scenario: Файл больше лимита загрузчика
- **WHEN** наблюдаемый файл больше `maxConfigBytes` и меняется его размер или `mtime`
- **THEN** наблюдатель сравнивает отпечаток `(size, mtime)` без чтения содержимого и даёт сигнал; загрузчик сообщает о превышении лимита

#### Scenario: Посторонний файл каталога
- **WHEN** в `$CODELAB_HOME` меняется файл с другим именем (`notes.txt`, `config.yaml.bak`)
- **THEN** сигнала нет

#### Scenario: Нечитаемый файл
- **WHEN** наблюдаемый файл становится нечитаемым, и по нему приходит событие каталога
- **THEN** пишется `config.watch.failed` с путём, а состояние «нечитаемый» отличается от прежнего содержимого — сигнал есть, причину называет загрузчик при `load()`

#### Scenario: Правка цели symlink даёт сигнал
- **WHEN** `$CODELAB_HOME/config.yaml` — ссылка на `~/dotfiles/codelab/config.yaml`, и меняется файл цели в `~/dotfiles/codelab/`
- **THEN** наблюдатель получает событие каталога цели и даёт ровно один сигнал после debounce; после `load()` (`rebase()`) перенаправленная ссылка наблюдается по новой цели
