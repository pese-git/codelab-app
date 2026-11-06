## ADDED Requirements

### Requirement: Модель по умолчанию без agent.default_model
`agent.default_model` SHALL быть необязательным ключом (design.md change `optional-default-model`, D1–D4). `CoreConfig.fromLayers` SHALL всегда давать в валидном `CoreConfig` модель уровня конфига `defaultModel` (`ModelRef`) и её источник `defaultModelSource` (`config` или `firstProvider`):
1. **Явная модель.** Если `agent.default_model` задан в каком-либо слое — файлы, `CODELAB_CONFIG`/`--config`, `CODELAB_MODEL`, предконфигурация `CODELAB_PROVIDER_CONFIG`/`CODELAB_PROVIDER_*`, флаги `serve`, — `defaultModel` SHALL быть этой моделью с источником `config`. Невалидное значение SHALL быть проблемой ключа, как раньше; отката на шаг 2 НЕ SHALL быть.
2. **Первый доступный провайдер.** Иначе `defaultModel` SHALL быть первой моделью (порядок `providers.<id>.models`) первого доступного провайдера в порядке `CoreConfig.providers`, источник — `firstProvider`. Провайдер SHALL считаться доступным, если у него есть хотя бы одна модель, для него нет записи `providerProblems` (переменная `api_key_env` не задана или пуста), и его ключ не `UnusableKeyRef`. Провайдер без ключа (локальный сервер) и провайдер со ссылкой `api_key_secret` SHALL считаться доступными без обращения к хранилищу секретов: загрузка НЕ SHALL читать хранилище для выбора модели.
3. **Нет доступных.** Если провайдеры с моделями есть, но ни один не доступен, `defaultModel` SHALL быть первой моделью первого провайдера с моделями, источник — `firstProvider`; загрузка SHALL быть успешной, а предупреждения `config.provider.key_missing` — прежними.
4. **Нет моделей.** Если ни у одного провайдера нет модели (в том числе провайдеров нет вовсе), загрузка SHALL давать проблему с ключом `agent.default_model`, видом `value`, событием `config.model.none` и текстом `no model is configured; add a provider with at least one model`. Ключ и вид этой проблемы SHALL оставаться `agent.default_model` и `value`, а листа `agent.default_model` в слоях при ней нет: признак «нужна настройка провайдера» клиентов (`codelab_setup`) определяется по ключу и виду или по событию `config.model.none` и НЕ SHALL разбирать текст. Конфиг, где провайдеры с моделями есть, но ни один не доступен (шаг 3), проблем не даёт, и признак настройки провайдера для него ложен.

Снимок без проектных слоёв (D9 change `add-agent-configuration`), если сам не задаёт ключ, SHALL выбирать модель так: явную модель полного снимка (источник `config`) — копировать как есть, с источником `config`; иначе — вычислять неявную модель по своим провайдерам правилом шагов 2–3 с источником `firstProvider` (провайдер проектного слоя вне корня недоступен); и только если у снимка без проекта нет ни одной модели — брать модель полного снимка с её источником. При перезагрузке конфига модель с источником `firstProvider` SHALL вычисляться заново по провайдерам итогового снимка после подстановки отложенных частей (`CoreConfig.withDeferred`): отложенный до перезапуска новый провайдер её не даёт. Смена неявной модели SHALL действовать для новых сессий и НЕ SHALL давать ключ в `pendingRestartKeys`.

#### Scenario: Первая модель первого провайдера
- **WHEN** конфиг объявляет провайдеров `a` (модели `x1`, `x2`) и `b` (модель `y`) в этом порядке без `agent.default_model`
- **THEN** `defaultModel` — `a/x1`, источник `firstProvider`, проблем нет

#### Scenario: Первый провайдер без ключа
- **WHEN** провайдер `a` задаёт `api_key_env: A_KEY`, переменная не задана, а следующий провайдер `b` задаёт `api_key_env: B_KEY`, и `B_KEY` задана; `agent.default_model` нет
- **THEN** `defaultModel` — первая модель `b`, источник `firstProvider`; предупреждение `config.provider.key_missing` для `a` прежнее

#### Scenario: Ссылка на секрет не читается при выборе
- **WHEN** единственный провайдер `gw` задаёт `api_key_secret: codelab/gw`, секрета в хранилище нет, `agent.default_model` нет
- **THEN** `defaultModel` — первая модель `gw`; при загрузке фейковое хранилище секретов не получило ни одного вызова

