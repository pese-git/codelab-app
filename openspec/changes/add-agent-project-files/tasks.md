Задачи идут парами «тест → реализация» (dart-agent-and-clients §9.0, правило 3; `packages/dart/codelab_agent_core/AGENTS.md` §2). В скобках — требование спецификации этого change, строка матрицы или решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `apps/codelab_agent` и документы ядра;
- `[protocol]` — `codelab_agent_acp` (публикация команд, реплей, опция `agent`, фабрика conformance) и фикстуры `codelab_acp_testing`;
- `[client]` — `apps/codelab_cli`: тест вывода `codelab config check` (D13) и раскрытие `~` в `CODELAB_HOME` (D17).

Задач `[desktop]` нет. Клиенты уже показывают `available_commands_update` (`CommandCatalog`) и любые `configOptions`, поэтому `codelab_client_*`, `apps/codelab_desktop` и `codelab_acp_protocol` не меняются (proposal, «Impact»).

Итерации — тонкие сквозные срезы, каждая отдельным PR (или 2–3 PR) в `develop`:
- итерация 0 — группа 0: документы;
- итерация 1 — группы 1–3: инструкции проекта (8.6, E-01);
- итерация 2 — группы 4–6: шаблоны команд (8.7, E-07, R-07 в части шаблонов);
- итерация 3 — группы 7–9: определения агентов (8.8, R-15);
- итерация 4 — группа 10: `config check` с диагностикой файлов проекта (D13);
- итерация 5 — группа 11: матрица, сверка документов, Definition of Done.

Итерации 2 и 3 зависят от порта и загрузчика итерации 1. Итерации 2 и 3 между собой независимы и МОГУТ идти параллельно.

