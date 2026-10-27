## MODIFIED Requirements

### Requirement: Layout workbench
CodeLab SHALL предоставлять десктопный layout workbench из четырёх зон (`dart-agent-and-clients` §12.3 A13, шаг 0): app bar, сайдбар сессий по проектам, панель сессии с лентой и композером, док панелей инструментов справа. Постоянной колонки инспектора и отдельной карточки debug log SHALL NOT быть: их содержимое — панели дока.

#### Scenario: Открывается основное рабочее пространство
- **WHEN** пользователь открывает CodeLab
- **THEN** первый экран — рабочий workbench клиента, а не маркетинговая страница

#### Scenario: Зоны рабочего места
- **WHEN** открыт workbench в окне шириной 1440 px с активной сессией и открытой панелью Plan
- **THEN** сверху app bar, слева сайдбар сессий, в центре панель сессии со своей шапкой, лентой и композером, справа док с вкладкой Plan

#### Scenario: Узкое окно адаптируется
- **WHEN** ширина окна меньше 900 px
- **THEN** сайдбар и док скрыты и открываются поверх контента, а лента и композер занимают всю ширину, не скрывая prompt composer или состояние отмены

### Requirement: Клавиатурный десктопный UX
CodeLab SHALL поддерживать клавиатурную эргономику для отправки prompt, отмены, approve/reject, командной палитры или slash-команд, создания сессии и сворачивания сайдбара.

#### Scenario: Пользователь отправляет prompt с клавиатуры
- **WHEN** фокус в prompt composer, и пользователь вызывает shortcut отправки
- **THEN** CodeLab отправляет prompt без необходимости взаимодействия с указателем

#### Scenario: Пользователь открывает командную палитру
- **WHEN** пользователь вызывает shortcut командной палитры
- **THEN** CodeLab представляет основные действия, такие как `/new`, `/plan`, `/permissions`, `/logs`, `/compact` и `/reconnect`

#### Scenario: Новая сессия с клавиатуры
- **WHEN** соединение установлено, и пользователь нажимает Cmd/Ctrl+N
- **THEN** CodeLab создаёт новую сессию в выбранном проекте и делает её активной

#### Scenario: Сайдбар сворачивается с клавиатуры
- **WHEN** окно шире 900 px, и пользователь нажимает Cmd/Ctrl+B
- **THEN** сайдбар сворачивается, а повторное нажатие разворачивает его; лента и текст композера при этом не теряются

### Requirement: Границы панелей перетаскиваются мышью
CodeLab SHALL позволять пользователю менять ширину сайдбара сессий и дока панелей инструментов перетаскиванием их общей границы с панелью сессии, когда они стоят колонками, в пределах фиксированных минимума и максимума.

#### Scenario: Перетаскивание границы сайдбара меняет его ширину
- **WHEN** пользователь перетаскивает разделитель между сайдбаром и панелью сессии
- **THEN** CodeLab меняет ширину сайдбара в реальном времени, следуя за курсором, а панель сессии заполняет оставшееся пространство

#### Scenario: Перетаскивание границы дока меняет его ширину
- **WHEN** окно шире 1280 px, док открыт колонкой, и пользователь перетаскивает разделитель между панелью сессии и доком
- **THEN** CodeLab меняет ширину дока в реальном времени, следуя за курсором

#### Scenario: Resize ограничен минимальной шириной
- **WHEN** пользователь тянет разделитель к ширине меньше настроенного минимума
- **THEN** CodeLab останавливает сжатие панели на минимальной ширине, никогда не схлопывая её до нуля

#### Scenario: Resize ограничен максимальной шириной
- **WHEN** пользователь тянет разделитель к ширине больше настроенного максимума
- **THEN** CodeLab останавливает рост панели на максимальной ширине, никогда не давая ей поглотить панель сессии

#### Scenario: Курсор показывает перетаскиваемую границу
- **WHEN** курсор наведён на перетаскиваемый разделитель, до начала перетаскивания
- **THEN** CodeLab показывает курсор горизонтального изменения размера

#### Scenario: Ширина дока переживает перезапуск
- **WHEN** пользователь изменил ширину дока и перезапустил CodeLab
- **THEN** док открывается с той же шириной

### Requirement: "Open Project" offers native browse and recent projects
CodeLab SHALL let the user switch projects from the sessions sidebar: recent project directories are shown as collapsed project groups for one-click reselection, and an "Open folder…" item opens the operating system's native folder-selection dialog.

#### Scenario: Picking a folder via the native dialog
- **WHEN** the user selects "Open folder…" in the sessions sidebar
- **THEN** CodeLab opens the operating system's native folder-selection dialog, and on a folder being chosen, sets it as the selected project

#### Scenario: Selecting a recent project
- **WHEN** the user expands a collapsed recent project group in the sidebar
- **THEN** CodeLab sets that path as the selected project without opening the native folder dialog, and that group lists the project's sessions

#### Scenario: Currently selected project is visible without opening a picker
- **WHEN** a project is selected
- **THEN** the sessions sidebar shows that project as an expanded group named after the folder, with the full path available as a tooltip

### Requirement: Debug log — отдельная докнутая панель, не вложенная в Inspector
CodeLab SHALL отображать протокольные записи текущей сессии и debug log в панели Protocol дока инструментов как два отдельных раздела одной панели, а не как постоянные колонки workbench.

#### Scenario: Панель Protocol открывается переключателем
- **WHEN** пользователь нажимает переключатель Protocol в app bar или выбирает `/logs` в палитре
- **THEN** в доке открывается и становится активной вкладка Protocol

#### Scenario: Разделы панели не дублируют друг друга
- **WHEN** пользователь просматривает панель Protocol
- **THEN** раздел протокола показывает только approval/tool-call/protocol-записи текущей сессии, а раздел debug log — только structured-log события; ни одна запись не показана в обоих разделах

