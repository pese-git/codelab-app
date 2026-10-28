import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Состояние хода для чипа в шапке панели сессии (требование «Session pane
/// header», change `redesign-transcript-rows`).
enum CodeLabTurnState { running, awaitingApproval, cancelling }

/// Шапка панели сессии: название, проект, режим, состояние хода.
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
/// следующих change). [turnState] — чип занятой сессии; `null` — сессия
/// свободна, чипа нет.
class CodeLabSessionPaneHeader extends StatelessWidget {
  const CodeLabSessionPaneHeader({
    required this.title,
    this.projectName,
    this.projectPath,
    this.mode,
    this.turnState,
    this.actions = const [],
    super.key,
  });

  static const titleKey = ValueKey('session-pane-title');
  static const projectChipKey = ValueKey('session-pane-project');
  static const modeChipKey = ValueKey('session-pane-mode');
  static const turnChipKey = ValueKey('session-pane-turn');

  final String title;
  final String? projectName;
  final String? projectPath;
  final String? mode;
  final CodeLabTurnState? turnState;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final projectName = this.projectName;
    final projectPath = this.projectPath;
    final mode = this.mode;
    final turnState = this.turnState;
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
          if (turnState != null) ...[
            const SizedBox(width: 6),
            _TurnChip(key: turnChipKey, state: turnState),
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

/// Чип занятой сессии: индикатор и подпись по состоянию хода.
class _TurnChip extends StatelessWidget {
  const _TurnChip({required this.state, super.key});

  final CodeLabTurnState state;

  @override
  Widget build(BuildContext context) {
    final label = switch (state) {
      CodeLabTurnState.running => 'Turn running',
      CodeLabTurnState.awaitingApproval => 'Waiting for approval',
      CodeLabTurnState.cancelling => 'Cancelling…',
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state != CodeLabTurnState.awaitingApproval) ...[
          const SizedBox.square(
            dimension: 12,
            child: ProgressRing(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
        ],
        CodeLabBadge(
          label: label,
          tone: state == CodeLabTurnState.awaitingApproval
              ? CodeLabTone.accent
              : CodeLabTone.neutral,
        ),
      ],
    );
  }
}
