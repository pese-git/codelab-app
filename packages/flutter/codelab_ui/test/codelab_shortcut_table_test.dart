// Кейкапы и таблица сочетаний (задача 2.1 change `add-app-keyboard-page`;
// design.md D6, D9; spec app-settings «Страница «Keyboard»: обозначения
// клавиш» и «…язык, доступность и узкое окно»).
//
// Красный до задачи 2.2: `CodeLabKeycaps` и `CodeLabShortcutTable` — заглушки,
// которые ничего не рисуют, а сообщения `codeLabShortcutAlternatives` в ARB
// кита ещё нет. Платформа подменяется `debugDefaultTargetPlatformOverride`
// и сбрасывается в `tearDown`. Проверяется поведение, не пиксели.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Хост без делегата кита (английский), как у прежних тестов кита.
Widget _enHost(Widget child, {double width = 1000}) => FluentApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: width, child: child),
  ),
);

/// Хост с русским языком и делегатом кита.
Widget _ruHost(Widget child) => FluentApp(
  locale: const Locale('ru'),
  localizationsDelegates: CodeLabLocalizations.localizationsDelegates,
  supportedLocales: CodeLabLocalizations.supportedLocales,
  home: Align(alignment: Alignment.topLeft, child: child),
);

/// Тексты плашек: `CodeLabText` роли `mono` внутри [scope].
List<String> _caps(WidgetTester tester, Finder scope) => [
  for (final text in tester.widgetList<CodeLabText>(
    find.descendant(of: scope, matching: find.byType(CodeLabText)),
  ))
    if (text.role == CodeLabTextRole.mono) text.data,
];

CodeLabKeyCombo _combo(CodeLabShortcut shortcut, [int index = 0]) =>
    shortcut.combos[index];

