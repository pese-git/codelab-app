## MODIFIED Requirements

### Requirement: Детерминированная сборка системного промпта
`composeSystemPrompt(PromptInputs)` SHALL собирать секции в фиксированном порядке §11.5 документа ядра и соединять их через пустую строку:
1. `system/base` с `cwd`, датой `yyyy-MM-dd`, платформой и именем режима.
2. `system/untrusted`.
3. `modes/plan` в режиме `plan`.
4. `tools/read`.
5. `tools/edit`.
6. `tools/listing` при `fileListing`.
7. `tools/exec` при `shellExec`.
8. `tools/plan`.
9. `mcp` — по требованию «Секция mcp».
9a. `skills/catalog` — если capability `skills` включена и у сессии есть навыки, видимые модели (capability `agent-skills`, «Секция каталога в системном промпте»; design.md change `add-agent-skills`, D6).
10. `project_context` — если `PromptInputs.projectContext` содержит хотя бы один файл (design.md change `add-agent-project-files`, D5).
11. `agent_profile` — если у сессии выбран агент (D11).

`PromptInputs` SHALL получить поле `skills` (навыки `modelVisible` снимка каталога сессии, по имени; пустой список — секции нет и промпт побайтово прежний) и поля `projectContext` (`ProjectContext?`, результат `assembleProjectContext`) и `agentProfile` (имя и тело выбранного определения или `null`). Тексты `project_context.md`, `project_context_file.md`, `agent_profile.md`, `skills/catalog.md`, `skills/invoked.md`, `skills/reattached.md` и `tool_descriptions/skill.md` SHALL лежать в `prompts/` и генерироваться в `prompts.g.dart` (PR-1, PR-2).

Одинаковые входы SHALL давать побайтово одинаковый результат; секций выключенных capability в нём нет (PR-3, HOST-4).

Секция `skills/catalog` называет инструмент `skill` и потому объявляет `tools: [skill]`; `skills/invoked.md` и `skills/reattached.md` — без `tools` и инструментов не называют. Секция с непустым `tools` SHALL входить в промпт, только если включены все её инструменты (PR-6). База и секции без `tools` НЕ SHALL называть ни одного инструмента по имени, которое не совпадает с обычным английским словом.

#### Scenario: Golden на профиль и режим
- **WHEN** промпт собирается для профилей `agent-serve` и `embedded-cli` в режимах `standard` и `plan` с фиксированной датой
- **THEN** результат совпадает с `test/prompts/golden/<profile>-<mode>.txt`

#### Scenario: Секция выключенного инструмента
- **WHEN** набор инструментов сессии не содержит `ls`, а затем не содержит `write` и `edit`
- **THEN** в первом промпте нет `tools/listing`, во втором есть `tools/read` и нет `tools/edit`

#### Scenario: База не называет инструментов
- **WHEN** тест-сторож проверяет `system/base.md`, `system/untrusted.md`, `project_context.md`, `project_context_file.md`, `agent_profile.md`, `skills/invoked.md` и `skills/reattached.md`
- **THEN** в них нет слов `exec`, `ls`, `update_plan` и подстроки `mcp__`

#### Scenario: Контекст проекта без профиля
- **WHEN** промпт собирается с двумя файлами контекста без выбранного агента
- **THEN** последняя секция — `# Project instructions` с двумя блоками `<project-instructions>` в порядке от общего к частному, секции профиля нет; результат совпадает с `test/prompts/golden/agent-serve-standard-project.txt`

#### Scenario: Контекст проекта и профиль агента
- **WHEN** промпт собирается с теми же двумя файлами контекста и выбранным агентом `reviewer`
- **THEN** последние две секции — `# Project instructions` и `# Agent profile: reviewer`; результат совпадает с `test/prompts/golden/agent-serve-standard-project-agent.txt`, а без последней секции — с `agent-serve-standard-project.txt`

#### Scenario: Каталог навыков между mcp и контекстом проекта
- **WHEN** промпт собирается с сервером MCP с инструментами, двумя навыками и двумя файлами контекста проекта
- **THEN** секция `## Skills` стоит после секции `# MCP servers` и до `# Project instructions`; без навыков результат побайтово равен промпту тех же входов до этого change
