# CodeLab — канвас Claude Design

Экспорт канваса UI/UX из Claude Design: макеты `codelab_desktop` (десктоп, планшет, смартфон, светлая и тёмная темы), `codelab_cli` (TUI, REPL, headless), графы навигации, покрытие целей паритета и живой прототип.

Экспорт снят 2026-11-20 и обновлён 2026-11-21 с опубликованной версии канваса (первый экспорт — 2026-10-29, предыдущий — 2026-11-12). В этот экспорт вошли правовые документы (`TERMS.md`, D-29, §12.7.7а): шаг onboarding 07a, страница настроек Legal 32–35 и состояния поиска 35a на десктопе, P13–P16 на смартфоне, T7–T10 на планшете и граф навигации планшета. Legal стал последним пунктом группы App в панели настроек всех страниц. Позже в тот же день онбординг десктопа получил все четыре шага: к 07 (Permissions) и 07a (Privacy) добавились 07b (What CodeLab does) и 07c (Choose a model), шаги связаны кнопками Back и Next, а подсказка 07a ведёт в Settings › Legal. На странице графов к ним добавился граф первого запуска `NavOnboarding`. Затем все экраны онбординга встали в один ряд «Первый запуск» в порядке прохождения, а мастер провайдера получил собственные экраны 07c.1–07c.4 и состояние 07c.5. Потом онбординг появился у смартфона (P17–P20, мастер P11a–P11d вокруг P11) и планшета (T11–T14, мастер T13a–T13e) с ограничениями профиля `mobile`: команд нет, ключ — Keychain или «No key». К ним добавились экраны отказа проверки: P11e–P11h и T13f–T13i, Review без проверки: P11i и T13j, и шаг 3 после такого сохранения: P19b и T13k. У CLI к основному пути C5 добавились остальные исходы первого запуска: C5a–C5d. Для планшета появился граф первого запуска `NavTabletOnboarding`. У панели Protocol появилась вкладка Log — 18a (она же в графе `NavApp`), а затем та же вкладка на планшете — T15, а к ней вкладка Frames — T15a; обе добавлены в граф `NavTablet`. У смартфона панель Protocol открывается отдельными экранами P21–P21c, они же добавлены в граф `NavPhone`. У CLI панели Protocol нет: кадры ACP показывает headless-экран C17, он есть и в графе `NavCli`. Тогда же у смартфона и планшета появились тёмные темы — страницы «Смартфон — тёмная тема» и «Планшет — тёмная тема». Канвас переехал в Claude и теперь опубликован как артефакт типа «Design»; отдельный Claude Design (claude.ai/design) закрывается 14 декабря 2026 года. Ссылка на канвас приватная и в репозиторий намеренно не попадает, как и у [`../ui-canvas`](../ui-canvas/README.md). Если канвас поменялся, файлы здесь надо экспортировать заново: правки в этом каталоге обратно в канвас не уходят.

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

