// Тесты `CodeLabSettingsNavigation` (задача 1.4 change
// `add-app-settings-shell`; D16): группы, выбранный пункт, поиск, режимы
// `left`/`top`, «Back». Проверяется поведение, а не пиксели.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _items = [
  CodeLabSettingsNavItem(
    id: 'connection',
    title: 'Connection',
    icon: FluentIcons.plug_connected,
    group: 'Agent',
  ),
  CodeLabSettingsNavItem(
    id: 'providers',
    title: 'Providers',
    icon: FluentIcons.cloud,
    group: 'Agent',
  ),
  CodeLabSettingsNavItem(
    id: 'general',
    title: 'General',
    icon: FluentIcons.settings,
    group: 'App',
  ),
];

void main() {
  void setWindow(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpNav(
    WidgetTester tester, {
    List<CodeLabSettingsNavItem> items = _items,
    String selectedId = 'connection',
    CodeLabSettingsNavMode mode = CodeLabSettingsNavMode.left,
    ValueChanged<String>? onSelected,
    ValueChanged<String>? onQueryChanged,
    VoidCallback? onBack,
  }) async {
    setWindow(tester, const Size(1000, 700));
    await tester.pumpWidget(
      FluentApp(
        home: CodeLabSettingsNavigation(
          items: items,
          selectedId: selectedId,
          mode: mode,
          onSelected: onSelected ?? (_) {},
          onQueryChanged: onQueryChanged ?? (_) {},
          onBack: onBack ?? () {},
          child: const Text('page body'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows each group title once and the page body', (tester) async {
    await pumpNav(tester);

    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('page body'), findsOneWidget);
    expect(
      find.byKey(CodeLabSettingsNavigation.itemKey('connection')),
      findsOneWidget,
    );
    expect(
      find.byKey(CodeLabSettingsNavigation.itemKey('general')),
      findsOneWidget,
    );
  });

  testWidgets('does not draw a title for a group without items', (
    tester,
  ) async {
    await pumpNav(tester, items: [_items[2]], selectedId: 'general');

    expect(find.text('Agent'), findsNothing);
    expect(find.text('App'), findsOneWidget);
  });

  testWidgets('marks the selected item and reports taps', (tester) async {
    String? tapped;
    await pumpNav(
      tester,
      selectedId: 'providers',
      onSelected: (v) => tapped = v,
    );

    final view = tester.widget<NavigationView>(find.byType(NavigationView));
    final selectedIndex = view.pane!.selected!;
    final selectedItem = view.pane!.effectiveItems[selectedIndex];
    expect(selectedItem.key, CodeLabSettingsNavigation.itemKey('providers'));

    await tester.tap(find.byKey(CodeLabSettingsNavigation.itemKey('general')));
    await tester.pumpAndSettle();
    expect(tapped, 'general');
  });

  testWidgets('typing in the search field reports the query', (tester) async {
    final queries = <String>[];
    await pumpNav(tester, onQueryChanged: queries.add);

    await tester.enterText(
      find.byKey(CodeLabSettingsNavigation.searchKey),
      'tok',
    );
    await tester.pump();

    expect(queries, ['tok']);
  });

  testWidgets('an empty result for a query shows the no-match line', (
    tester,
  ) async {
    await pumpNav(tester, items: const []);
    expect(find.textContaining('No settings match'), findsNothing);

    await tester.enterText(
      find.byKey(CodeLabSettingsNavigation.searchKey),
      'zzz',
    );
    await tester.pump();

    expect(find.text('No settings match "zzz"'), findsOneWidget);
  });

  testWidgets('left mode puts the items beside the page, top mode above it', (
    tester,
  ) async {
    await pumpNav(tester);
    final leftItem = tester.getRect(
      find.byKey(CodeLabSettingsNavigation.itemKey('connection')),
    );
    final leftBody = tester.getRect(find.text('page body'));
    expect(leftItem.right, lessThanOrEqualTo(leftBody.left));

    await pumpNav(tester, mode: CodeLabSettingsNavMode.top);
    final topItem = tester.getRect(
      find.byKey(CodeLabSettingsNavigation.itemKey('connection')),
    );
    final topBody = tester.getRect(find.text('page body'));
    expect(topItem.bottom, lessThanOrEqualTo(topBody.top));
  });

  testWidgets('the Back button calls onBack', (tester) async {
    var backs = 0;
    await pumpNav(tester, onBack: () => backs++);

    await tester.tap(find.byKey(CodeLabSettingsNavigation.backKey));
    await tester.pumpAndSettle();

    expect(backs, 1);
  });

  // Ключи для автотестов страниц настроек (находки ручного прогона
  // итерации 2): поле поиска и «Back» находятся по строковым ключам, а
  // «Back» подписана подсказкой.
  testWidgets('the search field and the Back button have stable string keys', (
    tester,
  ) async {
    await pumpNav(tester);

    expect(find.byKey(const ValueKey('settings-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-back')), findsOneWidget);
  });

  testWidgets('the Back button has the tooltip "Back"', (tester) async {
    await pumpNav(tester);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('settings-back')),
        matching: find.byType(Tooltip),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  // Задача 3.15/3.16 change `add-provider-setup-ui` (D24): тело страницы
  // получает всю высоту области содержимого, а не высоту по содержимому
  // с центрированием внутри `NavigationView`.
  for (final mode in CodeLabSettingsNavMode.values) {
    testWidgets('the page body fills the content area in $mode mode', (
      tester,
    ) async {
      setWindow(tester, const Size(1000, 900));
      await tester.pumpWidget(
        FluentApp(
          home: CodeLabSettingsNavigation(
            items: _items,
            selectedId: 'connection',
            mode: mode,
            onSelected: (_) {},
            onQueryChanged: (_) {},
            onBack: () {},
            // Прокручиваемая страница: она сжимается до высоты содержимого, если
            // получает неограниченно-свободные ограничения (причина D24).
            child: const SingleChildScrollView(
              key: ValueKey('page-fill'),
              child: SizedBox(height: 100),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final title = tester.getRect(find.byType(TitleBar));
      final page = tester.getRect(find.byKey(const ValueKey('page-fill')));
      expect(page.bottom, 900);
      expect(page.top, greaterThanOrEqualTo(title.bottom));
      expect(page.top, lessThan(title.bottom + 60));
    });
  }
}
