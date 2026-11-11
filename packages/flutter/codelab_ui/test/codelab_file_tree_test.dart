// Тесты `CodeLabFileTree` (задача 2.2 change `add-file-preview-and-tree`;
// spec workspace-file-browser «Ленивое перечисление папок» — «Большая папка»,
// «`.git` скрыт, скрытые файлы видны»; «Граница рабочей папки браузера» —
// «Ссылка наружу видна, но не открывается»; design.md D6, D13).
//
// Красные тесты 2.2: виджета ещё нет (реализация — задача 2.3). Ожидаемый API:
// `CodeLabFileTreeRowData(relativePath:, name:, kind:, depth:, expanded:,
// loading:)` с видами `CodeLabFileTreeRowKind` (`directory`, `file`,
// `outsideLink`, `other`, `more`, `error`); `CodeLabFileTree(rows:,
// selectedPath:, onToggleDirectory:, onOpenFile:, autofocus:)`. Знания о
// файловой системе у виджета нет: строки уже плоский список, а решения
// «раскрыть» и «открыть» — колбэки хоста.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

CodeLabFileTreeRowData _dir(
  String path, {
  int depth = 0,
  bool expanded = false,
  bool loading = false,
}) => CodeLabFileTreeRowData(
  relativePath: path,
  name: path.split('/').last,
  kind: CodeLabFileTreeRowKind.directory,
  depth: depth,
  expanded: expanded,
  loading: loading,
);

CodeLabFileTreeRowData _file(String path, {int depth = 0}) =>
    CodeLabFileTreeRowData(
      relativePath: path,
      name: path.split('/').last,
      kind: CodeLabFileTreeRowKind.file,
      depth: depth,
    );

ValueKey<String> _rowKey(String path) => ValueKey('file-tree-row-$path');

