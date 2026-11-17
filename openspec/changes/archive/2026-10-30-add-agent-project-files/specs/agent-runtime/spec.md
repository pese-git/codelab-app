## ADDED Requirements

### Requirement: Файлы проекта сессии
`createSession` и `loadSession` SHALL до возврата сессии вызывать `AgentCoreServices.projectFiles.load` (если порт задан) с каноническим `cwd` сессии, признаком `projectTrusted` и `tools.project_context.max_bytes` снимка конфигурации сессии (design.md change `add-agent-project-files`, D1, D4). `projectTrusted` SHALL быть истинным, только если канонический `cwd` равен одному из `CoreConfig.trustedProjects`; канонизация — тем же `PathResolver.realpath`, что выбирает снимок (D9 change `add-agent-configuration`). Если `cwd` не раскрылся (у базового env нет `PathResolver` или `realpath` вернул ошибку), `projectTrusted` SHALL быть ложным (fail-closed, D4): нераскрытый путь не сравнивается с доверенными корнями.

Результат SHALL проверяться ядром:
- `assembleProjectContext` → `PromptInputs.projectContext`;
- `parseCommandTemplates` → `AgentSession.commands`;
- `parseAgentDefinitions` с каталогом моделей сборки → `AgentSession.agents`.

Каждая диагностика SHALL писаться логгером сессии событием `project_files.diagnostic` (`session_id`, `path`, `line`, `column`, `code`, `message`; `warning` для уровней `error` и `warning`, `debug` для `info`), без содержимого файлов. Итоги — `project_context.loaded`, `commands.loaded`, `agents.loaded`.

Загрузка SHALL идти под токеном, дочерним от токена рантайма, и под таймаутом фазы (agent-project-context «Порт файлов проекта», D6): после `dispose()` рантайма результат выбрасывается и сессия не создаётся, по таймауту сессия создаётся без файлов проекта.

`AgentSession` SHALL получить члены `commands`, `agents`, `agent`, `setAgent(String)` (agent-slash-commands, agent-definitions).

#### Scenario: Доверие по cwd сессии
- **WHEN** глобальный конфиг доверяет `/work/b`, хост запущен в `/work/a`, а сессия создаётся с `cwd: /work/b`, где есть `.codelab/prompts/review.md`
- **THEN** фейковый порт получает `projectTrusted: true`, у сессии есть команда `review`

#### Scenario: Symlink на доверенный корень
- **WHEN** `/work/link` — symlink на доверенный `/work/b`, а сессия создаётся с `cwd: /work/link`
- **THEN** порт получает канонический `cwd: /work/b` и `projectTrusted: true`

#### Scenario: cwd не раскрылся
- **WHEN** глобальный конфиг доверяет `/work/b`, а `realpath` базового env для `cwd: /work/b` возвращает ошибку
- **THEN** фейковый порт получает `projectTrusted: false`

#### Scenario: Диагностика без содержимого
- **WHEN** порт возвращает определение агента с ошибкой frontmatter, а тело файла содержит строку `sk-test-secret`
- **THEN** лог содержит `project_files.diagnostic` с путём и кодом и не содержит `sk-test-secret`

### Requirement: Очередь смен конфигурации сессии
`AgentSession.setMode`, `setModel`, `setEffort` и `setAgent` SHALL исполняться строго по одной в порядке вызова (очередь сессии; design.md change `add-agent-project-files`, D11). Новое значение (база агента, пол режима, итоговые режим и модель) SHALL вычисляться под очередью — от состояния после предыдущей смены, а не в момент вызова. Записи журнала и события `ModeChanged` SHALL идти в порядке очереди; итоговое состояние сессии SHALL быть результатом последнего вызова. Ошибка одного вызова (`ArgumentError`) НЕ SHALL останавливать очередь. Правило применения смены к идущему ходу у каждого метода прежнее: `setMode` — со следующего вызова инструмента, `setModel`, `setEffort` и `setAgent` (включая режим агента) — со следующего шага.

#### Scenario: Параллельные setAgent и setMode
- **WHEN** режим конфигурации `standard`, определение `reviewer` задаёт `mode: plan`, а хост без ожидания вызывает `setAgent('reviewer')` и сразу `setMode(bypass)`
- **THEN** события `ModeChanged` идут в порядке `plan`, `bypass`; журнал содержит `config_change {optionId: "agent", value: "reviewer"}` и `mode_change plan` раньше `mode_change bypass`; итог — `agent == "reviewer"`, режим `bypass`

#### Scenario: Ошибка не ломает очередь
- **WHEN** без ожидания вызываются `setAgent('missing')` и `setMode(plan)`
- **THEN** первый завершается `ArgumentError`, второй исполняется, режим `plan`
