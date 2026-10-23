Задачи идут парами «тест → реализация» (§9.0, правило 3). В скобках — задача этапа 2 (`dart-agent-and-clients/09-07-stage-2-loop-tools-permissions.md`) и требование спецификации.

Пути — в `packages/dart/codelab_agent_core/`, если не указано иное. Группы задач по итерациям (design.md, D13):
- группы 1–4 — итерация 1 (ход в памяти с `read` и `edit`);
- группы 5–7 — итерация 2 (команды и разрешения, вместе с итерацией 1 change `add-agent-core-permission-policy`);
- группы 8–11 — итерация 3 (полный набор инструментов и супервизоры MVP);
- группы 12–14 — итерация 4 (промпты, сквозной сценарий, web-smoke, вместе с итерацией 2 change разрешений).

Каждая итерация — отдельный PR в `develop`.

## 1. ExecutionEnv и граница рабочей папки (2.1)

- [x] 1.1 Тест (agent-execution-env «Граница рабочей папки BoundedEnv»): `test/env/bounded_env_test.dart` — таблица §4.4, включая `rejects sibling directory with shared prefix` (`/proj_evil`); пути Windows `/c/proj2/x` и `/c/proj/../proj2/x` при корне `/c/proj`; ссылка наружу и новый файл за ссылкой внутрь на fake env с `PathResolver`; внутренний env не получает вызовов для отклонённого пути (ENV-3). `test/env/bounded_env_capabilities_test.dart` — обёртка не реализует `DirectoryListing` без внутреннего, с ним проверяет путь `listDir` (ENV-4); `test/util/posix_path_test.dart` (красные)
- [x] 1.2 Реализовать `lib/src/util/result.dart`, `lib/src/util/posix_path.dart`, `lib/src/env/execution_env.dart` (порты, `FileError`, `ExecError`, `ExecOptions`, `ExecResult`, `FileStat`, опциональные возможности), `lib/src/env/bounded_env.dart` (`BoundedEnv.wrap` с вариантами по возможностям) — 1.1 зелёные
- [x] 1.3 Тест (agent-execution-env «Порт ExecutionEnv и ошибки как значения», «MemoryExecutionEnv»): общий набор `test/env/execution_env_contract.dart` и его прогон `test/env/memory_env_test.dart` — диапазон строк, запись с созданием родителей, `notFound`, `isDirectory`, `notText`, `notDirectory`, `listDir` по порядку, `modified` из `FakeClock`, `exec` → `shellUnavailable`, ни одного исключения (ENV-1) (красный)
- [x] 1.4 Реализовать `lib/src/env/memory_env.dart` — 1.3 зелёный; экспорт портов, `Result` и `MemoryExecutionEnv` из барели (design.md, D1)

## 2. События и конфигурация цикла (2.3)

- [x] 2.1 Тест (agent-loop «События AgentEvent»): `test/loop/agent_events_test.dart` — иерархия закрыта (`switch` по всем вариантам компилируется без `default`), `TurnEndReason`, `ToolOutcome`, `AgentErrorClass`, `LoopNudgeOrigin`/`LoopNoteOrigin`; `TurnBudget` по умолчанию `maxSteps: 50`; `ModeChanged` добавляется в задаче 7.4 вместе с `ModeId` (красный)
- [x] 2.2 Реализовать `lib/src/loop/agent_events.dart`, `lib/src/loop/loop_config.dart` (`AgentLoopConfig`, хуки, `Block`, `ResultOverride`, `StepUpdate`, `StepResult`, `ResponseVerdict`, `MessageQueue`; `estimateTokens` и `emergencyCompact` объявлены, design.md, D7), `lib/src/loop/turn_budget.dart`, `SessionId`/`TurnId` — 2.1 зелёный

## 3. Ядро инструментов (2.5)

