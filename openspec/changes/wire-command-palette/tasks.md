## 1. State и видимость палитры

- [ ] 1.1 Добавить `isCommandPaletteOpen` (и, если нужно, список доступности команд) в `CodeLabShellState`
- [ ] 1.2 Реализовать `openCommandPalette()`/`closeCommandPalette()` в `CodeLabShellCubit` вместо заглушки `_recordPendingAction(...)`
- [ ] 1.3 Смонтировать `AcpCommandPaletteSurface` как overlay поверх `AcpWorkbenchLayout` в `workbench_shell.dart`, управляемый `state.isCommandPaletteOpen`
- [ ] 1.4 Убедиться, что `Esc` при открытой палитре закрывает именно её, а не триггерит `onCancel` шелла (проверить взаимодействие с `AcpWorkbenchShortcuts`)

## 2. Выполнение доступных команд

- [ ] 2.1 `/new` → вызывает существующий `createSession()`, закрывает палитру
- [ ] 2.2 `/reconnect` → вызывает существующий `reconnect()`, закрывает палитру
- [ ] 2.3 `/logs` → делает видимым `AcpDebugLogPanel` (снимает `Offstage` с инспектора в narrow-layout, если он был скрыт), закрывает палитру

## 3. Честное отображение недоступных команд

- [ ] 3.1 Пометить `/plan`, `/permissions`, `/compact` как недоступные в `AcpCommandAction`/палитре (disabled-стиль или "coming soon"), без изменений в `acp_ui`, если атрибут доступности уже поддержан, либо с точечным расширением `AcpCommandAction`, если нет
- [ ] 3.2 Убедиться, что выбор недоступной команды не закрывает палитру и не пишет в диагностику сообщение, похожее на выполненное действие

## 4. Тесты

- [ ] 4.1 Widget-тест: `Ctrl/Cmd+K` открывает палитру, `Esc` закрывает
- [ ] 4.2 Widget-тест: выбор `/new` создаёт сессию и закрывает палитру
- [ ] 4.3 Widget-тест: выбор `/reconnect` вызывает reconnect-флоу и закрывает палитру
- [ ] 4.4 Widget-тест: выбор `/logs` показывает debug log panel
- [ ] 4.5 Widget-тест: выбор `/plan`/`/permissions`/`/compact` оставляет палитру открытой и не создаёт ложной записи в диагностике

## 5. Проверка

- [ ] 5.1 `fvm dart run melos run format`
- [ ] 5.2 `fvm dart run melos run analyze`
- [ ] 5.3 `fvm dart run melos run test`
