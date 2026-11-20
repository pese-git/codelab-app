// Навигация настроек со страницей «Skills & extensions» (задача 4.6 change
// `add-app-skills-page`; spec app-settings «Страницы Providers и MCP servers
// в навигации», сценарии «Четыре страницы группы Agent» и «Поиск AGENTS.md»).
//
// Проверка набора из пяти страниц на тех же данных, что в production
// (`defaultSettingsPages`, `settingsPageBuilders`); порядок и объединение
// поиска двух change — design.md `add-settings-agents-modes`, D20.1.

import 'package:codelab_desktop/app/default_settings_pages.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/settings/presentation/settings_shell.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/l10n_app.dart';
import '../../../support/settings_search.dart';

Finder _nav(SettingsPage page) => find.byKey(ValueKey(page.navKey));

void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      localizedFluentApp(
        SettingsShell(
          pages: SettingsPages(
            available: {...defaultSettingsPages.available}
              ..remove(SettingsPage.general)
              ..remove(SettingsPage.appearance),
          ),
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
      SettingsPage.agentsAndModes,
      SettingsPage.skillsAndExtensions,
      SettingsPage.general,
      SettingsPage.appearance,
    ]);
    expect(settingsPageBuilders, contains(SettingsPage.skillsAndExtensions));
  });

  testWidgets('Five pages of the Agent group in this order, no App title', (
    tester,
  ) async {
    await pumpShell(tester);

    final ys = [
      for (final page in const [
        SettingsPage.connection,
        SettingsPage.providers,
        SettingsPage.mcpServers,
        SettingsPage.agentsAndModes,
        SettingsPage.skillsAndExtensions,
      ])
        tester.getTopLeft(_nav(page)).dy,
    ];
    expect(ys, [...ys]..sort());
    expect(ys.toSet(), hasLength(5));
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
    // `agents.md` не входит подстрокой ни в `agent`, ни в «Agents & modes».
    expect(_nav(SettingsPage.agentsAndModes), findsNothing);
  });

  testWidgets('search "agent" keeps both Agents & modes and Skills & '
      'extensions (D20.1)', (tester) async {
    await pumpShell(tester);

    await tester.enterText(
      find.byKey(CodeLabSettingsNavigation.searchKey),
      'agent',
    );
    await tester.pumpAndSettle();

    expect(_nav(SettingsPage.agentsAndModes), findsOneWidget);
    expect(_nav(SettingsPage.skillsAndExtensions), findsOneWidget);
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
        searchSettings(defaultSettingsPages.visible, word),
        contains(SettingsPage.skillsAndExtensions),
        reason: word,
      );
    }
  });
}
