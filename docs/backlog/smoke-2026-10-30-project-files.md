# Backlog: находки smoke-теста файлов проекта 2026-10-30

Ручной smoke-тест сборки `develop` @ `f7ce5ba` (после архивирования change `add-agent-project-files`,
этапы 8.6–8.8). Агент — `codelab-agent serve --stdio`, модель `qwen/qwen3.5-9b` в LM Studio
(`openai-compatible`). `CODELAB_HOME` и тестовые проекты изолированы во временном каталоге: доверенный
проект (`trusted_projects`) с `AGENTS.md`, `.codelab/prompts/review.md` и `.codelab/agents/{reviewer,yolo,bad}.md`,
его недоверенная копия, `$CODELAB_HOME/{AGENTS.md,prompts/hello.md}`. Прогнаны: headless `codelab -p`,
REPL (`/help`, `/config agent …`), `config check` агента и CLI, `serve --ws`, ввод модели (`lms log stream`).

Сценарии 8.6–8.8 прошли по спецификациям `agent-project-context`, `agent-slash-commands`,
`agent-definitions`: `AGENTS.md` от `cwd` до корня git и из `$CODELAB_HOME`, шаблоны в доверенном
проекте и текст как есть в недоверенном, список команд в REPL, пол режима (`agent.mode.not_applied`),
фильтр инструментов и профиль агента в промпте, `config_change agent` в журнале, `project_files.skipped`
по WebSocket, коды `64` для `~user` и `~` без `HOME`.

Приоритеты и колонки — как в [smoke-2026-10-30.md](smoke-2026-10-30.md).

## Сводка

| ID | P | Тип | Область | Кратко | OpenSpec | Issue |
|---|---|---|---|---|---|---|
| SMK-19 | P3 | enhancement | agent | Определения агентов в формате Python-агента дают шум диагностик без подсказки о переносе | да | — |

## Карточки

### SMK-19. Определения агентов в формате Python-агента: шум без подсказки о переносе (P3)

**Где:** `packages/dart/codelab_agent_core/lib/src/agents/agent_definition.dart` (проверка полей,
`unknown frontmatter key`), `packages/dart/codelab_agent_io/lib/src/cli/config_commands.dart` (вывод
`config check`), спецификация `agent-definitions` («Формат определения и проверка»).

**Шаги:** в `$CODELAB_HOME/agents/` лежат определения, оставшиеся от Python codelab-agent
(у пользователя — `architect.md`, `ask.md`, `coder.md`, `debug.md`, `universal.md`; frontmatter с ключами
`role`, `priority`, `permissions`, `model: lmstudio/…`, без `description`) → `codelab-agent config check`
или новая сессия.

**Факт:** каждый файл даёт 4–5 строк `warning:` — по строке на неизвестный ключ («unknown frontmatter
key; allowed: name, description, model, mode, tools, scope»), «"description" is required», «"model" must be
a model of the catalog» — и пропускается. Всего 24 строки на пять файлов; сессия пишет те же диагностики
в лог `project_files.diagnostic`. Что это файлы другого формата и что с ними делать, из вывода не следует.
Для `codelab.toml` агент в той же ситуации печатает одну строку `config.legacy_found` со ссылкой на
таблицу соответствия ключей (§15.7).

**Ожидание:** файл, похожий на определение Python-агента (есть `role`/`priority`/`permissions` и нет
`description`), даёт одну диагностику вроде «looks like a Python codelab-agent definition; it is not used —
rewrite the frontmatter as described in agent-core-architecture §15.8» вместо построчных ошибок;
в §15.8 — таблица соответствия ключей (`permissions` → `tools`/`mode`, `role`/`priority` — не переносятся).
Имя ключа и фрагменты файла в сообщение по-прежнему не попадают (agent-configuration, D3/D10).

**Риск:** нет — файлы не загружаются, поведение fail-closed. Пользователь, перешедший с Python-агента,
видит длинный список ошибок при каждом `config check` и не понимает, что агенты нужно переписать.

**Замечание:** при невалидном глобальном конфиге (например, без `agent.default_model`) `config check`
диагностику файлов проекта не печатает совсем — см. SMK-14
([#184](https://github.com/pese-git/codelab-app/issues/184)).
