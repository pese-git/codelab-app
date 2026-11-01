## Context

**Что есть в коде (`origin/develop` @ 2b8ad73):**
- **Транспорт.** `InProcessAcpLink` в основном web-безопасном бареле `codelab_acp_transports` (change `add-in-process-acp-transport`):
  - копия сообщений всегда (D9 того change);
  - закрытие одного конца переводит другой в `failed` с `disconnected`.
- **Хост бинаря.** `apps/codelab_agent/lib/src/host/agent_host.dart` (`AgentHost.build`) — единственный хост ядра. Он собирает:
  - каталог моделей `StaticModelCatalog` и `createRoutedStreamFunction` по провайдерам `CoreConfig`;
  - `SecretResolver` через `openHostSecrets`;
  - `JsonlSessionStore` в `$CODELAB_HOME/sessions`, `LocalExecutionEnv`, `ProjectFilesLoader`;
  - `McpClientConnector` (stdio из `codelab_agent_io`, streamable HTTP из `codelab_agent_mcp`);
  - `buildAgentCore`, затем `AcpAgentServer`.

  Сценарий `--llm-script` (`llm_script.dart`, `_withScriptedProviders` в `serve_config.dart`) живёт в приложении, поэтому пакеты взять его не могут.
- **Профили.** `HostProfile.of` знает `agent-serve` и `embedded-cli`; `embedded-app-desktop` нет.
- **Сервер.** `AcpAgentServer._wire` всегда ставит сессии env `AcpClientExecutionEnv`: файлы и команды идут через `fs/*` и `terminal/*` клиента, листинг — через `localListing`, если он есть. Встроенный профиль §10.4 так не работает: `shellExec` у него — transport `local`.
- **Клиенты:**
  - `ConnectionProfile` (`codelab_client_core`) — закрытая иерархия `StdioProfile | WebSocketProfile`;
  - `ConfigTransportResolver` переводит её в конфигурации транспортов;
  - `JsonFileProfileStore` (`codelab_client_io`) хранит `profiles.json` CLI;
  - CLI: `resolveAgentProfile` даёт `UsageError` на `embedded`, без `--agent` берёт профиль `default`; `ScenarioAgent` (`lib/src/scenario/agent_connector.dart`) поддерживает только stdio и ws;
  - desktop: форма подключения `ConnectionCubit` с `CodeLabTransportType {stdio, webSocket}`, резолвер в `app/app_scope.dart` (CherryPick); `CodeLabBootstrap` принимает готовый `Scope` — это шов интеграционных тестов.
- **Секреты.** `openHostSecrets` (D15 change `add-agent-secret-store`) — общая фабрика настольных хостов:
  - `CODELAB_TEST_SECRET_STORE` загрузчик знает только в сборке с `-DCODELAB_ALLOW_TEST_SECRETS=true`;
  - читать переменную по плану должна задача 7.7.
- **Сторож.** В `rules.dart` оставлены комментарии `stage 7: codelab_embedded …`; HOST-6 проверяется только для `apps/codelab_agent`.

**Ограничения:**
- ACP не придумывается (`AGENTS.md` §3.4);
- клиенты не импортируют `package:codelab_agent_*` (`AGENTS.md` §5); мост между сторонами — без префикса `codelab_agent_` (ADR-0002);
- ядро без `dart:io`, PKG-2 не расширяется;
- permission flow не обходится (`AGENTS.md` §2, §10);
- device-прогоны — только в `release/*` (`AGENTS.md` §21);
- пропорциональность (`AGENTS.md` §13): без пустых слоёв и абстракций «на вырост».

## Goals / Non-Goals

**Goals:**
- `codelab -a embedded -p hi` и тип подключения «Embedded agent» в app проводят ход встроенного агента. ACP-код тот же, что у `codelab-agent serve --stdio`: сервер, kit, одобрения.
- Встроенный агент берёт конфиг загрузчиком 8.5 и ключ через `SecretResolver` 8.9. Значения секретов не попадают в логи, ошибки и состояние клиента.
- `dispose` и отказ агента наблюдаемы и детерминированы: журнал дописан, разрешения отклонены, kit видит обрыв.
- Сторож закрепляет границы с первой итерации: web-безопасный основной барель, HOST-6, позиции импорта `io.dart` и `testing.dart` в клиентах.
- Решение об isolate принимается по числам замера.

**Non-Goals:** — см. proposal, «Не входит».

## Decisions

### D1. Пакет `codelab_embedded`: место, имя, исполнитель

**Решение.** Пакет называется `packages/dart/codelab_embedded`. Это мост между сторонами: клиенты получают через него агента, не импортируя `package:codelab_agent_*`. Поэтому префикса стороны у имени нет (ADR-0002), как у `codelab_setup`. Пакет — хост ядра (`agent-core-architecture` §10.1): он зовёт `buildAgentCore` и `AcpAgentServer` и не содержит клиентской логики. От `codelab_client_*` он не зависит.

