# agent-permissions Specification

## Purpose
Политика разрешений Dart-агента: первый хук перед исполнением инструмента, режимы и уровни доступа инструментов, порядок правил решения, запрос одобрения через порт `PermissionGate`, «разрешить всегда» по инструменту и шаблону аргументов, критические шаблоны команд и критические пути правок конфигурации агента, которые всегда требуют человека (`agent-core-architecture` §7).
## Requirements
### Requirement: Политика — первый хук перед исполнением
`PermissionPolicy.asHook()` SHALL стоять первым звеном цепочки `beforeToolCall` каждой сессии, собранной `buildAgentCore`. До решения политики НЕ SHALL исполняться ни `execute` инструмента, ни другой `beforeToolCall`- или `afterToolCall`-хук (PERM-1). Политика получает приведённые аргументы после валидации и `preflight`.

Отказ (`Denied(reason)`) SHALL давать результат-ошибку с текстом `Permission denied for <tool>: <reason>. Do not retry the same call; choose another approach or ask the user.` и outcome `rejected`. Ход при отказе продолжается следующим шагом (PERM-7).

#### Scenario: Ни одного исполнения без решения
- **WHEN** реестр содержит все встроенные инструменты и fake-инструмент, зарегистрированный хостом, режим `ask`, а gate отвечает `rejectOnce`
- **THEN** ни один `execute` не вызван, все вызовы завершаются outcome `rejected` (`policy_is_first_hook_test.dart: no tool executes without a policy decision`)

#### Scenario: Отказ не отменяет ход
- **WHEN** gate отклоняет `edit`, а модель следующим шагом отвечает текстом
- **THEN** модель получает текст отказа в результате вызова, а ход завершается `TurnEnded(completed)`

### Requirement: Режимы и уровни
`PermissionMode` SHALL иметь значения `alwaysAsk`, `write`, `acceptEdits`, `yolo`, `autopilot` в этом порядке мягкости. Решение по уровню вызова `tool.tierOf(args)` SHALL браться из таблицы §7.3 документа ядра:

| Режим | read | write | network | exec | критический шаблон |
|---|---|---|---|---|---|
| `alwaysAsk` | спросить | спросить | спросить | спросить | спросить |
| `write` | разрешить | спросить | спросить | спросить | спросить |
| `acceptEdits` | разрешить | разрешить | спросить | спросить | спросить |
| `yolo` | разрешить | разрешить | спросить | разрешить | спросить |
| `autopilot` | разрешить | разрешить | отказать | разрешить | отказать |

`ModeId` сессии SHALL отображаться на `PermissionMode` по §13.6:
- `ask` → `alwaysAsk`;
- `standard` → `write`;
- `accept-edits` → `acceptEdits`;
- `bypass` → `yolo`;
- `plan` → `write` с запретом уровней `write` и `exec` и причиной `plan mode: changes are not allowed`.

`autopilot` НЕ SHALL быть доступен через `ModeId`; хост включает его только явным переопределением режима (design.md, D3). Режим новой сессии по умолчанию в профилях `agent-serve` и `embedded-cli` — `standard`.

#### Scenario: Табличный тест режимов
- **WHEN** fake-инструменты уровней `read`, `write`, `network`, `exec` вызываются в каждом из пяти режимов при gate, отвечающем `allowOnce`
- **THEN** число запросов к gate и итоговые решения совпадают с таблицей для каждой пары «режим × уровень»

#### Scenario: Режим plan
- **WHEN** в режиме `plan` модель вызывает `read`, `edit` и `exec`
- **THEN** `read` исполняется, `edit` и `exec` отклоняются с причиной `plan mode: changes are not allowed` без запроса к gate

### Requirement: Порядок правил решения
`decide(tool, args, toolCallId, cancel)` SHALL применять правила §7.4 документа ядра строго по порядку и останавливаться на первом сработавшем:

