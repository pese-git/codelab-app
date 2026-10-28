import 'package:fluent_ui/fluent_ui.dart';

/// Роль текста в типографике Fluent.
///
/// [mono] — моноширинный текст команд, путей и вывода инструментов: в ленте
/// они должны читаться как код, а не как проза (change
/// `redesign-transcript-rows`, D5).
enum CodeLabTextRole { title, subtitle, body, strong, caption, mono }

class CodeLabText extends StatelessWidget {
  const CodeLabText(
    this.data, {
    this.role = CodeLabTextRole.body,
    this.maxLines,
    this.overflow,
    this.color,
    super.key,
  });

  final String data;
  final CodeLabTextRole role;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Overrides the role's default color when set — for callers that need to
  /// convey extra meaning (e.g. tone) through text color where there's no
  /// room for a separate badge.
  final Color? color;

  /// Стиль роли [role] в текущей теме — для составного текста
  /// (`Text.rich`), где часть фразы набрана другой ролью, например
  /// моноширинная цель в строке вызова «Read lib/main.dart».
  static TextStyle? styleOf(BuildContext context, CodeLabTextRole role) =>
      _styleForRole(FluentTheme.of(context).typography, role);

  @override
  Widget build(BuildContext context) {
    final style = styleOf(context, role);
    return Text(
      data,
      maxLines: maxLines,
      overflow: overflow,
      style: color == null ? style : style?.copyWith(color: color),
    );
  }
}

TextStyle? _styleForRole(Typography typography, CodeLabTextRole role) {
  return switch (role) {
    CodeLabTextRole.title => typography.title,
    CodeLabTextRole.subtitle => typography.subtitle,
    CodeLabTextRole.body => typography.body,
    CodeLabTextRole.strong => typography.bodyStrong,
    CodeLabTextRole.caption => typography.caption,
    CodeLabTextRole.mono => typography.body?.copyWith(
      fontFamily: 'Menlo',
      fontFamilyFallback: _monoFallback,
      fontSize: 12.5,
    ),
  };
}

/// Запасные моноширинные шрифты: на Windows нет Menlo, на Linux — ни Menlo,
/// ни Consolas.
const _monoFallback = [
  'SF Mono',
  'Consolas',
  'Cascadia Mono',
  'DejaVu Sans Mono',
  'Courier New',
  'monospace',
];