/// Таблица из трёх групп: «Approvals» с самой широкой строкой кейкапов,
/// «Navigation» с альтернативами и «Global» с длинным текстом действия.
CodeLabShortcutTable _table() => CodeLabShortcutTable(
  actionHeader: 'Action',
  shortcutHeader: 'Shortcut',
  whereHeader: 'Where',
  groups: [
    CodeLabShortcutTableGroup(
      key: const ValueKey('group-global'),
      title: 'Global',
      rows: [
        CodeLabShortcutTableRow(
          key: const ValueKey('row-close-overlay'),
          action: 'Close the command palette, a dialog or a sliding panel',
          combos: CodeLabShortcut.closeOverlay.combos,
          where: 'Command palette, dialog or sliding panel',
        ),
      ],
    ),
    CodeLabShortcutTableGroup(
      key: const ValueKey('group-navigation'),
      title: 'Navigation',
      rows: [
        CodeLabShortcutTableRow(
          key: const ValueKey('row-file-tree-move'),
          action: 'Move through files',
          combos: CodeLabShortcut.fileTreeMove.combos,
          where: 'Files tree',
        ),
      ],
    ),
    CodeLabShortcutTableGroup(
      key: const ValueKey('group-approvals'),
      title: 'Approvals',
      rows: [
        CodeLabShortcutTableRow(
          key: const ValueKey('row-allow-always'),
          action: 'Allow always',
          combos: CodeLabShortcut.allowAlways.combos,
          where: 'Pending approval in focus, when the agent offers this option',
        ),
      ],
    ),
  ],
);

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('CodeLabKeycaps', () {
    testWidgets('по плашке на клавишу, роль mono; macOS — ⌥ ⌘ ⏎', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.pumpWidget(
        _enHost(CodeLabKeycaps(combos: [_combo(CodeLabShortcut.allowAlways)])),
      );

      expect(_caps(tester, find.byType(CodeLabKeycaps)), ['⌥', '⌘', '⏎']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Windows и Linux — слова Ctrl Alt Enter', (tester) async {
      await tester.pumpWidget(
        _enHost(CodeLabKeycaps(combos: [_combo(CodeLabShortcut.allowAlways)])),
      );

      expect(_caps(tester, find.byType(CodeLabKeycaps)), [
        'Ctrl',
        'Alt',
        'Enter',
      ]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('одна подпись Semantics словами, плашки не читаются', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      addTearDown(handle.dispose);
      await tester.pumpWidget(
        _enHost(CodeLabKeycaps(combos: [_combo(CodeLabShortcut.allowAlways)])),
      );

      expect(
        tester.getSemantics(find.byType(CodeLabKeycaps)).label,
        'Option+Cmd+Enter',
      );
      for (final symbol in const ['⌥', '⌘', '⏎']) {
        expect(find.bySemanticsLabel(symbol), findsNothing, reason: symbol);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('альтернативы: плашки обеих клавиш и подпись «Up or Down»', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      addTearDown(handle.dispose);
      await tester.pumpWidget(
        _enHost(CodeLabKeycaps(combos: CodeLabShortcut.fileTreeMove.combos)),
      );

      expect(_caps(tester, find.byType(CodeLabKeycaps)), ['↑', '↓']);
      expect(
        tester.getSemantics(find.byType(CodeLabKeycaps)).label,
        'Up or Down',
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('на ru с делегатом «or» переведено сообщением '
        'codeLabShortcutAlternatives', (tester) async {
      final handle = tester.ensureSemantics();
      addTearDown(handle.dispose);
      await tester.pumpWidget(
        _ruHost(CodeLabKeycaps(combos: CodeLabShortcut.fileTreeMove.combos)),
      );

      final label = tester.getSemantics(find.byType(CodeLabKeycaps)).label;
      expect(label, 'Up или Down');
      expect(label, isNot(contains(' or ')));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  group('CodeLabShortcutTable', () {
    testWidgets('шапка из переданных подписей и группы с заголовками', (
      tester,
    ) async {
      await tester.pumpWidget(_enHost(_table()));

      for (final text in const [
        'Action',
        'Shortcut',
        'Where',
        'Global',
        'Navigation',
        'Approvals',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('ключи групп и строк — от вызывающего', (tester) async {
      await tester.pumpWidget(_enHost(_table()));

      for (final key in const [
        'group-global',
        'group-navigation',
        'group-approvals',
        'row-close-overlay',
        'row-file-tree-move',
        'row-allow-always',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      expect(_caps(tester, find.byKey(const ValueKey('row-allow-always'))), [
        'Ctrl',
        'Alt',
        'Enter',
      ]);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('заголовок группы помечен header: true', (tester) async {
      final handle = tester.ensureSemantics();
      addTearDown(handle.dispose);
      await tester.pumpWidget(_enHost(_table()));

      for (final key in const [
        'group-global',
        'group-navigation',
        'group-approvals',
      ]) {
        expect(
          tester.getSemantics(find.byKey(ValueKey(key))),
          isSemantics(isHeader: true),
          reason: key,
        );
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('строки не фокусируются: Tab таблицу не обходит', (
      tester,
    ) async {
      final field = FocusNode();
      addTearDown(field.dispose);
      await tester.pumpWidget(
        _enHost(
          Column(
            children: [
              TextBox(focusNode: field, autofocus: true),
              _table(),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('row-allow-always')), findsOneWidget);

      bool inTable(FocusNode node) =>
          node.context?.findAncestorWidgetOfExactType<CodeLabShortcutTable>() !=
          null;
      expect(
        FocusManager.instance.rootScope.descendants.where(
          (n) => inTable(n) && n.canRequestFocus && !n.skipTraversal,
        ),
        isEmpty,
        reason: 'в таблице нет остановок обхода',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final primary = FocusManager.instance.primaryFocus;
      expect(primary == null || !inTable(primary), isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('ширина 400 px: горизонтальная прокрутка без переполнения, '
        'кейкапы не переносятся, текст действия переносится', (tester) async {
      await tester.pumpWidget(_enHost(_table(), width: 400));

      expect(tester.takeException(), isNull);
      final scrolls = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .where((s) => s.scrollDirection == Axis.horizontal);
      expect(scrolls, isNotEmpty, reason: 'горизонтальная прокрутка');

      // Кейкапы одной строки стоят на одной линии и не сжаты до переноса.
      final allowRow = find.byKey(const ValueKey('row-allow-always'));
      final caps = [
        for (final label in const ['Ctrl', 'Alt', 'Enter'])
          find.descendant(of: allowRow, matching: find.text(label)),
      ];
      final tops = [for (final f in caps) tester.getRect(f).center.dy];
      expect(tops.toSet(), hasLength(1), reason: 'кейкапы на одной линии');

      // Длинное «действие» переносится: выше однострочного «Allow always».
      final longAction = tester.getSize(
        find.text('Close the command palette, a dialog or a sliding panel'),
      );
      final shortAction = tester.getSize(find.text('Allow always'));
      expect(longAction.height, greaterThan(shortAction.height));

      // После прокрутки все кейкапы строки видны целиком.
      await tester.ensureVisible(caps.last);
      await tester.pump();
      final viewport = tester.getRect(find.byType(CodeLabShortcutTable));
      for (final f in caps) {
        expect(
          tester.getRect(f).right,
          lessThanOrEqualTo(viewport.right),
          reason: 'кейкап виден после прокрутки',
        );
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}
