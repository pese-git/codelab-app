## Context

Вид вызова инструмента (`ToolKind`) приходит клиенту в трёх сообщениях ACP, и все три разбирает один кодек `codelab_acp_protocol` (`lib/src/acp/tool_call.dart`):

| Сообщение | Разбор | `kind` нет или `null` |
|---|---|---|
| `session/update` `tool_call` | `parseToolCallJson` (`session_update.dart`) | `ToolKind.other` (ACP: «other (default)», `17-Schema.md`) |
| `session/update` `tool_call_update` | `parseToolCallUpdateJson` | `null` — «не меняется» |
| `session/request_permission` `toolCall` | `ToolCallUpdate.fromJson` (`permission.dart`) | `null` |

`ToolKind.fromJson` строгий: строка вне перечисления — `invalidShape`. Последствия в клиенте (`codelab_client_acp`, `acp_client_application.dart`):

- `_handleSessionUpdate`: исключение ловит `on Object`, пишет `_recordDiagnostic` уровня error `Failed to handle ACP session update.` с полным `params` в `context`; обновление теряется, в том числе в реплее `session/load` (реплей идёт тем же путём);
- `_handlePermissionRequest`: исключение ловит `on Object`, клиент отвечает `cancelled` и пишет error `Failed to handle ACP permission request.`; пользователь запроса не видит.

ACP определяет вид `switch_mode` («Switching the current session mode», `17-Schema.md`), которого в `ToolKind` CodeLab нет. `12-Session Model.md`, «Exiting plan modes»: инструмент выхода из plan-режима запрашивает разрешение с `kind: "switch_mode"` и вариантами `allow_always` «Yes, and auto-accept all actions», `allow_once` «Yes, and manually accept actions», `reject_once` «No, stay in architect mode»; после выбора агент меняет режим и шлёт `current_mode_update`. Перечень видов в `08-Tool Calls.md` (`switch_mode` там не назван) отстаёт от схемы; источник истины для перечня — `17-Schema.md`.

ACP не говорит, как клиенту обращаться с незнакомым значением `ToolKind`. Он говорит, что вид — подсказка для отображения («Tool kinds help Clients choose appropriate icons and optimize how they display tool execution progress», `08-Tool Calls.md`, «Creating»), а `other` — значение по умолчанию. Решение «незнакомая строка → `other`» — политика клиента, а не новая семантика ACP (`AGENTS.md` §3.4): на wire ничего не добавляется и не отправляется.

Уровень риска `ApprovalRiskLevel.unknown` введён итерацией 6b change `add-provider-setup-ui` (D27, Q32; код уже в `develop`, коммит `9cd48f24`): `other` и отсутствующий вид — `unknown`, выше `readOnly`, ниже `localWrite`, режимы разрешений требуют для него явного одобрения. `ApprovalPolicy.classifyToolCallUpdateWithin` (review 6b, L-1) — единое правило «риск вызова не понижается» для слияния `tool_call_update` и для `ApprovalRequest`.

Существующие образцы мягкого разбора в протоколе:
- `unsupportedSessionUpdateKind(params)` (`session_update.dart`) — чистая функция над сырыми params; клиент вызывает её до разбора и пишет запись журнала (`_skipUnsupportedSessionUpdate`: DEBUG в application-журнал без payload, payload — в developer-only protocol-трассировку);
- `McpServer.unknown(raw)` (`session.dart`, D11 change `add-agent-mcp-client`) — вариант с сохранённым сырым объектом и обратной сериализацией как есть;
- `_tryParseSessionConfigOption` — пропуск опции незнакомого `type`;
- `tolerateUnknownRootFields` — зона, в которой лишние корневые поля игнорируются.

Ограничения: `AGENTS.md` §2 (безопасность выше UX), §3.4, §7, §10, §13, §15, §16; `acp-boundary.md` §18–§19, §22; `permissions.md` §12 («сохранить как unknown, залогировать, не интерпретировать как известную, conservative security policy»); `observability.md` §8 (warning — «recoverable abnormal condition… unknown optional field»), §11 (payload не в release-журнал).

