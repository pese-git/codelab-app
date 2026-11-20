## ADDED Requirements

### Requirement: Страница «Keyboard»: видимость и навигация
Composition root SHALL делать видимой страницу «Keyboard» группы «App» в рабочей сборке app при любой ширине окна. Её место в навигации — по порядку требования «Навигация настроек»: после «General» (и «Appearance», когда та появится). Ключ пункта навигации — `settings-nav-keyboard`, ключ тела страницы — `settings-keyboard`.

У страницы нет ключей конфигурации: её содержимое — каталог сочетаний сборки (требование «Сочетания app и страница «Keyboard» не расходятся»). Каталог в рабочей сборке не пуст, поэтому страница не попадает под правило «страница без содержимого скрыта» (SETUP-17). Это исключение и из фразы «остальные страницы остаются скрытыми» требования «Страницы Providers и MCP servers в навигации» (design.md, D7).

Поиск «Find a setting» SHALL находить страницу по заголовку и по ключевым словам сообщения `settingsSearchKeywordsKeyboard`: на английском — `shortcut`, `hotkey`, `keybinding`, `key`. Выбор страницы SHALL сохраняться в `codelab.settings.last_page` значением `keyboard`, как у других страниц.

Страница SHALL быть только для чтения:
- она НЕ SHALL читать и писать `config.yaml`, `profiles.json` и `shared_preferences`, кроме `codelab.settings.last_page` оболочки;
- она НЕ SHALL обращаться к агенту;
- на ней НЕ SHALL быть элементов, которые меняют или назначают сочетания.

#### Scenario: Страница видна в рабочей сборке
- **WHEN** app собран с `defaultSettingsPages`, и пользователь открывает настройки
- **THEN** в группе «App» пункт `settings-nav-keyboard` стоит после `settings-nav-general`, а его выбор показывает тело `settings-keyboard`

#### Scenario: Узкое окно не скрывает страницу
- **WHEN** ширина окна 600 px, и пользователь открывает настройки
- **THEN** пункт `settings-nav-keyboard` есть в навигации сверху

#### Scenario: Поиск страницы по ключевому слову
- **WHEN** пользователь вводит `shortcut` в «Find a setting»
- **THEN** в навигации остаётся «Keyboard», а выбор результата открывает `settings-keyboard`

#### Scenario: Последняя страница
- **WHEN** пользователь выбрал «Keyboard», вернулся на рабочее место и снова открыл настройки
- **THEN** открыта страница «Keyboard», а `codelab.settings.last_page` равен `keyboard`

#### Scenario: Страница ничего не меняет
- **WHEN** пользователь открывает «Keyboard», ищет и закрывает настройки
- **THEN** файлы `$CODELAB_HOME` и ключи `shared_preferences`, кроме `codelab.settings.last_page`, не изменились, агенту ничего не отправлено

### Requirement: Страница «Keyboard»: строки таблицы
Страница SHALL показывать сверху вниз:
1. заголовок `Keyboard shortcuts`;
2. поле поиска с подсказкой `Search by action or key` (ключ `settings-keyboard-search`);
3. подпись `Read-only list. Shortcuts are fixed in the app.`;
4. таблицу с колонками `Action`, `Shortcut`, `Where`;
5. строку `Agent commands have no shortcuts; open them from the command palette.` (ключ `settings-keyboard-footer`).

Строки таблицы SHALL быть сгруппированы. Над каждой группой — строка-заголовок (ключ `settings-keyboard-group-<группа>`). Группы идут в порядке `Global` (`global`), `Navigation` (`navigation`), `Transcript` (`transcript`), `Composer` (`composer`), `Approvals` (`approvals`).

Таблица SHALL содержать ровно строки ниже, в этом порядке. Ключ строки — `settings-keyboard-row-<id>`. Колонка «Shortcut» дана для macOS и для остальных ОС (требование «Страница «Keyboard»: обозначения клавиш»). Знак `/` разделяет альтернативные клавиши одной строки.

