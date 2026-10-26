import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

/// Full-screen master-detail log viewer, opened from `/logs` (the command
/// palette) and from the docked [WorkbenchDebugLogPane]'s "Expand" button —
/// both call [show], so there is exactly one open path
/// (`replace-debug-log-panel-with-fluent/design.md`, Decision 4).
///
/// Wraps `structured_log_fluent`'s [FluentLogViewerPage] as-is: `showDialog`
/// pushes a route, so `Navigator.canPop` is true and the page's own
/// back-button appears without extra chrome here. `showDialog`'s defaults
/// already satisfy the spec's closing/dimming requirements — `dismissWithEsc:
/// true` (Esc closes it) and a dark `barrierColor` (dims the workbench
/// behind it) — and pushing/popping a route never touches
/// [CodeLabShellState], so the workbench underneath is unchanged on close.
class DebugLogViewerDialog extends StatelessWidget {
  const DebugLogViewerDialog({required this.controller, super.key});

  final LogViewerController controller;

  static Future<void> show(BuildContext context, LogBuffer logBuffer) {
    final controller = LogViewerController(logBuffer);
    return showDialog<void>(
      context: context,
      builder: (_) => DebugLogViewerDialog(controller: controller),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: FluentLogViewerPage(controller: controller),
    );
  }
}
