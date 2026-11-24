# Тестирование, рецепты и частые проблемы

Глава собирает практику: как устроены тесты пакета, как расширить пакет по реальному коду и что делать при типичных сбоях. Устройство, на которое глава ссылается, описано в [главах 01–04](01-overview.md). Общие правила TDD, уровни тестов и харнессы ядра — в [главе 12 руководства по ядру](../../codelab_agent_core/doc/12-testing.md).

## Тестирование

Правило пакета — TDD по `packages/dart/codelab_agent_core/AGENTS.md` §2: красный тест, затем код. Время — `FakeClock`, джиттер — `Random(0)`, сервер — `FakeMcpServer`, HTTP — `MockClient`. Реальных процессов и сети в пакете нет. Синхронизация — события и `Completer`, а не `Future.delayed` (`AGENTS.md` пакета, §3).

### Что проверяет какой файл

| Файл в `test/` | Что проверяет |
|---|---|
| `json_rpc_test.dart` | кодек: разбор без исключений, `id`, `_meta` |
| `mcp_client_connect_test.dart` | эпохи, рукопожатие, пагинация, кэш эпохи, подписка, `list_changed`, устойчивость входящего канала |
| `mcp_client_call_test.dart` | `tools/call`: результат, ошибки, таймаут, отмена, поздние ответы |
| `mcp_client_spec_conformance_test.dart` | соответствие сценариям спецификации `agent-mcp-client` |
| `streamable_http_test.dart`, `streamable_http_review_test.dart` | HTTP: заголовки, SSE, сессия, возобновление, лимиты, отмена до заголовков |
| `mcp_tool_adapter_test.dart` | `McpTool`: имя, описание, схема, проекция блоков результата |
| `mcp_tool_kind_test.dart` | `kind` не зависит от аннотаций сервера |
| `mcp_tool_goes_through_policy_test.dart` | вызов доходит до сервера только после решения политики (настоящее ядро) |
| `connector_test.dart` | порядок регистрации, коллизии, изоляция сбоев, `list_changed`, `callTimeout` |
| `connector_replace_servers_test.dart` | `replaceServers` |
| `connector_changes_test.dart` | поток `changes` |
| `mcp_list_changed_boundary_test.dart` | обновление набора только на границе шага |
| `mcp_logs_no_secrets_test.dart` | в логах и журнале нет значений `env`, `headers`, секретов |
| `supervisor/mcp_reconnect_test.dart` | задержки, сброс счётчика, вызовы во время простоя, закрытие |
| `supervisor/mcp_supervisor_state_test.dart` | сводки, `reconnect`, `setEnabled`, секреты, `blockedReason`, ручной выбор |
| `supervisor/mcp_cancel_races_test.dart`, `mcp_runtime_cancel_test.dart` | отмена и гонки на закрытии сессии |

### Общая обвязка

| Что | Где | Для чего |
|---|---|---|
| `McpHarness` | `test/support/harness.dart` | `FakeClock` и `RecordingLogger`; `connect(server, kind:)` подключает клиента по транспорту в памяти, `connectHttp(server)` — по настоящему `StreamableHttpTransport` над `MockClient` |
| `SupervisorRig` | `test/support/supervisor_rig.dart` | коннектор над `FakeMcpTransportFactory`; `connect([...])`, `crash(name)`, `settle()`, `cancelSession()`; помощники `stdio`, `fakeServer`, `summaryOf`, `delayWithinBounds` |
| `SpyTransportFactory` | там же | пишет описания, с которыми вызван `open`, и умеет задерживать `open` (`gate`) |
| `CoreStack` | `test/support/core_stack.dart` | настоящее ядро (`buildAgentCore`) с `McpClientConnector` над фейковым сервером и сценарной моделью — проверяет путь «модель → политика → MCP-сервер» |
| `throwing_transport.dart` | `test/support/` | обёртка над транспортом: бросает не-MCP исключение на `send` сообщения с заданным методом (проверка изоляции сбоев) |

### Что умеет `FakeMcpServer`

