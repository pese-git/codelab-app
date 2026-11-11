// Тесты `CodeLabFilePreview` (задачи 2.4 и 2.5a change
// `add-file-preview-and-tree`; spec workspace-file-browser «Просмотр файла
// только для чтения» — «Текстовый файл», «Двоичный файл», «Слишком большой
// файл», «Copy path копирует относительный путь»; «Предупреждение для файлов
// с секретами»; design.md D4, D5, D13).
//
// Красные тесты: виджета ещё нет (реализация — задачи 2.5 и 2.5b). Ожидаемый
// API: `CodeLabFilePreview(relativePath:, content:, maybeSecret:,
// highlightLine:, onCopyPath:)`; `content` — закрытая иерархия
// `CodeLabFilePreviewContent` (`.loading()`, `.text(text)`,
// `.binary(sizeLabel)`, `.tooLarge(sizeLabel)`, `.failed(message)`). Подписи
// размеров («24 KB», «3 MB») приходят готовыми от хоста: виджет только
// собирает фразы «Binary file (…)» и «File too large to preview (…)».

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPreview(
    WidgetTester tester, {
    String relativePath = 'lib/a.dart',
    required CodeLabFilePreviewContent content,
    bool maybeSecret = false,
    int? highlightLine,
    ValueChanged<String>? onCopyPath,
    double height = 400,
  }) => tester.pumpWidget(
    FluentApp(
      home: ScaffoldPage(
        padding: EdgeInsets.zero,
        content: SizedBox(
          width: 480,
          height: height,
          child: CodeLabFilePreview(
            relativePath: relativePath,
            content: content,
            maybeSecret: maybeSecret,
            highlightLine: highlightLine,
            onCopyPath: onCopyPath,
          ),
        ),
      ),
    ),
  );

  testWidgets('a text file shows its lines with numbers 1-3 and no input or '
      'write action', (tester) async {
    await pumpPreview(
      tester,
      content: const CodeLabFilePreviewContent.text('one\ntwo\nthree'),
    );

    expect(find.byKey(const ValueKey('file-preview')), findsOneWidget);
    for (final n in [1, 2, 3]) {
      expect(find.byKey(ValueKey('file-preview-line-$n')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('file-preview-line-4')), findsNothing);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('three'), findsOneWidget);
    // Только чтение: ни поля ввода, ни кнопки записи.
    expect(find.byType(TextBox), findsNothing);
    expect(find.byType(EditableText), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('CRLF line endings do not add empty lines', (tester) async {
    await pumpPreview(
      tester,
      content: const CodeLabFilePreviewContent.text('a\r\nb\r\n'),
    );

    expect(find.byKey(const ValueKey('file-preview-line-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('file-preview-line-3')), findsNothing);
    expect(find.text('a\r'), findsNothing);
  });

  testWidgets('a long file is virtualized and scrolls to the highlighted '
      'line, which is marked', (tester) async {
    final text = [for (var i = 1; i <= 2000; i++) 'line $i'].join('\n');
    await pumpPreview(
      tester,
      content: CodeLabFilePreviewContent.text(text),
      highlightLine: 1500,
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('file-preview-line-1500')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('file-preview-line-1')), findsNothing);
    expect(
      find.byKey(const ValueKey('file-preview-highlighted-line')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('file-preview-highlighted-line')),
        matching: find.text('line 1500'),
      ),
      findsOneWidget,
    );
    final built = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('file-preview-line-'),
    );
    expect(built.evaluate().length, lessThan(80));
  });

  testWidgets('without a line the preview starts at the top and marks '
      'nothing', (tester) async {
    final text = [for (var i = 1; i <= 2000; i++) 'line $i'].join('\n');
    await pumpPreview(tester, content: CodeLabFilePreviewContent.text(text));

    expect(find.byKey(const ValueKey('file-preview-line-1')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('file-preview-highlighted-line')),
      findsNothing,
    );
  });

  testWidgets('the loading state shows a progress ring and no lines', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      content: const CodeLabFilePreviewContent.loading(),
    );

    expect(find.byType(CodeLabProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('file-preview-line-1')), findsNothing);
  });

  testWidgets('a binary file shows the size and no content', (tester) async {
    await pumpPreview(
      tester,
      content: const CodeLabFilePreviewContent.binary('24 KB'),
    );

    expect(find.text('Binary file (24 KB)'), findsOneWidget);
    expect(find.byKey(const ValueKey('file-preview-line-1')), findsNothing);
  });

  testWidgets('a file over the limit shows the size and no content', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      content: const CodeLabFilePreviewContent.tooLarge('3 MB'),
    );

    expect(find.text('File too large to preview (3 MB)'), findsOneWidget);
    expect(find.byKey(const ValueKey('file-preview-line-1')), findsNothing);
  });

  testWidgets('a failed read shows the message given by the host', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      content: const CodeLabFilePreviewContent.failed(
        'The file was not found.',
      ),
    );

    expect(find.text('The file was not found.'), findsOneWidget);
    expect(find.byKey(const ValueKey('file-preview-line-1')), findsNothing);
  });

  testWidgets('maybeSecret shows the warning InfoBar and keeps the content '
      'visible', (tester) async {
    await pumpPreview(
      tester,
      relativePath: '.env',
      maybeSecret: true,
      content: const CodeLabFilePreviewContent.text('API_KEY=test-marker'),
    );

    final bar = find.byKey(const ValueKey('file-preview-secret-warning'));
    expect(bar, findsOneWidget);
    expect(
      find.descendant(of: bar, matching: find.byType(InfoBar)),
      findsOneWidget,
    );
    expect(find.text('This file may contain secrets.'), findsOneWidget);
    expect(find.text('API_KEY=test-marker'), findsOneWidget);
  });

  testWidgets('no warning for an ordinary file', (tester) async {
    await pumpPreview(
      tester,
      content: const CodeLabFilePreviewContent.text('x'),
    );

    expect(
      find.byKey(const ValueKey('file-preview-secret-warning')),
      findsNothing,
    );
  });

  testWidgets('the relative path is shown above the preview and Copy path '
      'passes exactly that path to the callback', (tester) async {
    final copied = <String>[];
    await pumpPreview(
      tester,
      relativePath: 'lib/src/a.dart',
      content: const CodeLabFilePreviewContent.text('class A {}'),
      onCopyPath: copied.add,
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('file-preview-path')),
        matching: find.text('lib/src/a.dart'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('file-preview-copy-path')));
    // Кнопка Fluent отпускает нажатие по таймеру 100 мс.
    await tester.pump(const Duration(milliseconds: 100));

    expect(copied, ['lib/src/a.dart']);
  });

  testWidgets('the path row and Copy path stay for binary and failed states', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      relativePath: 'img/logo.bin',
      content: const CodeLabFilePreviewContent.binary('1 KB'),
      onCopyPath: (_) {},
    );

    expect(find.byKey(const ValueKey('file-preview-path')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('file-preview-copy-path')),
      findsOneWidget,
    );
  });
}
