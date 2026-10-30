# agent-project-context Specification

## Purpose
Инструкции проекта в системном промпте Dart-агента: ядро `codelab_agent_core` объявляет порт `ProjectFilesSource`, а `codelab_agent_io` (`ProjectFilesLoader`) читает `AGENTS.md` от `cwd` вверх до корня git (`CLAUDE.md` — алиас только без `AGENTS.md`) и кладёт их в секцию `project-context` с бюджетом `tools.project_context.max_bytes`. Чтение ограничено двухшаговой границей (каталог — по корню области, файлы — через `BoundedEnv` реального каталога), лимитами на число и размер файлов и таймаутом; доверие fail-closed: без канонического `cwd` или `PathResolver` проект недоверенный. По WebSocket файлы проекта не читаются. Решения и обоснования — `design.md` архивного change `add-agent-project-files` (D1–D17) и `agent-core-architecture` §11.5, §17.2.2.
## Requirements
### Requirement: Порт файлов проекта
Ядро SHALL объявлять порт `ProjectFilesSource` с методом `load(ProjectFilesQuery)` и необязательное поле `AgentCoreServices.projectFiles` (design.md change `add-agent-project-files`, D1). Запрос: канонический `cwd` сессии, признак `projectTrusted`, `contextMaxBytes`, токен отмены. Результат `ProjectFiles` содержит сырые файлы контекста, файлы шаблонов и определений (frontmatter — `ConfigTree` с позициями, тело, строка начала тела) и список `ExtensionDiagnostic {path, line?, column?, level, code, message}`.

Реализация `ProjectFilesLoader` SHALL жить в `codelab_agent_io`. Порт НЕ SHALL бросать исключений для ошибок файлов: каждая ошибка — диагностика. Без порта (`null`) сессия SHALL создаваться без файлов проекта, как до этого change. Хост, который по своему транспорту файлы проекта не читает, порт не передаёт (`codelab-agent serve --ws`, agent-binary «Файлы проекта в бинаре»).

Коды и уровни диагностик (D3, D6) SHALL быть такими:
- `warning` — `outside_root` (путь вне корня области), `not_utf8` (файл не в UTF-8), `limit_exceeded` для предела 100 файлов `*.md` в каталоге шаблонов или агентов (лишние отброшены), `unreadable` (файл не открылся или не прочитался, нет `PathResolver` у окружения, после открытия путь или тип изменились), `timeout` (загрузка не уложилась в таймаут фазы);
- `info` — `shadowed` (файл перекрыт другим), `limit_exceeded` для предела 64 уровней обхода к корню git;
- `error` — `unexpected` (непредвиденное исключение порта).

Загрузка SHALL ограничиваться таймаутом фазы 5 с (D6). Ядро SHALL ждать первым из трёх событий — результата порта, отмены рантайма и таймаута:
- отмена (`dispose()` рантайма) — сессия НЕ SHALL создаваться, результат порта выбрасывается;
- таймаут — токен запроса SHALL отменяться, сессия SHALL создаваться без файлов проекта, лог `project_files.diagnostic` с `code: timeout`; поздний результат порта выбрасывается.

#### Scenario: Без порта
- **WHEN** хост собирает ядро без `projectFiles` и создаёт сессию в каталоге с `AGENTS.md`
- **THEN** системный промпт не содержит секции `project_context`, `available_commands_update` пуст, опции `agent` нет

#### Scenario: Исключение порта не ломает сессию
- **WHEN** фейковый `ProjectFilesSource` бросает исключение при `load`
- **THEN** сессия создаётся без файлов проекта, лог `project_files.diagnostic` уровня `warning` с `code: unexpected` и типом исключения

#### Scenario: Таймаут загрузки
- **WHEN** фейковый `ProjectFilesSource` не завершает `load` дольше таймаута фазы
- **THEN** `createSession` возвращает сессию без файлов проекта, токен запроса отменён, лог `project_files.diagnostic` с `code: timeout`; результат, пришедший после таймаута, в промпт не попадает

