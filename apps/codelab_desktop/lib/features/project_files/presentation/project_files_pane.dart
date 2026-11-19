import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart'
    show ProjectFilesFailureKind;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_scope.dart';
import '../../../l10n/l10n.dart';
import '../application/preview_view.dart';
import '../application/project_files_cubit.dart';
import '../application/project_tree_rows.dart' show localizedProjectTreeRows;
import '../application/project_tree_state.dart';

/// Панель Files дока: дерево сверху, просмотр снизу (артборд `Files`;
/// отступления — design.md change `add-file-preview-and-tree`, D13).
///
/// Почему: корень панели следует за сессией в фокусе, а раскрытые папки и
/// выбор должны пережить переключение вкладок дока (док монтирует только
/// активную вкладку), поэтому [ProjectFilesCubit] принадлежит окну, а не
/// панели (D6).
///
/// Для чего: только отображение. Берёт Cubit окна из
/// `CodeLabDependencies.projectFilesCubit` (виджет не создаёт адаптеры,
/// `AGENTS.md` §6) и НЕ закрывает его.
///
/// Как использовать: показывается доком только для `ToolPane.files`, когда
/// `CodeLabShellState.projectFilesAvailable`; без привязки `ProjectFiles`
/// панели нет вообще.
class ProjectFilesPane extends StatelessWidget {
  const ProjectFilesPane({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = codeLabDependenciesOf(context).projectFilesCubit?.call();
    if (cubit == null) {
      return const SizedBox.shrink();
    }
    return BlocProvider.value(value: cubit, child: const ProjectFilesView());
  }
}

/// Тело панели Files над [ProjectFilesCubit] из `BlocProvider` выше по дереву.
class ProjectFilesView extends StatelessWidget {
  const ProjectFilesView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<ProjectFilesCubit, ProjectTreeState>(
      builder: (context, state) => switch (state.status) {
        ProjectTreeStatus.noFolder => _Message(l10n.projectFilesNoFolder),
        ProjectTreeStatus.unavailable => _Message(
          state.failure == ProjectFilesFailureKind.notFound
              ? l10n.projectFilesFolderMissing
              : l10n.projectFilesFolderUnreadable,
        ),
        ProjectTreeStatus.loading => const Center(
          child: CodeLabProgressIndicator(),
        ),
        ProjectTreeStatus.ready => _ReadyView(state: state),
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Align(
      alignment: Alignment.topLeft,
      child: CodeLabText(
        text,
        key: const ValueKey('project-files-message'),
        color: FluentTheme.of(context).resources.textFillColorSecondary,
      ),
    ),
  );
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({required this.state});

  final ProjectTreeState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProjectFilesCubit>();
    final theme = FluentTheme.of(context);
    final selected = state.selected;
    final l10n = context.l10n;
    final content = previewContentOf(state.preview, l10n);
    final shown = state.preview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.rootOutsideProject && state.root != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: KeyedSubtree(
              key: const ValueKey('project-files-root-outside'),
              // Корень объявил агент, он вне папки проекта: путь виден
              // только здесь, в логи выше debug он не попадает (Q18, D5).
              child: CodeLabText(
                l10n.projectFilesRootOutside('${state.root}'),
                role: CodeLabTextRole.caption,
                color: Colors.warningPrimaryColor,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: CodeLabText(
                  l10n.projectFilesGitHidden,
                  role: CodeLabTextRole.caption,
                  color: theme.resources.textFillColorSecondary,
                ),
              ),
              CodeLabButton(
                key: const ValueKey('project-files-refresh'),
                label: l10n.projectFilesRefresh,
                icon: FluentIcons.refresh,
                emphasis: CodeLabButtonEmphasis.subtle,
                onPressed: () => unawaited(cubit.refresh()),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 3,
          child: CodeLabFileTree(
            rows: localizedProjectTreeRows(state.rows, l10n),
            selectedPath: selected,
            onToggleDirectory: (row) =>
                unawaited(cubit.toggleDirectory(row.relativePath)),
            onOpenFile: (row) => unawaited(cubit.selectFile(row.relativePath)),
          ),
        ),
        Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
        Expanded(
          flex: 2,
          child: selected == null || content == null
              ? _Message(l10n.projectFilesSelectFile)
              : CodeLabFilePreview(
                  relativePath: selected,
                  content: content,
                  maybeSecret: shown is PreviewShown && shown.maybeSecret,
                  highlightLine: shown is PreviewShown ? shown.line : null,
                  // Копируется только относительный путь: ни содержимое, ни
                  // абсолютный путь в буфер обмена не попадают (Q14, D13).
                  onCopyPath: (path) =>
                      unawaited(Clipboard.setData(ClipboardData(text: path))),
                ),
        ),
      ],
    );
  }
}
