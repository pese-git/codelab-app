import 'package:fluent_ui/fluent_ui.dart';

import 'codelab_text.dart';

/// Заголовок `ContentDialog` в размере `typography.subtitle` (20 px, w600).
///
/// Почему: `ContentDialog` по умолчанию ставит крупный заголовок (~28 px), а
/// макеты (артборд `AddProfile`, fluent.css `.t-sub`) задают подзаголовок.
/// Заголовок нужен в нескольких диалогах, поэтому стиль вынесен в один виджет
/// вместо хардкода размера.
///
/// Для чего: чистая презентация, без логики.
///
/// Как использовать: `ContentDialog(title: CodeLabDialogTitle('Текст'), ...)`.
class CodeLabDialogTitle extends StatelessWidget {
  const CodeLabDialogTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: CodeLabText.styleOf(context, CodeLabTextRole.subtitle));
}
