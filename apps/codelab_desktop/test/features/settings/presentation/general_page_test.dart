// Красные тесты страницы «General» (задача 1.9 change
// `add-desktop-localization`; spec app-settings «Язык интерфейса app»:
// «Смена языка применяется сразу на странице настроек» — критерий D-19,
// «Сбой записи», «Возврат к английскому»; design.md D2, D9).
//
// Страница читает и вызывает `AppLanguageCubit`, своего Cubit-а у неё нет.
// Тесты идут через настоящее дерево app (`CodeLabApp`): язык должен
// переключаться без перезапуска и без пересоздания `FluentApp`.

import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/language/app_language_cubit.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/l10n_mix.dart';
import '../../../support/test_app_scope.dart';

/// Порт хранения, у которого запись всегда падает.
final class _FailingPreferences implements AppLanguagePreferences {
  @override
  Future<AppLanguagePreference> load() async => AppLanguagePreference.system;

  @override
  Future<void> save(AppLanguagePreference preference) =>
      Future.error(StateError('disk is read-only: /secret/path'));
}

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1400, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  /// Открывает страницу «General» в настоящем дереве app.
  Future<CodeLabTestBinding> openGeneral(
    WidgetTester tester, {
    AppLanguagePreferences? languagePreferences,
  }) async {
    final binding = CodeLabTestBinding(
      project: '/workspace',
      settingsPages: const SettingsPages(
        available: {SettingsPage.connection, SettingsPage.general},
      ),
      languagePreferences: languagePreferences,
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await binding.scope.resolve<NavigationCubit>().openSettings(
      page: SettingsPage.general,
      source: SettingsOpenSource.sidebar,
    );
    await tester.pumpAndSettle();
    return binding;
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  Future<void> choose(WidgetTester tester, String optionKey) async {
    await tester.tap(key(optionKey));
    await tester.pumpAndSettle();
  }

  testWidgets('показывает строку Language и три значения с эндонимами', (
    tester,
  ) async {
    await openGeneral(tester);

    expect(key('settings-general-language'), findsOneWidget);
    expect(find.text(en.settingsLanguageTitle), findsWidgets);
    for (final option in ['system', 'en', 'ru']) {
      expect(key('settings-language-$option'), findsOneWidget);
    }
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    expect(find.text(en.settingsLanguageSystem), findsOneWidget);
  });

  testWidgets('выбор Русский без перезапуска переводит страницу, навигацию и '
      'строку Language (критерий D-19)', (tester) async {
    final binding = await openGeneral(tester);
    final cubit = binding.scope.resolve<AppLanguageCubit>();

    await choose(tester, 'settings-language-ru');

    expect(cubit.state.locale, const Locale('ru'));
    // Английские подписи ушли, русские на месте.
    expect(find.text(en.settingsPageGeneralTitle), findsNothing);
    expect(find.text(en.settingsLanguageTitle), findsNothing);
    expect(find.text(ru.settingsPageGeneralTitle), findsWidgets);
    expect(find.text(ru.settingsLanguageTitle), findsWidgets);
    expect(find.text(ru.settingsLanguageSystem), findsOneWidget);
    // Эндонимы не переводятся.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    // Навигация настроек: пункты и заголовки групп пересобраны.
    expect(find.text('Connection'), findsNothing);
    expect(find.text('Agent'), findsNothing);
    expect(find.text('App'), findsNothing);
    await expectNoStaleLanguage(tester, from: en, to: ru);
  });

  testWidgets('English возвращает английский', (tester) async {
    await openGeneral(tester);

    await choose(tester, 'settings-language-ru');
    await choose(tester, 'settings-language-en');

    expect(find.text(en.settingsPageGeneralTitle), findsWidgets);
    expect(find.text(en.settingsLanguageTitle), findsWidgets);
    expect(find.text(ru.settingsLanguageTitle), findsNothing);
    await expectNoStaleLanguage(tester, from: ru, to: en);
  });

  testWidgets('выбор сохраняется в хранилище; System удаляет ключ', (
    tester,
  ) async {
    await openGeneral(tester);

    await choose(tester, 'settings-language-ru');
    expect(
      await const SharedPreferencesAppLanguagePreferences().load(),
      AppLanguagePreference.ru,
    );

    await choose(tester, 'settings-language-system');
    expect(
      await const SharedPreferencesAppLanguagePreferences().load(),
      AppLanguagePreference.system,
    );
  });

  testWidgets('сбой записи: язык применён, ошибка на новом языке без текста '
      'исключения', (tester) async {
    final binding = await openGeneral(
      tester,
      languagePreferences: _FailingPreferences(),
    );

    await choose(tester, 'settings-language-ru');

    expect(
      binding.scope.resolve<AppLanguageCubit>().state.locale,
      const Locale('ru'),
    );
    expect(find.text(ru.settingsLanguageSaveFailed), findsOneWidget);
    expect(find.text(en.settingsLanguageSaveFailed), findsNothing);
    expect(find.textContaining('/secret/path'), findsNothing);
    expect(find.textContaining('read-only'), findsNothing);
    await expectNoStaleLanguage(tester, from: en, to: ru);
  });
}
