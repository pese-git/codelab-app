## MODIFIED Requirements

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
| Approvals | `go-to-approval` | Go to approval | ⇧ ⌘ A | Ctrl Shift A | Workbench, while an approval is pending |
| Approvals | `allow-once` | Allow once | ⌘ Y | Alt Shift Y | Workbench, earliest pending approval, if it offers this option |
| Approvals | `allow-always` | Allow always | ⌥ ⌘ Y | Alt Shift Q | Workbench, earliest pending approval, if it offers this option |
| Approvals | `reject-once` | Reject once | ⌥ ⌘ Z | Alt Shift X | Workbench, earliest pending approval, if it offers this option |
| Approvals | `reject-always` | Reject always | ⌥ ⇧ ⌘ Z | Alt Shift W | Workbench, earliest pending approval, if it offers this option |

Сочетаний, которых нет среди привязок сборки, на странице НЕ SHALL быть. В этой сборке это Cmd/Ctrl+/, Cmd/Ctrl+Shift+I, Cmd/Ctrl+Shift+F, Cmd/Ctrl+\\, Cmd/Ctrl+Shift+D, Cmd/Ctrl+O, Cmd/Ctrl+Shift+Enter, Alt+Enter, Ctrl+\` и Ctrl+Shift+\`; Alt+←/→ тоже не привязаны. Alt+←/→ зарезервированы за навигацией инспектора (DSK-18) и строкой НЕ SHALL быть, пока не привязаны (решение пользователя Q2, 2026-11-19). Навигация дерева Files и меню команд после `/` — привязки app и показываются строками (решение пользователя Q3). Строка `go-to-approval` — привязка рабочего места, которая ставит клавиатурный фокус на полосу решения активного одобрения (spec agent-workbench-ui «Переход к ожидающему одобрению с клавиатуры»). Строки `allow-once`, `allow-always`, `reject-once`, `reject-always` — сочетания ответа, которые действуют с любого места рабочего места и отвечают самому раннему ожидающему одобрению активной сессии (spec agent-workbench-ui «Ответ на одобрение сочетанием с любого места рабочего места»); их клавиши различаются по платформам не только обозначениями. Стандартное поведение элементов управления строками НЕ SHALL показываться: Tab, Space и Enter на кнопке, правка и копирование текста в полях.

#### Scenario: Полный список на Linux
- **WHEN** платформа — Linux, и пользователь открывает «Keyboard» без запроса поиска
- **THEN** таблица показывает пять групп и 20 строк таблицы выше в том же порядке, с клавишами из колонки «Windows, Linux»

#### Scenario: Сочетаний без поведения нет
- **WHEN** пользователь открывает «Keyboard»
- **THEN** на странице нет строк с клавишами `/`, `I`, `F`, `\`, `D`, `O`, `` ` `` и строки steering, а также строки Alt+← и Alt+→

#### Scenario: Строка «Agent commands»
- **WHEN** пользователь открывает «Keyboard»
- **THEN** под таблицей показана строка `settings-keyboard-footer`, а кнопок назначения или сброса сочетаний на странице нет

#### Scenario: Строка «Go to approval»
- **WHEN** платформа — macOS, и пользователь открывает «Keyboard»
- **THEN** в группе `Approvals` первая строка — `go-to-approval` с действием `Go to approval`, кейкапами `⇧`, `⌘`, `A` и местом `Workbench, while an approval is pending`; у строк `allow-once`, `allow-always`, `reject-once`, `reject-always` место — `Workbench, earliest pending approval, if it offers this option`; строка `reject-always` на macOS — кейкапы `⌥`, `⇧`, `⌘`, `Z`

#### Scenario: Поиск строки перехода
- **WHEN** пользователь вводит `ctrl shift a`
- **THEN** видна только группа `Approvals` со строкой `go-to-approval`

#### Scenario: Поиск сочетания ответа в чужой нотации
- **WHEN** платформа — macOS, и пользователь вводит `alt shift y`
- **THEN** видна только строка `allow-once` с кейкапами `⌘` и `Y`

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
- кнопки и пункты вариантов одобрения: `⌘Y`, `⌥⌘Y`, `⌥⌘Z`, `⌥⇧⌘Z` на macOS; `Alt+Shift+Y`, `Alt+Shift+Q`, `Alt+Shift+X`, `Alt+Shift+W` на остальных ОС.