#### Scenario: Нет доступных провайдеров
- **WHEN** оба провайдера `a` и `b` задают `api_key_env` с незаданными переменными, `agent.default_model` нет
- **THEN** загрузка успешна, `defaultModel` — первая модель `a`, источник `firstProvider`, два предупреждения `config.provider.key_missing`

#### Scenario: Нет ни одного провайдера
- **WHEN** `$CODELAB_HOME` пуст, окружение не задаёт `CODELAB_MODEL` и `CODELAB_PROVIDER_*`
- **THEN** одна проблема: `key` — `agent.default_model`, `kind` — `value`, `event` — `config.model.none`, текст `no model is configured; add a provider with at least one model`; `CoreConfig` не построен; тот же итог — у провайдера без моделей (`providers.gw: {kind: openai-compatible, base_url: https://x/v1}`)

#### Scenario: Явная модель на несуществующую модель
- **WHEN** конфиг объявляет провайдера `gw` с моделью `m` и задаёт `agent.default_model: gw/zzz`
- **THEN** проблема `agent.default_model` (`gw/zzz is not in the model catalog; …`), `CoreConfig` не построен, отката на `gw/m` нет

#### Scenario: CODELAB_MODEL — явная модель
- **WHEN** файлы объявляют провайдеров `a` (модель `x`) и `b` (модель `y`) без ключа, окружение — `CODELAB_MODEL=b/y`
- **THEN** `defaultModel` — `b/y`, источник `config`

#### Scenario: Снимок без проекта при явной модели
- **WHEN** пользовательский слой объявляет провайдера `u` (модель `x`), доверенный проектный слой — провайдера `p` (модель `y`) и `agent.default_model: p/y`
- **THEN** у снимка без проекта `defaultModel` — `p/y`, источник `config`, как у полного снимка

#### Scenario: Провайдеры пользователя и проекта
- **WHEN** пользовательский слой объявляет провайдера `u` (модель `x`) с доступным ключом, доверенный проектный слой — провайдера `p` (модель `y`); `agent.default_model` нет ни в одном слое
- **THEN** ключи пользователя при слиянии идут раньше ключей проекта, поэтому у обоих снимков `defaultModel` — `u/x`, источник `firstProvider`

#### Scenario: Доступен только провайдер проекта
- **WHEN** пользовательский слой объявляет провайдера `u` (модель `x`) с `api_key_env: U_KEY`, переменная `U_KEY` не задана; доверенный проектный слой — провайдера `p` (модель `y`) с доступным ключом; `agent.default_model` нет
- **THEN** у полного снимка `defaultModel` — `p/y` (первый доступный, D2); у снимка без проекта (сессия вне корня) — `u/x` (своих доступных нет, первый провайдер снимка, D3); оба с источником `firstProvider`

#### Scenario: Снимок без проекта без своих моделей
- **WHEN** пользовательский слой не объявляет провайдеров, доверенный проектный слой объявляет провайдера `p` (модель `y`), `agent.default_model` нет
- **THEN** у полного снимка `defaultModel` — `p/y`, источник `firstProvider`; у снимка без проекта — тоже `p/y` с источником `firstProvider` (модель полного снимка), проблемы `config.model.none` нет

#### Scenario: Отложенный новый провайдер не становится моделью
- **WHEN** применённый снимок — провайдер `b` (модель `y`) без ключа модели, неявная модель `b/y`; перезагрузка добавляет перед ним провайдера `a` с `api_key_secret` (отложен до перезапуска)
- **THEN** итог `applied`, неявная модель снимка — `b/y`, `pendingRestartKeys` содержит `providers.a` и не содержит `agent.default_model`; проблемы `validateSnapshot` нет

## MODIFIED Requirements

### Requirement: Схема и строгая проверка
Ядро SHALL проверять каждый слой функцией `CoreConfig.fromLayers(layers, environment: …, projectRoot: …)` без файлов и без разборщиков (`codelab_agent_core/lib/src/config/`). Результат `ConfigLoadResult` SHALL содержать либо `CoreConfig`, либо непустой список `ConfigIssue {kind, key, source, line?, column?, message}`, а также предупреждения (тот же тип с заполненными `event`, `fields`, `level`) и список источников. `ConfigLoadResult.orThrow()` SHALL возвращать `CoreConfig` или бросать `ConfigException` (`ConfigInlineSecretException`, если есть проблема `inlineSecret`). Проектные слои без `projectRoot` — ошибка программиста хоста (`ArgumentError`), а не `ConfigIssue`.

