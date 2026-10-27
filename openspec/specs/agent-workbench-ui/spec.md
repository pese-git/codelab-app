## Purpose

Десктопный workbench UI на базе Fluent: layout, организация виджетов `codelab_ui` по Atomic Design, паттерны взаимодействия, нужные agent workbench (сайдбар сессий, approvals, режимы отображения, командная палитра и т. д.), и клавиатурная эргономика.
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
CodeLab SHALL организовывать переиспользуемые виджеты `codelab_ui` по `atomics`, `molecules` и `organisms`.

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
CodeLab SHALL открывать `CodeLabCommandPaletteSurface` при вызове shortcut'а командной палитры и SHALL выполнять `/new` (создание сессии) и `/reconnect` (переподключение активного transport) немедленно при выборе, закрывая палитру после этого.

#### Scenario: Открытие командной палитры показывает surface
- **WHEN** пользователь вызывает shortcut командной палитры (`Ctrl/Cmd+K`)
- **THEN** CodeLab показывает `CodeLabCommandPaletteSurface` поверх workbench

#### Scenario: Закрытие командной палитры
- **WHEN** командная палитра открыта, и пользователь нажимает `Esc` либо выбирает доступную команду
- **THEN** CodeLab скрывает `CodeLabCommandPaletteSurface` и возвращает фокус клавиатуры workbench

#### Scenario: Выбор /new создаёт сессию
- **WHEN** командная палитра открыта, и пользователь выбирает `/new`
- **THEN** CodeLab создаёт новую сессию через существующий флоу создания сессии и закрывает палитру

#### Scenario: Выбор /reconnect переподключает активный transport
- **WHEN** командная палитра открыта, и пользователь выбирает `/reconnect`
- **THEN** CodeLab вызывает существующий флоу reconnect для активного transport и закрывает палитру

#### Scenario: Выбор /logs открывает полноэкранный log viewer
- **WHEN** командная палитра открыта, и пользователь выбирает `/logs`
- **THEN** CodeLab открывает полноэкранный log viewer (master-detail, поверх притемнённого workbench) и закрывает палитру

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
CodeLab SHALL представлять `/plan`, `/permissions` и `/compact` в командной палитре как явно недоступные действия, а не тихо ничего не делать при их выборе, пока каждая соответствующая capability (plan mode, селектор режима разрешений, compact transcript) не реализована. Недоступная команда клиента SHALL скрываться из палитры, пока активный агент объявляет команду с тем же именем (сравнение без `/`, с учётом регистра), и SHALL возвращаться, когда новый `availableCommandsUpdate` это имя больше не содержит.

#### Scenario: Выбрана недоступная команда
- **WHEN** командная палитра открыта, и пользователь выбирает `/plan`, `/permissions` или `/compact`
- **THEN** CodeLab показывает команду как disabled/с пометкой «coming soon» и не закрывает палитру, и не выдаёт фиктивную запись диагностики, подразумевающую, что действие завершилось

#### Scenario: Enter на недоступной команде в inline-палитре
- **WHEN** inline-палитра открыта, недоступная команда (`/plan`, `/permissions` или `/compact`) — текущая подсвеченная запись, и пользователь нажимает `Enter`
- **THEN** CodeLab обрабатывает это так же, как любой другой выбор этой команды — палитра остаётся открытой, никакое действие не выполняется, текст composer не меняется

#### Scenario: Команда агента вытесняет одноимённую заглушку
- **WHEN** активный агент объявил команду `compact`
- **THEN** палитра показывает `compact` в секции агента и не показывает недоступную команду клиента `/compact`; `/plan` и `/permissions`, которых агент не объявил, остаются недоступными командами клиента

#### Scenario: Заглушка возвращается
- **WHEN** после команды `compact` агент присылает `availableCommandsUpdate` без неё
- **THEN** палитра снова показывает недоступную команду клиента `/compact`

### Requirement: Командная палитра представляет команды, объявленные агентом
CodeLab SHALL представлять команды, объявленные активным агентом через `SessionUpdate.availableCommandsUpdate`, в командной палитре (и в surface `Ctrl/Cmd+K`, и во inline-триггере `/`), визуально отделённые от команд клиента, и SHALL NOT вызывать их как метод протокола — выбор одной из них SHALL вставлять `/{name} ` (плюс объявленный input hint, если есть, как placeholder-текст) в prompt composer вместо этого, оставляя пользователю дополнение и отправку как обычного prompt, — и для команды с `input`, и без него. Доступные команды клиента (`/new`, `/logs`, `/reconnect`) команды агента SHALL NOT заменять; недоступные заменяют по требованию «Командная палитра честно помечает нереализованные действия как недоступные». Палитра SHALL отбирать команды по введённому запросу нечётким поиском каталога команд kit: сначала команды, имя которых начинается с запроса, затем содержащие его, затем содержащие буквы запроса по порядку, затем совпавшие по названию или описанию.