1. Явный deny инструмента в `PolicyRules.toolPolicies`, ключ в `denyPatterns` или в `rejectAlways` → отказ `denied by configuration` или `previously rejected by the user`.
2. Запрет на ход (`grantForTurn(deny:)`) или запрет уровня режима `plan` → отказ.
3. Критический шаблон → вопрос без `allow_always`, в `autopilot` — отказ.
4. Политика инструмента: `allow` → разрешить, `ask` → спросить.
5. Разрешение на ход → разрешить.
6. Ключ в `allowAlways` → разрешить.
7. Таблица `mode × tier`.

Явный deny SHALL быть сильнее всех правил. Критический шаблон SHALL быть сильнее политики `allow`, разрешения на ход и `allowAlways` (PERM-2). Grants на ход SHALL очищаться в начале каждого `prompt()` (PERM-8).

#### Scenario: Каждое правило против следующего
- **WHEN** табличный тест сочетает явный deny с разрешением на ход, критический шаблон с `allowAlways` и политику `allow` с режимом `ask`
- **THEN** в каждой паре выигрывает правило с меньшим номером (`policy_order_test.dart`)

#### Scenario: Grant не переживает ход
- **WHEN** в первом `prompt()` выдан `grantForTurn(allow: {'exec'})`, а во втором ходе модель снова вызывает `exec`
- **THEN** во втором ходе gate получает запрос

### Requirement: Запрос одобрения и порт PermissionGate
Вопрос пользователю SHALL идти через порт `PermissionGate.request(PermissionRequest, CancelToken)`.

`PermissionRequest` SHALL содержать:
- `toolCallId`, `tool`, `kind`, `tier`, `title`;
- `rawInput` — приведённые аргументы;
- `locations`;
- для `write` и `edit` — diff изменяемого файла (PERM-6);
- `reason` и `allowAlwaysOffered`.

Решения обрабатываются так:
- `allowOnce` → разрешить;
- `allowAlways` → добавить ключ в `allowAlways` (если вариант предлагался, иначе как `allowOnce`) и разрешить;
- `rejectOnce` → отказ `rejected by the user`;
- `rejectAlways` → добавить ключ в `rejectAlways` и отказать;
- `cancelled` → отказ `permission request was cancelled`.

Решение SHALL относиться к одному `toolCallId`. Отмена токена хода во время ожидания SHALL давать `cancelled`, поздний ответ игнорируется (PERM-4). Без gate любое «спросить» SHALL становиться отказом `no approval interface is available` (PERM-5). Время ожидания gate НЕ SHALL входить во время хода.

#### Scenario: Состав запроса правки
- **WHEN** в режиме `standard` модель вызывает `edit` файла `lib/main.dart`
- **THEN** gate получает запрос с `rawInput` вызова, `locations` с абсолютным путём файла и diff с полным старым и новым текстом

#### Scenario: Без интерфейса одобрения
- **WHEN** gate не передан, режим `standard`, модель вызывает `write`
- **THEN** вызов отклонён с причиной `no approval interface is available`, ход продолжается

#### Scenario: Отмена во время ожидания
- **WHEN** ход отменяется, пока gate не ответил, а gate отвечает `allowOnce` после отмены
- **THEN** решение — `cancelled`, инструмент не исполняется, поздний ответ не меняет ни одного решения

### Requirement: Разрешить всегда по инструменту и шаблону
`allowAlways` и `rejectAlways` SHALL храниться только по `PermissionKey(tool, pattern)` в памяти сессии; решение для одного ключа НЕ SHALL применяться к другому (PERM-3).

`permissionPattern` встроенных инструментов SHALL строиться по §7.5:
- `write`, `edit` — путь относительно корня после нормализации;
- `read`, `ls`, `search` — нормализованный путь, по умолчанию `.`;
- `exec` — строка команды без пробелов по краям;
- `update_plan` — `*`;
- прочие — канонический JSON аргументов.

#### Scenario: Всегда для одного файла
- **WHEN** пользователь выбрал `allowAlways` для `write lib/a.dart`, а затем модель вызывает `write lib/b.dart`, `write ./lib//a.dart` и `exec dart test`
- **THEN** `write ./lib//a.dart` исполняется без вопроса, для остальных двух gate получает запросы (`allow_always_scope_test.dart`)