- Неизвестный ключ SHALL давать проблему `unknownKey` с путём ключа и подсказкой ближайшего известного ключа (расстояние Левенштейна ≤ 2); ключ с точкой внутри — подсказку вложенной формы.
- Неверный тип SHALL давать проблему `type` с ожидаемым типом. Для `bool` строки `yes`, `no`, `on`, `off`, `y`, `n` — ошибка с подсказкой `use true or false`. `null` у ключа схемы — ошибка. `int` НЕ SHALL принимать `2.0`, `float` SHALL принимать `2`. `30s` и `"30s"` SHALL быть равны.
- `permissions.mode: autopilot` в любом файловом слое SHALL быть проблемой (CFG-4).
- Семантические проверки §15.5, шаг 8:
  - если `agent.default_model` задан в каком-либо слое, его провайдер объявлен, а модель есть в `providers.<p>.models`; невалидное значение SHALL быть проблемой этого ключа без отката на другую модель. Незаданный `agent.default_model` проблемой НЕ SHALL быть, если в конфиге есть провайдер с моделью (требование «Модель по умолчанию без agent.default_model»);
  - `openai-compatible` имеет `base_url`;
  - имена `mcp.servers` уникальны, `stdio` имеет `command`, `http` имеет `url`;
  - `reserve_tokens > 0`, `keep_recent_tokens > 0`, `max_steps ≥ 1`;
  - `idle_timeout_reasoning ≥ idle_timeout`.

  Нарушение SHALL давать проблему с путём ключа.

Строка и столбец SHALL браться из позиций слоя. У слоя без позиций (окружение, флаги, хранилище приложения) сообщение SHALL называть источник и путь ключа без строки.

Ключ схемы MVP без потребителя в этой сборке и ключ раздела после MVP SHALL приниматься с одним предупреждением `config.key.not_applied {key, source}` на каждый явно заданный лист; ключ вне схемы и вне списка разделов после MVP — проблема `unknownKey`. В `profile.<name>` допустимы только встроенные профили и известные capability (иначе `unknownKey`); capability после MVP даёт `config.key.not_applied`; расширение профиля — проблема с ключом `profile.<name>.<capability>`.

#### Scenario: Опечатка с подсказкой
- **WHEN** `config.yaml` содержит в строке 12, столбце 3 ключ `compaction.reserve_token`
- **THEN** проблема — `config.yaml:12:3: compaction.reserve_token: unknown key (did you mean reserve_tokens?)`, `CoreConfig` не построен

#### Scenario: Ключ с точкой
- **WHEN** внутри `tools:` записан ключ `output.max_lines: 2000`
- **THEN** проблема `unknownKey` предлагает вложенную форму `output:` → `max_lines:`

#### Scenario: Логическое значение yes
- **WHEN** `compaction.enabled: yes`, а в `profile.agent-serve.shell_exec` записано `off`
- **THEN** первое — проблема типа с подсказкой `use true or false`, второе — строка `off`

#### Scenario: Слой без позиций
- **WHEN** `fromLayers` получает слой `app-storage` без позиций с `budget.max_steps: "x"`
- **THEN** сообщение называет источник `app-storage` и ключ `budget.max_steps`, строки и столбца нет (`config_validator_positions_test.dart`)

#### Scenario: Ключ без потребителя
- **WHEN** глобальный конфиг задаёт `loop.empty_response_retries: 3` и `skills.max_skills: 100`
- **THEN** загрузка успешна, каждое значение даёт одно предупреждение `config.key.not_applied` с ключом и источником

#### Scenario: Предупреждения по листьям
- **WHEN** глобальный конфиг задаёт `loop: {misuse: {warn_after: 3, block_after: 6}}`
- **THEN** два предупреждения `config.key.not_applied` с ключами `loop.misuse.warn_after` и `loop.misuse.block_after`

