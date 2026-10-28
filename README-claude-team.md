# Команда Claude Code для CodeLab

## Где лежат файлы
Команда хранится в репозитории, отдельно ставить ничего не нужно: после checkout файлы уже на месте.
```
codelab-app/
├── CLAUDE.md          ← таблица зон и команды; правила подключает через @AGENTS.md
└── .claude/
    ├── agents/        ← 8 субагентов
    ├── commands/      ← /change, /implement, /codelab-review, /check и opsx/
    └── skills/        ← openspec-*
```
`AGENTS.md` остаётся единым источником правил для всех AI-агентов; `CLAUDE.md` правила не дублирует, а только подключает их и описывает команду.

В `.gitignore` открыты только `.claude/agents/`, `.claude/commands/` и `.claude/skills/`; остальное в `.claude/` (`settings.local.json`, `worktrees/`, `.DS_Store`) остаётся локальным. Изменение подготовлено в ветке `feature/add-claude-code-team` от `develop` (§22).

Команда ревью называется `/codelab-review`, чтобы не перекрывать встроенную `/review` Claude Code.

### `@AGENTS.md`: компромисс
Часть клиентов Claude Code (например, десктопное приложение) уже сама загружает `AGENTS.md` как инструкции проекта. Тогда импорт `@AGENTS.md` в `CLAUDE.md` загружает те же ~780 строк второй раз: лишние токены, но не противоречие. Импорт оставлен для клиентов, которые читают только `CLAUDE.md`. Если ваш клиент читает `AGENTS.md` сам, строку `@AGENTS.md` можно удалить.

## MCP-серверы (рекомендуется)
Агентам прописаны инструменты двух серверов. Без них агенты работают через Bash/Grep.
- `dart` — официальный Dart MCP (`claude mcp add --scope project dart -- fvm dart mcp-server`).
- `codegraph` — граф кода для поиска и анализа влияния изменений. Если у вас он подключён под другим именем — замените префикс `mcp__codegraph__` в поле `tools`.

## Модели
- `opus` — codelab-architect, architecture-reviewer, acp-safety-reviewer (дизайн, ACP, безопасность).
- `sonnet` — четыре инженера.
- `haiku` — check-runner (только запуск и сводка проверок).
Для сложных изменений ядра или протокола можно поднять модель инженера до `opus` в его файле.

## Использование
```
/change Показывать в композере оставшийся контекст модели
/implement add-integrated-terminal
/codelab-review add-cli-tui
/check guard conformance:agent
```
