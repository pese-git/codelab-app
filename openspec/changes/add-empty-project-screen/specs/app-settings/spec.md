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
| Global | `new-session` | New session | ⌘ N | Ctrl N | Workbench |
| Global | `open-folder` | Open a folder as the project | ⌘ O | Ctrl O | Workbench |
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

Сочетаний, которых нет среди привязок сборки, на странице НЕ SHALL быть. В этой сборке это Cmd/Ctrl+/, Cmd/Ctrl+Shift+I, Cmd/Ctrl+Shift+F, Cmd/Ctrl+\\, Cmd/Ctrl+Shift+D, Cmd/Ctrl+Shift+Enter, Alt+Enter, Ctrl+\` и Ctrl+Shift+\`; Alt+←/→ тоже не привязаны. Alt+←/→ зарезервированы за навигацией инспектора (DSK-18) и строкой НЕ SHALL быть, пока не привязаны (решение пользователя Q2, 2026-11-19). Навигация дерева Files и меню команд после `/` — привязки app и показываются строками (решение пользователя Q3). Строка `go-to-approval` — привязка рабочего места, которая ставит клавиатурный фокус на полосу решения активного одобрения (spec agent-workbench-ui «Переход к ожидающему одобрению с клавиатуры»). Строки `allow-once`, `allow-always`, `reject-once`, `reject-always` — сочетания ответа, которые действуют с любого места рабочего места и отвечают самому раннему ожидающему одобрению активной сессии (spec agent-workbench-ui «Ответ на одобрение сочетанием с любого места рабочего места»); их клавиши различаются по платформам не только обозначениями. Стандартное поведение элементов управления строками НЕ SHALL показываться: Tab, Space и Enter на кнопке, правка и копирование текста в полях.

#### Scenario: Полный список на Linux
- **WHEN** платформа — Linux, и пользователь открывает «Keyboard» без запроса поиска
- **THEN** таблица показывает пять групп и 21 строку таблицы выше в том же порядке, с клавишами из колонки «Windows, Linux»

#### Scenario: Сочетаний без поведения нет
- **WHEN** пользователь открывает «Keyboard»
- **THEN** на странице нет строк с клавишами `/`, `I`, `F`, `\`, `D`, `` ` `` и строки steering, а также строки Alt+← и Alt+→

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

#### Scenario: Строка «Open folder»
- **WHEN** платформа — macOS, и пользователь открывает «Keyboard»
- **THEN** в группе `Global` сразу после `new-session` стоит строка `open-folder` с действием `Open a folder as the project`, кейкапами `⌘` и `O` и местом `Workbench` (design.md change `add-empty-project-screen`, D7)

#### Scenario: Поиск строки «Open folder»
- **WHEN** пользователь вводит `ctrl o`
- **THEN** видна только группа `Global` со строкой `open-folder`
