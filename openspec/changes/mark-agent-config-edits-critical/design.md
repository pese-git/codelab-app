## Context

### Угроза

PERM-11 (`agent-core/07-permissions.md` §7.6.1, §7.9) говорит: конфигурацию агента меняет только человек. Через неё модель может расширить собственные права в следующих сессиях: снять `permissions.deny`, включить `bypass` для типа агента, подключить MCP-сервер, добавить хук или навык со скриптом. Поэтому правка защищаемых путей спрашивается в любом режиме, без `allow_always`, а в `autopilot` и без gate отклоняется.

`codelab -p --approve allow-all` — ACP-клиент, который отвечает на вопросы сам. Он отличает «вопрос, который может одобрить политика» от «вопроса, который требует человека» только по `_meta.codelab.critical` (spec `cli-headless`, «Политика одобрений headless»; design.md change `add-codelab-cli`, D9, D14). У вопроса PERM-11 для `write`/`edit` этой пометки нет, и `allow-all` его одобряет. Сценарий атаки: промпт-инъекция из файла репозитория просит модель «исправить конфиг» → `write .codelab/config.yaml` с `permissions.mode: bypass` и MCP-сервером злоумышленника → следующая сессия в этой папке работает с этими настройками (для глобального `$CODELAB_HOME/config.yaml` — во всех папках).

### Как сейчас устроено (сверено с `develop`, `91384e01`)

| Звено | Файл | Поведение |
|---|---|---|
| Политика, ветка PERM-11 | `codelab_agent_core/lib/src/permissions/policy.dart`, `_decide` | `_agentConfigTarget` → `autopilot`/без gate — `Denied('Editing agent configuration requires a human: <path>')`; иначе `_ask(reason: 'agent configuration: <path>', allowAlways: false)` без `criticalLabel` |
| Политика, критический шаблон | там же, `_criticalLabel` | `_ask(reason: 'critical command: <label>', criticalLabel: <label>, allowAlways: false)`; для записи в конфигурацию через `exec` метка `write to agent configuration` (`critical_patterns.dart`, `_agentConfig`; `agent_config_rules.dart`) |
| Лог вопроса | там же, `_ask` | `permission.asked {tool_call_id, tool, tier, critical: reason != null}` |
| ACP-gate | `codelab_agent_acp/lib/src/acp_permission_gate.dart`, `_params` | `reason` — первый текстовый блок `content`; `_meta.codelab = {critical: true, label}` только при `criticalLabel != null` |
| Клиентский домен | `codelab_client_acp/…/acp_client_application.dart`, `_isCritical` | `ApprovalRequest.critical` = `_meta.codelab.critical == true` в запросе или `toolCall` |
| Проекция | `codelab_client_core/…/transcript_projector.dart` | `ApprovalStateView.pending.critical` |
| Headless | `apps/codelab_cli/lib/src/headless/approval_policy.dart` | `allow-all` + `critical` → `reject_once`, причина `critical` |

Документ ядра уже ожидает метку у вопроса §7.6.1: комментарий к `PermissionRequest.criticalLabel` в §7.2 («метка критического шаблона §7.6 или `'agent configuration'` (§7.6.1)») и `A2aPermissionGate` в §17.15.4 (п. 1: «`req.criticalLabel != null` (критический шаблон §7.6 или конфигурация агента §7.6.1, PERM-11)»). Код с документом расходится; спецификация `agent-permissions` о метке у PERM-11 молчит, `agent-acp-server` говорит «критическая команда — `_meta.codelab.critical`», `docs/architecture/permissions.md` утверждает, что «критические запросы отклоняются при любой политике». Исправляется код и уточняются спецификации; поведение, которое уже обещано пользователю в документах, не меняется.

## Goals / Non-Goals

**Goals:**
- Вопрос PERM-11 о `write`/`edit` несёт ту же пометку критичности, что вопрос о записи в конфигурацию через `exec`.
- `codelab -p --approve allow-all` с Dart-агентом (встроенным и `codelab-agent`) отклоняет правку конфигурации агента.
- Поле `critical` лога `permission.asked` совпадает с пометкой, которую видит клиент.
- Сквозной тест и golden-фикстура закрепляют поведение.

**Non-Goals:**
- Менять состав путей PERM-11, правила `exec`, исключения навыков (change `add-agent-skills`).
- Новые расширения ACP или поля `_meta`.
- Визуальное выделение критического запроса в десктопе и TUI.

