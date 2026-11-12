## Why

Строка Should **E-06** матрицы целей ([`agent-parity-goals.md`](../../../docs/architecture/proposals/agent-parity-goals.md) §3.6) — навыки (skills): каталоги с `SKILL.md` в корнях проекта и пользователя, список навыков в системном промпте, тело по запросу модели, вызов `/skill:<name>` и чтение навыков других агентов только с согласия пользователя. Критерий приёмки — фикстура `acp/skill-command-listed`, устройство — `agent-core-architecture` [§17.2](../../../docs/architecture/proposals/agent-core/17-2-skills-and-templates.md).

Решением пользователя 2026-11-12 (Q1–Q3 в design.md) навыки перенесены из пула 1.x ([`delivery-roadmap.md`](../../../docs/architecture/proposals/delivery-roadmap.md) §6.2, бывший пункт 9) в объём продукта 1.0 (M4, §6.1, строка 10) и делаются **первой задачей сразу после ворот MVP** (итерация 4 change [`switch-default-agent-to-dart`](../switch-default-agent-to-dart/proposal.md)), до выпуска 9.4. Change готовится сейчас, пока идут ночи ворот; реализация по TDD — после их закрытия.

Сегодня у Dart-агента есть только соседние механизмы: шаблоны команд `/<name>` (E-07, change `add-agent-project-files`), встроенные команды (change `add-agent-builtin-slash-commands`) и загрузчик файлов проекта `ProjectFilesLoader` с границей чтения и диагностикой. Навыков нет: раздел конфигурации `skills` и capability `skills` распознаются как «после MVP» (`config.key.not_applied`), имя `skill` только зарезервировано, а `/skill:x` отвечает «Unknown command».

Пользователь также решил (Q2): архитектуру закладывать **для всей группы навыков** — встроенные навыки и указатели (E-18, `builtin://`), новые навыки без перезапуска (E-19, отпечаток каталога на границе шага), закреплённые строки `operative` (K-06), — а реализовать только базовый E-06. Контракты, порты и форматы этого change должны принять эти строки без переделки; сами они — отдельные changes.

## What Changes

