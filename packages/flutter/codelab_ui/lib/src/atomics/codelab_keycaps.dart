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

/// Плашки клавиш одного сочетания (или альтернатив) с подписью словами.
///
/// Почему: вид (плашки) и чтение с экрана (слова) разведены, иначе программы
/// чтения произносят ⌥⌘⏎ непредсказуемо (D4, D9).
///
/// Для чего: единственный способ показать клавиши в таблице сочетаний и
/// превью; цвета из `FluentTheme`, платформа — `defaultTargetPlatform`
/// через каталог.
///
/// Как использовать: `CodeLabKeycaps(combos: CodeLabShortcut.x.combos)`;
/// несколько комбинаций показываются как альтернативы через `/`. Виджет не
/// фокусируется и не нажимается.
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

  /// Ширина ряда плашек [combos] при текущих шрифтах и масштабе текста.
  ///
  /// Почему: колонка клавиш таблицы должна быть ровно по самой широкой
  /// строке, а не константой: плашки не сжимаются и не переносятся (D9), а
  /// ширина зависит от шрифта и платформы. Для чего: `CodeLabShortcutTable`
  /// берёт максимум по строкам. Как использовать: вызывать в `build` с тем же
  /// [combos], что у виджета; размеры повторяют раскладку `_Keycap`.
  static double widthOf(BuildContext context, List<CodeLabKeyCombo> combos) {
    final platform = defaultTargetPlatform;
    final scaler = MediaQuery.textScalerOf(context);
    double textWidth(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    var total = 0.0;
    for (var i = 0; i < combos.length; i++) {
      if (i > 0) {
        total +=
            12 +
            textWidth(
              '/',
              CodeLabText.styleOf(context, CodeLabTextRole.caption),
            );
      }
      final caps = combos[i].capsFor(platform);
      for (var j = 0; j < caps.length; j++) {
        if (j > 0) total += 4;
        total += 14 + textWidth(caps[j], _capStyle(context, caps[j]));
      }
    }
    return total;
  }

  static bool _isSymbol(String cap) => cap.runes.any((rune) => rune > 0x7f);

  static TextStyle? _capStyle(BuildContext context, String cap) =>
      _isSymbol(cap)
      ? CodeLabText.symbolStyleOf(context, CodeLabTextRole.mono)
      : CodeLabText.styleOf(context, CodeLabTextRole.mono);

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
      // Минимальная высота выравнивает плашки букв и знаков: у шрифтов разная
      // высота строки.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: Center(
            widthFactor: 1,
            // Знаки (не ASCII) — системным шрифтом: в `Menlo` они мельче.
            child: CodeLabText(
              text,
              role: CodeLabTextRole.mono,
              symbols: CodeLabKeycaps._isSymbol(text),
              maxLines: 1,
              overflow: TextOverflow.visible,
            ),
          ),
        ),
      ),
    );
  }
}