**Исполнитель** — `[agent]` (`agent-core-engineer`): весь код пакета — сборка агентской стороны. Таблица зон в `CLAUDE.md` и описание агента в `.claude/agents/` пакета пока не знают. Их дополняет задача документов этого change; правка вне `openspec/` и `docs/` — по согласованию с пользователем.

**Резолвер транспорта** (`EmbeddedTransportResolver`) живёт в composition root каждого клиента, как в эскизе §9.12, а не в пакете: иначе `codelab_embedded` зависел бы от `codelab_client_core`. Резолвер — около 30 строк: ожидание `dispose` прежнего агента, вызов «открывателя», `dispose` всего при закрытии хоста. Повтор в двух приложениях дешевле нового ребра между сторонами, а одинаковость резолверов проверяют тесты каждого клиента.

**Альтернативы:**
- (а) `codelab_agent_embedded` — отклонено ADR-0002: мост со стороной `agent` сторож разрешил бы клиентам по ошибке;
- (б) резолвер в `codelab_client_io` — отклонено: его allowlist без агентских пакетов (PKG-4);
- (в) общий хост `codelab_agent_host` для бинаря и встроенного режима — отклонено как лишний пакет. Сборка в обоих хостах — это вызовы готовых API на 60–80 строк, а расхождение ловит тест паритета профилей (§10.12, задача 2.8). Вынесено только то, что действительно дублировалось бы логикой: сценарий модели (D8).

### D2. Точки входа и публичный API

API в `09-12-stage-7-embedded.md` написан до 8.5: один `ProviderConfig`, `fallbackModels`, `mcpServers`. Конфиг 8.5 — это `CoreConfig` с несколькими провайдерами и маршрутизацией (D11 change `add-agent-configuration`) плюс `HostSettings`. Поэтому API уточняется; эскиз плана помечен ссылкой на это решение (задача 0.2).

**Основной барель `lib/codelab_embedded.dart`** — без `dart:io`, `dart:isolate` и `codelab_agent_io`, собирается для web:

```dart
/// Конфигурация встроенного агента: результат загрузчика 8.5 и профиль хоста.
final class EmbeddedAgentConfig {
  final String hostProfile;          // embedded-app-desktop | embedded-cli (mobile, web — этап 10)
  final CoreConfig core;             // провайдеры, модель по умолчанию, MCP, permissions.mode, …
  final HostSettings host;           // secretsBackend, sessionsDir, fsync, сужение профиля
}

/// Ресурсы хоста; создаёт io.dart (настольные хосты) или тест.
final class EmbeddedHostServices {
  final ExecutionEnv baseEnv;                          // локальный env; containment даёт BoundedEnv ядра
  final ExecutionEnv Function(String cwd)? localEnv;   // env сессии для AcpServerConfig.localEnv (D4)
  final SessionStore sessions;
  final SecretResolver secrets;
  final http.Client http;                              // закрывается в dispose, если создан хостом
  final Logger logger;
  final Clock clock;
  final McpConnector? mcp;
  final ProjectFilesSource? projectFiles;
  final String platform;
}

abstract interface class EmbeddedAgent {
  AcpTransport get clientTransport;  // клиентский конец InProcessAcpLink
  Future<void> get closed;           // завершается после dispose (явного или по закрытию клиента)
  Future<void> dispose();            // идемпотентен (D6)
}

/// Единственная точка сборки встроенного агента (HOST-6).
Future<EmbeddedAgent> createEmbeddedAgent({
  required EmbeddedAgentConfig config,
  required EmbeddedHostServices services,
});

/// Открыватель агента для резолвера клиента: прод — из io.dart, тест — из testing.dart.
typedef EmbeddedAgentOpener =
    Future<EmbeddedAgent> Function({required String cwd, required String hostProfile});

/// Невалидная конфигурация: проблемы загрузчика без значений секретов (CFG-2).
final class EmbeddedAgentConfigException implements Exception {
  final List<ConfigIssue> issues;
}

export … show Logger, LogLevel;      // адаптер логгера хоста (app, CLI)
```

**`lib/io.dart`** — настольные хосты:

```dart
/// load(8.5) → openHostSecrets(8.9, D15) → JsonlSessionStore, LocalExecutionEnv, MCP, файлы проекта → createEmbeddedAgent.
EmbeddedAgentOpener localEmbeddedAgentOpener({
  required Map<String, String> environment,   // Platform.environment
  required Logger logger,
  bool debugSecrets = false,                  // --debug-secrets CLI; CODELAB_DEBUG_SECRETS=1 читает openHostSecrets
  http.Client? httpClient,                    // шов тестов (MockClient)
});
```

**`lib/testing.dart`** — сценарий модели (D8). Импорт разрешён тестам и только `apps/codelab_cli/lib/src/scenario/` (D3).