| Группа | id | Action | macOS | Windows, Linux | Where |
|---|---|---|---|---|---|
| Global | `command-palette` | Open the command palette | ⌘ K | Ctrl K | Workbench |
| Global | `new-session` | New session | ⌘ N | Ctrl N | Workbench, when a project is selected |
| Global | `open-settings` | Open settings | ⌘ , | Ctrl , | Workbench |
| Global | `close-overlay` | Close the command palette, a dialog or a sliding panel | Esc | Esc | Command palette, dialog or sliding panel |
| Global | `leave-settings` | Back to the workbench | Esc | Esc | Settings |
| Navigation | `toggle-sidebar` | Show or hide the sidebar | ⌘ B | Ctrl B | Workbench |
| Navigation | `toggle-files` | Show or hide the Files pane | ⇧ ⌘ E | Ctrl Shift E | Workbench, when the Files pane is available |
| Navigation | `file-tree-move` | Move through files | ↑ / ↓ | ↑ / ↓ | Files tree |
| Navigation | `file-tree-fold` | Expand or collapse a folder | → / ← | → / ← | Files tree, on a folder |
| Navigation | `file-tree-open` | Open a file or expand a folder | ⏎ | Enter | Files tree |
| Transcript | `cancel-turn` | Cancel the running turn | Esc | Esc | Workbench or composer, while a turn runs |
| Composer | `send` | Send the message; it is queued while the session is busy | ⌘ ⏎ | Ctrl Enter | Composer |
| Composer | `command-menu-move` | Move through commands | ↑ / ↓ | ↑ / ↓ | Command menu after / |
| Composer | `command-menu-run` | Run the highlighted command | ⏎ | Enter | Command menu after / |
| Composer | `command-menu-close` | Close the command menu | Esc | Esc | Command menu after / |
| Approvals | `allow-once` | Allow once | ⌘ ⏎ | Ctrl Enter | Pending approval in focus, when the agent offers this option |
| Approvals | `allow-always` | Allow always | ⌥ ⌘ ⏎ | Ctrl Alt Enter | Pending approval in focus, when the agent offers this option |
| Approvals | `reject-once` | Reject once | ⌘ ⌫ | Ctrl Backspace | Pending approval in focus, when the agent offers this option |
| Approvals | `reject-always` | Reject always | ⌥ ⌘ ⌫ | Ctrl Alt Backspace | Pending approval in focus, when the agent offers this option |

Сочетаний, которых нет среди привязок сборки, на странице НЕ SHALL быть. В этой сборке это Cmd/Ctrl+/, Cmd/Ctrl+Shift+I, Cmd/Ctrl+Shift+F, Cmd/Ctrl+\\, Cmd/Ctrl+Shift+D, Cmd/Ctrl+O, Cmd/Ctrl+Shift+Enter, Alt+Enter, Ctrl+\` и Ctrl+Shift+\`; Alt+←/→ тоже не привязаны. Alt+←/→ зарезервированы за навигацией инспектора (DSK-18) и строкой НЕ SHALL быть, пока не привязаны (решение пользователя Q2, 2026-11-19). Навигация дерева Files и меню команд после `/` — привязки app и показываются строками (решение пользователя Q3). Стандартное поведение элементов управления строками НЕ SHALL показываться: Tab, Space и Enter на кнопке, правка и копирование текста в полях.

#### Scenario: Полный список на Linux
- **WHEN** платформа — Linux, и пользователь открывает «Keyboard» без запроса поиска
- **THEN** таблица показывает пять групп и 19 строк таблицы выше в том же порядке, с клавишами из колонки «Windows, Linux»

#### Scenario: Сочетаний без поведения нет
- **WHEN** пользователь открывает «Keyboard»
- **THEN** на странице нет строк с клавишами `/`, `I`, `F`, `\`, `D`, `O`, `` ` `` и строки steering, а также строки Alt+← и Alt+→

#### Scenario: Строка «Agent commands»
- **WHEN** пользователь открывает «Keyboard»
- **THEN** под таблицей показана строка `settings-keyboard-footer`, а кнопок назначения или сброса сочетаний на странице нет

### Requirement: Страница «Keyboard»: обозначения клавиш
Клавиши SHALL показываться кейкапами: каждая клавиша — отдельная плашка с рамкой, текст моноширинным шрифтом (`CodeLabTextRole.mono`). Обозначения выбираются по платформе app:
- на macOS: ⌘ (основной модификатор), ⌥, ⇧, ⏎, ⌫, модификаторы в порядке ⌥ ⇧ ⌘;
- на остальных ОС: `Ctrl` (основной модификатор), `Alt`, `Shift`, `Enter`, `Backspace`, модификаторы в порядке `Ctrl` `Alt` `Shift`.

`Esc`, буквы, `,` и стрелки ↑ ↓ ← → одинаковы на всех платформах. Обозначения клавиш НЕ SHALL переводиться. Пояснения вида «on macOS Ctrl reads Cmd» на странице НЕ SHALL быть: клавиши уже показаны в обозначениях платформы (решение пользователя Q1, 2026-11-19).