## Decisions

### D1. Метка — `write to agent configuration`, та же, что у `exec`

Политика передаёт в `_ask` ветки PERM-11 `criticalLabel: 'write to agent configuration'`.

Почему так: метка называет **класс опасности** (строку правила), а не способ, которым модель до неё добралась. Запись в конфигурацию через `write`, `edit` или `exec` — один класс: одинаковый ущерб, одинаковый ответ клиента. Одна метка даёт клиентам и логам одну группировку (фильтр по `label`, будущая визуальная пометка, отчёт headless), а A2A-gate и headless и так решают по наличию метки. Глагол `write` точен и для `edit`: правка — запись в файл.

Альтернативы:
- (б) `agent configuration` — так написано в комментарии §7.2. Отклонено: две метки для одного класса; комментарий писали до того, как у `exec` появилась строка таблицы `write to agent configuration` (change `add-config-writer-and-reload`). Комментарий §7.2 исправляется этим change.
- (в) метка с путём (`write to agent configuration: <path>`). Отклонено: метка — стабильный идентификатор правила, как строки таблицы §7.6; путь уже есть в `reason`, `locations` и `diff`, а пути пользователя в идентификаторах мешают группировке и попадают в логи без нужды.

### D2. `reason` не меняется: `agent configuration: <path>`

Текст первого блока `content` остаётся прежним.

Почему: человек в десктопе и REPL видит, **какой** файл модель хочет менять; `critical command: …` здесь неверно (это не команда) и теряет путь. Сохранение текста не меняет `content` запроса для существующих клиентов, тестов и журналов.

Альтернатива — общий формат `critical edit: write to agent configuration (<path>)`. Отклонено: смена видимого текста без выигрыша в безопасности, лишняя правка тестов клиентов.

### D3. Одна константа метки

Метка `write to agent configuration` определяется один раз в библиотеке правил PERM-11 (`agent_config_rules.dart`, рядом с `isAgentConfigPath`; без экспорта из барреля пакета) и используется и `critical_patterns.dart` (вместо приватной `_agentConfig`), и `policy.dart`. Новых классов и абстракций не вводится (§13 `AGENTS.md`).

Почему: две копии строки рано или поздно разойдутся, а клиенты и тесты сравнивают метку побайтово.

### D4. Лог `permission.asked`: `critical` = `criticalLabel != null`

Поле `critical` в `permission.asked` считается по наличию метки, а не по наличию `reason`.

Почему: сейчас `reason` есть ровно у двух веток (PERM-11 и критический шаблон), так что после D1 значение для них не меняется; но поле обязано означать то же, что `_meta.codelab.critical` у клиента (§16 `AGENTS.md`, наблюдаемость permission flow), и не должно ломаться, когда у некритического вопроса появится `reason` (например, сводка `lsp rename`, §17.8.9, или будущие подсказки). Отдельное поле `label` в лог не добавляется: метка видна в кадре ACP и в `permission.denied` (`reason`), а лог вопроса — уровня `debug`.

### D5. ACP: существующее расширение, новое место применения

`AcpPermissionGate` не меняется: он уже переносит `criticalLabel` в `toolCall._meta.codelab = {"critical": true, "label": <метка>}`. Меняется требование `agent-acp-server` «Запросы агента к клиенту»: `_meta.codelab.critical` ставится на любой вопрос с `PermissionRequest.criticalLabel` — критическую команду (§7.6) и правку конфигурации агента (§7.6.1).

ACP-2 (§13.12) соблюдён: набор расширений не меняется, `_meta.codelab.critical` введено change `add-dart-agent-acp-server`; в таблицу §13.12 дописывается место применения со ссылкой на этот change. Требование «Расширения протокола этапа 4» не трогается: его меняет активный change `add-subagents-and-tasks`, а перечень расширений от этого change не зависит.

Совместимость: `_meta` — механизм расширения ACP (`docs/protocols/acp/protocol/15-Extensibility.md#the-_meta-field`); сторонний клиент его игнорирует и видит те же варианты, что раньше (`allow_always` не предлагался и до change). Новых методов, полей и состояний ACP нет (§3.4 `AGENTS.md`).

### D6. Клиенты: кода не меняют

