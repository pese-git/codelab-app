## MODIFIED Requirements

### Requirement: Страницы Providers и MCP servers в навигации
Composition root SHALL делать видимыми страницы «Connection», «Providers», «MCP servers», «Agents & modes» и «Skills & extensions» группы «Agent» в порядке требования «Навигация настроек»; остальные страницы остаются скрытыми (SETUP-17). Тела страниц SHALL иметь ключи `settings-providers`, `settings-mcp`, `settings-agents-modes` и `settings-skills`. Поиск «Find a setting» SHALL находить «Providers» по ключевым словам `provider`, `model`, `api key`, `key storage`, `base url`, «MCP servers» — по `mcp`, `server`, `tools`, `headers`, «Agents & modes» — по `mode`, `permission`, `bypass`, `plan`, `effort`, `reasoning`, `agent`, `definition`, `subagent` (design.md change `add-settings-agents-modes`, D9, D20), а «Skills & extensions» — по `skill`, `agents.md`, `context`, `template`, `prompt`, `extension` (design.md change `add-app-skills-page`, D13).

#### Scenario: Пять страниц группы Agent
- **WHEN** пользователь открывает настройки
- **THEN** навигация показывает в группе «Agent» пункты `settings-nav-connection`, `settings-nav-providers`, `settings-nav-mcp-servers`, `settings-nav-agents-and-modes`, `settings-nav-skills-and-extensions` в этом порядке, заголовка «App» нет

#### Scenario: Поиск ключа API
- **WHEN** пользователь вводит `api key` в «Find a setting»
- **THEN** в навигации остаётся «Providers»

#### Scenario: Поиск режима bypass
- **WHEN** пользователь вводит `bypass` в «Find a setting»
- **THEN** в навигации остаётся «Agents & modes», а выбор результата открывает тело `settings-agents-modes`

#### Scenario: Поиск AGENTS.md
- **WHEN** пользователь вводит `agents.md` в «Find a setting»
- **THEN** в навигации остаётся «Skills & extensions»

## ADDED Requirements

### Requirement: Страница «Skills & extensions»: доступ и папка
Страница «Skills & extensions» SHALL показывать данные агента профиля текущего подключения, а без подключения — профиля по умолчанию. Доступ SHALL вычислять `resolveSettingsAccess` (spec client-agent-setup «Доступ к настройкам агента»), смена подключения SHALL перечитывать страницу (design.md change `add-app-skills-page`, D2).

Папкой SHALL быть папка сессии в фокусе, без неё — выбранный проект; смена папки сессии в фокусе SHALL перечитывать страницу. Без папки страница SHALL показывать `Open a project folder to see the context files, skills and prompt templates the agent uses there.` (ключ `skills-no-folder`) и НЕ SHALL читать файлы.

Для `EditableSettings` страница SHALL читать файлы на машине клиента функцией моста (spec client-agent-setup «Обзор расширений агента»), с конфигурацией, `CODELAB_HOME` и окружением агента этого профиля (окружение app, дополненное `env` stdio-профиля). Агенту страница НЕ SHALL отправлять запросов и команд, ACP НЕ SHALL меняться.

Для `RemoteReadOnly` и `NotManaged` страница НЕ SHALL читать локальные файлы и конфиг и НЕ SHALL показывать элементов записи (SETUP-2). Она SHALL показывать InfoBar уровня `warning` (ключ `skills-read-only`): `Read-only: this agent runs on <scheme://host:port>. Its skills, context files and prompt templates are read on that host: codelab-agent config check.` или `Skills are managed by <agentName>.` (решение Q1 (а) design.md).

Если конфиг агента не разбирается или нарушает схему, страница SHALL показывать проблемы загрузчика с путём ключа (ключ `skills-unreadable`) и НЕ SHALL читать файлы проекта и навыков и писать конфиг.

Для проекта вне `trusted_projects` (доверие — тем же расчётом, что у агента и `config check`, fail-closed) страница SHALL показывать InfoBar `skills-untrusted`: `This project is not in trusted_projects, so the agent does not read its skills and prompt templates. Your own skills and AGENTS.md files are shown.` и строку `Trust is set in trusted_projects of <файл пользовательского конфига>.`. Навыки и шаблоны проекта НЕ SHALL читаться и показываться.

