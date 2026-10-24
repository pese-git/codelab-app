## Context

Этап 1 (`add-agent-core-llm-contract`) положил в `codelab_agent_core` LLM-контракт и порты детерминизма. Этап 2 строит поверх них работающего агента в памяти. Контракты, алгоритмы, инварианты и тексты для модели уже описаны в принятом документе ядра:

- §4 — ExecutionEnv;
- §5 — цикл;
- §6 — инструменты;
- §10 — сборка и профили;
- §11 — промпты;
- §1.3 — раскладка.

Этот документ фиксирует только то, чего в документе ядра нет:
- какая часть контракта MVP входит в этап 2, а какая подключается позже;
- раскладка кода и состав нового пакета;
- решения на стыках с другими этапами;
- порядок итераций.

Где ниже нет отдельного решения, действует документ ядра как есть.

Связанный change `add-agent-core-permission-policy` (задача 2.7) реализует `PermissionPolicy` и встаёт первым звеном цепочки `beforeToolCall`, которую даёт этот change. Сквозной сценарий (2.10) и минимальная сборка (2.9) опираются на оба change.

## Goals / Non-Goals

**Goals:**
- Ход агента в памяти: модель → вызовы инструментов → результаты → следующий шаг → `TurnEnded`. Ход работает на `ScriptedStreamFunction` и на настоящей `StreamFunction` из фабрики этапа 1.
- Граница рабочей папки, в которую нельзя выйти через `..`, символическую ссылку или соседний каталог с общим префиксом имени (ENV-3, P-08).
- Встроенные инструменты MVP с текстами документа ядра. `LocalExecutionEnv` с честным завершением дерева процессов (ENV-5, T-09).
- Точка подключения разрешений: цепочка `beforeToolCall`, первое звено которой — политика (PERM-1).
- Прямой API `AgentRuntime` / `AgentSession` и минимальный `buildAgentCore`. Ими пользуются срез P0 (этап 4) и сквозной сценарий.
- Детерминизм: один сценарий на `FakeClock`, `SequentialIdGenerator` и `Random(42)` даёт одну и ту же последовательность событий (PKG-6).

**Non-Goals:**
- журнал, `loadSession`, `replay`, `listSessions` по хранилищу, сжатие, вынос результата, редакция секретов (этап 3);
- `AcpClientExecutionEnv`, `ListingOverlayEnv`, `AcpPermissionGate`, режимы ACP (этап 4);
- конфигурация, `EnvVarsEnv`, `tools.disabled`, MCP, `projectContext` (этап 8);
- супервизоры и инструменты после MVP;
- пользовательский steering `trySteer` (после MVP, C-03).

## Decisions

### D1. Раскладка и публичный API

Файлы — по §1.3 документа ядра:
- `lib/src/util/result.dart`, `posix_path.dart`, `canonical_json.dart`;
- `lib/src/env/` (`execution_env.dart`, `bounded_env.dart`, `memory_env.dart`);
- `lib/src/loop/` (`agent_events.dart`, `loop_config.dart`, `turn_budget.dart`, `payload_builder.dart`, `agent_loop.dart`, `agent.dart`);
- `lib/src/tools/` (`agent_tool.dart`, `registry.dart`, `executor.dart`, `validator.dart`, `pairing.dart`, `path_lock.dart`, `truncate.dart`, `fence.dart`, `unified_diff.dart`, `glob.dart`, `misuse.dart`, `builtin/*.dart`);
- `lib/src/prompts/`, `lib/src/runtime/`, `lib/src/host/`.

Барель `lib/codelab_agent_core.dart` дополнительно экспортирует:
- типы env: порты, `Result`, `FileError`, `ExecError`, `MemoryExecutionEnv`;
- события `AgentEvent`;
- контракт инструмента `AgentTool` с сопутствующими типами — понадобится MCP-адаптеру этапа 8 и хостам с собственными инструментами;
- `AgentRuntime`, `AgentSession`, `SessionSpec`;
- `HostProfile`, `AgentCoreServices`, `buildAgentCore`, `CorePlan`.