#### Scenario: Сужение профиля
- **WHEN** глобальный конфиг задаёт `profile.my-profile.mcp: off`, `profile.agent-serve.shell: off`, `profile.agent-serve.network: off` и `profile.agent-serve.mcp: [stdio, http, sse]`
- **THEN** первые два — `unknownKey`, третье — `config.key.not_applied`, четвёртое — проблема с ключом `profile.agent-serve.mcp`

#### Scenario: Модель вне каталога провайдера
- **WHEN** `agent.default_model: openai/gpt-x`, а у провайдера `openai` в `models` только `gpt-4o`
- **THEN** проблема `agent.default_model`, `CoreConfig` не построен

#### Scenario: autopilot в файле
- **WHEN** `config.yaml` задаёт `permissions.mode: autopilot`
- **THEN** загрузка даёт проблему `permissions.mode`, а флаг `--permission-mode autopilot` того же запуска допустим

#### Scenario: Провайдер без agent.default_model
- **WHEN** единственный слой объявляет провайдера `gw` с моделью `m` и не задаёт `agent.default_model`
- **THEN** проблем нет, `CoreConfig.defaultModel` — `gw/m`, `CoreConfig.defaultModelSource` — `firstProvider`

### Requirement: Подкоманда config check
`codelab-agent config check [--cwd <dir>]` и `codelab config check [--cwd <dir>]` SHALL выполнять полную загрузку для `cwd` (по умолчанию — текущий каталог процесса) без запуска агента. Загрузка SHALL учитывать окружение процесса целиком, включая `CODELAB_CONFIG` и прочие `CODELAB_*`; флагов `serve` (`--config`, `--provider`, `--model` и других) у подкоманды нет: проверяется то, что увидит `serve` без флагов. Вывод в stdout по строкам:
- первая строка — `Sources: <источники через ", ">`, где источники — `ConfigLoadResult.sources` как есть, по порядку слоёв: `defaults`, затем канонические абсолютные пути прочитанных файлов, затем `env`, если есть переменные-ключи (например `Sources: defaults, /home/u/.codelab/config.yaml, /work/demo/.codelab/config.yaml`);
- каждая проблема — строка `ConfigIssue.toString()`: `<location>: <key>: <message>`, без `<key>: `, если ключ пустой; `<location>` — `<source>:<line>:<column>` или `<source>`, если позиции нет; подсказка (`did you mean max_steps?`) — часть `<message>`;
- каждое предупреждение — строка `warning: <location>: [<key>: ]<message>` в той же форме, включая `config.legacy_found` и `config.env.unknown`. Текст `config.legacy_found` НЕ SHALL повторять путь, уже стоящий в `<location>`. Неизвестные `CODELAB_*` SHALL распознаваться в `ConfigLoader` (`codelab_agent_io`), а не в каждом бинаре: правило одно для `serve` и обеих подкоманд. `CODELAB_TEST_SECRET_STORE` SHALL считаться известной только в сборке с `--dart-define=CODELAB_ALLOW_TEST_SECRETS=true`; в обычной сборке она SHALL давать `config.env.unknown`, как любая неизвестная `CODELAB_*`, и НЕ SHALL читаться (agent-core §15.6);
- при валидном конфиге перед последней строкой — `Default model: <provider>/<model> (<source>)`: модель, которую получит новая сессия без явной модели (требование `agent-runtime` «Модель новой сессии»), и её источник — `config`, `last-used` или `first-provider`. Для источника `last-used` подкоманда SHALL читать файл последней модели `$CODELAB_HOME/state/last-model.json` (требование `agent-runtime` «Последняя выбранная модель») только для чтения; нечитаемый файл SHALL давать строку `warning: <path>: last model state ignored: <reason>` и выбор следующего шага, а не проблему. При невалидном конфиге строки `Default model:` нет;
- последняя строка — `Config: valid` или `Config: invalid (issues: <n>)`, где `<n>` — число проблем; предупреждения проблемами не считаются.

Код выхода SHALL быть `0` при валидном конфиге (с предупреждениями тоже), `1` при проблемах, `64` при ошибке использования. Ошибка использования — несуществующий каталог `--cwd` и `ConfigUsageException` загрузчика (`CODELAB_CONFIG` с расширением `.toml` или относительный): текст ошибки идёт в stderr, stdout SHALL быть пустым. Подкоманда НЕ SHALL писать файлы и печатать значения секретов. Обе подкоманды SHALL использовать одну реализацию `ConfigCommands` из `codelab_agent_io`.