Для каждого светлого артборда приложения (страница «Светлая тема», 52 файла) есть тёмная копия `<Имя>-dark.dc.html` на странице «Тёмная тема», кроме `TranscriptRows` и неутверждённого варианта `SubagentsAlt`. Так же устроены экраны смартфона и планшета: у каждого есть `<Имя>-dark.dc.html` на страницах «Смартфон — тёмная тема» и «Планшет — тёмная тема». Графы навигации не тематизируются, тёмных копий у них нет.

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
| `OnboardingWelcome.dc.html` | 07b Первый запуск — шаг 1 What CodeLab does: папка проекта, одобрения, своя модель и ключ, встроенный агент (D-11, §12.4.9) |
| `Onboarding.dc.html` | 07 Первый запуск — шаг 2 Permissions |
| `OnboardingModel.dc.html` | 07c Первый запуск — шаг 3 Choose a model: пресеты провайдеров, кнопка открывает мастер 06; шаг пропускается при `ProviderReady` |
| `OnbWizardUrl.dc.html` | 07c.1 Первый запуск — мастер провайдера поверх шага 3: Base URL из пресета (§12.4.4, шаг 2) |
| `OnbWizardKey.dc.html` | 07c.2 Мастер: ключ в хранилище секретов, переменная окружения или без ключа (§12.4.4, шаг 3) |
| `OnbWizardModel.dc.html` | 07c.3 Мастер: проверка прошла, выбор модели с фильтром и ручным вводом (§12.4.4, шаги 4 и 6); отказ проверки — 06 |
| `OnbWizardReview.dc.html` | 07c.4 Мастер: проверка плана, модель по умолчанию, «This project only», Save (§12.4.4, шаг 7) |
| `OnboardingModelDone.dc.html` | 07c.5 Первый запуск — шаг 3 после Save: провайдер подключён, Next ведёт на 07a |
| `OnboardingPrivacy.dc.html` | 07a Первый запуск — шаг 4 Privacy: что уходит с компьютера, ссылки на политику и условия, принимать нечего (D-11, D-29) |
| `Boot.dc.html` | 08 Сторож запуска — диагностика |
| `Narrow.dc.html` | 09 Узкая раскладка < 900 px |
| `Appearance.dc.html` | 10 Настройки — Appearance |
| `Projects.dc.html` | 11 Выбор проекта — недавние проекты, профиль |
| `Palette.dc.html` | 12 Палитра команд — Ctrl+K |
| `Composer.dc.html` | 13 Меню композера — режим, модель, `/`, `@`, очередь |
| `History.dc.html` | 14 История сессии — панель Branches, откат |
| `Ask.dc.html` | 15 Диалог ask, одобрение веб-запросов и критичных команд |
| `Agents.dc.html` | 16 Панель Agents v1 — список субагентов сессии, ожидание одобрения, дерево шагов выбранного (change `add-subagents-and-tasks`, D33); Stop, транскрипт потомка, фоновые задачи и a2a — после 1.0 |
| `Usage.dc.html` | 17 Панель Usage |
| `Inspector.dc.html` | 18 Панель Protocol — вкладка Frames: кадры JSON-RPC всего соединения, детали кадра, секреты замаскированы (R-23) |
| `InspectorLog.dc.html` | 18a Панель Protocol — вкладка Log: тот же буфер, что у `/logs` и Expand; поиск, категория, уровень, сессия; детали записи с полями корреляции и переходом к кадру по `request_id` |
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
| `Subagents.dc.html` | 30 Субагенты в ленте — компактный вид: свёрнутые агенты, тихие строки задач, вопрос с путём (change `add-subagents-and-tasks`, D27) |
| `SubagentsAlt.dc.html` | 30a Вариант, не утверждён — список задач под последним сообщением |
| `TaskList.dc.html` | 31 Строки агентов и список задач — все состояния |
| `Legal.dc.html` | 32 Настройки › Legal — Privacy policy (`PRIVACY.md`, D-18) |
| `Terms.dc.html` | 33 Настройки › Legal — Terms of use (`TERMS.md`, D-29, §12.7.7а) |
| `License.dc.html` | 34 Настройки › Legal — License: краткое содержание MIT и полный текст `LICENSE` |
| `Notices.dc.html` | 35 Настройки › Legal — Third-party notices: записи реестра и лицензии пакетов с поиском (D13 `add-app-general-page`, §12.7.7а) |
| `NoticesSearch.dc.html` | 35a Поиск по пакетам — состояния «M of N» с подсветкой и «No packages match» |
| `NoticesMatch.dc.html` | 35b Настройки › Legal — Third-party notices, поиск: полноэкранное состояние «M of N» |
| `NoticesEmpty.dc.html` | 35c Настройки › Legal — Third-party notices, поиск: полноэкранное состояние «No packages match» |

### codelab_cli

