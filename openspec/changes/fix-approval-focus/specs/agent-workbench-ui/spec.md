## ADDED Requirements

### Requirement: Одобрение получает клавиатурный фокус только по действию пользователя
Появление, обновление и перестроение ожидающего одобрения НЕ SHALL переносить клавиатурный фокус: ни на полосу решения, ни на её кнопки, ни на другие элементы строки вызова. Фокус SHALL оставаться там, где был, в том числе когда фокуса нет ни у одного элемента рабочего места. Клавиатурный фокус SHALL попадать в полосу решения только действием пользователя:
- клик по её элементу;
- Tab или Shift+Tab;
- сочетание «Go to approval» (требование «Переход к ожидающему одобрению с клавиатуры»).

Два понятия различаются:
- **Активное одобрение** — самое раннее по `requestedAt` ожидающее одобрение хода активной сессии (признак `focused` модели клиентского ядра, требование «Паттерны взаимодействия agent workbench», сценарий «Клавиатурные approve/reject применяются к самому раннему pending approval»). Признак модели не означает клавиатурного фокуса.
- **Клавиатурный фокус в полосе** — фокус Flutter на самой полосе решения или на элементе внутри неё.

Сочетания одобрения (`allow_once`, `allow_always`, `reject_once`, `reject_always`; требование «Approval options are rendered and bound to shortcuts by kind») SHALL действовать, только когда выполнены оба условия: одобрение активно, и клавиатурный фокус в его полосе. В любом другом месте эти клавиши НЕ SHALL отвечать на `session/request_permission`.

#### Scenario: Одобрение появилось без фокуса — Cmd/Ctrl+Enter не отвечает
- **WHEN** на рабочем месте фокуса нет ни у одного элемента (пользователь кликнул по пустой ленте), агент присылает `session/request_permission` с четырьмя стандартными вариантами, и пользователь нажимает Cmd+Enter, затем Ctrl+Enter
- **THEN** ответ на `session/request_permission` не отправлен, полоса решения ждёт, а клавиатурный фокус не в полосе

#### Scenario: Одобрение появилось без фокуса — остальные сочетания одобрения не отвечают
- **WHEN** на рабочем месте фокуса нет ни у одного элемента, появляется одобрение с четырьмя стандартными вариантами, и пользователь по очереди нажимает Cmd/Ctrl+Alt+Enter, Cmd/Ctrl+Backspace и Cmd/Ctrl+Alt+Backspace, каждое в варианте Ctrl и в варианте ⌘
- **THEN** ни один вариант не выбран, ответ на `session/request_permission` не отправлен

#### Scenario: Одобрение появилось после закрытия палитры
- **WHEN** пользователь закрыл палитру команд по Esc, сразу после этого появляется одобрение, и пользователь нажимает Cmd/Ctrl+Enter
- **THEN** ответ на `session/request_permission` не отправлен, полоса решения ждёт

#### Scenario: Фокус в композере не уходит к одобрению
- **WHEN** фокус в поле композера с текстом `run tests`, появляется одобрение, и пользователь нажимает Cmd/Ctrl+Enter
- **THEN** фокус по-прежнему в композере, сообщение `run tests` поставлено в очередь (требование «Messages queue instead of failing when the session is busy»), а одобрение ждёт

#### Scenario: Фокус в дереве Files или в сайдбаре
- **WHEN** фокус в дереве Files или на строке сайдбара, ждёт одобрение, и пользователь нажимает Cmd/Ctrl+Enter или Cmd/Ctrl+Backspace
- **THEN** ответ на `session/request_permission` не отправлен, сообщение в очередь не поставлено

#### Scenario: Tab до кнопки не самого раннего одобрения
- **WHEN** ждут одобрения `A` (раньше) и `B`, пользователь клавишей Tab ставит фокус на кнопку «Allow» одобрения `B` и нажимает Cmd/Ctrl+Enter
- **THEN** ответ не отправлен ни на `A`, ни на `B`; Enter или Space на этой кнопке отвечают на `B` её вариантом

### Requirement: Переход к ожидающему одобрению с клавиатуры
Рабочее место SHALL предлагать сочетание «Go to approval»: Cmd+Shift+A и Ctrl+Shift+A на всех платформах (основной модификатор каталога `CodeLabShortcut`, запись `goToApproval`). Сочетание SHALL действовать на рабочем месте, когда клавиатурный фокус:
- на рабочем месте или в любом его элементе, включая композер;
- не в открытом диалоге и не в палитре команд;
- не на экране настроек.

Сочетание действует, пока у активной сессии есть активное одобрение. Соединение при этом SHALL быть в состоянии `Connected`, а сессия НЕ SHALL быть `detached`.

