## Why

Экран 24 дорожной карты ([`delivery-roadmap.md`](../../../../docs/architecture/proposals/delivery-roadmap.md) §10.1) — «Settings › Skills & extensions» — единственное место в codelab-app, где пользователь видит, **какие инструкции получит агент в этой папке**: цепочку `AGENTS.md` (E-01), навыки (E-06) и шаблоны команд (E-07). Навыки в Dart-агенте реализованы change [`add-agent-skills`](../2026-11-18-add-agent-skills/proposal.md) (итерации 1–5), а страница app решением Q8 (а) этого change вынесена сюда. Сейчас навыки видны в app только как команды палитры и меню композера (`available_commands_update`). Не видно ни того, откуда навык загружен, ни того, что он перекрыт или пропущен с предупреждением, ни того, что проект недоверенный и его навыки не читаются. Выключить навык (`skills.disabled`) или дать согласие на каталог другого агента (`skills.extra_roots`, Q13 change `add-agent-skills`) можно только правкой `config.yaml` вручную.

Решение пользователя по объёму: «только то, что есть» в агенте. Контекстные файлы и шаблоны показываются только для чтения. Навыки показываются с выключателями, согласие на каталог другого агента — переключателем. Хуки (E-09), плагины (E-10) и переопределение системного промпта (E-08) не показываются: в агенте их нет.

## What Changes

- **Страница «Skills & extensions»** в группе «Agent» настроек app (`SettingsPage.skillsAndExtensions` уже есть в навигации, страница становится видимой). Разделы по артборду `Extensions` холста «CodeLab Desktop — Feature UI/UX»:
  - **Context files** — цепочка `AGENTS.md` (`CLAUDE.md` на уровне без `AGENTS.md`), от внешнего файла к ближнему, с размером, итогом `<n> files · <size>` и пометкой усечения по бюджету `tools.project_context.max_bytes`. Только чтение, кнопка «Open».
  - **Skills** — таблица навыков: имя, описание, «Invoke as» `/skill:<name> <argument-hint>`, источник (корень), выключатель «Enabled». Пометки: «Overrides <уровень> skill» (перекрытие), «Command only» (навык недоступен модели), число предупреждений. Над таблицей — InfoBar предупреждений загрузки. Под таблицей — переключатель согласия на каталог навыков другого агента (пишет `skills.extra_roots`) и подпись о порядке поиска. В подписи сказано, что список фиксируется при открытии сессии.
  - **Prompt templates** — команда, описание, файл-источник; только чтение.
  - В шапке — «Reload» (перечитать страницу) и «Open .codelab folder».
- **Источник данных — файлы на машине клиента через мост `codelab_setup`, а не агент.** Доступ определяет `resolveSettingsAccess`, как на страницах Providers и MCP servers. Встроенный агент и stdio-`codelab-agent` — тот же загрузчик `ProjectFilesLoader` и те же правила ядра (`parseSkills`, `parseCommandTemplates`, `assembleProjectContext`), что у агента и `config check`. WebSocket и сторонний stdio-агент — InfoBar «только для чтения», локальные файлы не читаются (SETUP-2). ACP не меняется.
- **Доверие проекта.** Для проекта вне `trusted_projects` навыки и шаблоны проекта не читаются, страница говорит об этом. Цепочка `AGENTS.md` читается и для недоверенного проекта (E-01).
- **Запись** — только мостом через `AgentConfigStore.apply` (`ConfigWriter`: блокировка, отпечаток базы, конфликт без автоповтора — SETUP-6). Цели — `user` и `projectLocal`, `project` никогда (SETUP-3, SKL-2). Изменения действуют на новые сессии.
- **Мост `codelab_setup`** (ADDED): вид страницы `AgentExtensionsView` и чистые правила записи `skills.disabled` и `skills.extra_roots` (основной барель); чтение файлов `readAgentExtensions` (`io.dart`).
- **`codelab_agent_core`** (аддитивно) и **`codelab_agent_io`**: типы результата — в ядре; расчёт канонической папки, доверия и двух фаз загрузки (файлы проекта и навыки) выносится из `ConfigCommands.check` в одну публичную функцию. Её используют `config check` и мост, вывод `config check` не меняется.
- **Платформа app**: порт `LocalFolderOpener` (`core/platform/`, `url_launcher`) открывает каталог в файловом менеджере ОС. Файлы не запускаются.
- **`codelab_ui`**: аддитивное расширение `CodeLabStatusTable` (вторая строка ячейки, теги, переключатель строки, доли ширины колонок). Поведение страницы MCP servers не меняется.

## Не входит

