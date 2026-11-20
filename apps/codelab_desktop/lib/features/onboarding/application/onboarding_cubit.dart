import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/onboarding_preferences.dart';
import 'onboarding_probe.dart';
import 'onboarding_state.dart';

/// Таймаут чтения фактов: время шага `stores` сторожа запуска (design.md
/// change `add-app-onboarding`, D6).
const kOnboardingFactsTimeout = Duration(seconds: 5);

/// Владелец шага onboarding и данных шагов.
///
/// Почему: onboarding — однократный экран со своим автоматом переходов (D4);
/// политика («пропустить шаг модели», «не запирать при сбое записи флага»)
/// принадлежит application, а не виджетам (AGENTS.md §7, §10).
///
/// Для чего: читает факты один раз при создании с таймаутом (D6), ведёт шаги
/// по таблице D4, принимает итог мастера провайдера, завершает onboarding:
/// пишет флаг и зовёт [onFinished] (D5). События — D13, без путей, имён
/// секретов, адресов и текстов исключений.
///
/// Как использовать: composition root создаёт один экземпляр на показ
/// onboarding; [onFinished] — `NavigationCubit.finishOnboarding`. Кнопки
/// экрана вызывают [next], [back], [setUpLater], [finish]; после диалога
/// мастера экран передаёт `Done` в [providerSaved]. Cubit закрывает владелец.
class OnboardingCubit extends Cubit<OnboardingState> {
  OnboardingCubit({
    required OnboardingProbe probe,
    required OnboardingPreferences preferences,
    required void Function() onFinished,
    Duration factsTimeout = kOnboardingFactsTimeout,
    Logger? logger,
  }) : _probe = probe,
       _preferences = preferences,
       _onFinished = onFinished,
       _logger = logger,
       super(const OnboardingState()) {
    _logger?.debug('onboarding.step_shown', context: {'step': 'welcome'});
    _loadFacts(factsTimeout);
  }

  final OnboardingProbe _probe;
  final OnboardingPreferences _preferences;
  final void Function() _onFinished;
  final Logger? _logger;

  final _factsDone = Completer<void>();
  final _clock = Stopwatch()..start();
  Timer? _timeout;
  var _factsResolved = false;
  var _waitingFacts = false;

  void _loadFacts(Duration timeout) {
    _timeout = Timer(timeout, () {
      if (!_factsResolved && !isClosed) {
        _resolveUnavailable({'timeout': true});
      }
    });
    _probe.read().then(
      (facts) {
        if (isClosed) {
          return;
        }
        if (_factsResolved) {
          // Поздний итог после таймаута шаг не меняет (D6, CON-002).
          _logger?.debug(
            'onboarding.facts_late',
            context: {'duration_ms': _clock.elapsedMilliseconds},
          );
          return;
        }
        _timeout?.cancel();
        _applyFacts(facts);
      },
      onError: (Object error) {
        if (isClosed || _factsResolved) {
          return;
        }
        _timeout?.cancel();
        // Только тип ошибки: в тексте бывают пути (D13).
        _resolveUnavailable({'error_type': error.runtimeType.toString()});
      },
    );
  }

  void _resolveUnavailable(Map<String, Object?> context) {
    _factsResolved = true;
    _logger?.warning('onboarding.facts_unavailable', context: context);
    emit(
      state.copyWith(
        facts: const FactsUnavailable(),
        model: const ModelChoose(ModelNotice.unavailable),
      ),
    );
    _factsDone.complete();
  }

  void _applyFacts(OnboardingFacts facts) {
    _factsResolved = true;
    final readiness = facts.readiness;
    _logger?.debug(
      'onboarding.facts_loaded',
      context: {
        'access': facts.isExternal ? 'external' : 'editable',
        if (readiness != null) 'readiness': _readinessName(readiness),
        if (facts.backendId != null) 'backend': facts.backendId,
        'duration_ms': _clock.elapsedMilliseconds,
      },
    );
    final model = switch (readiness) {
      null => const ModelSkipped(ModelSkipReason.external),
      ProviderReady() => const ModelSkipped(ModelSkipReason.ready),
      NoProviderConfigured() => const ModelChoose(ModelNotice.none),
      ProviderKeyMissing() => const ModelChoose(ModelNotice.keyMissing),
      ConfigBroken() => const ModelChoose(ModelNotice.configBroken),
    };
    if (model case ModelSkipped(:final reason)) {
      _logger?.info(
        'onboarding.model_step_skipped',
        context: {'reason': reason.name},
      );
    }
    emit(state.copyWith(facts: FactsLoaded(facts), model: model));
    _factsDone.complete();
  }