Нажатие SHALL:
1. выбрать целью активное одобрение активной сессии в момент нажатия. Это и одобрение, которое спрашивает субагент: его блок стоит под строкой `agent` корня (требование «Запрос одобрения от субагента под строкой корня»);
2. прокрутить ленту так, чтобы полоса решения цели была видна. Механизм тот же, что у «Go to approval» панели Agents, и строку `agent` корня он не раскрывает;
3. поставить клавиатурный фокус на саму полосу решения цели, а не на её кнопку.

Полоса с клавиатурным фокусом SHALL:
- принимать четыре сочетания одобрения;
- НЕ SHALL выбирать вариант по Enter или Space — их нажатие на полосе ничего не отправляет;
- пропускать Tab и Shift+Tab к своим элементам: «Allow», «Reject», выбор охвата, «View raw input».

Без активного одобрения в активной сессии нажатие НЕ SHALL ничего делать: фокус и прокрутка прежние, ошибки и заметки нет. Если цель решена, снята или ушла из ленты до того, как получила фокус, фокус SHALL оставаться прежним и НЕ SHALL переходить к другому одобрению. Повторное нажатие, пока фокус уже в полосе цели, НЕ SHALL ничего менять.

Полоса с клавиатурным фокусом SHALL показывать видимую рамку фокуса цветами `FluentTheme`. Рамка отличается от фона не только цветом заливки. Для чтения с экрана полоса SHALL быть контейнером с подписью `Awaiting approval` на языке интерфейса. Подсказка контейнера перечисляет варианты, у которых есть сочетание: название варианта от агента и клавиши словами (`spokenFor` каталога), например `Allow once: Cmd+Enter`.

Пока у активного одобрения клавиатурный фокус вне его полосы, полоса SHALL показывать приглушённую подсказку `Press {shortcut} to answer from the keyboard`. Здесь `{shortcut}` — короткое обозначение записи `goToApproval` по платформе: `⇧⌘A` на macOS, `Ctrl+Shift+A` на остальных ОС. Когда фокус в полосе, подсказки нет. У неактивных одобрений подсказки нет.

#### Scenario: Пользователь с клавиатуры доходит до одобрения и отвечает
- **WHEN** фокус в композере, ждёт одобрение с четырьмя стандартными вариантами, пользователь нажимает Cmd/Ctrl+Shift+A, а затем Cmd/Ctrl+Enter
- **THEN** после первого нажатия полоса решения видна и в фокусе с рамкой, ответ не отправлен; после второго выбран вариант `allow_once` этого одобрения

#### Scenario: Переход и остальные сочетания
- **WHEN** пользователь перешёл к одобрению сочетанием Cmd/Ctrl+Shift+A и нажимает Cmd/Ctrl+Alt+Backspace
- **THEN** выбран вариант `reject_always` этого одобрения

#### Scenario: Enter на полосе ничего не выбирает
- **WHEN** пользователь перешёл к одобрению сочетанием Cmd/Ctrl+Shift+A и нажимает Enter, затем Space
- **THEN** ответ на `session/request_permission` не отправлен, полоса ждёт и остаётся в фокусе

#### Scenario: С клавиатуры через Tab
- **WHEN** пользователь перешёл к одобрению сочетанием Cmd/Ctrl+Shift+A, нажимает Tab до кнопки «Reject» и нажимает Enter
- **THEN** выбран вариант этой кнопки для выбранного охвата (`reject_once` при охвате «Only this time»)

#### Scenario: Несколько одобрений — переход к самому раннему
- **WHEN** в ходе активной сессии ждут одобрения `A` (раньше по `requestedAt`) и `B`, лента прокручена к `B`, и пользователь нажимает Cmd/Ctrl+Shift+A
- **THEN** лента прокручена к `A`, фокус в полосе `A`; после Cmd/Ctrl+Enter выбран `allow_once` у `A`, а `B` ждёт и фокус не получает

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

#### Scenario: Подсказка перехода на macOS и Linux
- **WHEN** ждёт одобрение, фокус в композере, платформа — macOS, затем Linux
- **THEN** полоса активного одобрения показывает `Press ⇧⌘A to answer from the keyboard`, затем `Press Ctrl+Shift+A to answer from the keyboard`; после Cmd/Ctrl+Shift+A подсказки нет

#### Scenario: Чтение с экрана
- **WHEN** платформа — macOS, пользователь перешёл к одобрению с вариантами `allow_once` и `reject_once` сочетанием Cmd/Ctrl+Shift+A, и программа чтения с экрана читает элемент в фокусе
- **THEN** подпись элемента — `Awaiting approval` и сочетания словами `Cmd+Enter` и `Cmd+Backspace`, без символов `⌘⏎`

