## Purpose

Десктопный workbench UI на базе Fluent: layout, организация виджетов `acp_ui` по Atomic Design, паттерны взаимодействия, нужные agent workbench (сайдбар сессий, approvals, режимы отображения, командная палитра и т. д.), и клавиатурная эргономика.
## Requirements
### Requirement: Десктопный workbench на Fluent
CodeLab SHALL использовать `fluent_ui` как базовый Flutter UI framework и SHALL NOT использовать Material/Cupertino как базовый design framework.

#### Scenario: Проверяется UI framework
- **WHEN** анализируются UI-пакеты
- **THEN** публичные UI-компоненты CodeLab построены на `fluent_ui`

#### Scenario: Требуется совместимый импорт
- **WHEN** сторонний пакет требует совместимости с Material/Cupertino
- **THEN** импорт изолирован и не определяет публичный UI-стиль CodeLab

### Requirement: Layout workbench
CodeLab SHALL предоставлять десктопный layout workbench с командной панелью, панелью сессий, областью transcript/prompt и инспектором.

#### Scenario: Открывается основное рабочее пространство
- **WHEN** пользователь открывает CodeLab
- **THEN** первый экран — рабочий workbench клиента, а не маркетинговая страница

#### Scenario: Узкое окно адаптируется
- **WHEN** доступная ширина ограничена
- **THEN** панель сессий сжимается, а инспектор может сворачиваться, не скрывая prompt composer или состояние отмены

### Requirement: Организация виджетов по Atomic Design
CodeLab SHALL организовывать переиспользуемые виджеты `acp_ui` по `atomics`, `molecules` и `organisms`.

#### Scenario: Добавляется atomic-виджет
- **WHEN** реализуется минимальный переиспользуемый control
- **THEN** он размещается в `atomics`

#### Scenario: Добавляется панель workflow
- **WHEN** реализуется крупный блок workflow, такой как transcript, approval или сайдбар сессий
- **THEN** он размещается в `organisms`

### Requirement: Паттерны взаимодействия agent workbench
CodeLab SHALL поддерживать сайдбар сессий/задач, control strip области prompt, селектор режима разрешений, plan mode, inline approvals, режимы отображения, progress checklist, inspector-first детали, командную палитру или slash-команды, review-first изменения, изоляцию сессий, компактный transcript и context indicators.

#### Scenario: Показывается ожидающий approval
- **WHEN** агент запрашивает разрешение во время prompt turn
- **THEN** CodeLab отображает approval как часть записи transcript того tool call, к которому он относится (не как отдельную закреплённую панель вне ленты), с риском, причиной, командой/cwd/diff, если доступны — интерактивно, до момента решения

#### Scenario: Несколько approval ожидают решения одновременно
- **WHEN** активный prompt turn имеет более одного `ApprovalRequest` со статусом pending (параллельные tool calls)
- **THEN** CodeLab отображает каждый approval интерактивно на месте своей записи transcript, независимо от остальных — ни один не скрывает и не блокирует отображение другого

#### Scenario: Approval остаётся в истории после решения
- **WHEN** пользователь выбирает опцию для approval, или turn отменяется с этим approval в статусе `cancelled`
- **THEN** CodeLab не удаляет запись из transcript и не сбрасывает её к состоянию до approval — запись схлопывается в компактный маркер принятого решения (например, выбранная опция или "Cancelled"), остающийся видимым в истории

#### Scenario: Лента автоскроллится к новому approval
- **WHEN** появляется новый pending approval, и пользователь не проскроллил ленту transcript вверх (не читает более раннюю историю)
- **THEN** CodeLab прокручивает ленту так, чтобы новая approval-запись была видна, не требуя от пользователя искать её вручную

#### Scenario: Клавиатурные approve/reject применяются к самому раннему pending approval
- **WHEN** несколько approval активного turn ожидают решения одновременно, и пользователь использует клавиатурный shortcut approve/reject
- **THEN** CodeLab применяет это решение к approval с наименьшим `requestedAt` среди pending — не к произвольному или к тому, что ближе к текущей scroll-позиции

#### Scenario: Меняется режим отображения
- **WHEN** пользователь выбирает `summary`, `normal` или `verbose`
- **THEN** transcript и детали tool call меняют детализацию, не теряя данных