**Отличия от эскиза плана:**
- `memoryHostServices` и `mobileHostServices` не создаются: потребителя до этапа 10 нет (§13). Основной барель от `dart:io` свободен, и web-хост этапа 10 передаст свои `EmbeddedHostServices`;
- `EmbeddedAgent.plan` не публикуется: потребитель — план сборки в `config check`, это отдельный change (D13, п. 5). План по-прежнему уходит в лог `host.plan`;
- `loadEmbeddedAgentConfig` и `desktopHostServices` соединены в один открыватель. Оба клиента всегда вызывают их подряд, а `secretsBackend` и `sessions.dir` нужны службам только из загруженного конфига;
- `EmbeddedAgentConfig` не реэкспортирует `ProviderConfig` и `ModelRef`: клиенты строят агента открывателем, а не моделями ядра.

**Альтернатива** — буквальный API плана (`ProviderConfig provider`, `fallbackModels`) — отклонена: он не выражает маршрутизацию 8.5 и продублировал бы схему конфига.

### D3. Сторож, allowlist, граф

**Правила `rules.dart`** (вместо комментариев `stage 7`):
1. `packages/dart/codelab_embedded`:
   - `forbidden: [...webUnsafe, 'package:codelab_agent_io/', 'package:codelab_client_']`;
   - `exclude: ['lib/io.dart', 'lib/src/io/', 'lib/testing.dart', 'lib/src/testing/']`, `sealExclude: true`: основной барель не ссылается на IO и тестовые файлы.
2. `packages/dart/codelab_embedded` целиком: `['package:flutter/', 'package:fluent_ui/', 'package:codelab_ui/', 'package:codelab_client_']`.
3. `apps/codelab_cli/lib/src`:
   - `package:codelab_embedded/io.dart` — только `composition_root.dart`;
   - `package:codelab_embedded/testing.dart` — только `scenario/`.

   Оба правила — `sealExclude: false`, по образцу `codelab_setup/io.dart` и `codelab_acp_testing`.
4. `apps/codelab_desktop/lib`:
   - `package:codelab_embedded/io.dart` — только `app/` (composition root);
   - `package:codelab_embedded/testing.dart` запрещён во всём `lib/`. Тестовый сценарий в релизную сборку app не попадает структурно (D8).
5. HOST-6: `host_assembly_guard_test.dart` сканирует и `packages/dart/codelab_embedded/lib` (§10.12).

Существующее правило `apps/codelab_desktop: ['package:codelab_agent_']` остаётся. Мост его не нарушает: имя без префикса стороны (ADR-0002).

**Allowlist** (`pubspec_allowlist_test.dart`):
- новый `embeddedAllowlist = {codelab_agent_core, codelab_agent_io, codelab_agent_acp, codelab_agent_mcp, codelab_acp_protocol, codelab_acp_transports, http, meta, async}`: `codelab_acp_protocol` нужен для `Implementation` в `agentInfo`;
- `cliAllowlist` += `codelab_embedded`;
- у desktop allowlist нет, правило импорта прежнее.

**Граф** (`README.md`):
- новый узел `codelab_embedded` (серый, как `codelab_setup`) с рёбрами к `codelab_agent_acp`, `codelab_agent_io` и `codelab_agent_mcp`;
- рёбра `codelab_desktop` → `codelab_embedded` и `codelab_cli` → `codelab_embedded`;
- ребро к `codelab_acp_transports` транзитивно через `codelab_agent_acp` и не рисуется;
- абзац под графом уточняется: клиенты видят агентскую сторону только через мосты `codelab_setup` и `codelab_embedded`.

**Web.** `web-compile` компилирует `packages/dart/codelab_embedded/test/web_smoke/main.dart`: основной барель и `createEmbeddedAgent` на `MemoryExecutionEnv` с профилем `agent-serve`, суженным до памяти. Это исполняет обещание D6 change `add-in-process-acp-transport`: сборку бареля транспортов для web даёт `codelab_embedded`.

### D4. Локальное исполнение во встроенных профилях; `agentInfo`

**Решение.** У `AcpServerConfig` появляется поле `ExecutionEnv Function(String cwd)? localEnv`. Если оно задано, `_wire` ставит сессии env `localEnv(cwd)` вместо `AcpClientExecutionEnv` и `ListingOverlayEnv`. Агент тогда не отправляет `fs/*` и `terminal/*`, даже если клиент объявил `fs`/`terminal`. Gate остаётся `AcpPermissionGate`: вопрос идёт клиенту `session/request_permission`. Ядро ставит `BoundedEnv(env, root: cwd)` на сессию (ENV-2): containment обеспечивает ядро, тот же рубеж, что у инструментов бинаря.

`createEmbeddedAgent` задаёт `localEnv` для `embedded-*`. Для `agent-serve` (только `testing.dart`, D8) он не задаётся, как у бинаря по stdio, — файлы через клиента.

Почему это не меняет ACP:
- `fs` и `terminal` в `clientCapabilities` разрешают агенту вызывать методы клиента, но не обязывают его (`docs/acp/protocol/09-File System.md`, `10-Terminal.md`);
- `initialize` не меняется.

**Последствия:**
- в app встроенный агент не показывает встроенный терминал ACP (`terminal/*`): вывод `exec` приходит текстом результата вызова;
- несохранённые буферы редактора агент не видит — у desktop их нет;
- `fs_flow_test` и `terminal_flow_test` к встроенному режиму не применимы (D10).