#### Scenario: WebSocket-агент
- **WHEN** окно подключено к профилю `wss://devbox:7420/acp`, а в папке проекта есть `.codelab/skills/review/SKILL.md`
- **THEN** страница показывает InfoBar `skills-read-only` с `wss://devbox:7420` без `/acp`, таблицы навыков и выключателей нет, файлы проекта и `$CODELAB_HOME` не читались

#### Scenario: Сторонний stdio-агент
- **WHEN** окно подключено к stdio-профилю с командой `python` и аргументами `-m other_agent`
- **THEN** страница показывает `Skills are managed by python.` и не читает файлов

#### Scenario: Недоверенный проект
- **WHEN** папка `/work/repo` не в `trusted_projects`, в ней есть `/work/repo/AGENTS.md` и `.codelab/skills/deploy/SKILL.md`, а в `$CODELAB_HOME/skills/notes/SKILL.md` — навык пользователя
- **THEN** страница показывает InfoBar `skills-untrusted`, цепочку с `AGENTS.md`, навык `notes` и не показывает навык `deploy` и шаблоны `.codelab/prompts`

#### Scenario: Без папки проекта
- **WHEN** проект не выбран и сессий нет
- **THEN** страница показывает `skills-no-folder`, разделов навыков и шаблонов нет, загрузчик не вызывался

#### Scenario: Битый конфиг
- **WHEN** `$CODELAB_HOME/config.yaml` не разбирается
- **THEN** страница показывает `skills-unreadable` с проблемой загрузчика, выключателей нет, файлы навыков не читались

#### Scenario: Смена профиля перечитывает страницу
- **WHEN** страница открыта со встроенным агентом, а окно переподключается к WebSocket-профилю
- **THEN** страница переходит в состояние только для чтения, результат прежней загрузки, пришедший позже, не применяется

### Requirement: Страница «Skills & extensions»: контекстные файлы и шаблоны
Раздел «Context files» SHALL показывать цепочку файлов инструкций, которую агент добавит в системный промпт сессии этой папки: файлы в порядке агента (пользовательский `$CODELAB_HOME/AGENTS.md`, затем от корня репозитория к папке), путь, размер файла и итог `<n> files · <size>`. Файл, который ядро усечёт или опустит по бюджету `tools.project_context.max_bytes`, SHALL иметь пометку `truncated to <size>` или `not included (budget)`; бюджет считает функция ядра, а не app. `CLAUDE.md`, использованный на уровне без `AGENTS.md`, SHALL иметь пометку `used because this folder has no AGENTS.md` (E-01; решение Q6 (а) design.md). Без файлов раздел SHALL показывать `No AGENTS.md files for this folder.`

Раздел «Prompt templates» SHALL показывать шаблоны команд, которые агент объявит сессии этой папки: команду `/<name>` с подсказкой аргументов, описание и файл-источник. Шаблон проекта, заменивший шаблон пользователя с тем же именем, SHALL показываться один раз, как у агента. Без шаблонов раздел SHALL показывать `No prompt templates.`

Оба раздела SHALL быть только для чтения. Тексты файлов НЕ SHALL показываться на странице и попадать в состояние Cubit и журнал. Исключение — описание шаблона без `description` во frontmatter: им SHALL служить первая строка тела, как в `available_commands_update` агента; она показывается как недоверенный текст и НЕ SHALL попадать в журнал. Разделы Hooks, Plugins, System prompt override и Read context files of other agents артборда НЕ SHALL показываться (design.md, D13).

#### Scenario: Цепочка от внешнего к ближнему
- **WHEN** `/repo` — корень git, есть `/repo/AGENTS.md` (4,8 КБ) и `/repo/packages/ui/AGENTS.md` (1,3 КБ), папка — `/repo/packages/ui`
- **THEN** раздел показывает две строки в порядке `AGENTS.md`, `packages/ui/AGENTS.md`, итог `2 files · 6.1 KB`, пометок усечения нет

#### Scenario: CLAUDE.md вместо AGENTS.md
- **WHEN** на уровне `/repo/packages/ui` нет `AGENTS.md`, но есть `CLAUDE.md`
- **THEN** строка показывает `packages/ui/CLAUDE.md` с пометкой `used because this folder has no AGENTS.md`