- [x] 3.1 Тест (agent-tools «Контракт инструмента и реестр»): `test/tools/registry_test.dart` — порядок схем стабилен, дубликат заменяет и зовёт `onDuplicate`, неверное имя → `ArgumentError`, `tier` по умолчанию `exec` (TOOL-4, TOOL-5) (красный)
- [x] 3.2 Реализовать `lib/src/tools/agent_tool.dart` (`AgentTool`, `ToolContext`, `ToolServices`, `ToolExecutionResult`, `ToolPresentation`, `Location`, `FileDiff`, `ToolExecutionOutcome`, `ToolCallContent`), `lib/src/tools/registry.dart` — 3.1 зелёный
- [x] 3.3 Тест (agent-tools «Валидация и приведение аргументов»): `test/tools/validator_test.dart` — таблица приведения §6.3.2 строка за строкой, `default`, `null`, union с `null`, вложенные объекты и массивы, `enum` после приведения, формат ошибки (TOOL-2, T-12) (красный)
- [x] 3.4 Реализовать `lib/src/tools/validator.dart`, `lib/src/util/canonical_json.dart` — 3.3 зелёный
- [x] 3.5 Тест (agent-tools «Парность вызовов в запросе к модели»): `test/tools/pairing_repair_test.dart` — каждый вид нарушения §6.3.3 и пример оттуда, отчёт (TOOL-6) (красный)
- [x] 3.6 Реализовать `lib/src/tools/pairing.dart` — 3.5 зелёный
- [x] 3.7 Тест (agent-tools «Единая точка исполнения», «Усечение вывода»): `test/tools/executor_test.dart` — порядок шагов D9 на fake-инструменте (инструмента нет в схемах шага, ошибка валидации, `preflight`, `Block` первого хука и неисполнение второго, отмена до исполнения, `afterToolCall` только после `execute`); `test/tools/tool_throws_test.dart` — `StateError('x')` → `x` (TOOL-3); `test/tools/truncate_test.dart` — голова и хвост на границах 2000 строк и 50 КиБ, первая строка больше лимита, тексты уведомлений (TOOL-9); `test/tools/tool_executor_guard_test.dart` — `.execute(` только в `executor.dart` (TOOL-1) (красные)
- [x] 3.8 Реализовать `lib/src/tools/executor.dart`, `lib/src/tools/truncate.dart` — 3.7 зелёные

## 4. Цикл, read и edit (2.4, 2.6)

- [x] 4.1 Тест (agent-tools «Встроенные инструменты MVP»): `test/tools/builtin/read_test.dart` (картинки `read` — задача 8.1) — формат `<n>| `, `offset`/`limit`, усечение длинной строки, бинарный файл, пустой файл, тексты ошибок env; `test/tools/builtin/edit_test.dart` — 0, 1, 2 совпадения, `aa` в `aaa`, CRLF, BOM, `identical`, пустой `oldText`, вывод с фрагментом diff и `FileDiff` (TOOL-8, T-01, T-04) (красные)
- [x] 4.2 Реализовать `lib/src/tools/builtin/read.dart`, `edit.dart`, `lib/src/tools/unified_diff.dart` — 4.1 зелёные
- [x] 4.3 Тест (agent-loop «Функция хода runAgentLoop», «Хуки и сборка payload», «Пакет инструментов»): `test/loop/loop_sequences_test.dart` — эталоны: текст, один вызов, два параллельных, `length` с вызовом (LOOP-5), ошибка провайдера с `AgentError`, отмена во время стрима (LOOP-1, LOOP-3, LOOP-9); `test/loop/hook_throws_test.dart` (LOOP-1); `test/loop/payload_immutability_test.dart` (LOOP-7); `test/loop/duplicate_tool_ids_test.dart` (LOOP-11); `test/loop/pairing_retry_test.dart` (design.md, D8); `test/loop/sequential_mode_test.dart` (LOOP-4) (красные)
- [x] 4.4 Реализовать `lib/src/loop/payload_builder.dart`, `lib/src/loop/agent_loop.dart` (`runAgentLoop` §5.4 без пустого ответа, бюджета и steering — группа 10) — 4.3 зелёные
- [x] 4.5 Тест (agent-loop «Agent, steering и follow-up»): `test/loop/agent_test.dart` — `prompt` → события по порядку подписки, `waitForIdle` после всех подписчиков; `test/loop/slow_subscriber_test.dart` (LOOP-2); `test/loop/prompt_while_running_test.dart` (LOOP-10); `abort` → `TurnEnded(cancelled)` (красные)
- [x] 4.6 Реализовать `lib/src/loop/agent.dart` (очередь emit — design.md, D5) — 4.5 зелёные
- [ ] 4.7 Проверка итерации 1: ход на `ScriptedStreamFunction` с `read` и `edit` на `MemoryExecutionEnv` под `BoundedEnv` (`test/loop/read_edit_turn_test.dart`); уточнения контракта D14 внесены в документ ядра §5.2, §5.3, §5.4, §5.6, §6.2; `fvm dart run melos run check` зелёный; PR итерации 1