**`agentInfo`** — тот же, что у бинаря: `name: codelab-agent`, `title: CodeLab Agent`, версия пакета. Это один агент в другом хосте. Фикстура `acp/initialize-capabilities` ждёт именно его, и `test-scenario --agent embedded` проходит без исключений нормализации. Хост различает режим логом (`host.plan`, профиль), а не протоколом.

**`detachGrace: Duration.zero`**, как у бинаря. Клиентский конец закрывается только вместе с клиентом, переподключаться к прежнему агенту некому: kit открывает новый агент (D6).

**Альтернативы:**
- (а) встроенный агент работает через `fs/*`/`terminal/*` kit, как бинарь по stdio. Отклонено: это противоречит §10.4 (`shellExec: transport local`) и задаче 7.4. Ход стал бы зависеть от процессов клиентского терминала того же процесса, а `readBytes`, `realpath` и листинг пришлось бы склеивать оверлеем;
- (б) `localEnv` как флаг `bool`, а env — `services.baseEnv`. Отклонено: серверу нужен env с корнем `cwd` конкретной сессии, как у `localListing`.

### D5. Конфигурация и секреты встроенного агента

- **Загрузка.** Открыватель зовёт `ConfigLoader().load(cwd: <папка проекта>, environment: <окружение процесса>, flags: <пустой слой>)`.
  - Слои — §15.2: `$CODELAB_HOME/config.yaml`, проектные `.codelab/config.yaml` и `config.local.yaml` с правилами доверия, `CODELAB_CONFIG`.
  - Сужение `profile.<hostProfile>.*` применяется к профилю хоста, как `profile.agent-serve.*` у бинаря.
  - Своего загрузчика у пакета нет.
