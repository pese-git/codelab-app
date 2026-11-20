// Сколько Alt и Shift зажаты до нажатия буквы ответа на одобрение (решение
// пользователя 2026-11-20, change `fix-approval-focus`, D14).
//
// Почему: на Windows и Linux Alt+Shift — смена раскладки; буква, наложившаяся
// на неё, не должна отвечать. Кит не решает, сколько достаточно (политика у
// хоста), он только сообщает время зажатия модификаторов на управляемых часах.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/layout_keys.dart';

void main() {
  var now = DateTime.utc(2026, 11, 20, 12);
  final reported = <Duration?>[];

  setUp(() {
    now = DateTime.utc(2026, 11, 20, 12);
    reported.clear();
  });

  Future<void> pumpShortcuts(WidgetTester tester) async {
    await tester.pumpWidget(
      FluentApp(
        home: CodeLabWorkbenchShortcuts(
          clock: () => now,
          onAnswerApproval: (kind, held) => reported.add(held),
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );
    await tester.pump();
  }

  CodeLabKeyCombo comboOf(TargetPlatform platform) =>
      CodeLabShortcut.allowOnce.combosFor(platform).single;

  testWidgets('Linux: модификаторы нажаты вместе с буквой — зажатие нулевое', (
    tester,
  ) async {
    await pumpShortcuts(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(comboOf(TargetPlatform.linux).key);

    expect(reported, [Duration.zero]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Windows: модификаторы зажаты заранее — сообщается срок', (
    tester,
  ) async {
    await pumpShortcuts(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    now = now.add(const Duration(milliseconds: 200));
    await tester.sendKeyEvent(comboOf(TargetPlatform.windows).key);

    expect(reported, [const Duration(milliseconds: 200)]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('отпускание модификатора обнуляет отсчёт', (tester) async {
    await pumpShortcuts(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    now = now.add(const Duration(seconds: 1));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(comboOf(TargetPlatform.linux).key);

    expect(reported, [Duration.zero]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('macOS: условия зажатия нет — сообщается null', (tester) async {
    await pumpShortcuts(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(comboOf(TargetPlatform.macOS).key);

    expect(reported, [null]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  // Итерация 8 `fix-approval-focus` (задача 8.1, D16): при русской раскладке
  // Alt+Shift+Y приходит как «н» на физической Y; срок зажатия сообщается так
  // же, как для латинской Y. Красный до задачи 8.2.
  testWidgets('русская раскладка: Alt+Shift+«н» — срок передаётся так же', (
    tester,
  ) async {
    await pumpShortcuts(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    now = now.add(const Duration(milliseconds: 200));
    await simulateLayoutKey(
      tester,
      russianKeyFor(comboOf(TargetPlatform.windows).key),
    );

    expect(reported, [const Duration(milliseconds: 200)]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
