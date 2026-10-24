## Why

Этап 2 (`docs/architecture/proposals/dart-agent-and-clients/09-07-stage-2-loop-tools-permissions.md`, задача 2.7) даёт агенту инструменты, которые правят файлы и запускают команды. Без политики разрешений их исполнение ничем не ограничено.

У Python-агента три известных дефекта (`agent-parity-goals.md` §4.2):
- DF-03: «разрешить всегда» запоминается по виду инструмента;
- DF-04: запрос одобрения без аргументов;
- DF-06: отказ отменяет ход.

Dart-агент должен закрыть их по построению: политика — первый хук `beforeToolCall`, «всегда» — по ключу «инструмент + шаблон аргументов», критические команды спрашиваются в любом режиме.

Change закрывает цель Must P-03 и ядерную часть P-01, P-02, P-04, P-05, а также Should P-07. Источник решений — §7 принятого документа ядра `agent-core-architecture.md` и §10.5 (режим по умолчанию профиля). Точку подключения — цепочку `beforeToolCall` и единую точку исполнения — даёт change `add-agent-core-loop-and-tools`.

## What Changes

- **Режимы и уровни.**
  - `PermissionMode` (`alwaysAsk`, `write`, `acceptEdits`, `yolo`, `autopilot`) в порядке мягкости и таблица `mode × tier` §7.3 (уровни `read`, `write`, `network`, `exec` и критический шаблон).
  - `ModeId` сессии (`plan`, `ask`, `standard`, `accept-edits`, `bypass`) и его отображение на `PermissionMode` по §13.6; `plan` добавляет запрет уровней `write` и `exec`.
  - Режим по умолчанию профилей `agent-serve` и `embedded-cli` — `standard` (§10.5).
- **Порт `PermissionGate`** и типы `PermissionRequest` (с `rawInput`, `locations`, diff каждого изменяемого файла — PERM-6), `PermissionDecision`.
- **`PermissionPolicy`:**
  - алгоритм `decide` §7.4: явный deny и `rejectAlways`, запрет на ход, критический шаблон, политика инструмента, разрешение на ход, `allowAlways`, `mode × tier`;
  - `asHook()` первым звеном `beforeToolCall` (PERM-1);
  - отказ — результат-ошибка с текстом `Permission denied for <tool>: <reason>. Do not retry the same call; choose another approach or ask the user.` и outcome `rejected`, ход продолжается (PERM-7);
  - без gate «спросить» = отказ (PERM-5);
  - grants на ход очищаются в начале каждого `prompt()` (PERM-8);
  - ожидание gate не входит во время хода.
- **Ключ «разрешить всегда»** `PermissionKey(tool, pattern)` и `permissionPattern` встроенных инструментов по §7.5. Решения хранятся в памяти сессии (`PermissionDecisionStore`, PERM-3).
- **Критические шаблоны команд:**
  - лексер `shell_lexer.dart` §7.6: кавычки, операторы, подстановки, `sh -c` и `eval`, here-document, лаунчеры, перенаправления, глубина 4;
  - таблица критических шаблонов `critical_patterns.dart`, включая fork-бомбу;
  - вопрос без `allow_always` в любом режиме с человеком, отказ в `autopilot` (PERM-2, PERM-9);
  - критические пути правок конфигурации агента в проекте §7.6.1 (PERM-11).
- **Логи** `permission.asked`, `permission.decided`, `permission.denied` с `toolCallId`, `tool` и причиной, без значений аргументов (`AGENTS.md` §16).

Не входит:
- `AcpPermissionGate` и `_meta.codelab.critical` (этап 4);
- загрузка `permissions.*` из конфигурации, ужесточение режима проектным слоем, флаг `--permission-mode` (этапы 4 и 8). Хост передаёт `PolicyRules`, режим и переопределение `autopilot` напрямую;
- `narrow` для субагентов, `modeOf`, правила по `permissionKeyName` (после MVP);
- сохранение «всегда» между сессиями (после MVP, через OpenSpec);
- синонимы `ModeId` на входе ACP (этап 4).

## Capabilities

### New Capabilities
- `agent-permissions`: политика разрешений ядра — режимы и уровни, порт `PermissionGate`, алгоритм решения, ключ «разрешить всегда», критические шаблоны команд и критические пути правок, поведение без интерфейса одобрения.

### Modified Capabilities
(нет)

## Impact

- `packages/dart/codelab_agent_core/lib/src/permissions/`: `gate.dart`, `modes.dart`, `policy.dart`, `pattern.dart`, `shell_lexer.dart`, `critical_patterns.dart` и тесты `test/permissions/`.
- Встроенные инструменты change `add-agent-core-loop-and-tools` получают `permissionPattern` по §7.5. `buildAgentCore` ставит политику первым звеном `beforeToolCall`.
- Барель экспортирует `PermissionGate`, `PermissionRequest`, `PermissionDecision`, `PermissionMode`, `ModeId`, `PolicyRules`, `ToolPolicy`.
- Зависимости и allowlist не меняются. ACP-контракты и клиенты не меняются: модель разрешений клиента (`AGENTS.md` §10) остаётся прежней.