- **Невалидный конфиг** даёт `EmbeddedAgentConfigException(issues)`. Текст содержит строки `<location>: [<key>: ]<message>` той же формы, что `config check`, и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`. Значений секретов в нём нет (CFG-2). Ресурсы (HTTP-клиент) до этой точки не создаются.
  - CLI печатает текст в stderr, код `64`.
  - App показывает его в `ConnectionFailed` (баннер соединения).
- **Нет ключа** (`providerProblems`): поведение как у бинаря. Соединение открывается, первый ход с этим провайдером завершается ошибкой провайдера `auth` с именем секрета без значения. В app это заметка «Failed turn», в `codelab -p` — код `1` (D13, п. 2).
- **Секреты.** Один `SecretResolver` на агента — `openHostSecrets(codelabHome: codelabHomeOf(environment), environment, backend: host.secretsBackend, debug: debugSecrets, logger)`. Резолвер передаётся и в `createRoutedStreamFunction(…, secrets:)`, и в `AgentCoreServices.secrets`. `selectionReason` не передаётся (D15 change `add-agent-secret-store`).
- **Тестовое хранилище (7.7).** Если `const bool.fromEnvironment('CODELAB_ALLOW_TEST_SECRETS')` и в окружении есть `CODELAB_TEST_SECRET_STORE=<каталог>`, бэкенд — `FileSecretStore(path: '<каталог>/secrets.yaml')` с `backend.id == "file"` (D14 того change).
  - Для этого `openHostSecrets` получает необязательный `testStorePath`; разбор переменной и проверка define — в `codelab_agent_io` рядом с загрузчиком, который уже знает имя.
  - В обычной сборке переменная не читается и даёт `config.env.unknown`, как сейчас.
- **macOS: приложение из Finder.** Окружение у него минимальное, переменных `CODELAB_SECRET_*` оболочки оно не видит. Для app рабочий путь в 1.0 — `secrets.backend: file` и `codelab secret set`. Это записывается во вложенный `AGENTS.md` desktop и в подсказку ошибки «нет ключа», если её текст формирует хост (см. Risks).
- **`CODELAB_HOME`** — только `codelabHomeOf` (D17 change `add-agent-project-files`). Ошибка раскрытия тильды — `EmbeddedAgentConfigException` с текстом загрузчика.

### D6. Жизненный цикл: один агент на соединение, `dispose`, отказ

- **Сборка** (`createEmbeddedAgent`):
  1. `buildAgentCore(profile: HostProfile.of(hostProfile).narrowed(host.profileNarrowing[hostProfile] ?? {}), services: …, config: core, streamFunction: …)`;
  2. `InProcessAcpLink()`;
  3. `AcpAgentServer(…, config: AcpServerConfig(agentInfo, detachGrace: zero, localEnv / localListing по D4))`;
  4. `await link.agent.start()`, `serve(link.agent)` в охраняемой зоне (ниже).
- **`dispose()`** — идемпотентен, повторный вызов возвращает тот же `Future`:
  1. `server.shutdown(grace: 5 s)`: новые запросы → `-32603`, ожидающие разрешения → `cancelled` → отказ, ходы отменяются и дожидаются `TurnEnded`, журнал дописывается (§13.10);
  2. `runtime.dispose()` — закрываются MCP-серверы сессий;
  3. закрытие агентского конца, если он ещё открыт. Клиентский конец получает `failed`/`disconnected`, а если клиент уже закрыл его сам — ничего;
  4. `http.close()`, если клиент создан хостом;
  5. `closed` завершается.
- **Закрытие клиентом.** Агент подписан на события агентского конца. Переход в `failed` с `disconnected` (клиент закрыл свой конец: `disconnect`, переподключение, выход) запускает тот же `dispose`. Агент не живёт дольше соединения, утечки процессов MCP и HTTP-клиента нет.
- **Отказ агента.** `serve` и вся асинхронная работа агента запускаются в `runZonedGuarded`. Необработанная ошибка в зоне или завершение `serve` с ошибкой:
  1. пишет `embedded.agent.failed {error_class}` уровня `error`. Текста ошибки в событии нет: в нём мог бы оказаться ответ провайдера или путь;
  2. закрывает агентский конец — клиентский переходит в `failed` с `disconnected`, kit показывает `ConnectionLost`;
  3. запускает `dispose`.

  Это fail-stop, как смерть процесса stdio-агента. Ошибки агента не уходят в обработчик ошибок приложения (`PlatformDispatcher.onError`), где сломанный агент остался бы жить.
- **Резолвер клиента:**
  - `open(profile, projectDirectory)` сериализован: сначала `await _running?.dispose()`, затем открыватель, затем `_running = agent`. Два агента одного резолвера одновременно не пишут журнал;
  - `close()` (вызывает composition root при выходе) — `await _running?.dispose()`.
- **Поздние события.** После `dispose` агентский конец закрыт, `send` невозможен (`sendFailed`), поэтому кадров старого агента клиент не получает. Защиту от устаревших событий нового соединения kit уже обеспечивает по транспорту (`acp-client-kit`, «Явный автомат соединения»).
- **Альтернатива:** агент живёт до явного `dispose` резолвера, без реакции на закрытие клиентского конца. Отклонено: kit закрывает транспорт сам при переподключении, и агент без соединения держал бы MCP-процессы до выхода.

### D7. `EmbeddedProfile` в клиентском слое

- `ConnectionProfile.embedded({required String id, required String label, required String hostProfile}) = EmbeddedProfile`. Профиль — чистые данные, `hostProfile` — строка: клиентский слой не знает ядра.
- `ConfigTransportResolver.supports(EmbeddedProfile)` — `false`. Встроенный профиль открывает только `EmbeddedTransportResolver` клиента, без него — `UnsupportedConnectionProfileException`, как у любого профиля без резолвера.
- `JsonFileProfileStore` встроенный профиль не сохраняет:
  - `save` с ним бросает `ArgumentError`;
  - запись `"type": "embedded"` в `profiles.json` при чтении — `FormatException`, как неизвестный тип.

  Встроенный агент выбирается словом `embedded`, а не записью. `codelab profiles add <id> embedded` и id `embedded` по-прежнему отклоняются, с текстом `embedded is built in; use --agent embedded`.

### D8. Сценарий модели для тестов: `testing.dart`, без dart-define

- **Перенос.** `LlmScript` (разбор блока `{"llm": …}`, модели сценария) и `_withScriptedProviders` (слой провайдеров сценария) переезжают из `apps/codelab_agent` в `codelab_agent_io` (`lib/src/scripted/`, экспорт из основного бареля). Бинарь и встроенный режим разбирают сценарий одним кодом. `UsageError` бинаря заменяется типизированным `LlmScriptException`, бинарь переводит его в код `64`. Тексты ошибок прежние, поведение бинаря не меняется: его тесты остаются зелёными.
- **`package:codelab_embedded/testing.dart`** даёт открыватель со сценарием:

  ```dart
  EmbeddedAgentOpener scriptedEmbeddedAgentOpener({
    required Map<String, Object?> llm,     // блок llm фикстуры или файла сценария
    required String codelabHome,           // временный каталог теста
    String hostProfile = …,                // embedded-* или agent-serve (только здесь)
    String? permissionMode,                // setup.mode фикстуры / режим теста
    String? sessionsDir,
    required Logger logger,
  });
  ```

  Конфиг сценария строится тем же слоем провайдеров сценария (`scripted: true`), что у `--llm-script`: модели — из сценария, сеть и ключ не нужны.
- **Почему не `--dart-define=CODELAB_ALLOW_SCRIPTED_LLM`**, как в плане:
  - в app сценарий подаёт интеграционный тест через шов `CodeLabBootstrap(scope:)`;
  - в e2e CLI — тестовая точка входа `test/e2e/support/embedded_cli_main.dart`, которая передаёт открыватель в `run(…)`;
  - `lib/` клиентов `testing.dart` не импортирует (сторож D3), поэтому в релизную сборку сценарий не попадает структурно. Это сильнее, чем константа сборки, и не добавляет вариант сборки.

  Единственное место рабочего кода со сценарием — драйвер фикстур `codelab test-scenario` (`lib/src/scenario/`). Это то же исключение, что у `codelab_acp_testing` в CLI (`AGENTS.md` §5), и паритет с `codelab-agent serve --llm-script` в рабочем бинаре.
- **`test-scenario --agent embedded`:**
  - агент на фикстуру — `scriptedEmbeddedAgentOpener(llm: setup.llm, hostProfile: setup.profile ?? 'agent-serve', permissionMode: setup.mode, sessionsDir: <tmp>/sessions, codelabHome: <tmp>/home)`;
  - профиль `agent-serve` даёт `fs/*` и `terminal/*` клиенту-драйверу, как у бинаря, и корпус играется без изменений;
  - пропуски — как у `codelab-agent`: `setup.sessions`, `setup.config`, `setup.web`, `setup.mcp` и профиль вне `{agent-serve, embedded-cli}` дают `SKIP` с причиной. Поддержка `setup.*` в процессе — возможное расширение, в этот change не входит.
- **Альтернатива** — dart-define в обоих клиентах. Отклонено:
  - в app константа не даёт сменить сценарий между тестами одного файла;
  - в CLI она требует отдельной сборки для `test-scenario`;
  - в обоих случаях тестовый код остаётся в `lib/`.

  Расхождение с текстом плана (7.7 и `09-05`) правится задачами документов.

### D9. codelab-app: тип подключения и composition root

- `CodeLabTransportType.embedded(label: 'Embedded agent')`: строки app английские, как `stdio` и `WebSocket`. Полей у типа нет: проект выбирается «Open Project», конфиг — файлом.
  - `selectedProfileLabel` — `Embedded agent`;
  - `selectedConnectionDetail` — `codelab_embedded (embedded-app-desktop)`;
  - профиль — `ConnectionProfile.embedded(id: 'embedded', label: 'Embedded agent', hostProfile: 'embedded-app-desktop')`.
- Тип по умолчанию в форме остаётся `stdio`: план делает встроенный режим умолчанием только в CLI. Смена умолчания в app — решение этапа 9.
- `app/app_scope.dart`:
  - регистрирует `EmbeddedTransportResolver(localEmbeddedAgentOpener(environment: Platform.environment, logger: <адаптер>))` вторым резолвером `ClientWorkspace`;
  - закрывает его при закрытии root scope, до `AcpClientApplication`;
  - адаптер `Logger` → логгер приложения (`structured_log`) — в `app/`. Поля лога агента уже без значений секретов, адаптер ничего не добавляет.
- Шов тестов: `createCodeLabRootScope({EmbeddedAgentOpener? embeddedOpener})`. Интеграционный тест передаёт `scriptedEmbeddedAgentOpener` (D8).
- Выход из приложения: `CodeLabBootstrap.dispose` закрывает scope без ожидания (`unawaited`), а macOS может завершить процесс раньше `dispose` агента. Журнал JSONL с `fsync: checkpoints` теряет не больше незавершённого хода (§8). Ожидание закрытия при выходе — вне scope (Risks).

### D10. Тесты по уровням и веткам

- **`codelab_embedded`** (Dart VM, `melos run test`), на `InProcessAcpLink` и временном `CODELAB_HOME`:
  - ход со сценарием;
  - одобрение и отказ через ACP;
  - containment;
  - `dispose` при ожидающем разрешении: журнал содержит итог хода;
  - закрытие клиентом;
  - отказ в зоне → клиентский `failed`/`disconnected`;
  - конфиг 8.5 и ключ через `SecretResolver` (`MockClient` провайдера, `CODELAB_SECRET_*`, `secrets.backend: file`);
  - процессный тест `CODELAB_TEST_SECRET_STORE` через `fvm dart run -DCODELAB_ALLOW_TEST_SECRETS=true`.
- **Паритет профилей** (§10.12): один сценарий даёт одинаковую последовательность `AgentEvent` в `agent-serve`, `embedded-app-desktop` и `embedded-cli`.
- **CLI:**
  - модульные тесты резолвера и выбора профиля;
  - e2e `cli/*` с `CODELAB_E2E_AGENT=embedded` — CLI из kernel тестовой точки входа (D8), сценарии `test/e2e/llm_scripts/`, без тестов `scripted-only`. Скрипт `test:e2e:cli:embedded` входит в `check` (Dart VM, `AGENTS.md` §21);
  - `conformance:embedded` — `codelab test-scenario packages/dart/codelab_acp_testing/fixtures/acp --agent embedded`, тоже в `check`.
- **App:**
  - модульные тесты `ConnectionCubit` (тип `embedded`, профиль) и widget-тест диалога;
  - интеграционные тесты `integration_test/` с `CODELAB_E2E_AGENT=embedded`: поддержка `support/e2e_agent.dart` выбирает тип «Embedded agent» и передаёт scope со сценарием. Применимы все, кроме `fs_flow_test` и `terminal_flow_test` (D4) и тестов `scripted-only`;
  - в feature-ветке тесты пишутся и проходят `fvm flutter analyze`. Прогон на устройстве `melos run test:e2e:app:embedded` — только в `release/<version>` (`AGENTS.md` §21; D13, п. 4).

### D11. Замер 7.8 и isolate

- **Разведка.** `packages/dart/codelab_embedded/benchmark/stream_latency_benchmark.dart`, не дольше двух дней, без тестов (исключение (д)):
  - сценарий модели отдаёт 10 000 чанков;
  - клиентская сторона — `AcpClientApplication` и `ClientWorkspace` (dev-зависимости пакета): замер включает проекцию kit, а не только транспорт;
  - таймер 1 мс в том же isolate меряет задержку цикла событий;
  - печатаются p50, p99, максимум и время хода.

  Прогон — AOT (`fvm dart compile exe`, как релиз Flutter) на эталонной машине (D13, п. 3).
- **Критерии** (план): p99 > 8 мс или максимум > 50 мс → ядро переносится в `IsolateAcpLink` (эскиз §9.12) отдельной итерацией с тестами по TDD. Иначе остаётся `InProcessAcpLink`.
- Результат записывается сюда, в «Решение 7.8», с числами, машиной и режимом сборки. Если копия сообщений (D9 change `add-in-process-acp-transport`) окажется доминирующей, сравнение без копии вводится здесь же отдельным решением со спецификацией. Выключатель копии заранее не добавляется.
- **Разбор журнала.** По плану чтение и разбор JSONL при `session/load` уходят в `Isolate.run` в любом случае (`codelab_agent_io`, только `dart:io`-хосты).
  - Поведение и результат не меняются; тест — равенство реплея до и после.
  - Сжатие контекста в isolate не переносится: оно ждёт ответа LLM, его CPU-часть мала. Пересмотр — по числам замера.
- На web isolate нет, там всегда `InProcessAcpLink` (этап 10).

**Решение 7.8:** _заполняется при выполнении задачи 5.1 — машина, режим сборки, p50/p99/max, вывод по критериям._

### D12. Итерации

Каждая итерация — отдельный PR (§9.0, правило 8). Красный тест коммитится до кода, коммит — по просьбе пользователя.

0. **Документы** — §13.1 и уточнения §9.12 (сделано при подготовке change).
1. **Встроенный агент отвечает на ход в памяти** — `[agent]`, `[protocol]`:
   - профиль `embedded-app-desktop`;
   - `AcpServerConfig.localEnv`;
   - перенос сценария модели;
   - пакет `codelab_embedded` с `createEmbeddedAgent` и `testing.dart`;
   - сторож, allowlist, HOST-6, web-smoke.
2. **Настоящий хост** — `[agent]`: `io.dart` (конфиг 8.5, секреты 8.9 и тестовое хранилище, JSONL, MCP, файлы проекта), `dispose` и закрытие клиентом, отказ в зоне, паритет профилей.
3. **CLI** — `[client]`: `EmbeddedProfile`, резолвер, выбор по умолчанию, `--debug-secrets`, ошибки конфига, `test-scenario --agent embedded`, e2e `cli/*`, скрипты `check`.
4. **App** — `[desktop]`: тип подключения, резолвер и scope, адаптер логгера, интеграционные тесты (анализ в feature, прогон — `release/*`), скрипт `test:e2e:app:embedded`.
5. **Замер 7.8** — `[agent]`: бенчмарк и решение. Затем, по TDD, `Isolate.run` для журнала; `IsolateAcpLink` — только по результату.
6. **Документы и Definition of Done** — `[docs]`.

Итерации 3 и 4 независимы друг от друга после итерации 2.

## Risks / Trade-offs

- **Тяжёлая работа ядра в UI-isolate** (разбор журнала, проекция 10 000 чанков) → замер 7.8 по критериям; разбор журнала — в `Isolate.run`. Если критерии провалены — `IsolateAcpLink` отдельной итерацией.
- **Отказ агента роняет приложение** → охраняемая зона `runZonedGuarded` (D6), fail-stop с закрытием конца. Остаточный риск: синхронный бесконечный цикл в ядре зона не прерывает, и UI зависнет. Лечится только isolate (7.8).
- **Гонка `open`/`dispose`** при быстром переподключении → резолвер сериализует `open` и ждёт `dispose` прежнего агента (D6). Kit защищает состояние от поздних событий прежнего транспорта.
- **Один журнал из двух процессов.** App и CLI во встроенном режиме и бинарь пишут в один `$CODELAB_HOME/sessions`. Одну сессию, открытую на запись двумя процессами, MVP не защищает: lease `file` — после MVP (§17.6.8). Риск тот же, что у бинаря сегодня; change не ухудшает его, но делает вероятнее (app и CLI на одной машине).
- **Выход app без ожидания `dispose`** → незавершённый ход может не дописаться. `fsync: checkpoints` ограничивает потерю последним ходом (D9).
- **Секреты:**
  - app из Finder не видит `CODELAB_SECRET_*` (D5) → рабочий путь `secrets.backend: file`;
  - значения не попадают в `EmbeddedAgentConfigException`, `embedded.agent.failed` и баннер: проверяется тестами D10;
  - кэш резолвера до перезапуска — известное ограничение до 8.10.
- **Permission flow.** API для внешнего `PermissionGate` или режима (`autopilot`) у пакета нет. Режим задаёт профиль или `permissions.mode` конфига (HOST-7), `autopilot` в конфиге запрещён (CFG-4). Тестовый `permissionMode` есть только в `testing.dart` (D8).
- **Containment.** В embedded-профилях единственный рубеж — `BoundedEnv` ядра (ENV-2): клиентская проверка `fs/*` здесь не участвует. Тесты D10 проверяют выход `../` и symlink наружу.
- **Обход сторожа реэкспортом.** `codelab_embedded` реэкспортирует только `Logger` и `LogLevel`. Новые реэкспорты — через правку D2 и спецификации.
- **Дублирование сборки** в бинаре и `codelab_embedded` (D1, в) → тест паритета профилей и общий перенесённый сценарий (D8).

## Migration Plan

- `codelab` без `--agent` с профилем `default` в `profiles.json` работает как прежде (D13, п. 1). Без профиля вместо кода `64` с подсказкой `profiles add` запускается встроенный агент; без конфига — код `64` с проблемами конфига и подсказкой (D5).
- Бинарь `codelab-agent` не меняется. Перенос `LlmScript` — рефакторинг под его тестами.
- Откат: удаление резолвера из composition root возвращает клиентам прежнее поведение. Пакет и профиль ядра ничего не ломают.

### D13. Решения пользователя 2026-11-02 (бывшие OQ1–OQ6)

Все открытые вопросы решены пользователем 2026-11-02 по рекомендациям design.md.

1. **`codelab` без `--agent` (OQ1, вариант (а)).** Если в `profiles.json` есть профиль `default`, используется он. Иначе — встроенный агент, как с `-a embedded`. Битый `profiles.json` даёт код `64` с причиной, а не переход на встроенного агента. Внешний агент выбирается явно: `-a stdio:…`, `-a ws://…`, `-a <id>`. Явный выбор, сделанный командой `profiles add default`, сохраняется, а новая установка получает встроенного агента.
2. **Нет конфига или ключа в app (OQ2, вариант (а)).** До мастера 8.10/D-05:
   - нет `config.yaml` или конфиг невалиден — подключение в `ConnectionFailed`. Баннер соединения показывает текст `EmbeddedAgentConfigException`: проблемы загрузчика в форме `config check` и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check` (D5). Значений секретов в тексте нет;
   - нет ключа провайдера — подключение открывается. Первый ход с этим провайдером падает ошибкой провайдера с именем секрета без значения, как у бинаря: в app — заметка «Failed turn», в `codelab -p` — код `1`. Отдельной проверки готовности провайдера нет: её даст `ProviderReadiness` в change `add-provider-setup-ui`.
3. **Эталон замера 7.8 (OQ3).** Mac на Apple Silicon разработчика (модель, память, ОС записываются в «Решение 7.8»), сборка AOT `fvm dart compile exe`, три прогона, критерий — медиана p99 и максимум. Прогон на Linux-раннере CI — справочно, критерием не служит.
4. **Объём 7.7 в feature-ветке (OQ4).** Интеграционные тесты app пишутся и проходят `fvm flutter analyze` в feature-ветке. Прогон на устройстве `melos run test:e2e:app:embedded` — только в `release/<version>` (`AGENTS.md` §21). Доказательство в feature-ветке — тесты `codelab_embedded` и e2e CLI на Dart VM.
5. **План сборки в `codelab config check` (OQ5) — вне scope.** Отдельный change: план для профиля хоста в обоих бинарях и API ядра для расчёта плана без сборки runtime. Этот change его не создаёт; `EmbeddedAgent.plan` не публикуется (D2).
6. **Флаги CLI `--permission-mode`, `--config`, `--log-file` (OQ6) — вне scope.** Отдельный change. До него конфиг задаётся `CODELAB_CONFIG`, режим сессии — `permissions.mode` конфига, одобрения в `-p` — `--approve`.

## Open Questions

Открытых вопросов нет. Соответствие решений пользователя 2026-11-02:

| Вопрос | Решение | Где учтено |
|---|---|---|
| OQ1 | (а): профиль `default`, если есть, иначе встроенный агент | D13, п. 1; codelab-cli «Профили подключения CLI»; задачи 3.3–3.4, 3.8 |
| OQ2 | (а): конфиг — `ConnectionFailed` с проблемами и подсказкой; ключ — ошибка первого хода | D5; D13, п. 2; agent-workbench-ui «Тип подключения «Встроенный агент»»; embedded-agent «Конфигурация и секреты встроенного агента»; задачи 4.1, 4.3 |
| OQ3 | Mac Apple Silicon, AOT, медиана p99 по трём прогонам; CI Linux — справочно | D11; D13, п. 3; задача 5.1 |
| OQ4 | тесты app в feature — написание и анализ; прогон на устройстве — `release/*` | D10; D13, п. 4; testing-quality; задача 4.5 |
| OQ5 | вне scope, отдельный change | D13, п. 5; proposal «Не входит»; `09-12` |
| OQ6 | вне scope, отдельный change | D13, п. 6; proposal «Не входит»; `09-12` |
