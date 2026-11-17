## Why

`ToolKind.fromJson` (`packages/dart/codelab_acp_protocol/lib/src/acp/tool_call.dart`) бросает `JsonRpcProtocolException.invalidShape('toolKind has an unsupported value.')` на любой строке, которой нет в перечислении. Тем же кодеком разбираются все три места, где ACP передаёт вид вызова: `session/update` вида `tool_call` (`parseToolCallJson`), `session/update` вида `tool_call_update` (`parseToolCallUpdateJson`) и `session/request_permission.toolCall` (`ToolCallUpdate.fromJson`, `permission.dart`). Поэтому агент, который присылает вид, незнакомый CodeLab, ломает ход (L-3):

- `tool_call` и `tool_call_update` не применяются: `_handleSessionUpdate` (`codelab_client_acp`, `acp_client_application.dart`) пишет диагностику уровня error `Failed to handle ACP session update.`, вызова нет в транскрипте, его последующие обновления сливаются в запись без заголовка и вида;
- `session/request_permission` получает ответ `cancelled` без участия пользователя (`_handlePermissionRequest`, ветка `on Object`), агент считает ход отменённым пользователем.

Первый такой вид уже есть в самой спецификации ACP: `switch_mode` — «Switching the current session mode» (`docs/protocols/acp/protocol/17-Schema.md`, ToolKind). `12-Session Model.md` («Exiting plan modes») показывает его в `session/request_permission` с вариантом `allow_always` «Yes, and auto-accept all actions». CodeLab такой запрос сейчас молча отменяет. Вид вызова — подсказка для отображения («Tool kinds help Clients choose appropriate icons», `08-Tool Calls.md`, «Creating»), и отказ всего сообщения из-за подсказки противоречит правилу совместимости вперёд (`AGENTS.md` §7, `acp-boundary.md` §18, §22). При этом неизвестный вид не должен считаться безопасным (`AGENTS.md` §10, `permissions.md` §12).

## What Changes

- `ToolKind` получает значение `switchMode` с wire-именем `switch_mode` — оно определено в `17-Schema.md`; порядок значений как в схеме: перед `other`.
- `ToolKind.fromJson` на строке, которой нет в перечислении, возвращает `ToolKind.other` вместо ошибки формы. Не-строка (число, объект, массив, `bool`) по-прежнему даёт `invalidShape`. `null` и отсутствие поля ведут себя как раньше: у `tool_call` — `other`, у `tool_call_update` и `session/request_permission.toolCall` — «вид не передан» (`null`).
- `codelab_acp_protocol` получает чистую функцию `unrecognizedToolKind(Object? toolCall)` — исходное строковое значение `kind` сырого объекта вызова, если оно не входит в `ToolKind`, иначе `null`. Образец — `unsupportedSessionUpdateKind` (`session_update.dart`). Логгера в протоколе нет.
- `AcpClientApplication` после успешного разбора `session/update` (`tool_call`, `tool_call_update`, в том числе в реплее `session/load`) и `session/request_permission` сверяет сырой payload через `unrecognizedToolKind` и пишет в application-журнал одну запись уровня WARN `Unknown ACP tool kind treated as other.` с `session_id`, `tool_call_id`, `connection_generation`, методом и исходным значением вида (усечено до 64 символов, проходит маскирование). Payload в эту запись не попадает: он уже есть в developer-only protocol-трассировке входящих кадров.
- Незнакомый вид в `tool_call_update` и в `session/request_permission.toolCall` не перезаписывает известный вид записи вызова (метка `Run` у вызова `execute` остаётся), а риск становится `max(риск записи, unknown)`: вызов `read` с незнакомым видом требует явного одобрения. Признак деградации `AcpClientApplication` вычисляет по `unrecognizedToolKind` и проводит через буферы реплея и ранних обновлений в `SessionStateMachine`. Явный `kind: "other"` от агента перезаписывает вид по общему правилу. Если записи нет (первым пришёл `tool_call` с незнакомым видом или запрос разрешения на незнакомый вызов), вид — `other`, риск — `unknown` (D9).
- Риск: `switchMode` — `ApprovalRiskLevel.unknown` (явное одобрение, тег `Unknown risk`), не `readOnly`: одобрение смены режима может включить автоодобрение всех следующих действий. Неизвестный вид становится `other` и получает `unknown` по уже действующему правилу итерации 6b change `add-provider-setup-ui` (D27, Q32). Правило «риск вызова не понижается» (`ApprovalPolicy.classifyToolCallUpdateWithin`) по логике не меняется: обновление с незнакомым видом сохраняет в DTO `kind: other`, классифицируется как `unknown` и берёт `max` с риском записи (D9).
- Headless CLI `--approve read-only` разрешает запрос (`allow_once`) только если вид вызова `read` и риск одобрения `readOnly`; иначе `reject_once`. Без этого по D9 запрос с `future_kind` или `switch_mode` к записи `read` одобрялся бы без человека (D5).
- Транскрипт: `ToolRowFormatter` даёт вызову `switchMode` метку `Mode`; деталь — по общему правилу (`title` вызова, если в `rawInput` нет подходящего скалярного поля). Desktop и `codelab_ui` кода не меняют: строка вызова рисуется по `ToolRowView`, тег риска — по `ApprovalRiskLevel`; добавляется регрессионный тест маппера.
- Новая golden-фикстура `acp/tool-kind-unknown-tolerated` с ролью `client`: `tool_call` с неизвестным видом, `tool_call_update` с неизвестным видом и вызов `switch_mode` с `session/request_permission` по образцу `12-Session Model.md`.

