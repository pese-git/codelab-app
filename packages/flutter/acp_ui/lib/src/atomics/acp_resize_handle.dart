import 'package:fluent_ui/fluent_ui.dart';

/// A thin, draggable divider used between two resizable panes.
///
/// Reports the horizontal pointer delta via [onDelta] on every drag update
/// and, once the gesture completes, calls [onDragEnd] — it holds no width
/// state of its own; the owner decides how (and where) the delta is applied
/// and clamped.
class AcpResizeHandle extends StatelessWidget {
  const AcpResizeHandle({
    required this.onDelta,
    this.onDragEnd,
    this.width = 8,
    super.key,
  });

  final ValueChanged<double> onDelta;
  final VoidCallback? onDragEnd;

  /// Total hit-target width — wider than the visible line so the pointer
  /// doesn't need pixel-perfect precision to grab the border.
  final double width;

  static const double _lineWidth = 1;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDelta(details.delta.dx),
        onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
        child: SizedBox(
          width: width,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: _lineWidth, color: Colors.grey.withAlpha(64)),
            ],
          ),
        ),
      ),
    );
  }
}