#### Scenario: Содержательный текст записи не обрезается ни в одном режиме отображения
- **WHEN** запись transcript содержит содержательный текст (реплика пользователя, ответ агента, причина approval-запроса или диагностическое сообщение) длиннее, чем помещается в отведённое по умолчанию число строк
- **THEN** CodeLab отображает этот текст полностью независимо от выбранного `viewMode` — обрезка по числу строк применяется только к вспомогательным меткам и к детализации tool call, но не к самому содержательному тексту записи

#### Scenario: Переключение сессий показывает только состояние этой сессии
- **WHEN** пользователь переключает активную сессию (через сайдбар или создав новую)
- **THEN** CodeLab показывает собственные transcript, записи инспектора и pending approval этой сессии (если есть) — никогда не состояние, оставшееся от предыдущей активной сессии

### Requirement: Tool call появляется в transcript в хронологической позиции
CodeLab SHALL добавлять запись transcript для каждого tool call, полученного в активном или последнем prompt turn, в позицию потока, соответствующую моменту его создания агентом (`SessionUpdate.toolCall`) относительно окружающих текстовых записей — а не только показывать его в инспекторе.

#### Scenario: Tool call между двумя текстовыми ответами
- **WHEN** агент присылает текстовый чанк, затем `SessionUpdate.toolCall`, затем ещё один текстовый чанк
- **THEN** CodeLab показывает в transcript три записи в этом же порядке: текст, tool call, текст

#### Scenario: Обновление статуса tool call не создаёт вторую запись
- **WHEN** после `SessionUpdate.toolCall` для того же `toolCallId` приходит один или более `SessionUpdate.toolCallUpdate`
- **THEN** CodeLab обновляет содержимое и статус уже существующей записи transcript этого tool call, не добавляя новую

### Requirement: Approval options are rendered and bound to shortcuts by kind
CodeLab SHALL carry each approval option's `PermissionOptionKind` (`allow_once`, `allow_always`, `reject_once`, `reject_always`) through to the presentation layer and SHALL bind each kind to a fixed keyboard shortcut, without relying on matching substrings in the option's agent-provided label text.

#### Scenario: Four kinds shown distinctly
- **WHEN** a permission request offers all four standard option kinds
- **THEN** CodeLab shows four distinct options, each bound to its own shortcut, regardless of the exact wording of each option's label

#### Scenario: Non-English or unusual option labels still get shortcuts
- **WHEN** an agent provides an option label that does not contain the words "allow"/"approve"/"reject"/"deny" (e.g. a non-English label)
- **THEN** CodeLab still binds the correct shortcut to that option, based on its `kind`, not its label text

### Requirement: Approval panel offers a collapsed raw input view
CodeLab SHALL show the tool call's raw input in the approval panel behind a collapsed, expand-on-demand disclosure, not always visible by default.

#### Scenario: Raw input is collapsed by default
- **WHEN** an approval panel is shown for a tool call with input data
- **THEN** the raw input is hidden behind a "View raw input" control until the user expands it

### Requirement: Клавиатурный десктопный UX
CodeLab SHALL поддерживать клавиатурную эргономику для отправки prompt, отмены, approve/reject, навигации по инспектору и командной палитры или slash-команд.

#### Scenario: Пользователь отправляет prompt с клавиатуры
- **WHEN** фокус в prompt composer, и пользователь вызывает shortcut отправки
- **THEN** CodeLab отправляет prompt без необходимости взаимодействия с указателем

#### Scenario: Пользователь открывает командную палитру
- **WHEN** пользователь вызывает shortcut командной палитры
- **THEN** CodeLab представляет основные действия, такие как `/new`, `/plan`, `/permissions`, `/logs`, `/compact` и `/reconnect`

### Requirement: Командная палитра открывается и выполняет доступные действия
CodeLab SHALL открывать `AcpCommandPaletteSurface` при вызове shortcut'а командной палитры и SHALL выполнять `/new` (создание сессии) и `/reconnect` (переподключение активного transport) немедленно при выборе, закрывая палитру после этого.

#### Scenario: Открытие командной палитры показывает surface
- **WHEN** пользователь вызывает shortcut командной палитры (`Ctrl/Cmd+K`)
- **THEN** CodeLab показывает `AcpCommandPaletteSurface` поверх workbench

#### Scenario: Закрытие командной палитры
- **WHEN** командная палитра открыта, и пользователь нажимает `Esc` либо выбирает доступную команду
- **THEN** CodeLab скрывает `AcpCommandPaletteSurface` и возвращает фокус клавиатуры workbench

