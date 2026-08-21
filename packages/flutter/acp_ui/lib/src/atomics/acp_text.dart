import 'package:fluent_ui/fluent_ui.dart';

enum AcpTextRole { title, subtitle, body, strong, caption }

class AcpText extends StatelessWidget {
  const AcpText(
    this.data, {
    this.role = AcpTextRole.body,
    this.maxLines,
    this.overflow,
    super.key,
  });

  final String data;
  final AcpTextRole role;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      maxLines: maxLines,
      overflow: overflow,
      style: _styleForRole(FluentTheme.of(context).typography, role),
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
