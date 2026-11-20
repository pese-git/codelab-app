## ADDED Requirements

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
- клавиатурный фокус на рабочем месте или в его элементе, но не в открытом диалоге, не в палитре команд, не в терминале пользователя и не на экране настроек;
- соединение `Connected`, активная сессия не `detached`;
- у активной сессии есть активное одобрение, и у него есть вариант этого `kind`. Вариант выбирается по `kind`, а не по подписи; варианты неизвестного `kind` сочетаний не получают.

Целью SHALL быть активное одобрение в момент нажатия, вариант — по `kind` этого одобрения. Ответ SHALL уходить с `optionId` этого варианта и id этого запроса; другой запрос, в том числе появившийся после нажатия, НЕ SHALL получать этот ответ.

Компенсирующие меры (ответ на запрос, которого пользователь не видит или не успел увидеть, НЕ SHALL уходить):
- **Видимость.** Если полоса решения цели не видна целиком в области ленты (лента прокручена, строка не построена, ленту закрывает выдвижная панель), нажатие SHALL только прокрутить ленту к полосе и подсветить её, как «Go to approval» панели Agents, без ответа и без переноса фокуса. Следующее нажатие отвечает, если условия выполнены.
- **Задержка после появления.** Если цель стала активным одобрением меньше 500 мс назад, нажатие SHALL только показать полосу, как при невидимой цели, без ответа. Так двойное нажатие после ответа и нажатие, начатое до появления запроса, не отвечают на новый запрос.
- **Автоповтор** клавиши (удержание) НЕ SHALL отвечать.

После ответа сочетанием фокус SHALL оставаться там, где был, если его узел жив; иначе действует требование «Фокус после ухода одобрения». Каждый ответ с рабочего места SHALL журналироваться событием `workbench.approval_answer` с полями `session_id`, `request_id`, `tool_call_id`, `kind` и `source` (`button` или `shortcut`). Нажатие сочетания без ответа SHALL журналироваться событием `workbench.approval_shortcut_skipped` с полями `session_id`, `request_id` (если цель есть) и `reason`: `not_visible`, `settling`, `no_option`, `no_target`. Сырые аргументы, заголовок и команда вызова в эти события НЕ SHALL попадать.

#### Scenario: Ответ из композера
- **WHEN** платформа — macOS, фокус в поле композера с текстом `draft`, полоса активного одобрения видна и активна дольше 500 мс, и пользователь нажимает ⌘Y
- **THEN** выбран `allow_once` этого одобрения, текст композера по-прежнему `draft`, фокус в композере, в журнале `workbench.approval_answer` с `source: shortcut`

#### Scenario: Ответ на Windows и Linux
- **WHEN** платформа — Linux, полоса активного одобрения видна и активна дольше 500 мс, и пользователь нажимает Alt+Shift+Q, а для другого одобрения — Alt+Shift+X
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
- **WHEN** ждёт видимое активное одобрение, и пользователь нажимает ⌘Y на экране настроек, в открытой палитре команд, в диалоге «Add connection profile» и с фокусом в терминале пользователя
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

## MODIFIED Requirements

### Requirement: Approval options are rendered and bound to shortcuts by kind
CodeLab SHALL carry each approval option's `PermissionOptionKind` (`allow_once`, `allow_always`, `reject_once`, `reject_always`) through to the presentation layer and SHALL bind each of the four kinds to a fixed keyboard shortcut by kind, as in requirement «Ответ на одобрение сочетанием с любого места рабочего места», without relying on matching substrings in the option's agent-provided label text. An option of an unknown kind SHALL get no shortcut.

#### Scenario: Four kinds shown distinctly
- **WHEN** a permission request offers all four standard option kinds
- **THEN** CodeLab shows four distinct options, each bound to its own shortcut, regardless of the exact wording of each option's label

#### Scenario: Non-English or unusual option labels still get shortcuts
- **WHEN** an agent provides an option label that does not contain the words "allow"/"approve"/"reject"/"deny" (e.g. a non-English label)
- **THEN** CodeLab still binds the correct shortcut to that option, based on its `kind`, not its label text

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
