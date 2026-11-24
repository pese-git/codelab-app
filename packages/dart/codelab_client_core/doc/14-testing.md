# Тестирование

Глава объясняет, как проверяется клиентский слой: что и на каком уровне тестируется, на чём стоит стенд тестов, как писать тест без живого агента и как задавать порядок событий без таймеров. Запуск тестов и общий состав проверок — в [главе 0](00-getting-started.md); уровни и виды тестов репозитория — [`docs/architecture/testing.md`](../../../../docs/architecture/testing.md).

## Что и где проверяется

Тесты лежат в `test/` по областям. Живого агента, сети и процессов у них нет: «агента» играет тест.

| Каталог | Что проверяет |
|---|---|
| `workspace/` | автомат соединения, `ensureAgent`, вытеснение попыток, потеря соединения, повтор хода |
| `sessions/` | `session/list`, `session/load`, сессии после переподключения |
| `queue/` | очередь промптов, отмена, независимость очередей сессий |
| `transcript/` | проекция ленты, заметки, дерево вызовов потомков, строка инструмента, одобрение в элементе |
| `approvals/` | критичный запрос, ожидания, одобрения субагентов, снятие одобрений при смене соединения |
| `session/` | опции, план, поля задач, строки субагентов |
| `commands/` | каталог команд палитры |
| `restore/` | снимок и восстановление |
| `usage/` | декодер, свёртка, журнал, бюджет, форматирование, корпус фикстур |
| `protocol/` | буфер кадров и режим Trace |
| `connection/` | профили, черновик, ссылки на токен, запись профиля, резолвер, отказ по токену |
| `diagnostics/`, `inspector/` | диагностика без секретов, проекция инспектора |
| `stores/`, `files/`, `themes/` | чистые правила хранилищ, папки проекта и тем |
| `support/` | общие обвязки (ниже) |

Виды тестов:

- **Сценарные** — рабочее пространство на `FakeAcpTransport`, тест играет агента: подключиться, открыть сессию, отправить промпт, прислать обновление, проверить `SessionView`. Большинство тестов слоя.
- **Чистые** — функции без рабочего пространства: `UsageDecoder`, `UsageFold`, `ThemeFile.parse`, `normalizeRelativePath`, `ProfileDraft.validate`, `CommandCatalog`. Самые быстрые и самые подробные.
- **Свойства на корпусе фикстур** — один и тот же сценарий прогоняется на каждой фикстуре golden-корпуса ACP (ниже).
- **Контрактные** — один набор проверок для порта на двойнике: `theme_library_contract_test.dart` для `ThemeLibrary`.

Вне этого пакета границы слоя проверяет сторож `codelab_architecture_tests` (`melos run guard`): импорты и список зависимостей; поведение через оболочки проверяют характеризационные тесты `apps/codelab_desktop/.../shell_cubit_characterization/` и e2e CLI (`test:e2e:cli:*`).

## Стенд: `FakeAcpTransport`

`FakeAcpTransport` из [`codelab_acp_testing`](../../codelab_acp_testing/README.md) — транспорт, который тест держит в руках:

- сам отвечает на `initialize`, объявляя то, что задано в `initializeAgentCapabilities`: `loadSession`, `sessionCapabilities.list`, `_meta.codelab.usage` и так далее;
- `sent` — broadcast-поток всего, что клиент отправил; `sentMessages` — список;
- `emitInbound(message)` — сообщение «от агента»: ответ, `session/update`, запрос;
- `fail(AcpTransportException)` — оборвать соединение;
- `failNextSend(error)` — следующая отправка упадёт.

Два нюанса, о которых забывают:

- `sent` — broadcast: подписаться нужно **до** действия. Поэтому обвязки сначала берут `next(метод)`, потом вызывают действие, потом ждут запрос.
- Future потокового `elementAt` завершается синхронно внутри `add` транспорта. Без прыжка в микрозадачу (`await Future<void>.value()`) вызывающий продолжил бы внутри доставки события, и следующая его отправка упала бы с «Cannot fire new event» (комментарий в `GatedWorkspace.nextRequest`).

