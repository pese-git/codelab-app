## MODIFIED Requirements

### Requirement: Разрешить всегда по инструменту и шаблону
`allowAlways` и `rejectAlways` SHALL храниться только по `PermissionKey(tool, pattern)` в памяти сессии; решение для одного ключа НЕ SHALL применяться к другому (PERM-3). У дерева субагентов хранилище одно — корневой сессии: решение, принятое в запросе потомка, действует для всего дерева, и наоборот (SUB-2).

`permissionPattern` встроенных инструментов SHALL строиться по §7.5:
- `write`, `edit` — путь относительно корня после нормализации;
- `read`, `ls`, `search` — нормализованный путь, по умолчанию `.`;
- `exec` — строка команды без пробелов по краям;
- `task_create`, `task_update`, `task_list`, `task_get` — `*`;
- `agent` — имя типа субагента (`agent`): «разрешить всегда» для `explore` не разрешает `general`;
- прочие — канонический JSON аргументов.

#### Scenario: Всегда для одного файла
- **WHEN** пользователь выбрал `allowAlways` для `write lib/a.dart`, а затем модель вызывает `write lib/b.dart`, `write ./lib//a.dart` и `exec dart test`
- **THEN** `write ./lib//a.dart` исполняется без вопроса, для остальных двух gate получает запросы (`allow_always_scope_test.dart`)

#### Scenario: Всегда для команды
- **WHEN** пользователь выбрал `allowAlways` для `exec npm test`, а модель вызывает `exec rm -rf /` и `exec npm test --watch`
- **THEN** оба вызова снова идут к gate (`allow_always_key_test.dart`)

#### Scenario: Всегда для типа субагента
- **WHEN** в режиме `ask` пользователь выбрал `allowAlways` для `agent` с `type: explore`, а затем модель вызывает `agent` с `explore` и с `general`
- **THEN** первый исполняется без вопроса, для второго gate получает запрос

## ADDED Requirements

### Requirement: Разрешения потомка через gate корневой сессии
Запрос разрешения потомка любой глубины SHALL уходить в gate корневой сессии через `SubagentPermissionGate` (§17.3.3, SUB-3):
- `toolCallId` — цепочка id вызовов через `/` от вызова `agent` корневой сессии до вызова потомка; уникальна в корневой сессии (PERM-4);
- `title` — `[<agent>: <description>] <title вызова>` того потомка, чей вызов;
- `rawInput`, `locations`, diff, `reason`, `allowAlwaysOffered`, `kind`, `tier` и пометка критической команды — без изменений (PERM-6, PERM-9);
- запрос несёт сведения о потомке (`id`, `agent`, `description`, `depth`, `path`, `parentToolCallId` корня) для `_meta.codelab.subagent`.

Запросы потомков одного дерева SHALL уходить пользователю по одному в порядке поступления; запрос самой корневой сессии очереди не ждёт. Пока запрос ждёт, хэндл потомка в `waiting` с `waitingFor: approval`. Отмена токена потомка SHALL снимать его запрос с исходом `cancelled` (PERM-7).

Эффективный режим потомка SHALL сужаться по всей цепочке предков при каждом решении (SUB-2). `PolicyRules` у всего дерева общие. Без gate у корневой сессии запрос потомка SHALL становиться отказом `no approval interface is available` (PERM-5).

#### Scenario: Два ребёнка спрашивают одновременно
- **WHEN** два ребёнка одного пакета одновременно вызывают `exec`, требующий вопроса
- **THEN** fake gate корня получает второй запрос только после ответа на первый; `toolCallId` — `call_3/call_1` и `call_4/call_1` (`subagent_permission_prefix_test.dart`)

#### Scenario: Запрет всегда нельзя обойти через ребёнка
- **WHEN** пользователь выбрал `rejectAlways` для `exec rm -rf build` в корневой сессии, затем ребёнок вызывает ту же команду
- **THEN** вызов ребёнка отклонён без запроса к gate

#### Scenario: Вопрос внука
- **WHEN** внук глубины 2 вызывает `exec`, требующий вопроса
- **THEN** gate корня получает запрос с `toolCallId` из трёх сегментов, title с префиксом типа и заголовка внука и `depth: 2`
