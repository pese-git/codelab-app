## 1. WebSocket transport wiring

- [ ] 1.1 Добавить typedef `CodeLabWebSocketTransportFactory` (по аналогии с `CodeLabStdioTransportFactory`) и параметр в конструктор `CodeLabShellCubit`
- [ ] 1.2 Зарегистрировать WebSocket transport factory в DI рядом с существующей stdio-фабрикой (`app_scope.dart`)
- [ ] 1.3 Реализовать `_webSocketConfigFromState()` (валидация endpoint, сборка `WebSocketAcpTransportConfig` из `webSocketEndpoint`/`webSocketToken`)

## 2. connect()/reconnect() для WebSocket

- [ ] 2.1 Добавить WebSocket-ветку в `connect()`: валидация конфигурации → `connecting` → `_application.connect(transport)` → маппинг статуса/диагностики (зеркально stdio-ветке)
- [ ] 2.2 Добавить WebSocket-ветку в `reconnect()`: валидация → `reconnecting` → `_reconnectUseCase(ReconnectCommand(...))` → маппинг статуса/диагностики (зеркально stdio-ветке)
- [ ] 2.3 Убрать `_recordPendingAction('WebSocket connect/reconnect is deferred...')` — оба пути должны выполнять реальное действие

## 3. Диалог настройки подключения

- [ ] 3.1 Создать `ConnectionSetupDialog` в `apps/codelab_app/lib/features/workbench/presentation/widgets/` — оборачивает существующий `TransportSetupPanel` в Fluent `ContentDialog`, без изменений самой формы
- [ ] 3.2 Удалить безусловный инлайн-рендер `TransportSetupPanel` из `WorkbenchMainPane.build()` (`main_pane.dart:31,60`)
- [ ] 3.3 Добавить постоянную кнопку "Edit profile" в `WorkbenchCommandBar`, открывающую `ConnectionSetupDialog` через `showDialog`
- [ ] 3.4 Добавить компактный режим `AcpConnectionScreen` (или соседний виджет) для пустого/disconnected состояния: карточка с кнопкой "Configure connection", открывающей тот же диалог — не открывать диалог автоматически при старте
- [ ] 3.5 Удалить `CodeLabShellCubit.editProfile()` и `_recordPendingAction('Transport profile editing is wired in task 7.2.')` — открытие диалога не требует метода в кубите (ephemeral UI state, см. design.md)

## 4. Тесты

- [ ] 4.1 Заменить `'reconnect leaves WebSocket startup deferred'` (`widget_test.dart:815`) тестом на успешный WebSocket reconnect
- [ ] 4.2 Добавить тест на неудачный WebSocket reconnect (сетевая ошибка/auth) → `connectionStatus.failed` + диагностика
- [ ] 4.3 Добавить тест на успешный WebSocket connect (аналогично существующим stdio-тестам `connect()`)
- [ ] 4.4 Добавить тест: кнопка "Edit profile" в командной панели открывает `ConnectionSetupDialog` независимо от состояния транскрипта
- [ ] 4.5 Добавить тест: "Configure connection" на пустом экране открывает тот же диалог, предзаполненный текущими значениями
- [ ] 4.6 Добавить тест: диалог не открывается автоматически при первом запуске (пустой стейт без прежнего подключения)
- [ ] 4.7 Добавить тест: изменение поля внутри диалога применяется к состоянию немедленно (как у текущей инлайн-формы)

## 5. Проверка

- [ ] 5.1 `fvm dart run melos run format`
- [ ] 5.2 `fvm dart run melos run analyze`
- [ ] 5.3 `fvm dart run melos run test`
