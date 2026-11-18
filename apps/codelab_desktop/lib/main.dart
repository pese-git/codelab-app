import 'dart:io' show Platform;

import 'package:codelab_client_core/codelab_client_core.dart'
    show ProfileSecrets;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app_scope.dart';
import 'app/language/app_language_start.dart';
import 'core/platform/app_language_preferences.dart';
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

  runApp(
    CodeLabBootstrap(
      logDirectoryPath: logDirectoryPath,
      profileSecrets: profileSecrets,
      profileSecretsOpener: openSecrets,
      language: language,
      child: const CodeLabApp(),
    ),
  );
}