Для чтения с экрана сочетание SHALL иметь одну подпись словами, без символов клавиш:
- на macOS — например, `Shift+Cmd+E`, `Option+Cmd+Enter`;
- на остальных ОС — `Ctrl+Shift+E`, `Ctrl+Alt+Enter`.

Альтернативы одной строки подписываются через `or` на языке интерфейса.

Короткие подсказки сочетаний на рабочем месте SHALL строиться по тем же правилам:
- поле «Search or run a command» в шапке: `⌘K` или `Ctrl+K`;
- «New session» в сайдбаре: `⌘N` или `Ctrl+N`;
- кнопки и пункты вариантов одобрения: `⌘⏎`, `⌥⌘⏎`, `⌘⌫`, `⌥⌘⌫` на macOS; `Ctrl+⏎`, `Ctrl+Alt+⏎`, `Ctrl+⌫`, `Ctrl+Alt+⌫` на остальных ОС.

На Windows и Linux подсказка «Allow always» и «Reject always» меняет прежний порядок `Alt+Ctrl+` на `Ctrl+Alt+`: порядок модификаторов один для всех подсказок. Клавиши привязок от этого не меняются (design.md, D4; решение пользователя Q4, 2026-11-19).

#### Scenario: macOS
- **WHEN** платформа — macOS, и пользователь открывает «Keyboard»
- **THEN** строка `toggle-files` показывает кейкапы `⇧`, `⌘`, `E`, а строка `allow-always` — `⌥`, `⌘`, `⏎`

#### Scenario: Windows
- **WHEN** платформа — Windows, и пользователь открывает «Keyboard»
- **THEN** строка `toggle-files` показывает кейкапы `Ctrl`, `Shift`, `E`, а строка `reject-always` — `Ctrl`, `Alt`, `Backspace`

#### Scenario: Подпись для чтения с экрана
- **WHEN** платформа — macOS, и программа чтения с экрана доходит до клавиш строки `allow-always`
- **THEN** подпись — `Option+Cmd+Enter`, а не символы `⌥⌘⏎`

#### Scenario: Подсказка «Allow always» на Linux
- **WHEN** платформа — Linux, и в ленте ждёт одобрение с вариантом `allow_always`
- **THEN** кнопка или пункт этого варианта показывает подсказку `Ctrl+Alt+⏎`, а нажатие Ctrl+Alt+Enter по-прежнему выбирает его

### Requirement: Страница «Keyboard»: поиск
Поиск на странице SHALL отбирать строки таблицы по подстроке без учёта регистра и пробелов по краям. Строка подходит, если запрос содержится в одном из текстов:
- текст «Action» на языке интерфейса;
- английский текст «Action»;
- обозначение её клавиш в одной из нотаций, независимо от платформы app. Нотаций три: символами macOS (`⌥⌘⏎`), словами Windows и Linux (`Ctrl+Alt+Enter`) и словами macOS (`Option+Cmd+Enter`).

Перед сравнением с обозначением клавиш из запроса и из обозначения SHALL удаляться пробелы и знаки `+`. Поэтому `ctrl k`, `Ctrl+K`, `cmd+k` и `⌘K` находят строку `command-palette`.

Группа, в которой не осталось строк, SHALL скрываться вместе с заголовком. При пустом результате вместо таблицы SHALL показываться строка `No shortcuts match "<query>"` (ключ `settings-keyboard-empty`); строка `settings-keyboard-footer` остаётся. Пустой запрос SHALL показывать всю таблицу. Запрос поиска — временное состояние страницы: он НЕ SHALL сохраняться между открытиями настроек.

#### Scenario: Поиск по действию
- **WHEN** пользователь вводит `sidebar`
- **THEN** видна только группа `Navigation` со строкой `toggle-sidebar`

#### Scenario: Поиск по клавише в чужой нотации
- **WHEN** платформа — Linux, и пользователь вводит `⌘K`
- **THEN** видна строка `command-palette` с кейкапами `Ctrl` и `K`

#### Scenario: Поиск по клавише словами
- **WHEN** пользователь вводит `ctrl shift e`
- **THEN** видна только строка `toggle-files`

#### Scenario: Английский текст при русском интерфейсе
- **WHEN** app работает на русском, и пользователь вводит `allow always`
- **THEN** видна строка `allow-always` с переведённым текстом действия из `app_ru.arb`

#### Scenario: Переведённый текст при русском интерфейсе
- **WHEN** app работает на русском, и пользователь вводит часть перевода `Cancel the running turn` из `app_ru.arb`
- **THEN** видна строка `cancel-turn`

