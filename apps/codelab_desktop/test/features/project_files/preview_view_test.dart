// Перевод состояния просмотра в то, что рисует `CodeLabFilePreview` (задачи
// 2.7 и 2.10 change `add-file-preview-and-tree`; spec workspace-file-browser
// «Просмотр файла только для чтения» — «Двоичный файл», «Слишком большой
// файл»; design.md D4). Подписи размеров и тексты ошибок форматирует app, а
// не виджет `codelab_ui`.

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/project_files/application/preview_view.dart';
import 'package:codelab_desktop/features/project_files/application/project_tree_state.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

({String kind, String value}) _probe(FilePreviewState state) =>
    switch (previewContentOf(state)!) {
      CodeLabFilePreviewLoading() => (kind: 'loading', value: ''),
      CodeLabFilePreviewText(:final text) => (kind: 'text', value: text),
      CodeLabFilePreviewBinary(:final sizeLabel) => (
        kind: 'binary',
        value: sizeLabel,
      ),
      CodeLabFilePreviewTooLarge(:final sizeLabel) => (
        kind: 'tooLarge',
        value: sizeLabel,
      ),
      CodeLabFilePreviewFailed(:final message) => (
        kind: 'failed',
        value: message,
      ),
    };

void main() {
  test('no file means no preview', () {
    expect(previewContentOf(const PreviewNone()), isNull);
  });

  test('a file in flight is loading', () {
    expect(_probe(const PreviewLoading('a')).kind, 'loading');
  });

  test('a text file passes its text through', () {
    final probe = _probe(
      const PreviewShown('a', TextPreview('hi'), maybeSecret: false),
    );

    expect(probe.kind, 'text');
    expect(probe.value, 'hi');
  });

  test('a binary file is labelled in KB, rounding up and never below 1', () {
    expect(
      _probe(
        const PreviewShown('a', BinaryPreview(24 * 1024), maybeSecret: false),
      ).value,
      '24 KB',
    );
    expect(
      _probe(
        const PreviewShown('a', BinaryPreview(1500), maybeSecret: false),
      ).value,
      '2 KB',
    );
    expect(
      _probe(
        const PreviewShown('a', BinaryPreview(0), maybeSecret: false),
      ).value,
      '1 KB',
    );
  });

  test('a too large file is labelled in MB', () {
    final probe = _probe(
      const PreviewShown('a', TooLargePreview(3 << 20), maybeSecret: false),
    );

    expect(probe.kind, 'tooLarge');
    expect(probe.value, '3 MB');
  });

  test('every failure kind has its own message without the path', () {
    final messages = {
      for (final kind in ProjectFilesFailureKind.values)
        kind: _probe(PreviewFailed('secret/dir/a.txt', kind)).value,
    };

    expect(
      messages.values.toSet(),
      hasLength(ProjectFilesFailureKind.values.length),
    );
    for (final message in messages.values) {
      expect(message, isNot(contains('secret/dir')));
    }
  });
}
