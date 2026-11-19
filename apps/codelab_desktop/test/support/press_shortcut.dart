import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Нажимает комбинацию записи каталога кита: клавиши берутся из
/// `CodeLabShortcut`, а не из литералов теста.
///
/// Почему: сторож 2 (`keyboard_bindings_test.dart`, design.md D3) проверяет,
/// что привязка выполняет действие *строки каталога*; тест с отдельным
/// списком клавиш разошёлся бы с каталогом при первой правке.
///
/// Как использовать: `await pressShortcut(tester, CodeLabShortcut.send,
/// useMeta: true)`. [combo] — индекс комбинации записи (у «↑ / ↓» их две),
/// [useMeta] — ⌘ вместо Ctrl для основного модификатора. Пустой каталог —
/// ошибка теста, а не молчаливый пропуск.
Future<void> pressShortcut(
  WidgetTester tester,
  CodeLabShortcut shortcut, {
  int combo = 0,
  bool useMeta = false,
  Duration settle = const Duration(milliseconds: 100),
}) async {
  expect(
    shortcut.combos,
    isNotEmpty,
    reason: 'у записи ${shortcut.name} нет комбинаций',
  );
  final keys = shortcut.combos[combo];
  final modifiers = <LogicalKeyboardKey>[
    if (keys.primary)
      useMeta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
    if (keys.alt) LogicalKeyboardKey.altLeft,
    if (keys.shift) LogicalKeyboardKey.shiftLeft,
  ];
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyEvent(keys.key);
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump(settle);
}