#### Scenario: Битый конфиг
- **WHEN** `config.yaml` задаёт провайдера и `agent.default_model`, содержит одну опечатку ключа, а `config check` запускается в этом `cwd`
- **THEN** первая строка stdout начинается с `Sources: defaults, ` и называет канонический абсолютный путь `config.yaml`, строка проблемы содержит файл, строку, столбец, путь ключа и подсказку `did you mean …?`, последняя строка `Config: invalid (issues: 1)`, код `1`

#### Scenario: Предупреждения не делают конфиг невалидным
- **WHEN** `config.yaml` валиден, окружение содержит неизвестную переменную `CODELAB_UNKNOWN_X=1`, а `config check` запускается в этом `cwd`
- **THEN** stdout содержит строку `warning: …` предупреждения `config.env.unknown`, называющую `CODELAB_UNKNOWN_X`, но не её значение; последняя строка `Config: valid`, код `0`

#### Scenario: Подсказка о codelab.toml
- **WHEN** `CODELAB_HOME` пуст, в `cwd` есть только `codelab.toml`, а `config check` запускается в этом `cwd`
- **THEN** stdout содержит строку `warning: <cwd>/codelab.toml: codelab.toml is not used by the Dart agent…`, в тексте после локации путь `<cwd>/codelab.toml` не повторяется; единственная проблема — `agent.default_model: no model is configured; add a provider with at least one model`, последняя строка `Config: invalid (issues: 1)`, код `1`

#### Scenario: CODELAB_CONFIG учитывается
- **WHEN** `CODELAB_CONFIG=<tmp>/extra.yaml` (абсолютный путь), файл содержит неизвестный ключ, а `config check` запускается без флагов
- **THEN** строка `Sources:` содержит `<tmp>/extra.yaml`, stdout содержит проблему этого файла, код `1`

#### Scenario: Несуществующий каталог
- **WHEN** запускается `config check --cwd <tmp>/missing`, а каталога нет
- **THEN** код `64`, stderr называет каталог, stdout пуст

#### Scenario: Ошибка использования из окружения
- **WHEN** `CODELAB_CONFIG` равна `<tmp>/c.toml` или относительному пути `.codelab/extra.yaml`
- **THEN** код `64`, stderr содержит текст `ConfigUsageException` с именем `CODELAB_CONFIG`, stdout пуст, файл не читается

#### Scenario: Одинаковый вывод у двух бинарей
- **WHEN** `codelab-agent config check` и `codelab config check` запускаются с одним окружением и `cwd`
- **THEN** их stdout и коды выхода совпадают

#### Scenario: Тестовое хранилище в обычной сборке
- **WHEN** агент собран без `--dart-define=CODELAB_ALLOW_TEST_SECRETS=true`, `config.yaml` валиден, окружение содержит `CODELAB_TEST_SECRET_STORE=<tmp>/test-secrets`, а `config check` запускается в этом `cwd`
- **THEN** stdout содержит строку `warning: …` предупреждения `config.env.unknown`, называющую `CODELAB_TEST_SECRET_STORE`, но не её значение; каталог `<tmp>/test-secrets` не читается и не создаётся; последняя строка `Config: valid`, код `0`

#### Scenario: Модель первого провайдера в config check
- **WHEN** `config.yaml` объявляет только провайдера `gw` с моделью `m` без `agent.default_model`, файла `$CODELAB_HOME/state/last-model.json` нет, и запускается `config check`
- **THEN** код `0`, stdout содержит `Default model: gw/m (first-provider)`, последняя строка `Config: valid`, строки с `required` нет

