// Сторож 2 для записей кита: каждая запись каталога проверена нажатием
// (задача 1.2 change `add-app-keyboard-page`; design.md D3, Risks; spec
// app-settings «Сочетания app и страница «Keyboard» не расходятся», сценарий
// «Каждая строка проверена нажатием»).
//
// `_checkOf` — `switch` без `default` по `CodeLabShortcut`: новая запись без
// сценария не компилируется. Записи app (`leave-settings`, Esc диалогов в
// составе `close-overlay`) проверяет `keyboard_bindings_test.dart` app.
// Сценарий нажимает каждую комбинацию записи; у комбинации с основным
// модификатором — в варианте `control` и в варианте `meta`. Тест на запись
// создаётся всегда, а пустой каталог он считает ошибкой, поэтому красный до
// задачи 1.4, пока у записей нет комбинаций.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Нажатие комбинации; [useMeta] выбирает ⌘ вместо Ctrl для основного
/// модификатора, [key] подменяет клавишу (numpad Enter из `alsoKeys`).
typedef _Press =
    Future<void> Function(CodeLabKeyCombo combo, {LogicalKeyboardKey? key});

/// Сценарий записи: строит виджет, нажимает комбинации через `press` и
/// проверяет действие.
typedef _Scenario =
    Future<void> Function(
      WidgetTester tester,
      CodeLabShortcut shortcut,
      _Press press,
    );

/// Как проверена запись: нажатием в ките или в app.
sealed class _Check {
  const _Check();
}

final class _InKit extends _Check {
  const _InKit(this.scenario);
  final _Scenario scenario;
}

/// Запись принадлежит app: проверяется в `keyboard_bindings_test.dart` app
/// (задача 1.5).
final class _InApp extends _Check {
  const _InApp();
}

_Check _checkOf(CodeLabShortcut shortcut) => switch (shortcut) {
  CodeLabShortcut.commandPalette => const _InKit(_workbenchShortcut),
  CodeLabShortcut.newSession => const _InKit(_workbenchShortcut),
  CodeLabShortcut.openSettings => const _InKit(_workbenchShortcut),
  CodeLabShortcut.closeOverlay => const _InKit(_overlayPanelEscape),
  CodeLabShortcut.leaveSettings => const _InApp(),
  CodeLabShortcut.toggleSidebar => const _InKit(_workbenchShortcut),
  CodeLabShortcut.toggleFiles => const _InKit(_workbenchShortcut),
  CodeLabShortcut.fileTreeMove => const _InKit(_fileTreeMove),
  CodeLabShortcut.fileTreeFold => const _InKit(_fileTreeFold),
  CodeLabShortcut.fileTreeOpen => const _InKit(_fileTreeOpen),
  CodeLabShortcut.cancelTurn => const _InKit(_cancelTurn),
  CodeLabShortcut.send => const _InKit(_composerSend),
  CodeLabShortcut.commandMenuMove => const _InKit(_commandMenuMove),
  CodeLabShortcut.commandMenuRun => const _InKit(_commandMenuRun),
  CodeLabShortcut.commandMenuClose => const _InKit(_commandMenuClose),
  CodeLabShortcut.allowOnce => const _InKit(_approval),
  CodeLabShortcut.allowAlways => const _InKit(_approval),
  CodeLabShortcut.rejectOnce => const _InKit(_approval),
  CodeLabShortcut.rejectAlways => const _InKit(_approval),
};