## 5. Пакет codelab_agent_io и LocalExecutionEnv (2.2)

- [x] 5.1 Создать `packages/dart/codelab_agent_io`: `pubspec.yaml` (`codelab_agent_core`, `meta`, `async`), вложенный `AGENTS.md` (design.md, D2), запись в `workspace:` корневого `pubspec.yaml`, правило в `packages/dart/codelab_architecture_tests/test/support/rules.dart`
- [x] 5.2 Тест (workspace-architecture «Автоматический сторож границ пакетов»): `pubspec_allowlist_test.dart` — allowlist `codelab_agent_io`; негативный тест сторожа на временном пакете с `package:acp_protocol/` (красный)
- [x] 5.3 Реализовать проверку allowlist `codelab_agent_io` в стороже — 5.2 зелёный
- [x] 5.4 Тест (agent-execution-env «LocalExecutionEnv пакета codelab_agent_io»): `packages/dart/codelab_agent_io/test/local_execution_env_test.dart` — общий набор `execution_env_contract.dart` во временном каталоге; `BoundedEnv` с реальными ссылками (`/proj_evil`, ссылка наружу); `test/host_path_test.dart` (`C:\proj` ↔ `/c/proj`); `test/local_exec_test.dart` — ненулевой код → `Ok`, `trap "" TERM; sleep 60` с таймаутом 1 с → `timeout` не позже 6 с (ENV-5), вывод больше лимита → хвост и `truncated`, окружение без `CODELAB_TEST_SECRET` и с `GIT_TERMINAL_PROMPT=0` (ENV-6, P-11), `read` из `stdin` → EOF, отмена убивает внука (T-09) (красные)
- [x] 5.5 Реализовать `lib/src/env/local_execution_env.dart`, `process_tree.dart`, `output_buffer.dart`, `host_path.dart`, экспорт из `lib/codelab_agent_io.dart` — 5.4 зелёные

## 6. Инструмент exec (2.6)

- [x] 6.1 Тест (agent-tools «Встроенные инструменты MVP», «Ограда недоверенного вывода»): `test/tools/builtin/exec_test.dart` на fake `Shell` — `timeout` вне `1..3600` с заметкой, код 0 и ненулевой, таймаут и отмена с длительностью, `shellUnavailable`, `(no output)`, хвост вывода, `onOutput` → `ToolCallProgress`; `test/tools/fence_test.dart` — `exec curl …` огорожен с экранированным маркером, `exec dart test` и `exec httpie` — нет (TOOL-10, P-15) (красные)
- [x] 6.2 Реализовать `lib/src/tools/builtin/exec.dart`, `lib/src/tools/fence.dart` (ограда, сетевые команды §10.6, `untrusted_paths`), доверие через `outputTrust` инструментов (design.md, D9) — 6.1 зелёные

## 7. Runtime и минимальная сборка (2.9)

- [x] 7.1 Тест (agent-runtime «Профили хостов и сужение»): `test/host/host_profile_test.dart` — `agent-serve` и `embedded-cli` с явным состоянием трёх capability и причинами (HOST-1), `narrowed` с расширением → `HostWiringException` (HOST-2), неизвестный профиль → `ArgumentError`, режим по умолчанию `standard` (красный)
- [x] 7.2 Реализовать `lib/src/host/host_profile.dart` — 7.1 зелёный
- [x] 7.3 Тест (agent-runtime «Минимальная сборка buildAgentCore», «AgentRuntime и AgentSession в памяти»): `test/host/build_agent_core_test.dart` — матрица `agent-serve` на `MemoryExecutionEnv` с выключенным `shellExec` (схемы, `CorePlan.offReasons`), `shellExec` над `MemoryExecutionEnv` → `HostWiringException` (HOST-3), без gate — отказ `no approval interface is available` (PERM-5), `wiring_single_env_test.dart` (ENV-2), политика первым звеном, хуки хоста последними; `test/runtime/agent_session_test.dart` — ход через прямой API, поздний подписчик, `setMode` и `ModeChanged`, `cacheKey` = id сессии, `listSessions`, `dispose`; `test/host/host_wiring_guard_test.dart` — вне `build_agent_core.dart` в `lib/` нет `ToolRegistry(`, `Agent(` и `AgentRuntime(` (HOST-6) (красные)
- [x] 7.4 Реализовать `lib/src/host/services.dart` (`AgentCoreServices`, `CoreConfig` этапа 2), `lib/src/host/build_agent_core.dart`, `lib/src/runtime/agent_runtime.dart`, `agent_session.dart`, событие `ModeChanged`, экспорт из барели — 7.3 зелёные
- [ ] 7.5 Проверка итерации 2 (вместе с итерацией 1 change `add-agent-core-permission-policy`): ход «read → edit → exec» через `buildAgentCore` на `LocalExecutionEnv` во временном каталоге с fake gate (`packages/dart/codelab_agent_io/test/local_turn_test.dart`); `fvm dart run melos run check` зелёный локально на macOS и в CI (design.md, риски); PR итерации 2

