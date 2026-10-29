# CodeLab — канвас Claude Design

Экспорт канваса UI/UX из Claude Design: макеты `codelab_desktop` (десктоп, планшет, смартфон, светлая и тёмная темы), `codelab_cli` (TUI, REPL, headless), графы навигации, покрытие целей паритета и живой прототип.

Экспорт снят 2026-10-29 с опубликованной версии канваса. Ссылка на канвас приватная и в репозиторий намеренно не попадает, как и у [`../ui-canvas`](../ui-canvas/README.md). Если канвас поменялся, файлы здесь надо экспортировать заново: правки в этом каталоге обратно в канвас не уходят.

Канвас — проектный референс. При расхождении источник истины — документы `docs/architecture/proposals/dart-agent-and-clients/` (§12.x) и `openspec/`; номера целей (D-28, U-37, T-22 …) — из `agent-parity-goals.md`.

## Состав

| Файл | Назначение |
|---|---|
| `*.dc.html` | Артборды. Каждый — отдельная страница; `*-dark.dc.html` — обёртки, которые импортируют светлый артборд с `theme="dark"` |
| `canvas.json` | Раскладка канваса: страницы, позиции и размеры артбордов, заметки. Для просмотра отдельных файлов не нужен |
| `fluent.css` | Общие стили Fluent для артбордов приложения |
| `tui.css` | Общие стили терминала для артбордов `codelab_cli` |

## Как смотреть

Артборды подключают рантайм `./support.js` — это `dc-runtime.js` из Claude Design. Он не наш код и в репозиторий не кладётся (AGENTS.md §5, сторонний код), поэтому `support.js` здесь в `.gitignore`.

1. Скачайте `artifact-type/dc-runtime.js` из канваса и положите его сюда как `support.js`.
2. Запустите локальный сервер: `dc-import` загружает соседние файлы, поэтому `file://` не подходит.

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs/design/claude-design
```

3. Откройте `http://127.0.0.1:8765/Main.dc.html` или любой другой артборд. Прототип — `Prototype.dc.html`.

## Артборды

Для каждого светлого артборда приложения (страница «Светлая тема», 32 файла) есть тёмная копия `<Имя>-dark.dc.html` на странице «Тёмная тема», кроме `TranscriptRows`.

### Приложение — светлая тема

| Файл | Что показывает |
|---|---|
| `TranscriptRows.dc.html` | 00a Строки транскрипта — все виджеты и состояния |
| `Components.dc.html` | 00 fluent_ui — компоненты и карта экранов |
| `Main.dc.html` | 01 Workbench — сайдбар по проектам, сессия, док инструментов |
| `Turn.dc.html` | 02 Идущий ход — панели Agents и Plan |
| `Files.dc.html` | 03 Панель Files — дерево и просмотр в доке |
| `Sessions.dc.html` | 04 Поиск сессий в сайдбаре, сессия только для чтения |
| `Providers.dc.html` | 05 Настройки — Providers |
| `Mcp.dc.html` | 05b Настройки — MCP-серверы |
| `Wizard.dc.html` | 06 Мастер провайдера — проверка перед сохранением |
| `Onboarding.dc.html` | 07 Первый запуск |
| `Boot.dc.html` | 08 Сторож запуска — диагностика |
| `Narrow.dc.html` | 09 Узкая раскладка < 900 px |
| `Appearance.dc.html` | 10 Настройки — Appearance |
| `Projects.dc.html` | 11 Выбор проекта — недавние проекты, профиль |
| `Palette.dc.html` | 12 Палитра команд — Ctrl+K |
| `Composer.dc.html` | 13 Меню композера — режим, модель, `/`, `@`, очередь |
| `History.dc.html` | 14 История сессии — панель Branches, откат |
| `Ask.dc.html` | 15 Диалог ask, одобрение веб-запросов и критичных команд |
| `Agents.dc.html` | 16 Панель Agents — субагенты и задачи |
| `Usage.dc.html` | 17 Панель Usage |
| `Inspector.dc.html` | 18 Панель Protocol — кадры и лог |
| `States.dc.html` | 19 Состояния соединения и ошибок |
| `Connection.dc.html` | 20 Настройки — Connection |
| `AddProfile.dc.html` | 20a Настройки — добавление профиля подключения (§12.4.9) |
| `Modes.dc.html` | 21 Настройки — агенты и режимы |
| `Permissions.dc.html` | 22 Настройки — разрешения и инструменты |
| `Redaction.dc.html` | 23 Настройки — маскирование |
| `Extensions.dc.html` | 24 Настройки — навыки и расширения |
| `CodeWeb.dc.html` | 25 Настройки — код и веб |
| `General.dc.html` | 26 Настройки — General |
| `Keyboard.dc.html` | 27 Настройки — клавиатура |
| `Terminal.dc.html` | 28 Панель Terminal (D-28) |
| `SplitView.dc.html` | 29 Split view — две сессии рядом |