- **Новая capability `agent-skills`** (ADDED): корни навыков и доверие — `.codelab/skills` и `.agents/skills` от рабочей папки вверх до корня git (только доверенный проект, ближний перекрывает дальний), `$CODELAB_HOME/skills` и `~/.agents/skills`, `skills.extra_roots` — согласие пользователя (для `.claude/skills` и прочих каталогов конкретных агентов); мягкая проверка `SKILL.md` по руководству Agent Skills (`docs/protocols/agent-skills/`) с одной попыткой починки YAML; перекрытия — предупреждения; секция каталога `skills/catalog` с описаниями целиком; инструмент модели `skill` со схемой `enum`; блок навыка с экранированием, `compatibility` и списком файлов; команды `/skill:<name>`; повторная активация без повторного тела; активные навыки с учётом сжатия; сопутствующие файлы через `read` и `ls` с границей только для чтения; скрипты навыка через `exec` по абсолютному пути с рабочей папкой проекта (Q26; `cwd` в каталоге навыка локально разрешён, но не советуется); файлы каталога навыка при `read` — доверенные (Q30); конфигурация `skills.*` (включая бюджеты повторного приложения `skills.reattach.*`); хосты; наблюдаемость; точки расширения E-18, E-19, K-06.
- **Порт `SkillFilesSource`** ядра и его реализация в `ProjectFilesLoader` (`codelab_agent_io`): файлы навыков читаются отдельной фазой открытия сессии со своим таймаутом, параллельно с файлами проекта (design.md, D1).
- **Граница только для чтения** (`agent-execution-env`, ADDED): `BoundedEnv` получает корни `readOnlyRoots` — каталоги загруженных навыков вне рабочей папки; чтение из них идёт в файловую систему процесса агента, запись и правка — `outsideWorkspace`; `cwd` команды в них — только при исполнении на машине агента и не советуется: блок навыка одной строкой для любого режима просит запускать скрипты по абсолютному пути с рабочей папкой проекта (design.md, D5, D7; решения Q4, Q17, Q23 (а), Q26 — они заменяют прежнее «`cwd` в них отклоняется»).
- **Сжатие** (`agent-compaction`, ADDED «Навыки после сжатия»): запись `compaction` хранит список активных навыков (имя, отпечаток), а контекст после резюме получает их блоки заново в пределах бюджетов 5000 токенов на навык и 25000 всего (design.md, D15; решение Q6).
- **Разрешения** (`agent-permissions`, MODIFIED «Критические пути правок конфигурации агента»): `.agents/skills/**` проекта, `$CODELAB_HOME/skills`, `~/.agents/skills`, абсолютные `extra_roots` и корни навыков выше `cwd` — конфигурация агента (PERM-11; решения Q9, Q16); запуск скрипта навыка (исполняемый файл в каталоге навыка при любом `cwd`) критическим не считается, как и существующий файл навыка аргументом его же скрипта; пишущие команды и перенаправления в каталог навыка критичны всегда; все корни навыков, включая относительные `extra_roots` и уровни выше `cwd`, защищены (решения Q24 (а), Q25, Q27, Q29 в суженной формулировке; уточнения Q33 — рабочий каталог навыка не снимает критичность у команд, кроме скрипта навыка и белого списка чтения, Q34 — опции кода и модуля у интерпретатора отключают исключение, Q35 — `SKILL.md` и опции вывода исключением не пользуются, Q36 — скрипт только под `scripts/`, Q37 — без переменных окружения, Q38 — ресурс только под `assets/` без `.md`).
- **Команды** (`agent-slash-commands`, MODIFIED «Список команд сессии», «Неизвестная команда», «Разворачивание команды»): после шаблонов — команды `skill:<name>` навыков с `user-invocable`; `/help` помечает их ` (skill)`; `/skill:<нет такого>` — `Unknown skill: <name>. Run /help to list commands.`; общая функция подстановки шаблонов и навыков получает литерал `\$` (решение Q7; решение Q15 (а)).
- **Системный промпт** (`agent-prompts`, MODIFIED «Детерминированная сборка системного промпта»): шаг 9a — секция каталога навыков между `mcp` и `project_context`.
- **Файлы проекта** (`agent-project-context`, MODIFIED «Порт файлов проекта», «Граница чтения файлов проекта»): корни навыков, лимиты и коды диагностик.
- **Конфигурация** (`agent-configuration`, MODIFIED «Схема и строгая проверка», «config check показывает диагностику файлов проекта»): раздел `skills` (кроме `skills.operative.*`) применяется; `config check` печатает диагностики навыков.
- **Журнал** (`agent-sessions`, MODIFIED «Поле записи command»): источник `skill` у вызова `/skill:<name>`, реплей и заголовок по исходной команде.
- **Профили хостов** (`agent-runtime`, MODIFIED «Профили хостов и сужение»): capability `skills` — `on` в трёх настольных профилях, `skills.enabled: false` сужает её.
- **Фикстуры** (`acp-golden-fixtures`, ADDED «Фикстуры навыков»): `acp/skill-command-listed` (критерий E-06), `acp/skill-invoke`, `acp/skill-tool-load`, `acp/skill-script-exec`.
- **Документы** (итерация 0, внесено): дорожная карта §4.5, §6.1 (строка 11), §6.2, §10.1, §10.2; матрица — этап E-06 `9+` → `9`, пересчёт §7 и формулировка согласия (Q13); `09-14-stage-9-switch-default.md`; `17-0-post-mvp.md`; сверка `agent-core-architecture` §17.2, §7.6.1, §9.8 с кодом и решениями Q4–Q38 (задача 0.3).

## Не входит

- **E-18** — встроенные навыки в бинаре (`builtin://<name>`) и файлы-указатели; **E-19** — перечитывание каталога без перезапуска, `CommandsChanged` и повторный `available_commands_update` посреди сессии; **K-06** — секция `Pinned directives` и ключи `skills.operative.*`. Для них в этом change только точки расширения и явные резервы (design.md, D10): правила `metadata.codelab-operative` проверяются, но не применяются (Q32); `skills.operative.*` по-прежнему дают `config.key.not_applied`; элемент `skills.extra_roots` со схемой `<scheme>://` — проблема конфига.
- **Каталоги конкретных агентов без согласия.** `.claude/skills`, `~/.codex/skills` и подобные сами не обходятся; только путь, записанный пользователем в `skills.extra_roots`. Общий каталог `.agents/skills` читается без отдельного согласия (Q13). Список найденных, но не разрешённых каталогов (`codelab-agent doctor`, §17.2.2) — после появления `doctor`.
- **`prompts.templates_dirs`** (корень `extra` шаблонов, E-20) — без изменений.
- **Страница app «Settings › Skills & extensions»** (экран 24 дорожной карты) — решением Q8 отдельным change; навыки видны в app через палитру и меню композера из `available_commands_update` без изменений кода app.
- **Выполнение навыка в субагенте** (руководство, «Subagent delegation») — с субагентами C-06.
- **Применение `allowed-tools`** (Q14) — поле распознаётся, но прав не даёт; поддержка — отдельным change.
- **Исполнение скриптов навыка самим агентом.** Скрипты из `scripts/` запускаются только инструментом `exec` по обычной политике разрешений.
- **Изменения ACP.** Новых методов, полей, `_meta` и `_codelab/*` нет: команды — `available_commands_update` и `session/prompt` (`docs/protocols/acp/protocol/14-Slash Commands.md`), загрузка навыка моделью — обычный `tool_call` вида `read`.

