# Тестирование, расширение и частые проблемы

Глава собирает практику: как проверять ядро клиента, как добавить новое поведение и что делать, когда что-то не работает. Устройство описано в главах [01](01-overview.md), [02](02-connection-and-turns.md) и [03](03-agent-requests-fs-terminal.md); здесь они только упоминаются.

## Как тестируется пакет

Все тесты идут на Dart VM, без сети, настоящих процессов и файловой системы. Сеть, файлы и процессы заменяют двойники из [`codelab_acp_testing`](../../codelab_acp_testing/README.md) (в `dev_dependencies`).

| Уровень | Что проверяет | Файлы |
|---|---|---|
| Автоматы | чистые функции переходов: соединение, сессия, ход, реплей истории, идемпотентность | `test/state_machines_test.dart` |
| Ядро на `FakeAcpTransport` | методы `AcpClientApplication`, сценарии, потоки | `test/application_use_cases_test.dart`, `test/codelab_client_acp_test.dart` |
| Жизненный цикл и гонки | вытеснение попытки, снятие одобрений, таймауты, прерванный ход, закрытие | `test/application/*.dart` |
| Порты `fs/*` и `terminal/*` | containment, ошибки, процессы | `test/fs_access_test.dart`, `test/terminal_access_test.dart`, `test/application/terminal_stale_response_test.dart` |
| Неизвестные данные | незнакомый вид `session/update`, неизвестный вид вызова, неизвестный запрос агента | `test/unsupported_session_updates_test.dart`, `test/unknown_tool_kind_test.dart`, `test/unsupported_agent_requests_test.dart` |
| Наблюдаемость и секреты | кадры, политика payload, журнал, маскирование | `test/protocol_frame_test.dart`, `test/payload_policy_diagnostics_test.dart`, `test/structured_logging_test.dart`, `test/secret_redaction_test.dart` |
| Золотые фикстуры | клиент против корпуса ACP-обменов | `test/fixtures/client_fixture_conformance_test.dart` |

Общие правила тестов — в [`docs/architecture/testing.md`](../../../../docs/architecture/testing.md), правила пакета — в [`AGENTS.md`](../AGENTS.md) §4. Главное: красный тест на `FakeAcpTransport` пишется до кода; гонки проверяются заданным порядком событий через `Completer`, а не через `Future.delayed` с таймингом.

### Двойники из `codelab_acp_testing`

`FakeAcpTransport` — транспорт в памяти. Его контроллеры синхронные: `emitInbound(message)` доставляет кадр ядру сразу, внутри вызова. Обработчики `fs/*` и `terminal/*` асинхронные, поэтому после `emitInbound` тест даёт им один оборот цикла событий.

| Член | Для чего |
|---|---|
| `emitInbound(message)` | кадр «от агента» |
| `sentMessages`, `drainSentMessages()` | кадры, которые отправило ядро; `drain` ещё и очищает список |
| `sent` | поток отправленных кадров |
| `fail(error)`, `failNextSend(error)` | отказ транспорта; ошибка следующей отправки |
| `emitDiagnostic(...)`, `emitEvent(...)` | события транспорта |
| `autoRespondToInitialize`, `initializeProtocolVersion`, `initializeAgentCapabilities`, `initializeAgentInfo` | ответ на `initialize` и его параметры; без них `connect` каждого теста пришлось бы отыгрывать вручную |

`FakeTerminalProcessRunner` записывает старты (`started`, `handles`), `nextStartFailure` имитирует отказ запуска. У `FakeTerminalProcessHandle` тест сам задаёт вывод (`appendOutput`) и завершение (`exit(exitCode:, signal:)`), а `killCallCount` показывает вызовы `kill()`.

### Шаблон теста клиента

Шаблон ниже подключает ядро к `FakeAcpTransport`, открывает сессию и проводит один ход. Он собран по образцу тестов пакета и проверен прогоном.