Барель НЕ экспортирует `runAgentLoop`, `Agent`, `ToolExecutor`, `ToolRegistry`, `BoundedEnv`, `PathLock`, валидатор и встроенные инструменты. Это внутренние классы цикла (PKG-5); тесты ядра импортируют их из `src/`. `public_api_test.dart` получает проверку `export 'src/loop/agent_loop.dart'` (§1.6).

### D2. Пакет `codelab_agent_io`

- Новый пакет `packages/dart/codelab_agent_io`:
  - `lib/codelab_agent_io.dart` экспортирует `LocalExecutionEnv`;
  - реализация лежит в `lib/src/env/` (`local_execution_env.dart`, `process_tree.dart`, `output_buffer.dart`, `host_path.dart`).
- `dependencies`: `codelab_agent_core`, `meta`, `async` — подмножество allowlist пакета из §1.2.
- Правила сторожа:
  - в `rules.dart` встаёт правило `['package:flutter/', 'package:acp_']` (уже записано в комментарии файла);
  - `pubspec_allowlist_test.dart` получает второй тест — allowlist `codelab_agent_io` из §1.2.
- Пакет получает вложенный `AGENTS.md` (§9.0, правило 7): правила пакета, сторож, TDD, интеграционные тесты только на Dart VM.
- Тесты `LocalExecutionEnv` используют реальные процессы `/bin/sh` во временном каталоге. Это интеграционные тесты на Dart VM, они входят в `melos run check` (`AGENTS.md` §21).

### D3. Пути Windows

Ядро работает только с POSIX-путями (§4.4). `LocalExecutionEnv` на Windows приводит путь хоста к виду ядра и обратно функциями `toCorePath` / `toHostPath` (`host_path.dart`): `C:\proj\a.txt` ↔ `/c/proj/a.txt`, буква диска в нижнем регистре.

- Функции чистые и тестируются на любой ОС.
- Таблица `BoundedEnv` получает строки `/c/proj` против `/c/proj2` и `/c/proj/../proj2` — это закрывает пункт «Windows-пути» задачи 2.1.
- Завершение дерева процессов на Windows (`taskkill /T /F`) реализуется по §4.6, но CI его не проверяет: раннер — `ubuntu-latest`. Это риск ниже. Вопрос §16.3 документа ядра остаётся открытым.

### D4. Сессия этапа 2 — в памяти

`AgentSession` этапа 2 реализует подмножество контракта §5.6:

| Член | Что делает |
|---|---|
| `id` | идентификатор сессии |
| `events` | широковещательный поток; поздний подписчик получает события текущего хода с начала |
| `prompt` | запуск хода |
| `cancel` | отмена хода |
| `setMode` | смена режима |

`AgentRuntime` реализует:

| Член | Что делает |
|---|---|
| `createSession` | создание сессии |
| `listSessions()` | сессии этого процесса в порядке создания, без фильтра хранилища |
| `dispose` | освобождение ресурсов |

Остальные члены интерфейсов добавляются в своих этапах без изменения перечисленных сигнатур:
- `loadSession` и `replay` — этап 3, с журналом;
- `setConfigOption` — этап 4;
- члены после MVP — позже.

`SessionId` и `TurnId` — extension type над `String`, значения выдаёт `IdGenerator` хоста. Формат id журнала (§8.4) задаёт этап 3. `SessionSpec` этапа 2 содержит:
- `cwd`;
- `mode` (`ModeId` из change разрешений);
- `model` (`ModelRef`);
- `ports` (`SessionHostPorts`: env, gate, logger — каждый необязателен, по умолчанию берётся из `AgentCoreServices`);
- `extraBeforeToolCall`;
- `extraAfterToolCall`.

`mcpServers` и `skills` добавляются в этапах 8 и после MVP.

### D5. Последовательность событий и очередь emit