## Goals / Non-Goals

**Goals:** вызов с незнакомым строковым видом не ломает ни `tool_call`, ни `tool_call_update`, ни `session/request_permission`; `switch_mode` распознаётся по имени; ни незнакомый вид, ни `switch_mode` не получают риска ниже `unknown`, если вид вызова ещё неизвестен; незнакомый вид в обновлении не стирает известный вид записи и не понижает её риск; деградация видна в журнале с корреляцией; поведение закреплено golden-фикстурой.

**Non-Goals:**
- выдача `switch_mode` Dart-агентом (D6);
- сохранение исходного значения вида для обратной сериализации (D3);
- подсказка в карточке одобрения `switch_mode` о варианте `allow_always` («auto-accept all actions»): текст вариантов — от агента, ACP задаёт только `PermissionOptionKind`, а клиент показывает варианты без изменений (решение пользователя по Q1);
- мягкий разбор `ToolCallStatus`, `PlanEntryStatus`, `PlanEntryPriority`, `PermissionOptionKind`, `StopReason`. У `ToolKind` есть значение по умолчанию из ACP (`other`), и вид — только подсказка отображения, поэтому подмена незнакомого значения на `other` ничего не искажает, а риск остаётся консервативным (D5). У остальных перечислений значение несёт семантику: статус вызова (завершён он или нет), исход хода, вид варианта разрешения (разрешить или отклонить). Безопасного значения по умолчанию нет, и подмена исказила бы состояние хода или решение пользователя (приоритеты 2–4 `AGENTS.md` §2). Незнакомое значение там остаётся ошибкой формы (решение пользователя по Q2);
- показ деградации в диагностике сессий и в панели Debug log (D4; решение пользователя по Q3).

## Decisions

### D1. Незнакомая строка `kind` → `ToolKind.other` в `ToolKind.fromJson`

`ToolKind.fromJson(Object? value)`:
- строка из перечисления — соответствующее значение (включая новое `switch_mode`, D2);
- любая другая строка, включая пустую, — `ToolKind.other`;
- не-строка (число, `bool`, объект, массив) — `invalidShape('toolKind must be a string.')`.

Ветки «`null` или нет поля» остаются в `parseToolCallJson` (`other`) и `parseToolCallUpdateJson` (`null`) без изменений; `fromJson` для `null` по-прежнему не вызывается. Не-строка — нарушение формы схемы (`ToolKind` — union строк), а не «будущее значение», поэтому остаётся ошибкой; её путь в клиенте (диагностика error, обновление не применяется, запрос разрешения — `cancelled`) не меняется.

Альтернативы:
- оставить строгий разбор и пропускать всё обновление, как `usage_update` — отклонено: теряется вызов с его статусом и содержимым, а запрос разрешения всё равно пришлось бы отменять;
- сделать `ToolKind` sealed-классом с вариантом `unknown(raw)` по образцу `McpServer.unknown` — отклонено: меняется публичный тип протокола, все exhaustive switch по `ToolKind` в клиенте, CLI и трёх проекциях агента, а выгода — только точная обратная сериализация, которая никому не нужна (D3). Решение пользователя — `other`;
- поле `rawKind` в `ToolCall`/`ToolCallUpdate` — отклонено: поле, которого нет в ACP, в wire-модели (`AGENTS.md` §7: DTO отражает протокол), и оно расползлось бы по `copyWith` и `toJson`.

### D2. `ToolKind.switchMode` с wire `switch_mode`

Значение добавляется перед `other`, в порядке `17-Schema.md`. Индекс значений нигде не используется: `fromJson` ищет по `wireName`, проекции агента — по имени (`values.byName`). Тест перечня wire-имён (`permission_test.dart`) обновляется.

