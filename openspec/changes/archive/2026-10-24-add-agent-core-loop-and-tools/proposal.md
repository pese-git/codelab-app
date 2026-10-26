## Why

Этап 1 дал ядру LLM-контракт: `StreamFunction`, адаптеры, декораторы и `ScriptedStreamFunction`. Но модель пока не может ничего сделать: в ядре нет ни цикла, ни инструментов, ни доступа к файлам и командам. Этап 2 (`docs/architecture/proposals/dart-agent-and-clients/09-07-stage-2-loop-tools-permissions.md`) строит работающего агента в памяти. Ход вызывает модель, исполняет вызовы инструментов под проверкой разрешений и границей рабочей папки и доступен через прямой API `AgentRuntime` / `AgentSession`.

Без этого слоя не начинаются этапы 3 (журнал и сжатие) и 4 (ACP-адаптер), а срез P0 (`delivery-roadmap.md` §5) не собирается. Этап закрывает цели паритета уровня Must C-01, T-05, T-06, T-07, T-12 и P-08, ядерную часть T-01, T-03, T-04, T-08, T-09 и C-05, а также Should C-07, C-08, C-12, P-11 и P-15 (`agent-parity-goals.md`). Источник решений — принятый документ ядра `agent-core-architecture.md`: §4, §5, §6, §10 (минимальная сборка), §11 и §1.3 (раскладка).

Разрешения — отдельный change `add-agent-core-permission-policy` (задача 2.7). Этот change даёт ему точку подключения: цепочку `beforeToolCall`, первым звеном которой встаёт политика.

## What Changes

- **ExecutionEnv (2.1).** `Result`/`Ok`/`Err`, порты `FileSystem`, `Shell`, `ExecutionEnv` и опциональные возможности `DirectoryListing`, `BinaryFiles`, `PathResolver`. Нормализация POSIX-пути, декоратор `BoundedEnv` (граница рабочей папки по сегментам и `realpath` существующего префикса), `MemoryExecutionEnv` (§4, ENV-1…ENV-5).
- **Пакет `codelab_agent_io` (2.2).** `LocalExecutionEnv` на `dart:io` (§4.6):
  - файлы;
  - `Process.start` без наследования окружения, базовый набор переменных по allowlist;
  - закрытый `stdin`;
  - кольцевой буфер вывода;
  - завершение дерева процессов по таймауту и отмене не позже 5 с.

  Пакет получает правило в стороже, allowlist зависимостей и вложенный `AGENTS.md`.
- **События и конфигурация цикла (2.3).** Закрытая иерархия `AgentEvent` в объёме MVP, `AgentLoopConfig` с хуками `transformContext`, `beforeToolCall`, `afterToolCall`, `prepareNextStep`, `beforeFinalResponse` (только интерфейс), очереди steering и follow-up, `TurnBudget` (§5.2, §5.3).
- **Цикл (2.4).** Чистая функция `runAgentLoop` (алгоритм хода §5.4, пакет инструментов §5.5, сборка payload, пустой ответ модели §5.4.1) и `Agent` с состоянием: `prompt`, `steer`, `followUp`, `abort`, `waitForIdle`, `subscribe` (LOOP-1…LOOP-16).
- **Инструменты (2.5).** `AgentTool`, `ToolRegistry` и единая точка исполнения `ToolExecutor` (§6.3.1). Валидатор JSON Schema с приведением типов, ремонт парности вызовов, `PathLock`, усечение вывода, ограда недоверенного вывода, предохранитель повторяющихся неверных вызовов `MisuseBreaker`, `canonicalJson` (TOOL-1…TOOL-11).
- **Встроенные инструменты (2.6).** `read`, `write`, `edit`, `ls`, `search`, `exec`, `update_plan` по §6.4, с текстами ошибок и уведомлений документа ядра.
- **Промпты (2.8).** `prompts/**/*.md` MVP, генератор `tool/gen_prompts.dart` с режимом `--check`, `PromptTemplate`, `composeSystemPrompt` с правилом «секция подключается, только если включены все её инструменты» (§11, PR-1…PR-6 в объёме MVP).
- **Runtime в памяти и минимальная сборка (2.9).**
  - `AgentRuntime` / `AgentSession` с сессиями в памяти;
  - `HostProfile` с профилями `agent-serve` и `embedded-cli`, `narrowed`;
  - `AgentCoreServices`;
  - `buildAgentCore`: env-цепочка, реестр по capability, политика первым хуком, промпт, `CorePlan` (§10, HOST-1…HOST-4, HOST-6).
