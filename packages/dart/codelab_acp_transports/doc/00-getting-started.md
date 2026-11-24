# Начало работы

Глава для того, кто впервые открыл пакет: как подготовить репозиторий, запустить анализ и тесты, посмотреть работу транспорта своими глазами и найти причину сбоя. Устройство транспортов — в [главе 01](01-design.md).

## Подготовка

Пакет — чистый Dart. Ему нужен FVM-SDK из `.fvmrc` и сгенерированный код `*.freezed.dart`: в git он не хранится, а в `lib/` лежат freezed-модели `AcpTransportEvent`, `AcpTransportException` и конфигурации. Шаги подготовки одни для всего репозитория — [`docs/user/run-from-source.md`](../../../../docs/user/run-from-source.md):

```bash
fvm install
fvm flutter pub get
fvm dart run melos bootstrap
fvm dart run melos exec -c 1 --depends-on=build_runner -- "fvm dart run build_runner build --delete-conflicting-outputs"
```

Тесты пакета подключают `codelab_acp_testing`, а тот зависит от `codelab_client_acp`. Если у них нет `*.freezed.dart`, `fvm dart test` не соберёт ни один тестовый файл, где есть этот импорт, и покажет ошибки компиляции в `state_machines.freezed.dart`. Общая команда генерации выше создаёт код для всех пакетов сразу.

## Анализ и тесты

Из каталога пакета:

```bash
cd packages/dart/codelab_acp_transports
fvm dart analyze
fvm dart test
```

`dart analyze` на чистой ветке печатает `No issues found!`. Полный прогон — 71 тест в восьми файлах, около десяти секунд. Вывод заканчивается строкой `All tests passed!`.

Часть тестов запускает настоящие процессы и сокеты. Остальные работают в памяти.

| Файл | Что нужно ему от окружения |
|---|---|
| `test/in_process_acp_transport_test.dart` | ничего: пара в памяти |
| `test/web_safe_barrel_test.dart` | читает файлы `lib/` по относительному пути, поэтому запускается из каталога пакета |
| `test/stdio_server_transport_test.dart` | ничего: вход и выход подменены потоками в памяти |
| `test/codelab_acp_transports_test.dart` | дочерний процесс `dart` (агент-сценарий из `codelab_acp_testing`) и `HttpServer` на loopback |
| `test/websocket_handshake_rejection_test.dart`, `test/websocket_server_transport_test.dart` | `HttpServer` на `127.0.0.1`, порт выбирает ОС |
| `test/stdio_acp_transport_start_failure_test.dart` | запуск несуществующего `/nonexistent/agent` |
| `test/io/stdio_acp_transport_close_test.dart` | процессы `sh` с `trap` и `kill -0`: тест только для POSIX |

Нужен один файл или один тест:

```bash
fvm dart test test/io/stdio_acp_transport_close_test.dart
fvm dart test test/stdio_server_transport_test.dart --name "unparsable JSON"
```

(`--name` принимает часть названия теста.) Сторонних адресов тесты не трогают: сокеты открываются только на `127.0.0.1`, токены в них выдуманные.

## Проверки репозитория

Правка пакета запускает те же проверки, что и любая правка общего слоя (`AGENTS.md` репозитория, §21):

| Команда (из корня) | Когда |
|---|---|
| `fvm dart run melos run guard` | менялись импорты, `pubspec.yaml` или правила сторожа; правило пакета — `packages/dart/codelab_architecture_tests/test/support/rules.dart` |
| `fvm dart run melos run web-compile` | менялся основной барель или то, что он импортирует |
| `fvm dart run melos run conformance:client`, `conformance:agent` | менялись транспорты или кадрирование: корпус ACP-фикстур идёт через них |
| `fvm dart run melos run conformance:embedded`, `test:e2e:cli:embedded` | менялась пара в памяти |

`web-compile` не собирает `codelab_acp_transports` отдельно. Он компилирует точки входа `codelab_agent_core`, `codelab_embedded` и `codelab_setup` (`pubspec.yaml` репозитория, скрипт `web-compile`) в JavaScript и WebAssembly. Основной барель транспортов проверяется через `codelab_embedded`, который его импортирует (`packages/dart/codelab_embedded/lib/src/assemble.dart`). Прямые проверки web-безопасности — сторож и `test/web_safe_barrel_test.dart`. Скрипты `web-compile` и `conformance:*` долгие; для небольшой правки хватает `dart test` пакета и `guard`.

## Посмотреть, как работает транспорт

Лучший способ понять транспорт — подписаться на `events` и сломать его. Этот скрипт печатает всё, что публикует транспорт; он собран на `io.dart`, поэтому запускается из каталога пакета (например, как временный файл `tmp_probe.dart`; не коммитьте его):

```dart
import 'dart:async';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_acp_transports/io.dart';

void watch(String name, AcpTransport t) {
  t.events.listen((e) => print('[$name] ${switch (e) {
    AcpTransportStateChanged(:final state) => 'state -> ${state.name}',
    AcpTransportDiagnostic(:final message, :final severity, :final source) =>
      'diagnostic($severity, $source): $message',
    AcpTransportFailure(:final error) =>
      'failure ${error.code.name}: ${error.message} cause=${error.cause}',
  }}'));
}

Future<void> main() async {
  final t = StdioAcpTransport(
    const StdioAcpTransportConfig(command: 'sh', args: ['-c', 'sleep 0.2; exit 3']),
  );
  watch('stdio', t);
  await t.start();
  await Future<void>.delayed(const Duration(milliseconds: 600));
  await t.close();
}
```