Альтернатива — не вводить значение и полагаться на D1 (`switch_mode` → `other`) — отклонена: вид определён ACP, отображение по `title` у `other` хуже метки `Mode`, а запись WARN о «неизвестном» виде на каждый выход из plan-режима — ложная тревога.

### D3. Исходное значение незнакомого вида при обратной сериализации теряется

`ToolCall.toJson` / `ToolCallUpdate.toJson` после D1 пишут `"kind": "other"`. Где это проявляется:

- клиент ACP-сообщения с видом вызова не отправляет: `tool_call`, `tool_call_update` и `session/request_permission` идут только агент → клиент. Ответ на `session/request_permission` (`RequestPermissionResponse`) вида не несёт;
- клиентский драйвер golden-фикстур (`codelab_acp_testing`, `client_conformance.dart`) подаёт кадры `a2c` клиенту как есть и сравнивает только кадры `c2a` — вид в них не участвует;
- инспектор (`codelab_client_core`, `inspector_projection.dart`) показывает `Kind` как `kind.wireName` декодированного DTO — для незнакомого вида в `tool_call` и `tool_call_update` это `other` (DTO по D9 не переписывается), хотя метка строки транскрипта у обновления берёт вид записи. Исходный кадр с настоящим значением остаётся в developer-only protocol-трассировке входящих сообщений (`_traceProtocolMessage('inbound', …)` до ACP-разбора) и в записи WARN (D4);
- агент сериализует только свои виды (`codelab_agent_core` → `acp.ToolKind`), незнакомых строк у него не бывает; журнал сессий агента хранит вид ядра, а не ACP (`records.dart`).

Это осознанный компромисс: точность обратной сериализации отдаётся за неизменный публичный тип (D1). Если появится место, где клиент пересылает чужой `tool_call` дальше (прокси, экспорт сессии в ACP-формате), решение пересматривается отдельным change.

### D4. Запись в журнал — в `AcpClientApplication`, по сырому payload, через чистую функцию протокола

`codelab_acp_protocol` получает функцию рядом с `ToolKind`:

```dart
/// Исходное строковое значение `kind` сырого объекта вызова, если его нет в
/// [ToolKind]; иначе `null` (нет поля, `null`, известный вид, не-строка,
/// не объект).
String? unrecognizedToolKind(Object? toolCall);
```

`AcpClientApplication` после успешного разбора:
- `_handleSessionUpdate` — для `SessionUpdate.toolCall` и `SessionUpdate.toolCallUpdate` вызывает `unrecognizedToolKind(params['update'])` (в том числе для обновлений, которые уходят в буфер реплея `session/load` или ранних обновлений);
- `_handlePermissionRequest` — `unrecognizedToolKind(params['toolCall'])`, до проверки активного хода (запрос, отвеченный `cancelled` из-за отсутствия хода, тоже фиксируется).

При ненулевом результате — одна запись application-журнала уровня WARN, компонент `protocol`:
- текст `Unknown ACP tool kind treated as other.`;
- корреляция `connection_generation`, `session_id`, `tool_call_id` (из декодированного DTO) — через `withCorrelation`;
- `context`: `source: application.protocol`, `method` (`session/update` или `session/request_permission`), `sessionUpdate` (`tool_call` / `tool_call_update`, только для `session/update`), `toolKind` — исходное значение, усечённое до 64 символов и пропущенное через `SecretRedactor.redactText`.

Payload в запись не входит (`observability.md` §11): полный кадр уже есть в protocol-трассировке. `_recordDiagnostic` не вызывается: деградация не мешает работе, а `_recordDiagnostic` добавляет запись в `diagnostics` каждой сессии и публикует новое состояние всех сессий на каждое такое сообщение — та же причина, по которой `_skipUnsupportedSessionUpdate` пишет только в журнал. Пользователь видит последствие в самой ленте — тег `Unknown risk` у ждущего одобрения (D5). Уровень WARN, а не DEBUG, как у пропущенного `usage_update`: здесь клиент не пропускает данные, а меняет их смысл (сводит вид к `other`), и это должно быть видно в журнале release без включения трассировки.