#### Scenario: Отмена рантайма во время загрузки
- **WHEN** `AgentRuntime.dispose()` вызывается, пока фейковый `ProjectFilesSource` ещё не завершил `load`
- **THEN** `createSession` завершается отменой, сессия не создаётся, поздний результат порта выбрасывается

### Requirement: Граница чтения файлов проекта
`ProjectFilesLoader` SHALL читать файлы с локальной файловой системы процесса агента через `BoundedEnv`, корень которого — корень своей области (D2):
- корень git-репозитория или `cwd` — для контекста;
- `<cwd>/.codelab/prompts` и `<cwd>/.codelab/agents` — для файлов проекта;
- `$CODELAB_HOME` — для файлов пользователя.

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

### Requirement: Поиск инструкций проекта
Загрузчик SHALL искать от канонического `cwd` вверх первый каталог с записью `.git` (каталог или файл; символическая ссылка `.git` маркером не считается — её цель лежит вне границы чтения), не дальше 64 уровней. Найденный каталог — корень, иначе корень — `cwd`. На каждом уровне от корня до `cwd` SHALL читаться `AGENTS.md`, а если его нет — `CLAUDE.md` (алиас; при обоих `CLAUDE.md` даёт диагностику `info` `shadowed`). Дополнительно SHALL читаться `$CODELAB_HOME/AGENTS.md`. Файлы SHALL читаться для доверенного и недоверенного проекта одинаково (D4). При `contextMaxBytes == 0` файлы контекста не читаются.

#### Scenario: От корня к cwd
- **WHEN** `/repo/AGENTS.md` содержит «правило A», `/repo/pkg/AGENTS.md` — «правило B», `/repo` — корень git, а сессия создаётся с `cwd: /repo/pkg`
- **THEN** системный промпт первого запроса к модели содержит «правило A», а после него «правило B» (`core/project-context-agents-md-leaf-first`, E-01)

#### Scenario: Без репозитория
- **WHEN** у `cwd` и его предков нет `.git`, а `AGENTS.md` есть в `cwd` и в родительском каталоге
- **THEN** в промпт входит только файл `cwd`

#### Scenario: Алиас CLAUDE.md
- **WHEN** в корне репозитория есть только `CLAUDE.md`, а в `cwd` — `AGENTS.md` и `CLAUDE.md`
- **THEN** в промпт входят `CLAUDE.md` корня и `AGENTS.md` `cwd`; `CLAUDE.md` `cwd` не входит, есть диагностика `shadowed`

#### Scenario: Worktree
- **WHEN** в корне рабочей копии `.git` — файл, а не каталог
- **THEN** этот каталог считается корнем репозитория

### Requirement: Бюджет и усечение контекста проекта
Чистая функция ядра `assembleProjectContext(files, maxBytes)` SHALL:
- выстраивать файлы от общего к частному: `$CODELAB_HOME/AGENTS.md`, затем от корня к `cwd`;
- раздавать бюджет `maxBytes` (байты UTF-8) в обратном порядке, начиная с файла `cwd`;
- оставлять файл, который помещается, целиком;
- усекать файл, который не помещается, по последней границе строки в оставшемся бюджете и дописывать строку `[file truncated: showing N of M bytes]`, которая в бюджет не входит;
- если первая строка файла длиннее остатка бюджета — резать её по последней границе символа UTF-8 в остатке (символ посередине не режется);
- после усечения файла считать бюджет исчерпанным: все более дальние файлы, включая пользовательский, пропускаются и входят в `omitted`;
- пропускать пустые после обрезки пробелов файлы.

Путь файла в секции SHALL быть относительным от корня обхода, а у пользовательского файла — литералом `$CODELAB_HOME/AGENTS.md`. Одинаковые входы SHALL давать побайтово одинаковый результат.

