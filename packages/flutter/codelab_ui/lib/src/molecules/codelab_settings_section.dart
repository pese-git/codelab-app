import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/codelab_text.dart';

/// Секция страницы настроек: подзаголовок и столбец строк.
///
/// Почему: в макете настроек («Profiles», «Behavior») подзаголовок 14 px
/// отступает от предыдущего блока на 18 px, а карточки идут столбцом с
/// промежутком 4 px. Эти размеры должны быть в одном месте, а не на каждой
/// странице (design.md change `add-app-settings-shell`, D16).
///
/// Для чего: только вёрстка группы; содержимое строк задаёт владелец.
///
/// Как использовать: `CodeLabSettingsSection(title: 'Behavior', children:
/// [CodeLabSettingsRow(...), ...])`; ключ теста — обычный `key:`.
class CodeLabSettingsSection extends StatelessWidget {
  const CodeLabSettingsSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;

  /// Строки секции сверху вниз: [CodeLabSettingsRow], карточки профилей.
  final List<Widget> children;

  static const _rowGap = 4.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: CodeLabText(title, role: CodeLabTextRole.strong),
          ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: _rowGap),
            children[i],
          ],
        ],
      ),
    );
  }
}
