## ADDED Requirements

### Requirement: Пара транспортов в памяти
`package:codelab_acp_transports/codelab_acp_transports.dart` SHALL экспортировать `InProcessAcpLink` — пару соединённых концов `client` и `agent` типа `InProcessAcpTransport`, реализаций порта `AcpTransport`. Сообщение, отправленное в один конец, SHALL приходить в `inbound` другого объектом `JsonRpcMessage` без кодирования в текст (`agent-core-architecture` §13.11; design.md, D1). Концы создаются только парой: публичного конструктора у `InProcessAcpTransport` нет.

Доставка (design.md, D4):
- доставка SHALL быть асинхронной: обработчики получателя НЕ SHALL вызываться изнутри `send` отправителя;
- в одном направлении сообщения SHALL доставляться в порядке вызовов `send`;
- сообщение, пришедшее на конец, который ещё не запущен или у `inbound` которого ещё не было ни одного подписчика, SHALL буферизоваться и выдаваться по порядку, когда конец в `connected` и подписчик появился;
- буфер SHALL держаться только до первого подписчика: если у запущенного конца подписчик `inbound` уже был, а сейчас подписчиков нет, пришедшее сообщение SHALL выбрасываться; сообщения, накопленные в `idle` после того, как подписчик пришёл и отписался, SHALL выбрасываться при `start()`, и подписавшийся позже его НЕ SHALL получать. Подписчик, появившийся при живом подписчике, SHALL получать только сообщения, пришедшие после его подписки;
- `send` на конце не в `connected` SHALL бросать `AcpTransportException` с кодом `sendFailed`; `start()` на конце в `closing`, `closed` или `failed` — с кодом `closed`.

Копирование (design.md, D3):
- `send` SHALL делать глубокую копию дерева JSON в `params`, `result` и `error.data`; получатель SHALL получать неизменяемые `Map` и `List`;
- значение вне JSON — объект не из `null`/`bool`/`String`/конечного `num`/`List`/`Map`, ключ `Map` не строкой, `NaN`, `±Infinity` — SHALL давать `AcpTransportException` с кодом `sendFailed` на отправляющей стороне. Сообщение при этом НЕ SHALL доставляться, а состояние конца НЕ SHALL меняться;
- любая другая ошибка при копировании — включая `Error`, например `StackOverflowError` на цикле в `params` или исключение из итератора пользовательского `Map`, — SHALL давать тот же `AcpTransportException` с кодом `sendFailed` с теми же гарантиями: сообщение не доставляется, состояние не меняется;
- текст исключения копирования SHALL быть общим для всех причин; он, `cause` и диагностика НЕ SHALL содержать значение из сообщения или текст исходной ошибки.

Закрытие (design.md, D4):
- `close()` SHALL переводить конец через `closing` в `closed` с событиями `stateChanged`, закрывать его `events` и `inbound`; повторный `close()` SHALL ничего не делать;
- второй конец, если он не в `closing`, `closed` или `failed`, SHALL получить событие `failure` с кодом `disconnected`, перейти в `failed` и закрыть `inbound` после сообщений, отправленных до `close()`;
- невыданные сообщения второго конца — он не запущен или у его `inbound` ещё не было подписчика — SHALL выбрасываться при закрытии первого конца. Если выброшено хотя бы одно сообщение, второй конец SHALL до события `failure` писать в свои `events` одну диагностику уровня `warning` с числом выброшенных сообщений; диагностика НЕ SHALL содержать методы, id и содержимое сообщений. `events` широковещательный: диагностику получают подписчики `events` в момент закрытия первого конца, в том числе подписанные до `start()`;
- сообщение, доставка которого приходится на конец, закрытый своим владельцем, SHALL выбрасываться без исключения у отправителя и без диагностики.

#### Scenario: Порядок 1000 сообщений
- **WHEN** оба конца запущены, у `agent.inbound` есть подписчик, а `client` отправляет 1000 запросов с id `1…1000` подряд без ожидания доставки
- **THEN** `agent.inbound` отдаёт ровно 1000 сообщений с id `1…1000` в порядке отправки

