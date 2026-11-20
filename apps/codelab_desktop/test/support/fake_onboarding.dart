// Двойники портов onboarding для widget-тестов (change `add-app-onboarding`,
// задачи 3.3, 3.7; design.md D2, D6).
//
// Почему двойники: чтение конфига и хранилища секретов проверяет тест адаптера
// (`onboarding_probe_test.dart`), а экран и composition root отвечают только за
// то, что показать и что вызвать. Файлов, сети и часов здесь нет.

import 'dart:async';

import 'package:codelab_desktop/core/platform/onboarding_preferences.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_probe.dart';
import 'package:codelab_setup/codelab_setup.dart';

/// Подпись каталога логов app в фактах двойника.
const fakeLogsLabel = '~/Library/Application Support/CodeLab/logs';

/// Факты настраиваемого агента: готовность [readiness], бэкенд [backend].
OnboardingFacts onboardingFacts(
  ProviderReadiness readiness, {
  String backend = 'env',
  String mode = 'standard',
}) => OnboardingFacts(
  readiness: readiness,
  backendId: backend,
  backendWritable: backend != 'env',
  mode: mode,
  homeLabel: '~/.codelab',
  logsLabel: fakeLogsLabel,
);

/// Факты внешнего профиля по умолчанию.
const onboardingExternalFacts = OnboardingFacts.external(
  logsLabel: fakeLogsLabel,
);

/// Порт фактов: готовый ответ или ошибка; `reads` — число чтений.
final class FakeOnboardingProbe implements OnboardingProbe {
  FakeOnboardingProbe(this.facts) : error = null;
  FakeOnboardingProbe.failing(Object this.error) : facts = null;

  final OnboardingFacts? facts;
  final Object? error;
  var reads = 0;

  @override
  Future<OnboardingFacts> read() {
    reads++;
    return error != null
        ? Future<OnboardingFacts>.error(error!)
        : Future.value(facts);
  }
}

/// Порт флага: запись считается; [failure] имитирует сбой записи.
final class FakeOnboardingPreferences implements OnboardingPreferences {
  var marked = 0;
  Object? failure;

  @override
  Future<OnboardingLoad> load() async => const OnboardingLoad(false);

  @override
  Future<void> markDone() async {
    marked++;
    if (failure != null) {
      throw failure!;
    }
  }
}
