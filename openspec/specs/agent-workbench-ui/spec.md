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
- **THEN** approval появляется inline в transcript и в инспекторе с риском, причиной, командой/cwd/diff, если доступны

#### Scenario: Меняется режим отображения
- **WHEN** пользователь выбирает `summary`, `normal` или `verbose`
- **THEN** transcript и детали tool call меняют детализацию, не теряя данных

#### Scenario: Переключение сессий показывает только состояние этой сессии
- **WHEN** пользователь переключает активную сессию (через сайдбар или создав новую)
- **THEN** CodeLab показывает собственные transcript, записи инспектора и pending approval этой сессии (если есть) — никогда не состояние, оставшееся от предыдущей активной сессии

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
CodeLab SHALL present the transport setup form (profile, command, args, working directory, environment for stdio; endpoint and token for WebSocket) inside a modal dialog rather than as a permanently visible panel in the main workbench pane. The dialog SHALL be reachable both from a persistent "Configure connection" affordance in the command bar and from a compact "Configure connection" prompt on the empty/disconnected connection screen — the same label in both places, not two names for one action — and SHALL NOT open automatically on app start.

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

