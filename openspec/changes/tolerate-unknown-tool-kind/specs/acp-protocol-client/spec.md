## ADDED Requirements

### Requirement: Неизвестный вид вызова инструмента
CodeLab SHALL разбирать поле `kind` вызова инструмента одинаково в `session/update` вида `tool_call`, `session/update` вида `tool_call_update` (в том числе в реплее `session/load`) и в `toolCall` запроса `session/request_permission`:
- строка из перечня `ToolKind` `docs/protocols/acp/protocol/17-Schema.md` — соответствующий вид, включая `switch_mode` («Switching the current session mode»);
- любая другая строка — вид `other`, без диагностики уровня error; в `tool_call` сообщение SHALL обрабатываться так же, как с видом `other`, а в `tool_call_update` и `toolCall` запроса `session/request_permission` вид для отображения SHALL браться из существующей записи вызова (без записи — `other`), а риск SHALL определяться видом `other` (требование «Риск вызова неизвестного вида и смены режима» approval-safety); признак деградации SHALL сохраняться для обновлений, отложенных в реплей `session/load`; обновление вызова, пришедшее до ответа `session/new`, когда у сессии ещё нет хода, отбрасывается, как и раньше;
- не-строка (число, `bool`, объект, массив) — ошибка формы `invalidShape`, как раньше;
- `null` или отсутствие поля — как раньше: у `tool_call` вид `other`, у `tool_call_update` и `session/request_permission` вид «не передан».

Для каждого сообщения, в котором строковый `kind` не входит в перечень, CodeLab SHALL записать в application-журнал одну запись уровня WARN с текстом `Unknown ACP tool kind treated as other.`, идентификаторами `session_id`, `tool_call_id` и поколения соединения, методом, видом обновления (для `session/update`) и исходным значением `kind`: значение SHALL сначала маскироваться целиком, затем усекаться до 64 символов. Запись SHALL писаться при приёме сообщения, в том числе для обновлений, которые затем отбрасываются (неизвестная сессия, нет хода). Запись SHALL NOT содержать payload сообщения. Обратная сериализация такого вызова (`toJson`) SHALL давать `"kind": "other"`. Явный `kind: "other"` в `tool_call_update` SHALL перезаписывать вид записи, как любой известный вид (design.md change `tolerate-unknown-tool-kind`, D1, D3, D4, D9).

#### Scenario: tool_call с незнакомым видом
- **WHEN** во время хода агент присылает `tool_call` с `kind: "future_kind"`
- **THEN** CodeLab добавляет в ход запись вызова с видом `other`, не создаёт диагностику уровня error, продолжает принимать обновления и ответ на `session/prompt`

#### Scenario: tool_call_update с незнакомым видом сохраняет известный вид
- **WHEN** вызов пришёл с `kind: "execute"`, затем агент присылает `tool_call_update` того же вызова с `kind: "future_kind"` и `status: "completed"`
- **THEN** CodeLab применяет обновление: статус вызова — `completed`, вид — по-прежнему `execute`

#### Scenario: Первым пришёл tool_call с незнакомым видом
- **WHEN** агент присылает `tool_call` с `kind: "future_kind"`, затем `tool_call_update` того же вызова с `kind: "future_kind"` и `status: "completed"`
- **THEN** вид записи — `other` после обоих сообщений, статус — `completed`

#### Scenario: Явный other перезаписывает вид
- **WHEN** вызов пришёл с `kind: "execute"`, затем агент присылает `tool_call_update` того же вызова с `kind: "other"`
- **THEN** вид записи — `other`, запись WARN о незнакомом виде не создаётся

#### Scenario: Запрос разрешения с незнакомым видом на известный вызов
- **WHEN** вызов пришёл с `kind: "execute"`, затем агент присылает `session/request_permission` для него с `toolCall.kind: "future_kind"`
- **THEN** вид вызова в ждущем одобрении — `execute`

#### Scenario: Признак деградации в реплее session/load
- **WHEN** `tool_call` с `kind: "read"` и затем `tool_call_update` того же вызова с `kind: "future_kind"` приходят в реплее `session/load`
- **THEN** после ответа на `session/load` вид записи в восстановленной истории — `read`, риск — `unknown`, как при приёме тех же сообщений в активной сессии

#### Scenario: Незнакомый вид до ответа session/new
- **WHEN** `tool_call_update` с `kind: "future_kind"` приходит для создаваемой сессии до ответа на `session/new`
- **THEN** CodeLab пишет запись WARN при приёме, а обновление вызова после создания сессии отбрасывается, как любое обновление вызова без хода

#### Scenario: Запрос разрешения с незнакомым видом доходит до пользователя
- **WHEN** агент присылает `session/request_permission`, у `toolCall` которого `kind: "future_kind"`, во время активного хода
- **THEN** CodeLab создаёт ждущее одобрение для этого `toolCallId` и не отвечает агенту `cancelled`, пока пользователь не выберет вариант или ход не отменится

#### Scenario: Вид switch_mode распознаётся
- **WHEN** агент присылает `tool_call` или `session/request_permission` с `kind: "switch_mode"`
- **THEN** вид записи вызова — `switchMode`, а запись WARN о незнакомом виде не создаётся

#### Scenario: Не-строковый вид — ошибка формы
- **WHEN** агент присылает `tool_call` с `kind: 7` (или `{}`, `[]`, `true`)
- **THEN** разбор даёт ошибку формы `invalidShape`, обновление не применяется, а на `session/request_permission` с таким `kind` CodeLab отвечает `cancelled`, как и до этого требования

#### Scenario: Вид не передан
- **WHEN** агент присылает `tool_call` без `kind`, затем `tool_call_update` того же вызова с `kind: null`
- **THEN** вид записи — `other`, обновление вид не меняет, запись WARN не создаётся

#### Scenario: Запись журнала о незнакомом виде
- **WHEN** CodeLab принимает `tool_call` сессии `session-1` с `toolCallId` `call-1` и `kind: "future_kind"`
- **THEN** application-журнал содержит одну запись уровня WARN `Unknown ACP tool kind treated as other.` с `session_id` `session-1`, `tool_call_id` `call-1`, методом `session/update`, видом обновления `tool_call` и значением `future_kind`, без `title`, `rawInput` и `content` вызова

#### Scenario: Длинное значение вида усекается
- **WHEN** строковый `kind` длиннее 64 символов
- **THEN** запись журнала содержит не больше 64 символов этого значения

#### Scenario: Секрет в незнакомом виде маскируется
- **WHEN** строковый `kind` — PEM-блок `-----BEGIN RSA PRIVATE KEY-----` с телом ключа длиннее 64 символов
- **THEN** запись журнала не содержит ни заголовка, ни фрагмента тела ключа: маскирование применено к полной строке до усечения

#### Scenario: Незнакомый вид для неизвестной сессии
- **WHEN** `tool_call` с `kind: "future_kind"` приходит для `sessionId`, которой у клиента нет
- **THEN** CodeLab пишет одну запись WARN с этим `session_id`, а обновление отбрасывается, как раньше
