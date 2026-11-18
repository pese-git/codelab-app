import 'package:codelab_client_core/codelab_client_core.dart'
    show BinaryPreview, ProjectFilesFailureKind, TextPreview, TooLargePreview;
import 'package:codelab_ui/codelab_ui.dart' show CodeLabFilePreviewContent;

import '../../../l10n/app_localizations.dart';
import 'project_tree_state.dart';

/// Переводит состояние просмотра в содержимое `CodeLabFilePreview`.
///
/// Почему в app: подписи размеров («24 KB», «3 MB») и тексты ошибок — это
/// форматирование данных клиента, а виджет `codelab_ui` их не форматирует
/// (`AGENTS.md` пакета, §2; spec workspace-file-browser «Просмотр файла
/// только для чтения»).
///
/// Как использовать: `null` — файл не выбран, просмотр не показывается.
/// Тексты ошибок не содержат пути и содержимого (D5): вид сбоя — единственное,
/// что сообщается пользователю. Текст берётся из каталога [l10n]
/// (`add-desktop-localization`, D5 п. 4): состояние хранит вид сбоя, а не
/// строку, поэтому смена языка пересобирает текст вместе с виджетом.
CodeLabFilePreviewContent? previewContentOf(
  FilePreviewState state,
  AppLocalizations l10n,
) => switch (state) {
  PreviewNone() => null,
  PreviewLoading() => const CodeLabFilePreviewContent.loading(),
  PreviewShown(:final preview) => switch (preview) {
    TextPreview(:final text) => CodeLabFilePreviewContent.text(text),
    BinaryPreview(:final size) => CodeLabFilePreviewContent.binary(
      _kilobytes(size, l10n),
    ),
    TooLargePreview(:final size) => CodeLabFilePreviewContent.tooLarge(
      _megabytes(size, l10n),
    ),
  },
  PreviewFailed(:final kind) => CodeLabFilePreviewContent.failed(
    _failureText(kind, l10n),
  ),
};

/// Размер в КБ с округлением вверх, не меньше 1 («Binary file (24 KB)»).
String _kilobytes(int bytes, AppLocalizations l10n) {
  final kb = (bytes / 1024).ceil();
  return l10n.projectFilesSizeKilobytes(kb < 1 ? 1 : kb);
}

/// Размер в МБ с округлением к ближайшему («File too large to preview
/// (3 MB)»).
String _megabytes(int bytes, AppLocalizations l10n) =>
    l10n.projectFilesSizeMegabytes((bytes / (1024 * 1024)).round());

String _failureText(
  ProjectFilesFailureKind kind,
  AppLocalizations l10n,
) => switch (kind) {
  ProjectFilesFailureKind.outsideRoot => l10n.projectFilesFailureOutsideRoot,
  ProjectFilesFailureKind.notFound => l10n.projectFilesFailureNotFound,
  ProjectFilesFailureKind.unreadable => l10n.projectFilesFailureUnreadable,
  ProjectFilesFailureKind.invalidPath => l10n.projectFilesFailureInvalidPath,
};