#### Scenario: Доставка не реентерабельна
- **WHEN** подписчик `agent.inbound` записывает факт получения, а тест проверяет запись сразу после `await client.send(...)` и до следующей микрозадачи
- **THEN** запись пуста, а после `pumpEventQueue()` содержит сообщение

#### Scenario: Сообщение до start() получателя
- **WHEN** `agent` запущен, `client` ещё в `idle` и подписан на `inbound`, `agent` отправляет запрос
- **THEN** до `client.start()` подписчик ничего не получает, после `client.start()` получает запрос

#### Scenario: Сообщение до первого подписчика
- **WHEN** оба конца запущены, у `agent.inbound` нет подписчика, `client` отправляет два запроса, затем на `agent.inbound` подписываются
- **THEN** подписчик получает оба запроса в порядке отправки

#### Scenario: После отписки сообщения не буферизуются
- **WHEN** оба конца запущены, на `agent.inbound` подписываются и отписываются, затем `client` отправляет запрос, затем на `agent.inbound` подписываются снова
- **THEN** новый подписчик ничего не получает; следующий запрос `client` он получает

#### Scenario: Поздний подписчик при живом подписчике
- **WHEN** оба конца запущены, первый подписчик `agent.inbound` получил запрос `1`, затем подписывается второй, и `client` отправляет запрос `2`
- **THEN** первый подписчик получает `1` и `2`, второй — только `2`

#### Scenario: Изменение Map после send не видно получателю
- **WHEN** `client` отправляет запрос с `params` `{"prompt": [{"type": "text", "text": "hi"}]}`, а после `send` отправитель очищает вложенный список и добавляет ключ во внешний `Map`
- **THEN** получатель видит исходное `{"prompt": [{"type": "text", "text": "hi"}]}`, а попытка изменить полученные `params` бросает `UnsupportedError`

#### Scenario: Копия error.data
- **WHEN** `agent` отправляет ответ с `error` `{code: -32603, message: "x", data: {"codelab": {"reason": "r"}}}`, а после `send` отправитель меняет вложенный `Map`
- **THEN** получатель видит `data` `{"codelab": {"reason": "r"}}`, и `data` неизменяемо

#### Scenario: DateTime в params
- **WHEN** `client` отправляет запрос с `params` `{"at": DateTime.utc(2026)}`
- **THEN** `send` бросает `AcpTransportException` с кодом `sendFailed`, текст которого не содержит `2026`; получатель ничего не получает; `client.state` остаётся `connected`, и следующий корректный запрос доставляется

#### Scenario: Ключ не строкой и нечисловой double
- **WHEN** `client` отправляет `params` `{1: "x"}`, затем `{"v": double.nan}`, затем `{"v": double.infinity}`
- **THEN** каждый `send` бросает `AcpTransportException` с кодом `sendFailed`, получатель ничего не получает

#### Scenario: Ошибка итератора при копировании
- **WHEN** `client` отправляет `params` — `Map`, чей итератор `entries` бросает `StateError` с текстом `secret-42`
- **THEN** `send` бросает `AcpTransportException` с кодом `sendFailed` и тем же текстом, что при `DateTime` в `params`; текст не содержит `secret-42`, `cause` равен `null`; получатель ничего не получает, `client.state` остаётся `connected`

#### Scenario: send до start и после close
- **WHEN** `client.send` вызывается до `client.start()`, затем после `client.close()`
- **THEN** оба вызова бросают `AcpTransportException` с кодом `sendFailed`

#### Scenario: Закрытие одного конца
- **WHEN** оба конца запущены, и `client.close()` завершился
- **THEN** `client.state` — `closed`; `agent.events` содержит `failure` с кодом `disconnected` и `stateChanged(failed)`; `agent.state` — `failed`; поток `agent.inbound` завершён (done); `agent.send` бросает `AcpTransportException` с кодом `sendFailed`