`decideApproval` уже отвечает на `critical` `reject_once` с причиной `critical`; `read-only` и `reject` отклоняют правку и без пометки (вид `edit`, риск выше `readOnly`). Требование `cli-headless` «Политика одобрений headless» не меняется; добавляется требование со сквозным сценарием для Dart-агента, которое закрепляет связку ядро → ACP → CLI (решение пользователя исправить дыру отдельным change).

Строка stderr — прежнего формата: `codelab: permission "<title>": reject_once (critical)`. Модель получает отказ `Permission denied for write: rejected by the user. …` и продолжает ход (PERM-7); код выхода определяется ответом `session/prompt`, как раньше.

### D7. UX-проверка (сделана при проектировании)

| Поверхность | Что проверено | Итог |
|---|---|---|
| Десктоп (`apps/codelab_desktop/lib`, `packages/flutter/codelab_ui`) | поиск `critical` — совпадений нет; варианты диалога — из `options` запроса; текст `reason` — из `content` | диалог не меняется: `allow_always` не было и раньше, `reason` прежний (D2) |
| REPL (`apps/codelab_cli/lib/src/repl/approval_prompt.dart`) | строка `Permission: <title> (<risk>, critical)` | приемлемо и желательно: человек видит, что «разрешить всегда» нет потому, что вопрос критический; клавиша `[a]` и раньше не показывалась |
| TUI (`apps/codelab_cli/lib/src/tui`) | поиск `critical` — совпадений нет | не меняется |
| Клиентский домен (`codelab_client_acp`, `_isCritical`) | читает только булево `true` в запросе или `toolCall` | `ApprovalRequest.critical == true`; на машину состояний сессии и ответ не влияет |
| Проекция (`codelab_client_core`, `transcript_projector.dart`) | копирует `critical` в `ApprovalStateView.pending` | единственный потребитель — headless и REPL |
| Автоодобрение в клиенте | поиск `autoApprove`/запоминания решений в `codelab_client_*` и приложениях — нет; «разрешить всегда» помнит только агент (`PermissionDecisionStore`) | последствий нет |
| Headless `read-only`, `reject` | `decideApproval` | и до, и после — `reject_once`, причина `policy` |
| Встроенный агент (`codelab_embedded`) | собирает `AcpAgentServer` и тот же `AcpPermissionGate` поверх `InProcessAcpLink` | пометка приходит так же, как от `codelab-agent`; кода не меняет |
| Типы агентов с режимом (`agent_select_serial_test.dart`) | тип с `mode: bypass` правит `.codelab/config.yaml` | вопрос был без `allow_always`, теперь ещё и с меткой; тест дополняется (задача 1.1) |
| Пересылка вопросов потомков (`SubagentPermissionGate`, change `add-subagents-and-tasks`) | в коде этой ветки нет; требование change переносит «пометку критической команды — без изменений» | после реализации вопрос потомка о конфигурации тоже критичен; правки change `add-subagents-and-tasks` не нужны |
| `A2aPermissionGate` (после MVP, §17.15.4) | отклоняет запросы с `criticalLabel` | теперь отклоняет и PERM-11 — как и написано в §17.15.4 |
| Scripted-агент `codelab_acp_testing` | режим `with_critical_permission` с меткой `recursive delete` | не меняется; добавляется режим `with_agent_config_write` (D8) |

**Известный предел UX.** Headless с `allow-all` не может править конфигурацию агента вовсе — это намеренно (PERM-11: только человек). Подсказку «как разрешить» в stderr change не добавляет: правильный путь — `codelab config set`/`unset`, правка файла человеком или интерактивный REPL, а любая подсказка «перезапустите с флагом X» звала бы обойти PERM-11. Если пользователь попросит подсказку, это отдельный change `cli-headless`.

### D8. Фикстуры и тестовый агент

Существующие фикстуры не меняются: ни одна не правит путь §7.6.1 через `write`/`edit` (поиск по корпусу `packages/dart/codelab_acp_testing/fixtures/acp`), а `acp/permission-critical-pattern-in-bypass` — про `exec`.

