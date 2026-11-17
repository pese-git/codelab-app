## MODIFIED Requirements

### Requirement: Порт файлов проекта
Ядро SHALL объявлять порт `ProjectFilesSource` с методом `load(ProjectFilesQuery)` и необязательное поле `AgentCoreServices.projectFiles` (design.md change `add-agent-project-files`, D1). Запрос: канонический `cwd` сессии, признак `projectTrusted`, `contextMaxBytes`, токен отмены. Результат `ProjectFiles` содержит сырые файлы контекста, файлы шаблонов и определений (frontmatter — `ConfigTree` с позициями, тело, строка начала тела) и список `ExtensionDiagnostic {path, line?, column?, level, code, message}`.

Реализация `ProjectFilesLoader` SHALL жить в `codelab_agent_io`; тот же класс реализует порт навыков `SkillFilesSource` (capability `agent-skills`, «Порт файлов навыков»; design.md change `add-agent-skills`, D1) с той же границей, лимитами и кодами диагностик, а навыки загружаются отдельной фазой со своим таймаутом. Порт НЕ SHALL бросать исключений для ошибок файлов: каждая ошибка — диагностика. Без порта (`null`) сессия SHALL создаваться без файлов проекта, как до этого change. Хост, который по своему транспорту файлы проекта не читает, порт не передаёт (`codelab-agent serve --ws`, agent-binary «Файлы проекта в бинаре»).

Коды и уровни диагностик (D3, D6) SHALL быть такими:
- `warning` — `outside_root` (путь вне корня области), `not_utf8` (файл не в UTF-8), `limit_exceeded` для предела 100 файлов `*.md` в каталоге шаблонов или агентов и предела 1000 подкаталогов в корне навыков (лишние отброшены), `unreadable` (файл не открылся или не прочитался, нет `PathResolver` у окружения, после открытия путь или тип изменились), `timeout` (загрузка не уложилась в таймаут фазы), `unresolved_root` (элемент `skills.extra_roots` на `~` без домашнего каталога, решение Q41), `untrusted_project` для относительного элемента `skills.extra_roots` недоверенного проекта (корни навыков и каталоги файлов проекта недоверенного проекта дают `untrusted_project` уровня `info` — ожидаемое состояние, а не ошибка настройки; capability `agent-skills`, «Корни навыков, приоритет и согласие»);
- `info` — `shadowed` (файл контекста, шаблон или определение перекрыты другим; перекрытие навыков порт не выдаёт: `warning` `shadowed` навыка даёт ядро при построении каталога, capability `agent-skills`, «Корни навыков, приоритет и согласие», решения Q21, Q39), `limit_exceeded` для предела 64 уровней обхода к корню git;
- `error` — `unexpected` (непредвиденное исключение порта).

Уровень диагностики и уровень записи лога различаются: событие `project_files.diagnostic` для диагностик `error` и `warning` SHALL писаться с уровнем лога `warning`, для `info` — с уровнем `debug` (так устроен рантайм); поэтому сценарий «Исключение порта не ломает сессию» говорит об уровне лога `warning` у диагностики `error` `unexpected`.

Загрузка SHALL ограничиваться таймаутом фазы 5 с (D6). Ядро SHALL ждать первым из трёх событий — результата порта, отмены рантайма и таймаута:
- отмена (`dispose()` рантайма) — сессия НЕ SHALL создаваться, результат порта выбрасывается;
- таймаут — токен запроса SHALL отменяться, сессия SHALL создаваться без файлов проекта, лог `project_files.diagnostic` с `code: timeout`; поздний результат порта выбрасывается.

#### Scenario: Без порта
- **WHEN** хост собирает ядро без `projectFiles` и создаёт сессию в каталоге с `AGENTS.md`
- **THEN** системный промпт не содержит секции `project_context`, `available_commands_update` не содержит команд шаблонов (только встроенные команды сессии), опции `agent` нет

#### Scenario: Исключение порта не ломает сессию
- **WHEN** фейковый `ProjectFilesSource` бросает исключение при `load`
- **THEN** сессия создаётся без файлов проекта, лог `project_files.diagnostic` уровня `warning` с `code: unexpected` и типом исключения

