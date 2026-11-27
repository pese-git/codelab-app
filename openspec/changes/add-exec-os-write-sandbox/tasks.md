Порядок: 0 → 1 → 2 → 3 → 4. Итерация 1 — задачи 1–2: ядро, ключ, статус везде `unavailable`, поведение прежнее. Итерация 2 — задача 3: macOS и composition root. Итерации вливаются отдельными PR.

Внутри 1–3 — пары «красный тест → реализация». TDD — `codelab_agent_core/AGENTS.md` §2: красный тест каждой пары коммитится отдельно до кода, и только по явной просьбе пользователя. Все команды — через `fvm`. Интеграционные тесты — только Dart VM (`AGENTS.md` §21).

Метки: `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `codelab_embedded`, `apps/codelab_agent`. Задач `[protocol]`, `[client]` и `[desktop]` нет: ACP, клиентские пакеты и приложения клиентов не меняются (design.md, D14, D17, D18).

Перед стартом пользователь отвечает на Q1–Q6 design.md. Задачи ниже написаны под рекомендации.

## 0. Документы

- [ ] 0.1 `[agent]` Документ ядра до кода (`codelab_agent_core/AGENTS.md`, «сначала документ»). Правка — после влития или с учётом `harden-exec-cwd-tracking`, который тоже меняет `07-permissions.md`:
  - `docs/architecture/proposals/agent-core/04-execution-env.md`:
    - §4.2 — `ExecWriteProtection`, `ExecSandboxShell`, `ExecSandboxStatus`, `sandboxFailed`, `ExecResult.writeProtected`;
    - новый §4.6.1 «Защита записи на уровне ОС» — профиль, параметры, формы путей, предки, проба, fail closed;
    - ENV-8 «env с активной песочницей применяет `writeProtection` или не запускает команду»;
    - §4.11 — тесты.
  - `07-permissions.md`:
    - новый §7.6.3 «Второй рубеж PERM-11: ОС» — D1, D2, D4, D9–D12;
    - в §7.6.1 — ссылка на §7.6.3 у списка пределов разбора `exec` и пометка, какие пределы второй рубеж закрывает на macOS;
    - шаг `required` в алгоритме §7.4;
    - пункт §7.11.
  - `15-configuration.md` — ключ `permissions.exec_sandbox` (D8).

## 1. Ядро (`packages/dart/codelab_agent_core`)

- [ ] 1.1 `[agent]` Красные тесты порта (spec `agent-execution-env`, «Защита записи exec на уровне ОС»):
  - `test/env/bounded_env_test.dart` — «Обёртка пробрасывает статус и защиту», «Env без возможности», включая все восемь сочетаний `_Bounded*`;
  - `listing_overlay_env_test.dart` — статус `primary`;
  - `execution_env_test.dart` — «copyWith сохраняет защиту».

  Фейковый env с `ExecSandboxShell` — в `test/support/`.
- [ ] 1.2 `[agent]` Реализация 1.1:
  - `lib/src/env/execution_env.dart` — `ExecWriteProtection`, `ExecSandboxStatus` (`ExecSandboxActive`, `ExecSandboxUnavailable`), `ExecSandboxShell`, поле `ExecOptions.writeProtection` и `copyWith`, `ExecResult.writeProtected`, `ExecErrorCode.sandboxFailed`;
  - `_Bounded` реализует `ExecSandboxShell`;
  - `ListingOverlayEnv` реализует `ExecSandboxShell`;
  - экспорт из бареля.

  Doc-комментарии — по-русски, «почему / для чего / как» (`AGENTS.md` §15), со ссылками на D3. Комментарии `execution_env.dart`, которые меняются вместе с полями, переводятся.
- [ ] 1.3 `[agent]` Красные тесты `ExecWriteGuard`, новый `test/permissions/exec_write_guard_test.dart` (spec `agent-permissions`, сценарии «Состав защиты на вызов», «Режим off»; D2, D4):
  - состав `P`;
  - `AgentConfigPaths == null` → только два проектных пути;
  - снятие одноразовое;
  - `approve` неизвестного id не влияет на другие.
- [ ] 1.4 `[agent]` Реализация 1.3: `lib/src/permissions/exec_write_guard.dart`, enum `ExecSandboxMode { auto, required, off }`.
- [ ] 1.5 `[agent]` Красные тесты политики, `test/permissions/exec_sandbox_policy_test.dart` через `policy_harness.dart`. Сценарии `agent-permissions`:
  - «Текстовый рубеж не меняется» — прогон таблиц при активной фейковой песочнице;
  - «Одобрение правки конфигурации снимает защиту для одного вызова»;
  - «Прочие одобрения защиту не снимают»;
  - «Autopilot»;
  - «Режим required без механизма» — порядок: явный deny сильнее `required`, `required` раньше критического шаблона.
- [ ] 1.6 `[agent]` Реализация 1.5, `lib/src/permissions/policy.dart`:
  - параметр `ExecWriteGuard? execGuard`;
  - шаг `required` (D9);
  - `approve(ctx.toolCallId)` при `allowOnce` на критическую метку, содержащую `write to agent configuration`, у `exec`.
- [ ] 1.7 `[agent]` Красные тесты `ExecTool`, `test/tools/exec_tool_sandbox_test.dart`. Сценарии «Заметка об отказе записи», «Сбой песочницы — ошибка инструмента»; `writeProtection` уходит в `ExecOptions`; события `exec.sandbox.lifted` и `exec.sandbox.failed` с `tool_call_id`.
- [ ] 1.8 `[agent]` Реализация 1.7, `lib/src/tools/builtin/exec.dart`: параметр `ExecWriteGuard? guard`, заметка и текст `sandboxFailed` (D11), события журнала.
- [ ] 1.9 `[agent]` Красные тесты рантайма, `test/runtime/exec_sandbox_runtime_test.dart`:
  - guard создаётся на сессию из `_sessionConfigPaths(skillsLoad)` и корня сессии;
  - у двух сессий в разных папках разные проектные пути (Q44);
  - `ExecTool` сессии всегда получает guard, в том числе без `readOnlyRoots`;
  - субагент делит guard родителя, если change `add-subagents-and-tasks` уже влит, иначе пункт пропускается;
  - сценарий «Статус при открытии сессии» и уровни для `active`, `off`.
- [ ] 1.10 `[agent]` Реализация 1.9, `lib/src/runtime/agent_runtime.dart`:
  - guard рядом с политикой;
  - перерегистрация `ExecTool` с guard, когда `lookup('exec') is ExecTool`;
  - событие `exec.sandbox.status` (статус — `ctx.env is ExecSandboxShell`, D9).

## 2. Ключ конфигурации (`codelab_agent_core`)

- [ ] 2.1 `[agent]` Красные тесты: разбор и проверка значения, слияние слоёв, реестр настроек. Сценарии `agent-configuration`:
  - «Проект только ужесточает»;
  - «Неизвестное значение»;
  - «Перезагрузка не меняет режим»;
  - полнота `SettingsRegistry` (CFG-19).
- [ ] 2.2 `[agent]` Реализация 2.1: узел схемы `permissions.exec_sandbox`, `PermissionsConfig.execSandbox`, `narrow` по порядку `off < auto < required`, дескриптор `fileOnly`. Рантайм передаёт режим в `ExecWriteGuard`.

## 3. macOS и composition root (`codelab_agent_io`, `codelab_embedded`, `apps/codelab_agent`)

- [ ] 3.1 `[agent]` Красные юнит-тесты, новый `codelab_agent_io/test/env/exec_sandbox_test.dart`, все ОС, без запуска процессов. Сценарии «Текст профиля не зависит от путей», «Каноническая форма и предки» — вторая часть только `@TestOn('mac-os')`. Ещё проверить:
  - `-D` по одному на путь;
  - путь с NUL и пустой путь → `sandboxFailed` без `Process.start`;
  - пустой `writeProtection` → запуск без песочницы;
  - `NoOsWriteSandbox` не меняет argv.

  Запуск процесса — через внедрённую функцию, как в тестах `process_tree`.
- [ ] 3.2 `[agent]` Реализация 3.1, новый `lib/src/env/exec_sandbox.dart`:
  - `sealed class OsWriteSandbox`, `MacSandboxExec`, `NoOsWriteSandbox`;
  - построитель профиля и argv;
  - формы путей и предки (D5);
  - `detectExecSandbox` с пробой; единственный `Platform.isMacOS` (D7).

  Источник синтаксиса SBPL — `man sandbox-exec` и профили системы. Сторонний код не копируется (`AGENTS.md` §5).
- [ ] 3.3 `[agent]` Красные интеграционные тесты, новый `codelab_agent_io/test/env/local_exec_sandbox_test.dart`, `@TestOn('mac-os')`, `skip`, если проба не дала `MacSandboxExec`. Сценарии `agent-execution-env`:
  - «Запись в защищаемые пути отклоняется ОС»;
  - «Несуществующий каталог конфигурации нельзя создать»;
  - «Остальное разрешено»;
  - «Потомки и фоновые процессы наследуют защиту»;
  - «Сбой запуска песочницы — команда не исполняется»;
  - «Проба внутри чужой песочницы»;
  - «Отмена под песочницей».

  Дополнительно — проверка NFD-имени каталога. Результат записывается в design.md, D12, п. 3: закрыт или предел.

  Отдельный тест на Linux и Windows: «Linux и Windows без механизма».
- [ ] 3.4 `[agent]` Реализация 3.3, `lib/src/env/local_execution_env.dart`:
  - параметр `sandbox:`;
  - реализация `ExecSandboxShell`;
  - запуск через `MacSandboxExec` при непустом `writeProtection`;
  - `writeProtected`.

  Обновить spec-ссылки в doc-комментарии класса.
- [ ] 3.5 `[agent]` Красные тесты сборки и `config check`:
  - `codelab_embedded`: `local_opener` и `scripted_opener` передают обнаруженную песочницу во все `LocalExecutionEnv` (фейковое обнаружение);
  - `apps/codelab_agent`: `agent_host` — то же для `localEnv`, `localListing` и `baseEnv`;
  - `codelab_agent_io`: `config_commands` — сценарии «Механизм есть» (macOS) и «Required без механизма» с подменённым обнаружением; «Одинаковый вывод у двух бинарей» остаётся зелёным.
- [ ] 3.6 `[agent]` Реализация 3.5:
  - `detectExecSandbox()` — один раз в composition root;
  - параметр обнаружения в `ConfigCommands` для тестов;
  - строка `Exec sandbox:` и предупреждение (D9).

## 4. Проверка (`AGENTS.md` §21, затронутое)

- [ ] 4.1 `[agent]` `fvm dart format --set-exit-if-changed` изменённых файлов. `fvm dart analyze` в `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp` (публичный API ядра изменён), `codelab_embedded`, `apps/codelab_agent`.
- [ ] 4.2 `[agent]` Тесты этих пакетов, интеграционный тест песочницы — на macOS локально. Скрипты Melos:
  - `web-compile` — изменён web-безопасный `codelab_agent_core`;
  - `conformance:agent` — фикстуры не должны измениться;
  - `test:e2e:cli:dart-agent` — изменён `apps/codelab_agent`;
  - `guard` — подтвердить, что новых правил не нужно.

  `openspec validate add-exec-os-write-sandbox --strict`.