Проверки каждой задачи — по `AGENTS.md` §21, только для затронутого:
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` пакета;
- `fvm dart test` пакета и `fvm flutter test` того же пакета;
- `fvm dart run tool/gen_prompts.dart --check` в `codelab_agent_core` при правке `prompts/`;
- `fvm dart run melos run guard` при правке импортов или `pubspec.yaml`;
- `fvm dart run melos run web-compile` при правке ядра.

Полный `melos run check` — в CI pull request. Тесты с файлами идут во временных `CODELAB_HOME` и `cwd` и не читают настоящий `~/.codelab`. Процессные тесты — с `timeout` (`Timeout(Duration(seconds: 60))`). `test:e2e:app:*` не запускаются (`AGENTS.md` §21).

## 0. Документы (итерация 0, без кода)

- [x] 0.1 `[agent]` Сделано при подготовке change:
  - `09-13-stage-8-mcp-config.md`, пункты 6–8 — загрузчик `ProjectFilesLoader`, локальная файловая система и граница (D2), доверие (D4), ключ `tools.project_context.max_bytes`, резервные имена, режим не мягче конфига; имя change `add-agent-project-files`;
  - `agent-core/11-prompts.md` §11.5 — абзац о контексте проекта (локальная ФС вместо env сессии, корень `BoundedEnv`, бюджет, шаги 10 и 10b);
  - `agent-core/15-configuration.md` §15.8 — опция `agent` без `category`, шаг 6 `selectAgent` по ACP-11, режим не мягче конфига, `trustedProjects`;
  - `agent-core/17-2-skills-and-templates.md` §17.2.2 — шаблоны и доверие по каноническому `cwd`, резервные имена, источник — этап 8 (8.7).
- [x] 0.2 `[agent]` Решения пользователя 2026-10-30 (OQ1–OQ4, все (а)) записаны: §11.5 и 09-13, пункты 6–8 — алиас `CLAUDE.md`, `AGENTS.md` для недоверенного проекта, режим не мягче конфига, встроенные команды — отдельный change; `agent-parity-goals.md` E-01 — уточнение без изменения сути Must-строки.
- [x] 0.3 `[agent]` Точечные правки документа ядра:
  - `11-prompts.md` §11.2 (файлы `project_context.md`, `project_context_file.md`, `agent_profile.md`), §11.7 (тексты), §11.10 (golden с контекстом и профилем);
  - `15-configuration.md` §15.3 (строка `tools.project_context.max_bytes` — только уменьшение), §15.4 (диапазон `0..262144`, `0` — выключено);
  - `17-2-skills-and-templates.md` §17.2.6 — незакрытая кавычка закрывается концом ввода до change встроенных команд (D8); неизвестная команда уходит модели до того же change (OQ1);
  - `08-sessions.md` §8.2.3 — поле `command` с `source: template` с этапа 8;
  - `05-agent-loop.md` §5.3 — источник `template` с этапа 8, `CommandsChanged` пока не эмитится (D9);
  - `12-observability-and-errors.md` §12.2 — события D14;
  - `13-acp-adapter.md` §13.4, шаг 6 — список после `session/new` — команды шаблонов, встроенные — change встроенных команд (OQ1).
- [x] 0.4 `[agent]` `agent-parity-goals.md`: E-01 — алиас и чтение без доверия; E-07 — этап 8 в объёме шаблонов проекта и пользователя (без `templates_dirs`); R-07 — «часть шаблонов — change `add-agent-project-files`; встроенные команды и MCP prompts — change встроенных команд», строка закрыта частично; R-15 — ссылка на change и правило режима (OQ3), суть строки без изменений.

**Критерий итерации 0.** Документы не расходятся с design.md; ссылки на D-решения есть в каждом изменённом абзаце.

## 1. Ядро: порт, сборка контекста, секция промпта (итерация 1; D1, D5)

- [x] 1.1 `[agent]` Тесты `codelab_agent_core/test/project/assemble_project_context_test.dart` (agent-project-context «Бюджет и усечение контекста проекта»): порядок от общего к частному; бюджет от ближнего; усечение по границе строки с пометкой `[file truncated: showing N of M bytes]`; `omitted`; пустой файл; `maxBytes: 0`; многобайтовые символы UTF-8 не режутся посередине. Красный: функции нет.
- [x] 1.2 `[agent]` `lib/src/project/`: `ProjectFilesSource`, `ProjectFilesQuery`, `ProjectFiles`, `ContextFile`, `MarkdownFile`, `ExtensionDiagnostic`, `ExtensionScope`, `ProjectContext`, `assembleProjectContext`; экспорт бареля; doc-комментарии по `AGENTS.md` §15. 1.1 зелёный.
- [x] 1.3 `[agent]` Тесты промптов (agent-prompts «Детерминированная сборка системного промпта», agent-project-context «Секция project_context»):
  - golden `test/prompts/golden/agent-serve-standard-project.txt` с двумя файлами;
  - экранирование `</project-instructions`;
  - сторож PR-6 для новых файлов;
  - без контекста промпт побайтово прежний (существующие golden не меняются).

  Красный: секции нет.
- [x] 1.4 `[agent]` `prompts/project_context.md`, `prompts/project_context_file.md`; генерация `prompts.g.dart`; поле `PromptInputs.projectContext`; шаг 10 в `compose.dart`. 1.3 зелёный, `gen_prompts.dart --check` зелёный.

## 2. Ядро: конфигурация и runtime (итерация 1; D4, D5, D6)

- [x] 2.1 `[agent]` Тесты `codelab_agent_core/test/config/` (agent-configuration «Ключ tools.project_context.max_bytes», «Доверенные проекты в CoreConfig»): диапазон; `0`; уменьшение и увеличение из недоверенного проекта; нет `config.key.not_applied`; `trustedProjects` в полном снимке и в `withoutProject`. Красный.
- [x] 2.2 `[agent]` Схема (`_intU` → применяемый ключ), правило в `trust.dart` (только уменьшение), поле `CoreConfig.trustedProjects` из `_trustedRoots`. 2.1 зелёный.
- [x] 2.3 `[agent]` Тесты `codelab_agent_core/test/runtime/project_files_runtime_test.dart` на фейковом `ProjectFilesSource` (agent-runtime «Файлы проекта сессии»; agent-project-context «Порт файлов проекта»):
  - запрос с каноническим `cwd`, `projectTrusted` и `contextMaxBytes`;
  - доверие по `cwd` сессии и по symlink;
  - исключение порта → сессия без файлов и `code: unexpected`;
  - `dispose()` рантайма во время `load` → результат выброшен, сессия не создана;
  - повторный `session/load` открытой сессии порт не вызывает — перенесено в задачу 6.4 `[protocol]` (итерация 2): поведение выполняет ACP-адаптер (`reattach` в `agent_server.dart`), требование — в agent-acp-server «session/load и реплей»;
  - события `project_context.loaded` и `project_files.diagnostic` без содержимого файлов;
  - без порта — поведение прежнее.

  Красный.
- [x] 2.4 `[agent]` `AgentCoreServices.projectFiles`, вызов в `AgentRuntimeImpl._open` с дочерним токеном, логирование диагностик, `PromptInputs.projectContext` сессии. 2.3 зелёный.

## 3. Загрузчик контекста и хост (итерация 1; D2, D5, D16)

- [x] 3.1 `[agent]` Тесты `codelab_agent_io/test/project/project_context_loader_test.dart` на реальных файлах (agent-project-context «Поиск инструкций проекта», «Граница чтения файлов проекта»):
  - `core/project-context-agents-md-leaf-first` (E-01): «правило A» корня перед «правилом B» `cwd`;
  - без `.git` — только `cwd`;
  - `.git`-файл (worktree);
  - алиас `CLAUDE.md` и `shadowed`;
  - symlink `AGENTS.md` наружу → `outside_root`, файл не прочитан;
  - файл не в UTF-8 → `not_utf8`;
  - предел 64 уровней;
  - читается не больше `max_bytes + 1` байт, `M` — из `stat`;
  - `home: null` — пользовательский файл не читается.

  Красный: загрузчика нет.
- [x] 3.2 `[agent]` `codelab_agent_io/lib/src/project/project_files_loader.dart` — контекстная часть `ProjectFilesLoader` (`BoundedEnv` по корню области, единственная проверка `.git` вне границы); экспорт бареля. 3.1 зелёный.
- [x] 3.3 `[agent]` Тест `apps/codelab_agent/test/project_files_process_test.dart` (agent-binary «Файлы проекта в бинаре», сценарий «Сценарий не читает CODELAB_HOME»): `serve --stdio --llm-script` во временном `cwd` с `AGENTS.md` → лог `project_context.loaded` называет только файл `cwd`. Красный.
- [x] 3.4 `[agent]` `AgentHost.build` передаёт `ProjectFilesLoader` (`home: null` под `--llm-script`). 3.3 зелёный.

- [x] 3.5 Исправления по ревью итерации 1 (решения пользователя и ревью 2026-10-30). Каждый подпункт — сначала красный тест, затем код:
  - [x] 3.5.1 `[agent]` WebSocket не читает файлы проекта (agent-binary «Файлы проекта в бинаре», сценарий «WebSocket не читает файлы проекта»; D2, D16): тест хоста `apps/codelab_agent/test/agent_host_project_files_test.dart` для `--ws` — `projectFiles == null`, одно событие `project_files.skipped` с `transport: ws`, нет `project_context.loaded`. Код — `AgentHost.build` передаёт загрузчик только для `--stdio`; документ `apps/codelab_agent/AGENTS.md` — при сверке 11.2.
  - [x] 3.5.2 `[agent]` Экранирование блока (agent-project-context «Секция project_context», сценарии «Тег в другом регистре и с пробелами», «Кавычка в имени каталога»; D5, D15): тест `codelab_agent_core/test/prompts/prompt_project_context_test.dart` — `</PROJECT-INSTRUCTIONS`, `< / project-instructions`, `<project-instructions`, атрибут `path` с `"<>\r\n`; лог хранит неэкранированный путь. Код — сборка блока в `compose.dart`.
  - [x] 3.5.3 `[agent]` Усечение (agent-project-context «Бюджет и усечение контекста проекта», сценарии «Длинная первая строка», «После усечения дальние файлы пропускаются»; D5 п. 3–4): тест `assemble_project_context_test.dart`. Код — `assembleProjectContext`.
  - [x] 3.5.4 `[agent]` Чтение префикса (agent-project-context «Граница чтения файлов проекта», сценарии «Окружение без PathResolver», «Путь подменён после проверки»; D2, D5 п. 4): ветки fail-closed — `codelab_agent_io/test/project/project_files_loader_seam_test.dart` через `@visibleForTesting ProjectFilesLoader.testing(local:, beforeOpen:)`: окружение без `PathResolver` → `AGENTS.md` и каталоги шаблонов не читаются, `unreadable`; подмена пути symlink наружу между проверкой и открытием → содержимое внешнего файла не попадает, диагностика ровно `outside_root` (сценарий допускает и `unreadable`, тест строже); не больше `max_bytes + 1` байт по каноническому пути — `project_context_loader_test.dart` («at most max_bytes + 1 bytes are read»). Код — `ProjectFilesLoader` (`dart:io` по пути от `BoundedEnv.realpath`, повторная проверка после открытия). Тесты ветвей fail-closed добавлены в итерации 5 (11.3).
  - [x] 3.5.5 `[agent]` Таймаут и отмена загрузки (agent-project-context «Порт файлов проекта», сценарии «Таймаут загрузки», «Отмена рантайма во время загрузки»; D6): тест `project_files_runtime_test.dart` на фейковом порте, который не завершается, — без реального ожидания 5 с. Код — `_loadProjectFiles` ждёт первым из загрузки, отмены и таймаута; по таймауту токен запроса отменяется.
  - [x] 3.5.6 `[agent]` Fail-closed доверия (agent-runtime «Файлы проекта сессии», сценарий «cwd не раскрылся»; D4): тест `project_files_runtime_test.dart`. Код — `projectTrusted = false`, если `realpath` не удался или нет `PathResolver`.
  - [x] 3.5.7 `[agent]` Коды и уровни диагностик (agent-project-context «Порт файлов проекта»; D3, D6): тесты загрузчика и runtime — `unreadable`, `timeout` и `outside_root`, `not_utf8` — `warning`; `shadowed`, `limit_exceeded` (64 уровня) — `info`; `limit_exceeded` для 100 файлов каталога — `warning`, проверяется в 5.3 и 8.1; `unexpected` — `error`. Код — `ProjectFilesLoader`, `_loadProjectFiles`.
  - [x] 3.5.8 `[agent]` Экспорт `BoundedEnv` из бареля ядра (D1; `agent-core/04-execution-env.md` §4.3): `test/public_api_test.dart` фиксирует экспорт; `melos run guard` и `web-compile` зелёные.