#### Scenario: Агент объявляет доступные команды
- **WHEN** активная сессия получает `SessionUpdate.availableCommandsUpdate` с одной или более записями
- **THEN** CodeLab добавляет эти команды в палитру в секции, визуально отделённой от команд клиента, не удаляя и не заменяя ни одну доступную команду клиента

#### Scenario: Более позднее обновление заменяет список команд агента
- **WHEN** для активной сессии приходит новый `SessionUpdate.availableCommandsUpdate`
- **THEN** CodeLab заменяет ранее показанные команды агента записями из нового обновления

#### Scenario: Команды агента не объявлены
- **WHEN** активная сессия не получала ни одного `availableCommandsUpdate`
- **THEN** CodeLab показывает в палитре только шесть client-native команд

#### Scenario: Выбрана команда, объявленная агентом
- **WHEN** пользователь выбирает команду, пришедшую из `availableCommandsUpdate`
- **THEN** CodeLab вставляет `/{name} ` (и input hint команды как placeholder-текст, если команда его объявляет) в prompt composer, закрывает палитру и не вызывает никакой метод протокола — пользователь отправляет её сам через обычный флоу prompt

#### Scenario: Повторный выбор той же команды
- **WHEN** пользователь выбрал команду агента, стёр или отправил вставленный текст и снова выбирает ту же команду
- **THEN** CodeLab снова вставляет `/{name} ` в prompt composer

#### Scenario: Переключение сессий показывает собственные команды агента этой сессии
- **WHEN** активная сессия меняется
- **THEN** CodeLab показывает собственные команды агента, объявленные для новой активной сессии — восстановленные из её последнего `availableCommandsUpdate`, если он был, либо пустой список, если не было — но никогда список предыдущей сессии

#### Scenario: Нечёткий поиск находит команду по буквам
- **WHEN** агент объявил `compact`, и пользователь вводит в палитре `cpt`
- **THEN** палитра показывает `compact`, хотя `cpt` не подстрока ни имени, ни описания

#### Scenario: Префикс имени выше совпадения в описании
- **WHEN** агент объявил `plan` и команду, в описании которой есть слово `plan`, и пользователь вводит `/pl`
- **THEN** `plan` — первая команда агента в списке палитры

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
CodeLab SHALL отражать спонтанную (не инициированную явным `connect()`/`reconnect()`) потерю ACP-соединения как отдельное состояние `lost` в UI, отличное от неудачной попытки подключения `failed`, и SHALL очищать состояние активного запроса, которое больше не может считаться достоверным, вместо того чтобы бесконечно показывать `Connected` и зависший `running` turn.

#### Scenario: Агент падает во время активной сессии
- **WHEN** активное соединение (`connectionStatus == connected`) спонтанно теряется — например, дочерний процесс агента завершается неожиданно
- **THEN** CodeLab переводит `connectionStatus` в `lost`, очищает `pendingApproval`, `isPromptSubmitting`, `canCancel`, `isRespondingToApproval` и `isRespondingToConfigOption`, и записывает диагностику с причиной

#### Scenario: Explicit connect/reconnect failure не задваивается
- **WHEN** пользователь явно вызывает `Connect`/`Reconnect`, и попытка завершается неудачей
- **THEN** CodeLab переводит `connectionStatus` в `failed` и показывает ровно одну diagnostic-запись об этой неудаче — реакция на спонтанную потерю соединения не создаёт вторую, дублирующую запись для того же события

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

### Requirement: Progress checklist reflects the agent's plan
CodeLab SHALL render the agent's plan as a progress checklist, sourced from `SessionUpdate.plan` entries, showing each entry's priority and status without inventing statuses the protocol does not define.

#### Scenario: Plan update renders a checklist
- **WHEN** the active session receives a `SessionUpdate.plan` with one or more entries
- **THEN** CodeLab shows a checklist with one row per entry, each showing its status (pending/in_progress/completed) and priority (high/medium/low)

#### Scenario: No plan yet — no checklist shown
- **WHEN** the active session has not received any `plan` update
- **THEN** CodeLab does not show a checklist or an empty-state placeholder for it