#### Scenario: Бюджет контекста
- **WHEN** `tools.project_context.max_bytes: 4096`, а суммарный размер файлов цепочки 6 КБ
- **THEN** строки, которые ядро усекает или опускает, имеют пометки `truncated to <size>` или `not included (budget)`, совпадающие с результатом `assembleProjectContext`

#### Scenario: Шаблоны проекта и пользователя
- **WHEN** доверенный проект содержит `.codelab/prompts/review-pr.md` с `argument-hint: <number>`, а `$CODELAB_HOME/prompts/` — `review-pr.md` и `explain.md`
- **THEN** раздел показывает `/review-pr <number>` с источником `.codelab/prompts/review-pr.md` и `/explain` с источником в `$CODELAB_HOME/prompts`; второй строки `/review-pr` нет

#### Scenario: Текст файла не утекает
- **WHEN** `AGENTS.md` и тело шаблона содержат маркер `sk-test-leak-0123456789`
- **THEN** ни страница, ни состояние Cubit, ни журнал не содержат маркера

### Requirement: Страница «Skills & extensions»: навыки
Раздел «Skills» SHALL показывать навыки, которые агент загрузит в сессию этой папки, по правилам агента (корни, доверие, перекрытие, мягкая проверка, `skills.disabled`, `skills.max_skills`; spec agent-skills change `add-agent-skills`), и навыки, выключенные `skills.disabled`. Таблица (ключ строки `skills-row-<name>`) SHALL содержать:
- имя и описание;
- «Invoke as» — `/skill:<name>` и `argument-hint`, если есть; для навыка с `user-invocable: false` — `Model only`;
- «Source» — корень навыка: путь от папки проекта для корней проекта; для корней пользователя — путь с `~` вместо домашнего каталога (`~/.codelab/skills` при `CODELAB_HOME` по умолчанию, `~/.agents/skills`), вне домашнего каталога — абсолютный; элемент `skills.extra_roots` как записан с пометкой `(extra root)`;
- выключатель «Enabled» (ключ `skills-toggle-<name>`);
- тег `Overrides <user|project|extra> skill` (или `Overrides another skill` для того же уровня), если навык перекрыл одноимённый навык другого корня;
- тег `Command only` — навык вызывается командой, но модели недоступен (`disable-model-invocation: true` или запрет `skill:<name>` правилами разрешений);
- тег `<n> warning(s)` — предупреждения загрузки этого навыка с текстами в подсказке.

Ошибки и предупреждения, не относящиеся к показанному навыку (пропущенный навык, корень вне области, перекрытый навык, предел числа навыков), SHALL показываться InfoBar `skills-warnings` уровня `warning` с числом и фиксированными текстами диагностик агента и путями. Диагностики уровня `info` НЕ SHALL показываться, как в `config check`.

Под таблицей SHALL быть подпись порядка поиска по фактическим корням: `.codelab/skills`, затем `.agents/skills` от этой папки до корня репозитория; затем `$CODELAB_HOME/skills`, `~/.agents/skills`; extra roots — последними; ближний перекрывает дальний; `The list is fixed when a session opens: new and changed skills apply to new sessions.`

Если `skills.enabled: false` в конфигурации папки, раздел SHALL показывать `Skills are switched off: skills.enabled is false in <файл>.` и не читать навыки. Если навыки не прочитаны за 5 с или чтение завершилось исключением, раздел SHALL показывать `Skills were not read within 5 s.` или `Skills could not be read (<имя типа>).`, остальные разделы SHALL показываться.

Тексты из файлов навыков (имя, описание, подсказка аргументов) SHALL показываться как простой текст с видимыми управляющими, невидимыми и bidi-символами, без markdown и ссылок. Тело `SKILL.md` НЕ SHALL показываться и попадать в состояние Cubit и журнал.

#### Scenario: Перекрытие навыка пользователя
- **WHEN** доверенный проект содержит `.codelab/skills/release-notes/SKILL.md`, а `~/.agents/skills/release-notes/SKILL.md` — навык с тем же именем
- **THEN** одна строка `release-notes` с источником `.codelab/skills` и тегом `Overrides user skill`; InfoBar `skills-warnings` называет перекрытый `~/.agents/skills/release-notes/SKILL.md`

