## Why

Правку конфигурации агента через `write`/`edit` (PERM-11, `agent-core/07-permissions.md` §7.6.1) в `codelab -p --approve allow-all` одобряет сам CLI. Цепочка (сверено с `develop`, `91384e01`):

- `packages/dart/codelab_agent_core/lib/src/permissions/policy.dart`, `_decide`: для цели `_agentConfigTarget` политика зовёт `_ask(…, reason: 'agent configuration: $path', allowAlways: false)` **без** `criticalLabel`. `autopilot` и отсутствие gate уже дают отказ — это верно.
- `packages/dart/codelab_agent_acp/lib/src/acp_permission_gate.dart`, `_params`: `toolCall._meta.codelab = {critical: true, label}` ставится только при `criticalLabel != null`.
- `apps/codelab_cli/lib/src/headless/approval_policy.dart`, `decideApproval` (spec `cli-headless`, «Политика одобрений headless»): `allow-all` отвечает `allow_once` на всё, кроме `PendingApprovalView.critical`.

Итог: модель после промпт-инъекции переписывает `.codelab/config.yaml`, глобальный `config.yaml`, `secrets.yaml`, определения агентов и шаблоны команд, а `allow-all` это одобряет. Дальше конфигурация меняет политику разрешений, провайдера, MCP-серверы и хуки следующих сессий — то есть расширяет права модели без человека, ровно то, от чего защищает PERM-11. Дыра существует с change `add-config-writer-and-reload` (D8) и расширяется change `add-agent-skills` (D17, D19: корни навыков хоста и `skills.extra_roots` попадают под PERM-11); в D19 `add-agent-skills` этот случай записан как известный предел со ссылкой на этот change.

Для `exec` запись в конфигурацию уже критична: шаблон `write to agent configuration` (`critical_patterns.dart`, `agent_config_rules.dart`) даёт `criticalLabel`, и `allow-all` такой запрос отклоняет. Документ ядра (§7.2, комментарий к `PermissionRequest.criticalLabel`; §17.15.4, `A2aPermissionGate`) тоже предполагает метку у вопроса §7.6.1. Расхождение — только в ветке `write`/`edit` политики.

Вторичный дефект наблюдаемости: лог `permission.asked` пишет `critical: reason != null`, поэтому у PERM-11 он и сейчас `true`, хотя запрос не помечен критическим, а после исправления поле должно совпадать с тем, что видит клиент.

## What Changes

- **Ядро (`codelab_agent_core`).** Вопрос PERM-11 для `write`/`edit` (и любого инструмента с `lockPath`) получает `PermissionRequest.criticalLabel = 'write to agent configuration'` — ту же метку, что у критического шаблона `exec` (D1). `reason` остаётся `agent configuration: <path>` (D2), `allowAlwaysOffered: false` и отказ в `autopilot`/без gate — без изменений. Метка берётся из одной константы для обеих веток (D3). Поле `critical` лога `permission.asked` считается по `criticalLabel != null` (D4).
- **ACP-сервер (`codelab_agent_acp`).** Кода не меняет: `AcpPermissionGate` уже переносит `criticalLabel` в `toolCall._meta.codelab = {critical: true, label}`. Меняется требование: расширение `_meta.codelab.critical` (введено change `add-dart-agent-acp-server`) ставится на вопросы о критических командах **и** о правке конфигурации агента. Нового расширения нет, ACP-2 соблюдён, строка §13.12 уточняется (D5).
- **Клиенты.** Кода не меняют: `allow-all` уже отклоняет `critical` (D6). Поведение headless меняется для Dart-агента (встроенного и `codelab-agent`): правка конфигурации агента получает `reject_once` с причиной `critical`. REPL показывает `, critical` в строке риска; десктоп и TUI поле не читают (D7, UX-проверка).
- **Фикстуры.** Новая golden-фикстура `acp/permission-agent-config-edit-critical` (агент и клиент) закрепляет `_meta.codelab.critical` у правки `.codelab/config.yaml` в `bypass`. Существующие фикстуры не меняются: ни одна не правит путь §7.6.1 (D8).
- **Тесты.** Политика ядра, ACP-gate, scripted-агент `codelab_acp_testing` (режим `with_agent_config_write`), headless `allow-all` сквозным тестом CLI против Dart-агента и встроенного агента.
- **Документы.** `agent-core/07-permissions.md` (§7.2, §7.4, §7.6.1, §7.7, §7.8, §7.9 PERM-11), `agent-core/13-acp-adapter.md` §13.12, `docs/architecture/permissions.md`.

## Не входит

- Изменение состава путей PERM-11, правил `exec`, белого списка чтения и исключений навыков E1–E3 (change `add-agent-skills`).
- Изменение самого change `add-agent-skills` (он на другой ветке): его D19 только ссылается на этот change.
- Новые расширения ACP, новые поля `_meta` (например, путь в `_meta.codelab`), изменение текста `reason` и вариантов вопроса.
- Отдельная визуальная пометка критического запроса в десктопе и TUI (сейчас поле не читают) — UX, отдельный change при необходимости.
- Политики `reject` и `read-only`: они уже отклоняют такой запрос (вид `edit`, риск выше `readOnly`).
- Пересылка вопросов потомков (`SubagentPermissionGate`, change `add-subagents-and-tasks`): её требование уже переносит пометку критичности без изменений; этот change её не трогает.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `agent-permissions` — вопрос PERM-11 помечен критическим с меткой `write to agent configuration`; поле `critical` лога `permission.asked`.
- `agent-acp-server` — `_meta.codelab.critical` и у вопроса о правке конфигурации агента.
- `cli-headless` — `allow-all` отклоняет правку конфигурации Dart-агента (сквозной сценарий).
- `acp-golden-fixtures` — фикстура `acp/permission-agent-config-edit-critical`.

## Impact

- Код: `packages/dart/codelab_agent_core/lib/src/permissions/policy.dart`, `critical_patterns.dart` или `agent_config_rules.dart` (общая константа метки); `packages/dart/codelab_acp_testing` (фикстура, режим scripted-агента); тесты в `codelab_agent_core`, `codelab_agent_acp`, `codelab_client_acp`, `apps/codelab_cli`.
- Публичный API пакетов не меняется: `PermissionRequest.criticalLabel` уже есть.
- Зависимости, сторож, граф пакетов `README.md` — без изменений.
- Наблюдаемое поведение: Dart-агент помечает правку конфигурации агента `_meta.codelab.critical`; `codelab -p --approve allow-all` её отклоняет; REPL дописывает `, critical`; лог `permission.asked` у обычного вопроса с `reason` больше не говорит `critical: true` (таких вопросов, кроме PERM-11, сейчас нет — D4).
- Сторонние ACP-клиенты: `_meta` игнорируется по `15-Extensibility.md`; варианты вопроса те же (`allow_always` не было и раньше).