**Критерий итерации 1.** E-01 (`core/project-context-agents-md-leaf-first`) зелёный. Без `AGENTS.md` существующие golden-промпты и фикстуры не меняются. `web-compile` и `guard` зелёные. PR называет точку итерации 2: `ProjectFiles.templates` и `AgentSession.commands`.

## 4. Ядро: шаблоны, аргументы, разворачивание (итерация 2; D7, D8)

- [x] 4.1 `[agent]` Тесты `codelab_agent_core/test/commands/template_parse_test.dart` (agent-slash-commands «Формат шаблона и проверка», «Резервные имена команд», «Список команд сессии»):
  - имя файла;
  - frontmatter только `description`/`argument-hint`, неизвестный ключ → `error`;
  - описание из первой строки тела;
  - пустое тело и 33 КиБ;
  - `help.md` → `reserved_name`;
  - проект перекрывает пользователя (`shadowed`);
  - `inputHint`;
  - порядок по имени.

  Красный.
- [x] 4.2 `[agent]` Тесты `test/commands/arguments_test.dart` (SKL-8; «Разворачивание команды»): кавычки, `\"`, `$10`, `$$`, отсутствующий `$3`, значение `$ARGUMENTS` в `$1` не разворачивается, без плейсхолдеров — `ARGUMENTS:`, незакрытая кавычка закрывается концом ввода. Красный.
- [x] 4.3 `[agent]` `lib/src/commands/`: `CommandTemplate`, `SlashCommand`, `SlashCommandSource`, `parseCommandTemplates`, `splitArguments`, `substituteArguments`, `expandCommand`, `availableCommands`, список резервных имён §13.4. 4.1, 4.2 зелёные.
- [x] 4.4 `[agent]` Тесты `test/runtime/command_expansion_test.dart` и `test/session/record_command_test.dart` (agent-slash-commands «Разворачивание команды», «Исходный текст команды в журнале»; agent-sessions «Поле записи command»):
  - `prompt([/review lib, image])` → модель получает тело и картинку после него;
  - `/nope x` и `/usr/bin/foo` уходят без изменений;
  - запись журнала с `command`, модель поля не видит;
  - `replay()` отдаёт исходный текст;
  - неизвестный `source` сохраняется;
  - лог `command.expanded` без аргументов.

  Красный.
