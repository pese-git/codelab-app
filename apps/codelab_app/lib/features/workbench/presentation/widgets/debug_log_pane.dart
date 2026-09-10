import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log/structured_log.dart' show LogLevel;
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

/// Docked, always-visible debug log panel — a sibling of
/// [WorkbenchInspectorPane], not nested inside it
/// (`replace-debug-log-panel-with-fluent/design.md`, Decision 2/4).
///
/// Reads from the same [LogBuffer] as the full-screen viewer opened via
/// [onExpand], but keeps its own [LogViewerController] — search/level
/// filter state is local to this panel, not shared with the full-screen
/// view (Decision 4's "two controllers, one buffer" clarification).
class WorkbenchDebugLogPane extends StatefulWidget {
  const WorkbenchDebugLogPane({
    required this.logBuffer,
    required this.onExpand,
    super.key,
  });

  /// Shared with the full-screen viewer — same underlying data, independent
  /// filter/pause state (Decision 4).
  final LogBuffer logBuffer;

  /// Called from the header's "Expand" button and from tapping any row —
  /// both open the same full-screen viewer (Decision 4), never two
  /// independent paths.
  final VoidCallback onExpand;

  @override
  State<WorkbenchDebugLogPane> createState() => _WorkbenchDebugLogPaneState();
}

class _WorkbenchDebugLogPaneState extends State<WorkbenchDebugLogPane> {
  late final LogViewerController _controller;
  late final TextEditingController _searchController;

  static const _levelOptions = <String, LogLevel?>{
    'All levels': null,
    'Debug+': LogLevel.debug,
    'Info+': LogLevel.info,
    'Warning+': LogLevel.warning,
    'Error+': LogLevel.error,
  };

  @override
  void initState() {
    super.initState();
    _controller = LogViewerController(widget.logBuffer);
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
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
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextBox(
                    controller: _searchController,
                    placeholder: 'Search',
                    prefix: const Padding(
                      padding: EdgeInsetsDirectional.only(start: 8),
                      child: Icon(FluentIcons.search, size: 12),
                    ),
                    onChanged: (value) => _controller.searchQuery = value,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => ComboBox<LogLevel?>(
                      value: _controller.levelFilter,
                      isExpanded: true,
                      placeholder: const Text('Level'),
                      items: [
                        for (final option in _levelOptions.entries)
                          ComboBoxItem(
                            value: option.value,
                            child: Text(option.key),
                          ),
                      ],
                      onChanged: (value) => _controller.levelFilter = value,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final entries = _controller.visibleEntries.reversed.toList();
                if (entries.isEmpty) {
                  return LogViewerEmptyState(
                    hasLogs: _controller.buffer.entries.value.isNotEmpty,
                    onClearFilters: () {
                      _searchController.clear();
                      _controller
                        ..searchQuery = ''
                        ..levelFilter = null;
                    },
                  );
                }
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) => LogEntryTile(
                    entry: entries[index],
                    selected: false,
                    onTap: widget.onExpand,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
