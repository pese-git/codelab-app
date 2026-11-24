# Тестирование, расширение и частые проблемы

Глава для того, кто меняет транспорты или добавляет новый. Устройство — в [главе 01](01-design.md), запуск тестов — в [главе 00](00-getting-started.md).

## Как тестируются транспорты

Уровни тестов репозитория описаны в `docs/architecture/testing.md`. В этом пакете три приёма, и каждый выбирается по тому, что нельзя подменить фейком.

| Приём | Когда | Пример |
|---|---|---|
| потоки в памяти | логика кадров и очередь записи без процесса | `stdio_server_transport_test.dart`: `StreamController<List<int>>` как вход, `IOSink` над `StreamController` как выход |
| настоящий `HttpServer` на loopback | рукопожатие, заголовки, закрытие сокета | `websocket_handshake_rejection_test.dart`, `websocket_server_transport_test.dart` |
| настоящий процесс | запуск, выход процесса, эскалация сигналов | `test/io/stdio_acp_transport_close_test.dart` (`sh` с `trap` и `kill -0`) |

Пара в памяти и `FakeAcpTransport` — для проверки потребителей транспорта, не самого транспорта. `FakeAcpTransport` живёт в [`codelab_acp_testing`](../../codelab_acp_testing/doc/README.md), и этот пакет зависит от него только как `dev_dependency` (`AGENTS.md` репозитория, §5): в обратную сторону `codelab_acp_testing` зависит от транспортов.

Правила тестов пакета:

- сокет — только `InternetAddress.loopbackIPv4` и порт `0`; адрес берётся из `server.port`;
- токены и ключи в тестах выдуманные; тест, который проверяет утечку, ищет в тексте ошибки заведомый маркер вроде `sk-test-leak-0123456789`;
- каждый транспорт и сервер закрывается в `tearDown` или `addTearDown`, иначе процесс теста не завершится;
- ожидание процесса или сокета ограничивается `.timeout(...)`, чтобы повисший `close` не стал зависшим CI;
- тест, который запускает `sh`, пригоден только для POSIX; помечайте такой файл аннотацией `@TestOn('!windows')`, как `stdio_acp_transport_close_test.dart`;
- каждое требование из `openspec/specs/agent-transports/spec.md` имеет сценарий; новое поведение транспорта начинается с красного теста и правки спецификации.

## Рецепт: добавить новый транспорт

Допустим, нужен клиентский транспорт ACP поверх TCP: одна строка UTF-8 — одно сообщение. (Это учебный пример: профиль подключения такого вида в продукте не предусмотрен.) Новый публичный транспорт меняет публичный API и спецификацию `agent-transports`, поэтому начинается с OpenSpec change (`AGENTS.md` репозитория, §17); дальше — реализация.

**1. Выберите барель.** Это решает всё остальное.

| Транспорту нужно | Куда класть | Что экспортировать |
|---|---|---|
| `dart:io`, процесс, сокет, `web_socket_channel/io.dart` | `lib/src/io/<имя>_acp_transport.dart` | строку `export` в `lib/io.dart` |
| только чистый Dart | `lib/src/<имя>_acp_transport.dart` | `export` в `lib/codelab_acp_transports.dart`; путь файла добавьте в список точек входа `test/web_safe_barrel_test.dart` |

Файл вне `lib/src/io/` и вне `lib/io.dart` не должен импортировать `dart:io` ни прямо, ни транзитивно: сторож (`packages/dart/codelab_architecture_tests/test/support/rules.dart`) исключает из проверки только `lib/io.dart` и `lib/src/io/`. Правило нового пакета сторожа не нужно: правило этого пакета уже есть.

**2. Опишите конфигурацию**, если она есть. Конфигурации — freezed-классы в `lib/src/transport_configs.dart`, они web-безопасны. После правки выполните `fvm dart run build_runner build --delete-conflicting-outputs` в пакете. В примере конфигурация — два поля транспорта.

**3. Реализуйте порт.** Скелет ниже собран по тому же образцу, что `StdioAcpTransport` и `WebSocketAcpTransport`; он проверен тестом из шага 5.

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';