Добавляется golden-фикстура `acp/permission-agent-config-edit-critical` (роли `agent` и `client`, `extensions: ["critical", "outcome"]`, `spec`: `08-Tool Calls.md#requesting-permission`, `15-Extensibility.md#the-_meta-field`) по образцу `acp/permission-critical-pattern-in-bypass` и `acp/tool-write-permission-diff`: режим `bypass`, scripted-модель вызывает `write` с путём `.codelab/config.yaml`; `session/request_permission` — `kind: edit`, первый блок `content` — текст `agent configuration: .codelab/config.yaml`, затем `diff`, `_meta.codelab = {critical: true, label: "write to agent configuration"}`, варианты `allow_once`, `reject_once`, `reject_always` без `allow_always`; клиент отвечает `reject_once`; `tool_call_update` `failed` с `_meta.codelab.outcome: rejected`; `fs/write_text_file` не отправляется. Для агентского драйвера фикстура красная до задачи 1.3, для клиентского — сразу зелёная (клиент уже читает пометку; закрепление).

Scripted-агент `CodelabCompatibleStdioAgent` получает режим `with_agent_config_write`: запрос разрешения на `write .codelab/config.yaml` с той же пометкой. Он нужен матрице e2e CLI (`E2eCliAgent`): тот же тест идёт против scripted, `codelab-agent` и встроенного агента. Против scripted-агента тест проверяет только клиента (агент пометку просто копирует); защиту ядра проверяют прогоны `dart` и `embedded`.

### D9. Пакеты, зависимости, сторож, граф

| Пакет (ADR-0002) | Изменение | Исполнитель |
|---|---|---|
| `codelab_agent_core` | `policy.dart` (метка у PERM-11, поле лога), `agent_config_rules.dart`/`critical_patterns.dart` (константа); тесты | `[agent]` |
| `codelab_agent_acp` | только тест-закрепление gate; агентский прогон фикстуры | `[protocol]` |
| `codelab_acp_testing` | фикстура, режим scripted-агента, список корпуса | `[protocol]` |
| `codelab_client_acp` | запись фикстуры в клиентском прогоне (закрепление) | `[client]` |
| `apps/codelab_cli` | e2e-тест, сценарий модели для `dart`/`embedded` | `[client]` |
| `codelab_embedded`, `codelab_client_core`, `apps/codelab_desktop`, `codelab_ui` | без изменений | — |

Направление зависимостей не меняется, новых зависимостей нет, allowlist ядра (PKG-2) и web-безопасность пакетов не затронуты (новых импортов нет). Новое правило сторожа в `codelab_architecture_tests/test/support/rules.dart` не нужно, граф в `README.md` не меняется.

### D10. Согласование с активными changes

- `add-agent-skills` меняет требование `agent-permissions` «Критические пути правок конфигурации агента» (корни навыков). Чтобы архивирование changes не конфликтовало, этот change требование **добавляет** («Пометка критичности вопроса о конфигурации агента»), а не модифицирует. Пометка распространяется на все пути PERM-11, включая корни навыков, как только `add-agent-skills` их добавит. Ссылка из D19 `add-agent-skills` на этот change остаётся верной при любом порядке слияния.
- `add-subagents-and-tasks` меняет `agent-acp-server` «Расширения протокола этапа 4» — этот change его не трогает (D5) и меняет только «Запросы агента к клиенту».

## Risks / Trade-offs

- **Ложные срабатывания для пользователей `allow-all`.** Сценарии, где headless намеренно правил `.codelab/**`, перестанут работать. Это и есть цель: PERM-11 запрещает такую правку без человека; в `autopilot` она и так отклонялась. Отражается в описании pull request.
- **Сторонние клиенты** получают новый `_meta` у вопроса, который раньше был без него; по `15-Extensibility.md` неизвестный `_meta` игнорируется. Риск — только у клиента, который, вопреки спецификации, падает на `_meta` в `toolCall`; такие клиенты уже ломались на критических командах.
- **Гонки, отмена, поздние события** (§9, §12): не затрагиваются — меняются только поля одного и того же запроса до его отправки; корреляция по `toolCallId` (PERM-4) и обработка отмены gate прежние.
- **Containment** (§10): не затрагивается; `BoundedEnv` и канонизация пути выполняются, как раньше, метка — только представление решения.

## Migration Plan

Миграция данных не нужна: журналы сессий и хранилища решений не меняются (`PermissionDecisionStore` живёт в памяти сессии). Откат — возврат ветки PERM-11 к вызову `_ask` без метки.

## Открытые вопросы

Нет. Решения D1 (метка) и D4 (лог) приняты архитектором по пожеланию пользователя; если пользователь предпочтёт метку `agent configuration` (вариант (б) D1), меняются только константа и ожидания тестов, не структура change.