#### Scenario: Таймаут загрузки
- **WHEN** фейковый `ProjectFilesSource` не завершает `load` дольше таймаута фазы
- **THEN** `createSession` возвращает сессию без файлов проекта, токен запроса отменён, лог `project_files.diagnostic` с `code: timeout`; результат, пришедший после таймаута, в промпт не попадает

#### Scenario: Отмена рантайма во время загрузки
- **WHEN** `AgentRuntime.dispose()` вызывается, пока фейковый `ProjectFilesSource` ещё не завершил `load`
- **THEN** `createSession` завершается отменой, сессия не создаётся, поздний результат порта выбрасывается

#### Scenario: Один загрузчик для двух портов
- **WHEN** хост `--stdio` собирает ядро
- **THEN** `AgentCoreServices.projectFiles` и `AgentCoreServices.skillFiles` — один и тот же объект `ProjectFilesLoader`

### Requirement: Граница чтения файлов проекта
`ProjectFilesLoader` SHALL читать файлы с локальной файловой системы процесса агента через `BoundedEnv`, корень которого — корень своей области (D2):
- корень git-репозитория или `cwd` — для контекста;
- `<cwd>/.codelab/prompts` и `<cwd>/.codelab/agents` — для файлов проекта;
- `$CODELAB_HOME` — для файлов пользователя;
- для каталогов навыков — каждый корень навыков: `<уровень>/.codelab/skills` и `<уровень>/.agents/skills` на уровнях от `cwd` до корня git-репозитория (поиск корня — тот же, что у инструкций проекта; решение Q22), `$CODELAB_HOME/skills`, `~/.agents/skills` и каждый элемент `skills.extra_roots`; файлы навыка (`SKILL.md` и перечисление сопутствующих) — через `BoundedEnv` с корнем в реальном пути каталога навыка (capability `agent-skills`, «Корни навыков и согласие»).

Env сессии ACP (`AcpClientExecutionEnv`) для этих файлов НЕ SHALL использоваться. Путь, чей `realpath` вне корня области, SHALL отклоняться до чтения с диагностикой `outside_root`. Единственная операция вне границы — проверка существования записи `.git` у предков `cwd`, без чтения содержимого.

Файл контекста SHALL читаться не больше `contextMaxBytes + 1` байт средствами `dart:io` по каноническому пути, который вернул `BoundedEnv.realpath` корня области (D2, D5). Поэтому загрузчик SHALL требовать окружение с `PathResolver` (`LocalExecutionEnv`): без него файлы НЕ SHALL читаться, диагностика `unreadable`. После открытия файла загрузчик SHALL повторно проверять, что канонический путь не изменился и остался внутри корня и что это обычный файл; иначе файл НЕ SHALL читаться, диагностика `unreadable` или `outside_root`.

#### Scenario: Окружение без PathResolver
- **WHEN** `ProjectFilesLoader` получает окружение без `PathResolver`, а в `cwd` есть `AGENTS.md`
- **THEN** файл не читается, `ProjectFiles.context` пуст, есть диагностика `unreadable`

#### Scenario: Путь подменён после проверки
- **WHEN** между проверкой `realpath` и открытием `<cwd>/AGENTS.md` файл заменён symlink на файл вне корня (тест подменяет путь через точку внедрения загрузчика)
- **THEN** содержимое внешнего файла в `ProjectFiles.context` не попадает, есть диагностика `outside_root` или `unreadable`

#### Scenario: Symlink наружу
- **WHEN** `<cwd>/AGENTS.md` — symlink на файл вне корня репозитория
- **THEN** файл не читается, в промпте его содержимого нет, есть диагностика `outside_root` с путём

#### Scenario: Чтение не идёт через клиента ACP
- **WHEN** ACP-клиент создаёт сессию в каталоге с `AGENTS.md`
- **THEN** до ответа `session/new` агент не отправляет клиенту `fs/read_text_file`, а системный промпт первого хода содержит правила файла

#### Scenario: Сопутствующий файл-ссылка наружу
- **WHEN** в каталоге навыка `$CODELAB_HOME/skills/notes` файл `ref.md` — symlink на `$CODELAB_HOME/config.yaml`
- **THEN** навык загружен, `ref.md` нет в списке его сопутствующих файлов, содержимое `config.yaml` не читалось
