# 9.12. Этап 7 — Встроенный режим в обоих клиентах

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Accepted. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.11. Этап 6 — codelab_cli MVP](09-11-stage-6-cli-mvp.md) · [Оглавление](../dart-agent-and-clients.md) · [9.13. Этап 8 — MCP, конфигурация, AGENTS.md](09-13-stage-8-mcp-config.md) →

**Цель.** Агент работает внутри процесса codelab-app и codelab_cli через тот же ACP-код, что и
внешний: профиль «встроенный агент» в обоих клиентах, в CLI — по умолчанию.

**Задачи.**

1. **7.1. `InProcessAcpLink`** (пара `InProcessAcpTransport`) в `packages/dart/codelab_acp_transports/lib/src/in_process_acp_transport.dart`
   (правила — agent-core-architecture §13.11), экспорт из основного (платформенно-нейтрального)
   бареля. Тест `packages/dart/codelab_acp_transports/test/in_process_acp_transport_test.dart`.
   OpenSpec change `add-in-process-acp-transport`.
2. **7.2.** Заменить тестовую копию транспорта (`codelab_acp_testing/lib/src/in_process_acp_link.dart`)
   на `InProcessAcpLink` у всех потребителей — contract test этапа 4, агентский драйвер фикстур, тесты
   `codelab_agent_acp` и `apps/codelab_agent` — и удалить копию в том же PR (change
   `add-in-process-acp-transport`, D5).

   **Итог 7.1–7.2.** Сделано change `add-in-process-acp-transport` (итерация 1, PR #209):
   продуктовая пара `InProcessAcpLink` в `codelab_acp_transports` с копированием сообщений всегда
   (D9), экспорт из web-безопасного основного бареля; тестовая копия из `codelab_acp_testing`
   удалена, все потребители переведены (D5). Отметки DoD — ниже.
3. **7.3. Пакет `packages/dart/codelab_embedded`** (API ниже): `lib/codelab_embedded.dart`
   (нейтральная часть, `createEmbeddedAgent`), `lib/io.dart` (сервисы для десктопа).
4. **7.4. Профили хостов** `embedded-app-desktop` и `embedded-cli` в `buildAgentCore`
   (документ ядра §10); встроенный агент получает `services.baseEnv = LocalExecutionEnv`
   (agent-core-architecture §10.2) и исполняет файлы и команды локально, даже если клиент объявил
   `fs`/`terminal`.
5. **7.5. codelab-app:** `EmbeddedProfile` в диалоге подключения («Встроенный агент»),
   `EmbeddedTransportResolver` в composition root (`apps/codelab_desktop/lib/app/app_scope.dart`),
   выбор провайдера и модели из конфигурации; конфигурация — загрузчик задачи 8.5
   (`config_loader.dart`), ключ API — `SecretResolver` задачи 8.9 (переменная
   `CODELAB_SECRET_<…>` или, при явном `secrets.backend: file`, `$CODELAB_HOME/secrets.yaml`;
   хранилище ОС — после 1.0, change `add-agent-os-secret-backends`; §15 и §17.5.4 документа ядра). Это
   часть MVP. В 1.0 страница настроек и мастер (если сделаны) предлагают `file` или переменную, а не
   хранилище ОС; на Windows — только переменную.
   **Известное ограничение до 8.10** (change `add-agent-secret-store`, D3, D15): кэш найденных
   значений резолвера живёт до конца процесса. Ключ, заменённый `codelab secret set` или страницей
   настроек, работающий встроенный агент app или CLI увидит только после перезапуска, в том числе
   при записи через `SecretAdmin` в том же процессе; новый, ещё не прочитанный секрет подхватывается
   сразу. Сброс кэша (`SecretResolver.invalidate`) — вместе с перезагрузкой конфига в 8.10.
   **Should — не блокирует MVP:** пакет `codelab_setup` (§12.4.2), страница провайдеров app
   (D-05, §12.4.5), мастер и статус ключа (§12.4.4) — запись конфига идёт через `ConfigWriter`
   задачи 8.10, тоже Should. Без них встроенный профиль настраивается файлом `config.yaml` и
   `codelab secret set`.
6. **7.6. codelab_cli:** `--agent embedded` по умолчанию; тот же резолвер в
   `apps/codelab_cli/lib/src/composition_root.dart`; `codelab config check` показывает план
   сборки (что включено и почему выключено).
   **Решение пользователя 2026-11-02** (design.md change `add-embedded-agent-mode`, D13):
   без `--agent` используется профиль `default` из `profiles.json`, если он есть, иначе встроенный
   агент. Вне scope change `add-embedded-agent-mode`, отдельными change: план сборки в
   `codelab config check` (вывод обязан совпадать у CLI и `codelab-agent`, а план зависит от
   профиля хоста) и флаги CLI `--permission-mode`, `--config`, `--log-file` (таблица §9.11).
   До них работают `CODELAB_CONFIG`, `permissions.mode` конфига и `--approve`.
7. **7.7. Интеграционные тесты app в режиме `CODELAB_E2E_AGENT=embedded`:** поддержка
   `integration_test/support/e2e_agent.dart` создаёт `EmbeddedProfile` с провайдером
   `ProviderConfig.scripted(<скрипт>)`. Scripted-провайдер доступен только при
   `--dart-define=CODELAB_ALLOW_SCRIPTED_LLM=true`; в релизной сборке его нет. Так же устроено
   тестовое хранилище секретов: переменная `CODELAB_TEST_SECRET_STORE=<каталог>` действует только
   в сборке с `--dart-define=CODELAB_ALLOW_TEST_SECRETS=true` (только для тестов; §12.4.13,
   agent-core-architecture §15.6). Хранилище — бэкенд `file` задачи 8.9 с явным путём
   `<каталог>/secrets.yaml` (`FileSecretStore(path: …)`, `backend.id == "file"`; change
   `add-agent-secret-store`, D14). Переменную читает эта задача 7.7, в 8.9 она не читается. Имя
   `CODELAB_TEST_SECRET_STORE` известно загрузчику конфигурации только в сборке с
   `CODELAB_ALLOW_TEST_SECRETS` (задача 0.3 того же change, D14); в обычной сборке оно, как любая
   неизвестная `CODELAB_*`, даёт `config.env.unknown`. Сборку с флагом проверяет тоже 7.7.
8. **7.8. Замер нагрузки на UI:** `packages/dart/codelab_embedded/benchmark/stream_latency_benchmark.dart`
   — 10 000 чанков ответа через встроенного агента, измеряется задержка цикла событий. Это
   разведка (исключение (д) правила TDD §9.0 п.3): замер без тестов, ограничен двумя днями.
   Решение об isolate принимается в этой задаче по критериям ниже («Решение 7.8: ядро в
   isolate») и фиксируется в `design.md` change с числами замера.
   Замер идёт с копированием сообщений: выключателя копии у `InProcessAcpLink` нет (change
   `add-in-process-acp-transport`, D9). Если нужно сравнение без копии, параметр вводит change
   `add-embedded-agent-mode` с числами замера.
9. **7.9. E2E CLI во встроенном режиме:** те же `cli/*` с `--agent embedded` и scripted-провайдером;
   `codelab test-scenario packages/dart/codelab_acp_testing/fixtures/acp --agent embedded` — в CI-джобе
   `conformance`.

   **Итог 7.3–7.9.** Сделано change `add-embedded-agent-mode`, итерации 1–5
   ([design.md](../../../../openspec/changes/add-embedded-agent-mode/design.md), D12; отметки DoD — ниже):
   * **7.3** — пакет `packages/dart/codelab_embedded`, мост между сторонами без префикса стороны
     (ADR-0002): web-безопасный основной барель (`createEmbeddedAgent`), `io.dart` — настольный
     открыватель `localEmbeddedAgentOpener` (конфиг 8.5, секреты 8.9, журнал JSONL, MCP, файлы
     проекта), `testing.dart` — сценарный открыватель для тестов. Сторож, allowlist, HOST-6 и
     web-smoke — вместе с пакетом (D1–D3, D8).
   * **7.4** — профили `embedded-app-desktop` и `embedded-cli`; файлы и команды встроенный агент
     исполняет сам через `AcpServerConfig.localEnv` с containment `BoundedEnv` ядра (D4). Паритет
     профилей — тест ядра `codelab_agent_core/test/host/profile_event_parity_test.dart` (D1, в).
   * **7.5** — тип подключения «Встроенный агент» в codelab-app, резолвер
     `apps/codelab_desktop/lib/app/embedded_transport_resolver.dart` в composition root, таймаут
     закрытия 10 s (`embedded.close_timeout`), номер попытки подключения в `ClientWorkspace` против
     гонки повторного Connect (D6, D9). Should-часть (`codelab_setup` для мастера, D-05) — в change
     `add-provider-setup-ui`.
   * **7.6** — в CLI без `--agent` берётся профиль `default`, иначе встроенный агент (D13, п. 1);
     резолвер — `apps/codelab_cli/lib/src/embedded_transport_resolver.dart`, открыватель — из
     `composition_root.dart`; `--debug-secrets` (D13, п. 9). План сборки в `codelab config check` и
     флаги `--permission-mode`, `--config`, `--log-file` — вне scope (D13, пп. 5–6).
   * **7.7** — интеграционные тесты app с `CODELAB_E2E_AGENT=embedded` подают сценарий модели
     через шов `CodeLabBootstrap(scope:)` из `package:codelab_embedded/testing.dart`, без
     `--dart-define=CODELAB_ALLOW_SCRIPTED_LLM` (D8); скрипт `test:e2e:app:embedded` — в корневом
     `pubspec.yaml`, прогон на устройстве — в `release/<version>` (D10, D13, п. 4).
     `CODELAB_TEST_SECRET_STORE` действует только в сборке с `CODELAB_ALLOW_TEST_SECRETS` (D5).
   * **7.8** — замер выполнен, остаётся `InProcessAcpLink` (ниже, «Решение 7.8: ядро в isolate»);
     разбор журнала сессии — в `Isolate.run` (`JsonlSessionStore.open`).
   * **7.9** — `melos run test:e2e:cli:embedded` (CI-джоб `e2e-cli-embedded`) и
     `melos run conformance:embedded` (`codelab test-scenario … --agent embedded`, CI-джоб
     `conformance`) входят в `melos run check`.

**Артефакт: `InProcessAcpLink`** — пара `InProcessAcpTransport`, реализаций существующего интерфейса
`AcpTransport`. Код — `packages/dart/codelab_acp_transports/lib/src/in_process_acp_transport.dart`,
правила доставки, копирования и закрытия — одно место: agent-core-architecture §13.11
([`13-acp-adapter.md`](../agent-core/13-acp-adapter.md)); решения и альтернативы — design.md change
`add-in-process-acp-transport` (D2–D4). Отдельной копии кода здесь нет, чтобы копии не расходились.

Тесты транспорта (`in_process_acp_transport_test.dart`):
* порядок 1000 сообщений сохраняется, доставка не реентерабельна;
* сообщение до `start()` получателя или до первого подписчика его `inbound` буферизуется;
  после отписки всех подписчиков сообщения выбрасываются; невыданный буфер при закрытии второго
  конца выбрасывается с диагностикой `warning` и числом сообщений;
* `close()` одной стороны переводит другую в `failed` с `disconnected`; сообщения, отправленные до
  `close()`, доставляются раньше конца `inbound`; повторный `close()` идемпотентен;
* изменение `Map` после `send` не видно получателю, в том числе в `error.data`;
* `DateTime`, ключ не строкой, `NaN`, `±Infinity` и любая другая ошибка копирования в `params` дают
  `sendFailed` без значения в тексте;
* `send` до `start()` и после `close` — `sendFailed`.

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
/// LocalExecutionEnv, JsonlSessionStore в $CODELAB_HOME/sessions, секреты — SecretResolver из openHostSecrets
/// codelab_agent_io (8.9: те же бэкенды, что у CLI — в 1.0 env и file; change add-agent-secret-store, D15), MCP stdio (8.1–8.4).
/// Вызов: openHostSecrets(codelabHome: codelabHomeOf(Platform.environment), environment: Platform.environment,
/// backend: HostSettings.secretsBackend из loadEmbeddedAgentConfig (null → auto), debug: CODELAB_DEBUG_SECRETS=1
/// или опция хоста debugSecrets, logger); selectionReason не передаётся — он нужен только AgentHost со
/// сценарием (D11, D15). Ключа конфига для режима отладки нет.
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
`codelab_client_core`:

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

**Уточнения change `add-embedded-agent-mode`.** Эскиз выше написан до конфигурации 8.5. Действующий
API и решения — в [design.md change](../../../../openspec/changes/add-embedded-agent-mode/design.md):

* `EmbeddedAgentConfig` несёт `CoreConfig` и `HostSettings` загрузчика 8.5 (несколько провайдеров
  с маршрутизацией) вместо одного `ProviderConfig`, `fallbackModels` и `mcpServers` (D2).
* `loadEmbeddedAgentConfig` и `desktopHostServices` соединены в открыватель
  `localEmbeddedAgentOpener` из `io.dart`: оба клиента вызывают их подряд, а службам нужны
  `secretsBackend` и `sessions.dir` загруженного конфига (D2, D5). Резолвер клиента получает
  открыватель, а не фабрику сервисов. `EmbeddedAgent.plan` не публикуется до потребителя.
* `memoryHostServices` и `mobileHostServices` не создаются до этапа 10; основной барель остаётся
  web-безопасным (D2).
* Встроенные профили исполняют файлы и команды через `AcpServerConfig.localEnv`
  (agent-core-architecture §13.1): при `services.baseEnv = LocalExecutionEnv` сервер иначе отдал бы
  их клиенту через `fs/*` и `terminal/*` (D4).
* `dispose` запускается и при закрытии клиентского конца; ошибка агента перехватывается зоной
  и переводит клиентский транспорт в `failed` с `disconnected` (D6).
* Сценарий модели для тестов — `package:codelab_embedded/testing.dart`, который `lib/` клиентов
  не импортирует (сторож), вместо `--dart-define=CODELAB_ALLOW_SCRIPTED_LLM` и
  `ProviderConfig.scripted` (задача 7.7); разбор сценария переезжает из `apps/codelab_agent` в
  `codelab_agent_io` (D8).

**OpenSpec change.** `add-in-process-acp-transport` (задачи 7.1–7.2; scope: публичный API
`codelab_acp_transports`, правила копирования и закрытия; выполнен и архивирован —
[`archive/2026-11-01-add-in-process-acp-transport`](../../../../openspec/changes/archive/2026-11-01-add-in-process-acp-transport/)) и `add-embedded-agent-mode` (задачи 7.3–7.9;
scope: `codelab_embedded`, профили `embedded-*`, профиль подключения в app и CLI, scripted-провайдер
только для тестов; часть 7.5 про `codelab_setup` и D-05 — отдельный change
`add-provider-setup-ui`, Should; план сборки в `codelab config check` из 7.6 и флаги CLI
`--permission-mode`, `--config`, `--log-file` — вне scope, отдельные change, решение пользователя
2026-11-02). `tasks.md` — пары "тест → реализация" со ссылкой на критерий
(§9.0, правило 3); замер 7.8 — разведка без пары (исключение (д)).

**Решение 7.8: ядро в isolate.** Критерии (замер на эталонной машине, записанной в `design.md`):
p99 задержки цикла событий UI-isolate больше 8 мс или максимум больше 50 мс на 10 000 чанков —
ядро переносится в `IsolateAcpLink`; иначе остаётся `InProcessAcpLink`, а тяжёлые операции
(разбор журнала, сжатие) уходят в `Isolate.run` в любом случае. На web isolate нет — там всегда
`InProcessAcpLink`. *Уточнение change `add-embedded-agent-mode`:* выполнено для разбора журнала
(`JsonlSessionStore.open`); сжатие по D11 остаётся в главном isolate — оно ждёт ответа LLM, его
CPU-часть мала ([design.md change](../../../../openspec/changes/add-embedded-agent-mode/design.md), D11, «Разбор журнала»).

**Результат замера (задача 5.1 change `add-embedded-agent-mode`; решение пользователя 2026-11-02):
остаётся `InProcessAcpLink`, `IsolateAcpLink` не делается.** Числа, машина, режим сборки и
разбивка по слоям — [design.md change](../../../../openspec/changes/add-embedded-agent-mode/design.md), D11, «Решение 7.8». Кратко: критерии выполняются,
пока провайдер отдаёт не больше 7 SSE-событий на одно чтение сокета (задержка растёт ≈1 мс на
событие в пачке); больше половины стоимости чанка — клиентская проекция kit, которую isolate ядра
из UI-isolate не унёс бы. Разбор журнала при открытии сессии ушёл в `Isolate.run`. Остаточный риск
пачек от 8 событий и follow-up (PERF-1 — удешевить проекцию kit, PERF-2 — замерить реальный
размер пачки SSE) — [`docs/backlog/perf-2026-11-02-stream-latency.md`](../../../backlog/perf-2026-11-02-stream-latency.md). Эскиз ниже не
реализуется и сохранён на случай пересмотра решения по PERF-2.

Эскиз контракта на случай переноса:

```dart
// packages/dart/codelab_embedded/lib/src/isolate_acp_link.dart (только io.dart)
final class IsolateAcpLink {
  /// В isolate передаются только сериализуемые данные: конфиг как JSON и описание сервисов
  /// (codelabHome, hostProfile, secretsBackend, debugSecrets). http.Client, Logger и SecretResolver
  /// (openHostSecrets, change add-agent-secret-store, D15) создаются внутри isolate; значения секретов
  /// через SendPort не передаются. Замена прочитанного секрета видна только после перезапуска (до 8.10).
  static Future<IsolateAcpLink> spawn({required Map<String, Object?> configJson,
      required DesktopServicesSpec services});
  AcpTransport get client;                    // тот же контракт, что у InProcessAcpTransport
  Future<void> dispose({Duration grace = const Duration(seconds: 3)});
}
```

1. `spawn` вызывает `Isolate.spawn(_agentMain, boot)` с `SendPort` клиента и портами `onError`,
   `onExit`. Внутри isolate `_agentMain` вызывает `openHostSecrets` из полей `codelabHome`,
   `secretsBackend`, `debugSecrets` спецификации `DesktopServicesSpec` и `Platform.environment`
   (то же окружение процесса), собирает агента как `createEmbeddedAgent` поверх
   `InProcessAcpLink` и соединяет его клиентскую сторону с портом. Резолвер, его кэш и
   `SecretProcessRunner` живут только в isolate ядра (change `add-agent-secret-store`, D15).
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
   `grace` и падение isolate → `failed`; `melos run test:e2e:app:embedded` с isolate — в ветке
  `release/<version>` (`AGENTS.md` §21).

**Что прочитать.** Документ ядра §10, §13 (`shutdown`), §4 (выбор env); §4.5 и §6 этого документа;
`docs/architecture/concurrency.md` (isolate).

**Definition of Done.** Пункты 7.3–7.9 закрывает change `add-embedded-agent-mode`, итерация 6
(задача 6.3 `tasks.md`); результаты прогонов внесены по факту (2026-11-02).

* `fvm dart test packages/dart/codelab_acp_transports/test/in_process_acp_transport_test.dart` зелёный.
  **Выполнено** (7.1, change `add-in-process-acp-transport`, PR #209).
* Интеграционные тесты app для встроенного режима (таблица этапа 4) собираются:
  `fvm flutter analyze integration_test` в `apps/codelab_desktop`. **Выполнено** 2026-11-02
  на `develop` @ `8905dee`: код 0, «No issues found!».
  Прогон на устройстве `melos run test:e2e:app:embedded` — все применимые тесты
  зелёные — выполняется в ветке `release/<version>` (`AGENTS.md` §21; D13, п. 4).
* `codelab test-scenario packages/dart/codelab_acp_testing/fixtures/acp --agent embedded`
  (`melos run conformance:embedded`) — все `PASS` или `SKIP` с причиной (`setup.sessions`,
  `setup.config`, `setup.web`, `setup.mcp`, `setup.transport`, профиль вне `{agent-serve,
  embedded-cli}`; D8), без `FAIL`. **Выполнено** 2026-11-02 на `develop` @ `8905dee`: код 0,
  `37 passed, 0 failed, 19 skipped`; причины `SKIP`: `setup.config` (8), `setup.mcp` (7),
  `setup.transport` (2), `setup.sessions` (1), фикстура только с ролью `client` (1).
* `melos run guard` — правила D3: основной барель `codelab_embedded` не импортирует `dart:io`,
  `codelab_agent_io` и `codelab_client_*`; `io.dart` — только composition root клиентов,
  `testing.dart` — только `apps/codelab_cli/lib/src/scenario/` и тесты; app и CLI не импортируют
  `codelab_agent_*` напрямую; allowlist `codelab_embedded`, CLI и пакетов `codelab_*` app; HOST-6.
  **Выполнено** 2026-11-02: `melos run guard` — код 0, 100 тестов (с `desktopAllowlist`
  задачи 6.4).
* Замер 7.8 выполнен, решение об isolate записано в `design.md` с числами и критериями.
  **Выполнено** — [design.md change](../../../../openspec/changes/add-embedded-agent-mode/design.md), D11,
  «Решение 7.8»; остаётся `InProcessAcpLink`.
* Встроенный профиль в app и CLI берёт конфиг через загрузчик 8.5 и ключ через `SecretResolver`
  8.9. **Выполнено** — тесты задач 2.1 и 2.3 change `add-embedded-agent-mode`:
  `packages/dart/codelab_embedded/test/io/local_opener_test.dart` (ключ из `secrets.yaml` и
  `CODELAB_SECRET_*`, невалидный конфиг, нет конфигурации),
  `packages/dart/codelab_agent_io/test/secrets/host_secrets_test.dart` (`openHostSecrets(testStorePath:)`
  — `FileSecretStore`, `backend.id == "file"`) и
  `packages/dart/codelab_embedded/test/io/test_secret_store_process_test.dart`
  (`CODELAB_TEST_SECRET_STORE` только в сборке с `CODELAB_ALLOW_TEST_SECRETS`).
* Should (не блокирует MVP): `codelab_setup` для мастера, страница провайдеров app (D-05) и
  мастер — тесты §12.4.13 зелёные. **Перенесено** в будущий change `add-provider-setup-ui`
  (`delivery-roadmap.md`); этап 7 закрывается без него.

**Зависимости.** Этапы 6 и 8 (порядок D3: `{6, 8} → 7`): CLI-клиент этапа 6, загрузка
конфигурации 8.5 и хранилище секретов 8.9; через них — этапы 4 (агент) и 5 (kit для app). От
8.10 (запись конфига) зависит только Should-часть 7.5.

**Риски.** Тяжёлые операции ядра в UI-isolate (разбор журнала, сжатие) — разбор журнала в
`Isolate.run`; сжатие по D11 остаётся в главном isolate: оно ждёт ответа LLM, его CPU-часть мала
([design.md change](../../../../openspec/changes/add-embedded-agent-mode/design.md), D11). Замер 7.8 сжатие не измерял.
Пачки SSE от 8 событий на чтение дают задержку UI выше критерия — PERF-1 и PERF-2 в
[`docs/backlog/perf-2026-11-02-stream-latency.md`](../../../backlog/perf-2026-11-02-stream-latency.md). Общие изменяемые `Map` между сторонами —
глубокая копия по умолчанию.

---

← [9.11. Этап 6 — codelab_cli MVP](09-11-stage-6-cli-mvp.md) · [Оглавление](../dart-agent-and-clients.md) · [9.13. Этап 8 — MCP, конфигурация, AGENTS.md](09-13-stage-8-mcp-config.md) →