#### Scenario: A later plan update replaces the checklist
- **WHEN** a new `SessionUpdate.plan` arrives for the active session
- **THEN** CodeLab replaces the displayed checklist with the entries from the new update

### Requirement: Docked plan summary below the transcript
CodeLab SHALL show a compact summary of the current plan docked below the transcript, directly above the composer, expandable into the full checklist by clicking anywhere on the summary row.

#### Scenario: Summary names the active step
- **WHEN** a plan has an entry with status in_progress and the summary is collapsed
- **THEN** the compact summary shows that entry's description, and a count of remaining pending entries if any remain

#### Scenario: Summary shows an aggregate count when nothing is in progress
- **WHEN** a plan has no entry with status in_progress, or the summary is expanded
- **THEN** the compact summary shows an aggregate count (total entries if none are completed yet, or completed-out-of-total otherwise) instead of naming a specific entry

#### Scenario: Summary is omitted when the plan is fully completed
- **WHEN** every entry in the current plan has status completed
- **THEN** CodeLab does not show the compact summary row, though the full checklist remains reachable until every entry is completed

#### Scenario: Dismissing the plan clears the summary until the next update
- **WHEN** the user dismisses the plan summary
- **THEN** CodeLab stops showing the plan summary and checklist for that session until a new plan update arrives

### Requirement: Full checklist has a bounded, independently scrollable height
CodeLab SHALL cap the expanded checklist's height and scroll its entries independently, so a long plan does not push the transcript or composer out of view.

#### Scenario: Plan with many entries stays within a bounded height
- **WHEN** the expanded checklist has more entries than fit in its maximum height
- **THEN** the entries scroll within the checklist without resizing the surrounding layout

### Requirement: Sessions run prompt turns independently of the active session
CodeLab SHALL allow a session's prompt turn to continue running while a different session is active, and SHALL allow the active session to start its own prompt turn even while another session's turn is still running, as long as the active session itself is not busy.

#### Scenario: Starting a second session while the first is still running
- **WHEN** a session has a prompt turn running or an approval pending, and the user creates or switches to a different, idle session
- **THEN** CodeLab lets the user submit a prompt in the newly active session immediately, without queuing it, regardless of the other session's state

#### Scenario: A background session's turn keeps running while another session is active
- **WHEN** a session's prompt turn is running while a different session is active
- **THEN** CodeLab does not cancel, pause, or otherwise interrupt the background session's turn — it continues until it completes, fails, or is explicitly cancelled

#### Scenario: A background session's turn completes while another session is active
- **WHEN** a non-active session's prompt turn completes, fails, or its approval is resolved while a different session is active
- **THEN** CodeLab updates that session's own transcript and status without altering the transcript, composer, or submitting state currently shown for the active session

### Requirement: Sessions sidebar shows live status for background sessions
CodeLab SHALL keep each session's status indicator in the sessions sidebar current — including idle, running, and awaiting-approval — regardless of whether that session is the currently active one.

#### Scenario: A background session's status updates as its turn progresses
- **WHEN** a non-active session's prompt turn starts running, requests an approval, or completes
- **THEN** the sessions sidebar reflects that session's current status without requiring the user to switch to it first

### Requirement: Messages queue instead of failing when the session is busy
CodeLab SHALL queue a submitted prompt client-side, without attempting to send it and without losing the typed text, when the active session cannot currently accept a new prompt turn (a turn is running or an approval is pending), instead of attempting the send and showing a failure.

#### Scenario: Submitting while awaiting approval queues the message
- **WHEN** user submits a prompt while the active session has a pending approval
- **THEN** CodeLab adds the message to the queue instead of sending it, and does not show a "prompt failed" entry in the transcript

#### Scenario: Submitting while a turn is running queues the message
- **WHEN** user submits a prompt while the active session's turn is still running
- **THEN** CodeLab adds the message to the queue instead of attempting to send it

#### Scenario: Submitting while the session is free sends immediately
- **WHEN** user submits a prompt while the active session is idle or active
- **THEN** CodeLab sends it immediately, unchanged from current behavior

#### Scenario: Another session being busy does not queue a message for the active session
- **WHEN** user submits a prompt in the active session while a *different* session has a turn running or an approval pending
- **THEN** CodeLab sends the message immediately, exactly as it would if no other session existed — only the active session's own busy state can cause queuing

