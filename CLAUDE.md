# CodeLab — инструкции для Claude Code

Обязательные правила репозитория — в `AGENTS.md` (подключён ниже). Вложенные `AGENTS.md` в пакетах и приложениях уточняют правила своих каталогов: перед изменением кода прочитай ближайший.

@AGENTS.md

## Команда субагентов (`.claude/agents/`)

| Агент | Зона | Пишет код |
|---|---|---|
| `codelab-architect` | OpenSpec changes, `docs/architecture/` | только `openspec/`, `docs/` |
| `acp-protocol-engineer` | `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_acp_testing`, `codelab_agent_acp` | да |
| `agent-core-engineer` | `codelab_agent_core`, `codelab_agent_io`, `apps/codelab_agent` | да |
| `client-engineer` | `codelab_client_acp`, `codelab_client_core`, `codelab_client_io`, `apps/codelab_cli` | да |
| `desktop-engineer` | `apps/codelab_desktop`, `packages/flutter/codelab_ui` | да |
| `check-runner` | проверки затронутого; полный `melos run check` — по просьбе | нет |
| `architecture-reviewer` | спецификации, границы, слои, паттерны, тесты, комментарии | нет |
| `acp-safety-reviewer` | безопасность, ACP, данные, состояние, наблюдаемость (§2, приоритеты 1–5) | нет |

## Команды
- `/change <задача>` — полный цикл: OpenSpec change → одобрение пользователя → реализация по `tasks.md` (TDD) → проверка затронутого (§21) → двойное ревью → исправления.
- `/implement <change-id>` — реализовать или продолжить существующий change.
- `/codelab-review [change-id]` — check + двойное ревью текущей ветки (не путать со встроенной `/review` Claude Code).
- `/check [скрипты]` — прогон проверок; без аргументов — полный `melos run check` (явная просьба пользователя).

## Процесс
- Задача, меняющая поведение, ACP-контракты, public API, persistence, security или архитектуру, начинается с `codelab-architect` (§17). Implementation-only правку можно сделать напрямую, но затем — `/codelab-review`.
- Метки задач в `tasks.md`: `[protocol]`, `[agent]`, `[client]`, `[desktop]` — по ним выбирается исполнитель. Если меток нет (как в существующих changes), оркестратор определяет исполнителя по путям/пакетам задачи и таблице зон выше и показывает пользователю разбиение до старта.
- Красный тест коммитится отдельно до кода (TDD вложенных `AGENTS.md`), но коммит — только по явной просьбе: оркестратор на этой точке спрашивает пользователя, а не коммитит сам.
- Все команды Dart/Flutter — через `fvm` (§20). `test:e2e:app:*` — только в `release/*` (§21).
- Не утверждать, что проверка прошла, если она не запускалась (§21).
- `git commit`, `push`, PR, merge и архивирование change — только по явной просьбе (§19, §22).
