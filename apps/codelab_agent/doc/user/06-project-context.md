# Контекст проекта

Агент не знает вашего проекта, пока вы ему не расскажете. Для этого есть четыре вида файлов, которые он читает при открытии сессии: инструкции (`AGENTS.md`), шаблоны команд, определения агентов и навыки. После этой главы вы сможете записать правила проекта так, чтобы агент следовал им в каждой сессии.

В app эти файлы показывает страница настроек «Skills & extensions» — [руководство app](../../../codelab_desktop/doc/user/08-agent-extensions.md#навыки-файлы-контекста-и-шаблоны).

## Откуда агент их читает

| Что | Где лежит | Для чего |
|---|---|---|
| Инструкции | `AGENTS.md` (или `CLAUDE.md`) в папке проекта и выше; `$CODELAB_HOME/AGENTS.md` | правила и сведения о проекте, которые попадают в каждую сессию |
| Шаблоны команд | `.codelab/prompts/*.md`; `$CODELAB_HOME/prompts/*.md` | свои слэш-команды: заготовка запроса с аргументами |
| Определения агентов | `.codelab/agents/*.md`; `$CODELAB_HOME/agents/*.md` | профиль: роль, модель, режим, набор инструментов |
| Навыки | `.codelab/skills/<имя>/SKILL.md` и другие корни | инструкции, которые агент подгружает по необходимости |

`$CODELAB_HOME` — каталог настроек, по умолчанию `~/.codelab` ([где лежит](../../../../docs/ops/codelab-home.md#где-лежит-каталог)).

Агент читает файлы один раз, когда сессия создаётся или открывается заново. После правки файла откройте новую сессию.

Что именно загрузилось, видно в stderr агента. Реальный запуск `serve --stdio` на демонстрационном проекте с одним файлом каждого вида:

```text
info skills.loaded {session_id: <session-id>, count: 1, names: [release-notes], project: true}
info project_context.loaded {session_id: <session-id>, files: [AGENTS.md], bytes: 64, truncated: 0, omitted: 0, root: git}
info commands.loaded {session_id: <session-id>, count: 1, project: true}
info agents.loaded {session_id: <session-id>, names: [reviewer]}
```

(Время в начале каждой строки опущено.)

## Доверие к проекту

Папку проекта часто приносит репозиторий, поэтому ему доверяют не полностью. Каталог `.codelab/` проекта влияет на то, что агент выполняет, поэтому агент читает шаблоны команд, определения агентов и навыки проекта только если вы разрешили проект в глобальном файле `~/.codelab/config.yaml`:

```bash
codelab-agent config set trusted_projects '["/home/user/projects/demo"]'
```

Значение — JSON-список абсолютных путей к папкам проектов. После правки перезапустите агента (`note: restart the agent to apply: trusted_projects`). Ключ читается только из глобального файла: репозиторий не может объявить себя доверенным.

Если проект не доверенный, `codelab-agent config check` называет, что пропущено:

```text
note: ~/projects/demo/.codelab/prompts: the project is not trusted; add it to trusted_projects
note: ~/projects/demo/.codelab/agents: the project is not trusted; add it to trusted_projects
note: ~/projects/demo/.codelab/skills: the project is not trusted; add it to trusted_projects
```

Инструкции `AGENTS.md` читаются всегда. Что ещё зависит от доверия (провайдеры, MCP-серверы проекта), — [слои конфигурации](../../../../docs/user/configuration.md#слои-конфигурации).

## Инструкции: `AGENTS.md`

`AGENTS.md` — обычный файл Markdown: как собрать проект, как запускать тесты, что нельзя менять. Агент добавляет его текст в начало каждой сессии.

Как агент ищет файлы:

1. `$CODELAB_HOME/AGENTS.md` — ваши личные правила для всех проектов.
2. Затем от корня репозитория git до рабочей папки: на каждом уровне — `AGENTS.md`, а если его нет, то `CLAUDE.md`. Если на одном уровне есть оба, читается `AGENTS.md`, а `CLAUDE.md` пропускается.
3. Корень репозитория определяется по каталогу или файлу `.git`. Не нашли репозиторий — читается только рабочая папка.

Объём ограничен ключом `tools.project_context.max_bytes` (по умолчанию 32 768 байт; `0` — не читать инструкции). Лимит расходуется от самого частного файла (ближайшего к рабочей папке) к общему. Если файл не влез, его хвост обрезается по границе строки с пометкой `[file truncated: showing N of M bytes]`, а не вошедшие файлы пропускаются. Недоверенный проект может только уменьшить лимит.

Режим и правила разрешений от `AGENTS.md` не зависят: что агенту можно, решает [политика разрешений](05-permissions.md), а не текст файла.

## Шаблоны команд

Шаблон — файл `<имя>.md` в каталоге `prompts/`. Он превращается в слэш-команду `/<имя>`.

`.codelab/prompts/review.md`:

```markdown
---
description: Review the changes of a branch
argument-hint: <branch>
---
Review the changes in branch $1 and list the defects.
```

Команда `/review feature-x` отправит модели текст с подставленным `feature-x` вместо `$1`. Клиент показывает команду в списке команд агента с описанием и подсказкой аргумента.

- `description` и `argument-hint` — необязательные поля вверху файла.
- Имя команды — имя файла без `.md`: строчные буквы, цифры и `-`, до 64 знаков.
- В тексте доступны `$ARGUMENTS` (вся строка аргументов) и `$1`…`$9` (слова с учётом кавычек).
- Команда проекта заменяет одноимённую команду из `$CODELAB_HOME/prompts`.
- Имена встроенных команд (`compact`, `mode`, `model`, `status`, `usage`, `config`, `mcp`, `help`) и слово `skill` занять нельзя.
- Шаблон проекта читается только из доверенного проекта.

### Встроенные команды агента

Команды, которые агент выполняет сам, без модели:

| Команда | Что делает |
|---|---|
| `/compact [фокус]` | сжимает историю сессии — [глава о сессиях](09-sessions.md#сжатие-контекста) |
| `/mode <режим>` | меняет режим разрешений |
| `/model <провайдер/модель>` | меняет модель |
| `/status` | показывает модель, режим, рабочую папку и MCP-серверы |
| `/usage [rebuild]` | показывает расход токенов и стоимость сессии |
| `/config reload` или `/config check` | перечитывает или проверяет конфигурацию агента |
| `/mcp list`, `reload`, `enable <имя>`, `disable <имя>` | управляет MCP-серверами — [глава о MCP](08-mcp.md) |
| `/help` | перечисляет команды |

Список с вашими шаблонами и навыками агент печатает на `/help`. Реальный ответ в демонстрационном проекте из этой главы:

```text
> /help
Commands:
/compact [focus] - Compact the session history
/mode plan | ask | standard | accept-edits | bypass - Switch the session mode
/model provider/model - Switch the model
/status - Show the model, mode, working directory and MCP servers
/usage [rebuild] - Show token usage and cost of the session
/config reload | check - Reload or check the agent config
/mcp list | reload [<id>] | enable <id> | disable <id> - List, reload, enable or disable MCP servers
/help - List commands
/review <branch> - Review the changes of a branch (template)
/skill:release-notes arguments - Use when the user asks for release notes (skill)
```

Команды `/config` и `/mcp` не работают у агента, запущенного как `serve --ws`. Клиент может перекрыть команду агента своей: в `codelab` она тогда доступна с префиксом `agent:` — например, `/agent:help`.

## Определения агентов

Определение агента — файл `<имя>.md` в каталоге `agents/` — задаёт профиль: роль, модель, режим и набор инструментов. Выбрать его можно в клиенте среди вариантов опции «Agent»; тот же файл может служить типом субагента.

`.codelab/agents/reviewer.md`:

```markdown
---
name: reviewer
description: Reads code and reports problems
mode: plan
tools: [read, ls, search]
scope: both
---
You are a careful reviewer.
```

Поля:

| Поле | Значение |
|---|---|
| `name` | обязательно; строчные латинские буквы, цифры и `-`, начинается с буквы, до 48 знаков; не `default` |
| `description` | обязательно; 1–200 символов; показывается в списке |
| `model` | необязательно; `<провайдер>/<модель>` из вашего каталога моделей |
| `mode` | необязательно; один из режимов разрешений |
| `tools` | необязательно; список разрешённых инструментов, `*` в конце имени — префикс (`mcp__files__*`); без поля доступны все, пустой список — ни одного |
| `scope` | `session` (профиль сессии), `subagent` (тип субагента) или `both` (по умолчанию) |

Текст после заголовка попадает в системный промпт агента. Агент только сужает возможности: список `tools` убирает инструменты, а режим из определения не может быть мягче режима вашей конфигурации. Разрешения проверяются как обычно.

В сессии с этим проектом агент предлагает опцию «Agent» с вариантами `default` и `reviewer`. Определение с ошибкой агент пропускает и пишет причину; остальные работают.

## Навыки

Навык — каталог с файлом `SKILL.md`: инструкция для задач определённого вида («как готовить заметки к релизу»). Агент показывает модели только имя и описание навыка, а полный текст подгружает, когда задача подходит.

`.codelab/skills/release-notes/SKILL.md`:

```markdown
---
name: release-notes
description: Use when the user asks for release notes
---
Collect the merged changes and write release notes.
```

- `description` обязательно: навык без описания агент пропускает. Если нет `name`, берётся имя каталога.
- Модель подгружает навык инструментом `skill`. Вы вызываете его командой `/skill:<имя>`. Поле `disable-model-invocation: true` скрывает навык от модели и оставляет только команду.
- Рядом с `SKILL.md` могут лежать файлы навыка (скрипты, шаблоны): агент перечисляет их, а читает по просьбе инструкции.

Где агент ищет навыки — от более важного к менее важному:

1. `.codelab/skills` и `.agents/skills` в папке проекта и выше, до корня репозитория (только доверенный проект).
2. `$CODELAB_HOME/skills`.
3. `~/.agents/skills`.
4. Каталоги из ключа `skills.extra_roots`.

Настройки навыков:

| Ключ | Что делает |
|---|---|
| `skills.enabled` | `false` выключает навыки в этой папке |
| `skills.disabled` | список имён навыков, которые агент не загружает |
| `skills.extra_roots` | дополнительные каталоги навыков, например `~/.claude/skills`; согласие читать каталог вне проекта даёте вы — только в глобальном файле или в `config.local.yaml` доверенного проекта |

Пределы и остальные ключи навыков — в [настройке агента](../../../../docs/user/configuration.md#навыки).

В режиме `serve --ws` навыки, как и остальные файлы проекта, не читаются.

## Смотрите также

- [Разрешения](05-permissions.md)
- [Субагенты и список задач](07-subagents-and-tasks.md)
- [Настройка агента](../../../../docs/user/configuration.md)
- [Оглавление руководства](../user-guide.md)