#### Scenario: Источник модели в config check
- **WHEN** в первом варианте `config.yaml` задаёт `agent.default_model: gw/m`; во втором ключа нет, а `$CODELAB_HOME/state/last-model.json` называет модель `gw/m2` каталога; в третьем файл состояния содержит не JSON
- **THEN** stdout содержит соответственно `Default model: gw/m (config)`, `Default model: gw/m2 (last-used)` и строку `warning: …last-model.json: last model state ignored: …` вместе с `Default model: gw/m (first-provider)`; во всех вариантах код `0`, файл состояния не изменён

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
- **Правка.** Применять правки к байтам файла через `YamlEditor` (`package:yaml_edit`). Комментарии, пустые строки, порядок ключей, flow-стиль и перевод строк (LF/CRLF) вне изменённых узлов SHALL сохраняться побайтово. Новый ключ SHALL вставляться по правилу `YamlEditor` (R3-2): в отображение, ключи которого отсортированы по алфавиту, — на своё место по алфавиту, иначе — в конец отображения; новый элемент списка (`mcp.servers`) — в конец списка; недостающие предки — в блочном стиле с отступом файла. Известная граница: при вставке по алфавиту комментарий над следующим ключом оказывается над новым ключом; байты комментария сохраняются. Строку, которая содержит `${`, SHALL писать в одинарных кавычках без экранирования `/` (`'Bearer ${secret:codelab/mcp/gh/x}'`): в двойных `yaml_edit` экранирует `/` как `\/`, и файл становится нечитаемым (design.md change `add-config-literal-secrets-and-migrate`, D5). Прочую строку, которая по профилю §15.5 прочиталась бы не строкой (`off`, `yes`), SHALL писать в двойных кавычках. Строку с управляющим символом (в том числе `\n`) SHALL писать в двойных кавычках: одинарные его не выражают. Отказ `YamlEditor` SHALL давать `ConfigException` с `cannot edit <key> automatically; edit the file manually`.
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
- **WHEN** `$CODELAB_HOME` пуст, и применяется `SetValue("budget.max_steps", 40)`
- **THEN** файл записан, `ConfigWriteResult.warnings` содержит проблему `agent.default_model` с событием `config.model.none` (`no model is configured; add a provider with at least one model`), исключения нет

#### Scenario: Первый провайдер без модели по умолчанию
- **WHEN** `$CODELAB_HOME` пуст, и одной правкой применяются `SetValue` ключей `providers.gw.kind`, `providers.gw.base_url` и `providers.gw.models.m.context_window` без `agent.default_model`
- **THEN** файл записан, `ConfigWriteResult.warnings` пуст, исключения нет

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

#### Scenario: Ссылка на секрет в одинарных кавычках
- **WHEN** применяется `UpsertMcpServer` stdio-сервера `gh` с `env.GH_TOKEN` = `Bearer ${secret:codelab/mcp/gh/x}` и `env.DEBUG` = строкой `off`
- **THEN** файл содержит `GH_TOKEN: 'Bearer ${secret:codelab/mcp/gh/x}'` без `\/` и `DEBUG: "off"`; загрузка возвращает те же строки

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
- **Источник ключа** (R4-4): `provider add` с любым из `--api-key-stdin`, `--api-key-secret`, `--api-key-env` SHALL заменять источник ключа целиком — поля другого источника (`api_key_secret`, `api_key_env`, литеральный `api_key`) удаляются той же записью. Пары `api_key_env` + `api_key_secret` у провайдера после команды НЕ SHALL быть. Без флага ключа источник не меняется.
- **Недостающие обязательные флаги** `provider add` (`--kind`, `--model`, `--context-window`) SHALL перечисляться все одной строкой stderr.
- **`provider remove`** при ссылке из явного `agent.*` (`agent.default_model` любого слоя) SHALL завершаться кодом `1`, stderr SHALL содержать `change the model first: config set agent.default_model <provider>/<model>`. Если удаление оставляет конфиг без провайдера с моделью (новая проблема с событием `config.model.none`), код SHALL быть `1` с этой проблемой, но без подсказки `change the model first`. Модель провайдера, которая записана только как последняя выбранная (требование `agent-runtime` «Последняя выбранная модель»), удалению НЕ SHALL мешать: файл состояния не меняется, следующая сессия выбирает модель по следующему шагу.
- **`provider add`** без `--default` SHALL НЕ трогать `agent.default_model`; модель новой сессии без ключа выбирается правилом требования «Модель по умолчанию без agent.default_model». С `--default` поведение прежнее.
- **`mcp add` и `mcp remove`** SHALL отклонять имя сервера с пробелом, `[`, `]` или `"` кодом `64`.
- **`mcp remove <name>`** SHALL искать сервер только по `name`, никогда по номеру элемента списка.
- **Ошибка разбора аргументов** `config set`, `config unset`, `provider` и `mcp` SHALL печатать фиксированную фразу (`invalid arguments for config set`, `invalid arguments for config unset`, `invalid arguments for provider`, `invalid arguments for mcp`) и справку, не цитируя слова argv.
- **Маскирование** (R0-2; design.md, D6) — в `config get` и `provider list`:
  - значение любого листа без дескриптора реестра и элемента отображения с произвольными ключами (`headers`, `env`), чьё имя — ключ из `inlineSecretKeys` или секретное по нормализованному правилу требования «Запись конфига ConfigWriter» (на любой глубине дерева), без `${secret:…}` и `${VAR}` SHALL печататься как `<redacted>`; значение со ссылкой — как есть; скалярный лист, описанный реестром (`api_key_secret`, `api_key_env`, `auth_header`), SHALL печататься как есть, **кроме** листа с находкой `literalSecretTag` (литеральный `api_key`, ссылка-значение п. 3 в `api_key_env`/`api_key_secret`) — он SHALL печататься `<redacted>` (design.md change `add-config-literal-secrets-and-migrate`, D5); значения с `${…}` тоже SHALL проходить `literalSecretTag` по литеральным частям;
  - непрозрачное поддерево схемы (`providers.*.auth`, `providers.*.key_rotation`, разделы после MVP и другие узлы без схемы листьев) SHALL печататься как `<opaque: edit the file>` без содержимого;
  - значение из слоя окружения SHALL заменяться именем источника: `<from env:CODELAB_PROVIDER_CONFIG>`, `<from env:CODELAB_MODEL>`;
  - URL (`base_url`, `url`) SHALL разбираться как URI и печататься без userinfo (R4-5); неразбираемый URL и URL с `@` без авторитета (`user:pass@host`) SHALL печататься как `<redacted>`; значение query-параметра или пары `имя=значение` во фрагменте с секретным именем (то же нормализованное правило имён) без ссылки `${…}` SHALL печататься как `<redacted>`, значение-ссылка — как есть;
  - отображения и списки маскируются поэлементно.
