/// Кейкапы сочетания: плашки клавиш и подпись для чтения с экрана.
///
/// Почему: страница «Keyboard» показывает клавиши плашками, как на холсте, а
/// программы чтения с экрана произносят символы ⌥⌘⏎ непредсказуемо (change
/// `add-app-keyboard-page`, D4, D6, D9). Поэтому вид и подпись разведены:
/// плашки из семантики исключены, сочетание читается одной подписью словами.
///
/// Для чего: по плашке на клавишу комбинации, роль `CodeLabTextRole.mono`,
/// рамка с утолщённым нижним краем, цвета только из `FluentTheme`. Для
/// альтернатив (`↑ / ↓`) плашки идут через разделитель, а подпись склеивается
/// сообщением `codeLabShortcutAlternatives` («Up or Down»). Плашки не
/// переносятся и не сжимаются.
///
/// Как использовать: `CodeLabKeycaps(combos: CodeLabShortcut.x.combos)`.
/// Обозначения клавиш выбирает каталог по `defaultTargetPlatform` (D4), сам
/// виджет платформу не проверяет. Клавиши не переводятся (D5).
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;

import '../l10n/strings.dart';
import 'codelab_shortcuts.dart';
import 'codelab_text.dart';

class CodeLabKeycaps extends StatelessWidget {
  const CodeLabKeycaps({required this.combos, super.key});

  /// Комбинации одной строки: несколько — альтернативы.
  final List<CodeLabKeyCombo> combos;

  /// Подпись сочетания словами для чтения с экрана; альтернативы склеены
  /// сообщением каталога. Нужна и строке таблицы, поэтому открыта.
  static String labelOf(BuildContext context, List<CodeLabKeyCombo> combos) {
    final strings = codeLabStringsOf(context);
    final platform = defaultTargetPlatform;
    return combos
        .map((combo) => combo.spokenFor(platform))
        .reduce(strings.codeLabShortcutAlternatives);
  }

  @override
  Widget build(BuildContext context) {
    final muted = FluentTheme.of(context).resources.textFillColorSecondary;
    final platform = defaultTargetPlatform;
    return Semantics(
      label: labelOf(context, combos),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < combos.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: CodeLabText(
                  '/',
                  role: CodeLabTextRole.caption,
                  color: muted,
                ),
              ),
            for (final (j, cap) in combos[i].capsFor(platform).indexed) ...[
              if (j > 0) const SizedBox(width: 4),
              _Keycap(cap),
            ],
          ],
        ],
      ),
    );
  }
}

/// Одна плашка: рамка с утолщённым нижним краем, как на холсте.
class _Keycap extends StatelessWidget {
  const _Keycap(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final stroke = resources.controlStrokeColorDefault;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: resources.controlFillColorDefault,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          top: BorderSide(color: stroke),
          left: BorderSide(color: stroke),
          right: BorderSide(color: stroke),
          bottom: BorderSide(color: stroke, width: 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: CodeLabText(
          text,
          role: CodeLabTextRole.mono,
          maxLines: 1,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }
}
