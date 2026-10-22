# 9.12. Этап 7 — Встроенный режим в обоих клиентах

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Proposed. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.11. Этап 6 — codelab_cli MVP](09-11-stage-6-cli-mvp.md) · [Оглавление](../dart-agent-and-clients.md) · [9.13. Этап 8 — MCP, конфигурация, AGENTS.md](09-13-stage-8-mcp-config.md) →

**Цель.** Агент работает внутри процесса codelab-app и codelab_cli через тот же ACP-код, что и
внешний: профиль «встроенный агент» в обоих клиентах, в CLI — по умолчанию.

**Задачи.**

1. **7.1. `InProcessAcpLink`** (пара `InProcessAcpTransport`) в `packages/dart/acp_transports/lib/src/in_process_acp_transport.dart`
   (код ниже), экспорт из основного (платформенно-нейтрального) бареля. Тест
   `packages/dart/acp_transports/test/in_process_acp_transport_test.dart`.
2. **7.2.** Заменить тестовую копию транспорта в contract test этапа 4 на `InProcessAcpLink`.
3. **7.3. Пакет `packages/dart/codelab_embedded`** (API ниже): `lib/codelab_embedded.dart`
   (нейтральная часть, `createEmbeddedAgent`), `lib/io.dart` (сервисы для десктопа).
4. **7.4. Профили хостов** `embedded-app-desktop` и `embedded-cli` в `buildAgentCore`
   (документ ядра §10); встроенный агент получает `services.baseEnv = LocalExecutionEnv`
   (agent-core-architecture §10.2) и исполняет файлы и команды локально, даже если клиент объявил
   `fs`/`terminal`.
5. **7.5. codelab-app:** `EmbeddedProfile` в диалоге подключения («Встроенный агент»),
   `EmbeddedTransportResolver` в composition root (`apps/codelab_app/lib/app/app_scope.dart`),
   выбор провайдера и модели из конфигурации; конфигурация — загрузчик задачи 8.5
   (`config_loader.dart`), ключ API — `SecretResolver` задачи 8.9 (переменная
   `CODELAB_SECRET_<…>` или связка ключей ОС; §15 и §17.5.4 документа ядра). Это часть MVP.
   **Should — не блокирует MVP:** пакет `codelab_setup` (§12.4.2), страница провайдеров app
   (D-05, §12.4.5), мастер и статус ключа (§12.4.4) — запись конфига идёт через `ConfigWriter`
   задачи 8.10, тоже Should. Без них встроенный профиль настраивается файлом `config.yaml` и
   `codelab secret set`.
6. **7.6. codelab_cli:** `--agent embedded` по умолчанию; тот же резолвер в
   `apps/codelab_cli/lib/src/composition_root.dart`; `codelab config check` показывает план
   сборки (что включено и почему выключено).
7. **7.7. Интеграционные тесты app в режиме `CODELAB_E2E_AGENT=embedded`:** поддержка
   `integration_test/support/e2e_agent.dart` создаёт `EmbeddedProfile` с провайдером
   `ProviderConfig.scripted(<скрипт>)`. Scripted-провайдер доступен только при
   `--dart-define=CODELAB_ALLOW_SCRIPTED_LLM=true`; в релизной сборке его нет. Так же устроено
   тестовое хранилище секретов: переменная `CODELAB_TEST_SECRET_STORE=<каталог>` действует только
   в сборке с `--dart-define=CODELAB_ALLOW_TEST_SECRETS=true` (только для тестов; §12.4.13,
   agent-core-architecture §15.6).
8. **7.8. Замер нагрузки на UI:** `packages/dart/codelab_embedded/benchmark/stream_latency_benchmark.dart`
   — 10 000 чанков ответа через встроенного агента, измеряется задержка цикла событий. Это
   разведка (исключение (д) правила TDD §9.0 п.3): замер без тестов, ограничен двумя днями.
   Решение об isolate принимается в этой задаче по критериям ниже («Решение 7.8: ядро в
   isolate») и фиксируется в `design.md` change с числами замера.