- [x] 4.5 `[agent]` Разворачивание в `AgentSession.prompt`, поле `MessageRecord.command` (`records.dart`), реплей (`projections.dart`). 4.4 зелёный.

## 5. Загрузчик шаблонов и frontmatter (итерация 2; D2, D3, D6)

- [x] 5.1 `[agent]` Тесты `codelab_agent_io/test/project/frontmatter_test.dart` (CFG-21): `---` после BOM; CRLF; незакрытый `---` → `syntax`; якорь, тег, повторяющийся ключ → `profile` с позициями в координатах файла; без frontmatter — тело целиком. Красный.
- [x] 5.2 `[agent]` `lib/src/project/frontmatter.dart` поверх `readYamlTree`. 5.1 зелёный.
- [x] 5.3 `[agent]` Тесты `test/project/prompt_templates_load_test.dart` (agent-slash-commands «Каталоги шаблонов команд и доверие»):
  - недоверенный проект → файлы не читаются, одна диагностика `untrusted_project`;
  - доверенный → читаются;
  - 101 файл → `warning` `limit_exceeded`, видна в `config check`;
  - файл 65 КиБ → `too_large` без чтения;
  - подкаталоги не обходятся;
  - symlink в `prompts/` наружу → `outside_root`.

  Красный.
- [x] 5.4 `[agent]` Шаблонная часть `ProjectFilesLoader`. 5.3 зелёный.

## 6. ACP: публикация, реплей, фикстуры (итерация 2; D9, D15)

- [x] 6.1 `[protocol]` Фабрика conformance `codelab_agent_acp/test/conformance_test.dart`: `ProjectFilesLoader` с временным `CODELAB_HOME`, ключ `trusted_projects` с `${cwd}` в `setup.config` (acp-golden-fixtures «Фикстуры файлов проекта этапа 8»). Тест фабрики: неизвестный ключ по-прежнему провал. Сначала тест, затем код.
- [x] 6.2 `[protocol]` Фикстуры `codelab_acp_testing/fixtures/acp/prompt-template-command.json` и `available-commands-no-tools.json` (E-07, R-07; agent-acp-server «session/new», «session/load и реплей»). Красные: адаптер шлёт пустой список.
- [x] 6.3 `[protocol]` `agent_server.dart` и `session_bridge.dart`: `available_commands_update` из `session.commands` после `session/new` и в реплее; исходный текст команды — в `records.dart` и `projections.dart` ядра. 6.2 зелёные; сценарий «Режимы и опции новой сессии» прежний.

- [x] 6.4 `[protocol]` Тест `codelab_agent_acp/test/` (agent-acp-server «session/load и реплей», сценарий «Повторная загрузка открытой сессии не читает файлы проекта»; D6; перенесён из 2.3): открытая сессия загружается повторно после изменения `AGENTS.md` → фейковый `ProjectFilesSource` вызван один раз, промпт следующего хода прежний. Характеризационный: `reattach` уже не вызывает `loadSession`, поэтому тест зелёный сразу (PR говорит об этом); красный — правка `agent_server.dart`.