#### Scenario: Ничего не найдено
- **WHEN** пользователь вводит `zzz`
- **THEN** таблицы и заголовков групп нет, показана строка `No shortcuts match "zzz"`, строка `settings-keyboard-footer` на месте

### Requirement: Страница «Keyboard»: язык, доступность и узкое окно
Тексты страницы SHALL быть сообщениями каталогов app `en` и `ru` (требование «Локализация интерфейса app»):
- заголовок, подсказка поиска, подпись, заголовки колонок и групп;
- тексты «Action» и «Where»;
- строка «Agent commands» и пустой результат.

Смена языка SHALL пересобирать страницу сразу и НЕ SHALL сбрасывать введённый запрос поиска.

Таблица SHALL оставаться таблицей для чтения с экрана: строка группы — заголовок, строка сочетания читается как «действие, клавиши, где». Строки таблицы НЕ SHALL быть остановками обхода Tab: на странице с клавиатуры фокусируется поле поиска, а Esc по-прежнему возвращает на рабочее место (требование «Рабочее место недоступно с клавиатуры из настроек»).

Если ширины тела страницы не хватает таблице, таблица SHALL прокручиваться по горизонтали внутри своего блока, а не обрезать текст: текст «Action» и «Where» переносится, кейкапы не переносятся и не сжимаются.

#### Scenario: Русский интерфейс
- **WHEN** app работает на русском, и пользователь открывает «Keyboard»
- **THEN** заголовок, колонки, группы, действия, места и строка «Agent commands» — переводы из `app_ru.arb`, а кейкапы те же, что на английском

#### Scenario: Смена языка с запросом
- **WHEN** на странице введён запрос `esc`, и пользователь меняет язык на «Русский»
- **THEN** страница показана на русском, в поле поиска по-прежнему `esc`, видны те же строки

#### Scenario: Минимальное окно
- **WHEN** ширина окна 800 px (минимальное окно app), и пользователь открывает «Keyboard»
- **THEN** все три колонки видны без горизонтальной прокрутки, тексты «Action» и «Where» переносятся, ошибки переполнения нет

#### Scenario: Узкое окно
- **WHEN** область страницы уже минимальной ширины таблицы (380 px; окно 440 px), и пользователь открывает «Keyboard»
- **THEN** таблица прокручивается по горизонтали, ошибки переполнения нет, все кейкапы строки `allow-always` видны целиком после прокрутки

#### Scenario: Обход с клавиатуры
- **WHEN** фокус в навигации настроек на пункте `settings-nav-keyboard`, и пользователь нажимает Tab
- **THEN** фокус переходит в поле `settings-keyboard-search`, а не на строки таблицы

### Requirement: Сочетания app и страница «Keyboard» не расходятся
Каждая клавиатурная привязка рабочего места, экрана настроек и диалогов app SHALL быть строкой страницы «Keyboard» с теми же клавишами. Каждая строка страницы SHALL быть привязкой, которая выполняет своё действие в указанном месте. Короткие подсказки сочетаний на рабочем месте SHALL показывать клавиши той привязки, которой подсказка соответствует.

Change, который вводит, меняет или убирает сочетание, SHALL в том же change менять строку страницы «Keyboard», её тексты `en` и `ru` и проверку нажатием. Основной модификатор SHALL привязываться и к Ctrl, и к ⌘ на всех платформах, как до этого change. Привязки НЕ SHALL переназначаться этим требованием (DSK-18).

#### Scenario: Каждая строка проверена нажатием
- **WHEN** тест нажимает клавиши каждой строки таблицы в её месте: Ctrl-вариант на всех платформах, ⌘-вариант — у строк с основным модификатором
- **THEN** выполняется действие строки. Например, `allow-always` выбирает вариант `allow_always` ожидающего одобрения, а `leave-settings` возвращает на рабочее место без `session/cancel`

#### Scenario: Привязка вне списка
- **WHEN** в коде кита или app появляется привязка клавиш, которой нет на странице «Keyboard»
- **THEN** тест-сторож пакета падает и называет файл с этой привязкой

#### Scenario: Отправка и одобрение на одной клавише
- **WHEN** ждёт одобрение, и пользователь нажимает Cmd/Ctrl+Enter один раз с фокусом на одобрении, а другой раз с фокусом в композере с текстом
- **THEN** в первом случае выбран вариант `allow_once`, во втором сообщение поставлено в очередь, а одобрение по-прежнему ждёт
