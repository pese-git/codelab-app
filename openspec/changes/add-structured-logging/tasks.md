## 1. Подготовка технологии

- [x] 1.1 Утвердить `structured_log` как технологию логирования в `docs/architecture/technology-stack.md` — версия `0.2.0-dev.4` (pub.dev), с пометкой, что это prerelease и пин будет обновлён при выходе стабильного `0.2.0`.
- [x] 1.2 Добавить `structured_log: 0.2.0-dev.4` (точный pin, без caret) в `dependencies` `packages/dart/acp_client_core/pubspec.yaml`, выполнить `melos bootstrap`.

## 2. Logger-порт и адаптер (`acp_client_core`)

- [x] 2.1 Определить абстрактный Logger-порт в `acp_client_core` (методы уровней trace/debug/info/warning/error/critical — по факту сверки с `structured_log` 0.2.0-dev.4 `LogLevel` в пакете есть все, кроме отдельного `fatal` — маппится на `critical`; context-binding/`child()`, `withCorrelation`-эквивалент, `category`/`component`).
- [x] 2.2 Реализовать `structured_log`-адаптер порта внутри `acp_client_core` (единственное место с прямой зависимостью на `structured_log`) поверх `getLogger([name])` — используя глобальный `StructlogConfiguration`, сознательно без собственного explicit-instance (design.md Decision 7).
- [x] 2.3 Реализовать фабрику, конструирующую `StructlogConfiguration(sinks: [...])` согласно design.md Decision 6: `LogSink(name: 'application', output: coloredConsoleOutput, categories: {'application'})` + `LogSink(name: 'protocol', output: AsyncRotatingFileOutput(...), minLevel: LogLevel.trace, categories: {'protocol'}, enabled: false)`. Адаптер обязан выставлять `context: {'category': ...}` (или `bind({'category': ...})`) на каждый вызов, иначе `LogSink.categories`-фильтрация не сработает.
- [x] 2.4 Экспортировать Logger-порт и фабрику адаптера через публичный API пакета (`lib/acp_client_core.dart`).

## 3. Маскирование и correlation

- [x] 3.1 Подключить существующий `SecretRedactor` (`packages/dart/acp_client_core/lib/src/domain/secret_redaction.dart`) как processor Logger-адаптера — без новых правил редактирования.
- [x] 3.2 Прокинуть `AcpClientApplication.generation` в structured-события через `BoundLogger.withCorrelation(connectionGeneration: ...)`.
- [x] 3.3 Прокинуть существующие session/request/tool-call identifiers через `withCorrelation(sessionId: ..., requestId: ..., toolCallId: ...)`.
- [x] 3.4 Тест: секрет в context-поле и в свободном тексте сообщения замаскирован как в консольном (человекочитаемом), так и в файловом/protocol-trace выводе (см. спеку "Маскирование секретов в structured-выводе").
- [x] 3.5 Тест: reconnect-событие содержит актуальный `connection_generation`; событие из устаревшего generation логируется с `reason=stale_generation` и не применяется к текущему state.

## 4. Bounded diagnostics buffer

- [x] 4.1 Добавить cap (500 записей, по примеру `observability.md` §28) к `_diagnostics` в `AcpClientApplication` — вытеснение самых старых записей при превышении.
- [x] 4.2 Убедиться, что полный structured-вывод продолжает идти в Logger-sink независимо от bounded in-memory списка (ничего не теряется для целей диагностики за пределами UI-инспектора).
- [x] 4.3 Тест: превышение лимита вытесняет старые записи, `AcpClientApplication.diagnostics` не растёт неограниченно.

## 5. Layer ownership

- [x] 5.1 В `AcpClientApplication` пометить structured-события, порождённые `AcpTransportEvent.diagnostic`, как `component=transport`.
- [x] 5.2 Пометить structured-события, порождённые перехваченными типизированными ошибками `acp_protocol`, как `component=protocol`.
- [x] 5.3 Пометить structured-события собственного application-lifecycle (session/request/reconnect/cancellation/permission) как `component=client`.
- [x] 5.4 Тест: transport diagnostic-событие и protocol-ошибка помечены соответствующим `component` (см. спеку "Логирование по слоям согласно ownership").