9. **7.9. E2E CLI во встроенном режиме:** те же `cli/*` с `--agent embedded` и scripted-провайдером;
   `codelab test-scenario packages/dart/acp_testing/fixtures/acp --agent embedded` — в CI-джобе
   `conformance`.

**Артефакт: `InProcessAcpLink`** — пара `InProcessAcpTransport`, реализаций существующего интерфейса `AcpTransport`.

```dart
// packages/dart/acp_transports/lib/src/in_process_acp_transport.dart
import 'dart:async';
import 'package:acp_protocol/acp_protocol.dart';
import 'acp_transport.dart';

/// Пара соединённых транспортов: отправленное в один приходит в inbound другого.
/// `client` отдаётся AcpClientApplication, `agent` — AcpAgentServer.serve.
final class InProcessAcpLink {
  factory InProcessAcpLink({bool copyMessages = true}) {
    final client = InProcessAcpTransport._('client', copyMessages);
    final agent = InProcessAcpTransport._('agent', copyMessages);
    client._peer = agent;
    agent._peer = client;
    return InProcessAcpLink._(client, agent);
  }
  InProcessAcpLink._(this.client, this.agent);
  final InProcessAcpTransport client;
  final InProcessAcpTransport agent;
}

final class InProcessAcpTransport implements AcpTransport {
  InProcessAcpTransport._(this._side, this._copy);
  final String _side;
  final bool _copy;
  late final InProcessAcpTransport _peer;

  // Асинхронные контроллеры: доставка в следующей микрозадаче, порядок сохраняется,
  // отправитель не вызывает обработчики получателя реентерабельно.
  final _inbound = StreamController<JsonRpcMessage>.broadcast();
  final _events = StreamController<AcpTransportEvent>.broadcast();
  final _beforeStart = <JsonRpcMessage>[];  // агент может ответить раньше, чем клиент вызвал start()
  var _state = AcpTransportState.idle;

  @override Stream<JsonRpcMessage> get inbound => _inbound.stream;
  @override Stream<AcpTransportEvent> get events => _events.stream;
  @override AcpTransportState get state => _state;
  bool get _isDown => const {AcpTransportState.closing, AcpTransportState.closed, AcpTransportState.failed}.contains(_state);

  @override
  Future<void> start() async {
    if (_state == AcpTransportState.connected) return;
    if (_isDown) throw _error(AcpTransportErrorCode.closed, 'is closed');
    _setState(AcpTransportState.connecting);
    _setState(AcpTransportState.connected);
    _beforeStart..forEach(_inbound.add)..clear();
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    if (_state != AcpTransportState.connected) throw _error(AcpTransportErrorCode.sendFailed, 'is not connected');
    final JsonRpcMessage copy;
    try {
      copy = _copy ? _copyMessage(message) : message;
    } on ArgumentError catch (e) {             // как проводной транспорт с не-JSON значением
      throw _error(AcpTransportErrorCode.sendFailed, 'got a non-JSON value: ${e.message}');
    }
    _peer._deliver(copy);
  }

  void _deliver(JsonRpcMessage message) {
    if (_state == AcpTransportState.connected) {
      _inbound.add(message);
    } else if (!_isDown) {
      _beforeStart.add(message);
    } else {
      _events.add(const AcpTransportEvent.diagnostic(message: 'Dropped in-process message after close.',
          severity: AcpTransportDiagnosticSeverity.warning, source: 'in_process'));
    }
  }

  @override
  Future<void> close({Duration? timeout}) async {
    if (_state == AcpTransportState.closed || _state == AcpTransportState.closing) return;
    _setState(AcpTransportState.closing);
    _setState(AcpTransportState.closed);
    await _events.close();
    await _inbound.close();
    _peer._onPeerClosed();
  }

  void _onPeerClosed() {
    if (_isDown) return;
    _events.add(AcpTransportEvent.failure(_error(AcpTransportErrorCode.disconnected, 'peer closed the connection')));
    _setState(AcpTransportState.failed);
  }

  void _setState(AcpTransportState next) {
    _state = next;
    if (!_events.isClosed) _events.add(AcpTransportEvent.stateChanged(next));
  }

  AcpTransportException _error(AcpTransportErrorCode code, String text) =>
      AcpTransportException(code: code, message: 'In-process $_side transport $text.');
}

/// Глубокая копия JSON-дерева без строкового кодирования: стороны не делят изменяемые
/// Map/List, а не-JSON значения (DateTime, объекты домена) ловятся сразу, как на проводе.
JsonRpcMessage _copyMessage(JsonRpcMessage m) => switch (m) {
  JsonRpcRequest(:final id, :final method, :final params) =>
    JsonRpcMessage.request(id: id, method: method, params: _copyJson(params)),
  JsonRpcNotification(:final method, :final params) =>
    JsonRpcMessage.notification(method: method, params: _copyJson(params)),
  JsonRpcResponse(:final id, :final result, :final error) =>
    JsonRpcMessage.response(id: id, result: _copyJson(result), error: error),
};

Object? _copyJson(Object? v) => switch (v) {
  null || bool() || num() || String() => v,
  List() => List<Object?>.unmodifiable(v.map(_copyJson)),
  Map() => Map<String, Object?>.unmodifiable({
    for (final MapEntry(:key, :value) in v.entries)
      (key is String ? key : throw ArgumentError.value(key, 'key', 'must be a String')): _copyJson(value),
  }),
  _ => throw ArgumentError.value(v, 'value', 'not JSON-compatible'),
};
```

