import 'package:codelab_setup/codelab_setup.dart' show ProviderReadiness;

/// Факты, которые нужны шагам onboarding (design.md change
/// `add-app-onboarding`, D6).
///
/// Почему отдельный тип: шаги 2–4 показывают готовность провайдера, действующий
/// режим, бэкенд секретов и подписи путей, а читаются они из файлов и
/// хранилища секретов, куда application-слой не ходит (SETUP-9).
///
/// Как использовать: адаптер `SetupOnboardingProbe` собирает значение один раз;
/// [OnboardingFacts.external] — профиль по умолчанию не настраиваемый агент
/// (конфиг не читался, шаг «Choose a model» пропускается, режим — D7).
/// Значений ключей в фактах нет (SETUP-1).
final class OnboardingFacts {
  const OnboardingFacts({
    required ProviderReadiness this.readiness,
    required String this.backendId,
    required bool this.backendWritable,
    required String this.mode,
    required String this.homeLabel,
    required this.logsLabel,
  });

  /// Внешний профиль по умолчанию: известны только подписи каталога логов.
  const OnboardingFacts.external({required this.logsLabel})
    : readiness = null,
      backendId = null,
      backendWritable = null,
      mode = null,
      homeLabel = null;

  /// Готовность провайдера; `null` у внешнего профиля.
  final ProviderReadiness? readiness;

  /// `SecretBackendInfo.id` (`env`, `file`, …); `null` у внешнего профиля.
  final String? backendId;
  final bool? backendWritable;

  /// Основной id режима новой сессии (`standard`, `bypass`, …).
  final String? mode;

  /// Каталог конфига и сессий с `~` вместо домашнего каталога.
  final String? homeLabel;

  /// Каталог логов app с `~`.
  final String logsLabel;

  bool get isExternal => readiness == null;
}

/// Порт чтения фактов onboarding (D6).
///
/// Почему порт: `codelab_setup/io.dart` пускается только в `lib/app/`
/// (SETUP-9, D15), поэтому `OnboardingCubit` получает факты через него.
///
/// Как использовать: `OnboardingCubit` вызывает `read()` один раз при
/// создании, с таймаутом (`kOnboardingFactsTimeout`); реализация может
/// бросать, Cubit превращает сбой в `Choose(unavailable)`.
abstract interface class OnboardingProbe {
  Future<OnboardingFacts> read();
}
