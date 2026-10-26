import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// UI-facing recent-project entry — deliberately narrower than the
/// application layer's own recent-project record (no timestamp): ordering by
/// recency is already applied before this list reaches the widget, this only
/// needs to render entries in the order given. See
/// add-open-project-picker/design.md, Decision 5.
class AcpRecentProject {
  const AcpRecentProject({required this.path});

  final String path;

  @override
  bool operator ==(Object other) =>
      other is AcpRecentProject && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// "Open Project" affordance: shows the currently selected project (or a
/// placeholder), and offers a native-folder-browse action plus a list of
/// recently opened projects — never touches `file_selector`/
/// `shared_preferences` itself, both callbacks are delegated to whichever
/// application-layer object owns those platform ports (design.md, Decision
/// 5).
class AcpProjectPicker extends StatelessWidget {
  const AcpProjectPicker({
    required this.currentProjectPath,
    required this.recentProjects,
    required this.onProjectSelected,
    required this.onBrowseRequested,
    super.key,
  });

  final String? currentProjectPath;
  final List<AcpRecentProject> recentProjects;
  final ValueChanged<String> onProjectSelected;
  final VoidCallback onBrowseRequested;

  /// `DropDownButton`'s own title row is `Row(mainAxisSize: min,
  /// mainAxisAlignment: spaceBetween)` (fluent_ui's `DropDownButtonState`) —
  /// it does not wrap `title` in `Expanded`/`Flexible`, so `title` is always
  /// laid out at its unconstrained natural width regardless of how narrow
  /// the button itself ends up (e.g. the sessions pane at
  /// `kSessionsPaneMinWidth`). A `Flexible` inside *our own* title row can't
  /// fix that — it only bounds children of a row that itself is being asked
  /// for its natural size. The only reliable fix is to explicitly cap the
  /// path text's width via [LayoutBuilder] + `ConstrainedBox`, using our own
  /// incoming constraints (the sessions pane's real available width) minus
  /// a fixed reserve for the icon/spacing/chevron/button padding fluent_ui
  /// adds around it.
  static const double _nonTextReserve = 76;
  static const double _minTextWidth = 40;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textMaxWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - _nonTextReserve).clamp(
                _minTextWidth,
                double.infinity,
              )
            : 200.0;

        return DropDownButton(
          key: const ValueKey('open-project-picker'),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(FluentIcons.folder_open, size: 14),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: textMaxWidth),
                child: AcpText(
                  currentProjectPath == null
                      ? 'Open Project'
                      : _displayName(currentProjectPath!),
                  role: AcpTextRole.strong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          items: [
            MenuFlyoutItem(
              key: const ValueKey('open-project-browse'),
              leading: const Icon(FluentIcons.folder_open),
              text: const AcpText('Browse for folder…'),
              onPressed: onBrowseRequested,
            ),
            if (recentProjects.isNotEmpty) const MenuFlyoutSeparator(),
            for (final recent in recentProjects)
              MenuFlyoutItem(
                key: ValueKey('open-project-recent-${recent.path}'),
                text: AcpText(
                  recent.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: recent.path == currentProjectPath,
                onPressed: () => onProjectSelected(recent.path),
              ),
          ],
        );
      },
    );
  }
}

String _displayName(String path) {
  final segments = path
      .split(RegExp(r'[\\/]'))
      .where((segment) => segment.isNotEmpty);
  return segments.isEmpty ? path : segments.last;
}