#### Scenario: Выбор /new создаёт сессию
- **WHEN** командная палитра открыта, и пользователь выбирает `/new`
- **THEN** CodeLab создаёт новую сессию через существующий флоу создания сессии и закрывает палитру

#### Scenario: Выбор /reconnect переподключает активный transport
- **WHEN** командная палитра открыта, и пользователь выбирает `/reconnect`
- **THEN** CodeLab вызывает существующий флоу reconnect для активного transport и закрывает палитру

#### Scenario: Выбор /logs раскрывает панель debug-логов
- **WHEN** командная палитра открыта, и пользователь выбирает `/logs`
- **THEN** CodeLab делает панель debug-логов видимой (раскрывая инспектор, если он свёрнут узким layout) и закрывает палитру

### Requirement: Командная палитра открывается inline из prompt composer
CodeLab SHALL открывать командную палитру inline, привязанную над prompt composer и без переноса фокуса клавиатуры с него, когда пользователь вводит `/` как первый символ нового слова в поле ввода composer, и SHALL фильтровать видимые команды вживую по мере того, как пользователь продолжает печатать в composer.

#### Scenario: Слэш в начале слова открывает inline-палитру
- **WHEN** composer пуст, либо курсор находится сразу после пробела, и пользователь вводит `/`
- **THEN** CodeLab показывает командную палитру, привязанную над composer, фокус остаётся в текстовом поле composer

#### Scenario: Слэш внутри слова не открывает палитру
- **WHEN** пользователь вводит `/` сразу после непробельного символа (например, как часть уже набираемого пути или URL)
- **THEN** CodeLab не открывает командную палитру

#### Scenario: Продолжение ввода фильтрует inline-список
- **WHEN** inline-палитра открыта, и пользователь вводит дополнительные символы в composer
- **THEN** CodeLab фильтрует видимые команды по тексту, набранному после триггерного `/`

#### Scenario: Enter выбирает подсвеченную команду, пока открыта inline-палитра
- **WHEN** inline-палитра открыта, и пользователь нажимает `Enter`
- **THEN** CodeLab выбирает текущую подсвеченную команду вместо вставки переноса строки в composer

#### Scenario: Выбор команды из inline-палитры очищает текст триггера
- **WHEN** пользователь выбирает команду из inline-палитры
- **THEN** CodeLab удаляет фрагмент `/word` из текста composer и выполняет команду тем же способом, что и при выборе через палитру, вызванную клавиатурным shortcut'ом

#### Scenario: Удаление триггерного слэша закрывает inline-палитру
- **WHEN** inline-палитра открыта, и пользователь удаляет символ `/`, который её вызвал
- **THEN** CodeLab закрывает inline-палитру, не выполняя никакой команды

### Requirement: Командная палитра честно помечает нереализованные действия как недоступные
CodeLab SHALL представлять `/plan`, `/permissions` и `/compact` в командной палитре как явно недоступные действия, а не тихо ничего не делать при их выборе, пока каждая соответствующая capability (plan mode, селектор режима разрешений, compact transcript) не реализована.

#### Scenario: Выбрана недоступная команда
- **WHEN** командная палитра открыта, и пользователь выбирает `/plan`, `/permissions` или `/compact`
- **THEN** CodeLab показывает команду как disabled/с пометкой «coming soon» и не закрывает палитру, и не выдаёт фиктивную запись диагностики, подразумевающую, что действие завершилось

#### Scenario: Enter на недоступной команде в inline-палитре
- **WHEN** inline-палитра открыта, недоступная команда (`/plan`, `/permissions` или `/compact`) — текущая подсвеченная запись, и пользователь нажимает `Enter`
- **THEN** CodeLab обрабатывает это так же, как любой другой выбор этой команды — палитра остаётся открытой, никакое действие не выполняется, текст composer не меняется

### Requirement: Командная палитра представляет команды, объявленные агентом
CodeLab SHALL представлять команды, объявленные активным агентом через `SessionUpdate.availableCommandsUpdate`, в командной палитре (и в surface `Ctrl/Cmd+K`, и во inline-триггере `/`), визуально отделённые от шести client-native команд, и SHALL NOT вызывать их как метод протокола — выбор одной из них SHALL вставлять `/{name} ` (плюс объявленный input hint, если есть, как placeholder-текст) в prompt composer вместо этого, оставляя пользователю дополнение и отправку как обычного prompt.

#### Scenario: Агент объявляет доступные команды
- **WHEN** активная сессия получает `SessionUpdate.availableCommandsUpdate` с одной или более записями
- **THEN** CodeLab добавляет эти команды в палитру в секции, визуально отделённой от шести client-native команд, не удаляя и не заменяя ни одну client-native команду

