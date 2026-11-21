import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;

import '../../../../app/app_scope.dart';
import '../../../../app/navigation/navigation_cubit.dart';
import '../../../../app/navigation/settings_page.dart';
import '../../../../core/platform/os_drop_region.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../l10n/l10n.dart';
import '../../application/project_drop.dart';
import '../../application/shell_cubit.dart';

/// Текст отказа брошенной папки на языке [l10n] (spec agent-workbench-ui
/// «Открытие папки перетаскиванием»; design.md change
/// `add-empty-project-screen`, D4). Отказ хранится типом, а текст строит
/// presentation (`apps/codelab_desktop/AGENTS.md`, «Локализация»).
String projectDropRejectionText(
  AppLocalizations l10n,
  ProjectDropRejection rejection,
) => switch (rejection) {
  DropNotAFolder() => l10n.workbenchOpenProjectDropNotAFolder,
  DropMultiple() => l10n.workbenchOpenProjectDropMultiple,
  DropMissing(:final path) => l10n.workbenchOpenProjectDropMissing(path),
  DropUnsupported() => l10n.workbenchOpenProjectDropUnsupported,
};

/// Пояснение экрана по виду профиля окна (D6): обещание «агент не читает и не
/// пишет вне папки» — только у встроенного агента, внешнему его давать нельзя
/// (приоритет безопасности корневого `AGENTS.md` §2).
String openProjectDescriptionOf(
  AppLocalizations l10n,
  ProfileTransportKind kind,
) => switch (kind) {
  ProfileTransportKind.embedded => l10n.workbenchOpenProjectDescriptionEmbedded,
  ProfileTransportKind.stdio => l10n.workbenchOpenProjectDescriptionStdio,
  ProfileTransportKind.webSocket =>
    l10n.workbenchOpenProjectDescriptionWebSocket,
};

/// Строка транспорта карточки агента (D5): [detail] — команда stdio без
/// аргументов или адрес WebSocket без userinfo, пути и query
/// (`connectionDetail` состояния).
String agentCardDetailOf(
  AppLocalizations l10n,
  ProfileTransportKind kind,
  String detail,
) => switch (kind) {
  ProfileTransportKind.embedded => l10n.workbenchOpenProjectAgentEmbedded,
  ProfileTransportKind.stdio => l10n.workbenchOpenProjectAgentStdio(detail),
  ProfileTransportKind.webSocket => l10n.workbenchOpenProjectAgentWebSocket(
    detail,
  ),
};

/// Экран панели сессии, когда проект не выбран (кадр 11a).
///
/// Почему отдельный виджет app: организм кита `CodeLabOpenProjectScreen` без
/// логики, а тексты, профиль окна и приём перетаскивания принадлежат app
/// (design.md change `add-empty-project-screen`, D2, D3).
///
/// Для чего: собирает тексты по `context.l10n` из типизированных данных
/// `CodeLabShellState`, оборачивает организм адаптером [OsDropRegion] и
/// передаёт колбэки фасаду. Хранит только временное состояние просмотра
/// `dropActive` («элементы над экраном»); источником истины оно не является
/// (корневой `AGENTS.md` §8).
///
/// Как использовать: `main_pane.dart` строит его в ветке `project == null`.
class WorkbenchOpenProjectScreen extends StatefulWidget {
  const WorkbenchOpenProjectScreen({
    required this.state,
    required this.cubit,
    super.key,
  });

  final CodeLabShellState state;
  final CodeLabShellCubit cubit;

  @override
  State<WorkbenchOpenProjectScreen> createState() =>
      _WorkbenchOpenProjectScreenState();
}

class _WorkbenchOpenProjectScreenState
    extends State<WorkbenchOpenProjectScreen> {
  var _dropActive = false;

  void _setDropActive(bool value) {
    if (_dropActive != value && mounted) {
      setState(() => _dropActive = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    final cubit = widget.cubit;
    final kind = state.transportKind;
    final platform = defaultTargetPlatform;
    final rejection = state.dropRejection;
    return OsDropRegion(
      // Новое перетаскивание снимает прежний отказ (D4).
      onEntered: () {
        cubit.clearDropRejection();
        _setDropActive(true);
      },
      onExited: () => _setDropActive(false),
      onDropped: (paths) {
        _setDropActive(false);
        unawaited(cubit.openDroppedPaths(paths));
      },
      child: CodeLabOpenProjectScreen(
        title: l10n.workbenchOpenProjectTitle,
        description: openProjectDescriptionOf(l10n, kind),
        openLabel: l10n.workbenchOpenFolder,
        openShortcut: CodeLabShortcut.openFolder.combos.single.compactFor(
          platform,
        ),
        onOpen: () => unawaited(cubit.browseForProject()),
        dropLabel: l10n.workbenchOpenProjectDropLabel,
        dropHint: l10n.workbenchOpenProjectDropHint,
        dropActive: _dropActive,
        dropMessage: rejection == null
            ? null
            : projectDropRejectionText(l10n, rejection),
        agentName: state.profileLabel,
        agentDetail: agentCardDetailOf(l10n, kind, state.connectionDetail),
        agentNote: kind == ProfileTransportKind.webSocket
            ? l10n.workbenchOpenProjectAgentNoteConnects
            : l10n.workbenchOpenProjectAgentNoteStarts,
        settingsLinkLabel: l10n.workbenchOpenProjectSettingsLink,
        onOpenSettings: () => unawaited(
          codeLabDependenciesOf(context).navigationCubit.openSettings(
            page: SettingsPage.connection,
            source: SettingsOpenSource.startScreen,
          ),
        ),
        infoTitle: l10n.workbenchOpenProjectInfoTitle,
        infoBody: l10n.workbenchOpenProjectInfoBody(
          CodeLabShortcut.newSession.combos.single.compactFor(platform),
        ),
      ),
    );
  }
}
