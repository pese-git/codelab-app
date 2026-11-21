import '../../../../l10n/l10n.dart';
import '../../application/project_drop.dart';
import '../../application/shell_cubit.dart';

// Тексты экрана «проект не выбран» (кадр 11a) и шага «Open a project»
// onboarding, вынесенные из `open_project_screen.dart` без изменения
// содержания (design.md change `add-onboarding-project-step`, D5): шаг
// переиспользует их, не импортируя экран рабочего места с его навигацией.

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