### Requirement: Queued messages panel with per-item and bulk actions
CodeLab SHALL show a queued-messages panel, visible only when the queue is non-empty, offering Edit, Delete, and Send Now per item, and Clear All for the whole queue.

#### Scenario: Editing a queued message
- **WHEN** user selects Edit on a queued message
- **THEN** CodeLab removes it from the queue and places its text back into the prompt composer for editing

#### Scenario: Deleting a queued message
- **WHEN** user selects Delete on a queued message
- **THEN** CodeLab removes it from the queue without sending it

#### Scenario: Send Now attempts immediate delivery
- **WHEN** user selects Send Now on a queued message and the session is currently free
- **THEN** CodeLab sends that message immediately, out of FIFO order

#### Scenario: Send Now during a race returns the message to the queue
- **WHEN** user selects Send Now on a queued message but the session is still busy at that moment
- **THEN** CodeLab returns the message to its place in the queue without showing an error

#### Scenario: Clear All empties the queue
- **WHEN** user selects Clear All
- **THEN** CodeLab removes every queued message without sending any of them

### Requirement: Queue drains automatically when the session becomes free
CodeLab SHALL automatically send the oldest queued message once the active session returns to an idle/active state, without requiring user action.

#### Scenario: Oldest message sends automatically after the block clears
- **WHEN** the active session's turn completes or its pending approval is resolved, and the queue is non-empty
- **THEN** CodeLab automatically sends the oldest queued message

#### Scenario: A background session's own queue drains when its own turn completes
- **WHEN** a non-active session's turn completes or its pending approval is resolved while a different session is active, and that non-active session's own queue is non-empty
- **THEN** CodeLab automatically sends that session's oldest queued message, without requiring the user to switch to it first

### Requirement: Debug log — отдельная докнутая панель, не вложенная в Inspector
CodeLab SHALL отображать debug log как самостоятельную, персистентно видимую панель workbench, стоящую рядом с Inspector как sibling, а не как секция внутри карточки Inspector.

#### Scenario: Debug log панель видна без явного действия пользователя
- **WHEN** workbench открыт (вне зависимости от того, вызывалась ли команда `/logs`)
- **THEN** докнутая панель "Debug log" видна в правой колонке рядом с Inspector, как отдельная карточка со своим заголовком

#### Scenario: Docked-панель не дублирует содержимое Inspector
- **WHEN** пользователь просматривает докнутую Debug log панель и панель Inspector одновременно
- **THEN** Inspector показывает только approval/tool-call/protocol-записи текущей сессии, а Debug log — только structured-log события; ни одна запись не показана в обеих панелях одновременно

#### Scenario: Докнутая панель даёт поиск и фильтр по уровню
- **WHEN** пользователь вводит текст в поле поиска или выбирает минимальный уровень в докнутой Debug log панели
- **THEN** список записей в этой панели ограничивается совпадающими по тексту и/или не ниже выбранного уровня

#### Scenario: Кнопка Expand открывает полноэкранный log viewer
- **WHEN** пользователь нажимает кнопку "Expand" в заголовке докнутой Debug log панели
- **THEN** CodeLab открывает тот же полноэкранный log viewer, что и по команде `/logs`

#### Scenario: Селектор типа фильтрует записи по категории, когда их несколько
- **WHEN** в Debug log панели одновременно присутствуют записи двух и более категорий (например, `application` и `protocol`)
- **THEN** CodeLab показывает в панели селектор по типу записи, позволяющий ограничить список одной категорией или снять ограничение; протокольные события при этом всегда попадают в панель — видимость регулируется этим селектором, а не отдельным переключателем захвата

### Requirement: Полноэкранный log viewer — master-detail
CodeLab SHALL открывать полноэкранный log viewer (список записей слева, detail-панель выбранной записи справа) поверх притемнённого workbench при вызове через `/logs` или кнопку "Expand" докнутой панели, и SHALL закрывать его без потери состояния workbench под ним.

#### Scenario: Detail-панель показывает correlation-поля выбранной записи
- **WHEN** пользователь выбирает запись в списке полноэкранного log viewer
- **THEN** detail-панель показывает событие целиком, включая доступные correlation-поля (`component`, `category`, `connection_generation`, и где применимо `session_id`/`request_id`/`tool_call_id`) в виде key/value

#### Scenario: Закрытие возвращает к workbench без изменений
- **WHEN** полноэкранный log viewer открыт, и пользователь нажимает кнопку закрытия либо `Esc`
- **THEN** CodeLab скрывает log viewer и возвращает workbench к состоянию, в котором он был до открытия (активная сессия, transcript, docked-панели не меняются)

