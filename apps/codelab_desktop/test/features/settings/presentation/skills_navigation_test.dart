// Навигация настроек со страницей «Skills & extensions» (задача 4.6 change
// `add-app-skills-page`; spec app-settings «Страницы Providers и MCP servers
// в навигации», сценарии «Четыре страницы группы Agent» и «Поиск AGENTS.md»).
//
// Отдельный файл: прежние тесты `settings_shell_test.dart` фиксируют набор из
// трёх страниц (`defaultSettingsPages.visible`) и обновляются отдельным
// решением; здесь — проверка нового набора на тех же данных, что в
// production (`defaultSettingsPages`, `settingsPageBuilders`).

import 'package:codelab_desktop/app/default_settings_pages.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/settings/application/settings_search_index.dart';
import 'package:codelab_desktop/features/settings/presentation/settings_shell.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _nav(SettingsPage page) => find.byKey(ValueKey(page.navKey));

void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FluentApp(
        home: SettingsShell(
          pages: defaultSettingsPages,
          selected: SettingsPage.connection,
          onSelected: (_) {},
          onBack: () {},
          // Тела-заглушки: страницы строят Cubit-ы composition root.
          builders: {
            for (final page in SettingsPage.values)
              page: (_) => Text('body of ${page.slug}'),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('the production set has Skills & extensions with a body builder', () {
    expect(defaultSettingsPages.visible, [
      SettingsPage.connection,
      SettingsPage.providers,
      SettingsPage.mcpServers,
      SettingsPage.skillsAndExtensions,
    ]);
    expect(settingsPageBuilders, contains(SettingsPage.skillsAndExtensions));
  });

  testWidgets('Four pages of the Agent group in this order, no App title', (
    tester,
  ) async {
    await pumpShell(tester);

    final ys = [
      for (final page in const [
        SettingsPage.connection,
        SettingsPage.providers,
        SettingsPage.mcpServers,
        SettingsPage.skillsAndExtensions,
      ])
        tester.getTopLeft(_nav(page)).dy,
    ];
    expect(ys, [...ys]..sort());
    expect(ys.toSet(), hasLength(4));
    expect(
      SettingsPage.skillsAndExtensions.navKey,
      'settings-nav-skills-and-extensions',
    );
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('App'), findsNothing);
  });

  testWidgets('search "agents.md" keeps Skills & extensions', (tester) async {
    await pumpShell(tester);

    await tester.enterText(
      find.byKey(CodeLabSettingsNavigation.searchKey),
      'agents.md',
    );
    await tester.pumpAndSettle();

    expect(_nav(SettingsPage.skillsAndExtensions), findsOneWidget);
    expect(_nav(SettingsPage.providers), findsNothing);
    expect(_nav(SettingsPage.mcpServers), findsNothing);
    expect(_nav(SettingsPage.connection), findsNothing);
  });

  test('every keyword of the page finds it', () {
    for (final word in const [
      'skill',
      'agents.md',
      'context',
      'template',
      'prompt',
      'extension',
    ]) {
      expect(
        SettingsSearchIndex.search(defaultSettingsPages.visible, word),
        contains(SettingsPage.skillsAndExtensions),
        reason: word,
      );
    }
  });
}