- [x] 6.5 Исправления по ревью итерации 2 (документы уже обновлены: D2, D3, D8, D14, §12.2, §17.2.2, §17.2.6). Каждый пункт — тест, затем код:
  - `[agent]` граница каталогов двухступенчатая (D2): каталог шаблонов — `realpath` по корню области, файлы — `BoundedEnv` с корнем в реальном пути каталога; тест `prompt_templates_load_test.dart`: файл-symlink из `$CODELAB_HOME/prompts/` на `$CODELAB_HOME/config.yaml` → `outside_root`; запись `x.md`, которая FIFO, → `unreadable` (warning) без открытия;
  - `[agent]` уровни кодов содержимого шаблонов по таблице D3 (`unknown_key`, `invalid_value`, `empty_body`, `too_large` — error; `invalid_name`, `reserved_name` — warning; `shadowed`, `untrusted_project` — info); тест в `test/commands/`;
  - `[agent]` завершающий `\r?\n` снимается с `raw` (agent-slash-commands «Завершающий CRLF»); тест в `test/commands/`;
  - `[agent]` заголовок сессии по исходному `/<name> <args>` для записи с `command` (agent-sessions «Автозаголовок по команде»; D8): `summarize`, `session/list`, автоматический `session_info`; тесты в `test/session/` и `test/runtime/`;
  - `[agent]` поле `commands.loaded.project` — проект доверенный (D14); проверка лога в тесте рантайма;
  - `[protocol]` сценарий «Команды шаблонов после session/new» — шаблон доверенного проекта в `available-commands-no-tools.json`; пользовательская область — тест хоста `apps/codelab_agent/test/agent_host_project_files_test.dart`.

**Критерий итерации 2.** E-07 (`acp/prompt-template-command`) и R-07 в части шаблонов (`acp/available-commands-no-tools`) зелёные. Фикстуры этапов 0 и 4 не менялись. `web-compile`, `guard`, `gen_prompts --check` зелёные. PR называет точку итерации 3: `ProjectFiles.agents` и `AgentSession.setAgent`.

## 7. Ядро: определения агентов и выбор (итерация 3; D10, D11)

- [x] 7.1 `[agent]` Тесты `codelab_agent_core/test/agents/agent_definition_parse_test.dart` (agent-definitions «Формат определения и проверка»):
  - многострочный `tools`, кавычки, комментарии;
  - неизвестный ключ, пустое тело, `name: Reviewer`, `default`, `mode: autopilot`, синоним `code`, модель вне каталога, `*` не в конце;
  - два файла с одним `name` → `duplicate` с обоими путями;
  - `scope: subagent` вне `agents`.

  Красный.
- [x] 7.2 `[agent]` `lib/src/agents/`: `AgentDefinition`, `AgentScope`, `parseAgentDefinitions`. 7.1 зелёный.
- [x] 7.3 `[agent]` Тесты `test/agents/agent_select_test.dart` — критерий `core/agent-definition-markdown-frontmatter` (agent-definitions «Выбор агента»; CFG-7, CFG-8):
  - выбор `reviewer` → секция профиля, модель и режим из файла, только схемы из списка (включая MCP-инструмент, появившийся после `tools/list_changed`);
  - `write` → `Tool not available for agent reviewer: write` без вызова gate;
  - возврат к `default` восстанавливает всё;
  - `mode: bypass` при конфиге `standard` → `agent.mode.not_applied`;
  - `extraDeniedTiers` остаются;
  - смена посреди хода — со следующего шага;
  - golden промпта с профилем.

  Красный.
- [x] 7.4 `[agent]` `prompts/agent_profile.md`, шаг 10b `compose.dart`, `PromptInputs.agentProfile`; `AgentSession.agents`, `agent`, `setAgent` (база, пол режима, фильтр инструментов на шаге поиска инструмента, `StepUpdate`), `config_change agent`, лог `agent.selected`. 7.3 зелёный.
- [x] 7.5 `[agent]` Тест `test/runtime/agent_restore_test.dart` (agent-definitions «Восстановление агента при загрузке»): агент восстановлен; определение удалено → `default` и `agent.definition.missing`. Красный → код в `loadSession` → зелёный.

## 8. Загрузчик определений (итерация 3; D2, D4, D6)

- [x] 8.1 `[agent]` Тесты `codelab_agent_io/test/project/agent_definition_trust_test.dart` (CFG-6; agent-definitions «Каталоги определений агентов и доверие»): без доверия — не загружено, `untrusted_project`; с доверием — заменяет пользовательское (`shadowed`); лимиты и `outside_root` как в 5.3. Красный.
- [x] 8.2 `[agent]` Часть определений в `ProjectFilesLoader`. 8.1 зелёный.
- [x] 8.3 `[agent]` Тест хоста `apps/codelab_agent/test/agent_host_project_files_test.dart` (agent-binary «Файлы проекта в бинаре», сценарий «Шаблон пользователя»; дополнительно определение проекта при доверии в глобальном `config.yaml`). Красный, если хост не передаёт загрузчик полностью; иначе — характеризационный, зелёный сразу (PR говорит об этом).