#### Scenario: Ближний файл получает бюджет первым
- **WHEN** бюджет 100 байт, файл `cwd` — 60 байт, файл корня — 80 байт
- **THEN** файл `cwd` входит целиком, файл корня усечён до последней границы строки не дальше 40 байт с пометкой `[file truncated: showing N of 80 bytes]`

#### Scenario: Длинная первая строка
- **WHEN** бюджет 10 байт, а файл `cwd` — одна строка из 20 байт, в которой 10-й и 11-й байты занимает один двухбайтовый символ
- **THEN** в секцию входят первые 9 байт строки и пометка `[file truncated: showing 9 of 20 bytes]`

#### Scenario: После усечения дальние файлы пропускаются
- **WHEN** бюджет 100 байт, файл `cwd` — 60 байт, файл `pkg` — 80 байт, файл корня — 10 байт
- **THEN** файл `cwd` входит целиком, `pkg` усечён, файл корня в секцию не входит, `omitted: 1`

#### Scenario: Бюджет исчерпан
- **WHEN** файл `cwd` занимает весь бюджет
- **THEN** более дальние файлы и пользовательский файл в секцию не входят, `project_context.loaded` содержит `omitted` с их числом

#### Scenario: Выключенный контекст
- **WHEN** `tools.project_context.max_bytes: 0`
- **THEN** файлы контекста не читаются, секции `project_context` нет

### Requirement: Секция project_context системного промпта
Ядро SHALL иметь промпты `prompts/project_context.md` (`id: project_context`, `vars: [files]`, заголовок `# Project instructions`, правило, что инструкции не отменяют правил безопасности и решений пользователя) и `prompts/project_context_file.md` (`vars: [path, content]`, блок `<project-instructions path="{{path}}">…</project-instructions>`). Секция SHALL отсутствовать, если ни один файл не вошёл. Тексты секций НЕ SHALL называть инструментов (PR-6).

Экранирование при сборке блока (D5):
- в содержимом файла каждое вхождение открывающего или закрывающего тега блока — `<`, необязательные пробельные символы, необязательный `/`, необязательные пробельные символы и `project-instructions` без учёта регистра ASCII — SHALL получать `\` сразу после `<` (`</project-instructions` → `<\/project-instructions`, `</PROJECT-INSTRUCTIONS` → `<\/PROJECT-INSTRUCTIONS`, `< / project-instructions` → `<\ / project-instructions`, `<project-instructions` → `<\project-instructions`);
- в значении атрибута `path` символы `"`, `<`, `>`, `\r`, `\n` SHALL заменяться на `_`. Путь в промпте поэтому МОЖЕТ отличаться от пути в логе `project_context.loaded` и в диагностиках: там путь не экранируется.

#### Scenario: Файл не закрывает свой блок
- **WHEN** `AGENTS.md` содержит строку `</project-instructions>` и далее текст
- **THEN** в промпте эта строка выглядит как `<\/project-instructions>`, а блок файла закрывается один раз, после всего содержимого

#### Scenario: Тег в другом регистре и с пробелами
- **WHEN** `AGENTS.md` содержит `</PROJECT-INSTRUCTIONS>`, `< / project-instructions>` и `<project-instructions path="x">`
- **THEN** в промпте они выглядят как `<\/PROJECT-INSTRUCTIONS>`, `<\ / project-instructions>` и `<\project-instructions path="x">`; ни один не открывает и не закрывает блок

#### Scenario: Кавычка в имени каталога
- **WHEN** файл контекста лежит в каталоге `a"b` под корнем репозитория
- **THEN** атрибут блока — `path="a_b/AGENTS.md"`, а лог `project_context.loaded` называет `a"b/AGENTS.md`

#### Scenario: Наблюдаемость
- **WHEN** сессия создаётся с двумя файлами контекста, один из которых усечён
- **THEN** лог `project_context.loaded` содержит `session_id`, пути обоих файлов, `truncated: 1`, `root: git` и не содержит текста файлов