## 8. write, ls, search, update_plan и блокировка пути (2.5, 2.6)

- [ ] 8.1 Тест (agent-tools «Блокировка пути», «Встроенные инструменты MVP»): `test/tools/parallel_edit_test.dart` — 10 параллельных `edit` одного файла (TOOL-7, T-05); `test/tools/builtin/write_test.dart`; `ls_test.dart` (T-06); `search_test.dart` — regex и литерал, ошибка синтаксиса, пропуск каталогов и бинарных, glob `**/*.dart`, `{a,b}`, лимиты и уведомления (T-07); `test/tools/glob_test.dart`; `update_plan_test.dart` — `PlanUpdated` до `ToolCallFinished`, заметка о нескольких `in_progress` (C-05); `read` картинок (§6.4, шаг 2): `ImageContent` при `BinaryFiles` и `supportsImages`, иначе текст ошибки (красные)
- [ ] 8.2 Реализовать `lib/src/tools/path_lock.dart`, `glob.dart`, `builtin/write.dart`, `ls.dart`, `search.dart`, `update_plan.dart`, `PlanService` — 8.1 зелёные
- [ ] 8.3 Тест: `test/tools/builtin_tools_golden_test.dart` — каждый инструмент на `MemoryExecutionEnv` против golden; `read`/`search` под `node_modules` огорожены (P-15) (красный)
- [ ] 8.4 Golden-файлы `test/tools/golden/*.txt` и правки до совпадения — 8.3 зелёный

## 9. Предохранитель неверных вызовов (2.5, C-08)

- [ ] 9.1 Тест (agent-tools «Предохранитель повторяющихся неверных вызовов»): `test/tools/misuse_breaker_test.dart` — критерий `core/misuse-breaker-blocks-repeat`: семь вызовов `read {"limit":"ten"}`, ключ по каноническому JSON, отказы разрешения и ненулевой `exec` не блокируются, `enabled: false`; со стороны цикла — новый ход начинает с пустого счётчика, два одинаковых вызова одного пакета засчитываются оба (TOOL-11, LOOP-16) (красный)
- [ ] 9.2 Реализовать `lib/src/tools/misuse.dart` (`MisuseLimits`, `MisuseBreaker`) и шаги 1a и 9a в `executor.dart` — 9.1 зелёный

## 10. Пустой ответ, бюджет, steering и follow-up (2.4)

- [ ] 10.1 Тест (agent-loop «Пустой ответ модели»): `test/loop/empty_completion_test.dart` — критерий `core/empty-completion-retried`, случаи (а)–(д) §5.9 (случай (е) с журналом — этап 3) (LOOP-14, LOOP-15) (красный)
- [ ] 10.2 Тест (agent-loop «Бюджет хода»): `test/loop/budget_test.dart` — шаги, токены, стоимость при известных ценах, время по `FakeClock` без ожидания одобрения (LOOP-12, design.md, D6) (красный)
- [ ] 10.3 Тест (agent-loop «Agent, steering и follow-up»): `test/loop/steering_test.dart` — steering во время пакета после пакета, FIFO одним опросом, 25 при лимите 20 (LOOP-8, CAN-6); follow-up после естественной остановки в том же ходе (красный)
- [ ] 10.4 Реализовать в `agent_loop.dart` пустой ответ (§5.4.1, логи `loop.empty_response`), бюджет с `ApprovalWaitMeter`, опросы steering и follow-up; `final_response_hook_test.dart` — без хука `Accept`, `Revise` даёт шаг с заметкой в payload, `Hold` помечает `TurnEnded.held` (LOOP-13) — 10.1–10.3 зелёные