Тесты транспорта (`in_process_acp_transport_test.dart`): порядок 1000 сообщений сохраняется;
сообщение до `start()` получателя буферизуется; `close()` одной стороны переводит другую в
`failed` с `disconnected`; изменение `Map` после `send` не видно получателю; `DateTime` в
`params` даёт `sendFailed`; `send` после `close` — `sendFailed`.

**Артефакт: API `codelab_embedded`.**

```dart
// packages/dart/codelab_embedded/lib/codelab_embedded.dart — без dart:io, собирается для web
export 'package:codelab_agent_core/codelab_agent_core.dart'
    show ProviderConfig, ModelRef, AgentCoreServices, CorePlan, HostCapability;

final class EmbeddedAgentConfig {
  final String hostProfile;                  // embedded-app-desktop | embedded-cli | mobile | web
  final ProviderConfig provider;
  final List<ModelRef> fallbackModels;
  final String? defaultMode;
  final List<McpServerConfig> mcpServers;    // этап 8
}

abstract interface class EmbeddedAgent {
  AcpTransport get clientTransport;          // клиентская сторона InProcessAcpLink
  CorePlan get plan;                         // что включено и почему выключено
  /// Ожидающие разрешения → отказ, активный ход отменяется, журнал дописывается, транспорт закрывается.
  Future<void> dispose();
}

/// Единственная точка сборки встроенного агента для клиентов (HOST-6 документа ядра).
Future<EmbeddedAgent> createEmbeddedAgent({required EmbeddedAgentConfig config, required AgentCoreServices services});

/// MemoryExecutionEnv и MemorySessionStore: web и тесты (мобильные — mobileHostServices, §9.15).
AgentCoreServices memoryHostServices({required http.Client http, Logger? logger});

// packages/dart/codelab_embedded/lib/io.dart — десктоп и CLI; мобильные — с этапа 10
/// LocalExecutionEnv, JsonlSessionStore в $CODELAB_HOME/sessions, секреты — SecretResolver (8.9), MCP stdio (8.1–8.4).
Future<AgentCoreServices> desktopHostServices({String? codelabHome, http.Client? http, Logger? logger});
/// Этап 10 (§9.15): LocalExecutionEnv с корнем в папке документов приложения, без процессов (exec off),
/// JsonlSessionStore там же, MCP только по HTTP (agent-core-architecture §4, §10).
Future<AgentCoreServices> mobileHostServices({required String documentsDir, http.Client? http, Logger? logger});
/// Загрузка и валидация конфигурации поверх config_loader задачи 8.5 (документ ядра §15); ошибки — с путём ключа.
/// Ссылки на секреты разрешает SecretResolver задачи 8.9; своего загрузчика у codelab_embedded нет.
Future<EmbeddedAgentConfig> loadEmbeddedAgentConfig({required String cwd, required String hostProfile, String? configPath});
```