Дедупликации нет: запись — на каждое сообщение с незнакомым видом. Агенты повторяют `kind` в `tool_call_update` редко; лишнее состояние «уже сообщали для `tool_call_id`» со своим жизненным циклом (сброс при переподключении, закрытии сессии) здесь не окупается (§13).

Альтернативы:
- логгер или callback в кодеке — отклонено: протокол не знает логгера (`acp-boundary.md`: protocol layer без side effects), а callback пришлось бы протаскивать через `decodeAcpNotificationParams` и `decodeAcpRequestParams` для всех методов;
- предупреждение через зону, как `tolerateUnknownRootFields` — отклонено: скрытый канал побочного результата разбора, и он теряет корреляцию;
- сравнивать декодированный `kind == other` с сырым значением в клиенте вручную — это и делает D4, но правило «что считается известным видом» остаётся в одном месте — в протоколе рядом с перечнем;
- `_recordDiagnostic` уровня warning — отклонено по причине выше; решение пользователя по Q3 — только журнал.

### D5. Риск: `switchMode` → `ApprovalRiskLevel.unknown`

`_riskForKind` (`codelab_client_acp`, `approval_policy.dart`): `ToolKind.switchMode || ToolKind.other || null => ApprovalRiskLevel.unknown`. Не `readOnly`: одобрение смены режима само ничего не пишет, но может включить автоодобрение всех следующих действий («Yes, and auto-accept all actions», `12-Session Model.md`) — по последствиям это не «только чтение» (`AGENTS.md` §10, `permissions.md` §12). Не `destructive`/`shell`: смена режима не исполняет команд, а завышенный риск обесценивает тег.

Незнакомый вид в `tool_call` после D1 — `other` и получает `unknown` по уже действующему правилу (D27 change `add-provider-setup-ui`). Незнакомый вид в `tool_call_update` и в `session/request_permission` по D9 даёт вид для отображения из записи, а риск слияния и `ApprovalRequest` по-прежнему считает `classifyToolCallUpdateWithin` по `kind: other`, поэтому:
- у вызова без известной записи — вид `other`, риск `unknown` (классификация `kind == null`);
- у вызова `execute` — вид `execute`, риск `shell` (`max(shell, unknown)`);
- у вызова `read` — вид `read`, риск `unknown` (`max(readOnly, unknown)`), явное одобрение.

Режимы разрешений клиента (`ApprovalPolicy.decidePermission`) для `unknown` уже требуют явного одобрения во всех режимах; новых ветвей нет. Политика headless CLI (`apps/codelab_cli`, `decideApproval`) сравнивает только с `ToolKind.read` и для `switchMode` в режиме `--approve read-only` отклоняет — без изменений.

### D6. Агентская сторона не меняется; новое значение ACP её не ломает

`codelab_agent_acp` отображает вид ядра в ACP по имени: `acp.ToolKind.values.byName(kind.name)` в `event_projection.dart`, `acp_permission_gate.dart`, `replay.dart`. Имена `ToolKind` ядра (`read, edit, delete, move, search, execute, think, fetch, other`) — подмножество имён ACP-перечисления и после D2; добавление значения в ACP-перечисление `byName` не ломает. Обратного отображения ACP → ядро нет. Регрессионный тест в `codelab_agent_acp/test/` закрепляет: каждое значение `ToolKind` ядра находит ACP-значение с тем же wire-именем (кроме различия `snake_case`, которого у видов ядра нет). Выдача `switch_mode` агентом — вне scope; ядро не получает значения `switchMode`.

### D7. Метка транскрипта `Mode`; desktop без кода

`ToolRowFormatter._labelOf`: `ToolKind.switchMode => 'Mode'`. `_detailOf`: `switchMode` идёт веткой без собственных полей — деталь пуста, и общее правило §12.1.6 подставляет `title` вызова («Mode Ready for implementation»). Поля `rawInput` для `switch_mode` ACP не определяет, поэтому догадок об их именах (`modeId`, `mode`) нет.