#### Scenario: Более позднее обновление заменяет список команд агента
- **WHEN** для активной сессии приходит новый `SessionUpdate.availableCommandsUpdate`
- **THEN** CodeLab заменяет ранее показанные команды агента записями из нового обновления

#### Scenario: Команды агента не объявлены
- **WHEN** активная сессия не получала ни одного `availableCommandsUpdate`
- **THEN** CodeLab показывает в палитре только шесть client-native команд

#### Scenario: Выбрана команда, объявленная агентом
- **WHEN** пользователь выбирает команду, пришедшую из `availableCommandsUpdate`
- **THEN** CodeLab вставляет `/{name} ` (и input hint команды как placeholder-текст, если команда его объявляет) в prompt composer, закрывает палитру и не вызывает никакой метод протокола — пользователь отправляет её сам через обычный флоу prompt

#### Scenario: Переключение сессий показывает собственные команды агента этой сессии
- **WHEN** активная сессия меняется
- **THEN** CodeLab показывает собственные команды агента, объявленные для новой активной сессии — восстановленные из её последнего `availableCommandsUpdate`, если он был, либо пустой список, если не было — но никогда список предыдущей сессии

### Requirement: Композер показывает объявленные агентом config options
CodeLab SHALL показывать в prompt composer по одному селектору на каждый `SessionConfigOption` активной сессии, в порядке, присланном агентом, и SHALL NOT показывать этот ряд, когда `configOptions` активной сессии пуст или отсутствует.

#### Scenario: Агент объявляет config options при создании сессии
- **WHEN** ответ на создание сессии содержит непустой `configOptions`
- **THEN** CodeLab показывает в композере по одному селектору на каждую опцию, с текущим значением (`currentValue`) из ответа

#### Scenario: Агент не объявляет ни одной config option
- **WHEN** активная сессия не имеет ни одной `SessionConfigOption`
- **THEN** CodeLab не показывает ряд селекторов в композере вообще — ни пустым, ни как «coming soon»

#### Scenario: Обновление config options во время сессии
- **WHEN** активная сессия получает `SessionUpdate.configOptionUpdate` с новым списком
- **THEN** CodeLab заменяет ряд селекторов в композере полностью новым списком, включая появление или исчезновение ряда при переходе списка из пустого в непустой и обратно

### Requirement: Выбор значения селектора отправляется агенту
CodeLab SHALL отправлять `session/set_config_option` при выборе пользователем нового значения в селекторе композера и SHALL отражать в чипе значение из ответа агента, а не выбранное пользователем значение напрямую.

#### Scenario: Пользователь выбирает значение из выпадающего списка
- **WHEN** пользователь открывает селектор конфигурации и выбирает один из вариантов `options`
- **THEN** CodeLab отправляет `session/set_config_option` с `configId` и выбранным значением, дожидается ответа и обновляет отображаемое в чипе значение из полученного списка `configOptions`

#### Scenario: Селектор не смешивается с client-side permission mode
- **WHEN** активная сессия объявляет `SessionConfigOption` с `category: "mode"`
- **THEN** CodeLab отображает его название и варианты как есть, присланные агентом, не подставляя названия локальных режимов `readOnly`/`ask`/`plan`/`autoEdits` из `approval-safety` и не смешивая эти два понятия

### Requirement: Workbench честно отражает спонтанную потерю соединения
CodeLab SHALL отражать спонтанную (не инициированную явным `connect()`/`reconnect()`) потерю ACP-соединения как `failed` в UI и SHALL очищать состояние активного запроса, которое больше не может считаться достоверным, вместо того чтобы бесконечно показывать `Connected` и зависший `running` turn.

#### Scenario: Агент падает во время активной сессии
- **WHEN** активное соединение (`connectionStatus == connected`) спонтанно теряется — например, дочерний процесс агента завершается неожиданно
- **THEN** CodeLab переводит `connectionStatus` в `failed`, очищает `pendingApproval`, `isPromptSubmitting`, `canCancel`, `isRespondingToApproval` и `isRespondingToConfigOption`, и записывает диагностику с причиной

#### Scenario: Explicit connect/reconnect failure не задваивается
- **WHEN** пользователь явно вызывает `Connect`/`Reconnect`, и попытка завершается неудачей
- **THEN** CodeLab показывает ровно одну diagnostic-запись об этой неудаче — реакция на спонтанную потерю соединения не создаёт вторую, дублирующую запись для того же события