## 11. Проверка итерации 3

- [ ] 11.1 Тест «хуки, разрешения первыми» (`core/hooks-order-approval-first`, C-12): через `buildAgentCore` хук хоста видит вызов только после `Allowed`, исключение в `afterToolCall` — результат-ошибка, а не сбой хода
- [ ] 11.2 `fvm dart run melos run check` зелёный; PR итерации 3

## 12. Промпты (2.8)

- [ ] 12.1 Тест (agent-prompts «Промпты в Markdown и генерация констант», «Шаблоны»): `test/prompts/gen_prompts_test.dart` — ошибки генератора с путём файла (PR-4), `tools/*.md` без `tools`; `test/prompts/template_test.dart` — `\{{`, значение с `{{x}}`, неполный набор → `ArgumentError`; `test/prompts/prompts_sync_test.dart` (PR-1); `test/prompts/no_prompt_literals_test.dart` (PR-2) (красные)
- [ ] 12.2 Реализовать `tool/gen_prompts.dart` (`dart_style` в `dev_dependencies`, режим `--check`), `lib/src/prompts/template.dart`, файлы `prompts/**/*.md` этапа 2 (design.md, D11), сгенерированный `lib/src/prompts/prompts.g.dart`, melos-скрипт `prompts:check` в `check` — 12.1 зелёные
- [ ] 12.3 Тест (agent-prompts «Детерминированная сборка системного промпта»): `test/prompts/compose_test.dart` — golden `test/prompts/golden/<profile>-<mode>.txt` для `agent-serve`, `embedded-cli` и режимов `standard`, `plan` (PR-3); `prompt_sections_tools_test.dart` — без `ls` нет `tools/listing`, без `write` и `edit` нет `tools/edit`, `tools/read` остаётся; тест-сторож базы (PR-6) (красные)
- [ ] 12.4 Реализовать `lib/src/prompts/compose.dart`; `description` встроенных инструментов берётся из `Prompts.toolDescriptions*`; `buildAgentCore` собирает промпт по плану, `CorePlan.promptSections` — 12.3 зелёные

## 13. Сквозной сценарий (2.10)

- [ ] 13.1 Тест (agent-runtime «Сквозной сценарий и детерминизм»): `test/scenarios/read_edit_exec_test.dart` — scripted LLM читает, правит и запускает команду на `MemoryExecutionEnv` с фейковым `Shell`; последовательность `AgentEvent`, запросы к gate с `rawInput`, `locations` и diff, итоговые файлы; `same script yields identical event sequence on 100 runs` (PKG-6); парность после отмены — `core/pairing-survives-cancel` (красный)
- [ ] 13.2 Довести реализацию до зелёного 13.1; дубликаты, появившиеся в итерациях 1–4, устранены (§9.0, правило 8д)

## 14. Web-smoke и завершение этапа

- [ ] 14.1 `test/web_smoke/main.dart` проводит ход через `buildAgentCore` на `MemoryExecutionEnv`: scripted модель вызывает `read` и отвечает текстом (workspace-architecture «Web-smoke проводит ход с инструментом»); `fvm dart run melos run web-compile` зелёный
- [ ] 14.2 `public_api_test.dart`: барель не экспортирует `src/loop/agent_loop.dart`, `src/loop/agent.dart`, `src/tools/executor.dart` (PKG-5, design.md, D1)
- [ ] 14.3 Definition of Done этапа: `fvm dart test packages/dart/codelab_agent_core packages/dart/codelab_agent_io` зелёный; `melos run guard` и `melos run web-compile` зелёные; строки матрицы C-01, C-05 (ядро), C-07, C-08, C-12, T-01, T-03, T-04, T-05, T-06, T-07, T-08, T-09 (ядро), T-12, P-08, P-11, P-15 имеют доказательства; `docs/architecture/` и документ ядра правятся там, где реализация уточнила контракт; PR итерации 4
- [ ] 14.4 Перед архивированием: `openspec validate add-agent-core-loop-and-tools --strict`; архивировать после change `add-agent-core-llm-contract` (design.md, риски) и вместе с `add-agent-core-permission-policy`; заполнить Purpose новых спецификаций
