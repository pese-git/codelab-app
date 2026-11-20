// Страница «Legal» на устройстве (задача 7.1 change `add-app-legal-page`; spec
// app-settings «Страница «Legal»…», «Раздел «About» страницы «General»»;
// design.md D2, D4, D9; `dart-agent-and-clients` §12.7.10).
//
// Сценарий: «General» → «About» → «Terms of use» открывает вкладку с текстом
// `assets/legal/TERMS.md` из настоящей сборки (ресурсы и `LicenseRegistry` —
// без двойников) → «License» → «Third-party notices» → поиск `flutter`
// показывает `M of N packages` → `reqwest` даёт «No packages match» →
// «Clear search» возвращает полный список → русский интерфейс показывает
// `assets/legal/TERMS.ru.md`. Подключение к агенту не нужно: страница читает
// только ресурсы сборки, поэтому тест не зависит от `E2eAgent.launch`.
//
// В `feature/*` файл только компилируется (`fvm flutter analyze`); на
// устройстве или симуляторе его запускает `release/<version>` скриптом
// `test:e2e:app:legal` (AGENTS.md §21).

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_agent.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle();

/// Открывает настройки на странице [page] (`settings-nav-<page>`).
Future<void> _openSettings(WidgetTester tester, String page) async {
  await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
  await _settle(tester);
  await tester.tap(_key('settings-nav-$page'));
  await _settle(tester);
}

/// Нажимает кнопку раздела «About» (раздел свёрнут по умолчанию).
Future<void> _pressAbout(WidgetTester tester, String buttonKey) async {
  await tester.ensureVisible(_key('settings-general-about'));
  await tester.tap(_key('settings-general-about'));
  await _settle(tester);
  await tester.ensureVisible(_key(buttonKey));
  await tester.tap(_key(buttonKey));
  await _settle(tester);
}

Future<void> _pickTab(WidgetTester tester, String slug) async {
  // Длинные подписи прокручиваются по горизонтали (D6).
  await tester.ensureVisible(_key('settings-legal-tab-$slug'));
  await tester.tap(_key('settings-legal-tab-$slug'));
  await _settle(tester);
}

/// Текст, подходящий под [pattern] (число пакетов на устройстве заранее
/// неизвестно).
Finder _textMatching(RegExp pattern) => find.byWidgetPredicate(
  (w) => w is Text && w.data != null && pattern.hasMatch(w.data!),
);

Finder _source(String asset) => find.descendant(
  of: _key('settings-legal-source'),
  matching: find.textContaining(asset),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'About opens the Terms tab, License and notices tabs work, package '
    'search narrows and clears, Russian shows TERMS.ru.md'
    '${E2eAgent.current.skipStdioProcessNote}',
    skip: E2eAgent.current.skipStdioProcess,
    (tester) async {
      await tester.pumpWidget(E2eAgent.current.bootstrap());
      await _settle(tester);

      // «General» → «About» → «Terms of use».
      await _openSettings(tester, 'general');
      await _pressAbout(tester, 'settings-general-about-terms');
      expect(_key('settings-legal'), findsOneWidget);
      expect(_source('assets/legal/TERMS.md'), findsOneWidget);

      // «License» и «Third-party notices».
      await _pickTab(tester, 'license');
      expect(_key('settings-legal-license-text'), findsOneWidget);
      expect(find.textContaining('MIT License'), findsWidgets);
      await _pickTab(tester, 'third-party-notices');
      expect(_key('settings-legal-notices-records'), findsOneWidget);
      expect(_key('settings-legal-packages-count'), findsOneWidget);

      // Поиск `flutter`: `M of N packages`, затем пустой результат и очистка.
      await tester.ensureVisible(_key('settings-legal-packages-search'));
      await tester.enterText(_key('settings-legal-packages-search'), 'flutter');
      await _settle(tester);
      expect(
        find.descendant(
          of: _key('settings-legal-packages-count'),
          matching: _textMatching(RegExp(r'^\d+ of \d+ packages?$')),
        ),
        findsOneWidget,
      );
      await tester.enterText(_key('settings-legal-packages-search'), 'reqwest');
      await _settle(tester);
      expect(_key('settings-legal-packages-empty'), findsOneWidget);
      expect(find.text('No packages match'), findsOneWidget);
      await tester.tap(_key('settings-legal-packages-empty-clear'));
      await _settle(tester);
      expect(_key('settings-legal-packages-empty'), findsNothing);
      expect(
        find.descendant(
          of: _key('settings-legal-packages-count'),
          matching: _textMatching(RegExp(r'^\d+ packages?$')),
        ),
        findsOneWidget,
      );

      // Русский интерфейс: вкладка «Terms of use» показывает `TERMS.ru.md`.
      await _openSettings(tester, 'general');
      await tester.ensureVisible(_key('settings-language-ru'));
      await tester.tap(_key('settings-language-ru'));
      await _settle(tester);
      await _pressAbout(tester, 'settings-general-about-terms');
      expect(_source('assets/legal/TERMS.ru.md'), findsOneWidget);
    },
  );
}