  static String _readinessName(ProviderReadiness readiness) =>
      switch (readiness) {
        ProviderReady() => 'ready',
        NoProviderConfigured() => 'no_provider',
        ProviderKeyMissing() => 'key_missing',
        ConfigBroken() => 'config_broken',
      };

  bool get _modelSkipped => state.model is ModelSkipped;

  void _show(OnboardingStep step) {
    emit(state.copyWith(step: step));
    _logger?.debug('onboarding.step_shown', context: {'step': step.name});
  }

  /// «Next»: переходы D4. На шаге «Permissions» при неизвестной готовности
  /// ждёт итога чтения (не дольше таймаута); повторное нажатие в ожидании
  /// игнорируется.
  Future<void> next() async {
    switch (state.step) {
      case OnboardingStep.welcome:
        _show(OnboardingStep.permissions);
      case OnboardingStep.permissions:
        if (_waitingFacts) {
          return;
        }
        if (!_factsDone.isCompleted) {
          _waitingFacts = true;
          await _factsDone.future;
          _waitingFacts = false;
          if (isClosed || state.step != OnboardingStep.permissions) {
            return;
          }
        }
        _show(_modelSkipped ? OnboardingStep.privacy : OnboardingStep.model);
      case OnboardingStep.model:
        if (state.model is ModelSaved) {
          _show(OnboardingStep.privacy);
        }
      case OnboardingStep.privacy:
        break;
    }
  }

  /// «Back»: на «Privacy» ведёт на «Choose a model», если шаг не пропущен.
  void back() {
    switch (state.step) {
      case OnboardingStep.welcome:
        break;
      case OnboardingStep.permissions:
        _show(OnboardingStep.welcome);
      case OnboardingStep.model:
        _show(OnboardingStep.permissions);
      case OnboardingStep.privacy:
        _show(
          _modelSkipped ? OnboardingStep.permissions : OnboardingStep.model,
        );
    }
  }

  /// «Set up later» (Q3, D8): на «Privacy» без записи; доступна, пока
  /// провайдер не сохранён.
  void setUpLater() {
    if (state.step != OnboardingStep.model || state.model is! ModelChoose) {
      return;
    }
    _show(OnboardingStep.privacy);
  }

  /// Принимает `Done` мастера провайдера: шаг переходит в `Saved` (D8).
  ///
  /// Игнорируется при `configBroken` и `unavailable`: мастер там не
  /// открывается. Значения ключа в сводку не попадает (SETUP-1).
  void providerSaved(Done done) {
    final model = state.model;
    final loaded = state.facts;
    final allowed =
        state.step == OnboardingStep.model &&
        loaded is FactsLoaded &&
        (model is ModelSaved ||
            model is ModelChoose &&
                (model.notice == ModelNotice.none ||
                    model.notice == ModelNotice.keyMissing));
    if (!allowed) {
      return;
    }
    final plan = done.plan;
    final storage = switch (plan.key) {
      UseEnvVar(:final name) => EnvKeyStorage(name),
      NoKey() => const NoKeyStorage(),
      StoreSecret() || KeepStoredSecret() =>
        plan.secretName == null
            ? const NoKeyStorage()
            : SecretKeyStorage(
                name: plan.secretName!,
                backendId: loaded.facts.backendId ?? '',
              ),
    };
    emit(
      state.copyWith(
        model: ModelSaved(
          OnboardingSavedSummary(
            providerId: plan.providerId,
            model: '${plan.providerId}/${plan.model.id}',
            keyStorage: storage,
          ),
        ),
      ),
    );
    _logger?.info('onboarding.model_saved');
  }

  /// «Start using CodeLab» (D5): пишет флаг и зовёт `onFinished`.
  ///
  /// Сбой записи не запирает пользователя: onboarding покажется при
  /// следующем запуске. Повторный вызов во время записи игнорируется.
  Future<void> finish() async {
    if (state.step != OnboardingStep.privacy || state.finishing) {
      return;
    }
    emit(state.copyWith(finishing: true));
    try {
      await _preferences.markDone();
    } on Object catch (error) {
      _logger?.warning(
        'onboarding.save_failed',
        context: {'error_type': error.runtimeType.toString()},
      );
    }
    _logger?.info(
      'onboarding.completed',
      context: {
        'model_step': switch (state.model) {
          ModelSkipped() => 'skipped',
          ModelSaved() => 'saved',
          _ => 'later',
        },
      },
    );
    _onFinished();
  }

  @override
  Future<void> close() {
    _timeout?.cancel();
    return super.close();
  }
}
