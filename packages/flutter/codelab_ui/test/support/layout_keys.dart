// Клавиши нелатинских и нестандартных раскладок для тестов (change
// `fix-approval-focus`, итерация 8, D16).
//
// Почему: при русской раскладке физическая клавиша K приходит логической
// «л», и каталог `CodeLabShortcut`, сравнивавший только логическую клавишу,
// не срабатывал. Тест должен подавать событие так, как его отдаёт ОС:
// логическая клавиша раскладки на физической позиции US.
//
// Для чего: единая таблица «латинская клавиша комбинации → кириллическая
// логическая + физическая позиция», чтобы тесты каталога, привязок и трекера
// удержания не расходились. Физические клавиши в `test/` сторож 1 не
// проверяет (он читает только `lib/src`).
//
// Как использовать: `russianKeyFor(LogicalKeyboardKey.keyK)` даёт пару для
// «л» на физической K; `simulateLayoutKey` нажимает и отпускает такую пару.
// Причина ignore: `KeyEventManager` объявлен устаревшим для приложений, но это
// единственный способ подать в тест событие с логической клавишей, которой нет
// в таблицах `flutter_test` (кириллица); `HardwareKeyboard.addHandler` только
// принимает события.
// ignore_for_file: deprecated_member_use
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Клавиша раскладки: [logical] — что вернула раскладка, [physical] — позиция
/// на клавиатуре (USB HID).
typedef LayoutKey = ({
  LogicalKeyboardKey logical,
  PhysicalKeyboardKey physical,
});

/// Русская раскладка для клавиш, которые есть в каталоге: латинская клавиша
/// комбинации (позиция US) → кириллица на той же позиции.
final Map<LogicalKeyboardKey, LayoutKey> _russian = {
  LogicalKeyboardKey.keyQ: (
    logical: LogicalKeyboardKey(0x0439), // й
    physical: PhysicalKeyboardKey.keyQ,
  ),
  LogicalKeyboardKey.keyW: (
    logical: LogicalKeyboardKey(0x0446), // ц
    physical: PhysicalKeyboardKey.keyW,
  ),
  LogicalKeyboardKey.keyE: (
    logical: LogicalKeyboardKey(0x0443), // у
    physical: PhysicalKeyboardKey.keyE,
  ),
  LogicalKeyboardKey.keyY: (
    logical: LogicalKeyboardKey(0x043d), // н
    physical: PhysicalKeyboardKey.keyY,
  ),
  LogicalKeyboardKey.keyA: (
    logical: LogicalKeyboardKey(0x0444), // ф
    physical: PhysicalKeyboardKey.keyA,
  ),
  LogicalKeyboardKey.keyX: (
    logical: LogicalKeyboardKey(0x0447), // ч
    physical: PhysicalKeyboardKey.keyX,
  ),
  LogicalKeyboardKey.keyK: (
    logical: LogicalKeyboardKey(0x043b), // л
    physical: PhysicalKeyboardKey.keyK,
  ),
  LogicalKeyboardKey.keyN: (
    logical: LogicalKeyboardKey(0x0442), // т
    physical: PhysicalKeyboardKey.keyN,
  ),
  LogicalKeyboardKey.keyB: (
    logical: LogicalKeyboardKey(0x0438), // и
    physical: PhysicalKeyboardKey.keyB,
  ),
  LogicalKeyboardKey.comma: (
    logical: LogicalKeyboardKey(0x0431), // б
    physical: PhysicalKeyboardKey.comma,
  ),
};

/// Русская раскладка клавиши [latin] из комбинации каталога; ошибка теста,
/// если клавиши нет в таблице (новая запись каталога требует строки здесь).
LayoutKey russianKeyFor(LogicalKeyboardKey latin) {
  final key = _russian[latin];
  if (key == null) {
    throw ArgumentError('нет русской клавиши для ${latin.keyLabel}');
  }
  return key;
}

/// Есть ли у [latin] русская клавиша, то есть зависит ли она от раскладки
/// (буква или знак); Esc, Enter, стрелки в таблице не нужны.
bool isLayoutDependent(LogicalKeyboardKey latin) => _russian.containsKey(latin);

/// Нажимает и отпускает [key] как событие раскладки: логическая и физическая
/// клавиши заданы отдельно.
///
/// Почему не `simulateKeyDownEvent`: симулятор `flutter_test` требует, чтобы
/// логическая клавиша была в его таблицах кодов ОС (`keyCode != null`), а
/// кириллицы там нет; событие подаётся напрямую в `KeyEventManager` как
/// `ui.KeyData`, какой его отдаёт движок.
Future<void> simulateLayoutKey(WidgetTester tester, LayoutKey key) async {
  final manager = ServicesBinding.instance.keyEventManager;
  for (final type in const [ui.KeyEventType.down, ui.KeyEventType.up]) {
    manager.handleKeyData(
      ui.KeyData(
        timeStamp: Duration.zero,
        type: type,
        physical: key.physical.usbHidUsage,
        logical: key.logical.keyId,
        character: type == ui.KeyEventType.down
            ? String.fromCharCode(key.logical.keyId)
            : null,
        // Синтезированное событие `KeyEventManager` отдаёт сразу, не ожидая
        // парного сырого сообщения платформы, которого у теста нет.
        synthesized: true,
      ),
    );
    await tester.pump();
  }
}