Фейковый сервер из `package:codelab_agent_mcp/testing.dart` написан по тексту спецификации, а не по чужому SDK. Он принимает клиентскую половину пары транспортов в памяти (`connect(kind:)`) или HTTP-запросы (`httpClient()`, `handleHttp`). Основные настройки конструктора:

| Параметр | Что даёт |
|---|---|
| `era` | `FakeMcpEra.modern`, `legacy` или `dualEra` |
| `tools`, `responses` | набор `FakeMcpTool` и ответы `FakeToolResponse` по имени инструмента: `result`, `text`, `error`, `raw`, `gated` (ответ после `Completer`), `crash` |
| `pageSize`, `endlessPages`, `emptyStringFirstCursor` | пагинация `tools/list` |
| `listChanged`, `listen`, `acknowledgeToolsListChanged`, `duplicateAck` | подписка и её исходы (`FakeListen`: `acknowledge`, `withhold`, `error`, `close`, `abort`) |
| `supportedVersions`, `refuseWithUnsupportedVersion`, `probeErrorCode`, `legacyProbe` | сценарии выбора эпохи |
| `httpStyle`, `httpSessionId`, `probeReply`, `allowGetStream`, `allowDelete`, `pollCloses` | HTTP: JSON или SSE, сессия, ответ на пробу, потоки |
| `abortDiscover`, `abortListens`, `abortListResponses` | обрыв потока ответа без обрыва транспорта |

Что можно прочитать после прогона: `requests` (все сообщения клиента), `methods` (их имена), `calls` (`{name, arguments}` принятых `tools/call`), `cancelledRequestIds`, `abandoned`, `violations` (нарушения порядка рукопожатия), `httpLog` (HTTP-запросы с заголовками), `sentHeaders`, `subscriptions`, `closedTransports`. Что можно сделать на лету: `notifyToolsListChanged`, `setTools`, `setResponse`, `sendRequest`, `crash`, `abortResponse`, `expireSession`.

`FakeMcpTransportFactory(servers, failures: {...})` выбирает сервер по `name` из описания и имитирует ошибку запуска (`failures['name'] = 'spawn failed: …'`).

### Скелеты тестов

Три скелета проверены: каждый скомпилирован и прошёл (`fvm dart test`) во временном файле `test/`, затем файл удалён. Импорты те же, что у соседних тестов: тесты пакета берут внутренние типы из `src/` (`// ignore_for_file: implementation_imports`).

**Рукопожатие legacy-сервера.**

```dart
// ignore_for_file: implementation_imports
import 'package:codelab_agent_mcp/src/protocol.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  test('legacy-сервер: initialize после пробы', () async {
    final h = McpHarness();
    final server = FakeMcpServer(
      era: FakeMcpEra.legacy,
      tools: const [FakeMcpTool('echo')],
    );
    final client = await h.connect(server);
    expect(server.methods, [
      'server/discover',
      'initialize',
      'notifications/initialized',
      'tools/list',
    ]);
    expect(client.era, McpEra.legacy);
    await client.close();
  });
}
```

**Падение сервера и повтор.** Двигайте время только через `rig.clock.elapse`.

```dart
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/supervisor_rig.dart';

void main() {
  test('сервер падает и возвращается', () async {
    final rig = SupervisorRig({'docs': fakeServer(['t'])});
    final session = await rig.connect([stdio('docs')]);

    await rig.crash('docs');
    final failed = summaryOf(session, 'docs');
    expect(failed.state, McpServerState.failed);
    expect(delayWithinBounds(failed.retryIn!, 0), isTrue);

    await rig.clock.elapse(failed.retryIn!);
    expect(summaryOf(session, 'docs').state, McpServerState.connected);
    await session.close();
  });
}
```

**Проекция результата в текст модели.** Тест строит `McpTool` над клиентом и исполняет его так, как это делает исполнитель ядра:

```dart
// ignore_for_file: implementation_imports
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_mcp/src/mcp_tool.dart';
import 'package:codelab_agent_mcp/testing.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  test('блок результата виден модели', () async {
    final h = McpHarness();
    final server = FakeMcpServer(
      tools: const [FakeMcpTool('report')],
      responses: {
        'report': FakeToolResponse.result({
          'content': [
            {'type': 'text', 'text': 'готово'},
            {'type': 'video', 'uri': 'file:///demo.mp4'},
          ],
        }),
      },
    );
    final client = await h.connect(server);
    final tool = McpTool.create(
      server: 'fake',
      definition: client.tools.single,
      client: client,
      logger: h.logger,
      sessionId: const SessionId('s1'),
    )!;
    final result = await tool.execute(
      const {},
      ToolContext(
        env: MemoryExecutionEnv(cwd: '/'),
        cancel: CancelToken.none,
        onUpdate: (_) {},
        toolCallId: 'tc-1',
        services: ToolServices(clock: h.clock, logger: h.logger),
      ),
    );
    final text = (result.content.single as TextContent).text;
    expect(text, contains('[unsupported content: video]'));
  });
}
```

Тест прошёл на текущем коде: блок `video` сегодня попадает в ветку «неизвестный тип». Если вы добавляете для него отдельную ветку (рецепт ниже), этот тест сначала краснеет, потому что ожидание меняется.

### Что запускать

Для правки в пакете: `fvm dart format`, `fvm dart analyze` и `fvm dart test` в каталоге пакета. Если изменились импорты или `pubspec.yaml` — `melos run guard`. Если изменилась ACP-проекция или фикстуры MCP — `melos run conformance:agent`; если встроенный режим — `melos run conformance:embedded`. Если менялся stdio-процесс или хост агента — `fvm dart test test/mcp_stdio_process_test.dart` и `test/mcp_reconnect_process_test.dart` в `apps/codelab_agent`. Общие правила проверки — [`AGENTS.md` корня, §21](../../../../AGENTS.md).

## Рецепты

### Рецепт «Новый транспорт»

Нужен, когда сервер доступен не по stdio и не по streamable HTTP. Это изменение поведения и public API: оно требует [OpenSpec change](../../../../openspec/specs/agent-mcp-client/spec.md) до кода. Протокол MCP определяет только эти два транспорта (`basic/transports/index.md`), поэтому сначала проверьте, что новый транспорт описан в спецификации MCP или в проектном решении.

Что менять, по порядку:

1. **Порт.** Класс `McpTransport` и фабрику `McpTransportFactory` пишет тот пакет, у которого есть нужный ввод-вывод: если нужен `dart:io`, это `codelab_agent_io`, иначе — этот пакет. Скелет транспорта (проверен компиляцией и прогоном):

   ```dart
   import 'dart:async';

   import 'package:codelab_agent_core/codelab_agent_core.dart';

   final class MyTransport implements McpTransport {
     final _incoming = StreamController<String>();
     final _aborted = StreamController<McpRequestAbort>.broadcast();
     final _done = Completer<McpTransportClosed>();

     @override
     String get kind => 'my'; // от kind зависят зеркальные заголовки и отмена

     @override
     Stream<String> get incoming => _incoming.stream;

     @override
     Stream<McpRequestAbort> get abortedRequests => _aborted.stream;

     @override
     Future<McpTransportClosed> get done => _done.future;

     @override
     Future<void> send(
       String message, {
       Map<String, String> headers = const {},
     }) async {
       // записать message в канал; сбой — McpTransportException с текстом
       // кода CodeLab, без URL, аргументов и значений секретов
     }

     @override
     Future<void> abandon(Object requestId) async {}

     @override
     Future<void> close() async {
       if (!_done.isCompleted) {
         _done.complete(const McpTransportClosed('closed'));
       }
       await _incoming.close();
       await _aborted.close();
     }
   }

   final class MyTransportFactory implements McpTransportFactory {
     @override
     Set<String> get transports => const {'my'};

     @override
     Future<McpTransport> open(
       McpServerConfig server, {
       required String cwd,
       required CancelToken cancel,
       required Logger logger,
     }) async => MyTransport();
   }
   ```