## 9. ACP: опция agent (итерация 3; D12)

- [x] 9.1 `[protocol]` Фикстура `codelab_acp_testing/fixtures/acp/set-config-option-agent.json` (R-15; agent-acp-server «Режимы и опции сессии»): опция `agent` без `category` после `effort`; `set_config_option agent=reviewer` → `current_mode_update`, ответ с согласованными `agent`, `model`, `mode`, без `config_option_update`; следующий запрос к модели — только схемы списка. Тест `config_options_agent_test.dart`: без определений опции нет; неизвестное значение → `-32602`. Красные.
- [x] 9.2 `[protocol]` `config_options.dart` (опция `agent`), `session_bridge.dart` (`configId: agent`, `current_mode_update` при смене режима), реплей `config_option_update` с восстановленным агентом. 9.1 зелёные; `acp/session-new-modes-config` и `acp/set-config-option-model` без изменений.
- [x] 9.3 Исправления по ревью итерации 3 (документы уже обновлены: D10, D11, D12, D14, D15, §11.10, §12.2, §13.6, §15.8). Каждый пункт — тест, затем код:
  - [x] `[agent]` очередь смен конфигурации сессии: `setMode`, `setModel`, `setEffort`, `setAgent` по одной, значение под очередью, ошибка не ломает очередь (agent-runtime «Очередь смен конфигурации сессии», сценарии «Параллельные setAgent и setMode», «Ошибка не ломает очередь»; agent-definitions «Выбор агента и смена режима подряд»; D11); тест в `test/agents/agent_select_test.dart` или `test/runtime/`;
  - [x] `[agent]` режим агента посреди хода — со следующего шага, вызовы пакета текущего шага по прежнему режиму и набору; явный `setMode` после `setAgent` выигрывает (agent-definitions «Смена агента посреди хода»; D11); тест в `agent_select_test.dart`;
  - [x] `[agent]` зажим восстановленной базы полом конфига (agent-definitions «База зажата полом конфига»; D11); тест в `test/runtime/agent_restore_test.dart`;
  - [x] `[agent]` `agent.definition.missing` дописывает `config_change {optionId: "agent", value: "default"}`, повторная загрузка лога не пишет (agent-definitions «Определение удалено»; D11); тест в `agent_restore_test.dart`;
  - [x] `[agent]` `ModeId.softness`: явная ветка `standard`, неизвестный режим — fail-closed (agent-definitions «Неизвестный режим»; D11); тест в `test/permissions/`;
  - [x] `[agent]` два golden: `agent-serve-standard-project.txt` без профиля, `agent-serve-standard-project-agent.txt` с профилем (agent-prompts «Контекст проекта без профиля», «Контекст проекта и профиль агента»; D15); тест `test/prompts/`;
  - [x] `[agent]` уровни кодов определений по таблице D10, `duplicate` на каждый файл с обоими путями (agent-definitions «Ошибки определения», «Дубликат имени»); тест `agent_definition_parse_test.dart`;
  - [x] `[agent]` отказ вне набора агента в `MisuseBreaker` как неизвестный инструмент; секция `mcp` только с серверами, у которых есть доступные инструменты; тело профиля с обрезкой краёв (agent-definitions «Отказ вне набора считается предохранителем», «Сервер без доступных инструментов скрыт», «Тело профиля с краями»; D11); тесты в `agent_select_test.dart` и `test/prompts/`;
  - [x] `[agent]` `agent.selected`: `source: null` для `default`, `mode_applied: true` без `mode` у определения, `false` только при отказе по полу (D14); проверка лога в `agent_select_test.dart`;
  - [x] `[protocol]` очередь запросов `set_config_option`/`set_mode` в мосте и эхо `ModeChanged` своего запроса: ровно один ответ на запрос, без `config_option_update`, итог — последний запрос (agent-acp-server «Параллельные выбор агента и set_mode»; D12); тест `config_options_agent_test.dart`;
  - [x] `[protocol]` заметка §2.12.3 при смене модели через опцию `agent` (agent-acp-server «Смена модели агентом и заметка effort»; D12); тест `config_options_agent_test.dart`.

**Критерий итерации 3.** R-15 (`core/agent-definition-markdown-frontmatter`, `acp/set-config-option-agent`) зелёный; CFG-6, CFG-7, CFG-8 покрыты тестами. Выбор агента не смягчает режим конфига и не снимает запретов. `web-compile`, `guard`, `gen_prompts --check` зелёные.

## 10. config check (итерация 4; D13)