Desktop (`ui_mappers.dart`, `_toolCallRowOf`) берёт метку и деталь из `ToolRowView`, а тег риска — из `ApprovalRiskLevel` (`Unknown risk` введён итерацией 6b). Exhaustive switch по `ToolKind` в `apps/codelab_desktop` и `packages/flutter/codelab_ui` нет (проверено поиском `ToolKind\.`), значков по виду нет. Поэтому `[desktop]` — только регрессионный тест маппера; новый значок не вводится (§13). CLI и TUI рисуют вызов по `title` и статусу (`apps/codelab_cli/lib/src/render/tool_row.dart`) — без изменений.

### D8. Golden-фикстура `acp/tool-kind-unknown-tolerated` только для роли `client`

Сценарий по образцу `acp/errors-unknown-session-update-tolerated`: `roles: ["client"]` (Dart-агент таких видов не выдаёт), `spec` — `08-Tool Calls.md#creating`, `08-Tool Calls.md#updating`, `08-Tool Calls.md#requesting-permission`, `12-Session Model.md#exiting-plan-modes`, `17-Schema.md#toolkind`, `05-Prompt Turn.md#4-check-for-completion`. Кадры:
1. `c2a` `session/prompt`;
2. `a2c` `tool_call` `call_future` с `kind: "future_kind"` (значение, которого нет в `17-Schema.md`), `status: pending`;
3. `a2c` `tool_call_update` `call_future` с `kind: "future_kind"`, `status: completed`;
4. `a2c` `tool_call` `call_switch_mode_001` с `title` «Ready for implementation», `kind: "switch_mode"`, `status: pending`;
5. `a2c` `session/request_permission` для `call_switch_mode_001` с `kind: "switch_mode"` и тремя вариантами из `12-Session Model.md`;
6. `c2a` ответ `selected` `reject` (тест выбирает «No, stay in architect mode» — без смены режима, чтобы не зависеть от состояния режимов профиля);
7. `a2c` `tool_call_update` `call_switch_mode_001` `status: failed`;
8. `a2c` ответ `session/prompt` `end_turn`.

Фикстура доказывает, что ход не ломается и запрос разрешения доходит до пользователя (иначе кадр 6 был бы `cancelled`). Состояние (вид, риск) проверяет отдельный тест клиента на той же фикстуре (задача 1.6). Не-строковый `kind` в фикстуру не входит: это ошибка формы, её закрепляют модульные тесты, а «битый кадр не ломает ход» уже закреплён `acp/errors-bad-frame-survives`. Покрытие FIX-2 не меняется: виды `sessionUpdate` и методы те же.

### D9. Незнакомый вид в обновлении: вид для отображения — из записи, риск — не ниже `unknown`

Если в `tool_call_update` или в `toolCall` запроса `session/request_permission` строковый `kind` незнаком (D1 свёл его к `other`), то:
- **вид записи** (метка строки) берётся из уже существующей записи вызова: метка `Run` у `execute`, `Read` у `read` остаётся; без записи — `other`;
- **риск** — `max(риск записи, unknown)`: незнакомый вид — неизвестная capability, и считать вызов «только чтением» нельзя (`AGENTS.md` §10, приоритет 1 §2). `ApprovalPolicy.decidePermission` отдаёт `allowWithoutApproval` для `readOnly` во всех режимах, поэтому вид `read` из записи без нижней границы `unknown` разрешал бы политике одобрить такой запрос без пользователя. Сейчас в production решение режима для автоодобрения не вызывается (клиент показывает каждый запрос), но риск — контракт политики, и тег `Read-only` у вызова незнакомого вида вводил бы в заблуждение (решение пользователя);
- явный `kind: "other"` агента — известное значение: `unrecognizedToolKind` его не отмечает, и он перезаписывает вид по общему правилу `update.kind ?? current.kind`;
- последующие обновления риск не понижают — правило `max` в `classifyToolCallUpdateWithin` (L-1) уже есть.