#### Scenario: Навык только для команды
- **WHEN** у навыка `deploy-check` в frontmatter `disable-model-invocation: true`
- **THEN** строка имеет тег `Command only` и «Invoke as» `/skill:deploy-check`

#### Scenario: Предупреждение загрузки
- **WHEN** у навыка в каталоге `pdf-tools` поле `name: pdf_tools` не совпадает с именем каталога
- **THEN** строка `pdf_tools` загружена и имеет тег `1 warning` с текстом `the skill name differs from its directory name; the name from the frontmatter is used`

#### Scenario: Выключенный навык виден
- **WHEN** `skills.disabled: [flutter-golden]` в `$CODELAB_HOME/config.yaml`, а навык `flutter-golden` есть в `.codelab/skills` доверенного проекта
- **THEN** строка `flutter-golden` показана с выключенным «Enabled», тега `Command only` нет

#### Scenario: Навыки выключены конфигом
- **WHEN** `skills.enabled: false` в `.codelab/config.local.yaml` доверенного проекта
- **THEN** раздел показывает `Skills are switched off: skills.enabled is false in .codelab/config.local.yaml.`, таблицы нет, остальные разделы показаны

#### Scenario: Невидимые символы в описании
- **WHEN** описание навыка содержит `U+202E`
- **THEN** ячейка показывает символ видимой escape-последовательностью, а не применяет его

#### Scenario: Тело навыка не утекает
- **WHEN** тело `SKILL.md` содержит маркер `sk-test-leak-0123456789`
- **THEN** ни страница, ни состояние Cubit, ни журнал не содержат маркера

### Requirement: Страница «Skills & extensions»: запись и применение
Выключатель «Enabled» SHALL писать `skills.disabled`, а переключатель согласия на каталог навыков другого агента (ключ `skills-consent-<kind>`) — `skills.extra_roots` по правилам моста (spec client-agent-setup «Правила записи skills.disabled и skills.extra_roots») через `AgentConfigStore.apply`. Других ключей страница НЕ SHALL писать.

Переключатели согласия SHALL показываться для каталогов фиксированного списка — `.claude/skills` в папке проекта и `~/.claude/skills` (решение Q3 (а) design.md), — только если каталог существует. Подпись SHALL называть число найденных подкаталогов навыков и область действия согласия (`in every trusted project` для относительного элемента в слое `user`), а также говорить, что `.agents/skills` доверенного проекта читается без отдельного согласия.

Если запись не может подействовать, элемент SHALL быть неактивен с подсказкой причины: `Set in <файл>; edit that file.`, `Disabled by the project config (<файл>).`, `Trust this project to read .claude/skills.`.

Пока идёт запись, повторные действия SHALL игнорироваться. `ConfigConflict` SHALL давать баннер `skills-banner` и перечитывание без автоповтора (SETUP-6); `ConfigRejected` — баннер с проблемами загрузчика, файл не изменён. После `ConfigSaved` страница SHALL перечитываться и показывать баннер `Saved. New sessions use it; open sessions keep their skills.`; подсказки «Restart agent» нет (design.md, D9).

«Reload» (ключ `skills-reload`) SHALL перечитывать конфиг и файлы. Агенту «Reload» НЕ SHALL отправлять команд.

#### Scenario: Выключение навыка
- **WHEN** `skills.disabled` нигде не задан, и пользователь выключает «Enabled» у `code-review`
- **THEN** `$CODELAB_HOME/config.yaml` содержит `skills.disabled: [code-review]`, страница показывает строку выключенной и баннер `Saved. New sessions use it; open sessions keep their skills.`, идущая сессия не получает запросов

#### Scenario: Список задан в config.local.yaml
- **WHEN** `skills.disabled: [a]` задан в `.codelab/config.local.yaml` доверенного проекта, и пользователь выключает `b`
- **THEN** `.codelab/config.local.yaml` содержит `skills.disabled: [a, b]`, `$CODELAB_HOME/config.yaml` не изменён

