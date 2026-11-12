Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). В каждой итерации сначала одной задачей пишутся красные тесты — они коммитятся отдельно, до кода, и только по явной просьбе пользователя. Затем пишется код. В скобках — сценарий спецификации, критерий матрицы или инвариант документа ядра.

Метки исполнителей (CLAUDE.md, таблица зон):
- `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `apps/codelab_agent`;
- `[protocol]` — `codelab_agent_acp`, `codelab_acp_protocol`, `codelab_acp_testing` (фикстуры);
- `[client]` — `codelab_client_acp`, `codelab_client_core`, `apps/codelab_cli`;
- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`.

Итерации — каждая отдельным PR в `develop` (design.md, D19):
- 0 — документы; решения пользователя 2026-11-10 (Q1–Q6), 2026-11-12 (Q9–Q13, design.md D29–D33) и переименование `task` → `agent` (design.md, D20) внесены;
- 1 — список задач вместо `update_plan`, схема объявления `initialize`;
- 2 — субагенты глубины 1;
- 2s — стыковка с навыками после слияния кода change `add-agent-skills` (решение пользователя 2026-11-12, Q17, design.md D34);
- 3 — запрос разрешения потомка;
- 4 — вложенность до 3 и задачи у субагентов;
- 5 — шаги потомков деревом (этап 2, design.md D21);
- 5b — панель Agents v1 (решение пользователя 2026-11-12, Q13, design.md D33);
- 6 — ручная проверка, документы, Definition of Done.

Зависимости: 1 ← 0; 2 ← 1; 2s ← 2 и код `add-agent-skills` (его итерация 2) в `develop` — если он там уже к началу итерации 2, задачи 2s выполняются внутри неё; 3 ← 2; 4 ← 3; 5 ← 4; 5b ← 5; 6 ← 5b и все остальные, включая 2s.


