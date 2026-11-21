import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;

import '../../../l10n/l10n.dart';
import '../../workbench/application/shell_cubit.dart';
import '../../workbench/application/ui_mappers.dart' show projectNameOf;
import '../../workbench/presentation/widgets/open_project_texts.dart';

/// Сколько недавних проектов показывает шаг (решение пользователя 2026-11-22,
/// Q2; design.md change `add-onboarding-project-step`, D3): шаг обязан
/// помещаться в окно 800×600 без потери кнопок.
const kOnboardingRecentProjectsLimit = 5;

/// Восстановленный проект прошлого запуска: выбранный проект не пуст
/// (design.md change `add-onboarding-project-step`, D3).
///
/// Почему отдельная функция: и тело шага, и кнопки под ним (`Continue in …`
/// против `Skip for now`) решают по одному и тому же признаку, и расходиться
/// им нельзя. Читает только готовое состояние рабочего места. Правило то же,
/// что у `SettingsCubit.projectDirectory` (trim, пустая строка — не проект);
/// порт `OnboardingProjectPort.selectedProject` применяет его же, поэтому
/// экран и Cubit согласованы.
String? restoredProjectOf(CodeLabShellState shell) {
  final path = shell.selectedProjectPath?.trim();
  return path == null || path.isEmpty ? null : path;
}

/// Тело шага «Open a project» onboarding (design.md change
/// `add-onboarding-project-step`, D3, D4, D7).
///
/// Почему: шаг переиспользует блоки экрана 11a (пояснение, «Open folder…»,
/// зона, карточка агента) через организм [CodeLabOpenProjectBody], а строка
/// `Last project` и блок `Recent projects` — раскладка шага, второго
/// употребления у них нет, поэтому они живут здесь, а не в ките.
///
/// Для чего: только отображение. Решения «что считается принятой папкой» и
/// «чем кончается onboarding» принимает `OnboardingCubit` через порт; здесь
/// колбэки и готовое состояние рабочего места ([shell]) и признак занятости
/// шага ([busy]): пока выбор идёт или флаг пишется, «Open folder…» и записи
/// недавних неактивны (D6).
/// Без ссылки «в настройки» и без InfoBar про ⌘N: на onboarding настройки
/// недоступны, а ⌘N не привязан.
///
/// Как использовать: `OnboardingStepBody` строит его для шага `project`;
/// [dropActive] ведёт экран (регион перетаскивания над ним).
class OnboardingProjectBody extends StatelessWidget {
  const OnboardingProjectBody({
    required this.shell,
    required this.busy,
    required this.dropActive,
    required this.onOpenFolder,
    required this.onOpenRecent,
    super.key,
  });

  final CodeLabShellState shell;

  /// Идёт выбор (`ProjectStepPhase.choosing`) или запись флага
  /// (`finishing`): действия шага не принимаются.
  final bool busy;
  final bool dropActive;
  final VoidCallback onOpenFolder;
  final ValueChanged<String> onOpenRecent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final kind = shell.transportKind;
    final rejection = shell.dropRejection;
    final restored = restoredProjectOf(shell);
    // Восстановленный проект уже показан строкой `Last project`: среди недавних
    // его нет.
    final recents = [
      for (final recent in shell.recentProjects)
        if (recent.path != restored) recent.path,
    ].take(kOnboardingRecentProjectsLimit).toList(growable: false);
    return Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        // Ширина колонки кадра 11a (`.col{max-width:620px}`).
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CodeLabOpenProjectBody(
              description: openProjectDescriptionOf(l10n, kind),
              beforeOpen: restored == null
                  ? null
                  : _LastProject(path: restored),
              openLabel: l10n.workbenchOpenFolder,
              openShortcut: CodeLabShortcut.openFolder.combos.single.compactFor(
                defaultTargetPlatform,
              ),
              onOpen: busy ? null : onOpenFolder,
              dropLabel: l10n.workbenchOpenProjectDropLabel,
              dropHint: l10n.workbenchOpenProjectDropHint,
              dropActive: dropActive,
              dropMessage: rejection == null
                  ? null
                  : projectDropRejectionText(l10n, rejection),
              agentName: shell.profileLabel,
              agentDetail: agentCardDetailOf(
                l10n,
                kind,
                shell.connectionDetail,
              ),
              agentNote: kind == ProfileTransportKind.webSocket
                  ? l10n.workbenchOpenProjectAgentNoteConnects
                  : l10n.workbenchOpenProjectAgentNoteStarts,
            ),
            if (recents.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Recents(
                paths: recents,
                // Пока выбор выполняется или флаг пишется, записи не действуют
                // (D6).
                onOpen: busy ? null : onOpenRecent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Строка `Last project: <имя>` и полный путь под ней (Q5): имя и путь
/// показываются как есть, без перевода.
class _LastProject extends StatelessWidget {
  const _LastProject({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('onboarding-project-last'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CodeLabText(
        context.l10n.onboardingProjectLast(projectNameOf(path)),
        role: CodeLabTextRole.strong,
      ),
      CodeLabText(
        path,
        role: CodeLabTextRole.caption,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );
}

/// Блок `Recent projects`: до пяти записей, имя папки и путь. Нажатие — выбор
/// проекта как в сайдбаре; существование папки не проверяется (Q2).
class _Recents extends StatelessWidget {
  const _Recents({required this.paths, required this.onOpen});

  final List<String> paths;

  /// `null` — выбор уже идёт, записи неактивны.
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final action = onOpen;
    return Column(
      key: const ValueKey('onboarding-project-recents'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CodeLabText(
          context.l10n.onboardingProjectRecents,
          role: CodeLabTextRole.strong,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < paths.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          Button(
            key: ValueKey('onboarding-project-recent-$i'),
            onPressed: action == null ? null : () => action(paths[i]),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CodeLabText(
                    projectNameOf(paths[i]),
                    role: CodeLabTextRole.strong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  CodeLabText(
                    paths[i],
                    role: CodeLabTextRole.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
