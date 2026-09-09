## 1. Подготовка технологии

- [ ] 1.1 Утвердить `structured_log` как технологию логирования в `docs/architecture/technology-stack.md` (точная версия, ссылка на pub.dev).
- [ ] 1.2 (upstream, вне этого репозитория) Расширить `structured_log` типизированным context-binding API под `session_id`/`request_id`/`connection_generation`/`tool_call_id`/`message_id`/`operation_id` — если к моменту реализации API ещё не готово, использовать существующий inline `Map<String, Object?>` context как fallback, не блокируя остальные задачи.
- [ ] 1.3 Добавить `structured_log` в `dependencies` `packages/dart/acp_client_core/pubspec.yaml` (точный pin версии), выполнить `melos bootstrap`.

## 2. Logger-порт и адаптер (`acp_client_core`)

- [ ] 2.1 Определить абстрактный Logger-порт в `acp_client_core` (методы уровней trace/debug/info/warning/error/fatal, context-binding/`child()`, category/component).
- [ ] 2.2 Реализовать `structured_log`-адаптер порта внутри `acp_client_core` (единственное место с прямой зависимостью на `structured_log`).
- [ ] 2.3 Экспортировать Logger-порт и фабрику адаптера через публичный API пакета (`lib/acp_client_core.dart`).

## 3. Маскирование и correlation

- [ ] 3.1 Подключить существующий `SecretRedactor` (`packages/dart/acp_client_core/lib/src/domain/secret_redaction.dart`) как processor Logger-адаптера — без новых правил редактирования.
- [ ] 3.2 Прокинуть `AcpClientApplication.generation` в structured-события как `connection_generation`.
- [ ] 3.3 Прокинуть существующие session/request/tool-call identifiers в structured-события как `session_id`/`request_id`/`tool_call_id`.
- [ ] 3.4 Тест: секрет в context-поле и в свободном тексте сообщения замаскирован в structured-выводе (см. спеку "Маскирование секретов в structured-выводе").
- [ ] 3.5 Тест: reconnect-событие содержит актуальный `connection_generation`; событие из устаревшего generation логируется с `reason=stale_generation` и не применяется к текущему state.

## 4. Bounded diagnostics buffer

- [ ] 4.1 Добавить cap (500 записей, по примеру `observability.md` §28) к `_diagnostics` в `AcpClientApplication` — вытеснение самых старых записей при превышении.
- [ ] 4.2 Убедиться, что полный structured-вывод продолжает идти в Logger-sink независимо от bounded in-memory списка (ничего не теряется для целей диагностики за пределами UI-инспектора).
- [ ] 4.3 Тест: превышение лимита вытесняет старые записи, `AcpClientApplication.diagnostics` не растёт неограниченно.

## 5. Layer ownership

- [ ] 5.1 В `AcpClientApplication` пометить structured-события, порождённые `AcpTransportEvent.diagnostic`, как `component=transport`.
- [ ] 5.2 Пометить structured-события, порождённые перехваченными типизированными ошибками `acp_protocol`, как `component=protocol`.
- [ ] 5.3 Пометить structured-события собственного application-lifecycle (session/request/reconnect/cancellation/permission) как `component=client`.
- [ ] 5.4 Тест: transport diagnostic-событие и protocol-ошибка помечены соответствующим `component` (см. спеку "Логирование по слоям согласно ownership").

## 6. Protocol tracing (developer-only)

- [ ] 6.1 Ввести `trace`-уровень/категорию Logger для полного ACP payload, выключенную по умолчанию.
- [ ] 6.2 Реализовать explicit toggle включения protocol tracing (debug/runtime-настройка), не активируемый автоматически при ошибке.
- [ ] 6.3 Гарантировать, что release-сборка не включает protocol tracing по умолчанию независимо от toggle default.
- [ ] 6.4 Тест: release-конфигурация не пишет полный payload по умолчанию; явное включение раскрывает полный payload до явного выключения.

## 7. Composition root (`codelab_app`)

- [ ] 7.1 Добавить `CodeLabLoggingModule` в `apps/codelab_app/lib/app/app_scope.dart` по образцу `CodeLabPlatformModule`: конфигурация sink (stdout в debug / файл в app-data-dir в release), минимальный level.
- [ ] 7.2 Обеспечить безопасный fallback адаптера при ошибке инициализации файлового sink (no-op/stdout-only, без падения приложения).
- [ ] 7.3 Прокинуть `Logger` через constructor injection в `CodeLabShellCubit` (и другие presentation-компоненты, которым нужны significant user intents/UI failures), не резолвя его внутри widgets.
- [ ] 7.4 Добавить `structured_log` в `apps/codelab_app/pubspec.yaml`, если конкретная конфигурация sink требует типов пакета в composition root; выполнить `melos bootstrap`.

## 8. Регресс существующего контракта

- [ ] 8.1 Тест: `AcpClientApplication.diagnostics`/`inspector_pane.dart` получают `DiagnosticEntry` той же формы, что и до этого change (см. спеку "Существующий контракт diagnostics-потока не меняется").
- [ ] 8.2 Прогнать существующие тесты `acp_client_core_test.dart`, затрагивающие `SecretRedactor`/diagnostics, убедиться в отсутствии регрессии.

## 9. Проверка

- [ ] 9.1 `melos format` для изменённых файлов.
- [ ] 9.2 `melos analyze` для `acp_client_core` и `codelab_app`.
- [ ] 9.3 `melos test` — таргетированно для `acp_client_core` и `codelab_app`, затем полный прогон, так как меняется shared package.