#### Scenario: Ключ в файле --config
- **WHEN** stdio-профиль запускает `codelab-agent serve --stdio --config /etc/team.yaml`, а `skills.disabled` задан в `/etc/team.yaml`
- **THEN** выключатели неактивны с подсказкой `Set in /etc/team.yaml; edit that file.`, запись не выполняется

#### Scenario: Выключено недоверенным проектом
- **WHEN** `.codelab/config.yaml` недоверенного проекта задаёт `skills.disabled: [notes]`, а `notes` — навык пользователя
- **THEN** выключатель `notes` неактивен с подсказкой `Disabled by the project config (.codelab/config.yaml).`

#### Scenario: Согласие на .claude/skills
- **WHEN** доверенный проект содержит `.claude/skills/` с тремя каталогами навыков, `skills.extra_roots` нигде не задан, и пользователь включает переключатель согласия
- **THEN** `$CODELAB_HOME/config.yaml` содержит `skills.extra_roots: [.claude/skills]`, после перечитывания три навыка показаны с источником `.claude/skills (extra root)`, `.codelab/config.yaml` не изменён

#### Scenario: Согласие в недоверенном проекте
- **WHEN** проект недоверенный и содержит `.claude/skills/`
- **THEN** переключатель согласия неактивен с подсказкой `Trust this project to read .claude/skills.`

#### Scenario: Конфликт записи
- **WHEN** между открытием страницы и выключением навыка CLI меняет `$CODELAB_HOME/config.yaml`
- **THEN** страница показывает баннер `skills-banner` о конфликте и перечитывает снимок, правка CLI в файле сохранена, повторной записи нет

#### Scenario: Двойное нажатие
- **WHEN** пользователь дважды быстро переключает «Enabled» одного навыка во время записи
- **THEN** выполняется одна запись

### Requirement: Страница «Skills & extensions»: открытие папок
«Open .codelab folder» (ключ `skills-open-codelab`) SHALL открывать в файловом менеджере ОС `<папка проекта>/.codelab`, если каталог существует, иначе `$CODELAB_HOME` профиля; подсказка кнопки SHALL называть путь (решение Q4 (а) design.md). «Open» строки файла контекста, навыка или шаблона SHALL открывать каталог, где лежит файл (решение Q5 (а)). Путь SHALL браться только из показанных страницей данных.

Открытие SHALL идти через порт платформы app, принимающий только абсолютный путь существующего каталога. Файлы НЕ SHALL открываться и запускаться. Отказ платформы SHALL давать баннер `Could not open <путь>.` и событие без пути.

#### Scenario: Открытие папки проекта
- **WHEN** в папке проекта есть `.codelab/`, и пользователь нажимает «Open .codelab folder»
- **THEN** порт получает абсолютный путь `<папка проекта>/.codelab`

#### Scenario: Open строки навыка
- **WHEN** пользователь нажимает «Open» у навыка из `~/.agents/skills/pdf-tools/SKILL.md`
- **THEN** порт получает каталог `~/.agents/skills/pdf-tools` в абсолютной форме, а не путь `SKILL.md`

#### Scenario: Отказ платформы
- **WHEN** порт возвращает `failed`
- **THEN** страница показывает `Could not open <путь>.`, журнал содержит `skills_settings.open_failed` без пути

### Requirement: События журнала страницы Skills & extensions
Страница SHALL писать в журнал логгера `codelab_desktop.settings` события `skills_settings.loaded`, `skills_settings.read_only`, `skills_settings.unreadable`, `skills_settings.phase_failed`, `skills_settings.skill_toggled`, `skills_settings.root_consent`, `skills_settings.save_failed`, `skills_settings.load_discarded`, `skills_settings.open_failed` с видами, числами, именем навыка и слоем записи (design.md change `add-app-skills-page`, D10).

События НЕ SHALL содержать путей, описаний и тел навыков, текстов `AGENTS.md` и шаблонов, текстов диагностик и `toString()` исключений (только имя типа).

#### Scenario: События без содержимого
- **WHEN** пользователь открывает страницу, выключает навык `code-review`, а тело навыка и `AGENTS.md` содержат маркер `sk-test-leak-0123456789`
- **THEN** журнал содержит `skills_settings.loaded` с числами и `skills_settings.skill_toggled` с `name: code-review` и `layer: user`, и не содержит маркера и путей файлов