`createEmbeddedAgent` делает четыре шага:

1. `final core = buildAgentCore(profile: HostProfile.of(config.hostProfile), services: services, config: …)`
   — план сборки, env-цепочка, реестр инструментов, политика разрешений, `AgentRuntime`.
2. `final link = InProcessAcpLink();`
3. `AcpAgentServer(runtime: core.runtime, config: AcpServerConfig(…), logger: …, trace: …, clock: …)` (agent-core-architecture §13.1; env хоста задан на шаге 1 через `services.baseEnv = LocalExecutionEnv`, §10.2),
   `await link.agent.start()`, `unawaited(server.serve(link.agent))` (future завершается с закрытием соединения).
4. Возвращает `EmbeddedAgent` с `link.client`, `core.plan` и `dispose` = `server.shutdown()` +
   `link.agent.close()`.

Резолвер клиента — несколько строк в composition root, поэтому `codelab_embedded` не зависит от
`acp_client_kit`:

```dart
// После MVP (§12.6.7) реализует TerminatingTransportResolver: terminate = _running?.dispose().
final class EmbeddedTransportResolver implements TransportResolver {
  EmbeddedTransportResolver(this._services);
  final Future<AgentCoreServices> Function() _services;   // desktopHostServices, mobileHostServices или memoryHostServices
  EmbeddedAgent? _running;

  @override
  bool supports(ConnectionProfile profile) => profile is EmbeddedProfile;

  @override
  Future<AcpTransport> open(ConnectionProfile profile, {required String projectDirectory}) async {
    await _running?.dispose();
    final config = await loadEmbeddedAgentConfig(
        cwd: projectDirectory, hostProfile: (profile as EmbeddedProfile).hostProfile);
    final agent = _running = await createEmbeddedAgent(config: config, services: await _services());
    return agent.clientTransport;
  }
}
```

**OpenSpec change.** `add-in-process-acp-transport` (задачи 7.1–7.2; scope: публичный API
`acp_transports`, правила копирования и закрытия) и `add-embedded-agent-mode` (задачи 7.3–7.9;
scope: `codelab_embedded`, профили `embedded-*`, профиль подключения в app и CLI, scripted-провайдер
только для тестов; часть 7.5 про `codelab_setup` и D-05 — отдельный change
`add-provider-setup-ui`, Should). `tasks.md` — пары "тест → реализация" со ссылкой на критерий
(§9.0, правило 3); замер 7.8 — разведка без пары (исключение (д)).

**Решение 7.8: ядро в isolate.** Критерии (замер на эталонной машине, записанной в `design.md`):
p99 задержки цикла событий UI-isolate больше 8 мс или максимум больше 50 мс на 10 000 чанков —
ядро переносится в `IsolateAcpLink`; иначе остаётся `InProcessAcpLink`, а тяжёлые операции
(разбор журнала, сжатие) уходят в `Isolate.run` в любом случае. На web isolate нет — там всегда
`InProcessAcpLink`. Эскиз контракта на случай переноса:

```dart
// packages/dart/codelab_embedded/lib/src/isolate_acp_link.dart (только io.dart)
final class IsolateAcpLink {
  /// В isolate передаются только сериализуемые данные: конфиг как JSON и описание сервисов
  /// (codelabHome, hostProfile). http.Client, Logger и SecretResolver создаются внутри isolate.
  static Future<IsolateAcpLink> spawn({required Map<String, Object?> configJson,
      required DesktopServicesSpec services});
  AcpTransport get client;                    // тот же контракт, что у InProcessAcpTransport
  Future<void> dispose({Duration grace = const Duration(seconds: 3)});
}
```