| Файл | Что показывает |
|---|---|
| `CliTui.dc.html` | C1 TUI — транскрипт, строки инструментов, дифф, строка статуса |
| `CliApproval.dc.html` | C2 TUI — зона одобрения |
| `CliInput.dc.html` | C3 TUI — композер, `@`-дополнение, вложения |
| `CliRepl.dc.html` | C4 Построчный REPL (ansi) |
| `CliSetup.dc.html` | C5 Первый запуск — мастер провайдера |
| `CliSetupUnauthorized.dc.html` | C5a Первый запуск — ключ не принят (401): ввести ключ снова, Retry, Cancel (§12.4.4, шаги 4–5) |
| `CliSetupUnreachable.dc.html` | C5b Первый запуск — сервер недоступен: «Save without check» с подтверждением, модель вручную, «Not verified: timeout» |
| `CliSetupKeyMissing.dc.html` | C5c Первый запуск — провайдер без ключа: мастер не запускается, три случая ключа (§12.4.3, шаг 4) |
| `CliSetupNoTty.dc.html` | C5d Первый запуск без мастера: `-p` без провайдера и битый конфиг — код 64, `-p` без ключа — код 1 (SETUP-7) |
| `CliTheme.dc.html` | C6 Выбор темы `/theme` |
| `CliSessions.dc.html` | C7 `/sessions`, `/resume`, `/rewind`, `/fork` |
| `CliPickers.dc.html` | C8 Slash-меню, `/model`, `/mode`, `/agents` |
| `CliTasks.dc.html` | C9 Доска задач и субагентов |
| `CliStatus.dc.html` | C10 `/status` и `/usage` |
| `CliMcp.dc.html` | C11 `/mcp` и `/tools` |
| `CliStates.dc.html` | C12 Ask, ошибки, переподключение |
| `CliSettings.dc.html` | C13 `/settings` |
| `CliHeadless.dc.html` | C14 Headless: `-p`, stream-json, коды выхода |
| `CliTrace.dc.html` | C17 Headless: трасса протокола — строки `acp` в stream-json с `--include-acp`, `--trace-file`, код 64 без stream-json (§12.5; флаги change `add-cli-stream-json` ещё не реализованы) |
| `CliSwitch.dc.html` | C15 TUI — несколько открытых сессий, переключатель (U-37) |
| `CliAgents.dc.html` | C16 TUI — строки агентов, вложенные шаги, список задач (change `add-subagents-and-tasks`, Q8) |

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
| `PhoneWizard.dc.html` | P11 Мастер провайдера — Check: проверка адреса и ключа |
| `PhoneStates.dc.html` | P12 Состояния |
| `PhoneProtocol.dc.html` | P21 Панель Protocol — вкладка Frames отдельным экраном из P6 › Panes: список кадров в две строки, фильтры Requests, Notifications, Errors only и сессия; Pause, Clear, Export… — в меню «…» |
| `PhoneProtocolFrame.dc.html` | P21a Protocol — детали кадра: ответ с ошибкой −32603 на запрос id 5, JSON, переход «Show record in Log» |
| `PhoneProtocolLog.dc.html` | P21b Protocol — вкладка Log: записи в две строки, фильтры категории, уровня и сессии |
| `PhoneProtocolRecord.dc.html` | P21c Protocol — запись журнала: поля корреляции столбиком, `prompt` замаскирован, переход «Show frame in Frames» |
| `PhoneLegal.dc.html` | P13 Настройки › Legal — Privacy policy |
| `PhoneNotices.dc.html` | P14 Legal — Third-party notices, поиск по пакетам: состояние «M of N» с подсветкой |
| `PhoneNoticesEmpty.dc.html` | P14a Legal — Third-party notices, поиск: состояние «No packages match» с кнопкой «Clear search» |
| `PhoneTerms.dc.html` | P15 Legal — Terms of use |
| `PhoneLicense.dc.html` | P16 Legal — License |
| `PhoneOnbWelcome.dc.html` | P17 Первый запуск — шаг 1 What CodeLab does: папка Documents, одобрения, своя модель; shell на устройстве нет (D-11, §12.8.2) |
| `PhoneOnbPermissions.dc.html` | P18 Первый запуск — шаг 2 Permissions: «Run commands» — «Not here» |
| `PhoneOnbModel.dc.html` | P19 Первый запуск — шаг 3 Choose a model: пресеты, кнопка открывает мастер P11a |
| `PhoneWizardUrl.dc.html` | P11a Мастер провайдера — Base URL |
| `PhoneWizardKey.dc.html` | P11b Мастер провайдера — ключ: Keychain или «No key», переменной окружения нет (§12.8.4, шаг 9) |
| `PhoneWizardModel.dc.html` | P11c Мастер провайдера — выбор модели |
| `PhoneWizardReview.dc.html` | P11d Мастер провайдера — проверка плана и Save |
| `PhoneWizardFailKey.dc.html` | P11e Мастер провайдера — отказ проверки: ключ не принят (401), Back → P11b (§12.4.4, шаги 4–5) |
| `PhoneWizardFailNet.dc.html` | P11f Мастер — отказ проверки: сервер недоступен или таймаут; Retry, Back → P11a, «Save without check…» |
| `PhoneWizardSkip.dc.html` | P11g Мастер — подтверждение «Save without check» |
| `PhoneWizardManual.dc.html` | P11h Мастер — модель и окно контекста вручную, «Not verified: timeout» |
| `PhoneWizardReviewUnverified.dc.html` | P11i Мастер — Review с предупреждением «Not verified: timeout» после «Save without check» |
| `PhoneOnbModelDone.dc.html` | P19a Первый запуск — шаг 3 после Save: провайдер подключён |
| `PhoneOnbModelUnverified.dc.html` | P19b Первый запуск — шаг 3 после сохранения без проверки: метка и плашка «Not verified», Next → P20 |
| `PhoneOnbPrivacy.dc.html` | P20 Первый запуск — шаг 4 Privacy: ссылки на P13 и P15, «Start using CodeLab» → P1 |

### Планшет