## Обвязки `test/support/`

| Обвязка | Для чего |
|---|---|
| `KitAgent` | основная: `ClientWorkspace` поверх `FakeAcpTransport` с диагностикой; `start`, `newSession`, `prompt`, `next`, `nextResponse`, `respond`, `fail`, `update`, `requestPermission`, `restartAgent`, `dispose` |
| `GatedWorkspace`, `GatedResolver` | порядок завершений `open` задаёт тест: `resolver.next()` заводит вентиль-`Completer`; `requests(method)` и `nextRequest(method, on)` читают запросы на конкретном транспорте |
| `UsageAgent`, `RecordingLogger` | рабочее пространство с журналом kit; `usage(params)`, `usageParams(...)`, `usageCapabilities` |
| `FakeProfileSecrets`, `FakeProfileStore`, `CallLog` | двойники хранилищ с общим журналом вызовов: порядок «секрет, затем профиль» проверяется без таймеров |

`KitAgent.restartAgent` подменяет транспорт, который резолвер отдаст следующему `reconnect`: прежний ядро клиента закрывает при замене и повторно не открывает. `KitAgent.start` принимает `sessions` — ответ на `session/list`, который слой отправляет сразу после `initialize` агенту со списком, и `projectDirectory`.

### Порядок событий без таймеров

Гонки (AGENTS.md §9; [`concurrency.md`](../../../../docs/architecture/concurrency.md)) проверяются принудительным порядком, а не паузами. Правила тестов слоя:

- порядок завершений задаёт `Completer` (`GatedResolver.next()`), а не `Future.delayed`;
- единственные таймеры — страховка от зависания красного теста: `GatedWorkspace.nextRequest` падает с `TestFailure` через 3 с, если запрос так и не пришёл; порядок событий этот таймер не определяет;
- «ничего не произошло» проверяется состоянием (`workspace.current`, `sentMessages`), а не ожиданием.

### Скелет: сценарный тест

Этот тест на `KitAgent` проверяет очередь: промпт в занятую сессию ждёт, затем уходит сам. Сохраните как `test/scratch/queue_skeleton_test.dart` (временный файл, не коммитьте):

```dart
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

void main() {
  late KitAgent agent;

  setUp(() async {
    agent = KitAgent();
    await agent.start();
  });
  tearDown(() => agent.dispose());

  test('a prompt sent to a busy session waits in the queue', () async {
    final session = await agent.newSession('s-1');
    final first = await agent.prompt(session, 'first');

    final outcome = await session.send('second');

    expect(outcome, isA<PromptQueued>());
    expect(session.current.queue.map((item) => item.text), ['second']);

    final next = agent.next(sessionPromptMethod);
    agent.respond(first.request, {'stopReason': 'end_turn'});
    agent.respond(await next, {'stopReason': 'end_turn'});
    await first.done;
    expect(session.current.queue, isEmpty);
    expect(session.current.status, SessionStatusView.idle);
  });
}
```

Запуск: `fvm dart test test/scratch/queue_skeleton_test.dart`. Скелет проверен: `+1: All tests passed!`.

### Скелет: порядок завершений

Тест на `GatedWorkspace` проверяет, что поздний результат вытесненной попытки подключения ничего не меняет (спецификация, «Явный автомат соединения», «Поздний успех устаревшей попытки»):

```dart
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/gated_workspace.dart';

void main() {
  late GatedWorkspace gw;

  setUp(() => gw = GatedWorkspace());
  tearDown(() => gw.dispose());

  test('a late result of a superseded connect changes nothing', () async {
    final slow = gw.resolver.next(); // open первой попытки
    final fast = gw.resolver.next(); // open второй попытки
    final lateTransport = gw.resolver.transport();
    final freshTransport = gw.resolver.transport();

    final first = gw.workspace.connect(gatedProfile, projectDirectory: '/a');
    final second = gw.workspace.connect(gatedProfile, projectDirectory: '/b');

    fast.complete(freshTransport);
    await second;
    expect(gw.workspace.current.connection, isA<Connected>());

    slow.complete(lateTransport); // попытка 1 приходит позже и устарела
    await first; // завершается без ошибки

    expect(gw.workspace.current.connection, isA<Connected>());
    expect(gw.workspace.current.agentDirectory, '/b');
    expect(gw.resolver.directories, ['/a', '/b']);
  });
}
```

