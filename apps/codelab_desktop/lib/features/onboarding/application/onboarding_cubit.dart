import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/onboarding_preferences.dart';
import '../../settings/application/legal_documents.dart' show LegalTab;
import 'onboarding_probe.dart';
import 'onboarding_project_port.dart';
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
/// по таблице D4, принимает итог мастера провайдера, завершает onboarding на
/// шаге «Open a project»: выбор → флаг → [onFinished] (D2
/// `add-onboarding-project-step`). События — D13, без путей, имён папок,
/// секретов, адресов и текстов исключений.
///
/// Как использовать: composition root создаёт один экземпляр на показ
/// onboarding; [onFinished] — `NavigationCubit.finishOnboarding`, [project] —
/// адаптер рабочего места. Кнопки экрана вызывают [next], [back],
/// [setUpLater]; на последнем шаге — [openFolder], [openDropped],
/// [openRecent], [continueWithProject], [skip]; после диалога мастера экран
/// передаёт `Done` в [providerSaved]. Агента Cubit не стартует и удержание
/// триггера выбора не снимает: это делает `CodeLabShellCubit.startOnLaunch()`
/// рабочего места (D5). Cubit закрывает владелец.
class OnboardingCubit extends Cubit<OnboardingState> {
  OnboardingCubit({
    required OnboardingProbe probe,
    required OnboardingPreferences preferences,
    required OnboardingProjectPort project,
    required void Function() onFinished,
    Duration factsTimeout = kOnboardingFactsTimeout,
    Logger? logger,
  }) : _probe = probe,
       _preferences = preferences,
       _project = project,
       _onFinished = onFinished,
       _logger = logger,
       super(const OnboardingState()) {
    _logger?.debug('onboarding.step_shown', context: {'step': 'welcome'});
    _loadFacts(factsTimeout);
  }