1. `spawn` вызывает `Isolate.spawn(_agentMain, boot)` с `SendPort` клиента и портами `onError`,
   `onExit`. Внутри isolate `_agentMain` собирает агента как `createEmbeddedAgent` поверх
   `InProcessAcpLink` и соединяет его клиентскую сторону с портом.
2. Сообщения — конверты-Map: `{"k":"msg","m":<JSON-RPC>}`, `{"k":"log",…}`, `{"k":"close"}`,
   `{"k":"closed"}`, `{"k":"fatal","error":…}`. JSON-RPC кадр проходит те же правила
   `_copyJson`: не-JSON значение — `sendFailed` на отправляющей стороне. Порядок сохраняется
   (порт — очередь FIFO).
3. Отмена хода — обычное уведомление ACP `session/cancel` в конверте `msg`; отдельного канала
   нет, поэтому семантика отмены та же, что во встроенном режиме без isolate.
4. `close()`/`dispose()` клиента шлёт `close`; isolate вызывает `EmbeddedAgent.dispose`
   (ожидающие разрешения → отказ, журнал дописан) и отвечает `closed`. Нет ответа за `grace` —
   `Isolate.kill(priority: Isolate.immediate)`.
5. Падение isolate (`onError`, `onExit` без `closed`) переводит клиентский транспорт в `failed` с
   `disconnected` и пишет диагностику; kit показывает это как обрыв соединения (переподключение
   §9.10).
6. Тесты при переносе: те же случаи, что у `in_process_acp_transport_test.dart` (порядок 1000
   сообщений, `close` → `failed` у другой стороны, `DateTime` → `sendFailed`), плюс `kill` после
   `grace` и падение isolate → `failed`; `melos run test:e2e:app:embedded` с isolate.

**Что прочитать.** Документ ядра §10, §13 (`shutdown`), §4 (выбор env); §4.5 и §6 этого документа;
`docs/architecture/concurrency.md` (isolate).

**Definition of Done.**

* `fvm dart test packages/dart/acp_transports/test/in_process_acp_transport_test.dart` зелёный.
* `melos run test:e2e:app:embedded` — все применимые интеграционные тесты app (таблица этапа 4)
  зелёные во встроенном режиме.
* `codelab test-scenario packages/dart/acp_testing/fixtures/acp --agent embedded` — все `PASS`.
* `melos run guard`: основной барель `codelab_embedded` не импортирует `dart:io`; app и CLI не
  импортируют `codelab_agent_*` напрямую.
* Замер 7.8 выполнен, решение об isolate записано в `design.md` с числами и критериями.
* Встроенный профиль в app и CLI берёт конфиг через загрузчик 8.5 и ключ через `SecretResolver`
  8.9 (тест резолвера с `CODELAB_TEST_SECRET_STORE`).
* Если сделано (Should — не блокирует MVP): `codelab_setup`, страница провайдеров app (D-05) и
  мастер — тесты §12.4.13 зелёные.

**Зависимости.** Этапы 6 и 8 (порядок D3: `{6, 8} → 7`): CLI-клиент этапа 6, загрузка
конфигурации 8.5 и хранилище секретов 8.9; через них — этапы 4 (агент) и 5 (kit для app). От
8.10 (запись конфига) зависит только Should-часть 7.5.

**Риски.** Тяжёлые операции ядра в UI-isolate (разбор журнала, сжатие) — `Isolate.run` для
разбора и сжатия, при плохом замере — ядро в отдельном isolate. Общие изменяемые `Map` между
сторонами — глубокая копия по умолчанию.

---

← [9.11. Этап 6 — codelab_cli MVP](09-11-stage-6-cli-mvp.md) · [Оглавление](../dart-agent-and-clients.md) · [9.13. Этап 8 — MCP, конфигурация, AGENTS.md](09-13-stage-8-mcp-config.md) →