```dart
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;

  setUp(() async {
    transport = FakeAcpTransport();
    // Конструктору нужен какой-то транспорт; настоящий приходит в connect.
    client = AcpClientApplication(transport: FakeAcpTransport());
    await client.connect(transport);
    transport.drainSentMessages(); // убрать кадр initialize
  });

  tearDown(() async {
    await client.dispose();
  });

  Future<AcpSession> newSession() async {
    final future = client.createSession(
      const CreateSessionCommand(cwd: '/work/demo'),
    );
    await pump();
    final request = transport.drainSentMessages().single as JsonRpcRequest;
    transport.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: const NewSessionResponse(
          sessionId: SessionId('session-1'),
        ).toJson(),
      ),
    );
    return future;
  }

  test('ответ агента завершает ход', () async {
    final session = await newSession();
    final turn = client.sendPrompt(
      SendPromptCommand(
        sessionId: session.id,
        prompt: [const ContentBlock.text(text: 'привет')],
      ),
    );
    await pump();
    final prompt = transport.drainSentMessages().single as JsonRpcRequest;
    expect(prompt.method, sessionPromptMethod);

    transport.emitInbound(
      JsonRpcMessage.response(
        id: prompt.id,
        result: const PromptResponse(stopReason: StopReason.endTurn).toJson(),
      ),
    );

    expect((await turn).status, PromptTurnStatus.completed);
    expect(
      client.sessionById(session.id)!.status,
      SessionLifecycleStatus.active,
    );
  });
}
```

Что здесь устроено не очевидно:

- В конструктор и в `connect` передаются разные объекты. `connect` закрывает прежний транспорт ядра; если это тот же объект, он закроется до запуска (см. [частые проблемы](#частые-проблемы)).
- `pump()` — один оборот цикла событий. Кадр запроса уходит транспорту после `await` внутри ядра, поэтому читать `sentMessages` сразу после вызова метода нельзя.
- `createSession` не проверяет состояние соединения. Тесты, которым `initialize` не нужен, просто вызывают `await transport.start()` и создают ядро с этим транспортом (так делают `fs_access_test.dart` и `terminal_access_test.dart`). Методы, которым нужен `ready` (`listSessions`, `requestUsageLedger`), требуют `connect`.
- `tearDown` вызывает `dispose`: он закрывает потоки и завершает процессы.
- Если тест настраивал журнал через `configureCodeLabLogging`, в `tearDown` нужен `StructlogConfiguration.reset()` из `package:structured_log/structured_log.dart`: настройка глобальная.

### Тест с заданным порядком событий

Тест ниже проверяет поведение «ответ на `terminal/wait_for_exit` не уходит в новое соединение». Порядок событий задан последовательностью вызовов: сессия создана, процесс создан, обработчик ждёт выхода, затем `reconnect` завершает процессы старого соединения и тем самым будит ожидание. Таймеров нет. Тест самодостаточен (проверен прогоном); `pump` — из шаблона выше.

```dart
test('ответ wait_for_exit не уходит в новое соединение', () async {
  final transport = FakeAcpTransport();
  final runner = FakeTerminalProcessRunner();
  final client = AcpClientApplication(
    transport: FakeAcpTransport(),
    terminalProcessRunner: runner,
  );
  addTearDown(client.dispose);
  await client.connect(transport);

  // Сессия нужна: terminal/* для неизвестной сессии отклоняется.
  final created = client.createSession(
    const CreateSessionCommand(cwd: '/work/demo'),
  );
  await pump();
  final newRequest = transport.sentMessages.last as JsonRpcRequest;
  transport.emitInbound(
    JsonRpcMessage.response(
      id: newRequest.id,
      result: const NewSessionResponse(
        sessionId: SessionId('session-1'),
      ).toJson(),
    ),
  );
  await created;

  transport.emitInbound(
    JsonRpcMessage.request(
      id: const JsonRpcId.integer(11),
      method: terminalCreateMethod,
      params: const CreateTerminalRequest(
        sessionId: SessionId('session-1'),
        command: 'sleep',
      ).toJson(),
    ),
  );
  await pump();
  transport.emitInbound(
    JsonRpcMessage.request(
      id: const JsonRpcId.integer(12),
      method: terminalWaitForExitMethod,
      params: const WaitForTerminalExitRequest(
        sessionId: SessionId('session-1'),
        terminalId: TerminalId('term-11'),
      ).toJson(),
    ),
  );
  await pump(); // обработчик ждёт выхода процесса

  final fresh = FakeAcpTransport();
  // reconnect завершает процессы старого соединения: ожидание закончится.
  await client.reconnect(ReconnectCommand(transportFactory: () => fresh));
  await pump();

  expect(runner.handles.single.killCallCount, 1);
  expect(fresh.sentMessages.whereType<JsonRpcResponse>(), isEmpty);
});
```

Идентификатор `term-11` берётся из `id` запроса `terminal/create` ([глава 03](03-agent-requests-fs-terminal.md#реестр-процессов)).

## Золотые фикстуры и `conformance:client`

Золотая фикстура — JSON-файл со сценарием обмена: кадры `c2a` (клиент → агент) и `a2c` (агент → клиент). Корпус лежит в `packages/dart/codelab_acp_testing/fixtures/acp/`, формат и список матчеров описывает [README `codelab_acp_testing`](../../codelab_acp_testing/README.md#golden-фикстуры).

Тест `client_fixture_conformance_test.dart` проигрывает каждую фикстуру с ролью `client` так:

1. `runClientFixture` играет агента: отправляет кадры `a2c` через `FakeAcpTransport` и сравнивает с ожидаемыми кадры клиента (`c2a`).
2. Действие пользователя, которое должно породить очередной `c2a`, выполняет `ClientFixtureUser.act`: для `initialize` это `connect`, для `session/new` — `createSession`, для `session/prompt` — `sendPrompt`, дальше `session/load`, `session/cancel`, `session/set_config_option`, `_codelab/session/usage/ledger` и ответ на запрос разрешения (`respondToPermission`).
3. На кадры агента `fs/*` и `terminal/*` клиент отвечает сам, через порты окружения фикстуры: ответ сравнивается с ожидаемым.
4. После сценария таблица `_stateChecks` проверяет итоговое состояние (`PromptTurnStatus`, статус вызова, число одобрений и т. п.) по `id` фикстуры.

Если у новой фикстуры нет записи в `_stateChecks`, тест падает с сообщением `add a state check for` и `id` фикстуры. Фикстуры, у которых в `roles` нет `client`, тест пропускает с пометкой «has roles [agent] without "client"». Это не ошибка: так выглядят `~37` в [выводе тестов](00-getting-started.md#тесты-пакета).

```bash
fvm dart run melos run conformance:client
```

С переменной `CODELAB_TEST_REPORT_DIR` скрипт дополнительно пишет отчёт `dart/codelab_client_acp.conformance.json`. Как добавить фикстуру, описано в [README `codelab_acp_testing`](../../codelab_acp_testing/README.md#как-добавить-фикстуру). Тот же корпус играют агент (`conformance:agent`) и встроенный агент в CLI (`conformance:embedded`): фикстура проверяет обе стороны протокола, и менять её надо осторожно.

Для проверки через настоящий клиентский слой CLI подходит `codelab test-scenario` (пример — [в главе 00](00-getting-started.md#сценарий-через-cli)).

## Рецепты расширения

### Рецепт: новый вид `session/update`

Задача: агент присылает вид обновления, которого клиент пока не знает. Если ничего не делать, обновление пропускается (запись `debug` «Skipped unsupported ACP session update.»), а состояние не меняется.

1. **Протокол.** Добавьте вариант в `SessionUpdate`, `knownKinds`, `fromJson` и `toJson` в [`codelab_acp_protocol`](../../codelab_acp_protocol/README.md). Вид должен быть в схеме ACP (`docs/protocols/acp/protocol/17-Schema.md`): придумывать виды запрещено ([`AGENTS.md`](../../../../AGENTS.md) §3.4). Если вида в схеме нет, остановитесь и предложите OpenSpec change.
2. **Решите, чьё это состояние.**
   - *Сессии* (команды, режим, опции, заголовок): добавьте ветку в `_applySessionScopedUpdate` (`domain/state_machines.dart`) и поле в `AcpSession` (`domain/domain_models.dart`, затем перегенерация freezed). Реплей `session/load` пользуется тем же методом.
   - *Хода, снимок* (как `plan`): дополнительного кода не нужно. Ветка по умолчанию в `_applyUpdateToTurn` дописывает обновление в `PromptTurn.updates`, а дубль определяется по последнему обновлению того же вида.
   - *Хода, приращение* (как чанк): добавьте вариант в ветку чанков в `_applyUpdateToTurn`. Иначе два одинаковых по тексту приращения подряд будут приняты за дубль.
   - *Вызова инструмента*: нужна запись в `ToolCallRecord` и слияние в `_mergeToolCallUpdate`. Берите за образец `outcome` и `parentToolCallId`.
3. **Тесты.** Тест автомата в `test/state_machines_test.dart`, тест ядра в `test/application/`, фикстура в корпусе и запись в `_stateChecks`. Тест «незнакомый вид пропускается» в `test/unsupported_session_updates_test.dart` используйте для проверки, что новый вид больше не пропускается.
4. **Документы.** Обновите таблицу видов в [главе 02](02-connection-and-turns.md#что-делает-ядро-с-sessionupdate).

Образец ветки сессионного уровня, из `_applySessionScopedUpdate`:

```dart
SessionInfoUpdate(:final title) => session.copyWith(
  title: title ?? session.title,
),
```

Хосты с исчерпывающим `switch` по `SessionUpdate` получат ошибку компиляции после шага 1: это подсказка, где ещё нужны изменения.

Образец теста идемпотентности снимка (проверен прогоном; замените `plan` на новый вид):

```dart
test('снимок: повтор игнорируется, возврат A, B, A применяется', () {
  const a = SessionUpdate.plan(entries: []);
  const b = SessionUpdate.plan(
    entries: [
      PlanEntry(
        content: 'шаг',
        priority: PlanEntryPriority.medium,
        status: PlanEntryStatus.pending,
      ),
    ],
  );
  var session = AcpSession(
    id: const SessionId('s'),
    cwd: '/work/demo',
    status: SessionLifecycleStatus.active,
  );
  final turn = PromptTurn(
    id: const PromptTurnId('t'),
    sessionId: session.id,
    prompt: const [],
  );
  session = SessionStateMachine.startTurn(session, turn).stateOrThrow;

  final first = SessionStateMachine.applyUpdate(session, a);
  expect(first, isA<AppliedStateTransition<AcpSession>>());
  final again = SessionStateMachine.applyUpdate(first.stateOrThrow, a);
  expect(again, isA<IgnoredStateTransition<AcpSession>>());

  var s = SessionStateMachine.applyUpdate(first.stateOrThrow, b).stateOrThrow;
  s = SessionStateMachine.applyUpdate(s, a).stateOrThrow;
  expect(s.activeTurn!.updates, [a, b, a]);
});
```

### Рецепт: принять новый запрос агента к клиенту

Задача: ACP получил новый метод «агент → клиент», который должен выполнять клиент. Образцы: `fs/read_text_file` (файл) и `terminal/*` (процесс с состоянием).

1. **Протокол.** Метод должен быть в схеме ACP. Добавьте DTO запроса и ответа, константу метода и запись в реестр `acpMethodRegistry` в [`codelab_acp_protocol`](../../codelab_acp_protocol/README.md).
2. **Порт.** Если метод трогает файлы, процессы или сеть, опишите порт в `domain/` (`abstract interface class` и типизированные отказы по образцу `FsAccessFailure`). `dart:io` в пакете запрещён; реализацию пишите в [`codelab_client_io`](../../codelab_client_io/doc/README.md).
3. **Конструктор и возможность.** Добавьте необязательный параметр порта в `AcpClientApplication` и объявите возможность в `initialize` (`_establishConnection`) только если порт передан. Объявлять то, чего клиент не умеет, нельзя.
4. **Диспетчер и обработчик.** Добавьте ветку `JsonRpcRequest(method: ...)` в `_handleInboundMessage` и обработчик. Структура по образцу `_handleReadTextFileRequest`:
   - порт не передан: `-32603` «… is not supported by this client.»;
   - разобрать параметры (`decodeAcpRequestParams`);
   - найти сессию, иначе `-32602` «Unknown session»;
   - для каждого `path` и `cwd` вызвать `resolveWithinWorkingDirectory` до порта;
   - вызвать порт, ответить `encodeAcpResponse` через `_sendTracedMessage`;
   - перехватить типизированные отказы порта и ответить через `_sendAcpMethodError` (`resourceNotFound`, `internalError`, `invalidAcpParams`);
   - последний `catch` на любое исключение: диагностика `error` и `-32603`.
5. **Состояние и гонки.** Если метод создаёт ресурс (как процесс), заведите реестр по паре (сессия, идентификатор), завершайте ресурсы в `_killAllTerminalProcesses`-подобном методе при `disconnected`, `failed` и `dispose`, а ответ отправляйте через проверку поколения (как `_sendTerminalResponse`).
6. **Тесты.** Шаблон теста обработчика (проверен прогоном) — ниже. Для ресурсов добавьте тест устаревшего ответа и теста `dispose`.
7. **Документы.** Таблицы в [главе 03](03-agent-requests-fs-terminal.md#какие-методы-принимает-ядро) и в README пакета; спецификации `acp-*-client`.

Каркас теста обработчика, с портом файлов в памяти из [следующего рецепта](#рецепт-порт-файлов-в-памяти); замените метод и DTO:

```dart
test('fs/read_text_file: файл внутри папки читается через порт', () async {
  files.files['/work/demo/a.txt'] = 'привет';

  transport.emitInbound(
    JsonRpcMessage.request(
      id: const JsonRpcId.integer(5),
      method: fsReadTextFileMethod,
      params: const ReadTextFileRequest(
        sessionId: SessionId('session-1'),
        path: '/work/demo/a.txt',
      ).toJson(),
    ),
  );
  await pump();

  final response = transport.drainSentMessages().single as JsonRpcResponse;
  expect(response.id, const JsonRpcId.integer(5));
  expect(ReadTextFileResponse.fromJson(response.result).content, 'привет');
});

test('fs/read_text_file: путь снаружи отклоняется', () async {
  transport.emitInbound(
    JsonRpcMessage.request(
      id: const JsonRpcId.integer(6),
      method: fsReadTextFileMethod,
      params: const ReadTextFileRequest(
        sessionId: SessionId('session-1'),
        path: '/etc/passwd',
      ).toJson(),
    ),
  );
  await pump();

  final response = transport.drainSentMessages().single as JsonRpcResponse;
  expect(response.error!.code, jsonRpcInvalidParamsCode);
});
```

В `setUp` такого теста ядро создаётся с портами: `AcpClientApplication(transport: FakeAcpTransport(), textFileReader: files, textFileWriter: files, terminalProcessRunner: runner)`, затем `connect(transport)` и открытие сессии с `cwd` `/work/demo`, как в шаблоне выше.

### Рецепт: порт файлов в памяти

Задача: хосту без `dart:io` (web, тесты) нужны порты `TextFileReader` и `TextFileWriter`. Адаптер хранит файлы в `Map`, а нет файла — бросает `FsNotFoundFailure`, чтобы агент получил `-32002`.

```dart
import 'package:codelab_client_acp/codelab_client_acp.dart';

final class MemoryTextFiles implements TextFileReader, TextFileWriter {
  final files = <String, String>{};

  @override
  Future<String> readText({required String path, int? line, int? limit}) async {
    final text = files[path];
    if (text == null) {
      throw FsNotFoundFailure(path);
    }
    if (line == null && limit == null) {
      return text;
    }
    final lines = text.split('\n');
    final start = ((line ?? 1) - 1).clamp(0, lines.length);
    final end = limit == null
        ? lines.length
        : (start + limit).clamp(start, lines.length);
    return lines.sublist(start, end).join('\n');
  }

  @override
  Future<void> writeText({required String path, required String content}) async {
    files[path] = content;
  }
}
```

Путь приходит уже нормализованным и проверенным по рабочей папке, повторять проверку адаптеру не нужно. `line` в ACP — номер строки с единицы, как и в адаптере `IoTextFileIo`.

### Рецепт: данные расширения `_meta.codelab`

Задача: агент CodeLab кладёт в `_meta.codelab` новое поле (признак вызова или хода), а клиент должен его учитывать. Требование: терпимый разбор, неверная форма — это отсутствие данных, а не ошибка (forward compatibility, [`AGENTS.md`](../../../../AGENTS.md) §7).

1. **Разбор.** Добавьте функцию рядом с `subagentMetaOf`, `outcomeOf`, `parentToolCallIdOf` в `domain/domain_models.dart`:

   ```dart
   String? flavorOf(Map<String, Object?>? meta) {
     final codelab = meta?['codelab'];
     final flavor = codelab is Map ? codelab['flavor'] : null;
     return flavor is String && flavor.isNotEmpty ? flavor : null;
   }
   ```

   Тест проверяет четыре случая: `null`, не-`Map`, неверный тип, нормальное значение (проверен прогоном):

   ```dart
   test('flavorOf терпим к неверной форме', () {
     expect(flavorOf(null), isNull);
     expect(flavorOf({'codelab': 'x'}), isNull);
     expect(flavorOf({'codelab': {'flavor': 3}}), isNull);
     expect(flavorOf({'codelab': {'flavor': 'a'}}), 'a');
   });
   ```

2. **Поле.** Добавьте поле в `ToolCallRecord` (или другой доменный тип), перегенерируйте freezed.
3. **Слияние.** Добавьте его в `ToolCallRecord.fromToolCall`, `_mergeToolCallUpdate` и `_withKnownCodelabMeta` (`state_machines.dart`). Правило слияния — продумайте и зафиксируйте тестом: у `outcome` поздний кадр без поля не стирает прежнее, а `completed` снимает; у `parentToolCallId` поздний кадр не стирает родителя.
4. **Объявление.** Если агент присылает данные только объявившему клиенту, добавьте ключ в `codelabClientExtensionsMeta` (`domain/codelab_extensions.dart`). Это меняет кадр `initialize`: обновите тест `initialize_codelab_request_test.dart` и фикстуру `acp/initialize-codelab-extensions`.

### Рецепт: новый вариант сбоя хода

Задача: сбой `session/prompt` нужно различать у потребителей. Добавьте именованный конструктор в `PromptFailure` (`domain/prompt_failure.dart`), разбор в `PromptFailure.fromJsonRpcError`, если вариант приходит от агента, и ветку в `_promptFailureOf` (в конце `acp_client_application.dart`). Потребители с исчерпывающим `switch` по `PromptFailure` (например, в `codelab_client_core`) получат ошибку компиляции; поправьте их в том же изменении. Тест — `test/application/prompt_failure_test.dart`.

## Частые проблемы

| Симптом | Причина | Что сделать |
|---|---|---|
| `connect` бросает `AcpClientApplicationException` «Failed to connect ACP transport», состояние `failed` | В `connect` передан тот же объект, что в конструкторе: `connect` сначала закрывает прежний транспорт. Либо транспорт не запускается (`cause` — `AcpTransportException`) | Передавайте разные объекты (`AcpClientApplication(transport: placeholder)`, затем `connect(real)`). Смотрите `cause` исключения и запись `connection_state_changed` в журнале |
| `StateTransitionException`: «operation is stale: ACP transport was reconnected…» | Параллельный `connect` или `reconnect` вытеснил эту операцию | Это штатный исход вытесненной попытки; хосту достаточно отбросить результат. Источник — сравнение поколений ([глава 02](02-connection-and-turns.md#поколение-соединения)) |
| `ready` не наступает, агент молчит | `initialize` ждёт ответа до `requestTimeout` (60 с), затем `failed` с причиной `protocolViolation` | Проверьте, что агент жив и пишет в тот же транспорт |
| `AcpRequestTimeoutException` | Агент не ответил за `requestTimeout`; `session/prompt` не снимается по таймеру | Для `session/prompt` прервите ход `session/cancel`. Поздний ответ на снятый запрос игнорируется и пишет `response_ignored` в журнал |
| `StateTransitionException`: «session already has an active prompt turn» | Предыдущий ход не завершён: идёт, ждёт одобрения или отменяется | Дождитесь ответа на предыдущий `session/prompt`; в `cancellingTurn` новый ход начать нельзя, пока агент не ответит на отменённый |
| После `reconnect` ход остаётся `running` | Ответ на старый запрос уже не придёт, а ядро не помечает ход `failed` из-за смены поколения | Загрузите сессию `loadSession`: последний ход реплея будет показан `cancelled` |
| `StateTransitionException`: «permission request is not pending» | Одобрение уже решено, снято обрывом или заменой транспорта, либо `approvalId` чужой | Берите `approvalId` из актуального `AcpSession`; после `reconnect` одобрения заново придут от агента |
| `StateTransitionException`: «permission option is not available for this request» | `optionId` не из `ApprovalRequest.options` | Выбирайте идентификатор из списка запроса |
| Агент получил `-32602`, файл не прочитан | `path` или `cwd` вне рабочей папки сессии | В журнале `warning` «Rejected fs/read_text_file outside working directory.» Проверьте `cwd` в `CreateSessionCommand`/`LoadSessionCommand` и путь, который шлёт агент |
| Агент получил `-32603` «… is not supported by this client.» | Порт не передан ядру | Передайте `textFileReader`, `textFileWriter` или `terminalProcessRunner` в конструктор. Без порта `initialize` честно объявляет возможность `false` |
| Агент получил `-32603` «path must be a non-empty absolute path» | Агент прислал относительный путь | Путь должен быть абсолютным (`09-File System.md`); исправляйте на стороне агента |
| Агент получил `-32601` | Метод не обрабатывается клиентом | Если метод нужен — [рецепт](#рецепт-принять-новый-запрос-агента-к-клиенту); `_codelab/*`-расширения клиент от агента не принимает как запросы |
| «Unknown terminal» | Идентификатор освобождён (`terminal/release`), принадлежит другой сессии либо реестр очищен обрывом или `reconnect` | Агент должен создавать терминал заново; идентификаторы живут не дольше соединения |
| `emitInbound` в тесте бросает `AcpTransportException` «closed» | Транспорт закрыт: `connect` или `reconnect` закрыл прежний | Отправляйте кадры в актуальный транспорт, а не в тот, что был до замены |
| Обновление `session/update` «пропало» | Незнакомый вид (запись `debug`), неизвестная сессия вне `session/new`, терминальный ход или сессия без активного хода | Ищите в журнале `Skipped unsupported ACP session update.` и `event_ignored`. Сессионные обновления (команды, режим, опции, заголовок) применяются без хода |
| Текст в чанках повторяется | Чанки сознательно не дедуплицируются: у них нет ключа | Проверьте, не доставляет ли транспорт кадр дважды и не пришёл ли реплей `session/load` в уже заполненную сессию |
| В stdout сыплются JSON-строки | Логгер по умолчанию — `StructuredLogLogger` без настройки пишет в stdout | Передайте свой `Logger` или вызовите `configureCodeLabLogging` ([глава 00](00-getting-started.md#отладка)) |
| `protocolFrames` пуст или без `payload` | Подписка оформлена после `connect` (поток broadcast без повтора) либо политика `metadataOnly` | Подпишитесь до `connect`; для payload выберите `ProtocolPayloadPolicy.full` или включите `setFrameTrace(true)` |
| Вызов получил риск `unknown` | Вид `other`, отсутствует или незнаком, `switchMode` | Это защитный результат `ApprovalPolicy`; решение остаётся за пользователем |
| Тест фикстуры падает «add a state check for …» | У новой фикстуры нет записи в `_stateChecks` | Добавьте проверку итогового состояния в `client_fixture_conformance_test.dart` |
| Ошибки «Undefined class» вокруг `$…` или `_$…` в моделях | Не сгенерирован `*.freezed.dart` | Выполните `build_runner` в каталоге пакета ([глава 00](00-getting-started.md#подготовка-репозитория)) |

## Что читать дальше

- [README пакета](../README.md) — публичное API и схема зависимостей.
- [`AGENTS.md`](../AGENTS.md) — правила пакета и проверки перед pull request.
- [`codelab_client_core`](../../codelab_client_core/doc/README.md) — что собирает поверх ядра общий клиентский слой.
- [Руководство `codelab`](../../../../apps/codelab_cli/doc/02-startup-and-composition.md) — как CLI создаёт ядро и порты.
