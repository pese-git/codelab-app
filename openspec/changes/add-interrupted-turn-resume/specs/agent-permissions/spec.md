## ADDED Requirements

### Requirement: Повтор прерванного вызова
При открытии сессии через `AgentRuntime.loadSession` `AgentSession` SHALL строить набор защиты повтора из `unfinishedTurnOf(snapshot).interruptedCalls` (capability `agent-sessions`, «Незавершённый ход»; design.md change `add-interrupted-turn-resume`, D5; PERM-12). Набор — мультимножество пар: имя инструмента и каноническая форма аргументов. Каноническая форма — аргументы журнала после того же приведения валидатором инструмента, что проходит вызов перед `decide` (если валидатор их отвергает — сырые аргументы), сериализованные в JSON с ключами объектов в байтовом порядке, без пробелов. Аргументы вызова перед сравнением SHALL приводиться к той же форме.

Набор SHALL жить только в памяти, до закрытия сессии; в журнал он НЕ SHALL попадать. Набор принадлежит дереву сессии: `PermissionPolicy` потомков (субагентов любой глубины) SHALL проверять тот же набор.

Пока в наборе есть вхождение пары вызова, а уровень вызова `tool.tierOf(args)` не `read`, вызов SHALL получать решение правила 3a (требование «Порядок правил решения»):
- в режимах с человеком — вопрос через `PermissionGate` с `reason: 'repeat of interrupted call: verify the current state first'`, `allowAlwaysOffered: false` и меткой `critical` `repeat of interrupted call` — даже при `allowAlways` на этот ключ, разрешении на ход и политике инструмента `allow`;
- в `autopilot` — отказ `repeat of interrupted call blocked in autopilot` без вопроса;
- без `PermissionGate` — отказ `no approval interface is available`.

Разрешение человека SHALL снимать ровно одно вхождение пары. Отказ человека, отказ в `autopilot` и отказ без gate вхождение НЕ SHALL снимать. Вызовы одного параллельного пакета проверяются до снятия: каждый совпавший вызов получает свой вопрос. ACP-проекция вопроса SHALL помечать `toolCall` расширением `_meta.codelab: {"critical": true, "label": "repeat of interrupted call"}`. Совпадение SHALL давать лог `permission.interrupted_repeat` (info) с `session_id`, `tool_call_id`, `tool`, `decision` (`ask` или `deny`) без аргументов.

#### Scenario: Повтор exec в режиме bypass
- **WHEN** сессия загружена с прерванным `exec` `{"command": "make deploy"}`, режим `bypass`, и в ходе `/continue` модель вызывает `exec` с теми же аргументами
- **THEN** gate получает вопрос с причиной `repeat of interrupted call: verify the current state first` без варианта `allow_always`; команда не исполняется до ответа

#### Scenario: Повтор в autopilot
- **WHEN** то же в режиме `autopilot`
- **THEN** вызов отклонён с `repeat of interrupted call blocked in autopilot`, gate не вызывался

#### Scenario: Повтор без gate
- **WHEN** ядро собрано без `PermissionGate`, режим `bypass`, и модель повторяет прерванный `exec`
- **THEN** вызов отклонён с `no approval interface is available`, команда не исполнялась

#### Scenario: Чтение не защищается
- **WHEN** прерванным был `read` `{"path": "a.txt"}`, и модель повторяет его в режиме `standard`
- **THEN** вызов исполняется без вопроса

#### Scenario: Изменённые аргументы
- **WHEN** прерванным был `exec` `{"command": "make deploy"}`, а модель вызывает `exec` `{"command": "git status"}`
- **THEN** решение — по обычным правилам режима, правило 3a не срабатывает

#### Scenario: Приведённые аргументы совпадают
- **WHEN** в журнале прерванный `exec` записан с `{"timeout": "30", "command": "make deploy"}`, а модель вызывает `exec` с `{"command": "make deploy", "timeout": 30}`, и валидатор приводит строку `"30"` к числу
- **THEN** правило 3a срабатывает

#### Scenario: Отказ, затем повтор
- **WHEN** в режиме `bypass` человек отклонил повтор прерванного `exec`, и модель в том же или следующем ходе вызывает его снова
- **THEN** gate снова получает вопрос; команда не исполняется без разрешения

#### Scenario: Первый ход отменён
- **WHEN** первый ход после загрузки отменён до запроса к модели, а во втором ходе («продолжай») модель повторяет прерванный `exec` в режиме `bypass`
- **THEN** gate получает вопрос

#### Scenario: Одно разрешение — одно вхождение
- **WHEN** прерванным был один `exec`, и модель вызывает его дважды в одном параллельном пакете
- **THEN** gate получает два вопроса; после разрешения обоих вхождение снято, и следующий такой вызов решается по обычным правилам режима

#### Scenario: Повтор через субагента
- **WHEN** модель поручает субагенту вызвать прерванный `exec` с теми же аргументами в режиме `bypass`
- **THEN** решение потомка — вопрос через gate корня с причиной правила 3a

## MODIFIED Requirements

### Requirement: Порядок правил решения
`decide(tool, args, toolCallId, cancel)` SHALL применять правила §7.4 документа ядра строго по порядку и останавливаться на первом сработавшем:

1. Явный deny инструмента в `PolicyRules.toolPolicies`, ключ в `denyPatterns` или в `rejectAlways` → отказ `denied by configuration` или `previously rejected by the user`.
2. Запрет на ход (`grantForTurn(deny:)`) или запрет уровня режима `plan` → отказ.
3. Критический шаблон → вопрос без `allow_always`, в `autopilot` — отказ.
3a. Повтор прерванного вызова (требование «Повтор прерванного вызова») → вопрос без `allow_always`, в `autopilot` — отказ (design.md change `add-interrupted-turn-resume`, D5).
4. Политика инструмента: `allow` → разрешить, `ask` → спросить.
5. Разрешение на ход → разрешить.
6. Ключ в `allowAlways` → разрешить.
7. Таблица `mode × tier`.

Явный deny SHALL быть сильнее всех правил. Критический шаблон и повтор прерванного вызова SHALL быть сильнее политики `allow`, разрешения на ход и `allowAlways` (PERM-2, PERM-12). Если вызов совпадает и с критическим шаблоном, и с набором защиты повтора, решение даёт правило 3; разрешение человека при этом SHALL снимать вхождение набора, как после вопроса по правилу 3a. Grants на ход SHALL очищаться в начале каждого `prompt()` (PERM-8).

#### Scenario: Каждое правило против следующего
- **WHEN** табличный тест сочетает явный deny с разрешением на ход, критический шаблон с `allowAlways`, повтор прерванного вызова с политикой `allow` и политику `allow` с режимом `ask`
- **THEN** в каждой паре выигрывает правило с меньшим номером (`policy_order_test.dart`)

#### Scenario: Grant не переживает ход
- **WHEN** в первом `prompt()` выдан `grantForTurn(allow: {'exec'})`, а во втором ходе модель снова вызывает `exec`
- **THEN** во втором ходе gate получает запрос

#### Scenario: Deny сильнее защиты повтора
- **WHEN** прерванный `exec` повторяется, а `exec` запрещён в `toolPolicies`
- **THEN** отказ `denied by configuration` без вопроса