```bash
fvm dart run tmp_probe.dart
```

```text
[stdio] state -> connecting
[stdio] state -> connected
[stdio] state -> failed
[stdio] failure disconnected: Stdio ACP agent exited unexpectedly with code 3. cause=null
[stdio] state -> closing
[stdio] state -> closed
```

Вывод получен запуском этого скрипта. Три факта видны сразу: состояния приходят событиями `stateChanged`; неожиданный выход процесса — это `failed` и событие `failure` с кодом `disconnected`; код выхода лежит только в тексте сообщения. После сбоя транспорт всё равно нужно закрыть: `close()` переводит его `failed → closing → closed`.

Тот же приём для остальных сценариев. Вывод вторичных строк опущен до значимого (порт в сообщении об отказе заменён на `<port>`):

| Сценарий | Что печатает `events`, что бросает `start()` |
|---|---|
| `StdioAcpTransport` с `command: '/nonexistent/agent'` | `failure startFailed: Failed to start stdio ACP agent. cause=ProcessException: No such file or directory`; `start()` бросает `ProcessException` без аргументов команды |
| агент `sh -c 'echo log-line >&2; echo not-json'` | `diagnostic(info, stderr): log-line`, затем `failure protocolViolation: Agent wrote invalid ACP JSON-RPC to stdout.` |
| `WebSocketAcpTransport` на `ws://127.0.0.1:9/acp` | `failure startFailed … cause=SocketException: Connection refused …, port = <port>`; `start()` бросает `SocketException` |
| то же, токен с переводом строки (`abc\nSECRET`) | `failure startFailed: Invalid header value for Authorization.`, `cause=null`; `start()` бросает `AcpTransportException(startFailed)`, значения токена нет нигде |
| `HttpServer` отвечает на рукопожатие 401 | `failure startFailed … cause=AcpWebSocketHandshakeRejected(statusCode: 401)`; `start()` бросает `AcpWebSocketHandshakeRejected` |
| `start()` после `close()` | `AcpTransportException(closed): WebSocket ACP transport is closed.` |

Все строки — реальный вывод этих сценариев. Они показывают общее правило: события `failure` всегда несут `AcpTransportException`, а исключение из `start()` у `StdioAcpTransport` и `WebSocketAcpTransport` может быть исходным (`ProcessException`, `SocketException`, `AcpWebSocketHandshakeRejected`) — подробности в [главе 01](01-design.md#ошибки-start-исходное-исключение-и-событие).

## Отладка

- **Что транспорт знает о себе** — только `state`, `events` и исключения. Логгера у пакета нет: `print` запрещён, а `AcpClientApplication` сам переводит события транспорта в свою диагностику (`DiagnosticSeverity`). Чтобы разобраться, подпишитесь на `events`, как выше.
- **stderr агента** приходит событием `diagnostic` с `source: 'stderr'` и уровнем `info`. В `inbound` он не попадает. Хост агента (`codelab-agent serve --stdio`) обязан писать логи только в stderr: любая не-JSON-RPC строка в stdout — `protocolViolation` для клиента.
- **Плохие кадры на стороне агента** — событие `diagnostic` с `severity: warning`, `source: 'stdin'` (stdio) или `'websocket'`, текст `Rejected an ACP frame: <причина>`. Транспорт при этом сам отвечает клиенту ошибкой JSON-RPC.
- **Что реально ушло по проводу** — смотрите журнал соединения вызвавшего слоя (`codelab_client_core`, диагностика клиента) и [`docs/architecture/observability.md`](../../../../docs/architecture/observability.md). Транспорт полезную нагрузку не логирует: в ней бывают пути и содержимое файлов (`AGENTS.md` репозитория, §16).
- **Сообщение потерялось, а ошибки нет.** Клиентские транспорты (`StdioAcpTransport`, `WebSocketAcpTransport`) выдают `inbound` через broadcast-контроллер: сообщение, пришедшее до первого `listen`, пропадает. Подписывайтесь на `inbound` до `start()`. У серверных транспортов и пары в памяти буфер до первой подписки есть ([глава 01](01-design.md#кто-что-буферизует)).

## Куда смотреть

| Что нужно | Файл |
|---|---|
| порт `AcpTransport`, состояния, события, ошибки | `lib/src/acp_transport.dart` |
| конфигурации и `codelabAgentStdioProfile` | `lib/src/transport_configs.dart` |
| пара в памяти | `lib/src/in_process_acp_transport.dart` |
| клиентский stdio: запуск, эскалация закрытия | `lib/src/io/stdio_acp_transport.dart` |
| клиентский WebSocket: заголовки, отказ рукопожатия | `lib/src/io/websocket_acp_transport.dart` |
| серверные stdio и WebSocket | `lib/src/io/stdio_server_acp_transport.dart`, `lib/src/io/websocket_server_acp_transport.dart` |
| разбор сырого кадра на стороне агента | `lib/src/io/server_frames.dart` |
| состав бареля | `lib/codelab_acp_transports.dart`, `lib/io.dart` |
| правило сторожа | `packages/dart/codelab_architecture_tests/test/support/rules.dart` (запись `packages/dart/codelab_acp_transports`) |

Дальше: [устройство транспортов](01-design.md), [тестирование, рецепт нового транспорта и частые проблемы](02-extending-and-troubleshooting.md).