#### Scenario: Раздел debug log даёт поиск и фильтр по уровню
- **WHEN** пользователь вводит текст в поле поиска или выбирает минимальный уровень в разделе debug log
- **THEN** список записей ограничивается совпадающими по тексту и/или не ниже выбранного уровня

#### Scenario: Кнопка Expand открывает полноэкранный log viewer
- **WHEN** пользователь нажимает кнопку "Expand" в разделе debug log
- **THEN** CodeLab открывает тот же полноэкранный log viewer, что и раньше

#### Scenario: Селектор типа фильтрует записи по категории, когда их несколько
- **WHEN** в разделе debug log одновременно присутствуют записи двух и более категорий (например, `application` и `protocol`)
- **THEN** CodeLab показывает селектор по типу записи, позволяющий ограничить список одной категорией или снять ограничение

## ADDED Requirements

### Requirement: Layout class follows the window width
CodeLab SHALL choose the workbench layout class only from the window width in logical pixels (`dart-agent-and-clients` §12.8.3):

| Class | Window width |
|---|---|
| phone | < 641 |
| narrow | 641–899 |
| medium | 900–1279 |
| wide | ≥ 1280 |

In `wide` the sidebar and the tool dock SHALL be columns. In `medium` the sidebar SHALL be a column that Cmd/Ctrl+B collapses to icons, and the dock SHALL slide over the transcript. In `narrow` and `phone` both SHALL slide over the content. Changing the class SHALL NOT lose the composer text or the transcript scroll position.

#### Scenario: Thresholds
- **WHEN** the window is 640, 641, 899, 900, 1279 and 1280 px wide
- **THEN** the layout class is phone, narrow, narrow, medium, medium and wide respectively

#### Scenario: Dock as a column only when wide
- **WHEN** the Plan pane is open and the window is resized from 1280 px to 1279 px
- **THEN** the dock changes from a column beside the session pane to a panel that slides over the transcript

#### Scenario: Resizing keeps the draft and the scroll position
- **WHEN** the composer holds unsent text, the transcript is scrolled up, and the window is resized from 1440 px to 820 px and back
- **THEN** the composer holds the same text and the transcript keeps its scroll position

### Requirement: App bar with palette search and connection badge
CodeLab SHALL show an app bar with the app name, a search field labelled "Search or run a command" with the palette shortcut, toggles for the available tool panes, and a connection badge. Activating the search field SHALL open the command palette. The badge SHALL show the connection status; while the connection is lost or failed it SHALL offer Retry, which reconnects, and while disconnected it SHALL offer Connect. The app bar SHALL NOT show the agent binary path.

#### Scenario: Search field opens the palette
- **WHEN** the user clicks the "Search or run a command" field
- **THEN** the command palette opens with focus in its search box

#### Scenario: Badge offers Retry after a lost connection
- **WHEN** the agent process exits while connected
- **THEN** the badge reads "Connection lost" and offers Retry, and choosing Retry starts a reconnect

#### Scenario: Badge while connected
- **WHEN** the connection is established
- **THEN** the badge reads "Connected", no Connect button is shown, and the profile and transport are available in the badge tooltip

### Requirement: Sessions sidebar grouped by project
The sessions sidebar SHALL show, from top to bottom, "New session" with its shortcut, a filter field, a "Projects" section with one group per project, "Open folder…", and "Settings" at the bottom. The selected project's group SHALL be expanded and list its sessions with their status and "Load more sessions"; recent projects SHALL be collapsed groups named after the folder. The filter SHALL narrow the listed sessions by title.

#### Scenario: Groups by project
- **WHEN** the selected project has three sessions and two other projects are in the recent list
- **THEN** the sidebar shows the selected project's group expanded with three sessions and two collapsed groups for the other projects

#### Scenario: Filtering sessions
- **WHEN** the user types "reconnect" into the filter field
- **THEN** only sessions whose title contains "reconnect" (case-insensitive) stay listed

#### Scenario: Session status in the sidebar
- **WHEN** a listed session is running a turn, waiting for approval, failed or not loaded
- **THEN** its row shows the matching status, as in "Sessions sidebar shows live status for background sessions"

### Requirement: Tool dock with closable pane tabs
CodeLab SHALL host tool panes in a dock on the right, with one closable tab per open pane. Each available pane SHALL have a toggle in the app bar that opens it, makes it active, or closes it when it is already active. With no open panes the dock SHALL NOT be shown. The open panes, the active pane and the dock width SHALL persist across restarts. This change SHALL provide the Plan pane (the full plan checklist) and the Protocol pane; a pane without data SHALL NOT be offered.

#### Scenario: Opening and closing a pane
- **WHEN** the user clicks the Plan toggle, then closes the Plan tab
- **THEN** the dock appears with the Plan tab active, and after closing it the dock disappears and the transcript takes the width

#### Scenario: Two panes as tabs
- **WHEN** Plan and Protocol are both open
- **THEN** the dock shows two tabs, and clicking a tab makes that pane active

#### Scenario: Open panes survive a restart
- **WHEN** Plan and Protocol are open with Protocol active, and CodeLab is restarted
- **THEN** the dock opens with both tabs and Protocol active

### Requirement: Session pane header
The session pane SHALL have a header with the session title, a project chip named after the folder of the session's `cwd` with the full path as a tooltip, and a mode chip when the agent publishes a mode config option.

#### Scenario: Header of an active session
- **WHEN** a session titled "Fix reconnect race" in `/work/codelab-app` is active and the agent publishes the mode "standard"
- **THEN** the header shows "Fix reconnect race", a "codelab-app" chip with the tooltip `/work/codelab-app`, and a "standard" chip