#### Scenario: Секреты замаскированы и в списке, и в detail-панели
- **WHEN** запись, отображаемая в полноэкранном log viewer (в списке или в detail-панели), содержит значение, подпадающее под существующее правило редактирования секретов
- **THEN** это значение показано замаскированным — то же самое правило, что уже действует для docked debug-лога (см. `approval-safety`, требование "Редактирование секретов"), не дублируется отдельным набором правил

### Requirement: Отменяемый ход в workbench
CodeLab SHALL показывать вызов инструмента, отменённый клиентом при отправке `session/cancel`, со статусом «Cancelled», а не «Failed» или «Running». Пока ход «отменяется», сессия SHALL считаться занятой: кнопка отмены недоступна, очередь промптов не отправляет следующее сообщение до ответа агента на `session/prompt`.

#### Scenario: Отменённый вызов показан как Cancelled
- **WHEN** пользователь отменяет ход, пока вызов инструмента выполняется
- **THEN** запись вызова в transcript показывает статус «Cancelled»

#### Scenario: Очередь ждёт ответа агента на отмену
- **WHEN** пользователь отменяет ход, в очереди сессии есть сообщение, а агент ещё не ответил на `session/prompt`
- **THEN** CodeLab не отправляет сообщение из очереди и не показывает кнопку отмены; после ответа агента сообщение отправляется автоматически

### Requirement: Лента transcript следует за хвостом
CodeLab SHALL держать в виду конец ленты transcript, пока пользователь находится у её низа: когда в ленту дописываются или меняются записи, лента SHALL прокручиваться к новому низу. Если пользователь прокрутил ленту вверх, чтобы читать историю, CodeLab SHALL NOT менять позицию прокрутки.

#### Scenario: Новые записи у низа ленты остаются видимыми
- **WHEN** пользователь находится у низа ленты (не дальше 80 px) и в ленту приходят новые записи — ответ агента, карточки tool call, результаты
- **THEN** после перерисовки лента прокручена к новому низу без анимации, и последняя запись видна

#### Scenario: Чтение истории не прерывается
- **WHEN** пользователь прокрутил ленту вверх дальше 80 px от низа, и в ленту приходят новые записи
- **THEN** позиция прокрутки не меняется

#### Scenario: Возврат к низу возобновляет следование
- **WHEN** пользователь, читавший историю, прокрутил ленту обратно к низу (не дальше 80 px), и в ленту приходят новые записи
- **THEN** лента снова прокручивается к новому низу

#### Scenario: Автопрокрутка к approval сохраняется
- **WHEN** вместе с новыми записями появляется новый pending approval
- **THEN** CodeLab прокручивает ленту к approval так же, как требует сценарий «Лента автоскроллится к новому approval»

### Requirement: Sessions sidebar lists the project's sessions from the agent
When the agent declares `sessionCapabilities.list`, the sessions sidebar SHALL show the project's sessions from `session/list` after each successful connect or reconnect, after the sessions opened in this run and without duplicates. A session that is not open yet SHALL be shown with its title from the agent and a "not loaded" status. When the agent reports more sessions, the sidebar SHALL offer a "Load more sessions" control that fetches the next page.

#### Scenario: Sessions from the agent's journal
- **WHEN** the user connects to an agent whose journal holds two sessions for the selected project
- **THEN** the sidebar lists both sessions with their titles and a "not loaded" status

#### Scenario: More sessions than one page
- **WHEN** the agent's first `session/list` page has a `nextCursor`
- **THEN** the sidebar shows "Load more sessions", and selecting it appends the next page

### Requirement: Selecting a not-loaded session restores its transcript
Selecting a "not loaded" session in the sidebar SHALL load it via `session/load` and make it the active session with the transcript replayed by the agent. If loading fails, the previously active session SHALL stay active and the failure SHALL be recorded as a diagnostic.

#### Scenario: Loading a session from the sidebar
- **WHEN** the user selects a "not loaded" session
- **THEN** the session becomes active and its transcript shows the user prompts and agent replies the agent replayed

#### Scenario: Loading fails
- **WHEN** the agent answers `session/load` with an error
- **THEN** the active session does not change, the sidebar row stays "not loaded", and a diagnostic records the failure