/// Клиентский транспорт ACP поверх TCP: одна строка UTF-8 — одно сообщение.
final class TcpAcpTransport implements AcpTransport {
  TcpAcpTransport({required this.host, required this.port});

  final String host;
  final int port;

  final _inbound = StreamController<JsonRpcMessage>.broadcast(sync: true);
  final _events = StreamController<AcpTransportEvent>.broadcast(sync: true);
  Socket? _socket;
  StreamSubscription<String>? _subscription;
  var _state = AcpTransportState.idle;
  var _isClosed = false;

  @override
  Stream<JsonRpcMessage> get inbound => _inbound.stream;

  @override
  Stream<AcpTransportEvent> get events => _events.stream;

  @override
  AcpTransportState get state => _state;

  @override
  Future<void> start() async {
    if (_isClosed) {
      throw const AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'TCP ACP transport is closed.',
      );
    }
    if (_state == AcpTransportState.connected ||
        _state == AcpTransportState.connecting) {
      return;
    }
    _setState(AcpTransportState.connecting);
    try {
      final socket = await Socket.connect(host, port);
      _socket = socket;
      _subscription = socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine, onError: _onError, onDone: _onDone);
      _setState(AcpTransportState.connected);
    } on Object catch (error, stackTrace) {
      _fail(
        AcpTransportException(
          code: AcpTransportErrorCode.startFailed,
          message: 'Failed to connect TCP ACP agent.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    final socket = _socket;
    if (_state != AcpTransportState.connected || socket == null) {
      throw const AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'TCP ACP transport is not connected.',
      );
    }
    try {
      socket.writeln(encodeJsonRpcMessage(message));
      await socket.flush();
    } on Object catch (error, stackTrace) {
      throw AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'Failed to send ACP message over TCP.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> close({Duration? timeout}) async {
    if (_isClosed) return;
    _isClosed = true;
    _setState(AcpTransportState.closing);
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close().timeout(
      timeout ?? const Duration(seconds: 5),
      onTimeout: () {},
    );
    _socket = null;
    _setState(AcpTransportState.closed);
    await _inbound.close();
    await _events.close();
  }

  void _onLine(String line) {
    if (_isClosed || line.isEmpty) return;
    try {
      _inbound.add(decodeJsonRpcMessage(line));
    } on JsonRpcProtocolException catch (error, stackTrace) {
      _fail(
        AcpTransportException(
          code: AcpTransportErrorCode.protocolViolation,
          message: 'Agent wrote invalid ACP JSON-RPC to TCP.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  void _onError(Object error, StackTrace stackTrace) => _fail(
    AcpTransportException(
      code: AcpTransportErrorCode.receiveFailed,
      message: 'Failed to read the TCP stream.',
      cause: error,
      stackTrace: stackTrace,
    ),
  );

  void _onDone() {
    if (_isClosed || _state == AcpTransportState.failed) return;
    _fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'TCP ACP agent disconnected unexpectedly.',
      ),
    );
  }

  void _fail(AcpTransportException error) {
    if (_isClosed) return;
    _setState(AcpTransportState.failed);
    _events.add(AcpTransportEvent.failure(error));
  }

  void _setState(AcpTransportState next) {
    _state = next;
    _events.add(AcpTransportEvent.stateChanged(next));
  }
}
```

Что в скелете обязательно, и откуда это следует:

- `_setState` публикует **каждый** переход, а `_fail` — состояние `failed` и событие `failure`. После `close()` сбои не публикуются (`if (_isClosed) return`): закрытие не должно шуметь.
- `close()` идемпотентен, отменяет подписку, закрывает ресурс и **оба** контроллера. Повторный вызов ничего не делает. После него `start()` бросает `closed`.
- `start()` при ошибке публикует `failure(startFailed)` и пробрасывает исходное исключение, как `WebSocketAcpTransport`. Потребитель разбирает и то и другое ([глава 01](01-design.md#ошибки-start-исходное-исключение-и-событие)).
- Кодирование и разбор — только `encodeJsonRpcMessage` и `decodeJsonRpcMessage` из `codelab_acp_protocol`. Свои форматы запрещены: `AGENTS.md` репозитория (§3.4) не разрешает придумывать ACP.
- Транспорт не пишет в `print`, не показывает диалогов и не решает, переподключаться ли (`AGENTS.md` пакета). Всё, что нужно потребителю, — события.
- Тексты ошибок не содержат секретов: не кладите в `message` адрес с токеном, заголовки и содержимое сообщения.

Если транспорт серверный (клиент уже подключён), разбирайте строки через `decodeServerFrame` из `lib/src/io/server_frames.dart`: плохой кадр тогда получает ответ `-32700` или `-32600`, а соединение живёт. Образец — `StdioServerAcpTransport`.

**4. Зарегистрируйте экспорт.** Для примера — строка `export 'src/io/tcp_acp_transport.dart';` в `lib/io.dart`. Потребитель импортирует `package:codelab_acp_transports/io.dart` в своём composition root. Сам выбор транспорта по профилю подключения (`ConfigTransportResolver`, `ioTransportResolver` в `codelab_client_io`) — отдельная правка клиентского слоя; новый вид профиля меняет контракт настроек, это тоже OpenSpec change.

**5. Напишите тест.** Тест поднимает `ServerSocket` на loopback, который возвращает каждую строку обратно:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:test/test.dart';

import 'tcp_acp_transport.dart';

void main() {
  late ServerSocket server;
  final accepted = <Socket>[];
  late Completer<void> connected;

  setUp(() async {
    accepted.clear();
    connected = Completer<void>();
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) {
      accepted.add(socket);
      connected.complete();
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(socket.writeln);
    });
  });

  tearDown(() => server.close());

  test('a message goes out and comes back', () async {
    final transport = TcpAcpTransport(host: '127.0.0.1', port: server.port);
    final first = transport.inbound.first;
    await transport.start();
    await transport.send(
      const JsonRpcMessage.notification(method: 'session/update'),
    );

    expect(
      await first.timeout(const Duration(seconds: 5)),
      isA<JsonRpcNotification>(),
    );
    await transport.close();
    expect(transport.state, AcpTransportState.closed);
  });

  test('a dropped connection is a disconnected failure', () async {
    final transport = TcpAcpTransport(host: '127.0.0.1', port: server.port);
    final failure = transport.events
        .where((event) => event is AcpTransportFailure)
        .cast<AcpTransportFailure>()
        .first;
    await transport.start();
    await connected.future.timeout(const Duration(seconds: 5));
    for (final socket in accepted) {
      await socket.close();
    }

    final event = await failure.timeout(const Duration(seconds: 5));
    expect(event.error.code, AcpTransportErrorCode.disconnected);
    // Выйти из обработчика события, прежде чем закрывать транспорт.
    await Future<void>.delayed(Duration.zero);
    await transport.close();
  });
}
```

Скелет и тест проверены запуском (`fvm dart analyze` и `fvm dart test`): оба теста проходят. В пакете файл теста лежит в `test/io/`, а импорт транспорта — `package:codelab_acp_transports/io.dart`.

Что должен проверять тест любого нового транспорта:

| Проверка | Почему |
|---|---|
| обмен сообщениями в обе стороны | базовый контракт порта |
| сбой соединения даёт `failed` и `failure(disconnected)`, а не молчание | `AcpClientApplication` по событию переводит соединение в `failed` |
| ошибка запуска: исключение и событие `startFailed` без секретов | `AGENTS.md` репозитория, §10, §16 |
| `close()` дважды, `close()` во время `start()`, `start()` и `send()` после `close()` | идемпотентность и гонки (`AGENTS.md` репозитория, §9) |
| плохой кадр: клиентский — `failed` и `protocolViolation`, серверный — ответ ошибкой и живое соединение | ACP-4 |
| после `close()` процесс или сокет освобождены | иначе утечка процессов |

**6. Прогоните проверки.** `fvm dart format`, `fvm dart analyze`, `fvm dart test` в пакете; `guard`, если трогали импорты; `web-compile`, если трогали основной барель; `conformance:client` и `conformance:agent` — они гоняют корпус ACP-фикстур через транспорты. Обновите `README.md` пакета (таблица «Что внутри») и эту главу, если изменился контракт.

## Частые проблемы

Тексты ниже — из реального кода и запусков; где сообщение содержит порт или путь, они заменены на `<port>`.

### `ProcessException: No such file or directory` при запуске stdio

**Симптом.** `start()` бросает `ProcessException: No such file or directory`, строка `Command: <executable>` без аргументов; в `events` — `failure startFailed: Failed to start stdio ACP agent.`

**Причина.** Команда из `StdioAcpTransportConfig.command` не найдена в `PATH` или путь неверен. `codelabAgentStdioProfile` запускает `codelab-agent`: бинарь должен быть в `PATH` клиента. Аргументов в тексте нет намеренно: они могут быть ключами.

**Что сделать.** Проверьте путь, укажите полный путь в профиле (`copyWith(command: …)`), проверьте `cwd`. Тип и `errorCode` исключения сохранены: `on ProcessException` и `errorCode` годятся для классификации.

### `failure disconnected: Stdio ACP agent exited unexpectedly with code N`

**Симптом.** Соединение рвётся вскоре после запуска или посреди хода; транспорт в `failed`.

**Причина.** Агент завершился сам. Транспорт знает только код выхода, и тот лежит в тексте сообщения. Причину агент обычно пишет в stderr.

**Что сделать.** Найдите перед этим событием `diagnostic` с `source: 'stderr'`: это строки stderr агента. Запустите ту же команду вручную. Для `codelab-agent` смотрите [руководство DevOps по агенту](../../../../apps/codelab_agent/doc/operations.md) (коды выхода, логи).

### `protocolViolation: Agent wrote invalid ACP JSON-RPC to stdout`

**Симптом.** Сразу после запуска или посреди работы транспорт в `failed`, `cause` — `JsonRpcProtocolException(JsonRpcProtocolErrorKind.invalidJson)`.

**Причина.** Агент написал в stdout строку, которая не JSON-RPC: баннер, `print`, лог. По ACP stdout агента несёт только протокол (`16-Transports.md`), и транспорт строгий.

**Что сделать.** В агенте перенесите логи в stderr. Свою обёртку над агентом (например, скрипт запуска) проверьте на лишний вывод в stdout.

### `AcpWebSocketHandshakeRejected(statusCode: 401)` или `403`

**Симптом.** `start()` бросает `AcpWebSocketHandshakeRejected`, `error.cause` события `failure` — то же.

**Причина.** Сервер отказал в обновлении соединения. У `codelab-agent serve --ws` 401 означает неверный или отсутствующий Bearer-токен, а `426` — запрос без upgrade (например, обычный HTTP вместо `ws://`) (`apps/codelab_agent/lib/src/serve/serve_ws.dart`).

**Что сделать.** Проверьте токен и адрес (`ws://`, не `http://`). Не разбирайте текст исключения: берите `statusCode`. Токен в ошибку не попадает.

### `SocketException: Connection refused`

**Симптом.** `start()` бросает `SocketException`; в `events` — `failure startFailed … cause=SocketException: Connection refused`.

**Причина.** По адресу никто не слушает: агент не запущен, порт другой.

**Что сделать.** Проверьте, что `codelab-agent serve --ws` запущен и порт совпадает с `uri`. Это отличие от 401: здесь рукопожатия не было вообще.

### `Invalid header value for Authorization`

**Симптом.** `start()` бросает `AcpTransportException(startFailed)` с текстом `Invalid header value for Authorization.`, `cause` пуст.

**Причина.** Значение заголовка содержит символ вне ASCII или управляющий символ. Типичный случай — токен, прочитанный из файла вместе с переводом строки в конце. Само значение транспорт не показывает.

**Что сделать.** Обрежьте токен (`trim()`) до передачи в `WebSocketAcpTransportConfig`. Допустимы коды от 32 до 126 и табуляция.

### Сообщений нет, ошибок тоже

**Симптом.** Агент ответил (видно по его журналу), а `inbound` клиента пуст; события приходят.

**Причина.** `inbound` клиентских транспортов — broadcast без буфера: сообщение, пришедшее до `listen`, теряется. Подписка сделана после `start()`.

**Что сделать.** Подпишитесь на `inbound` и `events` до `start()`. Для проверки: у пары в памяти буфер до первой подписки есть, у stdio и WebSocket клиента — нет ([глава 01](01-design.md#кто-что-буферизует)).

### `Bad state: Cannot fire new event. Controller is already firing an event`

**Симптом.** В обработчике события `failure` вы вызвали `transport.close()`; в зоне прилетает `Bad state: Cannot fire new event…`, транспорт остаётся в `closing`, потоки не закрыты.

**Причина.** `events` — синхронный broadcast-контроллер, а `WebSocketAcpTransport.close()` публикует состояние `closing` до первого `await`, то есть внутри обработчика. Воспроизведено запуском для `WebSocketAcpTransport` (отказ соединения, `close()` в обработчике `failure`) и для `StdioServerAcpTransport` (плохой кадр, `close()` в обработчике `diagnostic`). `StdioAcpTransport.close()` сперва ждёт `await` и публикует `closing` позже, поэтому не затронут. У `WebSocketServerAcpTransport` `close()` публикует `closing` синхронно, как у остальных.

**Что сделать.** Не закрывайте транспорт синхронно из обработчика `events`: перенесите вызов в микрозадачу.

```dart
transport.events.listen((event) {
  if (event is AcpTransportFailure) {
    scheduleMicrotask(() => transport.close());
  }
});
```

Проверено запуском: с `scheduleMicrotask` транспорт приходит в `closed`.

### `AcpTransportException(sendFailed): … is not connected`

**Симптом.** `send()` бросает `sendFailed` с текстом «… is not connected».

**Причина.** `send` вызван до `start()`, после `failed` или во время `connecting`. У пары в памяти текст такой же: `In-process <client|agent> transport is not connected.`

**Что сделать.** Проверяйте `state == AcpTransportState.connected` и не отправляйте до завершения `start()`. После `failed` создайте новый транспорт: переподключение — дело прикладного слоя.

### `AcpTransportException(closed)`

**Симптом.** `start()` или `send()` бросает `closed`: «… is closed».

**Причина.** Транспорт закрыт; повторно использовать его нельзя. У клиентского stdio то же бывает, если `close()` пришёл во время `start()`.

**Что сделать.** Создайте новый транспорт. Если вы ждали `connected`, а получили `closed`, значит, кто-то вызвал `close()` раньше.

### `close()` стоит несколько секунд

**Симптом.** `StdioAcpTransport.close()` возвращается через 5 с или дольше.

**Причина.** Агент не вышел по закрытию stdin. Транспорт ждёт `timeout` (по умолчанию 5 с), затем шлёт `SIGTERM`, ждёт ещё до 2 с и шлёт `SIGKILL`.

**Что сделать.** Агент должен выходить по EOF stdin (`codelab-agent serve --stdio` так и делает). Для своих агентов поправьте цикл чтения. Для тестов передайте короткий `timeout`: `close(timeout: Duration(milliseconds: 200))`.

### `InProcessAcpTransport` отвечает `sendFailed`: `got a value that cannot be copied as JSON`

**Симптом.** `send()` на паре в памяти бросает `sendFailed`, а в сообщении нет ни значения, ни причины.

**Причина.** `params`, `result` или `error.data` содержат то, что не кодируется в JSON: `DateTime`, пользовательский объект, ключ не строкой, `NaN` или бесконечность, цикл. Значение скрыто намеренно: в `params` бывают пути и содержимое файлов.

**Что сделать.** Приведите значения к JSON-типам (`toJson()`, `toIso8601String()`) до `send`. На проводе такое сообщение тоже не ушло бы.

### В диагностике: `Dropped N undelivered in-process message(s) because the peer closed.`

**Симптом.** Событие `diagnostic` с `severity: warning` и `source: 'in_process'` у конца пары.

**Причина.** Второй конец закрыли, а у этого конца не было подписчика на `inbound` или он не был запущен: накопленные сообщения выбросили. Содержимое в диагностику не пишется.

**Что сделать.** Подпишитесь на `inbound` до того, как второй конец закроется; проверьте порядок `start()` и `listen` у потребителя.

### `fvm dart test` не собирает тесты: ошибки в `*.freezed.dart`

**Симптом.** Тестовые файлы с импортом `codelab_acp_testing` не компилируются; в выводе — `Error: The method '$PromptFailureCopyWith' isn't defined…` в `state_machines.freezed.dart`.

**Причина.** `codelab_acp_testing` зависит от `codelab_client_acp`, а части сгенерированного кода у него нет. Генерация одного этого пакета не помогает.

**Что сделать.** Выполните общую генерацию из [`docs/user/run-from-source.md`](../../../../docs/user/run-from-source.md) (шаг с `build_runner` для всех пакетов).

### `web_safe_barrel_test`: `lib/… is missing`

**Симптом.** Тест падает с причиной вроде `lib/codelab_acp_transports.dart is missing`.

**Причина.** Тест читает файлы по относительному пути `lib/…`, то есть от текущего каталога. Запуск из корня репозитория пути не находит.

**Что сделать.** Запускайте из каталога пакета: `cd packages/dart/codelab_acp_transports && fvm dart test test/web_safe_barrel_test.dart`.

### Сторож (`melos run guard`) ругается на `dart:io` в `lib/`

**Симптом.** Тест сторожа показывает нарушение правила пакета `packages/dart/codelab_acp_transports`.

**Причина.** `dart:io`, `package:web_socket_channel/io.dart` или импорт `io.dart` появились вне `lib/io.dart` и `lib/src/io/`. Основной барель должен собираться в web.

**Что сделать.** Перенесите файл в `lib/src/io/` и экспортируйте его из `lib/io.dart`. Если код нужен и в web, отделите чистую часть от части на `dart:io`.

## Нормы и спецификации

| Что | Где |
|---|---|
| порт, stdio, WebSocket, профиль `codelab-agent`, серверные транспорты, пара в памяти, ошибка запуска без аргументов, web-безопасный барель | `openspec/specs/agent-transports/spec.md` |
| как `AcpAgentServer` использует серверные транспорты | `openspec/specs/agent-acp-server/spec.md`, `openspec/specs/agent-binary/spec.md` |
| как клиент подключает транспорт и реагирует на сбои | `openspec/specs/acp-protocol-client/spec.md`, `openspec/specs/acp-client-kit/spec.md` |
| встроенный агент и `InProcessAcpLink` | `openspec/specs/embedded-agent/spec.md` |
| прогон корпуса ACP-фикстур через транспорты | `openspec/specs/acp-golden-fixtures/spec.md`, `openspec/specs/testing-quality/spec.md` |
| правила пакета | [`AGENTS.md`](../AGENTS.md); корневой `AGENTS.md`, §5, §7, §9, §10, §15, §16, §21 |
| граница ACP и ответственность транспортов | `docs/architecture/acp-boundary.md`, `docs/architecture/streaming.md`, `docs/architecture/concurrency.md`, `docs/architecture/session-lifecycle.md` |
| референс ACP про транспорты | `docs/protocols/acp/protocol/16-Transports.md` |

Соседние руководства: [`codelab_acp_protocol`](../../codelab_acp_protocol/doc/README.md) (типы и кодеки сообщений), [`codelab_acp_testing`](../../codelab_acp_testing/doc/README.md) (фикстуры и фейки), [`codelab_architecture_tests`](../../codelab_architecture_tests/doc/README.md) (сторож), [ядро агента](../../codelab_agent_core/doc/README.md) (то, что стоит за серверным транспортом).