Скелет проверен: `+1: All tests passed!`. Вентили выдаются по порядку вызовов `open`; без заведённого вентиля `open` возвращает свежий транспорт.

## Подмена порта: фейк `AgentBackend`

Когда нужны только кадры или состояния, а ACP-клиент не нужен, тест подставляет фейк порта. Пример — `_FakeBackend` в `test/protocol/protocol_frame_log_test.dart`: он реализует входящие потоки и `traceAvailable`, `setFrameTrace`, `generation`, а остальные члены через `noSuchMethod` бросает при случайном обращении.

```dart
final class FakeBackend implements AgentBackend {
  final _states = StreamController<ClientConnectionState>.broadcast();
  final _sessions = StreamController<AcpSession>.broadcast();
  final _usage = StreamController<UsageNotification>.broadcast();
  final _frames = StreamController<ProtocolFrame>.broadcast();

  @override
  Stream<ClientConnectionState> get connectionStates => _states.stream;
  @override
  Stream<AcpSession> get sessionChanges => _sessions.stream;
  @override
  Stream<UsageNotification> get usageNotifications => _usage.stream;
  @override
  Stream<ProtocolFrame> get protocolFrames => _frames.stream;
  @override
  bool get traceAvailable => false;
  @override
  int get generation => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
```

Скелет компилируется (`dart analyze`: без замечаний, при импортах `dart:async`, `codelab_client_acp` и `codelab_client_core`). Новый член порта `AgentBackend` обязателен для любого такого фейка: добавляя член, проверьте `_FakeBackend` и `FakeFrameBackend` в `apps/codelab_desktop/test/support/fake_protocol_workspace.dart` (`AGENTS.md` пакета, §3).

## Корпус фикстур

Golden-корпус ACP — каталог JSON-фикстур `packages/dart/codelab_acp_testing/fixtures/acp/`; каждая описывает обмен клиента и агента. Драйвер `runClientFixture` проигрывает фикстуру на клиенте, а `ClientFixtureUser` выполняет шаги пользователя. Слой использует корпус двумя способами:

- **Свойство проекции** (`transcript_projector_test.dart`): на каждом изменении сессии `TranscriptProjector.items` равно `projectTranscript(session)`. Фикстуры без роли клиента пропускаются (`markTestSkipped`) — это и есть `~37` в сводке.
- **Usage на корпусе** (`usage_fixture_test.dart`): `SessionView.usage` и заметка бюджета проверяются на фикстурах расхода. Драйвер сам падает на любом кадре клиента, которого нет в фикстуре: так проверяется «клиент не отвечает на уведомления». Прогон протокольного клиента на корпусе — `melos run conformance:client` — относится к `codelab_client_acp`, а не к слою.

Добавлять данные в корпус — задача `codelab_acp_testing` и спецификации [`acp-golden-fixtures`](../../../../openspec/specs/acp-golden-fixtures/spec.md), не слоя.

## Правила тестов слоя

- Подписки и рабочее пространство закрываются в `tearDown`: `dispose` рабочего пространства, затем `application.dispose()` (бэкенд слой не закрывает).
- Не использовать реальные таймеры и сеть. Нужен порядок — вентиль `Completer`.
- Секреты в тестах вымышленные (`s3cr3t` в `config_transport_resolver_test.dart`); проверка «значение не попало в журнал» делается на таком значении.
- Поведение app на время переноса логики защищают характеризационные тесты desktop; их текст меняется только явно, с обоснованием в `design.md` change.
- Заголовки тестовых файлов с пометкой «Красные тесты» в ряде файлов устарели: тесты давно зелёные. Не опирайтесь на такие комментарии, а правьте их при изменении файла.
