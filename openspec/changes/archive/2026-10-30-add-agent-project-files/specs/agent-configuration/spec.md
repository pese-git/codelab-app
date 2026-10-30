## ADDED Requirements

### Requirement: Корень состояния CODELAB_HOME
Корень глобального состояния агента — `CODELAB_HOME`, по умолчанию `~/.codelab` (`agent-core-architecture` §15.6). Его SHALL вычислять одна функция `codelabHomeOf` (`codelab_agent_io`) для всех потребителей: слоя 2 (`$CODELAB_HOME/config.yaml`), поиска `codelab.toml`, пользовательской области файлов проекта (`prompts/`, `agents/`) и журналов сессий хоста (design.md change `add-agent-project-files`, D17; решение пользователя 2026-10-30). Значение `CODELAB_HOME`, равное `~` или начинающееся с `~/`, SHALL раскрываться: `~` заменяется домашним каталогом — `HOME`, а если он не задан или пуст, `USERPROFILE`. Почему: тильду раскрывает оболочка, а в unit launchd/systemd, в `env` профиля и внутри кавычек она приходит буквально, и `~/x` молча указывал бы на каталог `./~/x` относительно текущего каталога процесса. Раскрытие SHALL совпадать с раскрытием `~` в `trusted_projects` (требование «Доверие к проектному конфигу»). Любое другое значение, начинающееся с `~` (`~user/…`, а также `~\…` на Windows — его, как и `trusted_projects`, агент не раскрывает), SHALL быть ошибкой использования (`ConfigUsageException`) с текстом `CODELAB_HOME: ~user is not supported, use an absolute path`. Значение `~` или `~/…` при неизвестном домашнем каталоге (`HOME` и `USERPROFILE` не заданы или пусты) SHALL быть ошибкой использования с текстом `CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an absolute path`. Ошибка возникает до чтения файлов: `serve` и `config check` печатают текст в stderr и завершаются с кодом `64`; относительный каталог `./~…` не создаётся и не читается. Пустой `CODELAB_HOME` SHALL считаться незаданным; умолчание без `CODELAB_HOME` не меняется. При запуске со сценарием `--llm-script` `$CODELAB_HOME` не читается (требование agent-binary «Конфиг бинаря…»; D16), поэтому `CODELAB_HOME` в этом режиме НЕ SHALL раскрываться и проверяться: неверное значение не даёт кода `64`.

#### Scenario: Тильда раскрывается в HOME
- **WHEN** загрузчик вызывается с `CODELAB_HOME='~/cl'` (буквально, без раскрытия оболочкой) и `HOME=<tmp>`, а `<tmp>/cl/config.yaml` задаёт `budget.max_steps: 50`
- **THEN** слой 2 прочитан из `<tmp>/cl/config.yaml` (источник в `config check` — этот путь), итоговое значение `50`; каталог `<cwd>/~` не создаётся и не читается

#### Scenario: Пользовательская область файлов проекта
- **WHEN** `serve --stdio` или `config check` запускается с `CODELAB_HOME='~/cl'`, `HOME=<tmp>`, а в `<tmp>/cl/prompts/` лежит шаблон `review.md`
- **THEN** шаблон загружен из `<tmp>/cl/prompts/review.md` (команда `/review` опубликована, `config check` не печатает `project files could not be read`)

#### Scenario: Windows и USERPROFILE
- **WHEN** `CODELAB_HOME='~/cl'`, `HOME` не задан, `USERPROFILE=<dir>`
- **THEN** корень состояния — `<dir>/cl`

#### Scenario: ~user — ошибка использования
- **WHEN** `codelab-agent serve --stdio` или `codelab-agent config check` запускается с `CODELAB_HOME='~bob/cl'` и `HOME=<tmp>`
- **THEN** код `64`, stderr содержит `CODELAB_HOME: ~user is not supported, use an absolute path`; каталог `<cwd>/~bob` не создаётся

