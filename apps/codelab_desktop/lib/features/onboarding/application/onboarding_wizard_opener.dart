import '../../settings/application/provider_wizard_cubit.dart'
    show ProviderWizardCubit;

/// Открывает мастер провайдера для шага «Choose a model» (design.md change
/// `add-app-onboarding`, D8).
///
/// Почему порт: сессию настроек и автомат собирает composition root (SETUP-9),
/// а экран onboarding знает только, какой пресет выбран.
///
/// Для чего: возвращает Cubit мастера встроенного профиля с целью `user`,
/// неснимаемым «Make default» и `entry: onboarding`; сам отправляет автомату
/// `PresetChosen(presetId)`, поэтому диалог начинается с «Base URL». `null` —
/// настройки недоступны (нет `CODELAB_HOME`, конфиг не читается).
///
/// Как использовать: экран вызывает `await open(presetId: id)`, показывает
/// диалог, передаёт итог `Done` в `OnboardingCubit.providerSaved` и закрывает
/// Cubit мастера (как `addProviderFromBanner`).
typedef OnboardingWizardOpener =
    Future<ProviderWizardCubit?> Function({required String presetId});