2. **Описание сервера в ядре.** `McpServerConfig` — запечатанный класс с ветвями `McpStdioServerConfig` и `McpHttpServerConfig`; новая ветвь и ключ `transport` добавляются в `codelab_agent_core/lib/src/mcp/mcp_server_config.dart`, а разбор `type` в конфигурации и профиль хоста (транспорты capability `mcp`) — рядом (см. [рецепт 9 ядра](../../codelab_agent_core/doc/11-extending.md#рецепт-9-mcp-сервер)).
3. **`McpTransports`** в `connector.dart`: поле, `keys` и `operator []` знают только `stdio` и `http`. `_connectOnce` берёт фабрику через `_owner._factories[effective.transport]`.
4. **Ветки по `kind` в `McpClient`.** `_filter` (отбор по `x-mcp-header` только для `http`), `_mirrorHeaders` (только `http`), `_signalCancel` и `close` (разные сигналы отмены для `stdio` и `http`). Новый `kind` по умолчанию ведёт себя как stdio в `_signalCancel`: если ему нужен другой сигнал, добавьте ветку явно.
5. **Тесты.** Фейк для нового транспорта по образцу `_FakeTransport` в `fake_mcp_server.dart` и красные тесты контракта: `send` и `incoming`, обрыв (`done`), локальный сбой (`abortedRequests`), `close()`, причины без секретов.
6. **Сторож.** Если транспорт использует новый пакет, `melos run guard` и `pubspec_allowlist_test.dart` потребуют правила; пакет не должен импортировать `dart:io`.

### Рецепт «Новый вид блока результата»

Нужен, когда сервер присылает блок `content[*].type`, который сегодня превращается в `[unsupported content: <type>]` (например, `video` из примера выше). Меняется один файл.

1. Убедитесь, что тип описан в [`server/tools.md`](../../../../docs/protocols/mcp/specification/server/tools.md) референса MCP (`CallToolResult`). Тип, которого там нет, вводить нельзя.
2. Напишите красный тест по скелету выше: сервер отдаёт блок, ожидание — новый текст.
3. Добавьте ветку в `switch (block['type'])` функции `_project` в `mcp_tool.dart`. Результат — строка в `parts` (она попадёт в общую ограду недоверенного вывода) или `ImageContent`. Скелет (фрагмент, не самостоятельный файл):

   ```dart
   case 'video':
     parts.add(
       '[video omitted: ${block['mimeType'] ?? ''}, '
       '${_byteCount('${block['data'] ?? ''}')} bytes]',
     );
   ```

4. Обновите таблицу в [главе 01](01-overview.md#результат-вызова) и тест `mcp_tool_adapter_test.dart`.

Не выводите содержимое блока без ограничений: результат недоверен и огораживается исполнителем ядра (P-16). Бинарные данные показывайте размером, как делают `audio` и `resource` без `text`.

### Рецепт «Новое поведение фейкового сервера»

Нужен, когда тесту нужен сервер, который ведёт себя по-новому (например, отвечает ошибкой на `initialize`).

1. Добавьте поле конструктора `FakeMcpServer` (оно `final` либо изменяемое, если тест меняет его на лету) с doc-комментарием «почему и как использовать».
2. Реализуйте реакцию в `_handleRequest` или `_handleNotification` (`fake_mcp_server.dart`). Для HTTP-ответа — `_FakeHttp` в `fake_mcp_http.dart`.
3. Запишите в `requests`, `violations` или новое публичное поле то, что тест будет проверять.
4. Поведение фейка должно быть из спецификации MCP: фейк — не место для выдуманных кодов.

### Рецепт «Изменить задержки повтора или переходы автомата»

1. Начните с теста в `test/supervisor/` на `SupervisorRig`: он двигает время и фиксирует `Random(0)`.
2. Формула и пределы — константы и `_fail` в `connector.dart`: `_maxRetryDelay`, `_stableConnection`, `_lastErrorLimit`.
3. Любое изменение состояний ядра (`McpServerState`) — это общий порт: ядро, UI хоста и спецификация [`agent-mcp-client`](../../../../openspec/specs/agent-mcp-client/spec.md) меняются вместе, поэтому нужен OpenSpec change.
4. Новое событие лога: имя `mcp.<что>.<как>`, поля — только коды и числа CodeLab; перед добавлением проверьте `mcp_logs_no_secrets_test.dart`.

### Рецепт «Использовать ещё один метод MCP»

Клиент сегодня знает только инструменты. Добавление, например, `resources/list` — новая функциональность продукта, а не правка: нужны OpenSpec change, спецификация и согласование с ядром (порт `McpSessionTools` не содержит ресурсов). Если решение принято: модель ответа — в `protocol.dart`, запрос — в `McpClient` через общий `_request` (он уже даёт таймаут, отмену и повтор), тесты — на `FakeMcpServer`.

## События и тексты ошибок

Причина сбоя подключения (`reason` в `mcp.server.failed` и `lastError` в сводке) — всегда текст кода CodeLab длиной не больше 200 рун. Основные тексты, которые формирует пакет (полный перечень — в коде, поиск по `reason`):

| Текст | Где возникает | Откуда |
|---|---|---|
| `no common protocol version: server supports [<версии>]` | нет общей версии протокола | `_modernHandshake`, `-32022` |
| `server rejected the probe (code <N>)` | modern-ошибка пробы, кроме `-32022` | `_handshake` |
| `unsupported protocol version <версия>` | версия `initialize` не из принятых | `_legacyHandshake` |
| `no answer to <метод> within <N> s` | нет ответа в срок подключения | `_start` |
| `disconnected: <причина транспорта>` | транспорт закрылся во время подключения | `_start` |
| `response stream closed` | оборван поток ответа, повтор не помог | `_start` |
| `<метод> failed (code <N>)` | ошибка JSON-RPC на этапе подключения | `_start` |
| `<метод> failed: <причина>` | локальный сбой транспорта: `HTTP 500`, `response body too large` | `_start` |
| `invalid server answer: <что>` | ответ не по схеме | `_start` |
| `tools/list pagination did not end` | больше 100 страниц | `_listAll` |
| `unexpected error: <тип исключения>` | неожиданное исключение клиента, фабрики или транспорта | `_start`, `_connectOnce` |
| `transport <ключ> is not available` | у хоста нет фабрики этого транспорта | `_connectOnce` |
| `connection cancelled` | сессия закрыта во время попытки | `_attempt`, `close` |
| `connection failed: <тип исключения>` | сбой HTTP-соединения | `StreamableHttpTransport._dispatch` |
| `invalid url` | схема не `http` и не `https` или пустой хост | `StreamableHttpTransportFactory.open` |
| `HTTP redirect (<N>) is not followed` | `3xx` | `_checkStatus` |
| `HTTP session expired` | `404` при открытой legacy-сессии | `_checkStatus`, `_expire` |
| `closing failed: <тип исключения>` | сбой закрытия клиента | `_closeLogged` |
| `invalid JSON in the response` | HTTP-ответ не JSON | `StreamableHttpTransport._readResponse` |
| `not an http server` | фабрике HTTP передан не HTTP-сервер | `StreamableHttpTransportFactory.open` |
| `tool name collision: <имя>` | коллизия имён (`disabled`) | `_resolve` |
| `disabled by /mcp disable` | выключен командой | `setEnabled` |
| `secret <имя> is not set`, `secret <имя> cannot be read: …` | не раскрыт секрет (текст ядра) | `McpSecretsException` |
| `spawn failed: …` | не запустился процесс stdio (текст `codelab_agent_io`) | `StdioMcpTransportFactory.open` |

Тексты для модели (`McpCallError`) перечислены в [главе 02](02-client-protocol.md#вызов-инструмента).

## Частые проблемы

### Сервер в `failed`, в `LAST ERROR` — `no common protocol version: server supports [...]`

**Симптом.** Сервер не подключается, в скобках — даты.

**Причина.** Сервер поддерживает версии, которых нет у клиента: клиент говорит только на `2026-07-28` и принимает legacy `2025-11-25`, `2025-06-18`, `2025-03-26`. Более ранние версии, например `2024-11-05`, не поддержаны: для них будет `unsupported protocol version <дата>`. Если в скобках пусто, сервер прислал версии не в формате даты.

**Что сделать.** Обновить сервер до поддерживаемой версии. Менять клиент можно только через OpenSpec change (версии заданы `design.md`, D2).

### `no answer to initialize within 10 s` или `no answer to server/discover …`

**Симптом.** Подключение заканчивается по таймауту `connectTimeout`; повтор идёт по расписанию.

**Причина.** Сервер молчит. Для stdio — процесс запустился, но не читает stdin или пишет что-то другое, кроме JSON-RPC; для HTTP — сервер не отвечает на `POST`. Проба `server/discover` ждёт не больше 5 с, остаток времени получает `initialize`.

**Что сделать.** Запустить сервер вручную и отправить ему `initialize`. Если сервер просто медленный — поднять `connect_timeout` сервера в `config.yaml` ([настройка](../../../../docs/user/configuration.md#mcp-серверы)). Подробный лог (`--log-level debug`) покажет `mcp.server.state` и `mcp.message.ignored`.

### `transport http is not available`

**Симптом.** Такой текст в `lastError` — только у хоста или теста, где транспорт `http` включён в профиле, а фабрики для него в `McpTransports` нет.

**Причина.** У настоящих хостов профиль держит `mcp` как `CapabilityTransport({stdio, http})`. Если транспорта нет в профиле, рантайм отбрасывает сервер до коннектора и пишет `mcp.server.skipped` «transport http is off in profile …» (`agent_runtime.dart`). Если транспорт в профиле, а фабрики нет, `buildAgentCore` бросает `HostWiringException` (HOST-3). Текст `transport http is not available` виден, когда капабилити включена напрямую (`CapabilityOn`) без фабрики.

**Что сделать.** Для настоящего хоста — искать `mcp.server.skipped`, а не `failed`. В тестах — `FakeMcpTransportFactory` с нужными `transports`.

### `invalid url`

**Симптом.** HTTP-сервер из `session/new` в `failed` с `invalid url`.

**Причина.** `url` не `http://` и не `https://`, либо хост пуст. Для серверов из конфигурации загрузка отвергает такой `url` раньше (`expected an http or https URL`), и ошибку показывает `codelab config check`; `invalid url` из фабрики видит только сервер клиента ACP.

**Что сделать.** Исправить `url` сервера.

### `HTTP redirect (307) is not followed`

**Симптом.** Подключение или вызов падают с `disconnected: HTTP redirect (307) is not followed`.

**Причина.** Сервер отвечает редиректом. Клиент намеренно не ходит по редиректам: заголовки с секретами не должны уйти на другой адрес.

**Что сделать.** Указать в `url` конечный адрес сервера.

### `HTTP session expired`

**Симптом.** После работы вызовы получают `MCP server <имя> disconnected during the call: HTTP session expired`, сервер уходит в `failed` и переподключается.

**Причина.** Legacy-сервер ответил `404` на запрос с `Mcp-Session-Id`: сессия на сервере кончилась.

**Что сделать.** Ничего: супервизор подключит сервер заново и откроет новую сессию. Если это происходит часто, смотрите настройки таймаута сессий на стороне сервера.

### Инструмент сервера пропал из списка

**Симптом.** Сервер `connected`, а часть инструментов у модели отсутствует.

**Причина.** Инструмент отсеян: `mcp.tool.invalid` с `reason`:

| `reason` | Что не так |
|---|---|
| `tool has no name` | пустое имя |
| `inputSchema is not an object` | схема не объект |
| `malformed inputSchema` | неверная форма `type`, `required`, `properties` или `enum`, либо вложенность больше 32 |
| `invalid x-mcp-header` | HTTP: нарушено ограничение расширения `x-mcp-header` |
| `task support required` | legacy: сервер обещал задачи, а инструмент требует их |

**Что сделать.** Исправить описание инструмента на стороне сервера. Запись содержит имя инструмента (до 64 рун) и причину. Чтобы увидеть её, нужен уровень `warning` и выше — он включён по умолчанию.

### Сервер `disabled`, `lastError: tool name collision: …`

См. [частые проблемы ядра](../../codelab_agent_core/doc/13-troubleshooting.md#mcp-сервер-в-состоянии-disabled): имя инструмента совпало с чужим. Источник — `_resolve` (`connector.dart`); таблица причин — в [главе 04](04-connector-and-supervisor.md#коллизии-имён).

### Вызов: `did not answer tools/call within N s`

**Симптом.** Модель получает ошибку `MCP server <имя> did not answer tools/call within <N> s.`

**Причина.** Инструмент работал дольше `callTimeout`: у сервера `call_timeout` из конфигурации, иначе 10 минут. Клиент отправил серверу сигнал отмены и больше не ждёт ответа.

**Что сделать.** Поднять `call_timeout` сервера (от `1s` до `24h`) или ускорить инструмент. Запись `mcp.call.timeout` содержит `tool_call_id` и `request_id` для сверки с журналом сервера.

### Вызов: `is not connected (retry in <n>s)`

**Симптом.** Инструменты сервера отвечают `MCP server <имя> is not connected (retry in <n>s). Continue without it or try later.`

**Причина.** Сервер в `failed`: процесс вышел или соединение потеряно. Супервизор повторит попытку через `<n>` секунд. Задержка растёт: 1, 2, 4, 8, 16, 30 с, затем 30 с.

**Что сделать.** Смотреть `lastError` в `/mcp list`. Сразу переподключить: `/mcp reload <имя>` (метод `reconnect`). Если сервер падает сразу после подключения, смотрите stderr процесса: его строки пишутся как `mcp.server.stderr` на уровне `trace`.

### Список инструментов не обновляется

**Симптом.** Сервер добавил инструмент, а модель его не видит.

**Причина (по порядку проверки).** Сервер не объявил `tools.listChanged`; подписка не подтверждена (в логе `mcp.message.ignored` с `kind: subscription_failed` — сервер живёт без обновлений); обновление ждёт границы шага (`takeUpdate`); новый набор вызвал коллизию имён, и сервер ушёл в `disabled`.

**Что сделать.** `/mcp reload <имя>` перечитывает набор сразу. Если сервер должен слать обновления, проверьте `capabilities.tools.listChanged` в ответе `server/discover` или `initialize`.

### `secret <имя> is not set`

**Симптом.** Сервер в `failed` с таким `lastError`, транспорт не открывается.

**Причина.** В `env` или `headers` сервера стоит `${secret:<имя>}`, а значения в хранилище нет.

**Что сделать.** Записать секрет (`codelab secret set`) — следующая попытка раскроет его заново, перезапускать агента не нужно. Серверы, пришедшие от клиента ACP в `session/new`, секреты не раскрывают: `${secret:…}` у них литерал.

### Тест завис

**Симптом.** Тест с `FakeClock` не завершается.

**Причина.** Таймеры (`Clock.timer`) срабатывают, только когда тест двигает время. Ожидание подтверждения подписки, пробы эпохи или повтора ждёт `clock.elapse`.

**Что сделать.** Продвинуть время на нужный срок (`h.clock.elapse(const Duration(seconds: 10))`) или `rig.settle()`, чтобы отдать управление очереди событий. Не используйте `Future.delayed` и реальные паузы.

### Сторож (`melos run guard`) красный

**Симптом.** Падает правило импортов или `pubspec_allowlist_test.dart`.

**Причина.** В `lib/` пакета появился запрещённый импорт (`dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, Flutter, ACP-пакет, клиентский пакет, `codelab_agent_io`) либо новая зависимость вне allowlist (`codelab_agent_core`, `http`, `meta`, `async`). Это касается и `lib/testing.dart`.

**Что сделать.** Убрать импорт, а ввод-вывод вынести в порт ядра и реализовать его в `codelab_agent_io`. Новую зависимость — только через OpenSpec change.

## Смотрите также

- [Начало работы](00-getting-started.md).
- [Руководство по ядру](../../codelab_agent_core/doc/README.md) — порты, разрешения, сессии.
- [`AGENTS.md` пакета](../AGENTS.md).
