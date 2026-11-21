import 'package:codelab_setup/codelab_setup.dart' show EditableSettings;

import '../../settings/application/provider_wizard_cubit.dart'
    show ProviderWizardCubit;

/// Открывает мастер провайдера для шага «Choose a model» (design.md change
/// `add-app-onboarding`, D8).
///
/// Почему порт: сессию настроек и автомат собирает composition root (SETUP-9),
/// а экран onboarding знает только, какой пресет выбран.
///
/// Для чего: возвращает Cubit мастера с целью `user`, неснимаемым «Make
/// default» и `entry: onboarding`; сам отправляет автомату
/// `PresetChosen(presetId)`, поэтому диалог начинается с «Base URL». Мастер
/// открывается по [access] — тому же `EditableSettings`, по которому зонд
/// прочитал факты шага (`OnboardingFacts.access`), поэтому для stdio-профиля
/// `codelab-agent` со своим `CODELAB_HOME` шаг проверяет и мастер пишет один и
/// тот же конфиг (design.md D8, ревью 2026-11-21, п. 2). `null` — настройки
/// недоступны (нет `CODELAB_HOME`, конфиг не читается).
///
/// Как использовать: экран вызывает `await open(presetId: id, access: …)`
/// между `OnboardingCubit.wizardStarted` и `wizardEnded`, показывает диалог, передаёт итог `Done` в `OnboardingCubit.providerSaved` и закрывает
/// Cubit мастера (как `addProviderFromBanner`).
typedef OnboardingWizardOpener =
    Future<ProviderWizardCubit?> Function({
      required String presetId,
      required EditableSettings access,
    });