## Capabilities

### New Capabilities

- `agent-skills` — навыки Dart-агента: корни, доверие, формат `SKILL.md`, каталог в промпте, инструмент `skill`, команды `/skill:<name>`, сопутствующие файлы, конфигурация, хосты, наблюдаемость, резервы E-18, E-19, K-06.

### Modified Capabilities

- `agent-slash-commands` — MODIFIED «Список команд сессии», «Неизвестная команда», «Разворачивание команды».
- `agent-prompts` — MODIFIED «Детерминированная сборка системного промпта».
- `agent-project-context` — MODIFIED «Порт файлов проекта», «Граница чтения файлов проекта».
- `agent-configuration` — MODIFIED «Схема и строгая проверка», «config check показывает диагностику файлов проекта».
- `agent-sessions` — MODIFIED «Поле записи command».
- `agent-runtime` — MODIFIED «Профили хостов и сужение».
- `agent-execution-env` — ADDED «Корни только для чтения».
- `agent-compaction` — ADDED «Навыки после сжатия».
- `agent-permissions` — MODIFIED «Критические пути правок конфигурации агента».
- `acp-golden-fixtures` — ADDED «Фикстуры навыков».

## Impact

- **Код (после ворот MVP, по `tasks.md`):**
  - `packages/dart/codelab_agent_core/lib/src/skills/` (новый каталог: типы, разбор, каталог, секция промпта), `tools/builtin/skill.dart`, `tools/builtin/exec.dart` (подсказка Q23 до вызова env), `tools/builtin/read.dart` (доверие файлов навыка, Q30), `commands/` (`SlashCommandSource.skill`, разворачивание `skill:`), `prompts/skills/*.md` и `prompts.g.dart`, `env/bounded_env.dart` (`readOnlyRoots`), `host/host_profile.dart` (capability `skills`), `host/services.dart` (порт `SkillFilesSource`, файловая система процесса агента), `config/` (раздел `skills`), `runtime/` (фаза загрузки, сборка инструментов и промпта), `session/` и `compaction/` (поле `compaction.skills`, приложение после резюме в `buildLlmContext`), `permissions/` (исключение для скрипта навыка), `commands/arguments.dart` (литерал `\$`);
  - `packages/dart/codelab_agent_io/lib/src/project/project_files_loader.dart` (реализация `SkillFilesSource`), `config/agent_config_paths.dart` (защищаемые корни навыков, Q9, Q16), `project/frontmatter.dart` (починка YAML), `cli/config_commands.dart` (`config check`);
  - `apps/codelab_agent/lib/src/host/agent_host.dart`, `packages/dart/codelab_embedded/lib/src/io/local_opener.dart` — передача порта и файловой системы процесса;
  - `packages/dart/codelab_acp_testing/fixtures/acp/` — четыре фикстуры; `packages/dart/codelab_agent_acp/test/conformance_test.dart` — ключ `skills` в `setup.config`;
  - тесты клиентов без изменения кода: `apps/codelab_cli` (`CommandRouter`), `packages/dart/codelab_client_core` (`CommandCatalog`).
- **Зависимости:** новых нет (`yaml` уже в `codelab_agent_io`); allowlist ядра (PKG-2) не меняется; новых пакетов и правил сторожа нет; граф `README.md` не меняется (design.md, D12).
- **ACP:** без изменений протокола.
- **Данные пользователя:** журнал сессии получает поле `command` с `source: "skill"` и необязательное поле `compaction.skills` (старые ядра сохраняют неизвестные значения без потери). Формат журнала и конфигурации не ломается. `\$` в теле существующего шаблона начинает давать `$` (Q15 (а)).
- **Безопасность:** новый источник инструкций для модели — только через гейты доверия (SKL-1, SKL-2); `.agents/skills` без отдельного согласия (Q13); новая граница только для чтения в `BoundedEnv`; корни навыков под PERM-11 (Q9, Q16); запуск скриптов навыка — через `exec` и разрешения (Q17, Q24 (а)).
