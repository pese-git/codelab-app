## MODIFIED Requirements

### Requirement: Промпты в Markdown и генерация констант
Тексты промптов, которые видит модель, SHALL лежать файлами `packages/dart/codelab_agent_core/prompts/**/*.md`. У каждого файла есть frontmatter с ключами `id`, `description`, `vars` и необязательным `tools`.

Генератор `tool/gen_prompts.dart` SHALL компилировать файлы в один файл `lib/src/prompts/prompts.g.dart` по алгоритму §11.3 документа ядра:
- файлы обрабатываются в порядке относительного пути;
- `id` совпадает с путём;
- имя константы — путь в lowerCamelCase;
- результат форматируется `DartFormatter`;
- режим `--check` сравнивает результат с файлом на диске.

Генератор SHALL завершаться ошибкой с путём файла в случаях:
- нет frontmatter;
- неизвестный ключ frontmatter;
- подстановка не объявлена в `vars` или объявлена, но не используется;
- дубликат `id`;
- файл под `tools/` без непустого `tools`.

Сгенерированный файл SHALL соответствовать исходникам (PR-1). В `lib/` ядра вне `prompts.g.dart` НЕ SHALL быть многострочных строковых литералов промптов (PR-2).

Тексты SHALL быть английскими, написанными для CodeLab (`AGENTS.md` §5); тексты, промпты и описания инструментов сторонних агентов, в том числе Claude Code, НЕ SHALL воспроизводиться (§7а `07-decision-sources.md`). Файлы:
- `system/base.md`, `system/untrusted.md`, `modes/plan.md`;
- `tools/read.md`, `tools/edit.md`, `tools/listing.md`, `tools/exec.md`, `tools/tasks.md` (`tools: [task_create]`; заменяет `tools/plan.md`, change `add-subagents-and-tasks`);
- `tool_descriptions/<tool>.md` для встроенных инструментов `read`, `write`, `edit`, `ls`, `search`, `exec`, `task_create`, `task_update`, `task_list`, `task_get`, `agent`; файла для `update_plan` нет;
- `subagent/system.md`, `subagent/task.md` (переменные `id`, `subject`) и `subagent/types/<name>.md` для `general`, `explore`, `review`, `plan` (§17.3.3, §17.16.4).

#### Scenario: Синхронизация с исходниками
- **WHEN** тест генерирует файл в памяти
- **THEN** результат побайтово равен `lib/src/prompts/prompts.g.dart` (`prompts_sync_test.dart`)

#### Scenario: Ошибки генератора
- **WHEN** генератор получает файл с неизвестной подстановкой, файл с необъявленной переменной, файл с ключом `author` и два файла с одним `id`
- **THEN** каждый случай даёт ошибку, называющую путь файла

#### Scenario: Описание agent по глубине
- **WHEN** описание `agent` рендерится для корневой сессии при `max_depth: 3` и для ребёнка глубины 2 при том же `max_depth`
- **THEN** первое содержит `A subagent may start its own subagents, up to 2 more level(s) below it.`, второе — `Subagents you start cannot start other subagents.`; оба рендеринга детерминированы (итерация 4)

#### Scenario: Описание agent до вложенности
- **WHEN** до итерации 4 change (ребёнку `agent` не даётся) описание `agent` рендерится для корневой сессии при `max_depth: 3`
- **THEN** `nesting` строится от эффективной глубины 1 и даёт `Subagents you start cannot start other subagents.`: описание не обещает модели вложенности, которой нет (design.md, D36, Т16)

### Requirement: Детерминированная сборка системного промпта
`composeSystemPrompt(PromptInputs)` SHALL собирать секции в фиксированном порядке §11.5 документа ядра и соединять их через пустую строку:
1. `system/base` с `cwd`, датой `yyyy-MM-dd`, платформой и именем режима.
2. `system/untrusted`.
3. `modes/plan` в режиме `plan`.
4. `tools/read`.
5. `tools/edit`.
6. `tools/listing` при `fileListing`.
7. `tools/exec` при `shellExec`.
8. `tools/tasks` — если в наборе есть `task_create` (у потомков её нет: детский вариант без `task_create`).
9. `mcp` — по требованию «Секция mcp».
9a. `skills/catalog` — если capability `skills` включена и в снимке каталога сессии есть навыки, видимые модели (change `add-agent-skills`, D6); у потомка — тот же снимок, что у родителя, и только если `skill` в наборе потомка (PR-6; design.md change `add-subagents-and-tasks`, D34).
10. `project_context` — если `PromptInputs.projectContext` содержит хотя бы один файл (design.md change `add-agent-project-files`, D5).
11. `agent_profile` — если у сессии выбран агент (D11).
12. `subagent/system` — только у потомка (design.md change `add-subagents-and-tasks`, D16).
13. профиль типа субагента `## Agent profile: <name>` — только у потомка, тело — `subagent/types/<name>.md` или тело пользовательского определения.
14. `subagent/task` — только у потомка с назначенным пунктом списка задач.

