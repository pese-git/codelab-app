import 'package:fluent_ui/fluent_ui.dart';

enum AcpTextRole { title, subtitle, body, strong, caption }

class AcpText extends StatelessWidget {
  const AcpText(
    this.data, {
    this.role = AcpTextRole.body,
    this.maxLines,
    this.overflow,
    this.color,
    super.key,
  });

  final String data;
  final AcpTextRole role;
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

TextStyle? _styleForRole(Typography typography, AcpTextRole role) {
  return switch (role) {
    AcpTextRole.title => typography.title,
    AcpTextRole.subtitle => typography.subtitle,
    AcpTextRole.body => typography.body,
    AcpTextRole.strong => typography.bodyStrong,
    AcpTextRole.caption => typography.caption,
  };
}