#### Scenario: Всегда для команды
- **WHEN** пользователь выбрал `allowAlways` для `exec npm test`, а модель вызывает `exec rm -rf /` и `exec npm test --watch`
- **THEN** оба вызова снова идут к gate (`allow_always_key_test.dart`)

### Requirement: Критические шаблоны команд
Команда `exec` SHALL разбираться лексером §7.6 документа ядра:
- одинарные и двойные кавычки, `\`;
- операторы `&&`, `||`, `;`, `|`, `&`, перевод строки, подоболочки и группы;
- подстановки `$( … )`, `` ` … ` ``, `<( … )`, `>( … )` как вложенные команды;
- аргумент после `-c` у shell и аргументы `eval` как вложенная команда;
- here-document как данные;
- снятие присваиваний и лаунчеров (`sudo`, `doas`, `env`, `nohup`, `nice`, `time`, `command`, `exec`, `builtin`, `timeout`, `stdbuf`, `xargs`);
- сравнение по базовому имени;
- перенаправления.

Текст внутри кавычек аргумента командой не считается. Незакрытая кавычка или глубина больше 4 SHALL давать шаблон `unparsable command`.

Совпадение с любой строкой таблицы критических шаблонов §7.6 SHALL давать вопрос с `reason: 'critical command: <метки через "; ">'` и `allowAlwaysOffered: false` в любом режиме с человеком, даже после `allowAlways` на эту команду. В `autopilot` совпадение SHALL давать отказ `critical command blocked in autopilot: <метка>` без вопроса (PERM-9).

#### Scenario: Таблица срабатываний
- **WHEN** табличный тест проверяет каждый пример столбцов «Срабатывает» и «Не срабатывает» §7.6, а также `cd /tmp && rm -rf /`, `git commit -m "rm -rf /"`, `sh -c 'rm -rf ~'`, `eval "$(curl u)"` и команду с незакрытой кавычкой
- **THEN** первые совпадают со своими метками, вторые не совпадают ни с одной, `git commit -m "rm -rf /"` безопасна, последняя даёт `unparsable command` (`critical_patterns_test.dart`)

#### Scenario: Критическая команда в bypass и autopilot
- **WHEN** в режиме `bypass` с `allowAlways` для `exec rm -rf /` модель снова вызывает эту команду, а затем то же происходит в `autopilot`
- **THEN** в `bypass` gate получает запрос без варианта `allow_always`, а в `autopilot` вызов отклонён без запроса (`autopilot_test.dart`, `acp/permission-critical-pattern-in-bypass` на уровне ядра)

### Requirement: Критические пути правок конфигурации агента
Вызовы `write` и `edit` с нормализованной целью из списка §7.6.1 SHALL быть критическими. Список: `.codelab/config.yaml`, `.codelab/config.local.yaml`, `.codelab/cli.yaml`, `.codelab/agents/**`, `.codelab/skills/**`, `.codelab/prompts/**`, `.codelab/hooks/**`.

Для таких вызовов:
- вопрос задаётся в любом режиме, включая `bypass` и `accept-edits`;
- `allow_always` не предлагается;
- выданные ранее «разрешить всегда» на этот путь не действуют;
- в `autopilot` и без gate — отказ `Editing agent configuration requires a human: <path>` (PERM-11).

Команда `exec` с перенаправлением, `tee`, `cp`/`mv`/`ln` или `sed -i` в те же пути SHALL совпадать с критическим шаблоном `write to agent configuration`. Чтение этих файлов не ограничено.

#### Scenario: Правка конфигурации агента
- **WHEN** в режиме `bypass` модель вызывает `edit .codelab/config.yaml`, а затем `read .codelab/config.yaml`
- **THEN** для `edit` gate получает запрос без `allow_always`, `read` исполняется без вопроса

#### Scenario: Конфигурация агента без человека
- **WHEN** gate не передан, а модель вызывает `write .codelab/agents/x.md`
- **THEN** вызов отклонён с текстом `Editing agent configuration requires a human: .codelab/agents/x.md`