`PromptInputs` SHALL получить поля `projectContext` (`ProjectContext?`, результат `assembleProjectContext`), `agentProfile` (имя и тело выбранного определения или `null`) и `subagent` (тип, тело и назначенный пункт потомка или `null`); поле `skills` (навыки `modelVisible` снимка каталога, change `add-agent-skills`) у потомка берётся из снимка родителя (D34). Тексты `project_context.md`, `project_context_file.md`, `agent_profile.md` и файлы `subagent/` SHALL лежать в `prompts/` и генерироваться в `prompts.g.dart` (PR-1, PR-2).

Одинаковые входы SHALL давать побайтово одинаковый результат; секций выключенных capability в нём нет (PR-3, HOST-4).

Секция с непустым `tools` SHALL входить в промпт, только если включены все её инструменты (PR-6). База и секции без `tools` НЕ SHALL называть ни одного инструмента по имени, которое не совпадает с обычным английским словом. Секция `tools/tasks` SHALL называть только `task_create`; правила `task_update`, `task_list`, `task_get` — в их описаниях, правило «после сжатия узнай состояние списка вызовом `task_list`» — в `tool_descriptions/task_list.md` (design.md change `add-subagents-and-tasks`, D32).

#### Scenario: Golden на профиль и режим
- **WHEN** промпт собирается для профилей `agent-serve` и `embedded-cli` в режимах `standard` и `plan` с фиксированной датой
- **THEN** результат совпадает с `test/prompts/golden/<profile>-<mode>.txt`, где вместо `tools/plan` стоит `tools/tasks`

#### Scenario: Секция выключенного инструмента
- **WHEN** набор инструментов сессии не содержит `ls`, а затем не содержит `write` и `edit`
- **THEN** в первом промпте нет `tools/listing`, во втором есть `tools/read` и нет `tools/edit`

#### Scenario: Секция списка задач называет только якорь
- **WHEN** тест-сторож проверяет `tools/tasks.md` и `tool_descriptions/task_list.md`
- **THEN** в `tools/tasks.md` нет `task_update`, `task_list`, `task_get`; описание `task_list` содержит правило о вызове после сжатия контекста (`prompt_sections_tools_test.dart`)

#### Scenario: База не называет инструментов
- **WHEN** тест-сторож проверяет `system/base.md`, `system/untrusted.md`, `project_context.md`, `project_context_file.md`, `agent_profile.md` и `subagent/system.md`
- **THEN** в них нет слов `exec`, `ls`, `update_plan`, `task_create` и подстроки `mcp__`

#### Scenario: Контекст проекта без профиля
- **WHEN** промпт собирается с двумя файлами контекста без выбранного агента
- **THEN** последняя секция — `# Project instructions` с двумя блоками `<project-instructions>` в порядке от общего к частному, секции профиля нет; результат совпадает с `test/prompts/golden/agent-serve-standard-project.txt`

#### Scenario: Контекст проекта и профиль агента
- **WHEN** промпт собирается с теми же двумя файлами контекста и выбранным агентом `reviewer`
- **THEN** последние две секции — `# Project instructions` и `# Agent profile: reviewer`; результат совпадает с `test/prompts/golden/agent-serve-standard-project-agent.txt`, а без последней секции — с `agent-serve-standard-project.txt`

#### Scenario: Промпт ребёнка
- **WHEN** промпт собирается для ребёнка `explore` с назначенным пунктом `#2` в режиме `plan`
- **THEN** после секций базы идут `subagent/system`, `## Agent profile: explore` и строка `Your task: #2 …`; секции `tools/tasks` нет; результат совпадает с `test/prompts/golden/subagent-explore-plan.txt`

#### Scenario: Промпт ребёнка с навыками
- **WHEN** промпт собирается для ребёнка `general` в режиме `standard`, а у родителя навыки `flutter-golden` и `release-notes`
- **THEN** секция `## Skills` стоит после `mcp` и до `project_context`, её текст побайтово равен секции родителя, за ней идут `subagent/system` и `## Agent profile: general`; результат совпадает с `test/prompts/golden/subagent-general-skills.txt` (задача 2s.1)