| Файл | Что показывает |
|---|---|
| `TabletWorkbench.dc.html` | T1 Планшет, альбомная — workbench |
| `TabletPortrait.dc.html` | T2 Планшет, портретная — узкая раскладка (D-21) |
| `TabletSettings.dc.html` | T3 Планшет — настройки (master–detail) |
| `TabletFiles.dc.html` | T4 Планшет — файлы и просмотр |
| `TabletPalette.dc.html` | T5 Планшет — палитра команд |
| `TabletProtocolLog.dc.html` | T15 Планшет — панель Protocol, вкладка Log в выдвижном доке (как 18a): открывается из палитры или Cmd+Shift+I, Category — фильтром, касания ≥ 44 px, Export… — в системное меню «Поделиться» |
| `TabletProtocolFrames.dc.html` | T15a Планшет — панель Protocol, вкладка Frames (как 18): фильтры Requests, Notifications, Errors only и сессия, выделен ответ с ошибкой −32603 на запрос id 5; переходы в T15 и обратно через «Show frame in Frames» и «Show record in Log» |
| `TabletSplit.dc.html` | T6 Планшет — split view при 1366 px |
| `TabletLegal.dc.html` | T7 Планшет — настройки › Legal, Privacy policy (master–detail) |
| `TabletTerms.dc.html` | T8 Планшет — Legal › Terms of use |
| `TabletLicense.dc.html` | T9 Планшет — Legal › License |
| `TabletNotices.dc.html` | T10 Планшет — Legal › Third-party notices |
| `TabletNoticesMatch.dc.html` | T10a Планшет — Third-party notices, поиск: состояние «M of N» с подсветкой (записи реестра свёрнуты) |
| `TabletNoticesEmpty.dc.html` | T10b Планшет — Third-party notices, поиск: состояние «No packages match» с кнопкой «Clear search» |
| `TabletOnbWelcome.dc.html` | T11 Планшет — первый запуск, шаг 1 What CodeLab does |
| `TabletOnbPermissions.dc.html` | T12 Планшет — шаг 2 Permissions, команд нет (профиль `mobile`) |
| `TabletOnbModel.dc.html` | T13 Планшет — шаг 3 Choose a model |
| `TabletOnbWizardUrl.dc.html` | T13a Планшет — мастер провайдера диалогом поверх T13: Base URL |
| `TabletOnbWizardKey.dc.html` | T13b Планшет — мастер: ключ в Keychain или «No key» |
| `TabletOnbWizardModel.dc.html` | T13c Планшет — мастер: проверка прошла, выбор модели |
| `TabletOnbWizardReview.dc.html` | T13d Планшет — мастер: проверка плана и Save |
| `TabletOnbWizardFailKey.dc.html` | T13f Планшет — мастер: ключ не принят (401) |
| `TabletOnbWizardFailNet.dc.html` | T13g Планшет — мастер: сервер недоступен или таймаут, «Save without check…» |
| `TabletOnbWizardSkip.dc.html` | T13h Планшет — мастер: подтверждение «Save without check» |
| `TabletOnbWizardManual.dc.html` | T13i Планшет — мастер: модель вручную, «Not verified: timeout» |
| `TabletOnbWizardReviewUnverified.dc.html` | T13j Планшет — мастер: Review с предупреждением «Not verified: timeout» |
| `TabletOnbModelDone.dc.html` | T13e Планшет — шаг 3 после Save: провайдер подключён |
| `TabletOnbModelUnverified.dc.html` | T13k Планшет — шаг 3 после сохранения без проверки, «Not verified» |
| `TabletOnbPrivacy.dc.html` | T14 Планшет — шаг 4 Privacy, «Start using CodeLab» → T1 |

### Навигация, покрытие и прототип

| Файл | Что показывает |
|---|---|
| `NavApp.dc.html` | Граф навигации `codelab_desktop`; панель Protocol — двумя карточками, 18 Frames и 18a Log, связанными вкладкой |
| `NavCli.dc.html` | Граф навигации `codelab_cli`, с C17 как вариантом вывода C14 |
| `NavOnboarding.dc.html` | Граф первого запуска app: проверка `onboarding_done`, шаги 07b → 07 → 07c → 07a, пропуск шага 3 при `ProviderReady`, шаги мастера провайдера 06, переходы в Legal 32/33 (D-11, §12.4.9) |
| `NavPhone.dc.html` | Граф навигации смартфона, с группой панели Protocol: P6 › Panes › Protocol → P21, вкладки P21 ↔ P21b, детали P21a и P21c и переходы между ними |
| `NavTablet.dc.html` | Граф навигации планшета, с панелью Protocol в группе дока: ⌘⇧I или палитра → T15a Frames, вкладки T15a ↔ T15 Log |
| `NavTabletOnboarding.dc.html` | Граф первого запуска планшета: `onboarding_done`, шаги T11–T14, пропуск шага 3 при `ProviderReady`, мастер T13a–T13e, отказы проверки T13f–T13k, переходы в Legal T7/T8 (D-11, §12.4.4, §12.8.5) |
| `Coverage.dc.html` | Покрытие целей: цель → экран |
| `Prototype.dc.html` | Живой прототип: десктоп, планшет, смартфон; темы, состояния соединения, раскладка (A13, §12.8) |