#### Scenario: История сессии не теряется при потере соединения
- **WHEN** происходит спонтанная потеря соединения
- **THEN** CodeLab сохраняет видимыми `transcriptEntries` уже случившейся сессии — они не считаются недостоверными, в отличие от состояния активного запроса

### Requirement: Границы панелей перетаскиваются мышью
CodeLab SHALL позволять пользователю менять ширину sessions pane и inspector pane перетаскиванием их общей границы с main pane, в десктопном режиме layout, в пределах фиксированных минимума и максимума.

#### Scenario: Перетаскивание границы sessions/main меняет ширину sessions pane
- **WHEN** пользователь перетаскивает разделитель между sessions pane и main pane в десктопном layout
- **THEN** CodeLab меняет ширину sessions pane в реальном времени, следуя за курсором, а main pane заполняет оставшееся пространство

#### Scenario: Перетаскивание границы main/inspector меняет ширину inspector pane
- **WHEN** пользователь перетаскивает разделитель между main pane и inspector pane в десктопном layout
- **THEN** CodeLab меняет ширину inspector pane в реальном времени, следуя за курсором

#### Scenario: Resize ограничен минимальной шириной
- **WHEN** пользователь тянет разделитель к ширине меньше настроенного минимума
- **THEN** CodeLab останавливает сжатие панели на минимальной ширине, никогда не схлопывая её до нуля

#### Scenario: Resize ограничен максимальной шириной
- **WHEN** пользователь тянет разделитель к ширине больше настроенного максимума
- **THEN** CodeLab останавливает рост панели на максимальной ширине, никогда не давая ей поглотить весь main pane

#### Scenario: Курсор показывает перетаскиваемую границу
- **WHEN** курсор наведён на перетаскиваемый разделитель, до начала перетаскивания
- **THEN** CodeLab показывает курсор горизонтального изменения размера

#### Scenario: Изменённые ширины переживают пересборку виджета в рамках запуска
- **WHEN** панель была изменена по размеру, и дерево виджетов workbench пересобирается (например, из-за несвязанного изменения state)
- **THEN** панель сохраняет изменённую ширину, а не исходное значение по умолчанию

### Requirement: Connection profile is edited in a modal dialog
CodeLab SHALL present the transport setup form (profile, command, args, environment for stdio; endpoint and token for WebSocket) inside a modal dialog rather than as a permanently visible panel in the main workbench pane. Working directory ("project") SHALL NOT be a field of this dialog — it is selected independently of the connection, via the "Open Project" picker (see "Project selection is independent of the connection type" below). For stdio, the dialog SHALL additionally present a "Run agent from project directory" toggle, defaulting to on, controlling whether the agent process is spawned with the currently selected project's directory as its OS-level working directory. The dialog SHALL be reachable both from a persistent "Configure connection" affordance in the command bar and from a compact "Configure connection" prompt on the empty/disconnected connection screen — the same label in both places, not two names for one action — and SHALL NOT open automatically on app start.

#### Scenario: Opening the dialog from the command bar
- **WHEN** a session is active (transcript non-empty) and user selects "Configure connection" in the command bar
- **THEN** CodeLab opens the connection setup dialog over the current screen without navigating away from the active session

#### Scenario: Opening the dialog from the empty connection screen
- **WHEN** no transport is connected and user selects "Configure connection" on the connection screen
- **THEN** CodeLab opens the same connection setup dialog, pre-filled with the current transport type and field values

#### Scenario: Dialog does not open unprompted
- **WHEN** CodeLab starts for the first time with no prior connection
- **THEN** the connection setup dialog remains closed until the user explicitly opens it

#### Scenario: Editing fields inside the dialog
- **WHEN** user changes a field value while the dialog is open
- **THEN** CodeLab applies the change to connection state immediately, the same way it does today for the inline form

#### Scenario: Closing the dialog
- **WHEN** user dismisses the dialog (close button or Esc)
- **THEN** CodeLab returns to the workbench with the field values as last edited, without connecting or discarding them

#### Scenario: stdio process runs from the project directory by default
- **WHEN** transport is stdio, the "Run agent from project directory" toggle is on (default), and a project is selected (or none is, falling back to the current process directory)
- **THEN** CodeLab spawns the agent process with that same directory as its OS-level working directory

