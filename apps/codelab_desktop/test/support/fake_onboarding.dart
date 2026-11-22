// Двойники портов onboarding для widget-тестов (change `add-app-onboarding`,
// задачи 3.3, 3.7; design.md D2, D6).
//
// Почему двойники: чтение конфига и хранилища секретов проверяет тест адаптера
// (`onboarding_probe_test.dart`), а экран и composition root отвечают только за
// то, что показать и что вызвать. Файлов, сети и часов здесь нет.

import 'dart:async';

import 'package:codelab_desktop/core/platform/onboarding_preferences.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_probe.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_project_port.dart';
import 'package:codelab_setup/codelab_setup.dart';

/// Подпись каталога логов app, которую composition root передаёт экрану
/// (`OnboardingScreen.appLogsLabel`; ревью 2026-11-21, п. 4).
const fakeLogsLabel = '~/Library/Application Support/CodeLab/logs';

/// Факты настраиваемого агента: готовность [readiness], бэкенд [backend].
OnboardingFacts onboardingFacts(
  ProviderReadiness readiness, {
  String backend = 'env',
  String mode = 'standard',
}) => OnboardingFacts(
  readiness: readiness,
  access: const EditableSettings(ConfigPaths(codelabHome: '/home/u/.codelab')),
  backendId: backend,
  backendWritable: backend != 'env',
  mode: mode,
  homeLabel: '~/.codelab',
);

/// Факты внешнего профиля по умолчанию.
const onboardingExternalFacts = OnboardingFacts.external();

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

/// Порт шага «Open a project» без поведения: выбор не принимается, проекта
/// нет (change `add-onboarding-project-step`, D5). Тесты шага
/// подменяют ответы своим двойником.
final class FakeOnboardingProjectPort implements OnboardingProjectPort {
  @override
  Future<String?> pickFolder() async => null;

  @override
  Future<String?> openDropped(List<String?> paths) async => null;

  @override
  Future<String?> openRecent(String path) async => null;

  @override
  String? selectedProject;
}

/// Порт флага: запись считается; [failure] имитирует сбой записи, [gate]
/// держит запись, пока тест не завершит затвор.
final class FakeOnboardingPreferences implements OnboardingPreferences {
  var marked = 0;
  Object? failure;
  Completer<void>? gate;

  @override
  Future<OnboardingLoad> load() async => const OnboardingLoad(false);

  @override
  Future<void> markDone() async {
    marked++;
    await gate?.future;
    if (failure != null) {
      throw failure!;
    }
  }
}
