Задачи идут парами «тест → реализация» (§9.0, правило 3). В скобках — требование спецификации `agent-permissions` и инвариант документа ядра. Пути — в `packages/dart/codelab_agent_core/`.

Итерации (design.md, D7):
- группы 1–3 — итерация 1, в одном PR с итерацией 2 change `add-agent-core-loop-and-tools`;
- группы 4–5 — итерация 2, в одном PR с итерацией 4 того change.

## 1. Режимы, уровни и gate (2.7)

- [x] 1.1 Тест («Режимы и уровни»): `test/permissions/modes_test.dart` — порядок мягкости пяти режимов; таблица `mode × tier` для каждой пары; `ModeId` → `PermissionMode` по §13.6; `ModeId.parse` для неизвестного id → `ArgumentError`; `autopilot` не выражается через `ModeId` (красный)
- [x] 1.2 Реализовать `lib/src/permissions/modes.dart` и `lib/src/permissions/gate.dart` (`PermissionGate`, `PermissionRequest`, `PermissionDecision`) — 1.1 зелёный

## 2. Ключ «разрешить всегда» и алгоритм решения (2.7)

- [x] 2.1 Тест («Разрешить всегда по инструменту и шаблону»): `test/permissions/pattern_test.dart` — `permissionPattern` встроенных инструментов по §7.5 (`./lib//a.dart` → `lib/a.dart`, `  dart test ` → `dart test`, `update_plan` → `*`, канонический JSON для прочих); `test/permissions/allow_always_scope_test.dart` и `allow_always_key_test.dart` — «всегда» для `write lib/a.dart` и `exec npm test` не распространяется на другие ключи (PERM-3, P-03) (красные)
- [x] 2.2 Тест («Порядок правил решения», «Запрос одобрения и порт PermissionGate»): `test/permissions/mode_table_test.dart` — таблица `mode × tier` на вызовах; `test/permissions/policy_order_test.dart` — каждое правило против следующего (PERM-2); режим `plan` запрещает `write` и `exec` без вопроса; `headless_test.dart` — без gate отказ `no approval interface is available` (PERM-5); `turn_grants_test.dart` (PERM-8); состав `PermissionRequest` для `edit` с `rawInput`, `locations` и diff (PERM-6); отмена во время ожидания → `cancelled`, поздний ответ игнорируется (PERM-4); ожидание не входит во время хода (design.md, D4); логи без значений аргументов (design.md, D5) (красные)
- [x] 2.3 Реализовать `lib/src/permissions/pattern.dart`, `policy.dart` (`decide`, `asHook`, `grantForTurn`, `clearTurnGrants`; `findCritical` пока возвращает `null`, design.md, D7) и `permissionPattern` встроенных инструментов; экспорт из барели — 2.1, 2.2 зелёные

## 3. Политика первым хуком (2.7)

- [x] 3.1 Тест («Политика — первый хук перед исполнением»): `test/permissions/policy_is_first_hook_test.dart: no tool executes without a policy decision` — через `buildAgentCore` все встроенные и fake-инструмент хоста, режим `ask`, gate `rejectOnce`; отказ не отменяет ход (PERM-1, PERM-7, P-04) (красный)
- [x] 3.2 `buildAgentCore` ставит `PermissionPolicy.asHook()` первым звеном `beforeToolCall`, режим новой сессии берётся из `CoreConfig.permissions.modeOverride ?? ModeId` сессии (design.md, D3), `AgentSession.prompt` вызывает `clearTurnGrants` — 3.1 зелёный
- [ ] 3.3 Проверка итерации 1: `fvm dart run melos run check` зелёный; PR вместе с итерацией 2 change `add-agent-core-loop-and-tools`

## 4. Лексер и критические шаблоны (2.7, P-07)

- [ ] 4.1 Тест («Критические шаблоны команд»): `test/permissions/shell_lexer_test.dart` — сегменты, кавычки, подстановки, `sh -c`, `eval`, here-document, лаунчеры, перенаправления слитно и отдельно, глубина 4, незакрытая кавычка; `test/permissions/critical_patterns_test.dart` — все примеры столбцов «Срабатывает» и «Не срабатывает» §7.6, несколько меток через `; `, fork-бомба; `autopilot_test.dart` — `bypass` с `allowAlways` → вопрос без `allow_always`, `autopilot` → отказ без gate (PERM-2, PERM-9) (красные)
- [ ] 4.2 Реализовать `lib/src/permissions/shell_lexer.dart`, `critical_patterns.dart` (design.md, D6) и подключить `findCritical` в шаге 3 `decide` — 4.1 зелёные

## 5. Критические пути правок (2.7, PERM-11)

- [ ] 5.1 Тест («Критические пути правок конфигурации агента»): `test/permissions/agent_config_paths_test.dart` — `write`/`edit` в каждый путь §7.6.1 спрашивают в `bypass` и `accept-edits` без `allow_always`, «всегда» на путь не действует, без gate и в `autopilot` — отказ `Editing agent configuration requires a human: <path>`, `read` не ограничен; `exec` с `>>`, `tee`, `cp`, `ln`, `sed -i` в эти пути — шаблон `write to agent configuration` (красный)
- [ ] 5.2 Реализовать проверку критических путей в `policy.dart` и шаблон `write to agent configuration` — 5.1 зелёный
- [ ] 5.3 Документ ядра §13.6: причина режима `plan` — `plan mode: changes are not allowed` (design.md, D2)
- [ ] 5.4 Проверка итерации 2: `fvm dart run melos run check` зелёный; строки матрицы P-01 (ядро), P-02 (ядро), P-03, P-04 (ядро), P-05 (ядро), P-07 имеют доказательства; PR вместе с итерацией 4 change `add-agent-core-loop-and-tools`
- [ ] 5.5 Перед архивированием: `openspec validate add-agent-core-permission-policy --strict`; архивировать вместе с `add-agent-core-loop-and-tools`; заполнить Purpose спецификации `agent-permissions`
