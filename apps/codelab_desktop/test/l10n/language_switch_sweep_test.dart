// Итоговый прогон смены языка по всем экранам (задача 6.1 change
// `add-desktop-localization`; spec app-settings «Живое рабочее место
// пересобирается», «Страницы настроек II пересобираются при смене языка»;
// design.md D9, R1).
//
// Почему отдельный файл: тесты итераций 2–5 проверяют смену языка по одному
// экрану, у каждого свои двойники. Здесь один тест проходит ВСЕ экраны одного
// приложения: рабочее место с данными и каждую видимую страницу настроек из
// `defaultSettingsPages`, `en → ru → en`. Cubit с текстом, который забыли
// подписать на `AppStrings`, или новая страница, чей текст остаётся от
// прежнего языка, будут пойманы здесь, даже если у них нет своего теста.
//
// Как устроен: настоящий граф app (`LiveScene`), агент-двойник с ответом,
// вызовом и ожидающим одобрением, двойник настроек агента с провайдером и
// MCP-сервером. Страница выбирается тем же `NavigationCubit`, что и пользователь
// в навигации настроек. Новая страница в `defaultSettingsPages` попадает в
// прогон сама.

import 'package:codelab_desktop/app/default_settings_pages.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_provider_settings.dart';
import '../support/l10n_mix.dart';
import '../support/live_scene.dart';

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

  testWidgets('en → ru → en: рабочее место с данными и каждая страница '
      'настроек без строк прежнего языка', (tester) async {
    final store = FakeAgentConfigStore(
      user: {
        'agent': {'default_model': 'anthropic/m'},
        'providers': {
          'anthropic': providerMap(
            kind: 'anthropic',
            baseUrl: null,
            secret: 'codelab/anthropic',
          ),
        },
        'mcp': {
          'servers': [
            {
              'name': 'github',
              'type': 'http',
              'url': 'https://api.example.test/mcp/',
            },
          ],
        },
      },
    );
    final session = FakeProviderSettingsSession(
      store,
      secrets: {'codelab/anthropic': leakMarker},
    );
    final scene = await LiveScene.open(
      tester,
      providerSettingsOpener: (access, env) async => session,
    );
    await scene.newSession('s1');
    final turn = await scene.prompt('explain the repo');
    await scene.agentText('s1', 'Done. 3 files changed.');
    await scene.endTurn(turn, stopReason: 'max_tokens');
    await scene.prompt('run the tests');
    await scene.toolCall('s1', toolCallId: 'c1', title: 'Run echo hi');
    await scene.requestPermission(id: 100, sessionId: 's1', toolCallId: 'c2');
    await scene.flush();

    // Данные теста, а не подписи: id профиля встроенного агента (`default` —
    // его алиас, spec connection-profiles), id провайдера, имя MCP-сервера;
    // они совпали бы с переводимой подписью источника «default».
    const data = {'default', 'github', 'anthropic'};

    // Страница выбрана, пока ждёт `selectLanguage`: проверка до и после.
    Future<void> roundTrip(String screen) async {
      await scene.selectLanguage(AppLanguagePreference.ru);
      await expectNoStaleLanguage(tester, from: en, to: ru, ignore: data);
      expect(tester.takeException(), isNull, reason: '$screen, ru');
      await scene.selectLanguage(AppLanguagePreference.en);
      await expectNoStaleLanguage(tester, from: ru, to: en, ignore: data);
      expect(tester.takeException(), isNull, reason: '$screen, en');
    }

    await roundTrip('рабочее место');

    final navigation = scene.binding.scope.resolve<NavigationCubit>();
    await navigation.openSettings(
      page: defaultSettingsPages.visible.first,
      source: SettingsOpenSource.sidebar,
    );
    await scene.flush();
    for (final page in defaultSettingsPages.visible) {
      await navigation.selectSettingsPage(page);
      // Не `pumpAndSettle`: идущий вызов держит бесконечную анимацию.
      await scene.flush();
      await roundTrip('настройки: ${page.slug}');
    }

    await scene.close();
  });
}
