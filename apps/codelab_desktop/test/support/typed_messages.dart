import 'package:codelab_desktop/features/settings/application/add_profile_cubit.dart';
import 'package:codelab_desktop/features/settings/application/provider_settings_cubit.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';

/// Английский текст типизированных разовых сообщений Cubit-ов настроек.
///
/// Почему: после `add-desktop-localization` (D5) состояния хранят типизированные
/// сообщения, а текст строит presentation по `context.l10n`. Прежние Cubit-тесты
/// проверяют английские строки, поэтому они читают текст через эти расширения,
/// построенные тем же кодом, что и экран (`providerMessageText`,
/// `addProfileFailureText`, `addProfilePlaintextText`) на каталоге `en`.
///
/// Как использовать: импортировать файл и читать `banner.text`,
/// `failed.message`, `confirming.message` как раньше.
extension ProviderBannerText on ProviderBanner {
  String get text => providerMessageText(AppLocalizationsEn(), message);
}

extension SaveFailedText on SaveFailed {
  String get message {
    final l10n = AppLocalizationsEn();
    final detail = addProfileFailureDetail(failure);
    return [addProfileFailureText(l10n, failure), ?detail].join(' ');
  }
}

extension ConfirmingPlaintextText on ConfirmingPlaintext {
  String get message => addProfilePlaintextText(
    AppLocalizationsEn(),
    origin: origin,
    hasToken: hasToken,
  );
}
