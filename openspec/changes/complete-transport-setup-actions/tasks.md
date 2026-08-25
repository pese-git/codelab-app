## 1. WebSocket transport wiring

- [ ] 1.1 Добавить typedef `CodeLabWebSocketTransportFactory` (по аналогии с `CodeLabStdioTransportFactory`) и параметр в конструктор `CodeLabShellCubit`
- [ ] 1.2 Зарегистрировать WebSocket transport factory в DI рядом с существующей stdio-фабрикой (`app_scope.dart`)
- [ ] 1.3 Реализовать `_webSocketConfigFromState()` (валидация endpoint, сборка `WebSocketAcpTransportConfig` из `webSocketEndpoint`/`webSocketToken`)

## 2. connect()/reconnect() для WebSocket

- [ ] 2.1 Добавить WebSocket-ветку в `connect()`: валидация конфигурации → `connecting` → `_application.connect(transport)` → маппинг статуса/диагностики (зеркально stdio-ветке)
- [ ] 2.2 Добавить WebSocket-ветку в `reconnect()`: валидация → `reconnecting` → `_reconnectUseCase(ReconnectCommand(...))` → маппинг статуса/диагностики (зеркально stdio-ветке)
- [ ] 2.3 Убрать `_recordPendingAction('WebSocket connect/reconnect is deferred...')` — оба пути должны выполнять реальное действие

## 3. Edit profile

- [ ] 3.1 Добавить `FocusNode` для Command-поля (stdio) и Endpoint-поля (WebSocket) в `TransportSetupPanel`/`_TransportTextField`
- [ ] 3.2 Реализовать `editProfile()` в `CodeLabShellCubit`/presentation: запросить фокус на нужном поле в зависимости от `state.transportType`, проскроллить `WorkbenchMainPane` к `TransportSetupPanel` через `Scrollable.ensureVisible`
- [ ] 3.3 Убрать `_recordPendingAction('Transport profile editing is wired in task 7.2.')`

## 4. Тесты

- [ ] 4.1 Заменить `'reconnect leaves WebSocket startup deferred'` (`widget_test.dart:815`) тестом на успешный WebSocket reconnect
- [ ] 4.2 Добавить тест на неудачный WebSocket reconnect (сетевая ошибка/auth) → `connectionStatus.failed` + диагностика
- [ ] 4.3 Добавить тест на успешный WebSocket connect (аналогично существующим stdio-тестам `connect()`)
- [ ] 4.4 Добавить тест: `editProfile()` при stdio-транспорте фокусирует Command-поле
- [ ] 4.5 Добавить тест: `editProfile()` при WebSocket-транспорте фокусирует Endpoint-поле

## 5. Проверка

- [ ] 5.1 `fvm dart run melos run format`
- [ ] 5.2 `fvm dart run melos run analyze`
- [ ] 5.3 `fvm dart run melos run test`
