import 'package:fluent_ui/fluent_ui.dart';

enum CodeLabTextRole { title, subtitle, body, strong, caption }

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

  @override
  Widget build(BuildContext context) {
    final style = _styleForRole(FluentTheme.of(context).typography, role);
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
  };
}