**Форма признака — минимальная.** Декодированный `ToolCallUpdate` не переписывается: его `kind` остаётся `other`, как его отдал кодек (D1). Отсюда риск получается без новых ветвей: `classifyToolCallUpdateWithin(current, update)` подставляет вид записи только при `update.kind == null`, а для `other` классифицирует `unknown` и берёт `max` с `current.riskLevel` — ровно `max(риск записи, unknown)`. Поэтому сигнатура и логика `ApprovalPolicy` не меняются; меняется только doc-комментарий `classifyToolCallUpdateWithin` (ссылка на D9). Признак нужен лишь для выбора **вида для отображения** и проводится одним булевым значением `toolKindUnrecognized`:
- домен (`codelab_client_acp`, `state_machines.dart`): необязательный именованный параметр `{bool toolKindUnrecognized = false}` у `SessionStateMachine.applyUpdate` и внутренних `_applyUpdateToTurn` → `_mergeToolCallUpdate`; у `SessionStateMachine.replayHistory` — необязательный `Set<int> toolKindUnrecognizedAt = const {}` (индексы в списке `updates`). В `_mergeToolCallUpdate`: `kind = toolKindUnrecognized && current != null ? current.kind : update.kind ?? current?.kind ?? ToolKind.other`; строка `riskLevel` не меняется. Значения по умолчанию сохраняют все существующие вызовы и тесты;
- приложение (`acp_client_application.dart`): буферы `_sessionReplays` и `_earlyUpdates` хранят вместо `SessionUpdate` запись Dart `({SessionUpdate update, bool toolKindUnrecognized})`; признак вычисляется один раз в `_handleSessionUpdate` по сырому `params` (D4) и кладётся рядом с обновлением; при применении раннего буфера он передаётся в `applyUpdate`, при реплее — индексами в `replayHistory`;
- запрос разрешения не буферизуется: `_toolCallRecordFromUpdate(update, known:, toolKindUnrecognized:)` выбирает вид тем же правилом, риск — прежним вызовом `classifyToolCallUpdateWithin(known, update)`.

**Почему признак не теряется.** Нижняя граница риска закодирована в самом DTO (`kind: other`), а не в признаке; признак управляет только видом для отображения. Поэтому:
- *дедупликация* (`_latestOfKind(turn.updates, update) == update`) сравнивает DTO. Повтор того же деградировавшего обновления — дубль, но равное ему обновление уже применено и уже подняло риск. Если раньше пришёл равный по DTO явный `other`, деградировавшее обновление отбрасывается, риск уже `≥ unknown`, вид — `other` от явного значения. Обратный порядок (сначала деградация, затем равный явный `other`) отбросит явный `other`, и вид останется видом записи — расхождение только в метке, риск тот же;
- *реплей `session/load`*: признак лежит в том же элементе буфера, что и обновление, и доходит до `replayHistory` индексом; буфер — список только для добавления, которым владеет одна загрузка, порядок и индексы стабильны;
- *ранний буфер*: признак в том же элементе, `applyUpdate` получает его при применении;
- *запись WARN* (D4) пишется при приёме, до буферов, — по одной на сообщение и в реплее.

`tool_call` (полный снимок) признак не использует: `ToolCall.kind` всегда задан, повтор `tool_call` с тем же id заменяет данные записи, а риск не понижается (L-2); незнакомый вид в нём — `other`.

Альтернативы:
- переписать обновление в `copyWith(kind: null)` («как будто без `kind`») — отклонено: вид записи сохраняется, но риск у записи `read` остаётся `readOnly` (см. выше), а дедупликация не отличает деградацию от настоящего отсутствия `kind` и может отбросить обновление вместе с нижней границей;
- параметр «нижняя граница риска» у `classifyToolCallUpdateWithin` и `applyUpdate` — отклонено как лишний: граница уже следует из `kind: other` в DTO, второй источник того же правила мог бы разойтись с первым;
- поле признака в `ToolCallUpdate` или в `_meta` — отклонено: поле, которого нет в ACP, в wire-модели (D1, `AGENTS.md` §7);
- собственный доменный класс-обёртка обновления для буферов и `replayHistory` — отклонено: меняет обязательную сигнатуру и 40 с лишним вызовов в тестах ради одного булева значения; необязательные параметры дают то же.

