// Красные тесты задачи 3.3 change `add-desktop-localization`: поиск «Find a
// setting» на русском и английском (spec app-settings «Навигация настроек»,
// сценарии «Поиск по английскому заголовку при русском интерфейсе», «Поиск
// по переведённому заголовку», «Поиск по ключевому слову»; решение
// пользователя 2026-11-18: русские ключевые слова — в итерации 3; design.md
// D5 п. 8).
//
// Страница находится по заголовку на языке интерфейса, по английскому
// заголовку и по ключевым словам на любом из двух языков: пользователь ищет и
// по тому, что видит, и по названию из документации. После итерации 1 ключевые
// слова (`SettingsSearchIndex.keywords`) только английские, поэтому русские
// запросы по ключевым словам красные до задачи 3.4.
//
// Русские ключевые слова — вне глоссария (в нём есть «токен», «ключ API»,
// «навык», «шаблон» как термины); они перечислены в отчёте задачи 3.3. Тест не
// знает, где хранятся слова (ARB, `SettingsSearchIndex`): проверяется видимый
// результат поиска в оболочке настроек.

import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/settings/presentation/settings_shell.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/l10n_app.dart';

const _pages = {
  SettingsPage.connection,
  SettingsPage.providers,
  SettingsPage.mcpServers,
  SettingsPage.agentsAndModes,
  SettingsPage.skillsAndExtensions,
  SettingsPage.general,
};

Finder _nav(SettingsPage page) => find.byKey(ValueKey(page.navKey));

/// Страницы, оставшиеся в навигации после ввода [query] при языке [locale].
Future<Set<SettingsPage>> _found(
  WidgetTester tester,
  String query, {
  required Locale locale,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    localizedFluentApp(
      locale: locale,
      SettingsShell(
        pages: const SettingsPages(available: _pages),
        selected: SettingsPage.general,
        onSelected: (_) {},
        onBack: () {},
        builders: {
          for (final page in SettingsPage.values)
            page: (_) => Text('body of ${page.slug}'),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(CodeLabSettingsNavigation.searchKey),
    query,
  );
  await tester.pumpAndSettle();
  return {
    for (final page in SettingsPage.values)
      if (_nav(page).evaluate().isNotEmpty) page,
  };
}

void main() {
  const ru = Locale('ru');
  const en = Locale('en');

  group('заголовки', () {
    testWidgets('английский заголовок при русском интерфейсе', (tester) async {
      expect(await _found(tester, 'providers', locale: ru), {
        SettingsPage.providers,
      });
    });

    testWidgets('часть переведённого заголовка General', (tester) async {
      expect(await _found(tester, 'Общ', locale: ru), {SettingsPage.general});
    });

    testWidgets('нет совпадений: строка кита на русском', (tester) async {
      await _found(tester, 'zzz', locale: ru);

      expect(find.text('Нет настроек по запросу «zzz»'), findsOneWidget);
    });
  });

  group('ключевые слова на любом из двух языков', () {
    const russian = {
      'токен': SettingsPage.connection,
      'перезапуск': SettingsPage.connection,
      'ключ api': SettingsPage.providers,
      'заголовки': SettingsPage.mcpServers,
      'субагент': SettingsPage.agentsAndModes,
      'шаблон': SettingsPage.skillsAndExtensions,
    };
    for (final entry in russian.entries) {
      testWidgets('«${entry.key}» при русском интерфейсе → '
          '${entry.value.slug}', (tester) async {
        expect(await _found(tester, entry.key, locale: ru), {entry.value});
      });
    }

    testWidgets('русское слово находит страницу и при английском '
        'интерфейсе', (tester) async {
      expect(await _found(tester, 'токен', locale: en), {
        SettingsPage.connection,
      });
    });

    testWidgets('английское ключевое слово при русском интерфейсе', (
      tester,
    ) async {
      expect(await _found(tester, 'token', locale: ru), {
        SettingsPage.connection,
      });
    });

    testWidgets('английское ключевое слово при английском интерфейсе', (
      tester,
    ) async {
      expect(await _found(tester, 'headers', locale: en), {
        SettingsPage.mcpServers,
      });
    });
  });
}