`Agent` владеет одной асинхронной очередью событий: цепочкой `Future`. Каждое событие ждёт обработки предыдущего всеми подписчиками по порядку подписки (LOOP-2). Параллельный пакет инструментов отдаёт `ToolCallFinished` в эту же очередь в момент завершения вызова (LOOP-3).

Через ту же очередь эмитят:
- сервис плана — событие `PlanUpdated`. `update_plan` ждёт его доставки до своего `ToolCallFinished`;
- `ToolCallProgress` от `onUpdate`. Перед `ToolCallFinished` цикл дожидается уже отправленных прогрессов (§5.5, шаг 5).

`ToolServices` этапа 2: `plan` (`PlanService`), `clock`, `logger`, `approvalWait`. Поля `spill`, `jobs` и поля после MVP добавляются в своих этапах.

### D6. Бюджет хода и ожидание одобрения

На каждый ход цикл создаёт `ApprovalWaitMeter` и кладёт его в `ToolServices.approvalWait`. Политика разрешений добавляет в него длительность каждого `PermissionGate.request` (§7.4, `budget.excludeWait`). Проверка `maxDuration` на границе шага использует `elapsed − approvalWait.total` по `Clock` хоста (LOOP-12).

`maxCost` проверяется только при известных ценах модели (`ModelRef.cost != null`). `deadline` (§17.12.5) не входит в этап 2: значение `BudgetLimit.deadline` объявлено, но не выставляется.

### D7. Поля `AgentLoopConfig` этапа 3 и позже

`estimateTokens` и `emergencyCompact` объявлены и в этапе 2 всегда `null`. Шаг 4 сборки payload и шаг 14a хода с `null` выполняются как «сжатия нет»:
- ответ `overflow` от провайдера — обычная ошибка шага;
- оценка размера до запроса не делается.

`deadline` и `imageRefs` (после MVP) в этапе 2 не объявляются: их добавление — расширение конфигурации без изменения существующих полей.

### D8. Ошибка парности от провайдера

Шаг 14 хода повторяет запрос один раз, если ответ — `ErrorEvent` с классом `badRequest` и `errorMessage` совпадает с выражением `tool[_ ]?(use|call|result)` без учёта регистра. Так описывают нарушение парности OpenAI (`tool_call_id`) и Anthropic (`tool_use` / `tool_result`).

Повтор пересобирает payload с ремонтом (§6.3.3). Вторая такая ошибка — обычная ошибка шага (`TurnEnded(failed)`). Ответ с ошибкой, после которого был повтор, в транскрипт не входит.

### D9. Шаги единой точки исполнения этапа 2

Единая точка исполнения (§6.3.1) реализует шаги 1, 1a, 2, 3, 3a, 4, 5, 6, 7, 8a, 8c (только усечение), 8d, 9, 9a и 10.

Шаги, которые добавятся позже, вставляются в уже существующий порядок, а сигнатура `ToolExecutor` не меняется:
- шаг 0 (`rewriteArgs`) и шаг 8- (подготовка картинок) — после MVP;
- шаг 3b (`prepare`) — после MVP. В контракте `AgentTool` метод `prepare` уже есть с реализацией по умолчанию, но этап 2 его не вызывает;
- шаг 8b (редакция) — этап 3;
- вынос результата в шаге 8c — этап 3.

Доверие вывода (шаг 8a) в этапе 2 объявляют сами инструменты через `outputTrust` (уточнено в итерации 2): у профилей этапа 2 (`agent-serve`, `embedded-cli`) таблица §10.6 совпадает с таблицей §6.3.6, поэтому отдельная `OutputTrustPolicy` профиля появится вместе с профилями `mobile` и `web` (этап 10), где `search` всегда доверенный. Правила:
- `read` и `search` — `untrusted` для путей под `tools.untrusted_paths`. По умолчанию это `node_modules`, `.dart_tool`, `vendor`; конфиг их пока не меняет, список передаётся константой сборки;
- `exec` — `untrusted` для сетевых команд по списку §10.6, иначе `trusted`;
- остальные встроенные инструменты — `trusted`.


