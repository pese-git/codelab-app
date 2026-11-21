import 'dart:io' show Platform;

import 'package:codelab_client_core/codelab_client_core.dart'
    show InMemoryThemeLibrary, ProfileSecrets, ThemeLibrary;
import 'package:codelab_client_io/codelab_client_io.dart' show IoThemeLibrary;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app_scope.dart';
import 'app/appearance/app_appearance_start.dart';
import 'app/language/app_language_start.dart';
import 'core/platform/app_appearance_preferences.dart';
import 'core/platform/system_accent_source.dart';
import 'core/platform/app_language_preferences.dart';
import 'core/platform/onboarding_preferences.dart';
import 'app/onboarding/onboarding_start.dart';
import 'app/client_profile_secrets.dart';
import 'app/codelab_app_widget.dart';
import 'app/connection_environment.dart';
import 'app/embedded_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDirectory = await getApplicationSupportDirectory();
  final logDirectoryPath = p.join(supportDirectory.path, 'logs');

  // Хранилище секретов агента открывается до сборки scope: `ProfileSecrets.backend`
  // синхронный (design.md change `add-provider-setup-ui`, D13).
  // Переоткрывается при каждом открытии диалога и страницы настроек.
  Future<ProfileSecrets> openSecrets() => openProfileSecrets(
    environment: ConnectionEnvironment.of(Platform.environment),
    logger: CodeLabEmbeddedLogger(),
  );
  final profileSecrets = await openSecrets();

  // Язык читается до `runApp`: первый кадр сразу на нужном языке, без мигания
  // английского (add-desktop-localization, D2). `load` не бросает; журнал здесь
  // ещё не настроен, поэтому диагностику чтения несёт шов и пишет её
  // `CodeLabLanguageModule` (D13).
  final language = AppLanguageStart.fromLoad(
    await const SharedPreferencesAppLanguagePreferences().load(),
    WidgetsBinding.instance.platformDispatcher.locales,
  );

  // Флаг onboarding читается до `runApp` (add-app-onboarding, D2, D3): первый
  // кадр сразу показывает нужный экран, без мигания рабочего места и без
  // раннего старта агента. `load` не бросает; события пишет
  // `CodeLabOnboardingModule` после настройки журнала.
  final onboarding = OnboardingStart.fromLoad(
    await const SharedPreferencesOnboardingPreferences().load(),
  );

  // Оформление читается до `runApp`, как язык: первый кадр сразу в итоговой
  // теме, без мигания (`add-app-appearance-page`, D13). Документ, файлы тем двух
  // режимов (по 1 с на файл) и первое чтение системного акцента (1 с) идут здесь;
  // `load` и `resolve` не бросают, диагностику пишет `CodeLabAppearanceModule`.
  final environment = ConnectionEnvironment.of(Platform.environment);
  final codelabHome = environment.codelabHome;
  // Недопустимый `CODELAB_HOME` не мешает запуску: пользовательских тем нет.
  final ThemeLibrary themeLibrary = codelabHome == null
      ? InMemoryThemeLibrary()
      : IoThemeLibrary(home: codelabHome);
  final accentSource = await SystemThemeAccentSource.start();
  final appearance = await AppAppearanceStart.resolve(
    load: await const SharedPreferencesAppAppearancePreferences().load(),
    library: themeLibrary,
    accentSource: accentSource,
  );

  runApp(
    CodeLabBootstrap(
      logDirectoryPath: logDirectoryPath,
      profileSecrets: profileSecrets,
      profileSecretsOpener: openSecrets,
      language: language,
      onboarding: onboarding,
      appearance: appearance,
      systemAccentSource: accentSource,
      themeLibrary: themeLibrary,
      child: const CodeLabApp(),
    ),
  );
}
