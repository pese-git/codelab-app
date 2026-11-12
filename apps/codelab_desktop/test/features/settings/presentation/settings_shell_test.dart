// Оболочка настроек (задача 1.2 change `add-app-settings-shell`; spec
// app-settings «Навигация настроек»; design.md D3).
//
// Страницы в тестах — тестовый набор `available` с заглушками тел: страница
// «Connection» появляется только в итерации 2.

import 'package:codelab_desktop/app/default_settings_pages.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/settings/application/settings_search_index.dart';
import 'package:codelab_desktop/features/settings/presentation/settings_shell.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _nav(SettingsPage page) => find.byKey(ValueKey(page.navKey));

void main() {
  /// Тела-заглушки для всех страниц: тест выбирает видимые через `available`.
  final bodies = <SettingsPage, WidgetBuilder>{
    for (final page in SettingsPage.values)
      page: (_) => Text('body of ${page.slug}'),
  };

  Future<void> pumpShell(
    WidgetTester tester, {
    required Set<SettingsPage> available,
    SettingsPage selected = SettingsPage.connection,
    Size size = const Size(1200, 800),
    ValueChanged<SettingsPage>? onSelected,
    VoidCallback? onBack,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FluentApp(
        home: SettingsShell(
          pages: SettingsPages(available: available),
          selected: selected,
          onSelected: onSelected ?? (_) {},
          onBack: onBack ?? () {},
          builders: bodies,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Задача 3.15 change `add-provider-setup-ui` (D24, артборды `Connection`,
  // `Providers`: `padding: 28px 40px 40px`). Короткая страница не должна
  // центрироваться по вертикали: верх заголовка — на 28 px ниже верха области
  // содержимого при любой высоте окна.
  for (final height in const [900.0, 1600.0]) {
    testWidgets('page title sits 28 px below the top of the content area at '
        '1280x${height.toInt()}', (tester) async {
      await pumpShell(
        tester,
        available: {SettingsPage.connection, SettingsPage.providers},
        size: Size(1280, height),
      );

      // Область содержимого — под строкой заголовка окна до низа окна;
      // страница не должна ни сжиматься по высоте, ни центрироваться в ней.
      final scroll = tester.getRect(find.byType(SingleChildScrollView).first);
      final area = Rect.fromLTRB(
        scroll.left,
        tester.getRect(find.byType(TitleBar)).bottom,
        scroll.right,
        height,
      );
      expect(scroll.bottom, height);
      final title = tester.getTopLeft(find.text('body of connection'));
      expect(title.dy - area.top, 28);
    });
  }

  testWidgets('orders pages by section 12.4.9 whatever the registration '
      'order', (tester) async {
    await pumpShell(
      tester,
      available: {
        SettingsPage.keyboard,
        SettingsPage.connection,
        SettingsPage.general,
      },
    );

    final connection = tester.getTopLeft(_nav(SettingsPage.connection));
    final general = tester.getTopLeft(_nav(SettingsPage.general));
    final keyboard = tester.getTopLeft(_nav(SettingsPage.keyboard));
    expect(connection.dy, lessThan(general.dy));
    expect(general.dy, lessThan(keyboard.dy));
    // Connection — в группе Agent, General и Keyboard — в группе App.
    final agent = tester.getTopLeft(find.text('Agent'));
    final app = tester.getTopLeft(find.text('App'));
    expect(agent.dy, lessThan(connection.dy));
    expect(connection.dy, lessThan(app.dy));
    expect(app.dy, lessThan(general.dy));
  });

  testWidgets('shows only available pages and no title for an empty group', (
    tester,
  ) async {
    await pumpShell(tester, available: {SettingsPage.connection});

    expect(_nav(SettingsPage.connection), findsOneWidget);
    expect(_nav(SettingsPage.general), findsNothing);
    expect(_nav(SettingsPage.providers), findsNothing);
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('App'), findsNothing);
    // Заголовки групп — PaneItemWidgetAdapter; у пустой группы его нет.
    final pane = tester
        .widget<NavigationView>(find.byType(NavigationView))
        .pane!;
    expect(pane.items.whereType<PaneItemWidgetAdapter>(), hasLength(1));
  });

  testWidgets('gives every item the key settings-nav-<page>', (tester) async {
    await pumpShell(
      tester,
      available: {SettingsPage.connection, SettingsPage.mcpServers},
    );

    expect(
      find.byKey(const ValueKey('settings-nav-connection')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-nav-mcp-servers')),
      findsOneWidget,
    );
  });

  testWidgets('shows the body of the selected page and reports a tap on '
      'another one', (tester) async {
    SettingsPage? tapped;
    await pumpShell(
      tester,
      available: {SettingsPage.connection, SettingsPage.general},
      selected: SettingsPage.general,
      onSelected: (page) => tapped = page,
    );

    expect(find.text('body of general'), findsOneWidget);

    await tester.tap(_nav(SettingsPage.connection));
    await tester.pumpAndSettle();
    expect(tapped, SettingsPage.connection);
  });

  testWidgets('search "token" keeps Connection and hides the others', (
    tester,
  ) async {
    await pumpShell(
      tester,
      available: {SettingsPage.connection, SettingsPage.general},
    );

    await tester.enterText(
      find.byKey(CodeLabSettingsNavigation.searchKey),
      'token',
    );
    await tester.pumpAndSettle();

    expect(_nav(SettingsPage.connection), findsOneWidget);
    expect(_nav(SettingsPage.general), findsNothing);
  });

  testWidgets('search "zzz" shows the no-match line', (tester) async {
    await pumpShell(
      tester,
      available: {SettingsPage.connection, SettingsPage.general},
    );

    await tester.enterText(
      find.byKey(CodeLabSettingsNavigation.searchKey),
      'zzz',
    );
    await tester.pumpAndSettle();

    expect(find.text('No settings match "zzz"'), findsOneWidget);
    expect(_nav(SettingsPage.connection), findsNothing);
  });

  testWidgets('a 700 px window puts navigation on top, 800 px on the left', (
    tester,
  ) async {
    final available = {SettingsPage.connection, SettingsPage.general};

    await pumpShell(tester, available: available, size: const Size(700, 800));
    final topItem = tester.getRect(_nav(SettingsPage.connection));
    final topBody = tester.getRect(find.text('body of connection'));
    expect(topItem.bottom, lessThanOrEqualTo(topBody.top));
    expect(
      tester
          .widget<NavigationView>(find.byType(NavigationView))
          .pane!
          .displayMode,
      PaneDisplayMode.top,
    );

    await pumpShell(tester, available: available, size: const Size(800, 800));
    final leftItem = tester.getRect(_nav(SettingsPage.connection));
    final leftBody = tester.getRect(find.text('body of connection'));
    expect(leftItem.right, lessThanOrEqualTo(leftBody.left));
    expect(
      tester
          .widget<NavigationView>(find.byType(NavigationView))
          .pane!
          .displayMode,
      PaneDisplayMode.expanded,
    );
  });

  testWidgets('the shell owns a focus scope and traversal group', (
    tester,
  ) async {
    await pumpShell(tester, available: {SettingsPage.connection});

    final scope = find.descendant(
      of: find.byType(SettingsShell),
      matching: find.byType(FocusScope),
    );
    expect(scope, findsWidgets);
    expect(
      find.descendant(
        of: find.byType(SettingsShell),
        matching: find.byType(FocusTraversalGroup),
      ),
      findsWidgets,
    );
  });

  testWidgets('Tab traversal never leaves the settings shell (H1)', (
    tester,
  ) async {
    final outside = FocusNode(debugLabel: 'outside');
    addTearDown(outside.dispose);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FluentApp(
        home: Column(
          children: [
            Expanded(
              child: SettingsShell(
                pages: const SettingsPages(
                  available: {SettingsPage.connection, SettingsPage.general},
                ),
                selected: SettingsPage.connection,
                onSelected: (_) {},
                onBack: () {},
                builders: bodies,
              ),
            ),
            // Соседняя фокусируемая кнопка вне оболочки — стоит в обходе
            // родительской области, если оболочка не держит свою.
            Button(
              focusNode: outside,
              onPressed: () {},
              child: const Text('x'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 40; i++) {
      FocusManager.instance.primaryFocus!.nextFocus();
      await tester.pump();
      expect(outside.hasFocus, isFalse, reason: 'step $i');
    }
    for (var i = 0; i < 40; i++) {
      FocusManager.instance.primaryFocus!.previousFocus();
      await tester.pump();
      expect(outside.hasFocus, isFalse, reason: 'back step $i');
    }
  });

  testWidgets('Esc and the Back button call onBack', (tester) async {
    var backs = 0;
    await pumpShell(
      tester,
      available: {SettingsPage.connection},
      onBack: () => backs++,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(backs, 1);

    await tester.tap(find.byKey(CodeLabSettingsNavigation.backKey));
    await tester.pumpAndSettle();
    expect(backs, 2);
  });

  test('the production set shows Connection, Providers and MCP servers in '
      'the Agent group (SETUP-17)', () {
    expect(defaultSettingsPages.visible, [
      SettingsPage.connection,
      SettingsPage.providers,
      SettingsPage.mcpServers,
    ]);
  });

  // Задача 5.5 change `add-provider-setup-ui` (spec app-settings «Страницы
  // Providers и MCP servers в навигации», сценарий «Три страницы группы
  // Agent»): красный до задачи 5.10 (`SettingsPage.mcpServers` в
  // `defaultSettingsPages` и `settingsPageBuilders`).
  testWidgets('Three pages of the Agent group: Connection, Providers and '
      'MCP servers in this order, no App title', (tester) async {
    await pumpShell(tester, available: defaultSettingsPages.available);

    expect(_nav(SettingsPage.mcpServers), findsOneWidget);
    expect(SettingsPage.mcpServers.navKey, 'settings-nav-mcp-servers');
    final connection = tester.getTopLeft(_nav(SettingsPage.connection));
    final providers = tester.getTopLeft(_nav(SettingsPage.providers));
    final mcp = tester.getTopLeft(_nav(SettingsPage.mcpServers));
    expect(connection.dy, lessThan(providers.dy));
    expect(providers.dy, lessThan(mcp.dy));
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('App'), findsNothing);
    expect(settingsPageBuilders, contains(SettingsPage.mcpServers));
  });

  testWidgets('search "headers" keeps MCP servers', (tester) async {
    await pumpShell(tester, available: defaultSettingsPages.available);

    await tester.enterText(
      find.byKey(CodeLabSettingsNavigation.searchKey),
      'headers',
    );
    await tester.pumpAndSettle();

    expect(_nav(SettingsPage.mcpServers), findsOneWidget);
    expect(_nav(SettingsPage.providers), findsNothing);
    expect(_nav(SettingsPage.connection), findsNothing);
  });

  testWidgets('search "api key" keeps Providers', (tester) async {
    await pumpShell(
      tester,
      available: {SettingsPage.connection, SettingsPage.providers},
    );

    await tester.enterText(
      find.byKey(CodeLabSettingsNavigation.searchKey),
      'api key',
    );
    await tester.pumpAndSettle();

    expect(_nav(SettingsPage.providers), findsOneWidget);
    expect(_nav(SettingsPage.connection), findsNothing);
  });

  test('the production builder table is immutable', () {
    expect(
      () =>
          settingsPageBuilders[SettingsPage.connection] = (_) =>
              const SizedBox(),
      throwsUnsupportedError,
    );
  });

  test('every page of the production available set has a body builder', () {
    expect(
      settingsPageBuilders.keys,
      containsAll(defaultSettingsPages.available),
    );
  });

  group('SettingsSearchIndex', () {
    const visible = [
      SettingsPage.connection,
      SettingsPage.general,
      SettingsPage.keyboard,
    ];

    test('an empty query keeps all visible pages in order', () {
      expect(SettingsSearchIndex.search(visible, ''), visible);
      expect(SettingsSearchIndex.search(visible, '  '), visible);
    });

    test('matches a title by substring without regard to case', () {
      expect(SettingsSearchIndex.search(visible, 'KEYB'), [
        SettingsPage.keyboard,
      ]);
    });

    test('matches Connection keywords', () {
      for (final word in const [
        'profile',
        'stdio',
        'websocket',
        'token',
        'restart',
      ]) {
        expect(SettingsSearchIndex.search(visible, word), [
          SettingsPage.connection,
        ], reason: word);
      }
    });

    test('matches Providers keywords', () {
      const pages = [SettingsPage.connection, SettingsPage.providers];
      for (final word in const [
        'provider',
        'model',
        'api key',
        'key storage',
        'base url',
      ]) {
        expect(SettingsSearchIndex.search(pages, word), [
          SettingsPage.providers,
        ], reason: word);
      }
    });

    test('matches MCP servers keywords', () {
      const pages = [
        SettingsPage.connection,
        SettingsPage.providers,
        SettingsPage.mcpServers,
      ];
      for (final word in const ['mcp', 'server', 'tools', 'headers']) {
        expect(SettingsSearchIndex.search(pages, word), [
          SettingsPage.mcpServers,
        ], reason: word);
      }
    });

    test('never returns a page that is not visible', () {
      expect(
        SettingsSearchIndex.search(const [SettingsPage.general], 'token'),
        isEmpty,
      );
    });
  });
}
