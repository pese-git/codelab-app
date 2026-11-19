import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Виджеты, которые рисуют [needle] видимым текстом.
///
/// Почему не `find.textContaining`: он видит и `EditableText` скрытых полей
/// (`PasswordBox`), где значение лежит в контроллере, но на экран не
/// выводится. Не годится и проверка `w is Text`: она пропускает `Text.rich`.
/// Видимый текст любого `Text` и `Text.rich` — это `RichText`, а
/// `EditableText` его не создаёт, поэтому поле ввода проверку не задевает.
///
/// Как использовать: `expect(findVisibleTextContaining(leak), findsNothing)`.
Finder findVisibleTextContaining(String needle) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText().contains(needle),
  description: 'RichText с «$needle»',
);