- **Hooks (E-09)** и **Plugins (E-10)** — разделы артборда не показываются, в агенте их нет. Это отдельные будущие changes (экран 24 остаётся в M5 частично).
- **System prompt override (E-08)** — в агенте ключи `prompts.system*` и `prompts.append_system*` распознаются, но не применяются (`applied: false` в `schema.dart`). Строки нет.
- **Чтение context-файлов других агентов (E-17)** — в агенте не реализовано: `prompts.context_files` не применяется, `GEMINI.md` и `.github/copilot-instructions.md` не читаются. Есть только `CLAUDE.md` как замена `AGENTS.md` на уровне без него (часть E-01, без настройки). Переключателя артборда «Read context files of other agents» нет.
- **Обновление списка навыков в идущих сессиях** (E-19) и встроенные навыки (E-18). Подпись артборда «running sessions get an updated command list» заменяется на «applies to new sessions».
- **Доверие проекту из app** (`trusted_projects`). Страница только показывает, что проект недоверенный, и называет, где это меняется.
- **Правка `SKILL.md`, шаблонов и `AGENTS.md` в app**, создание навыков, `skills.enabled`, `skills.max_skills` и другие ключи `skills.*`, кроме `disabled` и `extra_roots`.
- **Список навыков удалённого агента** (WebSocket, сторонний stdio). ACP не передаёт источник команды (D8 change `add-agent-skills`), а угадывать навыки по префиксу `skill:` запрещено.
- **CLI** (`/skills` в REPL и TUI) — не входит. Мост пишется так, чтобы CLI мог взять те же виды позже.
- **Изменения ACP** — новых методов, полей и `_meta` нет.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `app-settings` — MODIFIED «Страницы Providers и MCP servers в навигации» (страница «Skills & extensions» видима); ADDED «Страница «Skills & extensions»: доступ и папка», «Страница «Skills & extensions»: контекстные файлы и шаблоны», «Страница «Skills & extensions»: навыки», «Страница «Skills & extensions»: запись и применение», «Страница «Skills & extensions»: открытие папок», «События журнала страницы Skills & extensions».
- `client-agent-setup` — MODIFIED «Состав моста codelab_setup для настройки агента»; ADDED «Обзор расширений агента», «Правила записи skills.disabled и skills.extra_roots».

## Impact

- **Код:**
  - `packages/dart/codelab_agent_core` — аддитивно: типы данных `ProjectExtensions`, `PhaseOutcome`, `SkillRootInfo` рядом с портами файлов проекта (design.md, D3) (`[agent]`);
  - `packages/dart/codelab_agent_io` — публичная функция инвентаризации файлов проекта и навыков (из `ConfigCommands._fileLines`), `config check` переходит на неё без изменения вывода (`[agent]`);
  - `packages/dart/codelab_setup` — `lib/src/extensions/` (виды, построитель, правила записи), `lib/src/io/agent_extensions_reader.dart`, реэкспорты (`[agent]`);
  - `packages/flutter/codelab_ui` — расширение `CodeLabStatusTable`, превью (`[desktop]`);
  - `apps/codelab_desktop` — `features/settings/application/skills_settings_cubit.dart` и состояние, `presentation/skills_page.dart`, метод сессии настроек, `core/platform/local_folder_opener.dart`, сборка в `lib/app/`, `defaultSettingsPages` (`[desktop]`).
- **Зависимости:** новых нет. Allowlist ядра (PKG-2) и `setupAllowlist` не меняются. Новых пакетов и рёбер нет, граф `README.md` не меняется. Новое правило сторожа не нужно: существующие правила уже держат `codelab_setup/io.dart` в `lib/app/` и `url_launcher` в `core/platform/` (design.md, D11).
- **ACP:** без изменений.
- **Данные пользователя:** страница пишет только `skills.disabled` и `skills.extra_roots` в `$CODELAB_HOME/config.yaml` или `<проект>/.codelab/config.local.yaml` тем же писателем, что Providers и MCP servers. Формат конфига не меняется.
- **Безопасность:** app читает файлы навыков и шаблонов только по правилам агента (доверие fail-closed, границы и лимиты загрузчика). Тела навыков, шаблонов и `AGENTS.md` не попадают в состояние Cubit и журнал. Согласие на каталог другого агента даёт только пользователь (слои `user`/`projectLocal`, SKL-2). Открытие — только каталогов, без запуска файлов.
- **Документы:** `12-4-first-run-and-settings.md` (§12.4.9, строка экрана 24; новый §12.4.6а; инвариант SETUP-25), `delivery-roadmap.md` §10.1 (экран 24), `apps/codelab_desktop/AGENTS.md`, `packages/dart/codelab_setup/AGENTS.md`.
