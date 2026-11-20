/// Таблица страницы «Keyboard» из спецификации app-settings «Страница
/// «Keyboard»: строки таблицы» (change `add-app-keyboard-page`, D1).
///
/// Почему отдельно: ту же таблицу нужны тесты поиска, страницы и русского
/// интерфейса; тексты — символ в символ со спецификацией.
library;

/// Строка таблицы: id, группа, английские тексты, кейкапы по платформам.
typedef KeyboardRow = ({
  String id,
  String group,
  String action,
  String where,
  List<String> linuxCaps,
  List<String> macCaps,
});

KeyboardRow _r(
  String id,
  String group,
  String action,
  List<String> linux,
  List<String> mac,
  String where,
) => (
  id: id,
  group: group,
  action: action,
  where: where,
  linuxCaps: linux,
  macCaps: mac,
);

/// Группы по порядку: slug и английский заголовок.
const keyboardGroups = [
  (slug: 'global', title: 'Global'),
  (slug: 'navigation', title: 'Navigation'),
  (slug: 'transcript', title: 'Transcript'),
  (slug: 'composer', title: 'Composer'),
  (slug: 'approvals', title: 'Approvals'),
];

const _approvalWhere =
    'Pending approval in focus, when the agent offers this option';

/// 19 строк в порядке спецификации.
final keyboardRows = <KeyboardRow>[
  _r(
    'command-palette',
    'global',
    'Open the command palette',
    ['Ctrl', 'K'],
    ['⌘', 'K'],
    'Workbench',
  ),
  _r(
    'new-session',
    'global',
    'New session',
    ['Ctrl', 'N'],
    ['⌘', 'N'],
    'Workbench, when a project is selected',
  ),
  _r(
    'open-settings',
    'global',
    'Open settings',
    ['Ctrl', ','],
    ['⌘', ','],
    'Workbench',
  ),
  _r(
    'close-overlay',
    'global',
    'Close the command palette, a dialog or a sliding panel',
    ['Esc'],
    ['Esc'],
    'Command palette, dialog or sliding panel',
  ),
  _r(
    'leave-settings',
    'global',
    'Back to the workbench',
    ['Esc'],
    ['Esc'],
    'Settings',
  ),
  _r(
    'toggle-sidebar',
    'navigation',
    'Show or hide the sidebar',
    ['Ctrl', 'B'],
    ['⌘', 'B'],
    'Workbench',
  ),
  _r(
    'toggle-files',
    'navigation',
    'Show or hide the Files pane',
    ['Ctrl', 'Shift', 'E'],
    ['⇧', '⌘', 'E'],
    'Workbench, when the Files pane is available',
  ),
  _r(
    'file-tree-move',
    'navigation',
    'Move through files',
    ['↑', '↓'],
    ['↑', '↓'],
    'Files tree',
  ),
  _r(
    'file-tree-fold',
    'navigation',
    'Expand or collapse a folder',
    ['→', '←'],
    ['→', '←'],
    'Files tree, on a folder',
  ),
  _r(
    'file-tree-open',
    'navigation',
    'Open a file or expand a folder',
    ['Enter'],
    ['⏎'],
    'Files tree',
  ),
  _r(
    'cancel-turn',
    'transcript',
    'Cancel the running turn',
    ['Esc'],
    ['Esc'],
    'Workbench or composer, while a turn runs',
  ),
  _r(
    'send',
    'composer',
    'Send the message; it is queued while the session is busy',
    ['Ctrl', 'Enter'],
    ['⌘', '⏎'],
    'Composer',
  ),
  _r(
    'command-menu-move',
    'composer',
    'Move through commands',
    ['↑', '↓'],
    ['↑', '↓'],
    'Command menu after /',
  ),
  _r(
    'command-menu-run',
    'composer',
    'Run the highlighted command',
    ['Enter'],
    ['⏎'],
    'Command menu after /',
  ),
  _r(
    'command-menu-close',
    'composer',
    'Close the command menu',
    ['Esc'],
    ['Esc'],
    'Command menu after /',
  ),
  _r(
    'allow-once',
    'approvals',
    'Allow once',
    ['Ctrl', 'Enter'],
    ['⌘', '⏎'],
    _approvalWhere,
  ),
  _r(
    'allow-always',
    'approvals',
    'Allow always',
    ['Ctrl', 'Alt', 'Enter'],
    ['⌥', '⌘', '⏎'],
    _approvalWhere,
  ),
  _r(
    'reject-once',
    'approvals',
    'Reject once',
    ['Ctrl', 'Backspace'],
    ['⌘', '⌫'],
    _approvalWhere,
  ),
  _r(
    'reject-always',
    'approvals',
    'Reject always',
    ['Ctrl', 'Alt', 'Backspace'],
    ['⌥', '⌘', '⌫'],
    _approvalWhere,
  ),
];