Проверки каждой задачи — только для затронутого (AGENTS.md §21; полный `melos run check` — по просьбе пользователя и на `release/*`):
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` / `fvm flutter analyze` пакета;
- `fvm dart test` / `fvm flutter test` пакета;
- `fvm dart run melos run prompts:check` — при правке `prompts/`;
- `fvm dart run melos run guard` — при правке импортов и `pubspec.yaml`;
- `fvm dart run melos run web-compile` — при правке `codelab_agent_core`, `codelab_client_core`, `codelab_client_acp`;
- `fvm dart run melos run protocol-conformance`, `conformance:agent`, `conformance:client`, `conformance:embedded` — при правке фикстур, проекции и kit.

Тесты — на Dart VM и widget-тесты. Интеграционные `integration_test/*` app в `feature/*` только компилируются (`fvm flutter analyze`), на устройстве их запускает `release/<version>` (AGENTS.md §21).

## 0. Документы (итерация 0)

- [x] 0.1 `[agent]` `agent-core/17-3-subagents.md`:
  - глубина до 3 настройкой, таблица этапов в §17.3.1;
  - `SubagentTree`, `SubagentWait`, `SubagentActivity`;
  - передача слота и бюджет предков (§17.3.3, §17.3.4);
  - плоская раскладка журналов (§17.3.6);
  - `_meta.codelab.subagent` с `depth`/`path` и схема объявления (§17.3.7);
  - `max_depth` (§17.3.10), SUB-1/2/3/5/6/9/11/12, SUB-23, SUB-24, обоснование и тесты.
- [x] 0.2 `[agent]` Новый `agent-core/17-16-task-list.md` и ссылки на него: оглавление `agent-core-architecture.md`, таблица `17-0-post-mvp.md`, навигация `17-15-a2a.md`.
- [x] 0.3a `[protocol]` `agent-core/13-acp-adapter.md`: §13.2 (схема объявления) и §13.12 (`clientCapabilities._meta.codelab`, `subagents`, `tasks`, `_meta.codelab.subagent`, `_meta.codelab.task`).
- [x] 0.4 `[agent]` `delivery-roadmap.md`: §4.5 (вопрос до вехи), §6.1 (строка 9, итог 27 Should), §6.2 (пункт 10), §6.4 (этапы наращивания), §10.1–§10.3 (экраны 01, 02, 15, 16, C4, C2, C9; строка change).
- [x] 0.5 `[agent]` `agent-parity-goals.md`: C-05 (новый критерий), C-06 (глубина, поэтапность, 1.0), новая строка C-20, обоснования, сценарий приёмки C-05, сводка §7 (Should 82, всего 261 после обновления от develop).
- [x] 0.6 Решения пользователя 2026-11-10 по Q1–Q6 внесены в design.md («Решённые вопросы», D20–D22), proposal, спецификации, задачи, §17.3, §17.16, §13, дорожную карту и матрицу. Переименование (Q2, D20): инструмент субагентов `agent` (параметр `type`, поле назначения пункта `task`), `agent_status`/`agent_cancel`/`agent_send`/`agent_resume`/`agent_observe`, ключ разрешения `("agent", <тип>)`, инструменты списка `task_create`/`task_update`/`task_list`/`task_get`, запись `task`, `TaskListChanged` — во всех документах `docs/architecture/` (кроме исторических имён внутри A2A, D20). Команда фоновой работы `/tasks`, вид CLI `tasks` и `toggle_tasks` не переименовываются (решение пользователя 2026-11-10, D23).
- [x] 0.3b `[agent]` Обход упоминаний `update_plan`, `PlanUpdated`, записи `plan` и `tools/plan.md` в документах ядра. Каждое упоминание заменяется ссылкой на §17.16 или помечается «до change `add-subagents-and-tasks`»:
  - §5.3 (таблица событий) и §5.6 (`ChildSessionSpec`);
  - §6.4 (раздел `update_plan` → «Инструменты списка задач», таблица доверия, перечни);
  - §7.5 (таблица шаблонов);
  - §8.2.4 (запись `plan` — «старый формат, только чтение»; записи `task`, `subagent`), §8.3;
  - §10 (базовые инструменты, таблица доверия, шаг 5a);
  - §11 (`tools/plan.md` → `tools/tasks.md`, перечень `tool_descriptions`);
  - §1 (дерево файлов), §16.2 (имена инструментов), §17.4 и §17.11 (перечни), §15 (пример `update_plan: allow`).

  Исторические документы этапов (`09-07-stage-2…`, `09-09-stage-4…`) не переписываются.
- [x] 0.7 Решения пользователя 2026-11-12 по Q9–Q12 внесены в design.md («Решённые вопросы», D29–D32), спецификации agent-sessions, agent-tools, agent-acp-server, agent-prompts и задачи; в документах ядра пометки «change пока не определяет» заменены правилами:
  - Q9 (D29): §17.16.2 (порт `TaskList`, `restore(announce)`, `TaskChange.op = restore`), §17.16.6 («Смена ветки», `nextId` по всему журналу), TSK-1, TSK-3, TSK-7, §17.16.8, §17.16.9 (задел общей доски), §17.6.5 шаг 7, SESM-3, §17.6.8 (`JournalTail`), §17.11.6 шаг 3, §8.3 и §8.2.4 (`SessionWriter`, запись `task`), §5.3, §13.7;
  - Q10 (D30): §6.3.8 (шаг 1 алгоритма, тест `tool_switches_test.dart`), §11.5 (комментарий шага 8 сборки промпта), §17.11.9;
  - Q11 (D31): §17.11.9 (11 схем, без пометки неопределённости);
  - Q12 (D32): §17.16.3, §17.16.6, §11.2, §11.5 — секция `tools/tasks` называет только `task_create`, правило о `task_list` — в его описании; явный `on` зависимого при выключенном якоре — ошибка «якорь выключен» (§6.3.8, D30).

  Q10 и Q11 в спецификации этого change не входят: переключателей инструментов и режима `essential` нет ни в коде (`tools.disabled` — `applied: false`), ни в утверждённых спецификациях; правила D30 и D31 переносятся в дельты спецификаций change, вводящих §6.3.8 и §17.11.9 (задача 6.2).

- [x] 0.8 Решения пользователя 2026-11-12 по Q13–Q16 (панель Agents v1 в 1.0) внесено: design.md (D19, D33, «Решённые вопросы», Q1), proposal, спецификации acp-client-kit «Список субагентов сессии» и agent-workbench-ui «Панель Agents v1», задачи итерации 5b; `delivery-roadmap.md` §6.1 (строка 9), §6.2 (пункт 9), §6.4 (этап 5 делится), §10.1 (строка 16), §10.3; `dart-agent-and-clients/12-3-desktop-display.md` A13 (шаги 2 и 6), A15 («Панель Agents v1»), DSK-26, «Как проверить»; `agent-core/17-3-subagents.md` §17.3.1 (таблица этапов). Q14 (чип и счётчик переключателя — с доской), Q15 (хвост без токенов: D25, сценарии agent-workbench-ui, acp-client-kit, codelab-tui, задачи 5.1, 5.5), Q16 (`_meta.codelab.subagent` у вложенного `agent` в сценарии «Вызовы ребёнка и внука» и фикстуре) внесены; строка D-25 `agent-parity-goals.md` помечена.

- [x] 0.9 Решение пользователя 2026-11-12 по Q17 (навыки в субагенте) внесено: design.md (D34, D19, «Решённые вопросы», Context, Risks), proposal, спецификации agent-subagents («Сборка ребёнка», «Вложенность и слоты дерева») и agent-prompts (шаг 9a, «Промпт ребёнка с навыками»), задачи итераций 2 и 2s; `agent-core/17-3-subagents.md` §17.3.3 (шаги 3, 5, 8), `agent-core/05-agent-loop.md` §5.6 (`ChildSessionSpec`). Change `add-agent-skills` не менялся.

## 1. Список задач вместо `update_plan` (итерация 1)

Сквозной срез C-20 и C-05: ядро → журнал → ACP → kit → app и CLI.

- [ ] 1.1 `[agent]` `[protocol]` `[client]` `[desktop]` Красные тесты итерации:
  - ядро:
    - `task_list_tools_test.dart` (agent-tools «Инструменты списка задач»: «Создание, разблокировка и удаление»);
    - `task_list_cycle_test.dart` («Цикл зависимостей», TSK-2);
    - golden `builtin_tools_golden_test.dart` с `task_*` (agent-tools «Golden-вывод инструментов»);
    - `task_list_journal_test.dart` (agent-sessions «Список после загрузки», «Счётчик id по всем веткам», «Восстановление при открытии»; TSK-3, D29);
    - `task_list_restore_test.dart` (agent-sessions «Восстановление с публикацией», «Восстановление списка не пишется»; TSK-1, TSK-3, D29);
    - `core/task-list-legacy-session-continues` (agent-sessions «Старая сессия с update_plan»);
    - golden-разбор `all_records.jsonl` с `task` и `plan` (agent-sessions «Golden-разбор»);
    - сборка (agent-runtime «Матрица профиля»);
    - промпты (agent-prompts «Golden на профиль и режим», «База не называет инструментов», «Секция списка задач называет только якорь»; D32);
  - ACP:
    - фикстуры `acp/prompt-task-plan`, `acp/session-load-legacy-plan`, `acp/initialize-codelab-extensions`;
    - `acp_projection_exhaustive_test.dart`: `TaskListChanged` с `op: restore` (agent-acp-server «Список новой ветки»; D29);
    - перевод `acp/prompt-update-plan` на роль `client`;
    - тест `initialize` без клиентского `_meta` (agent-acp-server «Ответ codelab-app», «Клиент CodeLab объявил расширения»);
  - kit:
    - `initialize` с `clientCapabilities._meta.codelab` (acp-protocol-client «Запрос initialize клиента CodeLab», «Агент без блока объявлений», «Будущая версия расширения»);
    - `PlanEntryView` (acp-client-kit «Метаданные пунктов плана»: три сценария);
    - `TaskOpsItem` (acp-client-kit «Операции со списком задач в ленте»: «Слияние созданий», «Отклонённая операция», «Сторонний агент»; D27);
  - CLI: REPL «План с задачами», «Тихая строка операций со списком» (codelab-cli); TUI «Ctrl+T прячет список задач» и тихая строка операций (codelab-tui, D26, D27);
  - app: widget-тесты agent-workbench-ui «Чек-лист задач с id, владельцем и блокерами» (включая «Сводка скрыта при открытой панели Plan»), «Тихие строки операций со списком задач» («Четыре создания подряд», «Ошибка операции видна»).
- [ ] 1.2 `[agent]` `TaskList`, `TaskItem`, `TaskOp`, `TaskActor`, `TaskListChanged` и четыре инструмента в `lib/src/tools/tasks/` по §17.16.2–§17.16.3. Сюда входят:
  - замок операций;
  - проверки и тексты ошибок;
  - удаление с очисткой `blocked_by`;
  - заметки о блокерах.

  `ToolServices.tasks` вместо `ToolServices.plan` (1.1, ядро; TSK-1…TSK-4).
- [ ] 1.2a `[agent]` `TaskList.restore(items, nextId:, announce:)` под замком `apply`: счётчик не убывает, при `announce: true` — один `TaskListChanged` с `TaskChange(op: restore, actor: main, changed, deleted)`; `TaskChange.op` дополняется значением `restore` (1.1, `task_list_restore_test.dart`; agent-sessions «Список задач следует ветке журнала»; TSK-1, TSK-3, D29). Вызовов из смены ветки и `JournalTail` здесь нет — их операций в коде пока нет (D29, «Что входит в этот change»).
- [ ] 1.3 `[agent]` Запись журнала `task`, разбор записей `plan` старого формата, проекция `buildTaskList`, восстановление `TaskList` при `open` без публикации. `SessionWriter`: `TaskListChanged → task` (1.1, журнал; TSK-6).
- [ ] 1.3a `[agent]` `buildTaskList`: `items` — по активной ветке, `nextId` — по всему журналу (все ветки, `items` и `deleted` записей `task`, число entries записей `plan`); `SessionWriter` на `TaskListChanged` с `op: restore` ничего не пишет (1.1, `task_list_journal_test.dart`, `task_list_restore_test.dart`; agent-sessions «Счётчик id по всем веткам», «Восстановление списка не пишется»; TSK-1, TSK-3, D29).
- [ ] 1.4 `[agent]` Удаление `UpdatePlanTool`, `PlanService`, `PlanUpdated` и типов плана ядра. Реестр `buildAgentCore`: `task_*` вместо `update_plan`. Промпты:
  - `tools/tasks.md` и `tool_descriptions/task_*.md` — свои тексты (§7а), без копирования Claude Code; `tools/tasks.md` (`tools: [task_create]`) называет только `task_create`, правило «после сжатия вызови `task_list`» — в `tool_descriptions/task_list.md` (agent-prompts «Секция списка задач называет только якорь»; D32);
  - удалить `tools/plan.md` и `tool_descriptions/update_plan.md`;
  - `gen_prompts`.

  Обновить golden промптов, профилей хоста и `update_plan.txt` (1.1, сборка и промпты; D13).
- [ ] 1.5 `[protocol]` Проекция `TaskListChanged → plan` с `_meta.codelab.task` и реплей плана из `buildTaskList` (agent-acp-server «Проекция субагентов и списка задач»: «Список задач в ходе»; «План старой сессии»). Блок `agentCapabilities._meta.codelab` с `tasks` по объявлению клиента (agent-acp-server «initialize», D9). Обновить фикстуры:
  - фикстуры с ожидаемыми схемами `update_plan`: `prompt-turn-budget-exceeded`, `prompt-max-turn-requests`, `session-new-with-mcp`;
  - клиентские фикстуры с кадром `initialize`;
  - перечень расширений §13.12 и проверка ACP-2 (1.1, ACP).
- [ ] 1.5a `[protocol]` Проекция `TaskListChanged` с `op: restore` — тот же `plan` со всем списком, пустой список — `entries: []`; строка в исчерпывающем `switch` (1.1, `acp_projection_exhaustive_test.dart`; agent-acp-server «Список новой ветки»; D29).
- [ ] 1.6 `[client]` `codelab_client_acp`: `clientCapabilities._meta.codelab` в `initialize` и терпимый разбор `agentCapabilities._meta.codelab`. `codelab_client_core`: поля `PlanEntryView`, незавершённые блокеры, метка владельца (1.1, kit). `fvm dart run build_runner build` после изменения freezed-моделей.
- [ ] 1.6a `[client]` `TaskOpsItem` в транскрипте kit: распознавание по `plan` с `_meta.codelab.task`, пришедшему во время успешного вызова `think`, разница планов, слияние подряд идущих, текст элемента; без разбора заголовков (1.1, kit; D27).
- [ ] 1.7 `[client]` REPL и `--ui tui`: тихая строка `TaskOpsItem`; формат плана `#<id> [<status>] <subject>` с владельцем и блокерами; в TUI — блок списка задач над композером с заголовком `Tasks <c>/<n> done · ctrl+t hide`, действие `toggle_tasks` (Ctrl+T) в реестре клавиш и подсказка в строке помощи; доска Ctrl+T не открывает (1.1, CLI; D26).
- [ ] 1.8 `[desktop]` Чек-лист `codelab_ui`/app: `#<id>`, метка владельца, «blocked by»; сводка над композером скрыта при открытой панели Plan; тихая строка `TaskOpsItem` (иконка списка, без рамки и тега), ошибка операции — обычной строкой (D27). `integration_test/llm_scripts/with_plan.json` переписать на `task_*`, `plan_progress_checklist_flow_test.dart` — только компиляция в `feature/*` (1.1, app).

## 2. Субагенты глубины 1 (итерация 2)

- [ ] 2.1 `[agent]` `[protocol]` `[client]` `[desktop]` Красные тесты итерации:
  - ядро:
    - `agent_tool_schema_test.dart` (agent-subagents «Enum типов», «Неверный заголовок»);
    - `subagent_tools_intersection_test.dart` («Пересечение инструментов» при `max_depth: 1`);
    - `subagent_mode_narrow_test.dart` («Смена режима родителя посреди работы ребёнка»);
    - `core/agent-two-children-parallel` (слоты и `max_per_turn` на одном уровне: «Предел слотов дерева» в варианте глубины 1, «Лимит запусков»);
    - `subagent_cancel_test.dart` («Отмена хода корня», «Отмена в момент завершения»);
    - `subagent_report_wrapper_test.dart` («Обёртка отчёта»);
    - `subagent_budget_test.dart` («Бюджет ребёнка»);
    - `subagent_journal_test.dart` (раскладка для глубины 1; agent-sessions «Дочерние журналы не в списке сессий»);
    - `core/subagent-interrupted-not-restarted` («Сбой с двумя детьми»);
    - `subagent_activity_test.dart` (вариант глубины 1);
    - конфиг (agent-configuration «Умолчания», «Диапазон глубины», «Проект не повышает глубину», «Дескрипторы в реестре», «Запись через config set», «Глубина 1»);
    - сборка (agent-runtime «Субагенты включены»);
    - `deterministic_journal_test.dart` с `agent`;
    - `subagent_protected_paths_test.dart` (agent-subagents «Защищённые пути корня у ребёнка»; D34);
    - `subagent_tools_intersection_test.dart` — вариант «Нет снимка каталога — нет skill» (поддельный инструмент `skill` в реестре родителя, без кода `add-agent-skills`; D34);
  - ACP: фикстура `acp/prompt-subagent-tool-call` (agent-acp-server «Вызов agent»); `initialize` с `subagents` и при `enabled: false` («Субагенты выключены»); `acp_projection_exhaustive_test.dart` со строками `Subagent*`;
  - признак первого кадра: agent-acp-server «Вызов agent» с `_meta.codelab.subagent {id, type}`; acp-client-kit «Вызов agent с первого кадра»; резерв `SubagentId` в `present` — id отклонённого вызова не создаёт ребёнка (D28);
  - итог: agent-subagents «Итог с потомками»; agent-acp-server «Итог субагента» (вживую, при отмене и в реплее); `summary` в финальном обновлении фикстуры `acp/prompt-subagent-tool-call`;
  - kit и клиенты: строка `agent` (acp-client-kit «Запрос одобрения от субагента», часть про строку `agent`; acp-client-kit «Итог в представлении», «Сторонний агент без итога»; agent-workbench-ui «Завершённый субагент свёрнут», «Неуспешный субагент сохраняет тег», «Без дерева — строка прогресса»; codelab-cli «Отчёт субагента в pipe», «Итог в строке вызова»; codelab-tui «Итог в статусе»).
- [ ] 2.2 `[agent]` Ключи схемы `subagents.*` базового этапа с диапазонами (`max_depth` 1–3, `max_concurrent` 1–8, `max_per_turn` 1–50 и др.) и правилом проектного слоя «только ужесточать»; дескрипторы `SettingsRegistry` (`scope: shared`, `min`/`max`, `restartRequired: false`) вместо опакового `subagents`; чтение лимитов при каждом `spawn` (agent-configuration «Ключи subagents в схеме и реестре настроек», D17, D22).
- [ ] 2.3 `[agent]` Встроенные типы `general`, `explore`, `review`, `plan` (тела — `prompts/subagent/types/*.md`, свои тексты) и снимок типов сессии из определений со `scope` `subagent | both`. `SubagentTool`: схема с `task` только у корня, проверки, описание с `nesting`/`agentList` (agent-subagents «Инструмент task и типы субагентов»).
- [ ] 2.4 `[agent]` Резерв `SubagentId` в `SubagentTool.present` до `ToolCallStarted` и передача в `SubagentSpec` (D28); `SubagentManager`, `SubagentHandle`, `SubagentTree` (слоты, FIFO, `max_per_turn`), `createChildSession`/`ChildSessionSpec`, сборка ребёнка (инструменты, режим `narrow`, модель, промпт `subagent/system`), токены, `cancel_grace`, гонка отмены и завершения, отписка поздних событий (agent-subagents «Сборка ребёнка», «Жизненный цикл и отмена»; D3, D5).
- [ ] 2.5 `[agent]` Отчёт и обёртка `<subagent-report>`, усечение `report_max_bytes`; транзитивные `toolCalls` и `usage` и `duration` в `SubagentReport`, поля `toolCalls`, `durationMs` итоговой записи `subagent` (D24); usage ребёнка в `subagentUsage` родителя; бюджет ребёнка (agent-subagents «Отчёт ребёнка», «Бюджет и usage дерева» для глубины 1).
- [ ] 2.6 `[agent]` События `SubagentStarted`/`Progress`/`Finished`, `SubagentActivity`, строка прогресса и heartbeat через `onUpdate` (agent-subagents «События потомков в потоке родителя»; D6).
- [ ] 2.7 `[agent]` Журнал: порт `SessionStore` для журнала потомка, `JsonlSessionStore` — каталог `subagents/` корня без попадания в `list` и `index.json`, заголовок `parent`, записи `subagent`, лечение `agent` в `healInterruptedTurn` (agent-subagents «Журнал субагента и прерывание»; D7).
- [ ] 2.8 `[protocol]` Проекция `agent` (`kind: think`, `_meta.codelab.subagent {id, type}` в первом `tool_call` вживую и при реплее (D28), прогресс, отчёт без обёртки, `_meta.codelab.subagent.summary` в финальном обновлении вживую и в реплее (D24), `_meta.codelab.subagent.failure` у `failed`). `Subagent*`/`SubagentActivity` — «not sent». Ключ `subagents` в блоке `initialize` (2.1, ACP).
- [ ] 2.9 `[client]` `ToolCallView.subagentSummary`, строка итога и её сокращённый вид в kit (терпимый разбор, D27); `ToolCallView.subagentCall` из `_meta.codelab.subagent` первого `tool_call` — опознание вызова `agent` с первого кадра, без него — обычный `think` (D28); `ToolRowView` строки `agent`: прогресс, отчёт, итог; REPL — итог в скобках строки вызова без «Done»; TUI — глиф ✓ и сокращённый итог без «Done», `Failed`/`Cancelled` — явно (D27). REPL — прогресс на месте только на `ansi`, отчёт до 20 строк. TUI — строка вызова (2.1, kit и CLI).
- [ ] 2.10 `[desktop]` Компактная строка вызова `agent` (D27): свёрнута по умолчанию, глиф, `Subagent <type>: <description>`, справа «N tool calls · N.Nk · время», шеврон; без тега «Done» и `#id` в свёрнутом виде, «Failed»/«Cancelled» остаются; под работающей — строка прогресса; раскрытие — отчёт (2.1, app; D24, D27).
- [ ] 2.11 `[agent]` Реализация тестов 2.1 про навыки и пути: политика ребёнка получает набор защищаемых путей корневой сессии (пути хоста и сессии) вместо нового расчёта; инвариант «нет снимка каталога — нет `skill`» в сборке набора ребёнка (agent-subagents «Сборка ребёнка», «Защищённые пути корня у ребёнка», «Нет снимка каталога — нет skill»; D34, SUB-1).

## 2s. Стыковка с навыками (итерация 2s, решение пользователя 2026-11-12, Q17)

Начинается после слияния кода change `add-agent-skills` (его итерация 2: `skill`, `SkillCatalog`, `BoundedEnv.readOnlyRoots`) в `develop`; если он там уже к началу итерации 2 — задачи идут внутри итерации 2 (design.md, D34). Change `add-agent-skills` при этом не меняется.

- [ ] 2s.1 `[agent]` Красные тесты: `subagent_skills_test.dart` (agent-subagents «Каталог ребёнка — снимок родителя», «Тип без skill», «Файлы навыка пользователя у ребёнка», «Активные навыки родителя не наследуются», «Корень навыков выше cwd у ребёнка»); golden `test/prompts/golden/subagent-general-skills.txt` (agent-prompts «Промпт ребёнка с навыками»).
- [ ] 2s.2 `[agent]` Реализация 2s.1: поле снимка каталога в `ChildSessionSpec` — тот же `SkillCatalog` родителя без вызова `SkillFilesSource`; `PromptInputs.skills` ребёнка из снимка; `readOnlyRoots` и `execInReadOnlyRoots` env ребёнка — каталоги навыков снимка и каталог выноса; доверие Q30 и исключения E1–E3 по тем же каталогам; корни навыков сессии попадают к ребёнку через набор путей корня из 2.11 (D34). Проверки: `prompts:check`, `web-compile`.

## 3. Запрос разрешения потомка (итерация 3)

- [ ] 3.1 `[agent]` `[protocol]` `[client]` `[desktop]` Красные тесты итерации:
  - ядро: `subagent_permission_prefix_test.dart` (agent-permissions «Два ребёнка спрашивают одновременно», «Запрет всегда нельзя обойти через ребёнка»); `allow_always_scope_test.dart` («Всегда для типа субагента»); снятие запроса при отмене ребёнка (PERM-7);
  - ACP: фикстура `acp/prompt-subagent-permission` (agent-acp-server «Запрос разрешения ребёнка»; acp-golden-fixtures «Агентский прогон запроса ребёнка»); переподключение с ожидающим запросом ребёнка — тот же `toolCallId`;
  - kit: acp-client-kit «Запрос ребёнка», «Запрос без сведений о субагенте»;
  - kit: acp-client-kit «Путь внука без дерева»;
  - CLI: codelab-cli «Одобрение ребёнка»; codelab-tui «Одобрение ребёнка в TUI» (строка пути, D27);
  - app: widget-тесты agent-workbench-ui «Запрос одобрения от субагента под строкой корня»: «Ребёнок просит команду», «Вопрос внука не раскрывает дерево».
- [ ] 3.2 `[agent]` `SubagentPermissionGate`: цепочка `toolCallId`, префикс `title`, сведения о потомке в запросе, FIFO дерева в `SubagentTree`, `waiting` с `waitingFor: approval`, общее хранилище решений корня, нет gate → отказ (agent-permissions «Разрешения потомка через gate корневой сессии»; D8).
- [ ] 3.3 `[protocol]` `AcpPermissionGate`: `toolCall._meta.codelab.subagent` вместе с `critical` (3.1, ACP).
- [ ] 3.4 `[client]` `SubagentRequester` в `PendingApprovalView` и `ToolCallView`, `pathTypes` и строка пути (`…` для неизвестных звеньев); строка `<путь> wants to run` и заголовок задачи в REPL и TUI (3.1, kit и CLI; D27).
- [ ] 3.5 `[desktop]` Блок одобрения потомка под строкой `agent` корневого уровня: путь «review › explore wants to run» (заголовок задачи — в подсказке и раскрытии), команда, панель решения; деревья предков не раскрываются; после решения — тег исхода под строкой корня (3.1, app; D27).

## 4. Вложенность до 3 и задачи у субагентов (итерация 4)

- [ ] 4.1 `[agent]` `[protocol]` Красные тесты итерации:
  - ядро:
    - `core/subagent-nested-no-deadlock` и `subagent_nested_slots_test.dart` (agent-subagents «Нет взаимоблокировки при одном слоте», «Возвращающийся родитель раньше нового ребёнка», «Предел слотов дерева», «Лимит запусков считает внуков»; SUB-23);
    - `subagent_tree_budget_test.dart` («Бюджет корня останавливает внука»);
    - `subagent_tools_intersection_test.dart` при `max_depth: 3` (SUB-24);
    - `subagent_activity_test.dart` («Адрес события внука»);
    - `subagent_nested_skills_test.dart` («Внук получает пути и снимок корня»; часть про навыки — если итерация 2s уже выполнена, иначе добавляется в 2s.1; D34);
    - `subagent_journal_test.dart` («Раскладка внука») и рекурсивное лечение;
    - agent-permissions «Вопрос внука»;
    - `task_list_owner_test.dart` (agent-tools «Потомок меняет чужой пункт», «Назначение пункта ребёнку»);
    - промпт ребёнка (agent-prompts «Промпт ребёнка», «Описание agent по глубине»);
  - ACP: фикстура `acp/prompt-subagent-nested-permission` (agent-acp-server «Запрос разрешения внука»).
- [ ] 4.2 `[agent]` Глубина и `agent` у потомков до `max_depth`. Передача слота ожидающим родителем, приоритетная очередь возвращающихся, отмена ожидающего в очереди. `waitingFor: subagents`, `activeChildren` в снимке (D3; SUB-5, SUB-23, SUB-24).
- [ ] 4.3 `[agent]` Бюджет предков на границе шага потомка и транзитивный usage (D4; SUB-11).
- [ ] 4.4 `[agent]` Плоская обёртка `SubagentActivity` для внуков. Журналы внуков в `subagents/` корня с `parent.depth`/`rootSessionId`. Рекурсивный `healInterruptedTurn`. Сужение режима по цепочке (D6, D7; SUB-2, SUB-9).
- [ ] 4.5 `[agent]` Детский вариант инструментов задач (только `status` своих пунктов). Поле `agent.task` с проверкой до запуска и операцией `assign` при получении слота, лог `task.assign.skipped`. Секция `subagent/task` (D10; TSK-4).
- [ ] 4.6 `[protocol]` `_meta.codelab.subagent` с `depth`/`path`/`parentToolCallId` корня для внуков; фикстура вложенного запроса в агентском прогоне против встроенного агента и `serve --stdio` (4.1, ACP).

## 5. Шаги потомков деревом (итерация 5, этап 2)

- [ ] 5.1 `[protocol]` `[client]` `[desktop]` Красные тесты итерации:
  - ACP: фикстуры `acp/prompt-subagent-tool-tree` (кадр `tool_call` `call_1/call_2` несёт `_meta.codelab.subagent` `{id, type}` внука — Q16, D28) и `acp/session-load-subagent-tool-tree` (agent-acp-server «Шаги потомков деревом»: «Вызовы ребёнка и внука», «Запрос разрешения в строке своего вызова», «Клиент без согласия», «Висящие вызовы при отмене», «Реплей дерева»); `initialize` с `subagentToolCalls` (agent-acp-server «Клиент CodeLab объявил расширения»); загрузчик фикстур кладёт журналы детей из `setup.sessions` в `subagents/` по заголовку `parent`;
  - kit: acp-client-kit «Дерево вызовов потомков» (три сценария); acp-protocol-client «Запрос initialize клиента CodeLab» с `subagentToolCalls`;
  - kit: acp-client-kit «Хвост из пяти вызовов» — без токенов (D25, Q15);
  - CLI: codelab-cli «Шаги ребёнка с отступом»; TUI — хвост свёрнутой строки и вложенные строки раскрытой;
  - app: widget-тесты agent-workbench-ui «Свёрнутые шаги ребёнка», «Хвост работающего субагента»; вопрос внука при дереве — вызов виден на своём месте после раскрытия, блок под строкой корня («Вопрос внука не раскрывает дерево»);
  - фикстуры: `summary` в финальных обновлениях `acp/prompt-subagent-tool-tree` и реплея `acp/session-load-subagent-tool-tree`.
- [ ] 5.2 `[protocol]` Проекция `SubagentActivity` вызовов потомков в `tool_call`/`tool_call_update` с цепочкой `toolCallId` и `_meta.codelab.parentToolCallId` только по согласию `subagentToolCalls`; закрытие висящих вызовов поддерева при терминальном вызове `agent`; реплей вызовов потомков из их журналов; ключ `subagentToolCalls` в блоке `initialize` (5.1, ACP; D21).
- [ ] 5.3 `[agent]` Порт чтения журналов потомков для реплея (`AgentSession.replay` отдаёт события детей с адресом, как `SubagentActivity`) без записи и без lease ребёнка (5.1, «Реплей дерева»; D21).
- [ ] 5.4 `[client]` `clientCapabilities._meta.codelab.subagentToolCalls`; `ToolCallView.parentToolCallId`, дерево в `SessionView` без дублей при реплее; строки потомков с отступом в REPL и TUI; хвост в `SessionView` (три последних вызова поддерева и `moreCount`) и в свёрнутой строке TUI (5.1, kit и CLI; D25).
- [ ] 5.5 `[desktop]` Вложенные строки потомков в строке `agent`: свёрнуты по умолчанию, счётчик шагов, хвост из трёх последних вызовов и `+N more tool calls` без токенов под свёрнутой строкой работающего вместо строки прогресса, справа — `N tool calls` (Q15); тихие строки операций потомков со списком; вопрос потомка дерево не раскрывает (5.1, app; D25, D27).

## 5b. Панель Agents v1 (итерация 5b, решение пользователя 2026-11-12, Q13)

Только клиент: kit и app; протокол, ядро и CLI не меняются (design.md, D33). Integration-тест app в `feature/*` только компилируется (AGENTS.md §21).

- [ ] 5b.1 `[client]` `[desktop]` Красные тесты итерации:
  - kit — `session_subagents_test.dart` (acp-client-kit «Список субагентов сессии»: «Строки ребёнка и внука», «Итог завершённого субагента», «Отмена и отказ», «Ожидание одобрения потомка», «Одобрение без дерева», «Пункты списка у субагента», «Реплей без дублей в списке», «Поздний кадр после завершения», «Время работающего субагента», «Сторонний агент без признака»); источник кадров — фикстуры `acp/prompt-subagent-tool-tree`, `acp/session-load-subagent-tool-tree`, `acp/prompt-subagent-nested-permission` в роли `client` и сценарные `session/update` теста; часы `ClientWorkspace` — поддельные;
  - app — widget-тесты панели (agent-workbench-ui «Панель Agents v1»: «Панель появляется с первым субагентом», «Сторонний агент», «Ребёнок, внук и итог», «Ожидание одобрения и переход к нему», «Дерево шагов выбранного потомка», «Переход к строке в ленте», «Пункты списка у субагента», «Загрузка сессии с субагентами», «Только данные v1»); предикат доступности — в тесте раскладки дока (сохранённая открытая панель Agents без строк не даёт вкладки и остаётся в раскладке);
  - `codelab_ui` — widget-тест организма панели: строки с отступом по глубине, счётчики без нулей, поля без данных не рисуются, ключи `agents-row-<toolCallId>`, `agents-go-to-approval-<toolCallId>`, `agents-show-in-transcript-<toolCallId>`.
- [ ] 5b.2 `[client]` `codelab_client_core`: `SubagentRowView`, состояния строки и счётчики, `SessionView.subagents` как функция транскрипта, ожидающих одобрений и плана; `startedAt` по часам, внедрённым в `ClientWorkspace` (по умолчанию системные), формат длительности общий с итогом D24; терминальное состояние окончательно; без разбора `title` и строки прогресса (5b.1, kit; D33, AGENTS.md §9). `fvm dart run build_runner build` после изменения freezed-моделей; `melos run web-compile`.
- [ ] 5b.3 `[desktop]` `codelab_ui`: организм панели Agents — заголовок со счётчиками, строки с отступом, метки `#N`, отметка и действие «Go to approval», «Show in transcript», дерево шагов выбранной строки на компактных строках ленты (D27); `CodeLabOrganismPreviews` — пример панели (5b.1, `codelab_ui`).
- [ ] 5b.4 `[desktop]` `apps/codelab_desktop`: `ToolPane.agents` с предикатом «у сессии в фокусе есть строка `SessionView.subagents`», пункт палитры; UI-часть выбора строки по сессиям по образцу `TranscriptViewCubit`; прокрутка ленты к строке `agent` и к блоку одобрения, раскрытие пути через `TranscriptViewCubit`, короткая подсветка; тик времени работающих строк раз в секунду, пока панель видна и сессия занята (5b.1, app; D33).
- [ ] 5b.5 `[desktop]` `integration_test/agents_pane_flow_test.dart` со сценарием LLM: ребёнок с внуком и запрос разрешения внука — панель, «Go to approval», ответ в ленте, дерево шагов; в `feature/*` — только компиляция, прогон на устройстве — в `release/*` (AGENTS.md §21).

## 6. Ручная проверка, документы и Definition of Done (итерация 6)

- [ ] 6.1 `[desktop]` `[client]` Ручной прогон на macOS-сборке разработчика с настоящим провайдером (без устройства в CI, AGENTS.md §21):
  - список задач из 5+ пунктов с зависимостями;
  - `agent` `explore` и `review` параллельно;
  - ребёнок запускает внука; дерево шагов потомков в app и REPL;
  - панель Agents v1: строки ребёнка и внука, «Go to approval», «Show in transcript», дерево шагов выбранного потомка, загрузка сессии с субагентами;
  - запрос разрешения ребёнка и внука в app и в REPL;
  - отмена хода во время работы внука;
  - загрузка сессии старого формата с `update_plan`.

  Найденные дефекты — подзадачами 6.1x с красным тестом и исправлением.
- [ ] 6.2 `[agent]` Документы и код не расходятся: §17.3, §17.16, §13 — по фактическим именам и текстам. Правила D29–D31 для ещё не реализованных операций (смена ветки §17.6.5, откат к метке §17.11.6, `JournalTail` §17.6.8, переключатели §6.3.8 вместе с ошибкой «якорь выключен», режим `essential` §17.11.9) остаются в документах ядра с тестами `session_branch_task_list_test.dart`, `session_read_only_tail_test.dart`, `tool_switches_test.dart`, `core/discover-tools-mount` — для change, вводящих эти операции. Вложенные `AGENTS.md`:
  - `codelab_agent_core` — `lib/src/subagents/`, `lib/src/tools/tasks/`, запрет копирования текстов Claude Code;
  - `codelab_agent_acp` — новые расширения;
  - `codelab_client_core` — разбор `_meta.codelab.*`.
- [ ] 6.3 `[agent]` `agent-parity-goals.md`: статусы и доказательства C-05, C-06 (этапы 1 и 2), C-20 по зелёным тестам и фикстурам. `delivery-roadmap.md` §6.4 — отметка «этапы 1 и 2 и панель Agents v1 выполнены»; §10.1 строка 16 — часть M4.
- [ ] 6.4 Definition of Done (ниже) выполнен; change готов к архивации по просьбе пользователя.

## Definition of Done

- Все задачи итераций 0–6 и 5b отмечены. Красные тесты каждой итерации были в истории до кода.
- Зелёные проверки:
  - сценарии спецификаций change: `agent-subagents`, `agent-tools`, `agent-loop`, `agent-sessions`, `agent-permissions`, `agent-runtime`, `agent-prompts`, `agent-configuration`, `agent-acp-server`, `acp-protocol-client`, `acp-client-kit`, `agent-workbench-ui`, `codelab-cli`, `codelab-tui`, `acp-golden-fixtures`;
  - критерии матрицы: C-05 (`acp/prompt-task-plan`, `acp/session-load-legacy-plan`, `acp/prompt-update-plan` с ролью `client`), C-06 (`core/agent-two-children-parallel`, `core/subagent-nested-no-deadlock`, `acp/prompt-subagent-tool-call`, `acp/prompt-subagent-permission`, `acp/prompt-subagent-nested-permission`, `acp/prompt-subagent-tool-tree`, `acp/session-load-subagent-tool-tree`), C-20 (`core/task-list-create-update`, `core/task-list-cycle-rejected`).
- Инварианты:
  - SUB-1…SUB-12 (SUB-12 — в редакции этапа 2: без согласия `subagentToolCalls` вызовы потомков не отправляются), SUB-23, SUB-24 и TSK-1…TSK-6 покрыты тестами; TSK-7 — механизмом `restore` (`task_list_restore_test.dart`), вызовы из смены ветки — в change, вводящем её (D29);
  - висящие вызовы поддерева закрываются при завершении вызова `agent`;
  - финальное обновление каждого вызова `agent` несёт `_meta.codelab.subagent.summary`; клиенты без `summary` показывают строку как прежде;
  - поздние события отменённого ребёнка не доходят до клиента;
  - гонка «отмена ↔ завершение» даёт один результат;
  - панель Agents v1: список субагентов без дублей при реплее и повторной загрузке, поздний кадр не возвращает завершённого субагента в `running`, решение по одобрению принимается только в ленте (D33).
- ACP:
  - сервер отправляет только расширения из требования «Расширения протокола этапа 4»;
  - сторонний клиент без `clientCapabilities._meta.codelab` получает прежний ответ `initialize` и не получает вызовов потомков;
  - новых методов и корневых полей нет.
- Allowlist ядра (PKG-2) и правила сторожа не изменились, `melos run guard` зелёный. `melos run web-compile` зелёный для ядра и kit.
- Тексты промптов и описаний инструментов написаны для CodeLab. Источник поведения указан в §17.3.13 и §17.16.8; записи в `THIRD_PARTY_NOTICES.md` не потребовалось — или она добавлена, если ревью нашло воспроизведённый фрагмент.
- В коде нет заготовок этапов 3–6: полей `background`, методов `followUp`, ключей конфига других этапов, `_codelab/subagents/*`; в панели Agents v1 нет кнопок и разделов этапов 3–6 («Stop», «Open transcript», «Background jobs»).
- CI pull request каждой итерации зелёный (затронутое), полный `melos run check` зелёный на `develop` после merge (AGENTS.md §21).
- Слово task в именах инструментов, событий и записей означает только пункт списка задач (D20); единственное сознательное исключение — slash-команда `/tasks` для человека (D23).
- Документы и код не расходятся (6.2), матрица и дорожная карта обновлены (6.3).