### D10. Валидатор, glob и regex — свой код

- Валидатор JSON Schema реализует подмножество §6.3.2 в `tools/validator.dart`.
- Glob для `search` реализует синтаксис §6.4 в `tools/glob.dart`.
- Сторонние пакеты не берутся, allowlist PKG-2 не меняется. Подмножество маленькое, а приведение типов §6.3.2 нестандартно для готовых валидаторов.
- `search` использует `RegExp` Dart; это поведение задокументировано в схеме инструмента.

### D11. Генератор промптов

- `tool/gen_prompts.dart` реализует алгоритм §11.3:
  - форматирует результат `DartFormatter` из `dart_style`; пакет подключается как `dev_dependency`;
  - режим `--check` сравнивает результат с файлом на диске побайтово.
- `test/prompts/prompts_generated_test.dart` вызывает функцию генератора напрямую (без процесса) и сравнивает с `lib/src/prompts/prompts.g.dart`.
- Melos-скрипт `prompts:check` входит в `check`.
- Тексты промптов пишутся для CodeLab по-английски по §11.7, проходят ревью как код и не копируются из сторонних проектов (`AGENTS.md` §5).
- Файлы этапа 2:
  - `system/base.md`, `system/untrusted.md`, `modes/plan.md`;
  - `tools/read.md`, `tools/edit.md`, `tools/listing.md`, `tools/exec.md`, `tools/plan.md`;
  - `tool_descriptions/*.md` для семи встроенных инструментов.
- Файлы следующих этапов: `mcp.md` и `project_context.md` — этап 8, `compaction/*.md` — этап 3.

### D12. Минимальная сборка `buildAgentCore`

- **`HostCapability`** этапа 2 содержит три значения: `shellExec`, `fileListing`, `interactiveApproval`. Только у них в этапе 2 есть реализации. Остальные значения §10.2 добавляются с подсистемами:
  - `compaction`, `sessionPersistence` — этап 3;
  - `mcp`, `projectContext` — этап 8;
  - значения после MVP — позже.

  Это расширение закрытого перечисления внутри ядра; внешнего кода, который перебирает его исчерпывающе, нет.
- **`HostProfile.of`** знает `agent-serve` и `embedded-cli` с состояниями из таблицы §10.4 для трёх capability. Остальные профили добавляются на этапах 4, 7 и 10.
- **`buildAgentCore`** выполняет шаги §10.7: 1 (сужение по `gate` и `DirectoryListing`; `shellExec` над заглушкой `exec` → `HostWiringException`), 2, 4 без `EnvVarsEnv`, 5a–5b, 5e, 6, 7, 9, 10 и 11.
- **`CoreConfig`** этапа 2 — `defaultModel` (`ModelRef`), `permissions` (режим и правила из change разрешений) и `budget`. Загрузка из файлов — этап 4/8; хост и тесты передают значения напрямую.
- **`streamFunction`** передаётся хостом: фабрика этапа 1 или `ScriptedStreamFunction` в тестах. Шаг 8 §10.7 (сборка `StreamFunction` из конфига) — этап 4, вместе с конфигурацией бинаря.

### D13. Итерации и TDD

Задачи идут парами «тест → реализация» (§9.0, правило 3); красные тесты коммитятся до кода. Итерации (§9.0, правило 8):

1. **Ход в памяти с `read` и `edit`.** Задачи 2.1, 2.3, 2.4, ядро 2.5, `read` и `edit` из 2.6. Цепочка `beforeToolCall` уже есть; тесты подключают хук напрямую.
2. **Команды и разрешения — завершение среза P0 этапа 2.**
   - Этот change: 2.2 (`codelab_agent_io`), `exec` и 2.9.
   - Change `add-agent-core-permission-policy`: итерация 1 (режимы × уровни, ключ «разрешить всегда», gate, headless).