- [x] 10.1 `[agent]` Тесты `codelab_agent_io/test/cli/config_commands_test.dart` (agent-configuration «config check показывает диагностику файлов проекта»):
  - битое определение → строка `warning:` с путём, строкой и столбцом, `Config: valid`, код `0`;
  - `info` не печатается;
  - невалидный конфиг → файлы не проверяются;
  - в выводе нет фрагментов файла.

  Красный.
- [x] 10.2 `[agent]` `ConfigCommands.check` вызывает `ProjectFilesLoader` и проверки ядра. 10.1 зелёный; `apps/codelab_agent/test/config_command_process_test.dart` дополнен сценарием с битым шаблоном.
- [x] 10.3 `[client]` Тест `apps/codelab_cli/test/config_command_test.dart`: `codelab config check --cwd` с `$CODELAB_HOME/prompts/Review.md` печатает ту же строку `warning:`, что `codelab-agent config check` (сценарий «Одинаково у двух бинарей»). Кода в CLI не требуется (мост `codelab_setup`); если тест красный — правка только в `codelab_agent_io`.
- [x] 10.4 Исправления по ревью итерации 4 (agent-configuration «config check показывает диагностику файлов проекта»; D13):
  - [x] `[agent]` тесты `config_commands_test.dart`: сценарии «Битое определение агента» (префикс `unknown frontmatter key`, без имени ключа), «Недоверенный проект» (две строки `note:`, прочих `info` нет), «Сбой загрузчика» (`CODELAB_HOME='~/x'`), «Таймаут загрузки» (фейковый `ProjectFilesSource`); канонический `cwd` через `LocalExecutionEnv.realpath` (symlink на доверенный корень — доверен). Красные;
  - [x] `[agent]` `ConfigCommands.check` → `Future<ConfigCommandResult>`, канонический `cwd`, строки `note:`, перехват исключения и таймаут 5 с; вызывающие `apps/codelab_agent` и мост `codelab_setup` ждут результат. Тесты выше зелёные;
  - [x] `[client]` `apps/codelab_cli`: ожидание асинхронного `check`; `config_command_test.dart` — «Одинаково у двух бинарей» (`not a valid command name`) и сбой загрузчика с той же строкой, что у `codelab-agent`.

- [x] 10.5 `CODELAB_HOME` с `~` раскрывается в домашний каталог (решение пользователя 2026-10-30; D17; agent-configuration «Корень состояния CODELAB_HOME», codelab-cli «Домашний каталог CLI CODELAB_HOME»):
  - [x] `[agent]` тесты `codelab_agent_io/test/config/codelab_home_test.dart`: `~` → `HOME`, `~/x` → `HOME/x`, `USERPROFILE` при отсутствующем или пустом `HOME`, абсолютное значение — как есть; `~bob/x` и `~\x` — `ConfigUsageException` с `CODELAB_HOME: ~user is not supported, use an absolute path`; `~` и `~/x` при отсутствующих или пустых `HOME` и `USERPROFILE` — `ConfigUsageException` с `CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an absolute path`; тот же тест — `trusted_projects: [~/proj]` раскрывается тем же правилом. В `config_loader_test.dart` (или там же) — сценарий «Тильда раскрывается в HOME»: слой 2 из `<HOME>/cl/config.yaml`, каталог `<cwd>/~` не создан. В `config_commands_test.dart` — «Пользовательская область файлов проекта»: `CODELAB_HOME='~/cl'`, шаблон в `<HOME>/cl/prompts/`, строки `could not be read` нет; сценарий «Сбой загрузчика» переведён с `~/x` на относительный путь к несуществующему каталогу. Красные;
  - [x] `[agent]` `codelabHomeOf` раскрывает `~` и `~/…` одной приватной функцией с `ConfigLoader._canonicalEntry` (`trusted_projects`): сейчас там `HOME ?? USERPROFILE` без проверки на пустой `HOME`, правило должно стать одним; doc-комментарий — почему/для чего/как (D17); `codelabHomeOf` бросает `ConfigUsageException` для `~user/…`, `~\…` и тильды без домашнего каталога; `apps/codelab_agent/test/config_command_process_test.dart` — процесс с `CODELAB_HOME='~/cl'` и `HOME=<tmp>` читает `<tmp>/cl/config.yaml`, а `config check` и `serve --stdio` с `CODELAB_HOME='~bob/cl'` — код `64` и текст в stderr (сценарии «~user — ошибка использования», «Тильда без домашнего каталога»); `serve --stdio --llm-script` с `CODELAB_HOME='~bob/cl'` запускается и проводит ход без кода `64` (сценарий «Сценарий --llm-script не проверяет CODELAB_HOME»; хост не вызывает `codelabHomeOf` в этом режиме). Тесты выше зелёные;
  - [x] `[client]` тесты `apps/codelab_cli/test/home_test.dart` с теми же входами, что у агента: `~`, `~/x`, `USERPROFILE`; `~user/x` и `~\x` — `UsageError` с тем же текстом, что у агента; `~/x` без домашнего каталога — `UsageError` с тем же текстом, что у агента; процессный тест `codelab -p hi` с `CODELAB_HOME='~bob/cl'` — код `64`; `config_command_test.dart` — одинаковость вывода двух бинарей проверяется на ошибке `~bob/x` (код `64`, тот же текст, что у `codelab-agent`); сбой загрузчика проверяется только в `codelab_agent_io` на подменённом источнике. Красные;
  - [x] `[client]` `CodelabHome.resolve` раскрывает `~` и `~/…`; `~user/…`, `~\…` и тильда без домашнего каталога — `UsageError` (код `64`) с текстами D17; doc-комментарий обновлён (D17). Тесты выше зелёные;

