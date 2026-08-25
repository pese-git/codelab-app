## 1. Архитектурное решение (блокирует остальные разделы)

- [ ] 1.1 Подтвердить PTY-стратегию для MVP (design.md рекомендует вариант (b) — `Process.start` без нативного PTY, без новой native-зависимости) — явное решение перед началом реализации, не по умолчанию
- [ ] 1.2 Добавить зависимость `xterm` в `apps/codelab_app/pubspec.yaml`, выполнить `fvm dart run melos bootstrap`
- [ ] 1.3 Если выбран вариант (a) — зафиксировать конкретный PTY-пакет и платформенные ограничения отдельно, до раздела 2

## 2. Infrastructure — terminal process lifecycle

- [ ] 2.1 Создать `TerminalSession`/`TerminalProcessFactory` в `apps/codelab_app/lib/core/platform/` — старт процесса в заданном cwd, потоковый stdin/stdout/stderr, `dispose()` убивает процесс
- [ ] 2.2 Реализовать снимок cwd на момент создания вкладки (не live-привязка к `stdioCwd`)
- [ ] 2.3 Обеспечить kill всех активных terminal-процессов при закрытии приложения

## 3. AcpTerminalPanel (acp_ui)

- [ ] 3.1 Реализовать `AcpTerminalPanel` organism: collapsed/expanded состояния, вкладки, `+` для новой вкладки, закрытие вкладки
- [ ] 3.2 Интегрировать `xterm`-виджет для рендера ANSI/ввода
- [ ] 3.3 Добавить first-open disclosure (approval-safety bypass + no secret redaction)

## 4. Интеграция в workbench

- [ ] 4.1 Добавить collapsible terminal-строку под существующим `Row` в layout workbench (не пятый слот `AcpWorkbenchLayout`)
- [ ] 4.2 Состояние "открыта/закрыта панель" + список вкладок — в `CodeLabShellState` (ephemeral, но переживает пересборку виджета); буфер вывода/процесс — presentation/infrastructure уровень, не в state
- [ ] 4.3 Подключить старт вкладки к текущему `state.stdioCwd`/`WorkingDirectoryProvider`

## 5. Тесты

- [ ] 5.1 Тест: новая вкладка стартует в ожидаемом cwd
- [ ] 5.2 Тест: `cd` внутри терминала не меняет `state.stdioCwd`
- [ ] 5.3 Тест: закрытие вкладки убивает процесс (мок процесса, проверка вызова kill)
- [ ] 5.4 Тест: закрытие приложения убивает все активные terminal-процессы
- [ ] 5.5 Widget-тест: first-open disclosure показывается при первом открытии панели за сессию

## 6. Проверка

- [ ] 6.1 `fvm dart run melos run format`
- [ ] 6.2 `fvm dart run melos run analyze`
- [ ] 6.3 `fvm dart run melos run test`