- **Сквозной сценарий (2.10).** Scripted LLM читает, правит и запускает команду на `MemoryExecutionEnv` с фейковым `exec`. Проверяются последовательность `AgentEvent`, запросы к `PermissionGate` и итоговые файлы; 100 прогонов дают одну и ту же последовательность.
- **Web-smoke ядра** проводит ход с инструментом `read` на `MemoryExecutionEnv`.

Не входит:
- журнал сессии, `session/load`, сжатие, вынос результата (этап 3);
- `AcpClientExecutionEnv`, `ListingOverlayEnv`, `AcpPermissionGate`, режимы ACP и `session/set_mode` (этап 4);
- `EnvVarsEnv` (переменные `exec.env` и секреты из конфигурации), загрузка конфигурации, `tools.disabled` (T-26), MCP-инструменты (этап 8);
- редакция секретов `Redactor` (этап 3, P-10): шаг 8b единой точки исполнения пока пропускается;
- супервизоры после MVP: heartbeat, финальный гейт, дедлайн; `trySteer`, субагенты, картинки в `read` и всё помеченное в документе ядра «после MVP».

## Capabilities

### New Capabilities
- `agent-execution-env`: доступ ядра к файлам и процессам — порты и `Result`, граница рабочей папки `BoundedEnv`, `MemoryExecutionEnv`, `LocalExecutionEnv` пакета `codelab_agent_io`.
- `agent-loop`: ход агента — функция `runAgentLoop`, события `AgentEvent`, хуки, бюджет хода, очереди steering и follow-up, сборка payload, обработка пустого ответа, `Agent` с состоянием.
- `agent-tools`: контракт инструмента, реестр, единая точка исполнения, валидация и приведение аргументов, парность вызовов, блокировка пути, усечение, ограда недоверенного вывода, предохранитель неверных вызовов и встроенные инструменты MVP.
- `agent-prompts`: Markdown-исходники промптов, генератор Dart-констант, шаблоны и детерминированная сборка системного промпта.
- `agent-runtime`: публичный API `AgentRuntime` / `AgentSession` в памяти, профили хостов и минимальная сборка `buildAgentCore`.

### Modified Capabilities
- `workspace-architecture`:
  - «Границы пакетов monorepo» — в workspace появляется пакет `codelab_agent_io`, а web-smoke ядра проводит ход с инструментом `read`;
  - «Автоматический сторож границ пакетов» — правило и allowlist зависимостей для `codelab_agent_io`.

## Impact

- **`packages/dart/codelab_agent_core`:**
  - новые каталоги `lib/src/env/`, `loop/`, `tools/` (с `builtin/`), `prompts/`, `runtime/`, `host/`;
  - новые файлы `lib/src/util/result.dart`, `posix_path.dart`, `canonical_json.dart`;
  - каталог `prompts/` и `tool/gen_prompts.dart`, сгенерированный `lib/src/prompts/prompts.g.dart` (коммитится);
  - расширенный барель и тесты.
- **Новый пакет `packages/dart/codelab_agent_io`.**
  - Зависимости: `codelab_agent_core`, `meta`, `async` (подмножество allowlist §1.2).
  - Пакет добавляется в `workspace:` корневого `pubspec.yaml` и в правила сторожа.
  - Тесты работают с реальными процессами во временном каталоге на Dart VM (`AGENTS.md` §21).
- **Зависимости ядра.** В `dependencies` новых нет, allowlist PKG-2 не меняется. Генератору промптов нужен `dart_style` (`DartFormatter`, §11.3); он подключается как `dev_dependency` (их allowlist не ограничивает, §1.2) и в `lib/` не попадает.
- **Документы.** Вложенный `AGENTS.md` пакета `codelab_agent_io`. `docs/architecture/` правится только там, где реализация уточняет контракт (design.md).
- **Не меняются:** клиенты, ACP-контракты, поведение `codelab_app` и `acp_*` пакетов.
