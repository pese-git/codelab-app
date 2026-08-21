import 'package:fluent_ui/fluent_ui.dart';

class AcpProgressIndicator extends StatelessWidget {
  const AcpProgressIndicator({
    this.value,
    this.semanticLabel,
    this.size = 18,
    super.key,
  });

  final double? value;
  final String? semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ProgressRing(value: value, semanticLabel: semanticLabel),
    );
  }
}
