## 1. Infrastructure — filesystem read

- [ ] 1.1 Создать `WorkspaceFileReader` (интерфейс + `dart:io`-реализация) в `apps/codelab_app/lib/core/platform/` — `listDirectory(path)` (один уровень), `readFile(path)` (с лимитом размера)
- [ ] 1.2 Добавить захардкоженный игнор-лист директорий (`.git`, `.dart_tool`, `build`, `.venv`, `node_modules`, `.pub-cache`) в `listDirectory`
- [ ] 1.3 Зарегистрировать `WorkspaceFileReader` в DI рядом с `WorkingDirectoryProvider`

## 2. AcpFilePreviewPanel (acp_ui)

- [ ] 2.1 Реализовать `AcpFilePreviewPanel` organism: путь, номера строк, опциональный `highlightRange`, футер с provenance-меткой ("from agent's tool call" / "read directly from disk")
- [ ] 2.2 Реализовать "too large to preview" состояние
- [ ] 2.3 Реализовать "Following" toggle (виден только для tool-call-source)

## 3. AcpDirectoryTree (acp_ui)

- [ ] 3.1 Реализовать `AcpDirectoryTree` organism: ленивое раскрытие узлов, иконки папка/файл, выбранное состояние
- [ ] 3.2 Реализовать пустое/ошибочное состояние (директория недоступна для чтения)

## 4. Интеграция в workbench

- [ ] 4.1 Добавить вкладки "Sessions"/"Files" в левую панель, состояние — `activeSidebarTab` в `CodeLabShellState`
- [ ] 4.2 Подключить `AcpDirectoryTree` к `WorkspaceFileReader` через use case/кубит
- [ ] 4.3 Добавить иконку предпросмотра к tool call карточкам в транскрипте/инспекторе, открывающую `AcpFilePreviewPanel` с provenance "tool call"
- [ ] 4.4 Подключить клик по файлу в дереве к `AcpFilePreviewPanel` с provenance "disk"
- [ ] 4.5 Реализовать обновление панели по "Following" при новых `ToolCallLocation` в session update

## 5. Тесты

- [ ] 5.1 Widget-тест: открытие preview из tool call показывает контент агента и highlight диапазона
- [ ] 5.2 Widget-тест: открытие preview из дерева показывает контент с диска и метку "read directly from disk"
- [ ] 5.3 Widget-тест: файл сверх лимита размера показывает сообщение вместо контента
- [ ] 5.4 Widget-тест: переключение Sessions/Files сохраняет активную вкладку при пересборке виджета
- [ ] 5.5 Widget-тест: Following обновляет панель при новой `ToolCallLocation`, не показывается для disk-source

## 6. Проверка

- [ ] 6.1 `fvm dart run melos run format`
- [ ] 6.2 `fvm dart run melos run analyze`
- [ ] 6.3 `fvm dart run melos run test`
