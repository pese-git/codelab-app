# 9.7. Этап 2 — Цикл, инструменты, разрешения

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Proposed. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.6. Этап 1 — LLM](09-06-stage-1-llm.md) · [Оглавление](../dart-agent-and-clients.md) · [9.8. Этап 3 — Сессии и сжатие](09-08-stage-3-sessions.md) →

**Цель.** Работающий агент в памяти: ход с вызовами инструментов, проверкой разрешений и
границей рабочей папки, доступный через прямой API `AgentRuntime` / `AgentSession`.

**Задачи.** Пути — в `packages/dart/codelab_agent_core/`, если не указано иное.

1. **2.1. ExecutionEnv:** `lib/src/env/execution_env.dart` (порт и capability-интерфейсы),
   `lib/src/util/result.dart`, `lib/src/env/bounded_env.dart` (алгоритм §4.3),
   `lib/src/env/memory_env.dart` (`MemoryExecutionEnv`). Тест `test/env/bounded_env_test.dart`: `/proj_evil`
   при `cwd=/proj`, `..`, симлинк наружу, новый файл в несуществующем каталоге, Windows-пути
   (`C:\proj` против `C:\proj2`).
2. **2.2. Пакет `packages/dart/codelab_agent_io`** с `lib/src/env/local_execution_env.dart` (файлы,
   `Process.start` с `env` по allowlist, kill дерева процессов по `CancelToken`, лимит вывода).
   Тест `test/local_execution_env_test.dart` на временном каталоге.
3. **2.3. События и хуки:** `lib/src/loop/agent_events.dart` (sealed иерархия по документу ядра
   §5), `lib/src/loop/loop_config.dart` (хуки, очереди steering и follow-up),
   `lib/src/loop/turn_budget.dart`.
4. **2.4. Цикл:** `lib/src/loop/agent_loop.dart` (чистая функция цикла, алгоритм — документ ядра
   §5) и `lib/src/loop/agent.dart` (состояние, `prompt`, `steer`, `followUp`, `abort`,
   `waitForIdle`). Тест `test/loop/agent_loop_test.dart`: `TurnEnded` ровно один и последний,
   в том числе при исключении в хуке; `length` → все вызовы получают ошибку «аргументы обрезаны».
5. **2.5. Инструменты:** `lib/src/tools/agent_tool.dart`, `registry.dart` (коллизия имён —
   ошибка), `validator.dart` (JSON Schema с приведением типов), `executor.dart`
   (единственная точка исполнения), `pairing.dart` (у каждого вызова есть результат,
   при восстановлении — синтетический результат и событие), `path_lock.dart` (последовательная
   запись в один путь при параллельных вызовах).
6. **2.6. Встроенные инструменты:** `lib/src/tools/builtin/read.dart`, `write.dart`,
   `edit.dart` (точное совпадение фрагмента, ошибка при нуле или нескольких совпадениях),
   `ls.dart`, `search.dart`, `exec.dart`, `update_plan.dart`. Имена инструментов решены
   (agent-core-architecture §16.2): `read`, `write`, `edit`, `ls`, `search`, `exec`, `update_plan`;
   `design.md` change только ссылается на решение. В MVP ни один встроенный инструмент не
   переопределяет `preflight`, проверки `redact.block` нет (она — после MVP, §6.3.1 шаг 3a,
   §17.12.7). `ls` и `search` требуют `DirectoryListing`: здесь они работают на
   `MemoryExecutionEnv` и `LocalExecutionEnv`; в `agent-serve` по stdio — на
   `ListingOverlayEnv` (`lib/src/env/listing_overlay_env.dart`: `listDir` — от локального env,
   чтение, запись и `exec` — от `AcpClientExecutionEnv`; agent-core-architecture §4.7, §10.4),
   который появляется в задаче 4.3.
7. **2.7. Разрешения:** `lib/src/permissions/gate.dart` (порт),
   `policy.dart` (первый хук `beforeToolCall`), `pattern.dart` (ключ
   «инструмент + шаблон аргументов»), `shell_lexer.dart`, `critical_patterns.dart`, `modes.dart`. Тест
   `test/permissions/policy_is_first_hook_test.dart`: инструмент, зарегистрированный любым
   способом, не исполняется без решения политики; `test/permissions/allow_always_key_test.dart`:
   «разрешить всегда» для `exec npm test` не разрешает `exec rm -rf /`.
8. **2.8. Промпты:** `prompts/*.md`, генератор `tool/gen_prompts.dart` → `lib/src/prompts/prompts.g.dart`
   (документ ядра §11); тест, что сгенерированный файл актуален.
9. **2.9. Runtime в памяти и минимальная сборка:** `lib/src/runtime/agent_runtime.dart`,
   `agent_session.dart`, `lib/src/host/host_profile.dart`, `lib/src/host/build_agent_core.dart`,
   `services.dart` с профилями `agent-serve` и `embedded-cli`; тесты берут
   `HostProfile.of('agent-serve')` и подставляют `services.baseEnv = MemoryExecutionEnv`, лишнее
   выключают через `narrowed` (agent-core-architecture §10.2). Сессии пока в памяти (`MemorySessionStore` появится на этапе 3; до этого
   — список в `AgentRuntime`).
10. **2.10. Сквозной сценарий:** `test/scenarios/read_edit_exec_test.dart` — scripted LLM читает
    файл, правит его, запускает команду; `MemoryExecutionEnv` с фейковым `exec`; проверяются
    последовательность `AgentEvent`, запросы к `PermissionGate` с аргументами и итоговые файлы.

**OpenSpec change.** `add-agent-core-loop-and-tools` (задачи 2.1–2.6, 2.8–2.10) и
`add-agent-core-permission-policy` (задача 2.7; scope: уровни и режимы, ключ «разрешить
всегда», критические шаблоны, режим по умолчанию для каждого профиля хоста). `tasks.md` — пары
«тест → реализация» со ссылкой на критерий (§9.0, правило 3).

**Что прочитать.** Документ ядра §4, §5, §6, §7, §10, §11.

**Definition of Done.**

* `fvm dart test packages/dart/codelab_agent_core packages/dart/codelab_agent_io` зелёный.
* `bounded_env_test.dart: rejects sibling directory with shared prefix` (`/proj_evil`).
* `policy_is_first_hook_test.dart: no tool executes without a policy decision`.
* `read_edit_exec_test.dart: same script yields identical event sequence on 100 runs` — сценарий детерминирован.
* `melos run guard`: `codelab_agent_io` добавлен в правила (без Flutter и ACP).
* `melos run web-compile`: web-smoke проводит ход с инструментом `read` на `MemoryExecutionEnv`.

**Зависимости.** Этап 1 (нужны `StreamFunction` и `ScriptedStreamFunction`); задачи 2.1–2.2 и
2.5–2.6 можно начинать параллельно с этапом 1.

**Риски.** Перенос лишней сложности (супервизоры, все возможности профиля) раньше, чем она нужна,
— в этап входят только подсистемы с этапом 2 в §4.0. Ошибки в парности вызовов приводят к
ошибкам 400 провайдера — тест парности на каждом пути отмены и ошибки.

---

← [9.6. Этап 1 — LLM](09-06-stage-1-llm.md) · [Оглавление](../dart-agent-and-clients.md) · [9.8. Этап 3 — Сессии и сжатие](09-08-stage-3-sessions.md) →
