import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// Короткий доступ к каталогу интерфейса: `context.l10n.settingsLanguageTitle`.
///
/// Почему расширение: текст виджета берётся в `build` через `Localizations`,
/// поэтому смена языка пересобирает его без подписок (add-desktop-localization,
/// D5, вид «текст виджета»). Как использовать: только в presentation; Cubit-ы
/// получают язык портом `AppStrings`, а не `BuildContext`.
extension AppL10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
