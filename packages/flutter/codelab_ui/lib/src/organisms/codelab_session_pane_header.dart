import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Шапка панели сессии: название, проект, режим.
///
/// Почему: макет (артборд Main, A13 шаг 0) даёт каждой панели сессии свою
/// шапку; прежняя `CurrentSessionPanel` показывала полный `cwd` второй строкой
/// (change `redesign-workbench-shell`, D7).
///
/// Для чего: организм без логики; имя папки проекта и режим готовит хост.
///
/// Как использовать: [projectName] — имя папки `cwd`, [projectPath] — полный
/// путь для подсказки. [mode] — значение опции режима агента; без опции чип
/// не показывается. [actions] — слот справа (Rename, Fork, Split — в
/// следующих change).
class CodeLabSessionPaneHeader extends StatelessWidget {
  const CodeLabSessionPaneHeader({
    required this.title,
    this.projectName,
    this.projectPath,
    this.mode,
    this.actions = const [],
    super.key,
  });

  static const titleKey = ValueKey('session-pane-title');
  static const projectChipKey = ValueKey('session-pane-project');
  static const modeChipKey = ValueKey('session-pane-mode');

  final String title;
  final String? projectName;
  final String? projectPath;
  final String? mode;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final projectName = this.projectName;
    final projectPath = this.projectPath;
    final mode = this.mode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          Flexible(
            child: CodeLabText(
              title,
              key: titleKey,
              role: CodeLabTextRole.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (projectName != null) ...[
            const SizedBox(width: 10),
            _withTooltip(
              projectPath,
              CodeLabBadge(
                key: projectChipKey,
                label: projectName,
                tone: CodeLabTone.neutral,
              ),
            ),
          ],
          if (mode != null) ...[
            const SizedBox(width: 6),
            CodeLabBadge(
              key: modeChipKey,
              label: mode,
              tone: CodeLabTone.accent,
            ),
          ],
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }

  Widget _withTooltip(String? message, Widget child) =>
      message == null ? child : Tooltip(message: message, child: child);
}