**Критерий итерации 4.** Диагностика R-15 «битый YAML — диагностика с именем файла» видна в `config check` обоих бинарей; коды выхода прежние. `CODELAB_HOME='~/…'` указывает на домашний каталог у обоих бинарей.

## 11. Матрица, сверка документов, DoD (итерация 5)

- [x] 11.1 `[agent]` Матрица этапа 8 в `09-13-stage-8-mcp-config.md`: E-01, E-07, R-15 — «выполнено» с файлами тестов и фикстур; R-07 — «часть шаблонов выполнена (`acp/available-commands-no-tools`); встроенные команды и MCP prompts — change встроенных команд»; DoD «Фикстуры `acp/available-commands-no-tools` зелёные» отмечен; итог 8.6–8.8 абзацем, как у 8.1–8.4.
- [x] 11.2 `[agent]` Сверка документов с кодом (`codelab_agent_core/AGENTS.md` §3, критерий (е)):
  - `agent-core` §11.2, §11.5, §11.7, §15.4, §15.8, §17.2.2, §17.2.6, §8.2.3, §5.3, §12.2, §13.4;
  - вложенные `AGENTS.md` `codelab_agent_io` (§1: `lib/src/project/`) и `apps/codelab_agent` (§1: загрузчик файлов проекта, `--llm-script`);
  - doc-комментарии новых сущностей на русском (`AGENTS.md` §15).
- [x] 11.3 `[agent]` Definition of Done change:
  - все сценарии спецификаций этого change покрыты тестами из задач 1–10;
  - `melos run guard`, `web-compile`, `gen_prompts --check` зелёные;
  - сторож и allowlist не менялись (D1);
  - полный `melos run check` — в CI pull request последней итерации.

  Сверка DoD 2026-10-30 (итерация 5). Сценарии, у которых покрытия не хватало при первой сверке, закрыты тестами:

  | Сценарий | Тест |
  |---|---|
  | agent-project-context «Окружение без PathResolver» | `codelab_agent_io/test/project/project_files_loader_seam_test.dart`, группа `an environment without PathResolver` |
  | agent-project-context «Путь подменён после проверки» | тот же файл, группа `the path is swapped after the check` (`beforeOpen`), диагностика ровно `outside_root` |
  | agent-project-context «Кавычка в имени каталога» | `codelab_agent_core/test/runtime/project_files_runtime_test.dart`, группа `the log (D14)`: атрибут `a_b/AGENTS.md`, лог `a"b/AGENTS.md` |
  | agent-configuration «Тильда без домашнего каталога» | `apps/codelab_agent/test/config_command_process_test.dart` — процесс `config check`, `HOME=''`, код `64`, текст stderr |
  | codelab-cli «Тильда раскрывается в HOME», «Тильда без домашнего каталога» | `apps/codelab_cli/test/e2e/codelab_home_tilde_test.dart` — процессы `profiles add` и `-p hi`, пустые `HOME`/`USERPROFILE` |
  | agent-definitions «Неизвестный режим» | `codelab_agent_core/test/permissions/modes_test.dart` (`fitsFloor(ModeId.standard)` — `false`); сценарий переписан на модульный уровень по решению пользователя 2026-10-30: разбор отвергает режим вне пяти `ModeId` (сценарий «Ошибки определения»), лог для него недостижим; D11 синхронизирован |

  Остальные сценарии покрыты тестами задач 1–10 (ссылки — в самих задачах). Без `PathResolver` `unreadable` получают и каталоги `prompts`/`agents`: сценарий требует «есть диагностика `unreadable`» и это допускает.
  - D1: `git log 59ff202^..HEAD` по `packages/dart/codelab_architecture_tests` и по `pubspec.yaml` пакетов и приложений пуст, незакоммиченных правок там нет — сторож и allowlist не менялись.
  - Targeted-прогон оркестратора 2026-10-30, все команды — exit 0: тесты `codelab_agent_core` (1405), `codelab_agent_io` (307), `codelab_agent_mcp` (248), `codelab_agent_acp` (198), setup (2), `codelab_architecture_tests` (68), `apps/codelab_agent` (156), `apps/codelab_cli` (462); `melos run guard`, `prompts:check` (`gen_prompts.dart --check`), `web-compile`, `conformance:agent` (55), `test:e2e:cli` (57), `test:e2e:cli:dart-agent` (44), `openspec validate add-agent-project-files --strict`.
  - Полный `melos run check` — подтверждается CI pull request.