## Не входит

- Агентская сторона. Dart-агент `switch_mode` не порождает: в `ToolKind` ядра (`codelab_agent_core`, `agent_tool.dart`) значения нет и не добавляется. Проекции `codelab_agent_acp` (`event_projection.dart`, `acp_permission_gate.dart`, `replay.dart`) отображают вид ядра в ACP через `acp.ToolKind.values.byName(<имя вида ядра>)`; новое значение ACP их не ломает, это закрепляет регрессионный тест (D6).
- Сохранение исходного значения неизвестного вида в DTO и его обратная сериализация (`toJson` даёт `other`): осознанный компромисс D3.
- Отдельная обработка `current_mode_update` после одобрения `switch_mode`: обновление режима уже обрабатывается требованием «Жизненный цикл prompt turn» и «Идемпотентные переходы состояния».
- Подсказка в карточке одобрения `switch_mode` о том, что вариант `allow_always` («auto-accept all actions») может включить автоодобрение: текст вариантов задаёт агент, ACP определяет только `PermissionOptionKind`; карточка показывает варианты агента без изменений (решение пользователя по Q1).
- Мягкий разбор других перечислений протокола — `ToolCallStatus`, `PlanEntryStatus`, `PlanEntryPriority`, `PermissionOptionKind`, `StopReason`: их строгий разбор остаётся. У `ToolKind` есть безопасное значение по умолчанию, определённое ACP (`other`), и он лишь подсказка отображения; у остальных значение несёт семантику состояния или решения (статус вызова, исход хода, вид варианта разрешения), и подмена незнакомого значения известным исказила бы состояние или решение пользователя (`AGENTS.md` §2, приоритеты 2–4; решение пользователя по Q2).
- Видимость деградации в диагностике сессий и панели Debug log (`_recordDiagnostic`): только запись WARN в application-журнал (D4; решение пользователя по Q3).
- Новых методов, полей или состояний ACP нет; новых пакетов и зависимостей нет.

## Capabilities

### Modified Capabilities
- `acp-protocol-client`: новое требование «Неизвестный вид вызова инструмента» — разбор `kind`, `switch_mode`, запись в журнал.
- `approval-safety`: новое требование «Риск вызова неизвестного вида и смены режима».
- `acp-client-kit`: требование «Строка инструмента без сырого JSON» — метка `Mode` для `switch_mode`.
- `agent-workbench-ui`: новое требование «Вызов смены режима и неизвестного вида в ленте».
- `cli-headless`: требование «Политика одобрений headless» — `read-only` по виду и риску.
- `acp-golden-fixtures`: новое требование «Фикстура неизвестного вида вызова».

## Impact

- `packages/dart/codelab_acp_protocol/lib/src/acp/tool_call.dart`: `ToolKind.switchMode`, мягкий `ToolKind.fromJson`, функция `unrecognizedToolKind`; тесты `permission_test.dart`, `session_update_tolerance_test.dart`, `session_update_test.dart`.
- `packages/dart/codelab_client_acp/lib/src/domain/approval_policy.dart` (`_riskForKind`), `lib/src/application/acp_client_application.dart` (`_handleSessionUpdate`, `_handlePermissionRequest`, буферы `_sessionReplays` и `_earlyUpdates`: запись журнала и признак `toolKindUnrecognized`, D9), `lib/src/domain/state_machines.dart` (признак `toolKindUnrecognized` полем публичных событий `PromptTurnStateEvent.update` и `SessionStateEvent.update`, у `replayHistory` и `_mergeToolCallUpdate`), doc-комментарий `classifyToolCallUpdateWithin`; тесты `test/` пакета.
- `packages/dart/codelab_client_core/lib/src/transcript/tool_row.dart` (`_labelOf`, `_detailOf`); тест `test/transcript/tool_row_test.dart`.
- `packages/dart/codelab_acp_testing/fixtures/acp/tool-kind-unknown-tolerated.json`; клиентский прогон корпуса (`codelab_client_acp/test/fixtures/client_fixture_conformance_test.dart`).
- `packages/dart/codelab_agent_acp/test/`: регрессионный тест отображения видов ядра в ACP.
- `apps/codelab_desktop/test/features/workbench/application/ui_mappers_test.dart`: регрессионный тест строки вызова.
- `apps/codelab_cli/lib/src/headless/approval_policy.dart` (`decideApproval`) и `apps/codelab_cli/test/headless/approval_policy_test.dart`.
- Зависимость по порядку архивации: требования этого change опираются на `ApprovalRiskLevel.unknown` и тег `Unknown risk` из активного change `add-provider-setup-ui` (требования «Неизвестный уровень риска вызова» acp-client-kit и «Тег неизвестного риска одобрения» agent-workbench-ui). Код итерации 6b уже в `develop`; архивировать этот change СЛЕДУЕТ после `add-provider-setup-ui`.
- Сторож (`codelab_architecture_tests/test/support/rules.dart`) и граф пакетов `README.md` не меняются.
