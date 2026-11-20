import '../../core/platform/onboarding_preferences.dart';

/// Решение «показывать ли onboarding», которое `main` передаёт в composition
/// root (design.md change `add-app-onboarding`, D3).
///
/// Почему отдельный тип: флаг читается до `runApp`, когда журнал ещё не
/// настроен, поэтому шов несёт только решение и диагностику чтения; события
/// `onboarding.shown`, `onboarding.flag_invalid`, `onboarding.flag_unreadable`
/// пишет `CodeLabOnboardingModule` после настройки журнала, как
/// `app.locale_resolved` (`add-desktop-localization`, D13).
///
/// Как использовать: `OnboardingStart.fromLoad(await prefs.load())` в `main`.
/// Без шва (тесты и хосты без onboarding) onboarding не показывается, поэтому
/// прежние тесты рабочего места не меняются.
final class OnboardingStart {
  const OnboardingStart({
    required this.show,
    this.storedValueInvalid = false,
    this.readFailure,
  });

  /// Результат чтения флага → решение: показ только при отсутствии ключа.
  factory OnboardingStart.fromLoad(OnboardingLoad load) => OnboardingStart(
    show: !load.done,
    storedValueInvalid: load.storedValueInvalid,
    readFailure: load.readFailure,
  );

  /// Показать onboarding вместо рабочего места.
  final bool show;

  /// В ключе значение не `true` (событие `onboarding.flag_invalid`).
  final bool storedValueInvalid;

  /// Имя типа ошибки чтения хранилища (событие `onboarding.flag_unreadable`).
  final String? readFailure;
}
