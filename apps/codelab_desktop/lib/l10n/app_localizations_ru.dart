// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get settingsPageGeneralTitle => 'Общие';

  @override
  String get settingsLanguageTitle => 'Язык';

  @override
  String get settingsLanguageSystem => 'Как в системе';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageSaveFailed =>
      'Не удалось сохранить язык. После перезапуска CodeLab будет использовать прежний язык.';

  @override
  String get settingsGroupAgent => 'Агент';

  @override
  String get settingsGroupApp => 'Приложение';

  @override
  String get settingsPageConnectionTitle => 'Подключение';

  @override
  String get settingsPageProvidersTitle => 'Провайдеры';

  @override
  String get settingsPageMcpServersTitle => 'MCP-серверы';

  @override
  String get settingsPageAgentsAndModesTitle => 'Агенты и режимы';

  @override
  String get settingsPagePermissionsAndToolsTitle => 'Разрешения и инструменты';

  @override
  String get settingsPageRedactionTitle => 'Маскирование';

  @override
  String get settingsPageSkillsAndExtensionsTitle => 'Навыки и расширения';

  @override
  String get settingsPageCodeAndWebTitle => 'Код и веб';

  @override
  String get settingsPageAppearanceTitle => 'Оформление';

  @override
  String get settingsPageKeyboardTitle => 'Клавиатура';

  @override
  String get settingsGeneralSectionInterface => 'Интерфейс';
}