3. **Полный набор инструментов и супервизоры MVP.** `write`, `ls`, `search`, `update_plan`, `PathLock`, ограда, `MisuseBreaker`, пустой ответ, бюджет, steering и follow-up.
4. **Промпты, сквозной сценарий, web-smoke.** Задачи 2.8 и 2.10, web-smoke. Change разрешений: итерация 2 (критические шаблоны, лексер, критические пути правок).

Каждая итерация — отдельный PR в `develop` из `feature/add-agent-core-loop-and-tools`. Ветка удаляется после слияния и создаётся заново от `develop` для следующей итерации. Изменения change разрешений идут в том же PR, что и итерация, в которую они входят.

### D14. Уточнения контракта, найденные в итерации 1

Реализация уточнила контракт документа ядра. Документ правится в том же PR (§9.0, правило 8е):

- **`ToolExecutor`** — интерфейс в две фазы, а не функция: `announce` (шаг 1, `present` и `ToolCallStarted`), `complete` (шаги 1a–10) и `abandon` (вызов последовательного пакета, оставшийся после отмены). Параллельный пакет объявляет все вызовы по порядку ответа и только потом исполняет их одновременно (§5.5). Без этого асинхронный `present` одного вызова мог бы обогнать другой. Данные вызова от цикла приходят в `ToolInvocation`: сессия, токен, имена схем шага, `emit`, цепочки хуков.
- **`present(args, ctx)` асинхронный и получает `ToolContext`.** `edit` строит diff для запроса разрешения, читая файл через env сессии (PERM-6), а синхронный `present(args)` этого не может.
- **`ToolContext.stepTools`** — имена схем текущего шага. Тексты ошибок упоминают только доступные модели инструменты (суффикс ` Use ls to list it.`, §6.4).
- **`AgentTool.truncatesOutput`.** `read` и `exec` усекают вывод сами со своим уведомлением. Для остальных инструментов точка исполнения усекает голову с общим уведомлением `[Output truncated: showing the first N lines of M.]`, так что TOOL-9 соблюдается и для инструментов без своего усечения.
- **`MessageStarted` ответа** эмитится на первом блоке, а ответ без блоков — на терминальном событии. Тогда ошибка парности до первого блока повторяется (D8) без начатого и не законченного сообщения; повтор не эмитит второй `StepStarted`.
- **`Agent`** получает `systemPrompt` и `tools` в конструкторе: их нет в `AgentLoopConfig`.
- **`MemoryExecutionEnv` сохраняет BOM в начале файла** (`utf8.decode` его отбрасывает): `edit` должен записать его обратно.

Итерация 2 добавила:

- **`permissionPattern(args, cwd)`.** Шаблон пути §7.5 — «относительно корня после нормализации», значит инструменту нужен корень сессии.
- **`ToolCancelled`.** `exec` при отмене отдаёт модели свой текст `[Command was cancelled after <t> s]` с outcome `cancelled`. `CancelledException` по-прежнему даёт общий текст `Tool call was cancelled`.
- **`ToolServices.approvalWait`** (`ApprovalWaitMeter`) — счётчик ожидания gate за ход (D6). Политика добавляет в него время каждого вопроса, сессия сбрасывает его в начале хода.
- **`sliceLines` и `decodeUtf8Strict`** экспортирует барель ядра: срез строк и строгий UTF-8 с BOM у `MemoryExecutionEnv` и `LocalExecutionEnv` одни и те же.
- **Системный промпт сессии** в итерации 2 пустой; его собирает `composeSystemPrompt` в задаче 12.4.

Итерация 3 добавила:

