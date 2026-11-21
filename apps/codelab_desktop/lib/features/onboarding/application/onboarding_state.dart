import 'onboarding_probe.dart';

/// Шаг onboarding в порядке показа (design.md change `add-app-onboarding`,
/// D4).
enum OnboardingStep { welcome, permissions, model, privacy }

/// Состояние чтения фактов (D6): закрытая иерархия вместо набора флагов
/// (AGENTS.md §8).
sealed class OnboardingFactsState {
  const OnboardingFactsState();
}

/// Факты ещё читаются.
final class FactsLoading extends OnboardingFactsState {
  const FactsLoading();
}

/// Факты прочитаны.
final class FactsLoaded extends OnboardingFactsState {
  const FactsLoaded(this.facts);

  final OnboardingFacts facts;
}

/// Чтение завершилось сбоем или таймаутом; тексты шагов строятся по
/// умолчаниям (D7, D9).
final class FactsUnavailable extends OnboardingFactsState {
  const FactsUnavailable();
}

/// Почему шаг «Choose a model» пропущен (D4).
enum ModelSkipReason { ready, external }

/// Пояснение на шаге «Choose a model» (D8).
enum ModelNotice { none, keyMissing, configBroken, unavailable }

/// Где хранится ключ сохранённого провайдера (D8, сводка `Saved`).
///
/// Значения ключа здесь нет (SETUP-1): только имя секрета и бэкенд либо имя
/// переменной.
sealed class OnboardingKeyStorage {
  const OnboardingKeyStorage();
}

final class SecretKeyStorage extends OnboardingKeyStorage {
  const SecretKeyStorage({required this.name, required this.backendId});

  final String name;
  final String backendId;

  @override
  bool operator ==(Object other) =>
      other is SecretKeyStorage &&
      other.name == name &&
      other.backendId == backendId;

  @override
  int get hashCode => Object.hash(name, backendId);
}

final class EnvKeyStorage extends OnboardingKeyStorage {
  const EnvKeyStorage(this.variable);

  final String variable;

  @override
  bool operator ==(Object other) =>
      other is EnvKeyStorage && other.variable == variable;

  @override
  int get hashCode => variable.hashCode;
}

final class NoKeyStorage extends OnboardingKeyStorage {
  const NoKeyStorage();

  @override
  bool operator ==(Object other) => other is NoKeyStorage;

  @override
  int get hashCode => (NoKeyStorage).hashCode;
}

/// Сводка сохранённого провайдера для шага `Saved` (артборд 07c.5).
final class OnboardingSavedSummary {
  const OnboardingSavedSummary({
    required this.providerId,
    required this.model,
    required this.keyStorage,
  });

  final String providerId;

  /// Модель по умолчанию `<id>/<model>`.
  final String model;
  final OnboardingKeyStorage keyStorage;

  @override
  bool operator ==(Object other) =>
      other is OnboardingSavedSummary &&
      other.providerId == providerId &&
      other.model == model &&
      other.keyStorage == keyStorage;

  @override
  int get hashCode => Object.hash(providerId, model, keyStorage);
}

/// Фаза мастера провайдера на шаге «Choose a model» (design.md change
/// `add-app-onboarding`, D8, ревью 2026-11-21, п. 6).
///
/// Почему поле шага, а не отдельный флаг состояния: фаза имеет смысл только у
/// `Choose` и `Saved`, и набора независимых флагов быть не должно (AGENTS.md
/// §8). `active` — мастер открывается или открыт: навигация шага блокируется.
enum ModelWizard { idle, active }

/// Шаг «Choose a model» (D4): `Pending` — готовность ещё не известна.
sealed class OnboardingModelStep {
  const OnboardingModelStep();
}

final class ModelPending extends OnboardingModelStep {
  const ModelPending();
}

final class ModelSkipped extends OnboardingModelStep {
  const ModelSkipped(this.reason);

  final ModelSkipReason reason;

  @override
  bool operator ==(Object other) =>
      other is ModelSkipped && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

final class ModelChoose extends OnboardingModelStep {
  const ModelChoose(this.notice, {this.wizard = ModelWizard.idle});

  final ModelNotice notice;
  final ModelWizard wizard;

  @override
  bool operator ==(Object other) =>
      other is ModelChoose && other.notice == notice && other.wizard == wizard;

  @override
  int get hashCode => Object.hash(notice, wizard);
}

final class ModelSaved extends OnboardingModelStep {
  const ModelSaved(this.summary, {this.wizard = ModelWizard.idle});

  final OnboardingSavedSummary summary;
  final ModelWizard wizard;

  @override
  bool operator ==(Object other) =>
      other is ModelSaved && other.summary == summary && other.wizard == wizard;

  @override
  int get hashCode => Object.hash(summary, wizard);
}

/// Состояние onboarding (D4).
///
/// Как использовать: читает `OnboardingScreen`; меняет только
/// `OnboardingCubit`. [finishing] — запись флага идёт, повторное нажатие
/// «Start using CodeLab» игнорируется (D5).
final class OnboardingState {
  const OnboardingState({
    this.step = OnboardingStep.welcome,
    this.facts = const FactsLoading(),
    this.model = const ModelPending(),
    this.finishing = false,
  });

  final OnboardingStep step;
  final OnboardingFactsState facts;
  final OnboardingModelStep model;
  final bool finishing;

  OnboardingState copyWith({
    OnboardingStep? step,
    OnboardingFactsState? facts,
    OnboardingModelStep? model,
    bool? finishing,
  }) => OnboardingState(
    step: step ?? this.step,
    facts: facts ?? this.facts,
    model: model ?? this.model,
    finishing: finishing ?? this.finishing,
  );

  @override
  String toString() =>
      'OnboardingState(${step.name}, ${facts.runtimeType}, '
      '${model.runtimeType}, finishing: $finishing)';
}