## 6. Protocol tracing в отдельный файл (developer-only)

- [x] 6.1 Использовать `logger.trace(...)` (`LogLevel.trace`, `structured_log` 0.2.0-dev.4+) с `category=protocol` для полного ACP payload обмена client↔agent — runtime on/off идёт через `LogSink.enabled` (не через `minLevel`, он `final`/немутируем), выключено по умолчанию (design.md Decision 4).
- [x] 6.2 Настроить protocol-trace `LogSink` на `AsyncRotatingFileOutput('protocol.log', maxSizeBytes: …, maxBackups: …)` с `minLevel: LogLevel.trace` (иначе default `minLevel: debug` отфильтрует trace-записи) — путь в app-data-dir, см. задачу 7.1, отдельно от application-sink в консоли (задача 2.3).
- [x] 6.3 Реализовать explicit toggle включения protocol tracing через `StructlogConfiguration.setSinkEnabled('protocol', enabled: ...)` (debug/runtime-настройка), не активируемый автоматически при ошибке.
- [x] 6.4 Гарантировать, что release-сборка не включает protocol tracing по умолчанию независимо от toggle default.
- [x] 6.5 Тест: release-конфигурация не пишет `protocol.log` по умолчанию; явное включение начинает писать в него полный payload до явного выключения.
- [x] 6.6 Тест: `flushed` protocol-trace sink дожидается всех поставленных в очередь записей (см. задачу 7.5 — graceful shutdown).

## 7. Composition root (`codelab_app`)

- [x] 7.1 Добавить `CodeLabLoggingModule` в `apps/codelab_app/lib/app/app_scope.dart` по образцу `CodeLabPlatformModule`: application-sink на `coloredConsoleOutput` (человекочитаемый вывод в терминал) в debug / `AsyncFileOutput` в app-data-dir в release (неблокирующий, не `fileOutput`); protocol-trace sink отдельно, per задачу 6.2.
- [x] 7.2 Проверить/задействовать per-sink error isolation пакета для protocol-trace и application-file sink (ошибка инициализации/записи файлового sink не должна ронять приложение и не должна мешать другим sink'ам); добавить собственный safe-fallback в адаптере, если встроенной изоляции недостаточно.
- [x] 7.3 Прокинуть Logger-порт (адаптер поверх `BoundLogger`) через constructor injection в `CodeLabShellCubit` (и другие presentation-компоненты, которым нужны significant user intents/UI failures), не резолвя его внутри widgets.
- [x] 7.4 Добавить `structured_log` в `apps/codelab_app/pubspec.yaml`, если конкретная конфигурация sink требует типов пакета в composition root; выполнить `melos bootstrap`.
- [x] 7.5 В `CodeLabRootLifecycle.dispose()` дождаться `flushed` обоих async file-output инстансов (application-в-release и protocol-trace) перед возвратом, аналогично уже существующей последовательности `shellCubit.close() → transport.close() → application.dispose()` (design.md Decision 8).

## 8. Регресс существующего контракта

- [x] 8.1 Тест: `AcpClientApplication.diagnostics`/`inspector_pane.dart` получают `DiagnosticEntry` той же формы, что и до этого change (см. спеку "Существующий контракт diagnostics-потока не меняется").
- [x] 8.2 Прогнать существующие тесты `acp_client_core_test.dart`, затрагивающие `SecretRedactor`/diagnostics, убедиться в отсутствии регрессии.
- [x] 8.3 В тестах, создающих несколько `AcpClientApplication`/Logger-конфигураций в одном файле, вызывать `StructlogConfiguration.reset()`/`.configure(...)` явно в `setUp`/`tearDown`, чтобы избежать утечки глобального logging state между тестами одного файла (design.md Decision 7 — остаточный риск).

## 9. Проверка

- [x] 9.1 `melos format` для изменённых файлов.
- [x] 9.2 `melos analyze` для `acp_client_core` и `codelab_app`.
- [x] 9.3 `melos test` — таргетированно для `acp_client_core` и `codelab_app`, затем полный прогон, так как меняется shared package.