- **`AgentTool.lockPath(args)` и `PathLock.reserve`.** Блокировку пути берёт точка исполнения, а какой путь меняет вызов, знает инструмент. Место в очереди занимается при `announce`, в порядке ответа, по сырым аргументам: иначе порядок правок одного файла зависел бы от того, чей хук разрешений ответит раньше (TOOL-7). Шаг 6 ждёт `ticket.acquired`, билет освобождается на любом пути завершения.
- **`ToolContext.supportsImages`** (через `ToolInvocation`). `read` отдаёт `ImageContent`, только если модель шага принимает картинки, а модели в `ToolContext` нет.
- **`PlanService.publish` и публичный `Agent.emit`.** План эмитится через очередь агента, поэтому `PlanUpdated` приходит между `ToolCallStarted` и `ToolCallFinished` своего вызова (D5). Сессия задаёт `publish` после создания агента.
- **`AgentLoopConfig.approvalWait` и `logger`.** Цикл читает тот же `ApprovalWaitMeter`, что и политика, и считает время хода за вычетом прироста ожидания с начала хода — сброс счётчика сессией для этого не нужен. `logger` нужен логам `loop.empty_response` (§5.4.1).
- **Граница лимита бюджета — `>=`.** Лимит исчерпан, когда значение его достигло.
- **`MisuseLimits` проверяется `assert`.** `ConfigException` (§15.4) появится вместе с загрузчиком конфигурации на этапах 4 и 8.
- **`TurnInfo`** — поля §17.12.4. **`ListMessageQueue`** — очередь `Agent` в памяти; **`SteeringItem`** несёт `origin`.
- **Заметка `Revise`** передаётся в `buildPayload` готовым `UserMessage` со временем по `Clock` хоста: ядро не читает системные часы (PKG-6).
- **`search`:** ссылка читается как файл (ссылка на каталог даёт ошибку чтения и пропускается); glob поддерживает `[!abc]`, незакрытые `{` и `[` понимаются буквально; длинная строка совпадения обрезается до 200 символов без суффикса.
- **Регистрация в `buildAgentCore`** — порядок §10.7, шаг 5: `read`, `write`, `edit`, `update_plan`, затем `exec` (shellExec), `ls` и `search` (fileListing).

## Risks / Trade-offs

- **[Перенос лишней сложности документа ядра в этап 2]** → в этап входит только перечисленное в задачах 2.1–2.10 и в D4, D9, D12. Поля и шаги следующих этапов не объявляются заранее, кроме `estimateTokens` и `emergencyCompact` (D7): без них сигнатура `AgentLoopConfig` изменилась бы на этапе 3.
- **[Ошибки парности дают 400 провайдера]** → тест парности на каждом пути отмены и ошибки (`pairing_repair_test.dart`, `loop_sequences_test.dart`) и повтор по D8.
- **[Завершение дерева процессов на macOS и Windows не проверяется CI]** (раннер `ubuntu-latest`) → алгоритм §4.6 использует `ps -A -o pid=,ppid=`, одинаковый на macOS и Linux. Локальный прогон `melos run check` на macOS разработчика — часть проверки итерации 2. Windows-ветка (`taskkill`) — ручная проверка до этапа 9.
- **[Тест таймаута `exec` зависит от времени ОС]** → таймауты тестов в секундах с запасом, `trap "" TERM` проверяет SIGKILL. ENV-5 проверяется как «не позже 5 с», а не точным временем.
- **[Детерминизм 100 прогонов ломают реальные таймеры]** → сценарий 2.10 идёт на `FakeClock` и `MemoryExecutionEnv` без реального `exec`: фейковый `Shell` отвечает из таблицы.
- **[Два change одного этапа расходятся]** → сквозной сценарий и `buildAgentCore` проверяют их вместе. Итерации 2 и 4 сливают изменения обоих change одним PR.
- **[Delta `workspace-architecture` правит то же требование, что и change этапа 1]** → текст «Границы пакетов monorepo» в этой delta включает изменения этапа 1. Change этапа 1 архивируется раньше (задача 13.6), поэтому порядок слияния спецификаций сохраняется.

## Migration Plan

Только новый код ядра, новый пакет и тесты; поведение клиентов не меняется. Откат — revert PR итерации.

## Open Questions

- Нет. Вопрос Windows-путей (§16.3 документа ядра) остаётся открытым на уровне ядра; для этапа 2 его закрывает D3.
