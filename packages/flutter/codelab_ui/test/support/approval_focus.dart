import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Помощники тестов клавиатурного фокуса одобрения (change
/// `fix-approval-focus`, задача 1.1).
///
/// Почему: после отказа от `autofocus` полоса не берёт фокус сама, и тесты
/// сочетаний одобрения обязаны сами довести фокус до кнопки — так, как это
/// делает пользователь (Tab). Помощники собраны в одном месте, чтобы прежние
/// сценарии не ослаблялись, а получали один и тот же явный шаг.
///
/// Как использовать: `await tabTo(tester, find.byKey(...))` перед нажатием
/// сочетаний; `focusIsInside(finder)` — проверка, где сейчас фокус.

/// Фокус Flutter сейчас на элементе внутри [finder] (или на нём самом).
bool focusIsInside(WidgetTester tester, Finder finder) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null || finder.evaluate().isEmpty) {
    return false;
  }
  final target = finder.evaluate().first;
  if (identical(context, target)) {
    return true;
  }
  var inside = false;
  context.visitAncestorElements((element) {
    if (identical(element, target)) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

/// Нажимает Tab, пока фокус не окажется внутри [finder]; падает, если за
/// [maxSteps] нажатий до него не дошли.
Future<void> tabTo(
  WidgetTester tester,
  Finder finder, {
  int maxSteps = 8,
}) async {
  for (var i = 0; i < maxSteps && !focusIsInside(tester, finder); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(
    focusIsInside(tester, finder),
    isTrue,
    reason: 'Tab не довёл фокус до $finder за $maxSteps нажатий',
  );
}

/// Нажимает [key] с основным модификатором (Ctrl или ⌘) и, при [alt],
/// с Alt.
Future<void> pressPrimary(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  required bool meta,
  bool alt = false,
}) async {
  final primary = meta
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(primary);
  if (alt) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  }
  await tester.sendKeyEvent(key);
  if (alt) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  }
  await tester.sendKeyUpEvent(primary);
  await tester.pump(const Duration(milliseconds: 100));
}