  final OnboardingProbe _probe;
  final OnboardingPreferences _preferences;
  final OnboardingProjectPort _project;
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
    if (!_factsDone.isCompleted) {
      _factsDone.complete();
    }
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
    if (!_factsDone.isCompleted) {
      _factsDone.complete();
    }
  }

  static String _readinessName(ProviderReadiness readiness) =>
      switch (readiness) {
        ProviderReady() => 'ready',
        NoProviderConfigured() => 'no_provider',
        ProviderKeyMissing() => 'key_missing',
        ConfigBroken() => 'config_broken',
      };

  bool get _modelSkipped => state.model is ModelSkipped;

  /// Фаза мастера на шаге модели; у остальных видов шага — `idle`.
  ModelWizard get _wizardPhase => switch (state.model) {
    ModelChoose(:final wizard) => wizard,
    ModelSaved(:final wizard) => wizard,
    _ => ModelWizard.idle,
  };

  OnboardingModelStep _withWizard(
    OnboardingModelStep model,
    ModelWizard phase,
  ) => switch (model) {
    ModelChoose(:final notice) => ModelChoose(notice, wizard: phase),
    ModelSaved(:final summary) => ModelSaved(summary, wizard: phase),
    _ => model,
  };

  /// Мастер провайдера начинает открываться (D8, ревью 2026-11-21, п. 6).
  ///
  /// Почему здесь: открытие мастера асинхронно (хранилище секретов, снимок), и
  /// без блокировки пользователь успел бы уйти с шага, а диалог появился бы
  /// поверх чужого шага. Возвращает `false`, если мастер открывать нельзя:
  /// шаг не «Choose a model», мастер уже активен, конфиг битый или факты
  /// недоступны (мастер не пишет поверх битого файла), Cubit закрыт.
  ///
  /// Как использовать: экран вызывает до открытия, при `false` ничего не
  /// открывает; после диалога вызывает [wizardEnded].
  bool wizardStarted() {
    if (isClosed ||
        state.step != OnboardingStep.model ||
        state.document != null ||
        _wizardPhase == ModelWizard.active) {
      return false;
    }
    final model = state.model;
    final allowed =
        model is ModelSaved ||
        model is ModelChoose &&
            (model.notice == ModelNotice.none ||
                model.notice == ModelNotice.keyMissing);
    if (!allowed) {
      return false;
    }
    emit(state.copyWith(model: _withWizard(model, ModelWizard.active)));
    return true;
  }

  /// Диалог мастера закрыт (сохранением или отменой): навигация шага снова
  /// действует. Без активного мастера и после `close()` ничего не делает.
  void wizardEnded() {
    if (isClosed || _wizardPhase != ModelWizard.active) {
      return;
    }
    emit(state.copyWith(model: _withWizard(state.model, ModelWizard.idle)));
  }

  void _show(OnboardingStep step) {
    emit(state.copyWith(step: step));
    _logger?.debug('onboarding.step_shown', context: {'step': step.name});
  }

  /// Открывает просмотр правового документа [tab] на шаге «Privacy» (D10 в
  /// редакции 2026-11-21).
  ///
  /// Почему здесь: навигация app остаётся на `OnboardingDestination`, а то, что
  /// показано поверх шага, — состояние экрана onboarding; сводка провайдера и
  /// факты при этом не меняются. Возвращает `false`, если открыть нельзя: шаг
  /// не «Privacy», документ или мастер уже открыты, идёт завершение или Cubit
  /// закрыт.
  ///
  /// Как использовать: ссылки шага вызывают [openDocument], панель документа —
  /// [closeDocument]. Событие `onboarding.document_opened {tab}` без путей.
  bool openDocument(LegalTab tab) {
    if (isClosed ||
        state.step != OnboardingStep.privacy ||
        state.document != null ||
        state.finishing ||
        _wizardPhase == ModelWizard.active) {
      return false;
    }
    emit(state.copyWith(document: tab));
    _logger?.info('onboarding.document_opened', context: {'tab': tab.logName});
    return true;
  }

  /// Закрывает просмотр документа: шаг «Privacy» в прежнем виде. Без открытого
  /// документа и после `close()` ничего не делает. Событие
  /// `onboarding.document_closed {tab}` (debug).
  void closeDocument() {
    final tab = state.document;
    if (isClosed || tab == null) {
      return;
    }
    emit(state.copyWith(clearDocument: true));
    _logger?.debug('onboarding.document_closed', context: {'tab': tab.logName});
  }

  /// «Next»: переходы D4. На шаге «Permissions» при неизвестной готовности
  /// ждёт итога чтения (не дольше таймаута); повторное нажатие в ожидании
  /// игнорируется.
  Future<void> next() async {
    if (state.document != null || _wizardPhase == ModelWizard.active) {
      return;
    }
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
        _show(OnboardingStep.project);
      case OnboardingStep.project:
        break;
    }
  }

  /// «Back»: на «Privacy» ведёт на «Choose a model», если шаг не пропущен.
  void back() {
    if (state.document != null ||
        _wizardPhase == ModelWizard.active ||
        !_projectStepIdle) {
      return;
    }
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
      case OnboardingStep.project:
        _show(OnboardingStep.privacy);
    }
  }

  /// «Set up later» (Q3, D8): на «Privacy» без записи; доступна, пока
  /// провайдер не сохранён.
  void setUpLater() {
    if (state.step != OnboardingStep.model ||
        state.model is! ModelChoose ||
        state.document != null ||
        _wizardPhase == ModelWizard.active) {
      return;
    }
    _show(OnboardingStep.privacy);
  }

  /// Принимает `Done` мастера провайдера: шаг переходит в `Saved` (D8).
  ///
  /// Игнорируется при `configBroken` и `unavailable`: мастер там не
  /// открывается. Значения ключа в сводку не попадает (SETUP-1).
  void providerSaved(Done done) {
    // Итог диалога может прийти после закрытия Cubit-а (выход из app с
    // открытым мастером): `emit` в закрытый Cubit бросил бы `StateError`.
    if (isClosed) {
      return;
    }
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
          // Итог приходит, пока диалог ещё закрывается: фазу снимает
          // `wizardEnded`, а не `Done`.
          wizard: _wizardPhase,
        ),
      ),
    );
    _logger?.info('onboarding.model_saved');
  }

  /// Шаг «Open a project» принимает действия: он показан, выбор не идёт и
  /// завершение не началось (D6). Для остальных шагов — всегда `true`:
  /// их навигацию эта проверка не меняет.
  bool get _projectStepIdle =>
      state.step != OnboardingStep.project ||
      !state.finishing && state.project == ProjectStepPhase.idle;

  /// Шаг «Open a project» готов принять выбор или исход.
  bool get _canChooseProject =>
      !isClosed &&
      state.step == OnboardingStep.project &&
      !state.finishing &&
      state.project == ProjectStepPhase.idle;

  /// «Open folder…» и Cmd/Ctrl+O: системный выбор папки (D2, D6).
  ///
  /// Принятая папка завершает onboarding ([ProjectChosen] `picker`); отмена
  /// диалога и его сбой оставляют шаг на месте без записи флага и пишут
  /// `onboarding.project_pick_cancelled`. Пока порт не ответил
  /// ([ProjectStepPhase.choosing]), повторный вызов игнорируется.
  Future<void> openFolder() async {
    final path = await _choose(
      _project.pickFolder,
      cancelledEvent: 'onboarding.project_pick_cancelled',
    );
    if (path != null) {
      await _complete(const ProjectChosen(ProjectSource.picker));
    }
  }

  /// Бросок на экран: решение о путях принимает рабочее место (порт), здесь
  /// только исход. Принятая папка — [ProjectChosen] `drop`; отказ (`null`)
  /// оставляет шаг и флаг как есть, текст отказа показывает зона шага.
  Future<void> openDropped(List<String?> paths) async {
    final path = await _choose(() => _project.openDropped(paths));
    if (path != null) {
      await _complete(const ProjectChosen(ProjectSource.drop));
    }
  }

  /// Запись «Recent projects»: выбор недавнего проекта, как в сайдбаре
  /// (D3). Принятый — [ProjectChosen] `recent`.
  Future<void> openRecent(String path) async {
    final chosen = await _choose(() => _project.openRecent(path));
    if (chosen != null) {
      await _complete(const ProjectChosen(ProjectSource.recent));
    }
  }

  /// `Continue in <name>`: подтверждает восстановленный проект (D3). Без
  /// выбранного проекта ничего не делает.
  Future<void> continueWithProject() async {
    if (!_canChooseProject || _project.selectedProject == null) {
      return;
    }
    await _complete(const ProjectRestored());
  }

  /// «Skip for now»: откладывает выбор (D2). Действует, только пока проекта
  /// нет; с проектом на шаге вместо него `Continue…`. Это не «запустить без
  /// проекта»: восстановление идёт как при обычном запуске.
  Future<void> skip() async {
    if (!_canChooseProject || _project.selectedProject != null) {
      return;
    }
    await _complete(const ProjectSkipped());
  }

  /// Выполняет один выбор через порт под защитой фазы [ProjectStepPhase]
  /// (D6): возвращает путь принятой папки или `null` (отмена, отказ, сбой
  /// порта, закрытый Cubit). Результат после `close()` отбрасывается — выбор,
  /// уже применённый рабочим местом, остаётся и предложит `Continue…` при
  /// следующем запуске.
  Future<String?> _choose(
    Future<String?> Function() action, {
    String? cancelledEvent,
  }) async {
    if (!_canChooseProject) {
      return null;
    }
    emit(state.copyWith(project: ProjectStepPhase.choosing));
    String? path;
    var portFailed = false;
    try {
      path = await action();
    } on Object catch (error) {
      // Порт обязан не бросать; сбой адаптера — «выбор не принят», но не
      // «отмена диалога»: ошибка не теряется. Только тип: в тексте бывают
      // пути (D8).
      portFailed = true;
      if (!isClosed) {
        _logger?.warning(
          'onboarding.project_port_failed',
          context: {'error_type': error.runtimeType.toString()},
        );
      }
    }
    if (isClosed) {
      return null;
    }
    if (path == null) {
      emit(state.copyWith(project: ProjectStepPhase.idle));
      if (cancelledEvent != null && !portFailed) {
        _logger?.debug(cancelledEvent);
      }
      return null;
    }
    return path;
  }

  /// Единственный выход шага (D2): исход — закрытая иерархия
  /// [OnboardingProjectExit], порядок «флаг → навигация» один для всех
  /// исходов. Наружу не открыт: вызывающие проходят проверки своих методов
  /// ([openFolder], [continueWithProject], [skip] и др.), иначе инварианты D2
  /// можно обойти. Папку не выбирает: принятый выбор уже сделал порт.
  ///
  /// Порядок D2: `finishing` → флаг → (при сбое `save_failed`, без остановки)
  /// → проверка `isClosed` → `onboarding.completed` → `onFinished`.
  ///
  /// Сбой записи не запирает пользователя: рабочее место откроется с
  /// выбранным проектом, onboarding покажется при следующем запуске.
  Future<void> _complete(OnboardingProjectExit exit) async {
    if (isClosed || state.finishing) {
      return;
    }
    emit(state.copyWith(finishing: true, project: ProjectStepPhase.idle));
    try {
      await _preferences.markDone();
    } on Object catch (error) {
      if (isClosed) {
        return;
      }
      _logger?.warning(
        'onboarding.save_failed',
        context: {'error_type': error.runtimeType.toString()},
      );
    }
    // Закрытие во время записи: итог не публикуется, `onFinished` не зовётся
    // (design.md D5, ревью 2026-11-21, п. 7; CON-005).
    if (isClosed) {
      return;
    }
    _logger?.info(
      'onboarding.completed',
      context: {
        'model_step': switch (state.model) {
          ModelSkipped() => 'skipped',
          ModelSaved() => 'saved',
          _ => 'later',
        },
        'project': switch (exit) {
          ProjectChosen(:final source) => source.name,
          ProjectRestored() => 'restored',
          ProjectSkipped() => 'skipped',
        },
      },
    );
    _onFinished();
  }

  @override
  Future<void> close() {
    _timeout?.cancel();
    // `next()` на шаге «Permissions» ждёт факты: закрытие завершает ожидание,
    // иначе он повис бы (D6, ревью 2026-11-21, п. 8).
    if (!_factsDone.isCompleted) {
      _factsDone.complete();
    }
    return super.close();
  }
}