void main() {
  Future<void> pumpTree(
    WidgetTester tester,
    List<CodeLabFileTreeRowData> rows, {
    String? selectedPath,
    ValueChanged<CodeLabFileTreeRowData>? onToggle,
    ValueChanged<CodeLabFileTreeRowData>? onOpen,
    bool autofocus = false,
    double height = 600,
  }) => tester.pumpWidget(
    FluentApp(
      home: ScaffoldPage(
        padding: EdgeInsets.zero,
        content: SizedBox(
          width: 320,
          height: height,
          child: CodeLabFileTree(
            rows: rows,
            selectedPath: selectedPath,
            onToggleDirectory: onToggle,
            onOpenFile: onOpen,
            autofocus: autofocus,
          ),
        ),
      ),
    ),
  );

  testWidgets('draws one keyed row per entry with a deeper indent for nested '
      'rows and an icon for a folder and a file', (tester) async {
    await pumpTree(tester, [
      _dir('lib', expanded: true),
      _dir('lib/src', depth: 1),
      _file('lib/src/a.dart', depth: 2),
      _file('README.md'),
    ]);

    for (final path in const [
      'lib',
      'lib/src',
      'lib/src/a.dart',
      'README.md',
    ]) {
      expect(find.byKey(_rowKey(path)), findsOneWidget, reason: path);
    }
    final shallow = tester.getTopLeft(find.text('lib')).dx;
    final middle = tester.getTopLeft(find.text('src')).dx;
    final deep = tester.getTopLeft(find.text('a.dart')).dx;
    expect(middle, greaterThan(shallow));
    expect(deep, greaterThan(middle));
    expect(
      find.descendant(
        of: find.byKey(_rowKey('lib')),
        matching: find.byIcon(FluentIcons.open_folder_horizontal),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(_rowKey('lib/src')),
        matching: find.byIcon(FluentIcons.folder),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(_rowKey('README.md')),
        matching: find.byIcon(FluentIcons.page),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a click on a folder asks to toggle it and a click on a file '
      'asks to open it', (tester) async {
    final toggled = <String>[];
    final opened = <String>[];
    await pumpTree(
      tester,
      [_dir('lib'), _file('a.txt')],
      onToggle: (row) => toggled.add(row.relativePath),
      onOpen: (row) => opened.add(row.relativePath),
    );

    await tester.tap(find.byKey(_rowKey('lib')));
    await tester.pump();
    await tester.tap(find.byKey(_rowKey('a.txt')));
    await tester.pump();

    expect(toggled, ['lib']);
    expect(opened, ['a.txt']);
  });

  testWidgets('10 000 rows build only the visible ones and a reserve', (
    tester,
  ) async {
    await pumpTree(tester, [
      for (var i = 0; i < 10000; i++) _file('f${i.toString().padLeft(5, '0')}'),
    ]);

    final built = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('file-tree-row-'),
    );
    // Окно 600 px при строке 24 px — 25 строк; запас `ListView` невелик.
    expect(built.evaluate().length, lessThan(60));
    expect(built.evaluate().length, greaterThan(20));
    expect(find.byKey(_rowKey('f00000')), findsOneWidget);
    expect(find.byKey(_rowKey('f09999')), findsNothing);
  });

  testWidgets('arrow keys move through rows, Enter opens a file and toggles '
      'a folder, Right expands and Left collapses', (tester) async {
    final toggled = <String>[];
    final opened = <String>[];
    await pumpTree(
      tester,
      [_dir('lib'), _dir('open', expanded: true), _file('a.txt')],
      autofocus: true,
      onToggle: (row) => toggled.add(row.relativePath),
      onOpen: (row) => opened.add(row.relativePath),
    );
    await tester.pump();

    // Фокус начинается с первой строки.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(toggled, ['lib']);

    // → раскрывает свёрнутую папку, ← сворачивает раскрытую; на уже
    // раскрытой → и на свёрнутой ← ничего не просят.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(toggled, ['lib', 'lib']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(toggled, ['lib', 'lib']);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(toggled, ['lib', 'lib', 'open']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(toggled, ['lib', 'lib', 'open']);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, ['a.txt']);

    // Выше первой и ниже последней строки фокус не уходит.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, ['a.txt', 'a.txt']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(toggled.last, 'lib');
  });

  testWidgets('a link that leaves the root shows an arrow and gives no '
      'callbacks for click, Enter or Right', (tester) async {
    final calls = <String>[];
    await pumpTree(
      tester,
      [
        const CodeLabFileTreeRowData(
          relativePath: 'secrets',
          name: 'secrets',
          kind: CodeLabFileTreeRowKind.outsideLink,
        ),
      ],
      autofocus: true,
      onToggle: (row) => calls.add('toggle ${row.relativePath}'),
      onOpen: (row) => calls.add('open ${row.relativePath}'),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('file-tree-outside-secrets')),
      findsOneWidget,
    );
    expect(find.text('↗'), findsOneWidget);

    await tester.tap(find.byKey(_rowKey('secrets')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(calls, isEmpty);
  });

  testWidgets('a broken link or a special file is shown but never opened', (
    tester,
  ) async {
    final calls = <String>[];
    await pumpTree(
      tester,
      [
        const CodeLabFileTreeRowData(
          relativePath: 'pipe',
          name: 'pipe',
          kind: CodeLabFileTreeRowKind.other,
        ),
      ],
      autofocus: true,
      onToggle: (row) => calls.add('toggle'),
      onOpen: (row) => calls.add('open'),
    );
    await tester.pump();

    await tester.tap(find.byKey(_rowKey('pipe')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(find.text('pipe'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('the “… N more” row and a folder error row are plain text rows '
      'without callbacks', (tester) async {
    final calls = <String>[];
    await pumpTree(
      tester,
      [
        _dir('big', expanded: true),
        const CodeLabFileTreeRowData(
          relativePath: 'big/#more',
          name: '… 5000 more',
          kind: CodeLabFileTreeRowKind.more,
          depth: 1,
        ),
        _dir('locked', expanded: true),
        const CodeLabFileTreeRowData(
          relativePath: 'locked/#error',
          name: 'Cannot read this folder.',
          kind: CodeLabFileTreeRowKind.error,
          depth: 1,
        ),
      ],
      onToggle: (row) => calls.add('toggle'),
      onOpen: (row) => calls.add('open'),
    );

    expect(find.text('… 5000 more'), findsOneWidget);
    expect(find.text('Cannot read this folder.'), findsOneWidget);
    await tester.tap(find.byKey(_rowKey('big/#more')));
    await tester.tap(find.byKey(_rowKey('locked/#error')));
    await tester.pump();

    expect(calls, isEmpty);
  });

  testWidgets('the selected row is marked and a loading folder shows a '
      'progress ring', (tester) async {
    await pumpTree(tester, [
      _dir('lib', loading: true),
      _file('a.txt'),
    ], selectedPath: 'a.txt');

    expect(
      find.byKey(const ValueKey('file-tree-selected-a.txt')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('file-tree-selected-lib')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(_rowKey('lib')),
        matching: find.byType(CodeLabProgressIndicator),
      ),
      findsOneWidget,
    );
  });
}