void main() {
  test('в каталоге 19 записей, а запись без сценария не компилируется', () {
    expect(CodeLabShortcut.values, hasLength(19));
    for (final shortcut in CodeLabShortcut.values) {
      expect(_checkOf(shortcut), isA<_Check>(), reason: shortcut.name);
    }
  });

  for (final shortcut in CodeLabShortcut.values) {
    final check = _checkOf(shortcut);
    if (check is! _InKit) {
      continue;
    }
    testWidgets('${shortcut.name}: нажатие выполняет действие', (tester) async {
      expect(
        shortcut.combos,
        isNotEmpty,
        reason: 'у записи ${shortcut.name} нет комбинаций',
      );
      // Каждая комбинация с основным модификатором — и Ctrl, и ⌘.
      for (final useMeta in const [false, true]) {
        if (useMeta && !shortcut.combos.any((c) => c.primary)) {
          continue;
        }
        Future<void> press(
          CodeLabKeyCombo combo, {
          LogicalKeyboardKey? key,
        }) async {
          final modifiers = <LogicalKeyboardKey>[
            if (combo.primary)
              useMeta
                  ? LogicalKeyboardKey.metaLeft
                  : LogicalKeyboardKey.controlLeft,
            if (combo.alt) LogicalKeyboardKey.altLeft,
            if (combo.shift) LogicalKeyboardKey.shiftLeft,
          ];
          for (final modifier in modifiers) {
            await tester.sendKeyDownEvent(modifier);
          }
          await tester.sendKeyEvent(key ?? combo.key);
          for (final modifier in modifiers.reversed) {
            await tester.sendKeyUpEvent(modifier);
          }
          await tester.pump(const Duration(milliseconds: 100));
        }

        // Чистое дерево: состояние виджетов прошлого прохода не переносится.
        await tester.pumpWidget(const SizedBox.shrink());
        await check.scenario(tester, shortcut, press);
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Оболочка CodeLabWorkbenchShortcuts: палитра, новая сессия, настройки,
// сайдбар, Files.

Future<void> _workbenchShortcut(
  WidgetTester tester,
  CodeLabShortcut shortcut,
  _Press press,
) async {
  var calls = 0;
  void hit() => calls++;
  await tester.pumpWidget(
    FluentApp(
      home: CodeLabWorkbenchShortcuts(
        onOpenCommandPalette: shortcut == CodeLabShortcut.commandPalette
            ? hit
            : null,
        onNewSession: shortcut == CodeLabShortcut.newSession ? hit : null,
        onOpenSettings: shortcut == CodeLabShortcut.openSettings ? hit : null,
        onToggleSidebar: shortcut == CodeLabShortcut.toggleSidebar ? hit : null,
        onToggleFiles: shortcut == CodeLabShortcut.toggleFiles ? hit : null,
        child: const SizedBox(width: 320, height: 200),
      ),
    ),
  );
  await press(shortcut.combos.single);
  expect(calls, 1, reason: shortcut.name);
}

/// Esc оболочки (`onCancel`) и Esc композера при `canCancel` отменяют ход.
Future<void> _cancelTurn(
  WidgetTester tester,
  CodeLabShortcut shortcut,
  _Press press,
) async {
  var shell = 0;
  await tester.pumpWidget(
    FluentApp(
      home: CodeLabWorkbenchShortcuts(
        onCancel: () => shell++,
        child: const SizedBox(width: 320, height: 200),
      ),
    ),
  );
  await press(shortcut.combos.single);
  expect(shell, 1, reason: 'Esc оболочки');

  var composer = 0;
  await tester.pumpWidget(
    FluentApp(
      home: CodeLabPromptComposer(
        initialPrompt: 'long task',
        canCancel: true,
        onSubmit: (_) {},
        onCancel: () => composer++,
      ),
    ),
  );
  await press(shortcut.combos.single);
  expect(composer, 1, reason: 'Esc композера при canCancel');
}

// ---------------------------------------------------------------------------
// Выдвижная панель раскладки (Esc закрывает; Esc диалогов app — в app).

Future<void> _overlayPanelEscape(
  WidgetTester tester,
  CodeLabShortcut shortcut,
  _Press press,
) async {
  tester.view.physicalSize = const Size(820, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var dismissed = 0;
  await tester.pumpWidget(
    FluentApp(
      home: CodeLabWorkbenchLayout(
        appBar: const SizedBox(),
        sidebar: const Text('Sidebar'),
        sessionPane: const Text('Session'),
        sidebarOverlayOpen: true,
        onSidebarOverlayDismiss: () => dismissed++,
      ),
    ),
  );
  await tester.pump();
  await press(shortcut.combos.single);
  expect(dismissed, 1);
}

// ---------------------------------------------------------------------------
// Композер: отправка и меню команд после `/`.

Widget _composer({
  void Function(String)? onSubmit,
  ValueChanged<CodeLabCommandAction>? onCommand,
  String initialPrompt = '',
}) => FluentApp(
  home: CodeLabPromptComposer(
    initialPrompt: initialPrompt,
    onSubmit: onSubmit ?? (_) {},
    commandActions: _commands,
    onCommandSelected: onCommand ?? (_) {},
  ),
);

const _commands = [
  CodeLabCommandAction(
    id: 'first',
    label: 'First',
    slashCommand: '/first',
    description: 'First command.',
    icon: FluentIcons.add,
  ),
  CodeLabCommandAction(
    id: 'second',
    label: 'Second',
    slashCommand: '/second',
    description: 'Second command.',
    icon: FluentIcons.add,
  ),
  CodeLabCommandAction(
    id: 'third',
    label: 'Third',
    slashCommand: '/third',
    description: 'Third command.',
    icon: FluentIcons.add,
  ),
];

CodeLabKeyCombo _comboOf(CodeLabShortcut shortcut, LogicalKeyboardKey key) =>
    shortcut.combos.singleWhere((c) => c.key == key);

Future<void> _composerSend(
  WidgetTester tester,
  CodeLabShortcut shortcut,
  _Press press,
) async {
  final submitted = <String>[];
  await tester.pumpWidget(_composer(onSubmit: submitted.add));
  await tester.enterText(find.byType(EditableText), 'hello');
  await tester.pump();

  await press(shortcut.combos.single);

  expect(submitted, ['hello']);
}

Future<void> _commandMenuMove(
  WidgetTester tester,
  CodeLabShortcut shortcut,
  _Press press,
) async {
  final down = _comboOf(shortcut, LogicalKeyboardKey.arrowDown);
  final up = _comboOf(shortcut, LogicalKeyboardKey.arrowUp);
  final run = CodeLabShortcut.commandMenuRun.combos.single;

  Future<String?> runAfter(List<CodeLabKeyCombo> presses) async {
    String? selected;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_composer(onCommand: (a) => selected = a.id));
    await tester.enterText(find.byType(EditableText), '/');
    await tester.pump();
    for (final combo in presses) {
      await press(combo);
    }
    await press(run);
    return selected;
  }

  expect(await runAfter([down]), 'second', reason: '↓ подсвечивает следующую');
  expect(
    await runAfter([down, up]),
    'first',
    reason: '↑ возвращает на предыдущую',
  );
}

Future<void> _commandMenuRun(
  WidgetTester tester,
  CodeLabShortcut shortcut,
  _Press press,
) async {
  CodeLabCommandAction? selected;
  await tester.pumpWidget(_composer(onCommand: (a) => selected = a));
  await tester.enterText(find.byType(EditableText), '/');
  await tester.pump();

  await press(shortcut.combos.single);

  expect(selected?.id, 'first');
}

Future<void> _commandMenuClose(
  WidgetTester tester,
  CodeLabShortcut shortcut,
  _Press press,
) async {
  await tester.pumpWidget(_composer());
  await tester.enterText(find.byType(EditableText), '/');
  await tester.pump();
  expect(find.byType(CodeLabCommandPaletteSurface), findsOneWidget);

  await press(shortcut.combos.single);

  expect(find.byType(CodeLabCommandPaletteSurface), findsNothing);
}

// ---------------------------------------------------------------------------
// Дерево Files: ↑/↓, →/←, Enter и numpad Enter.

Widget _tree({
  required List<CodeLabFileTreeRowData> rows,
  ValueChanged<CodeLabFileTreeRowData>? onToggle,
  ValueChanged<CodeLabFileTreeRowData>? onOpen,
}) => FluentApp(
  home: ScaffoldPage(
    padding: EdgeInsets.zero,
    content: SizedBox(
      width: 320,
      height: 400,
      child: CodeLabFileTree(
        rows: rows,
        onToggleDirectory: onToggle,
        onOpenFile: onOpen,
        autofocus: true,
      ),
    ),
  ),
);

CodeLabFileTreeRowData _file(String path) => CodeLabFileTreeRowData(
  relativePath: path,
  name: path,
  kind: CodeLabFileTreeRowKind.file,
  depth: 0,
);

CodeLabFileTreeRowData _dir(String path, {bool expanded = false}) =>
    CodeLabFileTreeRowData(
      relativePath: path,
      name: path,
      kind: CodeLabFileTreeRowKind.directory,
      depth: 0,
      expanded: expanded,
    );

Future<void> _fileTreeMove(
  WidgetTester tester,
  CodeLabShortcut shortcut,
  _Press press,
) async {
  final down = _comboOf(shortcut, LogicalKeyboardKey.arrowDown);
  final up = _comboOf(shortcut, LogicalKeyboardKey.arrowUp);
  final open = CodeLabShortcut.fileTreeOpen.combos.single;
  final rows = [_file('a.txt'), _file('b.txt'), _file('c.txt')];

  Future<List<String>> openedAfter(List<CodeLabKeyCombo> presses) async {
    final opened = <String>[];
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _tree(rows: rows, onOpen: (row) => opened.add(row.relativePath)),
    );
    await tester.pump();
    for (final combo in presses) {
      await press(combo);
    }
    await press(open);
    return opened;
  }

  expect(await openedAfter([down]), ['b.txt'], reason: '↓');
  expect(await openedAfter([down, down, up]), ['b.txt'], reason: '↓ ↓ ↑');
}

Future<void> _fileTreeFold(
  WidgetTester tester,
  CodeLabShortcut shortcut,
  _Press press,
) async {
  final right = _comboOf(shortcut, LogicalKeyboardKey.arrowRight);
  final left = _comboOf(shortcut, LogicalKeyboardKey.arrowLeft);

  final expanded = <String>[];
  await tester.pumpWidget(
    _tree(
      rows: [_dir('lib')],
      onToggle: (row) => expanded.add(row.relativePath),
    ),
  );
  await tester.pump();
  await press(right);
  expect(expanded, ['lib'], reason: '→ раскрывает свёрнутую папку');

  final collapsed = <String>[];
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    _tree(
      rows: [_dir('lib', expanded: true)],
      onToggle: (row) => collapsed.add(row.relativePath),
    ),
  );
  await tester.pump();
  await press(left);
  expect(collapsed, ['lib'], reason: '← сворачивает раскрытую папку');
}

Future<void> _fileTreeOpen(
  WidgetTester tester,
  CodeLabShortcut shortcut,
  _Press press,
) async {
  final combo = shortcut.combos.single;
  for (final key in [combo.key, ...combo.alsoKeys]) {
    final opened = <String>[];
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _tree(rows: [_file('a.txt')], onOpen: (r) => opened.add(r.relativePath)),
    );
    await tester.pump();
    await press(combo, key: key);
    expect(opened, ['a.txt'], reason: key.keyLabel);
  }
}

// ---------------------------------------------------------------------------
// Одобрение: четыре варианта по `kind`; подписи вариантов не на английском,
// чтобы выбор по виду, а не по тексту, был виден (ACP: `name` — текст агента).

const _options = [
  CodeLabApprovalOption(
    id: 'ao',
    label: 'Разрешить один раз',
    kind: CodeLabApprovalOptionKind.allowOnce,
  ),
  CodeLabApprovalOption(
    id: 'aa',
    label: 'Всегда разрешать',
    kind: CodeLabApprovalOptionKind.allowAlways,
  ),
  CodeLabApprovalOption(
    id: 'ro',
    label: 'Отклонить',
    kind: CodeLabApprovalOptionKind.rejectOnce,
  ),
  CodeLabApprovalOption(
    id: 'ra',
    label: 'Всегда отклонять',
    kind: CodeLabApprovalOptionKind.rejectAlways,
  ),
];

CodeLabApprovalOptionKind _kindOf(CodeLabShortcut shortcut) =>
    switch (shortcut) {
      CodeLabShortcut.allowOnce => CodeLabApprovalOptionKind.allowOnce,
      CodeLabShortcut.allowAlways => CodeLabApprovalOptionKind.allowAlways,
      CodeLabShortcut.rejectOnce => CodeLabApprovalOptionKind.rejectOnce,
      CodeLabShortcut.rejectAlways => CodeLabApprovalOptionKind.rejectAlways,
      _ => throw ArgumentError('не одобрение: $shortcut'),
    };

Future<void> _approval(
  WidgetTester tester,
  CodeLabShortcut shortcut,
  _Press press,
) async {
  final expectedId = _options
      .singleWhere((o) => o.kind == _kindOf(shortcut))
      .id;
  final combo = shortcut.combos.single;

  final fromGroup = <String>[];
  await tester.pumpWidget(
    FluentApp(
      home: CodeLabApprovalOptionGroup(
        options: _options,
        onSelected: fromGroup.add,
      ),
    ),
  );
  await tester.pump();
  await press(combo);
  expect(fromGroup, [expectedId], reason: 'CodeLabApprovalOptionGroup');

  final fromPrompt = <String>[];
  await tester.pumpWidget(
    FluentApp(
      home: Center(
        child: SizedBox(
          width: 720,
          child: CodeLabApprovalPrompt(
            options: _options,
            onOptionSelected: fromPrompt.add,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await press(combo);
  expect(fromPrompt, [expectedId], reason: 'CodeLabApprovalPrompt');
}
