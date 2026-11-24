# Совместимость: строго и терпимо

Агент — внешний процесс, и версии схемы ACP у клиента и агента расходятся. Если пакет отвергает всё незнакомое, одно лишнее поле теряет целый ответ. Если принимает всё подряд, пропускает ошибки и открывает дыру в безопасности. Глава описывает, где пакет выбрал строгость, где терпимость и как это устроено. Нормы — требования [`acp-protocol-client`](../../../../openspec/specs/acp-protocol-client/spec.md) («Обработка сообщений JSON-RPC 2.0», «Неизвестный вид вызова инструмента») и [`acp-boundary.md`, §18–§19](../../../../docs/architecture/acp-boundary.md#18-неизвестные-поля).

## Принцип

ACP запрещает собственные поля в корне объектов схемы: расширения живут только в `_meta` ([`15-Extensibility.md`](../../../../docs/protocols/acp/protocol/15-Extensibility.md)). Поэтому по умолчанию разбор строгий: незнакомый ключ в корне объекта — ошибка `invalidShape`:

```text
promptRequest contains unsupported root field "xVendor"; use _meta for extensions.
```

Терпимость вводится точечно и только там, где потеря сообщения вредит, а проверка ничего не защищает. Неизвестное поле при этом никогда не получает смысла: модель читает только известные ей ключи, остальные пропускает ([`acp-boundary.md`, §18](../../../../docs/architecture/acp-boundary.md#18-неизвестные-поля)).

## Что строго, что терпимо

Таблица показывает поведение декодеров пакета. «Строго» значит `JsonRpcProtocolException` с `kind == invalidShape`.

| Что приходит | Поведение | Где устроено | Тест |
|---|---|---|---|
| лишний корневой ключ в параметрах запроса (клиента или агента) | строго | `requireAcpObject` | `protocol_conformance_test.dart` |
| лишний корневой ключ в `session/request_permission`, `fs/*`, `terminal/*` | строго: запросы требуют ответа и касаются безопасности | `decodeAcpRequestParams` | `session_update_tolerance_test.dart`, `response_tolerance_test.dart` («everything … stays strict») |
| лишний корневой ключ в `result` ответа (на любой глубине) | игнорируется | `decodeAcpResult`, `decodeAcpResponseResult` | `response_tolerance_test.dart` |
| лишний корневой ключ в параметрах `session/update` (на любой глубине) | игнорируется | `decodeAcpNotificationParams` | `session_update_tolerance_test.dart` |
| лишнее поле в объектах возможностей `initialize` | игнорируется | `requireAcpCapabilityObject` | `initialize_test.dart` |
| лишнее поле в `session/cancel` | строго | `decodeAcpNotificationParams` | — |
| незнакомый вид `sessionUpdate` | ошибка декодера; приёмник пропускает обновление | `unsupportedSessionUpdateKind` | `session_update_tolerance_test.dart` |
| незнакомая строка `kind` вызова инструмента | `ToolKind.other` | `ToolKind.fromJson` | `tool_kind_test.dart` |
| MCP-сервер незнакомого `type` | `McpServerUnknown` с сырым объектом | `McpServer.fromJson` | `session_test.dart` |
| опция конфигурации незнакомого `type` | пропускается, остальные читаются | `parseSessionConfigOptionList` | `session_test.dart` |
| незнакомое значение `StopReason`, `ToolCallStatus`, `PermissionOptionKind`, `Role`, `PlanEntry*`, `outcome` | строго | `fromJson` перечисления | тест группы |
| незнакомое `type` блока содержимого или содержимого вызова | строго | `ContentBlock.fromJson`, `ToolCallContent.fromJson` | тест группы |
| значение не того типа, нет обязательного поля, не-объект | строго везде | — | тест группы |
| метод вне реестра | `unknownMethod` | `requireAcpMethod` | `acp_method_codec_test.dart` |

Подробнее о строках, которые требуют пояснения.

## Терпимость к лишним корневым полям

Реализация держится на `tolerateUnknownRootFields(decode)` из `acp_validation.dart`. Функция выполняет `decode` в дочерней зоне Dart с ключом-флагом, а `requireOnlyRootKeys` (ею пользуется каждая модель через `requireAcpObject`) проверяет этот флаг и при нём не бросает ошибку на лишнем ключе.

Зона выбрана, а не параметр или глобальная переменная, по трём причинам (комментарий в `acp_validation.dart`):

- флаг действует ровно на один вызов и снимается сам, даже если декодер бросил исключение;
- он доходит до вложенных объектов, не меняя сигнатуры `fromJson` каждой модели;
- нет глобального состояния, которое надо сбрасывать.

Все декодеры пакета синхронные, поэтому `tolerateUnknownRootFields` оборачивает обычный вызов без `await`.

Терпимость не смягчает остальные проверки. Не объект, пропущенное обязательное поле, поле известного имени неверного типа и незнакомое значение дискриминатора остаются ошибкой (тесты «still rejects invalid shapes» в обоих файлах терпимости). Пример из тестов: настоящий агент `claude-agent-acp` присылает `messageId` в `agent_message_chunk` — поле принимается и игнорируется, а `usage_update` целиком идёт по другому пути (ниже).

Где терпимость включается:

- `decodeAcpResult` и `decodeAcpResponseResult` — результат ответа агента. Пример: `session/new` с полем `models`, которого пакет не знает, не должен терять уже созданную сессию.
- `decodeAcpNotificationParams` — только для метода `session/update`: это односторонний поток от внешнего процесса.

Где не включается: `decodeAcpParams`, `decodeAcpRequestParams`, прямой вызов `Model.fromJson` и прямой вызов `definition.decodeResult`. Терпимость привязана к функциям кодека, а не к определению метода.

## Объекты возможностей `initialize`

`requireAcpCapabilityObject` проверяет только «это JSON-объект» и не смотрит на ключи. Им пользуются `ClientCapabilities`, `AgentCapabilities`, `PromptCapabilities`, `McpCapabilities`, `SessionCapabilities` и вложенные объекты. Причина: стороны расширяют флаги возможностей независимо, и более новый агент законно объявит флаг, которого клиент ещё не знает (например, `sessionCapabilities.fork`). Отказ из-за него провалил бы всё рукопожатие. Модель читает только известные ключи, а неизвестные не интерпретирует.

Корень самого `InitializeRequest` и `InitializeResponse` строгий при прямом `fromJson` и в параметрах (`initialize_test.dart`, «still rejects unknown root fields outside capability objects»). Результат `initialize`, разобранный через `decodeAcpResult`, терпим к лишним корневым полям (`response_tolerance_test.dart`, «initialize result with an unknown root field»).

## Неизвестный вид `session/update`

Дискриминатор `sessionUpdate` строгий: `SessionUpdate.fromJson` на незнакомом виде бросает `invalidShape` («sessionUpdate "usage_update" is not supported.»). Но спецификация требует другого поведения приёмника: такое обновление пропускается без ошибки и без изменения состояния сессии (`acp-protocol-client`, «Незнакомый вид обновления пропускается»). Решение разделено между пакетом и приёмником:

- пакет знает, какие виды понимает: `SessionUpdate.knownKinds` — множество из десяти строк (`user_message_chunk`, `agent_message_chunk`, `agent_thought_chunk`, `tool_call`, `tool_call_update`, `plan`, `available_commands_update`, `current_mode_update`, `config_option_update`, `session_info_update`); тест проверяет, что оно совпадает с `switch` в `fromJson`;
- `unsupportedSessionUpdateKind(params)` принимает «сырые» параметры уведомления и возвращает строку вида, если вид незнакомый; для известного вида, битых параметров и «не похоже на обновление» возвращает `null`, чтобы строгий разбор сообщил об ошибке сам;
- приёмник вызывает её до `decodeAcpNotificationParams` и при ненулевом результате пропускает кадр (в клиенте — `_handleSessionUpdate` в `codelab_client_acp`).

Незнакомое значение внутри известного вида обновления (например, `type` блока содержимого в `agent_message_chunk`) этим путём не идёт: это `invalidShape`, и обновление отвергается.

## Неизвестный вид вызова инструмента (`ToolKind`)

`kind` вызова инструмента — подсказка клиенту для отображения и оценки риска, а перечень растёт. `ToolKind.fromJson` поэтому мягкий:

- строка из перечня (включая `switch_mode`) — соответствующее значение;
- любая другая строка, в том числе пустая, — `ToolKind.other`;
- не-строка — `invalidShape` («toolKind must be a string.»): это нарушение формы, а не будущее значение;
- `null` или отсутствие поля обрабатывают `parseToolCall*Json`: у `ToolCall` вид `other`, у `ToolCallUpdate` и запроса разрешения вид «не передан».

Разбор одинаков в `tool_call`, `tool_call_update` и `toolCall` внутри `session/request_permission`. Обратная сериализация пишет `other`: исходное значение при `toJson` теряется. Чтобы узнать исходное значение, приёмник вызывает `unrecognizedToolKind(rawToolCall)` по «сырому» объекту до разбора и пишет предупреждение в журнал (пакет сам ничего не пишет, `acp-boundary.md`). Клиент делает это в `_logUnrecognizedToolKind`. Решения D1–D4 — change `tolerate-unknown-tool-kind`.

## MCP-серверы и опции конфигурации

**MCP-серверы** в `mcpServers` запросов `session/new` и `session/load`. ACP может добавить транспорты, а отказ всего запроса из-за одного сервера теряет остальные поля. Поэтому `McpServer.fromJson` разбирает `stdio`, `http` и `sse` строго, а сервер незнакомого `type` сохраняет как `McpServerUnknown`: объект целиком в поле `raw` и тот же объект на выходе `toJson`. Потребитель обязан обработать этот вариант: агент пропускает такой сервер и пишет в журнал, клиент пересылает как есть. У `stdio` в ACP нет дискриминатора, поэтому объект без `type` — это stdio. Пример:

```json
{"type": "ws", "name": "x", "url": "u"}
```

`McpServer.fromJson` возвращает для него `McpServerUnknown`, а `toJson` отдаёт тот же объект.

**Опции конфигурации.** `parseSessionConfigOptionList` пропускает опцию с незнакомым `type` и разбирает остальные. Сейчас в схеме один тип, `select`. Так сделано по ACP: клиент, получивший опцию незнакомого типа, игнорирует её, а не отвергает весь список (`docs/protocols/acp/protocol/13-Session Config Options.md`, раздел «Default Values and Graceful Degradation»).

## Неизвестные методы

`requireAcpMethod` бросает `JsonRpcProtocolException.unknownMethod` для любого имени вне реестра: `foo/bar`, `authenticate`, `_codelab/session/usage`. Пакет только сообщает факт. Что делать дальше, решает приёмник, и спецификация предписывает:

- неизвестный запрос агента — ответ `-32601 Method not found` с тем же `id`, соединение живёт (`acp-protocol-client`, «Неподдерживаемые запросы агента отклоняются как Method not found»);
- неизвестное уведомление — без ответа и без ошибки;
- метод агента `authenticate` агент CodeLab отвечает `-32601` (`agent-acp-server`).

В золотых фикстурах это проверяет `errors-bad-frame-survives` (роль агента): `foo/bar` получает `-32601`, плохие параметры `session/prompt` получают `-32602`, а следующий запрос проходит.

## Расширения CodeLab

Собственные расширения делятся на три вида, и ни один не определён в этом пакете как модель ACP:

| Вид | Где живёт | Что делает пакет |
|---|---|---|
| блоки `_meta.codelab.*` (`tasks`, `subagents`, `subagentToolCalls`, `usage`, …) | поле `meta` любой модели | хранит как есть, не разбирает |
| `data.codelab` ответа-ошибки | поле `data` у `JsonRpcError` | своего `codelab` не пишет: кладёт только `kind`, `message`, `method` |
| методы `_codelab/session/usage` (уведомление) и `_codelab/session/usage/ledger` (запрос) | собственные имена методов | не знает: для реестра это `unknownMethod` |

Правило из спецификации: собственные данные идут в `_meta`, а имена собственных методов начинаются с `_` (`acp-protocol-client`, «Официальный источник истины ACP»). Каждое расширение вводит OpenSpec change ([`acp-boundary.md`, §49](../../../../docs/architecture/acp-boundary.md)).

Клиент объявляет расширения в `initialize`. Фрагмент `params` из фикстуры `initialize-codelab-extensions`, он проходит через `InitializeRequest.fromJson` и обратно `toJson` без потерь:

```json
{
  "protocolVersion": 1,
  "clientCapabilities": {
    "fs": {"readTextFile": true, "writeTextFile": true},
    "terminal": true,
    "_meta": {
      "codelab": {
        "tasks": {"version": 1},
        "subagents": {"version": 1},
        "subagentToolCalls": {"version": 1},
        "usage": {"version": 1}
      }
    }
  }
}
```

Разбор блока `_meta.codelab` делает `CodelabExtensions.parse` в `codelab_client_acp` (`lib/src/domain/codelab_extensions.dart`), а уведомление и запрос `_codelab/*` маршрутизируют по «сырому» имени метода соседние пакеты: имена объявлены в `codelab_agent_acp/lib/src/usage_accounting.dart` (`usageNotificationMethod`, `usageLedgerMethod`), приём на клиенте — `UsageNotification` в `codelab_client_acp`. Пакет здесь только переносит `params` и `_meta` без изменений; формат снимка описывают спецификации `acp-protocol-client` («Приём уведомления `_codelab/session/usage`») и `acp-golden-fixtures` («Фикстуры расширения usage»).

Урезанный кадр уведомления из фикстуры `prompt-usage-steps` (поля, которых нет в сокращении, помечены `…`):

```json
{
  "jsonrpc": "2.0",
  "method": "_codelab/session/usage",
  "params": {
    "sessionId": "<session-id>",
    "seq": 1,
    "trigger": "step",
    "step": {
      "index": 0,
      "model": "scripted/scripted-1",
      "tokens": {"input": 1200, "output": 300, "cacheRead": 10000, "cacheWrite": 0},
      "cost": "0.0111"
    },
    "…": "…"
  }
}
```

`decodeJsonRpcMessage` разбирает такой кадр как `JsonRpcNotification`, а `decodeAcpNotificationParams` для него бросает `unknownMethod`.

## Что пакет не моделирует

Найдено при сверке со схемой; поведение ниже описано как есть.

- **Сгруппированные значения опции `select`.** В схеме `SessionConfigSelectOptions` — это либо плоский список `SessionConfigSelectOption`, либо список групп `SessionConfigSelectGroup` (`group`, `name`, `options`). Пакет принимает только плоский список: запись-группа не проходит `SessionConfigSelectOption.fromJson` («sessionConfigValueId must be a non-empty string.»), и вместе с ней отвергается весь `session/new`. Решение за OpenSpec change.
- **Метод `authenticate` и код ошибки `-32000`.** Они есть в схеме, но не в пакете; агент отвечает на `authenticate` кодом `-32601` по спецификации.

## Смотрите также

- [Устройство](01-design.md) — функции кодека и ошибки.
- [Расширение](03-extending.md) — как добавить значение перечисления или терпимость.
- [Частые проблемы](04-troubleshooting.md) — что делать, когда агент прислал незнакомое.