#### Scenario: stdio process spawn directory can be decoupled from the project
- **WHEN** transport is stdio and the user turns off "Run agent from project directory"
- **THEN** CodeLab spawns the agent process without an explicit working directory override (inherits CodeLab's own process directory), while the selected project's path is still sent as `cwd` in `session/new` for sessions created afterward

### Requirement: Схлопывание потоковых сообщений агента в transcript
CodeLab SHALL отображать подряд идущие потоковые обновления одного и того же рода (`agent_message_chunk` либо `agent_thought_chunk`) в рамках одного prompt turn как единую, дописывающуюся запись transcript, а не как отдельную запись на каждое обновление. CodeLab SHALL начинать новую запись transcript всякий раз, когда между такими обновлениями встречается обновление turn другого рода, либо когда род потокового обновления меняется (сообщение ↔ размышление).

#### Scenario: Агент стримит текст ответа несколькими чанками подряд
- **WHEN** активный prompt turn получает несколько подряд идущих `agent_message_chunk` обновлений без других обновлений turn между ними
- **THEN** CodeLab показывает единственную запись transcript, текст которой дополняется по мере поступления новых чанков, а не отдельную запись на каждый чанк

#### Scenario: Другое обновление turn прерывает серию чанков сообщения
- **WHEN** между двумя `agent_message_chunk` обновлениями одного turn приходит обновление другого рода (например, обновление вызова инструмента)
- **THEN** CodeLab начинает новую запись transcript для текста, пришедшего после этого обновления, не склеивая его с текстом, пришедшим до него

#### Scenario: Род потокового обновления меняется с сообщения на размышление
- **WHEN** подряд идущие потоковые обновления одного turn переключаются с `agent_message_chunk` на `agent_thought_chunk` (или наоборот)
- **THEN** CodeLab начинает новую запись transcript, не склеивая текст разных родов обновления в одну запись

#### Scenario: Turn ещё выполняется, ответ агента ещё не завершён
- **WHEN** prompt turn ещё выполняется и агент уже прислал часть текста ответа через потоковые обновления
- **THEN** CodeLab показывает уже полученную часть текста в соответствующей записи transcript, не дожидаясь завершения turn

### Requirement: Project selection is independent of the connection type
CodeLab SHALL let the user select the working directory ("project") for sessions as an action independent of the transport connection, and SHALL apply the currently selected project to the next session created regardless of whether the active transport is stdio or WebSocket.

#### Scenario: Project applies to a WebSocket session
- **WHEN** CodeLab is connected via WebSocket and the user creates a new session
- **THEN** CodeLab sends the currently selected project's path as `cwd` in `session/new`, the same as it would for stdio

#### Scenario: No project selected falls back to the current process directory
- **WHEN** the user creates a session and no project has been explicitly selected
- **THEN** CodeLab uses the same fallback it uses today (the CodeLab process's own current directory) as the session's `cwd`

#### Scenario: Switching connection does not clear the selected project
- **WHEN** the user reconnects or switches transport type while a project is selected
- **THEN** the selected project remains the same, and is used for the next session created after the switch

### Requirement: "Open Project" offers native browse and recent projects
CodeLab SHALL provide an "Open Project" affordance, reachable from the sessions sidebar, that lets the user pick a project directory via the operating system's native folder-selection dialog, and SHALL show a list of recently opened project directories for one-click reselection.

#### Scenario: Picking a folder via the native dialog
- **WHEN** the user selects "Browse for folder…" in the "Open Project" picker
- **THEN** CodeLab opens the operating system's native folder-selection dialog, and on a folder being chosen, sets it as the selected project

#### Scenario: Selecting a recent project
- **WHEN** the user opens "Open Project" and selects an entry from the recent-projects list
- **THEN** CodeLab sets that path as the selected project without opening the native folder dialog

#### Scenario: Currently selected project is visible without opening the picker
- **WHEN** a project is selected
- **THEN** the sessions sidebar shows that project's name (or path) in the "Open Project" row without requiring the user to open the picker

### Requirement: Recent projects persist across app restarts
CodeLab SHALL remember recently opened project directories across application restarts, on the local machine.

#### Scenario: A newly opened project appears in recents after restart
- **WHEN** the user opens a project directory (via browse or by it becoming the selected project) and then restarts CodeLab
- **THEN** that directory still appears in the "Open Project" recents list

#### Scenario: Recents list has a bound
- **WHEN** the number of distinct opened project directories exceeds the recents list's capacity
- **THEN** CodeLab keeps only the most recently opened entries, dropping the least recently used ones, rather than growing the list without bound

