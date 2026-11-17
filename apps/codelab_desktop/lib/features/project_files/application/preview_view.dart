import 'package:codelab_client_core/codelab_client_core.dart'
    show BinaryPreview, ProjectFilesFailureKind, TextPreview, TooLargePreview;
import 'package:codelab_ui/codelab_ui.dart' show CodeLabFilePreviewContent;

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
/// что сообщается пользователю.
CodeLabFilePreviewContent? previewContentOf(FilePreviewState state) =>
    switch (state) {
      PreviewNone() => null,
      PreviewLoading() => const CodeLabFilePreviewContent.loading(),
      PreviewShown(:final preview) => switch (preview) {
        TextPreview(:final text) => CodeLabFilePreviewContent.text(text),
        BinaryPreview(:final size) => CodeLabFilePreviewContent.binary(
          _kilobytes(size),
        ),
        TooLargePreview(:final size) => CodeLabFilePreviewContent.tooLarge(
          _megabytes(size),
        ),
      },
      PreviewFailed(:final kind) => CodeLabFilePreviewContent.failed(
        _failureText(kind),
      ),
    };

/// Размер в КБ с округлением вверх, не меньше 1 («Binary file (24 KB)»).
String _kilobytes(int bytes) {
  final kb = (bytes / 1024).ceil();
  return '${kb < 1 ? 1 : kb} KB';
}

/// Размер в МБ с округлением к ближайшему («File too large to preview
/// (3 MB)»).
String _megabytes(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

String _failureText(ProjectFilesFailureKind kind) => switch (kind) {
  ProjectFilesFailureKind.outsideRoot =>
    'This file is outside the project folder.',
  ProjectFilesFailureKind.notFound => 'The file was not found.',
  ProjectFilesFailureKind.unreadable => 'The file cannot be read.',
  ProjectFilesFailureKind.invalidPath => 'The file path is not valid.',
};