### Requirement: Фокус после ухода одобрения
Если полоса решения исчезает, пока клавиатурный фокус в ней, фокус SHALL переходить в поле композера активной сессии, если композер есть и включён, иначе — на рабочее место. Полоса исчезает, когда:
- пользователь ответил клавишами или кнопкой;
- ход отменён;
- запрос снят переподключением;
- пользователь переключил сессию.

Следующее ожидающее одобрение, в том числе ставшее активным, НЕ SHALL получать фокус само (требование «Одобрение получает клавиатурный фокус только по действию пользователя»).

Клавиатурный фокус полосы SHALL принадлежать своему запросу (`ApprovalRequestId`). Если на том же месте ленты появляется полоса другого запроса, фокус на неё НЕ SHALL переходить.

#### Scenario: Ответ клавишами возвращает фокус в композер
- **WHEN** пользователь перешёл к одобрению `A` сочетанием Cmd/Ctrl+Shift+A и выбрал `allow_once` клавишами Cmd/Ctrl+Enter, а одобрение `B` ещё ждёт
- **THEN** фокус в поле композера, полоса `B` фокуса не получила; повторное Cmd/Ctrl+Enter при пустом композере ничего не отправляет и не отвечает на `B`

#### Scenario: Отмена хода при фокусе в полосе
- **WHEN** фокус в полосе одобрения, и ход отменяется
- **THEN** полоса заменена тегом «Cancelled», фокус в поле композера

#### Scenario: Новый запрос того же вызова
- **WHEN** фокус в полосе одобрения `A`, пользователь ответил на `A`, и агент присылает новый `session/request_permission` для того же вызова
- **THEN** полоса нового запроса показана в той же строке вызова без фокуса, фокус в поле композера

## MODIFIED Requirements

### Requirement: Approval card inside the tool call row
A pending approval SHALL be shown inside its tool call row as one decision bar at the bottom of the row, not as a separate card. The decision bar SHALL separate the decision from its scope: it SHALL show an "Allow" button and a "Reject" button and a scope selector with "Only this time" and "Always". A button SHALL answer with the agent's option of its decision and the selected scope:

| Button | Only this time | Always |
|---|---|---|
| Allow | `allow_once` | `allow_always` |
| Reject | `reject_once` | `reject_always` |

The scope SHALL default to "Only this time" when the request has an `allow_once` or `reject_once` option, and to "Always" otherwise. A scope SHALL be offered only when the request has an option of that scope. A button whose decision has no option in the selected scope SHALL be disabled and SHALL say that the agent offers no such option. The "Always" scope SHALL show the names of the agent's `allow_always` and `reject_always` options. The scope SHALL apply to this approval only. Each button of the active approval SHALL show the shortcut of the option it answers with; option shortcuts SHALL stay as in requirement "Approval options are rendered and bound to shortcuts by kind" and SHALL work whatever scope is selected, but only while the approval is active and keyboard focus is in its decision bar (requirement «Одобрение получает клавиатурный фокус только по действию пользователя»). While keyboard focus is outside the decision bar of the active approval, the bar SHALL show the hint to go to it, as in requirement «Переход к ожидающему одобрению с клавиатуры». The decision bar SHALL NOT take keyboard focus by itself. The decision bar SHALL NOT repeat the command shown in the row header and SHALL NOT carry a title. The reason, when present, SHALL be shown as a muted line above the decision bar. The raw input SHALL stay collapsed until the user chooses "View raw input" in the decision bar, as in requirement "Approval panel offers a collapsed raw input view". After the decision the decision bar SHALL be replaced by a tag in the tool call row naming the outcome, as in requirement "Паттерны взаимодействия agent workbench".

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
- **WHEN** the approval is active, keyboard focus is in its decision bar, the scope is "Only this time" and the user presses the shortcut of `allow_always`
- **THEN** CodeLab selects the `allow_always` option for that approval

#### Scenario: Shortcut without keyboard focus in the bar
- **WHEN** the approval is active, keyboard focus is outside its decision bar and outside the composer, and the user presses the shortcut of `allow_always`
- **THEN** CodeLab sends no answer to `session/request_permission`, and the approval stays pending

#### Scenario: Decision leaves a tag
- **WHEN** the user chooses "Allow" with the scope "Only this time" and the agent's `allow_once` option is named "Allow once"
- **THEN** the decision bar disappears and the tool call row shows a tag "Allow once" with a success tone
