import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/settings/application/settings_search_index.dart';
import 'package:codelab_desktop/features/settings/presentation/settings_titles.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';

/// Поиск настроек по английским заголовкам (язык тестов по умолчанию — `en`).
///
/// Почему: заголовок страницы зависит от языка и приходит в
/// `SettingsSearchIndex.search` функцией `titleOf`
/// (`add-desktop-localization`, D5, п. 8); тестам поиска нужен только `en`.
List<SettingsPage> searchSettings(
  Iterable<SettingsPage> visible,
  String query,
) => SettingsSearchIndex.search(
  visible,
  query,
  titlesOf: (page) => [settingsPageTitleOf(AppLocalizationsEn(), page)],
);