Порядок модификаторов один для всех подсказок: `Ctrl`, `Alt`, `Shift` на Windows и Linux (design.md `add-app-keyboard-page`, D4; решение пользователя Q4, 2026-11-19). Сочетания ответа на одобрение различаются по платформам не только обозначениями: на каждой платформе показываются и привязываются её клавиши (spec agent-workbench-ui «Ответ на одобрение сочетанием с любого места рабочего места»).

#### Scenario: macOS
- **WHEN** платформа — macOS, и пользователь открывает «Keyboard»
- **THEN** строка `toggle-files` показывает кейкапы `⇧`, `⌘`, `E`, а строка `allow-always` — `⌥`, `⌘`, `Y`

#### Scenario: Windows
- **WHEN** платформа — Windows, и пользователь открывает «Keyboard»
- **THEN** строка `toggle-files` показывает кейкапы `Ctrl`, `Shift`, `E`, а строка `reject-once` — `Alt`, `Shift`, `X`

#### Scenario: Подпись для чтения с экрана
- **WHEN** платформа — macOS, и программа чтения с экрана доходит до клавиш строки `allow-always`
- **THEN** подпись — `Option+Cmd+Y`, а не символы `⌥⌘Y`

#### Scenario: Подсказка «Allow always» на Linux
- **WHEN** платформа — Linux, и в ленте ждёт одобрение с вариантом `allow_always`
- **THEN** кнопка или пункт этого варианта показывает подсказку `Alt+Shift+Q`, а нажатие Alt+Shift+Q при видимой полосе выбирает его; Ctrl+Alt+Enter ничего не выбирает

### Requirement: Сочетания app и страница «Keyboard» не расходятся
Каждая клавиатурная привязка рабочего места, экрана настроек и диалогов app SHALL быть строкой страницы «Keyboard» с теми же клавишами. Каждая строка страницы SHALL быть привязкой, которая выполняет своё действие в указанном месте. Короткие подсказки сочетаний на рабочем месте SHALL показывать клавиши той привязки, которой подсказка соответствует.

Change, который вводит, меняет или убирает сочетание, SHALL в том же change менять строку страницы «Keyboard», её тексты `en` и `ru` и проверку нажатием. Основной модификатор SHALL привязываться и к Ctrl, и к ⌘ на всех платформах, как до этого change. Исключение — сочетания ответа на одобрение: у них свои клавиши на macOS и на остальных ОС, и на каждой платформе привязываются только её клавиши (Ctrl+Y на Windows и Linux остаётся повтором правки). Привязки НЕ SHALL переназначаться этим требованием (DSK-18).

#### Scenario: Каждая строка проверена нажатием
- **WHEN** тест нажимает клавиши каждой строки таблицы в её месте: Ctrl-вариант на всех платформах, ⌘-вариант — у строк с основным модификатором; у строк ответа на одобрение — клавиши macOS при платформе macOS и клавиши Windows и Linux при платформе Linux
- **THEN** выполняется действие строки. Например, `allow-always` выбирает вариант `allow_always` видимого активного одобрения, а `leave-settings` возвращает на рабочее место без `session/cancel`

#### Scenario: Привязка вне списка
- **WHEN** в коде кита или app появляется привязка клавиш, которой нет на странице «Keyboard»
- **THEN** тест-сторож пакета падает и называет файл с этой привязкой

#### Scenario: Отправка и одобрение на разных клавишах
- **WHEN** ждёт видимое активное одобрение, и пользователь нажимает Cmd/Ctrl+Enter один раз с фокусом на полосе одобрения, а другой раз с фокусом в композере с текстом
- **THEN** в первом случае ничего не выбрано, во втором сообщение поставлено в очередь, а одобрение по-прежнему ждёт; ⌘Y (Alt+Shift+Y на Windows и Linux) в обоих местах выбирает `allow_once`