### Затронутые пакеты и зависимости

| Пакет | Слой (ADR-0002) | Изменение | Исполнитель |
|---|---|---|---|
| `codelab_acp_protocol` | общий, `protocol` | `ToolKind.switchMode`, мягкий `fromJson`, `unrecognizedToolKind` | `[protocol]` |
| `codelab_acp_testing` | общий, `testing` | фикстура `acp/tool-kind-unknown-tolerated` | `[protocol]` |
| `codelab_agent_acp` | `agent`, `acp` | только регрессионный тест | `[protocol]` |
| `codelab_client_acp` | `client`, `acp` | риск `switchMode`, запись WARN; признак `toolKindUnrecognized` в буферах, `SessionStateMachine` и `_toolCallRecordFromUpdate`, doc-комментарий `classifyToolCallUpdateWithin` (D9) | `[client]` |
| `codelab_client_core` | `client`, `core` | метка `Mode` | `[client]` |
| `apps/codelab_desktop` | приложение | только регрессионный тест | `[desktop]` |

Направление зависимостей прежнее: `codelab_client_acp` → `codelab_acp_protocol`; новых рёбер нет. Новое правило сторожа в `codelab_architecture_tests/test/support/rules.dart` не нужно: пакетов и импортов не добавляется. Граф в `README.md` не меняется. Web-безопасность: `tool_call.dart` остаётся чистым Dart без `dart:io`. Allowlist зависимостей ядра (PKG-2) не затронут: ядро агента не меняется.

## Risks / Trade-offs

- **Агент полагается на новый вид с особым смыслом.** Клиент покажет такой вызов как `other` с риском `unknown` и потребует явного одобрения — безопасное направление ошибки (`permissions.md` §12).
- **Шум WARN.** Агент, который шлёт незнакомый вид в каждом `tool_call_update`, даст запись на каждое обновление. Записи короткие, без payload; дедупликация отложена (D4).
- **Агент меняет вид вызова на незнакомый посреди хода.** Метка остаётся прежней, риск поднимается не ниже `unknown` (D9); исходное значение видно в записи WARN и protocol-трассировке.
- **Расхождение метки при дедупликации.** Деградировавшее обновление, за которым следует равный по DTO явный `other`, оставляет вид записи вместо `other`; риск не затронут (D9).
- **Порядок архивации.** Дельты ссылаются на `ApprovalRiskLevel.unknown` и тег `Unknown risk` из дельт активного change `add-provider-setup-ui`; этот change архивируется после него. Дельта `add-provider-setup-ui` не правится.
- **Отмена и поздние события.** Логика отмены не меняется: запрос разрешения `switch_mode` в отменяемом ходе по-прежнему получает `cancelled` (`_handlePermissionRequest`, ветка `cancelling`), запись WARN при этом пишется до ответа. Поздний `tool_call_update` с незнакомым видом после ответа на `session/prompt` применяется или отбрасывается теми же правилами, что и с известным видом.

## Решённые вопросы

- **Q1.** Подсказка о варианте `allow_always` в карточке `switch_mode` — не делается, Non-Goal (решение пользователя).
- **Q2.** Мягкий разбор — только для `ToolKind`; остальные перечисления — Non-Goal с обоснованием в «Goals / Non-Goals» (решение пользователя).
- **Q3.** Только запись WARN в application-журнал, без `_recordDiagnostic` (D4; решение пользователя).
- **Q4.** Незнакомый вид в обновлении не перезаписывает известный вид записи, риск — `max(риск записи, unknown)`; явный `other` перезаписывает (D9; решение пользователя).
