// Поиск по таблице сочетаний (задача 3.1 change `add-app-keyboard-page`;
// design.md D8; spec app-settings «Страница «Keyboard»: поиск», сценарии
// «Поиск по действию», «Поиск по клавише в чужой нотации», «Поиск по клавише
// словами», «Английский текст при русском интерфейсе», «Переведённый текст
// при русском интерфейсе», «Ничего не найдено»).
//
// Красный до задачи 3.2: `filterKeyboardShortcuts` — заглушка, возвращает
// пустой список. Записи собираются из настоящего каталога кита: нотации
// клавиш берутся у комбинаций, тексты действия — из таблицы спецификации.

import 'package:codelab_desktop/features/settings/application/keyboard_shortcut_search.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/keyboard_rows.dart';

/// Запись каталога с английским текстом из таблицы; [action] подменяет текст
/// языка интерфейса (русский при русском интерфейсе).
KeyboardShortcutEntry _entry(
  CodeLabShortcut shortcut, {
  Map<String, String> translated = const {},
}) {
  final row = keyboardRows.singleWhere((r) => r.id == shortcut.id);
  return KeyboardShortcutEntry(
    shortcut: shortcut,
    action: translated[row.id] ?? row.action,
    englishAction: row.action,
    notations: [
      for (final combo in shortcut.combos) ...combo.searchNotations(),
    ],
  );
}

List<KeyboardShortcutEntry> _entries({
  Map<String, String> translated = const {},
}) => [
  for (final shortcut in CodeLabShortcut.values)
    // Временно (change `fix-approval-focus`): строка «Go to approval» на
    // страницу попадёт с задачей 4.1/4.2, тогда пропуск и эталон строки уйдут.
    if (shortcut != CodeLabShortcut.goToApproval)
      _entry(shortcut, translated: translated),
];

List<String> _ids(List<KeyboardShortcutEntry> found) => [
  for (final entry in found) entry.shortcut.id,
];

List<String> _allIds() => [for (final row in keyboardRows) row.id];

void main() {
  test('пустой запрос показывает все записи в порядке каталога', () {
    expect(_ids(filterKeyboardShortcuts(_entries(), '')), _allIds());
    expect(_ids(filterKeyboardShortcuts(_entries(), '   ')), _allIds());
  });

  test('поиск по действию: «sidebar» — только toggle-sidebar', () {
    expect(_ids(filterKeyboardShortcuts(_entries(), 'sidebar')), [
      'toggle-sidebar',
    ]);
  });

  test('регистр и пробелы по краям не важны', () {
    expect(_ids(filterKeyboardShortcuts(_entries(), '  SideBar  ')), [
      'toggle-sidebar',
    ]);
  });

  test('поиск по клавише в чужой нотации: ⌘K находит command-palette', () {
    expect(_ids(filterKeyboardShortcuts(_entries(), '⌘K')), [
      'command-palette',
    ]);
  });

  test('«ctrl k», «Ctrl+K» и «cmd+k» находят command-palette', () {
    for (final query in const ['ctrl k', 'Ctrl+K', 'cmd+k', '⌘K']) {
      expect(
        _ids(filterKeyboardShortcuts(_entries(), query)),
        contains('command-palette'),
        reason: query,
      );
    }
  });

  test('поиск по клавише словами: «ctrl shift e» — только toggle-files', () {
    expect(_ids(filterKeyboardShortcuts(_entries(), 'ctrl shift e')), [
      'toggle-files',
    ]);
  });

  test('плюсы и пробелы в запросе не мешают: «Ctrl + Shift + E»', () {
    expect(_ids(filterKeyboardShortcuts(_entries(), 'Ctrl + Shift + E')), [
      'toggle-files',
    ]);
  });

  test('символы macOS и слова macOS находят allow-always', () {
    for (final query in const ['⌥⌘⏎', 'Option+Cmd+Enter', 'ctrl alt enter']) {
      expect(
        _ids(filterKeyboardShortcuts(_entries(), query)),
        contains('allow-always'),
        reason: query,
      );
    }
  });

  group('русский интерфейс', () {
    final translated = {
      'allow-always': 'Всегда разрешать',
      'cancel-turn': 'Отменить идущий ход',
    };

    test('английский текст действия находит строку: «allow always»', () {
      final found = filterKeyboardShortcuts(
        _entries(translated: translated),
        'allow always',
      );

      expect(_ids(found), ['allow-always']);
      expect(found.single.action, 'Всегда разрешать');
    });

    test('часть перевода находит строку: «идущий ход»', () {
      expect(
        _ids(
          filterKeyboardShortcuts(
            _entries(translated: translated),
            'идущий ход',
          ),
        ),
        ['cancel-turn'],
      );
    });
  });

  test('ничего не найдено: «zzz» даёт пустой список, а «» — все записи', () {
    // Первая проверка отличает пустой результат от «функция ничего не
    // отбирает».
    expect(filterKeyboardShortcuts(_entries(), ''), hasLength(19));
    expect(filterKeyboardShortcuts(_entries(), 'zzz'), isEmpty);
  });

  test('поиск не идёт по «Where»: «files tree» ничего не находит', () {
    expect(filterKeyboardShortcuts(_entries(), ''), hasLength(19));
    // «Files tree» — текст «Where» строк дерева, но не их действия.
    expect(filterKeyboardShortcuts(_entries(), 'files tree'), isEmpty);
  });
}