#### Scenario: Тильда без домашнего каталога
- **WHEN** `codelab-agent config check` запускается с `CODELAB_HOME='~/cl'`, а `HOME` и `USERPROFILE` не заданы или пусты
- **THEN** код `64`, stderr содержит `CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an absolute path`

#### Scenario: Сценарий --llm-script не проверяет CODELAB_HOME
- **WHEN** `codelab-agent serve --stdio --llm-script <file.json>` запускается с `CODELAB_HOME='~bob/cl'` (или `CODELAB_HOME='~/cl'` без `HOME` и `USERPROFILE`)
- **THEN** бинарь запускается и проводит ход сценария, ошибки использования и кода `64` нет; каталог `~bob` не создаётся и не читается

#### Scenario: Абсолютное значение не меняется
- **WHEN** `CODELAB_HOME=/srv/cl`
- **THEN** корень состояния — `/srv/cl`

### Requirement: Ключ tools.project_context.max_bytes
Ключ `tools.project_context.max_bytes` SHALL применяться: целое `0..262144`, по умолчанию `32768`; `0` выключает чтение контекста проекта (design.md change `add-agent-project-files`, D5). Значение вне диапазона SHALL быть проблемой конфига с путём ключа. В проектных слоях недоверенного проекта значение SHALL приниматься только на уменьшение относительно результата слияния нижних слоёв; увеличение SHALL отбрасываться с предупреждением `config.project.untrusted_key`. Ключ НЕ SHALL давать `config.key.not_applied`.

#### Scenario: Увеличение из недоверенного проекта
- **WHEN** глобальный конфиг не задаёт ключ, а `.codelab/config.yaml` недоверенного проекта задаёт `tools.project_context.max_bytes: 200000`
- **THEN** итоговое значение `32768`, предупреждение `config.project.untrusted_key` с ключом `tools.project_context.max_bytes`

#### Scenario: Уменьшение из проекта
- **WHEN** недоверенный проект задаёт `tools.project_context.max_bytes: 4096`
- **THEN** итоговое значение `4096`, предупреждения нет

### Requirement: Доверенные проекты в CoreConfig
`CoreConfig` SHALL содержать `trustedProjects` — канонические абсолютные корни из `trusted_projects` глобального слоя (после раскрытия `~` и symlink в `ConfigLoader`); снимок `withoutProject` SHALL содержать тот же список. Проектные слои список не меняют (CFG-3).

#### Scenario: Список доступен сессии вне корня
- **WHEN** глобальный конфиг доверяет `/work/a` и `/work/b`, а проектные слои прочитаны для `/work/a`
- **THEN** `config.trustedProjects` и `config.withoutProject.trustedProjects` равны `[/work/a, /work/b]`

### Requirement: config check показывает диагностику файлов проекта
`ConfigCommands.check` SHALL после валидной загрузки конфига загружать файлы проекта для канонического `--cwd` (та же форма, что у runtime: `LocalExecutionEnv.realpath`) тем же `ProjectFilesLoader` с доверием и каталогом моделей загруженного конфига и печатать перед последней строкой (design.md, D13):
- каждую диагностику уровня `error` или `warning` — строкой `warning: <path>[:<line>[:<column>]]: <message>`;
- диагностику `untrusted_project` — строкой `note: <каталог>: the project is not trusted; add it to trusted_projects`, по строке на каталог (`.codelab/prompts`, `.codelab/agents`).

Прочие диагностики уровня `info` НЕ SHALL печататься. Сообщения SHALL быть фиксированными текстами кодов (D3, D10); имя ключа или фрагмент файла в сообщение НЕ SHALL попадать. Непредвиденное исключение загрузчика SHALL давать одну строку `warning: <cwd>: project files could not be read: <runtimeType>`; загрузка дольше 5 с (D6) SHALL прерываться строкой `warning: <cwd>: project files were not read within 5 s`. Диагностики, заметки, сбой и таймаут НЕ SHALL считаться проблемами: последняя строка и код выхода определяются только конфигом. При невалидном конфиге файлы проекта НЕ SHALL проверяться. Вывод SHALL совпадать у `codelab-agent config check` и `codelab config check`.

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