- **`config set`** SHALL разбирать значение через `SettingsRegistry.parseCliValue`.
- **`config path`** без флага слоя SHALL печатать строки `user: <path> (exists|missing)`, `project: …`, `local: …` и при заданной `CODELAB_CONFIG` — `CODELAB_CONFIG: …`; с `--project`/`--local` — только путь.
- **`provider list`** SHALL первой строкой печатать `Secrets: <backend>`, затем по строке на провайдера итогового конфига `<id>  kind: …  base_url: …  models: a, b  key: <source>` (без `base_url` — `(default)`); источник ключа без значения (`secret <name>: found|not set|unavailable`, `env <VAR>: set|not set`, `literal in config file`; у `api_key: ${VAR}` — `env <VAR>: set|not set`, у `api_key: ${secret:x}` — `secret x: found|not set|unavailable`; у ссылки-значения п. 3 — `unusable reference (looks like a secret value)` без поиска в хранилище).
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
- **THEN** первый — код `0`, `Updated budget.max_steps in <home>/config.yaml` и строка `warning: agent.default_model: no model is configured; add a provider with at least one model` (прежняя проблема конфига, R3-1), второй — `40` и слой `user`

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

#### Scenario: provider add в пустом CODELAB_HOME без --default
- **WHEN** `$CODELAB_HOME` пуст, окружение содержит `GW_KEY` (непустое значение), вызывается `provider add gw --kind openai-compatible --base-url https://x/v1 --model m --context-window 8192 --api-key-env GW_KEY` без `--default`, затем `config check`
- **THEN** первый — код `0`, stdout `Updated providers.gw in <home>/config.yaml` без строк `warning:`, в файле нет `default_model`; второй — `Default model: gw/m (first-provider)` и `Config: valid`

#### Scenario: provider remove единственного провайдера без ключа модели
- **WHEN** `config.yaml` объявляет только провайдера `gw` с моделью `m` без `agent.default_model`, и вызывается `provider remove gw`
- **THEN** код `1`, stderr содержит проблему `agent.default_model: no model is configured; add a provider with at least one model` и не содержит `change the model first`; файл не изменён

#### Scenario: provider remove провайдера последней модели
- **WHEN** `config.yaml` объявляет провайдеров `a` (модель `x`) и `b` (модель `y`) без `agent.default_model`, `$CODELAB_HOME/state/last-model.json` называет `b/y`, и вызывается `provider remove b`
- **THEN** код `0`, `providers.b` удалён, файл состояния не изменён; `config check` печатает `Default model: a/x (first-provider)`
