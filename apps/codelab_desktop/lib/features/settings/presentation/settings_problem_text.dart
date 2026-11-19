import '../../../l10n/app_localizations.dart';
import '../application/settings_notices.dart';

/// Текст одной проблемы списка нечитаемого конфига на языке интерфейса.
///
/// Почему: списки `Unreadable` трёх страниц настроек смешивают фразы app
/// (переводятся) с текстами загрузчика ядра агента (показываются как есть,
/// под переведённым заголовком, D6). Тип проблемы хранит Cubit, а здесь — одна
/// функция для всех страниц (D5, «Уточнение итерации 5»).
String settingsProblemText(AppLocalizations l10n, SettingsProblem problem) =>
    switch (problem) {
      AppSettingsProblem(:final kind) => switch (kind) {
        AppSettingsProblemKind.cannotReadSettings =>
          l10n.providersProblemCannotReadSettings,
        AppSettingsProblemKind.homeUnavailable => l10n.providersProblemNoHome,
        AppSettingsProblemKind.userConfigUnreadable =>
          l10n.providersProblemUserConfig,
        AppSettingsProblemKind.cannotReadExtensions =>
          l10n.settingsProblemCannotReadExtensions,
      },
      LoaderSettingsProblem(:final text) => text,
    };

/// Проблемы построчно для содержимого InfoBar.
String settingsProblemsText(
  AppLocalizations l10n,
  Iterable<SettingsProblem> problems,
) => problems.map((p) => settingsProblemText(l10n, p)).join('\n');
