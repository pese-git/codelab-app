import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/acp_resize_handle.dart';

class AcpWorkbenchLayout extends StatelessWidget {
  const AcpWorkbenchLayout({
    required this.commandBar,
    required this.sessionsPane,
    required this.mainPane,
    required this.inspectorPane,
    this.sessionsPaneWidth = 280,
    this.compactSessionsPaneWidth = 176,
    this.inspectorPaneWidth = 320,
    this.collapsedInspectorHeight = 220,
    this.gap = 12,
    this.padding = const EdgeInsets.all(16),
    this.inspectorVisibleInNarrowMode = false,
    this.onSessionsPaneWidthChanged,
    this.onSessionsPaneResizeEnd,
    this.onInspectorPaneWidthChanged,
    this.onInspectorPaneResizeEnd,
    super.key,
  });

  static const commandBarKey = ValueKey('acp-workbench-command-bar');
  static const sessionsPaneKey = ValueKey('acp-workbench-sessions-pane');
  static const mainPaneKey = ValueKey('acp-workbench-main-pane');
  static const inspectorPaneKey = ValueKey('acp-workbench-inspector-pane');

  final Widget commandBar;
  final Widget sessionsPane;
  final Widget mainPane;
  final Widget inspectorPane;
  final double sessionsPaneWidth;
  final double compactSessionsPaneWidth;
  final double inspectorPaneWidth;
  final double collapsedInspectorHeight;
  final double gap;
  final EdgeInsetsGeometry padding;

  /// Whether the narrow-layout body should keep the inspector pane on
  /// stage instead of collapsing it (e.g. after the user explicitly asks
  /// to see the debug log panel via the command palette's `/logs` action).
  final bool inspectorVisibleInNarrowMode;

  /// Called with the sessions pane's width delta on every pointer movement
  /// while the sessions/main divider is being dragged (desktop layout
  /// only) — a delta, not an absolute width, so it stays correct
  /// regardless of when the caller's own rebuild happens to land relative
  /// to the raw pointer events. Null keeps that divider a plain,
  /// non-interactive gap — this layout does not decide where (or whether)
  /// the resulting width is stored.
  final ValueChanged<double>? onSessionsPaneWidthChanged;

  /// Called once the sessions/main divider drag gesture ends. Callers use
  /// this to commit the final accumulated width to their own state,
  /// instead of doing so on every [onSessionsPaneWidthChanged] call.
  final VoidCallback? onSessionsPaneResizeEnd;

  /// Same as [onSessionsPaneWidthChanged] for the main/inspector divider —
  /// the sign is already flipped so a positive value always means "grow
  /// this pane", even though the divider sits on the inspector's left edge.
  final ValueChanged<double>? onInspectorPaneWidthChanged;

  /// Same as [onSessionsPaneResizeEnd] for the main/inspector divider.
  final VoidCallback? onInspectorPaneResizeEnd;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: FluentTheme.of(context).micaBackgroundColor,
      child: Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mode = _AcpWorkbenchLayoutMode.fromWidth(
              constraints.maxWidth,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AcpWorkbenchSlot(
                  slotKey: commandBarKey,
                  label: 'Command bar',
                  child: commandBar,
                ),
                SizedBox(height: gap),
                Expanded(
                  child: switch (mode) {
                    _AcpWorkbenchLayoutMode.desktop => _buildDesktopBody(),
                    _AcpWorkbenchLayoutMode.medium => _buildMediumBody(
                      constraints,
                    ),
                    _AcpWorkbenchLayoutMode.narrow => _buildNarrowBody(),
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDesktopBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AcpWorkbenchSlot(
          slotKey: sessionsPaneKey,
          label: 'Sessions pane',
          width: sessionsPaneWidth,
          child: sessionsPane,
        ),
        _buildDivider(
          onWidthChanged: onSessionsPaneWidthChanged,
          onResizeEnd: onSessionsPaneResizeEnd,
        ),
        Expanded(
          child: _AcpWorkbenchSlot(
            slotKey: mainPaneKey,
            label: 'Main pane',
            expand: true,
            child: mainPane,
          ),
        ),
        _buildDivider(
          onWidthChanged: onInspectorPaneWidthChanged == null
              ? null
              : (dx) => onInspectorPaneWidthChanged!(-dx),
          onResizeEnd: onInspectorPaneResizeEnd,
        ),
        _AcpWorkbenchSlot(
          slotKey: inspectorPaneKey,
          label: 'Inspector pane',
          width: inspectorPaneWidth,
          child: inspectorPane,
        ),
      ],
    );
  }

  Widget _buildDivider({
    required ValueChanged<double>? onWidthChanged,
    required VoidCallback? onResizeEnd,
  }) {
    if (onWidthChanged == null) {
      return SizedBox(width: gap);
    }
    return AcpResizeHandle(
      width: gap,
      onDelta: onWidthChanged,
      onDragEnd: onResizeEnd,
    );
  }

  Widget _buildMediumBody(BoxConstraints constraints) {
    final inspectorHeight = collapsedInspectorHeight.clamp(
      160.0,
      constraints.maxHeight * 0.42,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AcpWorkbenchSlot(
          slotKey: sessionsPaneKey,
          label: 'Sessions pane',
          width: compactSessionsPaneWidth,
          child: sessionsPane,
        ),
        SizedBox(width: gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _AcpWorkbenchSlot(
                  slotKey: mainPaneKey,
                  label: 'Main pane',
                  expand: true,
                  child: mainPane,
                ),
              ),
              SizedBox(height: gap),
              _AcpWorkbenchSlot(
                slotKey: inspectorPaneKey,
                label: 'Inspector pane',
                height: inspectorHeight,
                child: inspectorPane,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowBody() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _AcpWorkbenchSlot(
          slotKey: mainPaneKey,
          label: 'Main pane',
          expand: true,
          child: mainPane,
        ),
        Offstage(
          child: _AcpWorkbenchSlot(
            slotKey: sessionsPaneKey,
            label: 'Sessions pane',
            child: sessionsPane,
          ),
        ),
        Offstage(
          offstage: !inspectorVisibleInNarrowMode,
          child: _AcpWorkbenchSlot(
            slotKey: inspectorPaneKey,
            label: 'Inspector pane',
            child: inspectorPane,
          ),
        ),
      ],
    );
  }
}

enum _AcpWorkbenchLayoutMode {
  desktop,
  medium,
  narrow;

  static _AcpWorkbenchLayoutMode fromWidth(double width) {
    if (width >= 1100) {
      return desktop;
    }
    if (width >= 720) {
      return medium;
    }
    return narrow;
  }
}

class _AcpWorkbenchSlot extends StatelessWidget {
  const _AcpWorkbenchSlot({
    required this.slotKey,
    required this.label,
    required this.child,
    this.width,
    this.height,
    this.expand = false,
  });

  final Key slotKey;
  final String label;
  final Widget child;
  final double? width;
  final double? height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    if (expand) {
      return SizedBox.expand(
        key: slotKey,
        child: Semantics(container: true, label: label, child: child),
      );
    }

    return SizedBox(
      key: slotKey,
      width: width,
      height: height,
      child: Semantics(container: true, label: label, child: child),
    );
  }
}