#### Scenario: Сообщения до close доставляются до отсоединения
- **WHEN** `agent` отправляет три уведомления и сразу, не дожидаясь доставки, вызывает `close()`
- **THEN** подписчик `client.inbound` получает все три уведомления до события done, затем `client.state` — `failed`

#### Scenario: Повторный close идемпотентен
- **WHEN** `client.close()` вызывается дважды
- **THEN** второй вызов завершается без исключения и без новых событий; `agent.events` содержит ровно одно событие `failure`

#### Scenario: События состояний
- **WHEN** подписчик `client.events` наблюдает `client.start()`, затем `client.close()`
- **THEN** он получает `stateChanged` с состояниями `connecting`, `connected`, `closing`, `closed` в этом порядке

#### Scenario: Закрытие конца в failed и start после закрытия
- **WHEN** `client` закрыт, `agent` в `failed`, затем вызываются `agent.close()` и `agent.start()`
- **THEN** `agent.close()` переводит его в `closed`, а `agent.start()` бросает `AcpTransportException` с кодом `closed`

#### Scenario: Невыданный буфер при закрытии второго конца
- **WHEN** на `client.events` подписан наблюдатель, `client` либо запущен без подписчика `inbound`, либо ещё в `idle`; `agent` запущен, отправляет два уведомления с текстом `secret-42` в `params` и сразу вызывает `close()`
- **THEN** наблюдатель `client.events` получает ровно одну `diagnostic` уровня `warning`, текст которой содержит число `2` и не содержит `secret-42` и имён методов, затем `failure` с кодом `disconnected` и `stateChanged(failed)`; подписка на `client.inbound` получает done без сообщений

#### Scenario: Доставка на закрытый конец
- **WHEN** наблюдатель подписан на `agent.events`, `client` отправляет запрос, а `agent.close()` вызывается до доставки
- **THEN** `client.send` завершается без исключения, запрос никому не доставлен, наблюдатель `agent.events` не получает `diagnostic`

## MODIFIED Requirements

### Requirement: Web-безопасный публичный барель transport
Основная точка входа `package:codelab_acp_transports/codelab_acp_transports.dart` SHALL экспортировать без транзитивного импорта `dart:io`:
- порт transport;
- классы конфигурации `StdioAcpTransportConfig`, `StdioAcpAgentProfile` и `WebSocketAcpTransportConfig`;
- пару транспортов в памяти `InProcessAcpLink` и `InProcessAcpTransport`.

Реализации `StdioAcpTransport` и `WebSocketAcpTransport` SHALL экспортироваться только из отдельной точки входа `package:codelab_acp_transports/io.dart`. Файлы основного бареля НЕ SHALL ссылаться на файлы IO-точки входа.

#### Scenario: Основной барель не тянет dart:io
- **WHEN** сторож архитектуры проверяет `packages/dart/codelab_acp_transports/lib/` по правилу web-безопасного пакета с исключением IO-точки входа
- **THEN** нарушений нет. `grep -rn "dart:io"` по `lib/codelab_acp_transports.dart`, `lib/src/transport_configs.dart` и `lib/src/in_process_acp_transport.dart` ничего не находит, а `web_safe_barrel_test.dart` не находит `dart:io`, достижимого из этих точек входа

#### Scenario: Пара в памяти доступна из основного бареля
- **WHEN** код импортирует только `package:codelab_acp_transports/codelab_acp_transports.dart`
- **THEN** ему доступны `InProcessAcpLink` и `InProcessAcpTransport`, и импорт `package:codelab_acp_transports/io.dart` для них не нужен

#### Scenario: Код создания транспорта импортирует io.dart
- **WHEN** composition root приложения создаёт `StdioAcpTransport` или `WebSocketAcpTransport`
- **THEN** он импортирует `package:codelab_acp_transports/io.dart`, а поведение подключения по stdio и WebSocket не меняется — интеграционные тесты stdio проходят
