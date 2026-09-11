import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

/// Docked, always-visible debug log panel — a sibling of
/// [WorkbenchInspectorPane], not nested inside it
/// (`replace-debug-log-panel-with-fluent/design.md`, Decision 2/4).
///
/// The header (title + "Expand") is CodeLab's own docking chrome; the body
/// is `structured_log_fluent`'s embeddable [FluentLogViewer] as-is — search,
/// category selector (auto-shown once 2+ categories are present, e.g. once
/// protocol-trace events start arriving), level filter, pause/clear, and a
/// responsive master-detail split all come from the package, not
/// reimplemented here (see the TZ that requested `LogCategoryComboBox`/the
/// embeddable-widget split, both landed in `structured_log_fluent`
/// `0.1.0-dev.3`/`.4`).
///
/// Reads from the same [LogBuffer] as the full-screen viewer opened via
/// [onExpand], but keeps its own [LogViewerController] — search/level/
/// category filter state is local to this panel, not shared with the
/// full-screen view (Decision 4's "two controllers, one buffer"
/// clarification).
class WorkbenchDebugLogPane extends StatefulWidget {
  const WorkbenchDebugLogPane({
    required this.logBuffer,
    required this.onExpand,
    super.key,
  });

  /// Shared with the full-screen viewer — same underlying data, independent
  /// filter/pause state (Decision 4).
  final LogBuffer logBuffer;

  /// Called from the header's "Expand" button — opens the same full-screen
  /// viewer that `/logs` does (Decision 4), never two independent paths.
  final VoidCallback onExpand;

  @override
  State<WorkbenchDebugLogPane> createState() => _WorkbenchDebugLogPaneState();
}

class _WorkbenchDebugLogPaneState extends State<WorkbenchDebugLogPane> {
  late final LogViewerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LogViewerController(widget.logBuffer);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Debug log', style: theme.typography.subtitle),
                ),
                Tooltip(
                  message: 'Expand',
                  child: IconButton(
                    icon: const Icon(FluentIcons.full_screen),
                    onPressed: widget.onExpand,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: FluentLogViewer(controller: _controller)),
        ],
      ),
    );
  }
}