### codelab_cli

| Файл | Что показывает |
|---|---|
| `CliTui.dc.html` | C1 TUI — транскрипт, строки инструментов, дифф, строка статуса |
| `CliApproval.dc.html` | C2 TUI — зона одобрения |
| `CliInput.dc.html` | C3 TUI — композер, `@`-дополнение, вложения |
| `CliRepl.dc.html` | C4 Построчный REPL (ansi) |
| `CliSetup.dc.html` | C5 Первый запуск — мастер провайдера |
| `CliTheme.dc.html` | C6 Выбор темы `/theme` |
| `CliSessions.dc.html` | C7 `/sessions`, `/resume`, `/rewind`, `/fork` |
| `CliPickers.dc.html` | C8 Slash-меню, `/model`, `/mode`, `/agents` |
| `CliTasks.dc.html` | C9 Доска задач и субагентов |
| `CliStatus.dc.html` | C10 `/status` и `/usage` |
| `CliMcp.dc.html` | C11 `/mcp` и `/tools` |
| `CliStates.dc.html` | C12 Ask, ошибки, переподключение |
| `CliSettings.dc.html` | C13 `/settings` |
| `CliHeadless.dc.html` | C14 Headless: `-p`, stream-json, коды выхода |
| `CliSwitch.dc.html` | C15 TUI — несколько открытых сессий, переключатель (U-37) |

### Смартфон

| Файл | Что показывает |
|---|---|
| `PhoneSessions.dc.html` | P1 Сессии (главный экран) |
| `PhoneChat.dc.html` | P2 Сессия |
| `PhoneApproval.dc.html` | P3 Одобрение и идущий ход |
| `PhoneComposer.dc.html` | P4 Меню композера |
| `PhoneAsk.dc.html` | P5 Ask (T-22) |
| `PhonePane.dc.html` | P6 Навигационная панель |
| `PhoneFiles.dc.html` | P7 Файлы (Documents) |
| `PhoneSettings.dc.html` | P8 Настройки |
| `PhoneConnection.dc.html` | P9 Настройки › Connection |
| `PhoneAddProfile.dc.html` | P9a Connection › добавить WebSocket-агента |
| `PhoneProviders.dc.html` | P10 Настройки › Providers |
| `PhoneWizard.dc.html` | P11 Первый запуск — мастер провайдера |
| `PhoneStates.dc.html` | P12 Состояния |

### Планшет

| Файл | Что показывает |
|---|---|
| `TabletWorkbench.dc.html` | T1 Планшет, альбомная — workbench |
| `TabletPortrait.dc.html` | T2 Планшет, портретная — узкая раскладка (D-21) |
| `TabletSettings.dc.html` | T3 Планшет — настройки (master–detail) |
| `TabletFiles.dc.html` | T4 Планшет — файлы и просмотр |
| `TabletPalette.dc.html` | T5 Планшет — палитра команд |
| `TabletSplit.dc.html` | T6 Планшет — split view при 1366 px |

### Навигация, покрытие и прототип

| Файл | Что показывает |
|---|---|
| `NavApp.dc.html` | Граф навигации `codelab_desktop` |
| `NavCli.dc.html` | Граф навигации `codelab_cli` |
| `NavPhone.dc.html` | Граф навигации смартфона |
| `Coverage.dc.html` | Покрытие целей: цель → экран |
| `Prototype.dc.html` | Живой прототип: десктоп, планшет, смартфон; темы, состояния соединения, раскладка (A13, §12.8) |
