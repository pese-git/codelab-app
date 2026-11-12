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

Раздел `skills` (кроме подраздела `skills.operative`) — ключи схемы с потребителем (capability `agent-skills`, «Конфигурация навыков»; design.md change `add-agent-skills`, D11), capability `skills` в `profile.<name>` — известная. Ключ схемы MVP без потребителя в этой сборке и ключ раздела после MVP SHALL приниматься с одним предупреждением `config.key.not_applied {key, source}` на каждый явно заданный лист; ключ вне схемы и вне списка разделов после MVP — проблема `unknownKey`. В `profile.<name>` допустимы только встроенные профили и известные capability (иначе `unknownKey`); capability после MVP даёт `config.key.not_applied`; расширение профиля — проблема с ключом `profile.<name>.<capability>`.

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
- **WHEN** глобальный конфиг задаёт `loop.empty_response_retries: 3` и `skills.operative.max_tokens: 1024`
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

#### Scenario: Раздел skills применяется
- **WHEN** глобальный конфиг задаёт `skills.max_skills: 100`, `skills.catalog_max_chars: 500` и `profile.agent-serve.skills: off`
- **THEN** `max_skills` применён без `config.key.not_applied`; `catalog_max_chars` — проблема границы `1000–64000`; сужение профиля по `skills` принято

### Requirement: config check показывает диагностику файлов проекта
`ConfigCommands.check` SHALL после валидной загрузки конфига загружать файлы проекта для канонического `--cwd` (та же форма, что у runtime: `LocalExecutionEnv.realpath`) тем же `ProjectFilesLoader` с доверием и каталогом моделей загруженного конфига — и файлы проекта, и, при включённой capability `skills`, навыки (`loadSkills` и проверка ядра, capability `agent-skills`) и печатать перед последней строкой (design.md, D13):
- каждую диагностику уровня `error` или `warning` — строкой `warning: <path>[:<line>[:<column>]]: <message>`;
- диагностику `untrusted_project` уровня `info` — строкой `note: <каталог>: the project is not trusted; add it to trusted_projects`; диагностика `untrusted_project` уровня `warning` (относительный элемент `skills.extra_roots` недоверенного проекта — ошибка настройки) печатается по общему правилу строкой `warning:`; по строке на каталог (`.codelab/prompts`, `.codelab/agents`, каждый корень навыков проекта `.codelab/skills` и `.agents/skills`). Предупреждения навыков (`yaml_repaired`, `invalid_name`, `name_mismatch`, `missing_name`, `unknown_key`, `empty_body`, `shadowed` и другие уровня `warning`) печатаются по общему правилу.

Прочие диагностики уровня `info` НЕ SHALL печататься. Сообщения SHALL быть фиксированными текстами кодов (D3, D10); имя ключа или фрагмент файла в сообщение НЕ SHALL попадать. Непредвиденное исключение загрузчика SHALL давать одну строку `warning: <cwd>: project files could not be read: <runtimeType>`; загрузка дольше 5 с (D6) SHALL прерываться строкой `warning: <cwd>: project files were not read within 5 s`. Навыки читаются отдельной фазой (capability `agent-skills`, «Порт файлов навыков»): исключение или таймаут только этой фазы SHALL давать строку `warning: <cwd>: skills could not be read: <runtimeType>` или `warning: <cwd>: skills were not read within 5 s`, а диагностики файлов проекта печатаются как обычно; и наоборот. Диагностики, заметки, сбой и таймаут НЕ SHALL считаться проблемами: последняя строка и код выхода определяются только конфигом. При невалидном конфиге файлы проекта НЕ SHALL проверяться. Вывод SHALL совпадать у `codelab-agent config check` и `codelab config check`.

#### Scenario: Битое определение агента
- **WHEN** конфиг валиден, проект доверенный, а `.codelab/agents/reviewer.md` содержит неизвестный ключ `color` в строке 4
- **THEN** stdout содержит строку с префиксом `warning: <cwd>/.codelab/agents/reviewer.md:4:1: unknown frontmatter key`, без `color`; последняя строка `Config: valid`, код `0`

#### Scenario: Одинаково у двух бинарей
- **WHEN** `codelab-agent config check` и `codelab config check` запускаются в том же `cwd` с битым шаблоном `$CODELAB_HOME/prompts/Review.md`
- **THEN** у обоих есть строка `warning:` с путём шаблона и `not a valid command name`, коды выхода совпадают

#### Scenario: Недоверенный проект
- **WHEN** конфиг валиден, `cwd` нет в `trusted_projects`, а в нём есть `.codelab/prompts/` и `.codelab/agents/`
- **THEN** stdout содержит ровно две строки `note: <каталог>: the project is not trusted; add it to trusted_projects` — для `<cwd>/.codelab/prompts` и `<cwd>/.codelab/agents`; других строк от диагностик `info` нет; последняя строка и код выхода — как без этих каталогов

#### Scenario: Сбой загрузчика
- **WHEN** конфиг валиден, а загрузчик бросает непредвиденное исключение (в тестах — подменённый бросающий источник файлов проекта: через `CODELAB_HOME` сбой больше не вызвать, тильда даёт ошибку использования заранее)
- **THEN** у обоих бинарей stdout содержит одну строку `warning: <cwd>: project files could not be read: <runtimeType>`, последняя строка и код выхода — как без файлов проекта

#### Scenario: Таймаут загрузки
- **WHEN** конфиг валиден, а загрузка файлов проекта не завершается за 5 с
- **THEN** stdout содержит строку `warning: <cwd>: project files were not read within 5 s`, последняя строка и код выхода — как без файлов проекта

#### Scenario: Битый навык
- **WHEN** конфиг валиден, а `$CODELAB_HOME/skills/notes/SKILL.md` содержит `name: Notes`
- **THEN** stdout содержит строку с префиксом `warning: <home>/skills/notes/SKILL.md:` и фиксированным текстом кода `invalid_name`; последняя строка `Config: valid`, код `0`
