# Расширение и частые проблемы

Глава собирает рецепты изменений пакета и таблицу «симптом → причина → что сделать». Главное правило: сервер не придумывает ACP. Методы, поля и значения берутся только из `codelab_acp_protocol` и [`docs/protocols/acp/protocol/`](../../../../docs/protocols/acp/protocol/); всё сверх них — расширения `_meta.codelab.*`, `data.codelab` или методы `_codelab/*`, и каждое вводится отдельным OpenSpec change (корневой [`AGENTS.md`](../../../../AGENTS.md) §3.4, `AGENTS.md` пакета §2, ACP-2). Если нужного значения в протоколе нет, остановитесь и предложите change, а не добавляйте поле «на всякий случай».

В скелетах ниже `…` — намеренно опущенные тела; имена `Foo…`, `Something…` — условные. Реальные имена, на которые они опираются, проверены по коду.

## Рецепты

| Что нужно | Рецепт |
|---|---|
| новое событие ядра должно дойти до клиента | [1](#1-новое-событие-ядра-в-проекции) |
| у существующего кадра нужно новое поле | [2](#2-новое-поле-в-_metacodelab) |
| опция или режим сессии | [3](#3-новая-опция-сессии) |
| новый метод ACP, который агент обслуживает | [4](#4-новый-метод-acp) |
| собственный запрос `_codelab/*` | [5](#5-собственный-запрос-_codelab) |
| новый запрос агента к клиенту | [6](#6-новый-запрос-агента-к-клиенту) |
| новая причина завершения хода | [7](#7-новая-причина-завершения-хода) |

### 1. Новое событие ядра в проекции

Когда: агентский инженер добавил подтип `AgentEvent` в `codelab_agent_core` (`lib/src/loop/agent_events.dart`), и клиент должен либо увидеть его, либо явно не видеть.

1. Убедитесь, что для события есть вариант `SessionUpdate` в протоколе. В `codelab_acp_protocol` их десять: `user_message_chunk`, `agent_message_chunk`, `agent_thought_chunk`, `tool_call`, `tool_call_update`, `plan`, `available_commands_update`, `current_mode_update`, `config_option_update`, `session_info_update` (`lib/src/acp/session_update.dart`). Если нужен другой — это изменение протокола: change и `acp-protocol-engineer`.
2. После добавления подтипа пакет перестаёт компилироваться: `switch` в `projectEvent` исчерпывающий без `default`. Добавьте ветку (кадры или `const []`) и строку в `projectionTable`.
3. Если событие попадает в журнал сессии и должно быть видно при `session/load`, дополните `replayUpdates` и хвост `replayInto`; если не должно — ничего не меняйте и запишите причину в строке таблицы.
4. Добавьте тест строки в `test/projection/event_projection_test.dart`; сверка таблицы с иерархией (`every_agent_event_is_projected_test.dart`) сработает сама.
5. Если событие меняет кадры хода, добавьте или обновите golden-фикстуру в `codelab_acp_testing` и проверьте `melos run conformance:agent`.

Скелет (`event_projection.dart`; `FooHappened` — условное событие):

```dart
const projectionTable = <Type, String>{
  // …
  FooHappened: 'session_info_update', // что получает клиент, одной строкой
};

List<acp.SessionUpdate> projectEvent(AgentEvent event, { /* параметры */ }) =>
    switch (event) {
      // …
      FooHappened(:final title) => [
        acp.SessionUpdate.sessionInfoUpdate(title: title),
      ],
    };
```

Кадры события, которое клиенту не нужно, — `const []` в общей ветке «не передаётся» и строка `'not sent: <причина>'`.

### 2. Новое поле в `_meta.codelab`

Когда: к `tool_call`, `tool_call_update`, `plan` или ответу нужно приложить данные, которых нет в ACP. Это расширение, поэтому сначала OpenSpec change (ACP-2): он описывает ключ, форму и условие, при котором поле уходит. Для расширений, о которых клиент должен знать, правило такое:

- объявление идёт в `agentCapabilities._meta.codelab` (`_codelabExtensions`) и только клиенту, прислав `clientCapabilities._meta.codelab`;
- согласие читается через `codelabKeyAgreed(meta, ключ)` из `ClientLink.capabilities` в момент события, не при создании моста;
- поле, которое клиент не просил, не уходит: сторонний клиент получает ровно поля стандарта.

Где менять: поле кадра вызова — `projectEvent` (`ToolCallStarted`), `finishedMeta` (итог), `withParentToolCallId` (цепочки); поле плана — ветка `TaskListChanged`; поле ответа — `turnResponse`. Реплей собирает `_meta` отдельно (`replay.dart`, `_mergeMeta`): если поле должно быть видно после `session/load`, продублируйте его там. Тест — кадр в `event_projection_test.dart` и фикстура.

### 3. Новая опция сессии

Когда: клиент должен выбирать значение, которое умеет менять `AgentSession`. Опции строит одна функция, `sessionConfigOptions` в [`config_options.dart`](../lib/src/config_options.dart); один и тот же снимок уходит в `session/new`, `session/load`, `session/set_config_option` и `config_option_update`.

1. Ядро: у `AgentSession` есть метод смены (по образцу `setAgent`) и текущее значение. Без этого начинать нечем.
2. `sessionConfigOptions`: добавьте опцию после `agent` (порядок опций — часть спецификации: `mode`, `model`, `effort`, `agent`). Поле `category` не задавайте: категории без `_` зарезервированы ACP (`mode`, `model`, `thought_level`), собственную вводит только отдельный change.
3. Ветка в `_Connection._setConfigOption` (`agent_server.dart`): значение вне списка — `AcpRequestError.invalidParams('unknown value: …')`; общая ветка `case 'model' || agentConfigId` должна включить новый `configId`, чтобы недопустимое значение не превратилось в «неизвестная опция».
4. Метод в `SessionBridge`: смена, меняющая режим или модель, — через `_clientChange` (подавляет эхо `config_option_update`), прочие — через `_queued` (ACP-11, [глава 2](02-session-bridge.md#смена-настроек-без-дубля-config_option_update)).
5. Тесты: `config_options_test.dart` (состав и порядок), `set_config_option` в серверном тесте, фикстура `set-config-option-<имя>`.

Скелет:

```dart
// config_options.dart — после опции agent
const somethingConfigId = 'something';

if (session.somethings.isNotEmpty)
  acp.SessionConfigOption.select(
    id: const acp.SessionConfigId(somethingConfigId),
    name: 'Something',
    currentValue: acp.SessionConfigValueId(session.something),
    options: [
      for (final item in session.somethings)
        acp.SessionConfigSelectOption(
          value: acp.SessionConfigValueId(item.name),
          name: item.name,
        ),
    ],
  ),
```

```dart
// agent_server.dart — _setConfigOption, перед веткой `case 'model' || …`
case somethingConfigId
    when bridge.session.somethings.any((item) => item.name == value):
  await bridge.setSomething(value);
```

```dart
// session_bridge.dart
Future<void> setSomething(String name) =>
    _queued(() => session.setSomething(name));
```

Новый **режим** (`ModeId`) — изменение ядра: сервер берёт список режимов из `modeInfos`, а разбор значений — из `ModeId.tryParse` ядра (одна таблица синонимов со слэш-командой `/mode`). Режим добавляется в ядре и в `modeInfos` (имя и описание видит пользователь клиента, поэтому они английские).

### 4. Новый метод ACP

Когда: протокол ACP определяет метод, который агент обязан обслуживать, и `codelab_acp_protocol` уже содержит его (`AcpMethodDefinition` в `acpMethodRegistry`, константа `…Method`). Сейчас обслужены все определённые клиентские запросы; метод `authenticate` в пакете протокола не определён и получает `-32601`. Если определения нет — сначала change и `acp-protocol-engineer`, пакет сервера не придумывает метод.

1. В `_Connection._onRequest` добавьте ветку в `switch` перед `_ => methodNotFound`. Правило «любой `session/*` до `initialize`» сработает само по префиксу; для метода с другим префиксом решите это явно.
2. Обработчик возвращает `Reply`: результат закодирован кодеком метода (`encodeResult`), побочные кадры — через `Reply.after`, если они обязаны идти после ответа.
3. Ошибки — `AcpRequestError` с кодами из таблицы [главы 1](01-structure.md#коды-ошибок-json-rpc); свои коды не вводятся, причину уточняет `data.codelab.reason`.
4. Если метод связан с возможностью агента, объявите её в `initialize` (`_initialize`) в соответствии с `02-Initialization.md`.
5. Спецификация `agent-acp-server` обновляется в том же change. Фикстуры — в `codelab_acp_testing`, если метод общий для клиента и агента.

Скелет (`sessionXxxMethod` и `acpSessionXxx` — условные имена из `codelab_acp_protocol`):

```dart
// agent_server.dart — _Connection._onRequest
return switch (method) {
  // …
  acp.sessionXxxMethod => _sessionXxx(request.params),
  _ => throw AcpRequestError.methodNotFound('Method not found: $method'),
};

Future<Reply> _sessionXxx(Object? params) async {
  final request = acp.acpSessionXxx.decodeParams(params);
  final bridge = _bridge(request.sessionId); // -32002, если сессии нет
  // … вызов ядра через мост …
  return Reply(acp.acpSessionXxx.encodeResult(response));
}
```

Если метод — уведомление клиента, ветка идёт в `_onNotification`: оттуда нельзя ответить, поэтому сбой пишется в лог (`acp.frame.bad`).

### 5. Собственный запрос `_codelab/*`

Когда: нужна операция, которой нет в ACP. Образец — `_codelab/session/usage/ledger` (`usageLedgerMethod` в `usage_accounting.dart`, `_Connection._usageLedger`). Требования `15-Extensibility.md`: имя начинается с `_`, ответ идёт с тем же `id`. Расширение вводит OpenSpec change.

1. Константа имени. Образец — `usageLedgerMethod` в `usage_accounting.dart`; для нового расширения константу можно держать там же, рядом с ним, или в файле его обработчика.
2. Ветка в `_onRequest` до `_ => methodNotFound`.
3. Кодека в протоколе нет, поэтому параметры проверяются вручную: неверный тип — `AcpRequestError.invalidParams('<поле> must be a string')`. Идентификатор сессии ищется среди открытых (`_bridge`), путь к файлу из параметров не строится.
4. Сбой — `AcpRequestError(acp.jsonRpcInternalErrorCode, '<текст>', data: {'codelab': {'reason': '<причина>'}})` и запись в лог warning.
5. Объявите расширение в `_codelabExtensions`: `'<имя>': {'version': 1}`; без блока клиент о нём не узнает.
6. Тест и фикстура с меткой в `extensions`.

```dart
// agent_server.dart
const somethingMethod = '_codelab/session/something';

Future<Reply> _something(Object? params) async {
  final map = params is Map ? params : const <Object?, Object?>{};
  final sessionId = map['sessionId'];
  if (sessionId is! String) {
    throw const AcpRequestError.invalidParams('sessionId must be a string');
  }
  final bridge = _bridge(acp.SessionId(sessionId));
  // … чтение состояния через мост …
  return Reply(<String, Object?>{ /* результат */ });
}
```

### 6. Новый запрос агента к клиенту

Когда: протокол определил запрос, который агент шлёт клиенту (как `fs/*` или `terminal/*`), и нужен новый порт ядра или шаг окружения. Корневой `AGENTS.md` §10 запрещает вводить собственный approval-гейт для `fs/*` и `terminal/*`; containment по рабочей папке остаётся за ядром (`BoundedEnv`).

1. Вызов — `ClientRequests.request(acp.acpXxx, params, prefix:, timeout:, cancel:)` через `ClientLink.requests`. `prefix` даёт читаемые id (`perm`, `fs`, `term`); новый префикс должен быть коротким и уникальным.
2. Проверьте возможность клиента в `ClientLink.capabilities` до отправки: нет возможности — отказ без кадра (как `FileErrorCode.unsupported`).
3. Ловите `ClientCallFailure` и переводите её в значение результата порта (`FileError`, `ExecError`, решение разрешения): исключение через границу порта не выпускается (ENV-1).
4. Таймаут — поле `AcpTimeouts` с умолчанием; тест на `FakeClock`, без реального ожидания.
5. Отмена: ожидание прекращает `CancelToken`, а запрос клиенту не отзывается. Поздний ответ станет «неизвестным id».

```dart
// acp_client_env.dart — шаг окружения
final raw = await _link.requests.request(
  acp.acpXxx,
  acp.XxxRequest(sessionId: acp.SessionId(_link.sessionId) /* … */),
  prefix: 'xxx',
  timeout: _timeouts.xxx,
  cancel: token,
);
final response = acp.acpXxx.decodeResult(raw);
```

### 7. Новая причина завершения хода

Когда: ядро добавило значение в `TurnEndReason`. `turnResponse` переключается по нему исчерпывающе, поэтому пакет перестанет компилироваться. Выберите одно из пяти значений `StopReason` протокола (`end_turn`, `max_tokens`, `max_turn_requests`, `refusal`, `cancelled`) или ошибку `-32603`. Нового значения `stopReason` придумывать нельзя; подробность идёт в `_meta.codelab`, как у `budgetExceeded`. Тесты — `event_projection_test.dart`, фикстура хода.

## События лога пакета

Имена событий и поля — из `lib/src/`. Пакет не пишет секреты, тексты промптов и значения конфигурации; в события usage не попадают токены и деньги.

| Событие | Уровень | Когда | Поля |
|---|---|---|---|
| `acp.inbound.error` | warning | поток входящих кадров сообщил об ошибке | — (ошибка и стек) |
| `acp.frame.bad` | warning | ответ клиента на неизвестный id; сбой обработки уведомления | `reason`, `id` или `method` |
| `acp.handler.failed` | error | исключение обработчика, не `AcpRequestError` | `method`, ошибка и стек |
| `acp.notification.unknown` | info | неизвестное уведомление клиента | `method` |
| `acp.client_capabilities.absent` | warning | в `initialize` нет `clientCapabilities` | — |
| `acp.extensions.negotiated` | debug | сразу после `initialize` | `keys` |
| `acp.session.project_config_invalid` | warning | ошибка конфигурации папки | `cwd`, `session_id`, `issues` |
| `mcp.server.skipped` | info | сервер из запроса пропущен | `session_id`, `server`, `transport`, `reason` |
| `mcp.servers.replace_failed` | warning | сбой замены серверов при `session/load` | `session_id`, `error` |
| `acp.prompt.rejected` | info | `session/prompt` во время хода | `session_id`, `reason` |
| `acp.cancel`, `acp.cancel.no_turn` | info | `session/cancel` с ходом и без | `session_id` |
| `acp.turn.failed` | error | `AgentSession.prompt` бросил исключение | `session_id` |
| `acp.session.detached` | info | соединение закрыто во время хода | `session_id`, `grace_ms` |
| `acp.session.reconnected` | info | ход пережил переподключение | `session_id` |
| `acp.session.grace_expired` | info | окно переподключения истекло, ход отменяется | `session_id` |
| `acp.subagent.unknown_parent` | warning | кадр потомка без известного предка | `session_id`, `subagent_id`, `parent_tool_call_id` |
| `acp.subagent.subtree_closed` | info | закрыты висящие вызовы поддерева | `session_id`, `tool_call_id`, `closed_calls` |
| `acp.permission.unknown_option` | warning | клиент выбрал вариант, которого не предлагали | `session_id`, `tool_call_id`, `option_id` |
| `acp.permission.failed` | warning | сбой запроса разрешения, итог — отказ | `session_id`, `tool_call_id`, `reason` |
| `acp.terminal.kill_failed`, `…output_failed`, `…release_failed` | warning | сбой шага терминала | `session_id`, `terminal_id`, `reason` |
| `acp.send.failed`, `acp.send.failed_handler` | warning | транспорт не принял кадр; сбой обработчика этого сбоя | ошибка и стек |
| `acp.usage.sent` | debug | отправлен снимок usage | `session_id`, `seq`, `trigger`, `turn_id` |
| `acp.usage.seeded`, `acp.usage.seed_failed` | debug, warning | засев суммы при `session/load` | `session_id`, `turns`, `steps`, `duration_ms` или `error_class` |
| `acp.usage.load_snapshot_failed` | warning | сбой снимка `load` | `session_id`, `error_class` |
| `acp.usage.ledger`, `acp.usage.ledger.coalesced`, `acp.usage.ledger_failed` | debug, debug, warning | запрос журнала usage | `session_id`, `rebuild`, `status`, `turns`, `steps`, `duration_ms` |

Лог читают так же, как лог ядра ([глава ядра](../../codelab_agent_core/doc/10-observability-and-errors.md#журнал-диагностики)); в тестах записи отдаёт `RecordingLogger.eventsOf('<событие>')`.

## Частые проблемы

### `initialize required` на `session/new`

**Симптом.** Клиент получил `-32600 initialize required`.
**Причина.** Любой метод с префиксом `session/` до `initialize` на этом соединении отклоняется (`_Connection._onRequest`).
**Что сделать.** Отправить `initialize` первым кадром соединения. Новое соединение (например, после переподключения) требует свой `initialize`.

### `already initialized`

**Симптом.** `-32600 already initialized`.
**Причина.** `initialize` повторён на том же соединении: состояние `_client` уже задано.
**Что сделать.** Не повторять `initialize`; для новой договорённости о возможностях открыть новое соединение.

### `cwd must be an absolute path` или `cwd does not exist`

**Симптом.** `session/new` или `session/load` отвечает `-32602`.
**Причина.** Первая ошибка: путь не начинается с `/` (проверка `startsWith('/')`, поэтому путь Windows вида `C:\…` не проходит: пакет принимает только POSIX-пути). Вторая: хост дал локальный листинг (`localListing` или `localEnv`) и каталога нет на машине агента. Без листинга (WebSocket) существование не проверяется.
**Что сделать.** Передать абсолютный путь на машине агента. Если клиент и агент на разных машинах, каталога на стороне агента нет и stdio-сценарий неприменим.

### `a turn is already running`

**Симптом.** `session/prompt` отвечает `-32602`, `data.codelab.reason` равен `turnActive`.
**Причина.** В сессии идёт ход; ACP не допускает второй `prompt` до ответа на первый. Лог: `acp.prompt.rejected`.
**Что сделать.** Дождаться ответа на предыдущий `prompt` или отправить `session/cancel`. Очередь промптов — забота клиента (`codelab_client_core`).

### `the session is busy in another connection`

**Симптом.** `session/load` — `-32602` с `reason: "sessionBusy"`.
**Причина.** В сессии идёт ход, и его владелец — другое живое соединение. Второй живой клиент идущего хода не подключается.
**Что сделать.** Дождаться конца хода или закрыть соединение-владельца и загрузить сессию в окне переподключения (`detachGrace`). Оба хоста ставят окно в ноль, поэтому у них разорванное соединение отменяет ход сразу.

### `Session not found`

**Симптом.** `-32002 Session not found: <id>`.
**Причина.** Сервер не знает `sessionId`: процесс перезапущен, сессия не открыта в этом сервере, а `session/prompt` и опции работают только с открытыми. Для закрытой сессии нужен `session/load`; он, в свою очередь, возможен, если профиль включил `sessionPersistence`.
**Что сделать.** Сначала `session/new` или `session/load`. Если `loadSession: false` в ответе `initialize`, журнал сессий хост не хранит.

### `Turn failed: …`

**Симптом.** Ответ на `session/prompt` — `-32603` с текстом `Turn failed: <сообщение>`.
**Причина.** Ход завершился причиной `failed`. `data.codelab.errorClass` называет класс сбоя, `retryable` — имеет ли смысл повтор (`network`, `timeout`, `rateLimited`, `server` — да).
**Что сделать.** Смотреть последнюю ошибку без повтора (`AgentError`) в логе ядра и журнале хода ([ядро: ошибки](../../codelab_agent_core/doc/10-observability-and-errors.md)). Если `errorClass` равен `unknown`, `AgentError` не пришёл: ищите `acp.turn.failed` и `acp.handler.failed`.

### `Internal error` без деталей

**Симптом.** `-32603 Internal error`, `data` нет.
**Причина.** Обработчик бросил исключение, не являющееся `AcpRequestError`; детали в клиента не уходят намеренно.
**Что сделать.** Найти в логе агента `acp.handler.failed {method: …}` со стеком (уровень `error`).

### Клиент не получает `_meta.codelab`, уведомления usage или вызовы потомков

**Симптом.** В ответе `initialize` нет блока `_meta.codelab`; нет `_codelab/session/usage`; нет вызовов потомков.
**Причина.** Расширения уходят только согласившемуся клиенту. Блок `initialize` — только при `clientCapabilities._meta.codelab` (даже пустом). Согласие по ключу — объект с целым `version: 1`: значения `2`, `'1'`, `1.5` или не-объект не считаются. Вызовы потомков, кроме того, нужны ядру с включёнными субагентами.
**Что сделать.** Проверить в логе `acp.extensions.negotiated {keys: […]}` (уровень debug): ключа нет в списке — клиент его не объявил или объявил неверно.

### Модель не может выполнить команду или прочитать файл

**Симптом.** Результат инструмента — `the client does not support terminals`; чтение возвращает «unsupported».
**Причина.** Клиент не объявил `terminal` или `fs.readTextFile` / `fs.writeTextFile` в `initialize`; окружение отвечает отказом без кадра. В профиле `agent-serve` инструмент `exec` зарегистрирован всегда; без `terminal` у клиента `AcpClientExecutionEnv.exec` отвечает `shellUnavailable` без кадра (`acp_client_env.dart`). Про отсутствие других инструментов — [в разделе ядра «Инструмент не виден модели»](../../codelab_agent_core/doc/13-troubleshooting.md#инструмент-не-виден-модели).
**Что сделать.** Объявить возможности в клиенте или использовать встроенный режим с `localEnv`.

### Ход ждёт и не движется

**Симптом.** Ход идёт, кадров нет, `session/prompt` не отвечает.
**Причина.** Чаще всего агент ждёт клиента: `session/request_permission` не имеет таймаута, у `terminal/wait_for_exit` тоже нет таймаута запроса: срок ограничивает только `ExecOptions.timeout` команды, если он задан. Если клиент не ответил (или не видит запрос), ход стоит.
**Что сделать.** Отправить `session/cancel`: он прекращает ожидание. В логе при `--log-level debug` ищите `permission.asked` без `permission.decided`. Для `fs/*` и остальных шагов терминала таймаут есть: сообщение `client did not answer <метод> in <N> s (timed out)` придёт модели результатом инструмента.

### `acp.frame.bad` — `unknown response id`

**Симптом.** Предупреждение `acp.frame.bad {reason: unknown response id, id: …}`.
**Причина.** Клиент ответил на запрос агента, которого уже никто не ждёт: ожидание прекращено отменой хода или таймаутом, либо id чужой.
**Что сделать.** Обычно ничего: это штатный поздний ответ (PERM-4). Если предупреждения идут постоянно, проверить, что клиент отвечает с тем же `id` (строка вида `perm-1`, `fs-2`, `term-3`).

### Кадры пришли не в том порядке

**Симптом.** `tool_call` пришёл после `session/request_permission`, ответ на `prompt` раньше последнего `session/update`.
**Причина.** Кадр отправлен в обход очереди соединения: напрямую в транспорт, не через `OutboundQueue`, или мост поставил его не через `_send`. Порядок гарантирует только единая очередь (ACP-3).
**Что сделать.** Все исходящие кадры — через `_Connection._notify`, `_notifyFrame`, `Reply` и `ClientRequests`. Тест на `ServerHarness.start(slow: true)` (медленный транспорт) воспроизводит порядок.

### Отсоединённое соединение: кадры уходят «в пустоту»

**Симптом.** После обрыва клиент не получил часть `session/update`; в логе `acp.session.detached`.
**Причина.** `detach` подменяет очередь пустой: кадры не накапливаются. Журнал ядра остаётся полным.
**Что сделать.** Клиент загружает сессию через `session/load`: реплей отдаст всё, что он не получил. После `acp.session.grace_expired` ход отменён.

### `HostWiringException` при создании сервера

**Симптом.** Конструктор `AcpAgentServer` бросает `HostWiringException: capability fileListing requires AcpServerConfig.localListing: …`.
**Причина.** Профиль включил `fileListing`, а хост не дал ни `localListing`, ни `localEnv` с `DirectoryListing`.
**Что сделать.** Для stdio передать `localListing` (клиент и агент на одной машине); для WebSocket выключить `fileListing` при сборке ядра; для встроенного режима реализовать `DirectoryListing` в `localEnv`.

### Красный тест проекции или фикстуры

**Симптом.** `every_agent_event_is_projected_test.dart` падает; фикстура падает с `FormatException … config.<ключ>`.
**Причина.** Первое: в `agent_events.dart` есть подтип без строки в `projectionTable` (или строка без подтипа). Второе: фабрика фикстур принимает ограниченный набор ключей `setup.config`; неизвестный ключ — намеренный громкий провал.
**Что сделать.** Добавить строку таблицы ([рецепт 1](#1-новое-событие-ядра-в-проекции)); для ключа фикстуры — расширить `_FixtureConfig` в `test/conformance_test.dart` вместе со спецификацией `acp-golden-fixtures`.

## Заметки о коде

Эти наблюдения не ошибки пользователя, а свойства кода, которые полезно знать при изменениях:

- `OutboundQueue` принимает `onSendFailed`, но `_Connection` его не задаёт: сбой отправки только пишется (`acp.send.failed`). Комментарий класса говорит, что соединение переходит в `detached`; по коду этого не происходит, о конце соединения сервер узнаёт по концу входного потока.
- Отсоединённая сессия без хода не имеет таймера: она остаётся в `AcpAgentServer._sessions`, пока её не загрузят или сервер не остановят. На сервере WebSocket, который живёт долго, закрытые клиентом простаивающие сессии накапливаются в памяти.
- `session/list` не проверяет объявленную возможность `sessionCapabilities.list`: без хранилища он отвечает пустым списком.

## Смотрите также

- [Устройство пакета](01-structure.md), [мост сессии](02-session-bridge.md), [проекция и запросы](03-projection-and-client-requests.md), [тестирование](04-testing.md).
- [Частые проблемы ядра](../../codelab_agent_core/doc/13-troubleshooting.md) — сборка, инструменты, конфигурация, контекст.
- [Расширение ядра](../../codelab_agent_core/doc/11-extending.md) — инструмент, провайдер, команда, хук, режим, настройка.
- Спецификация [`agent-acp-server`](../../../../openspec/specs/agent-acp-server/spec.md) и [`docs/architecture/acp-boundary.md`](../../../../docs/architecture/acp-boundary.md).
