## MODIFIED Requirements

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