### Requirement: Workbench restores sessions after reconnect and restart
After `Reconnect`, the workbench SHALL reload the open sessions so the active session's transcript matches the agent's replay; a session the agent cannot restore SHALL be shown as "detached" with a notice in its transcript, and prompts to it SHALL fail without reaching the agent. After an app restart, the workbench SHALL select the project from the previous run and, on the first successful connect, SHALL list the project's sessions and load the previously active session; when the agent cannot restore it, the workbench SHALL start a new session with a notice explaining why.

#### Scenario: Reconnect reloads the active session
- **WHEN** a session with a finished turn is active and the user presses Reconnect to an agent that supports `session/load`
- **THEN** after reconnecting the active session shows the same transcript, rebuilt from the agent's replay

#### Scenario: Restart restores the previous session
- **WHEN** the user restarts the app after working in a session and connects again with the same connection settings
- **THEN** the previous project is selected, the sidebar lists the project's sessions, and the previously active session is loaded with its transcript

#### Scenario: The agent cannot restore sessions
- **WHEN** after a restart the user connects to an agent without `loadSession`
- **THEN** the workbench starts a new session in the previous project and its transcript shows "The agent cannot restore sessions; a new session was started."

### Requirement: Connection banner above a non-empty transcript
When the transcript of the active session is not empty and the connection is `lost`, `failed` or `reconnecting`, the workbench SHALL show a banner above the transcript that states the connection status and its reason. The banner SHALL offer Reconnect and Connection settings while the connection is `lost` or `failed`, and SHALL show progress without a Reconnect action while it is `reconnecting`. The banner SHALL NOT be dismissible and SHALL disappear when the connection becomes `connected`. When the transcript is empty, the workbench SHALL keep showing the connection screen instead of the banner.

#### Scenario: The agent process exits during a session
- **WHEN** the active session's transcript has entries and the agent process exits unexpectedly
- **THEN** a "Connection to the agent lost" banner with the reason, a Reconnect action and a Connection settings action appears above the transcript, and the transcript entries stay visible

#### Scenario: Reconnect from the banner
- **WHEN** the user selects Reconnect in the banner and the reconnect succeeds
- **THEN** the banner shows "Reconnecting…" without the Reconnect action while reconnecting, and disappears once the connection is `connected`

#### Scenario: Reconnect from the banner fails
- **WHEN** the user selects Reconnect in the banner and the attempt fails
- **THEN** the banner shows "Could not connect to the agent" with the failure reason and offers Reconnect again

#### Scenario: Empty transcript keeps the connection screen
- **WHEN** the connection is lost while the active session's transcript is empty
- **THEN** the workbench shows the connection screen with Reconnect and no banner

### Requirement: Failed turn notice with Retry
A failed prompt turn SHALL be shown in the transcript as a notice whose title describes the failure class and whose body is the agent's message, with the raw error text available only in collapsed details. The title SHALL follow the agent's `errorClass`:

| `errorClass` | Title |
|---|---|
| `auth` | The agent could not sign in to the model provider |
| `network`, `timeout`, `server` | The model provider is unavailable |
| `rateLimited` | The model provider's rate limit was reached |
| `overflow` | The conversation is too long for the model |
| a turn interrupted by a lost connection | The connection to the agent was lost |
| any other or no class | The agent could not complete the turn |

The notice of the session's last turn SHALL offer a Retry action exactly when the session can retry it (`SessionView.canRetry`, requirement "Повтор сорвавшегося хода" of `acp-client-kit`) and the connection is `connected`. Selecting Retry SHALL send the same prompt as a new turn.

#### Scenario: Provider authentication failure
- **WHEN** the agent answers the prompt as in fixture `acp/prompt-failed-provider-auth`
- **THEN** the transcript shows "The agent could not sign in to the model provider" with the body "401 Unauthorized from openai: check api_key_env", no Retry action, and the raw error text only inside collapsed details

#### Scenario: Retry after a provider outage
- **WHEN** the last turn failed with `errorClass: "server"` and `retryable: true`, and the user selects Retry
- **THEN** the same prompt is sent as a new turn, and the failed turn with its notice stays in the transcript above it

#### Scenario: Turn interrupted by a lost connection
- **WHEN** the agent process exits while a turn is running
- **THEN** the turn's notice reads "The connection to the agent was lost" without a Retry action, and the connection banner offers Reconnect

#### Scenario: Error from a third-party agent
- **WHEN** an agent without the CodeLab extension answers the prompt with a JSON-RPC error without `data`
- **THEN** the notice reads "The agent could not complete the turn" with the JSON-RPC error message as its body, and offers Retry

