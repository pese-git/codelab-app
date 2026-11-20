// Клавиши нелатинских и нестандартных раскладок для тестов app (change
// `fix-approval-focus`, итерация 8, D16).
//
// Почему: при русской раскладке физическая клавиша K приходит логической
// «л», и сочетания каталога `CodeLabShortcut` с буквой не срабатывали.
// Тест подаёт событие так, как его отдаёт ОС: логическая клавиша раскладки
// на физической позиции US.
//
// Для чего: общий помощник сценариев «палитра и настройки», «ответ на
// одобрение», «AZERTY» и «кириллица без модификаторов». Физические клавиши
// в `test/` сторож 1 не проверяет (он читает только `lib/`).
//
// Как использовать: `pressLayoutKey(tester, russianKey(LogicalKeyboardKey.keyK),
// meta: true)`. Событие идёт в `KeyEventManager` как синтезированный
// `ui.KeyData`: симулятор `flutter_test` не знает кириллицы в таблицах кодов
// ОС (`keyCode != null`), а синтезированное событие не ждёт парного сырого
// сообщения платформы.
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

/// Русская клавиша на позиции латинской [latin] из сочетаний каталога.
LayoutKey russianKey(LogicalKeyboardKey latin) {
  final key = <LogicalKeyboardKey, LayoutKey>{
    LogicalKeyboardKey.keyQ: (
      logical: LogicalKeyboardKey(0x0439), // й
      physical: PhysicalKeyboardKey.keyQ,
    ),
    LogicalKeyboardKey.keyY: (
      logical: LogicalKeyboardKey(0x043d), // н
      physical: PhysicalKeyboardKey.keyY,
    ),
    LogicalKeyboardKey.keyA: (
      logical: LogicalKeyboardKey(0x0444), // ф
      physical: PhysicalKeyboardKey.keyA,
    ),
    LogicalKeyboardKey.keyK: (
      logical: LogicalKeyboardKey(0x043b), // л
      physical: PhysicalKeyboardKey.keyK,
    ),
    LogicalKeyboardKey.comma: (
      logical: LogicalKeyboardKey(0x0431), // б
      physical: PhysicalKeyboardKey.comma,
    ),
  }[latin];
  if (key == null) {
    throw ArgumentError('нет русской клавиши для ${latin.keyLabel}');
  }
  return key;
}

/// Французская AZERTY (macOS): на физической W напечатана Z.
const LayoutKey azertyZ = (
  logical: LogicalKeyboardKey.keyZ,
  physical: PhysicalKeyboardKey.keyW,
);

/// Французская AZERTY (macOS): на физической Z напечатана W.
const LayoutKey azertyW = (
  logical: LogicalKeyboardKey.keyW,
  physical: PhysicalKeyboardKey.keyZ,
);

/// Нажимает [key] с модификаторами и отпускает. [afterModifiers] вызывается
/// после нажатия модификаторов и до клавиши: так тест сдвигает управляемые
/// часы («Alt и Shift зажаты заранее», D14).
Future<void> pressLayoutKey(
  WidgetTester tester,
  LayoutKey key, {
  bool meta = false,
  bool control = false,
  bool alt = false,
  bool shift = false,
  void Function()? afterModifiers,
  Duration settle = const Duration(milliseconds: 100),
}) async {
  final modifiers = [
    if (control) LogicalKeyboardKey.controlLeft,
    if (meta) LogicalKeyboardKey.metaLeft,
    if (alt) LogicalKeyboardKey.altLeft,
    if (shift) LogicalKeyboardKey.shiftLeft,
  ];
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  afterModifiers?.call();
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
        synthesized: true,
      ),
    );
    await tester.pump();
  }
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump(settle);
}
