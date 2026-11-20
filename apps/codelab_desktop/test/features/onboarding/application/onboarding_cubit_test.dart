// Красные тесты `OnboardingCubit` (задача 2.1 change `add-app-onboarding`;
// design.md D4–D8, D13; spec app-onboarding «Шаги onboarding и переходы»,
// «Пропуск шага выбора модели», «Шаг «Choose a model» и мастер провайдера»,
// «Завершение onboarding и старт рабочего места»).
//
// Красные по причине компиляции: `features/onboarding/application/` появляется
// в задаче 2.2.
//
// Контракт сверх design.md (фиксируется этими тестами, принят при реализации
// 2.2):
// - `OnboardingCubit({probe, preferences, onFinished, factsTimeout, logger})`:
//   конец onboarding (D5, п. 4) отдаётся колбэком `onFinished` — composition
//   root передаёт `navigation.finishOnboarding`, поэтому application-слой не
//   зависит от `app/navigation`;
// - `factsTimeout` по умолчанию `kOnboardingFactsTimeout` (5 с, D6); тесты
//   сокращают его до нуля: пакет `fake_async` в проект не добавляется;
// - методы: `next()`, `back()`, `setUpLater()`, `providerSaved(Done)`,
//   `finish()`;
// - иерархии состояния — `Facts{Loading,Loaded,Unavailable}`,
//   `Model{Pending,Skipped,Choose,Saved}`.

import 'dart:async';

import 'package:codelab_desktop/core/platform/onboarding_preferences.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_cubit.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_probe.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_state.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_logger.dart';

/// Маркер ключа: ни в состоянии, ни в журнале его быть не должно (SETUP-1).
const _leak = 'sk-test-leak-0123456789';

/// Двойник порта фактов: ответ готов сразу, по затвору или бросает.
final class _FakeProbe implements OnboardingProbe {
  _FakeProbe.value(OnboardingFacts facts) : _immediate = facts;
  _FakeProbe.gated() : _immediate = null;
  _FakeProbe.failing(Object error) : _immediate = null, _error = error;

  final OnboardingFacts? _immediate;
  Object? _error;
  final gate = Completer<OnboardingFacts>();
  var reads = 0;

  @override
  Future<OnboardingFacts> read() {
    reads++;
    if (_error != null) {
      return Future<OnboardingFacts>.error(_error!);
    }
    return _immediate != null ? Future.value(_immediate) : gate.future;
  }
}

/// Двойник порта флага: запись считается, может ждать затвор или падать.
final class _FakePreferences implements OnboardingPreferences {
  var marked = 0;
  Completer<void>? gate;
  Object? failure;

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

OnboardingFacts _facts(
  ProviderReadiness readiness, {
  String backend = 'env',
  String mode = 'standard',
}) => OnboardingFacts(
  readiness: readiness,
  backendId: backend,
  backendWritable: backend != 'env',
  mode: mode,
  homeLabel: '~/.codelab',
  logsLabel: '~/Library/Application Support/CodeLab/logs',
);

const _keyMissing = ProviderKeyMissing(
  providerId: 'openai',
  reference: 'secret codelab/openai',
  backend: SecretBackendInfo(id: 'file', writable: true),
);

/// `Done` мастера: сохранён провайдер `llm` с моделью `m1`.
Done _done({KeyChoice key = const KeepStoredSecret(), String? secret}) => Done(
  ProviderSetupPlan(
    providerId: 'llm',
    kind: 'openai-compatible',
    baseUrl: 'http://localhost:1234/v1',
    key: key,
    secretName: secret,
    replaceSecret: false,
    model: const PlannedModel(id: 'm1', contextWindow: 8000),
    makeDefault: true,
    target: const ConfigTarget.user(),
  ),
  const ProviderCommitted(
    saved: ConfigSaved(fingerprint: 'f', warnings: [], restartRequiredKeys: []),
    keyReplaced: false,
  ),
);

void main() {
  late RecordingLogger logger;
  late _FakePreferences preferences;
  late int finished;
  final cubits = <OnboardingCubit>[];

  setUp(() {
    logger = RecordingLogger();
    preferences = _FakePreferences();
    finished = 0;
  });

  tearDown(() async {
    for (final cubit in cubits) {
      await cubit.close();
    }
    cubits.clear();
  });

  OnboardingCubit build(
    _FakeProbe probe, {
    Duration factsTimeout = kOnboardingFactsTimeout,
  }) {
    final cubit = OnboardingCubit(
      probe: probe,
      preferences: preferences,
      onFinished: () => finished++,
      factsTimeout: factsTimeout,
      logger: logger,
    );
    cubits.add(cubit);
    return cubit;
  }

  Iterable<Map<String, Object?>> events(String name) =>
      logger.entries.where((e) => e['event'] == name);

  Future<void> settle() => pumpEventQueue(times: 30);

  /// Доводит onboarding до шага [target] кнопкой «Next».
  Future<void> walkTo(OnboardingCubit cubit, OnboardingStep target) async {
    while (cubit.state.step != target) {
      final before = cubit.state.step;
      await cubit.next();
      if (cubit.state.step == before) {
        fail('«Next» не сдвинул шаг $before');
      }
    }
  }

  test('таймаут фактов по умолчанию — 5 с (D6)', () {
    expect(kOnboardingFactsTimeout, const Duration(seconds: 5));
  });

  group('начальное состояние и факты', () {
    test('шаг welcome, факты читаются один раз при создании', () async {
      final probe = _FakeProbe.gated();
      final cubit = build(probe);

      expect(cubit.state.step, OnboardingStep.welcome);
      expect(cubit.state.facts, isA<FactsLoading>());
      expect(cubit.state.model, isA<ModelPending>());
      expect(cubit.state.finishing, isFalse);
      expect(probe.reads, 1);

      await cubit.next();
      await settle();
      expect(probe.reads, 1, reason: 'повторного чтения нет (D6)');
    });

    test('FactsLoaded несёт факты: режим и подписи путей (D7, D9)', () async {
      final cubit = build(
        _FakeProbe.value(_facts(const NoProviderConfigured(), mode: 'bypass')),
      );
      await settle();

      final facts = (cubit.state.facts as FactsLoaded).facts;
      expect(facts.mode, 'bypass');
      expect(facts.isExternal, isFalse);
      expect(facts.homeLabel, '~/.codelab');
    });

    test(
      'facts_loaded: access, readiness, backend, duration_ms без путей',
      () async {
        final cases = <ProviderReadiness, String>{
          const ProviderReady('llm/m1'): 'ready',
          const NoProviderConfigured(): 'no_provider',
          _keyMissing: 'key_missing',
          const ConfigBroken([]): 'config_broken',
        };
        for (final entry in cases.entries) {
          logger.entries.clear();
          build(_FakeProbe.value(_facts(entry.key, backend: 'file')));
          await settle();

          final loaded = events('onboarding.facts_loaded').single;
          expect(loaded['level'], 'debug');
          expect(loaded['access'], 'editable');
          expect(loaded['readiness'], entry.value);
          expect(loaded['backend'], 'file');
          expect(loaded['duration_ms'], isA<int>());
        }
      },
    );

    test('внешний профиль: access external, шаг модели пропущен', () async {
      final cubit = build(
        _FakeProbe.value(const OnboardingFacts.external(logsLabel: '~/logs')),
      );
      await settle();

      expect((cubit.state.facts as FactsLoaded).facts.isExternal, isTrue);
      expect(cubit.state.model, const ModelSkipped(ModelSkipReason.external));
      final loaded = events('onboarding.facts_loaded').single;
      expect(loaded['access'], 'external');
      final skipped = events('onboarding.model_step_skipped').single;
      expect(skipped['level'], 'info');
      expect(skipped['reason'], 'external');
    });
  });

  group('переходы по таблице D4', () {
    test('проход без пропуска: welcome, permissions, model, privacy', () async {
      final cubit = build(
        _FakeProbe.value(_facts(const NoProviderConfigured())),
      );
      await settle();

      await cubit.next();
      expect(cubit.state.step, OnboardingStep.permissions);
      await cubit.next();
      expect(cubit.state.step, OnboardingStep.model);
      expect(cubit.state.model, const ModelChoose(ModelNotice.none));
      cubit.setUpLater();
      expect(cubit.state.step, OnboardingStep.privacy);

      expect(events('onboarding.step_shown').map((e) => e['step']), [
        'welcome',
        'permissions',
        'model',
        'privacy',
      ]);
      expect(events('onboarding.step_shown').first['level'], 'debug');
    });

    test('Back идёт по таблице и на первом шаге ничего не делает', () async {
      final cubit = build(
        _FakeProbe.value(_facts(const NoProviderConfigured())),
      );
      await settle();

      cubit.back();
      expect(cubit.state.step, OnboardingStep.welcome);

      await walkTo(cubit, OnboardingStep.model);
      cubit.setUpLater();
      expect(cubit.state.step, OnboardingStep.privacy);

      cubit.back();
      expect(cubit.state.step, OnboardingStep.model);
      cubit.back();
      expect(cubit.state.step, OnboardingStep.permissions);
      cubit.back();
      expect(cubit.state.step, OnboardingStep.welcome);
    });

    test('ProviderReady: шаг model пропущен, Back с privacy ведёт на '
        'permissions', () async {
      final cubit = build(
        _FakeProbe.value(_facts(const ProviderReady('llm/m1'))),
      );
      await settle();

      await cubit.next();
      await cubit.next();

      expect(cubit.state.step, OnboardingStep.privacy);
      expect(cubit.state.model, const ModelSkipped(ModelSkipReason.ready));
      final skipped = events('onboarding.model_step_skipped').single;
      expect(skipped['reason'], 'ready');

      cubit.back();
      expect(cubit.state.step, OnboardingStep.permissions);
    });

    test('«Next» на шаге model без сохранённого провайдера и на privacy '
        'ничего не делает', () async {
      final cubit = build(
        _FakeProbe.value(_facts(const NoProviderConfigured())),
      );
      await settle();
      await walkTo(cubit, OnboardingStep.model);

      await cubit.next();
      expect(cubit.state.step, OnboardingStep.model);

      cubit.setUpLater();
      await cubit.next();
      expect(cubit.state.step, OnboardingStep.privacy);
    });

    test('setUpLater вне шага model ничего не меняет', () async {
      final cubit = build(
        _FakeProbe.value(_facts(const NoProviderConfigured())),
      );
      await settle();

      cubit.setUpLater();
      expect(cubit.state.step, OnboardingStep.welcome);
      await cubit.next();
      cubit.setUpLater();
      expect(cubit.state.step, OnboardingStep.permissions);
    });
  });

  group('«Next» на шаге Permissions при ещё не известной готовности', () {
    test('ждёт итога; повторное нажатие не даёт второго перехода', () async {
      final probe = _FakeProbe.gated();
      final cubit = build(probe);
      final steps = <OnboardingStep>[];
      final sub = cubit.stream.map((s) => s.step).distinct().listen(steps.add);
      await cubit.next();
      expect(cubit.state.step, OnboardingStep.permissions);

      final first = cubit.next();
      final second = cubit.next();
      await settle();
      expect(cubit.state.step, OnboardingStep.permissions);
      expect(cubit.state.model, isA<ModelPending>());

      probe.gate.complete(_facts(const ProviderReady('llm/m1')));
      await Future.wait([first, second]);

      // Ровно один переход: permissions -> privacy (шаг model пропущен).
      expect(cubit.state.step, OnboardingStep.privacy);
      expect(steps, [OnboardingStep.permissions, OnboardingStep.privacy]);
      await sub.cancel();
    });
  });

  group('сбой и таймаут фактов (D6)', () {
    test('таймаут: Choose(unavailable), facts_unavailable {timeout: true}, '
        'поздний итог шаг не меняет', () async {
      final probe = _FakeProbe.gated();
      final cubit = build(probe, factsTimeout: Duration.zero);
      await cubit.next();

      await cubit.next();

      expect(cubit.state.step, OnboardingStep.model);
      expect(cubit.state.facts, isA<FactsUnavailable>());
      expect(cubit.state.model, const ModelChoose(ModelNotice.unavailable));
      final warning = events('onboarding.facts_unavailable').single;
      expect(warning['level'], 'warning');
      expect(warning['timeout'], isTrue);

      final snapshot = cubit.state;
      final emitted = <OnboardingState>[];
      final sub = cubit.stream.listen(emitted.add);
      probe.gate.complete(_facts(const ProviderReady('llm/m1')));
      await settle();

      expect(cubit.state, snapshot);
      expect(emitted, isEmpty);
      expect(events('onboarding.model_step_skipped'), isEmpty);
      final late = events('onboarding.facts_late').single;
      expect(late['level'], 'debug');
      expect(late['duration_ms'], isA<int>());
      await sub.cancel();
    });

    test(
      'таймаут срабатывает и без «Next»: шаг ждёт уже готовый итог',
      () async {
        final cubit = build(_FakeProbe.gated(), factsTimeout: Duration.zero);
        await settle();

        expect(cubit.state.facts, isA<FactsUnavailable>());
        expect(cubit.state.model, const ModelChoose(ModelNotice.unavailable));
      },
    );

    test(
      'исключение зонда: Choose(unavailable), error_type без текста',
      () async {
        final cubit = build(
          _FakeProbe.failing(StateError('нет доступа к /Users/x/.codelab')),
        );
        await settle();

        expect(cubit.state.facts, isA<FactsUnavailable>());
        expect(cubit.state.model, const ModelChoose(ModelNotice.unavailable));
        final warning = events('onboarding.facts_unavailable').single;
        expect(warning['error_type'], 'StateError');
        expect(warning.containsKey('timeout'), isFalse);
        expect(logger.entries.toString(), isNot(contains('/Users/x')));
      },
    );

    test('итог после close() не даёт emit и не бросает', () async {
      final probe = _FakeProbe.gated();
      final cubit = build(probe);

      await cubit.close();
      probe.gate.complete(_facts(const NoProviderConfigured()));
      await settle();

      expect(cubit.isClosed, isTrue);
    });
  });

  group('шаг «Choose a model»: пояснения и мастер (D8)', () {
    test('ProviderKeyMissing, ConfigBroken: Choose с соответствующим '
        'пояснением', () async {
      final missing = build(_FakeProbe.value(_facts(_keyMissing)));
      await settle();
      expect(missing.state.model, const ModelChoose(ModelNotice.keyMissing));

      final broken = build(_FakeProbe.value(_facts(const ConfigBroken([]))));
      await settle();
      expect(broken.state.model, const ModelChoose(ModelNotice.configBroken));
    });

    test('«Set up later» доступна в любом Choose и ничего не пишет', () async {
      for (final readiness in <ProviderReadiness>[
        const NoProviderConfigured(),
        _keyMissing,
        const ConfigBroken([]),
      ]) {
        final cubit = build(_FakeProbe.value(_facts(readiness)));
        await settle();
        await walkTo(cubit, OnboardingStep.model);

        cubit.setUpLater();

        expect(cubit.state.step, OnboardingStep.privacy);
        expect(preferences.marked, 0);
      }
    });

    test(
      'Done мастера: Saved(summary) без значения ключа, Next активна',
      () async {
        final cubit = build(
          _FakeProbe.value(
            _facts(const NoProviderConfigured(), backend: 'file'),
          ),
        );
        await settle();
        await walkTo(cubit, OnboardingStep.model);

        cubit.providerSaved(
          _done(key: StoreSecret(SecretValue(_leak)), secret: 'codelab/llm'),
        );

        final model = cubit.state.model as ModelSaved;
        expect(model.summary.providerId, 'llm');
        expect(model.summary.model, 'llm/m1');
        expect(
          model.summary.keyStorage,
          const SecretKeyStorage(name: 'codelab/llm', backendId: 'file'),
        );
        expect(cubit.state.toString(), isNot(contains(_leak)));
        expect(model.toString(), isNot(contains(_leak)));
        final saved = events('onboarding.model_saved').single;
        expect(saved['level'], 'info');
        expect(logger.entries.toString(), isNot(contains(_leak)));
        expect(logger.entries.toString(), isNot(contains('codelab/llm')));

        await cubit.next();
        expect(cubit.state.step, OnboardingStep.privacy);
        cubit.back();
        expect(cubit.state.step, OnboardingStep.model);
        expect(cubit.state.model, isA<ModelSaved>());
      },
    );

    test('способы хранения ключа в сводке: env и без ключа', () async {
      final cubit = build(
        _FakeProbe.value(_facts(const NoProviderConfigured())),
      );
      await settle();
      await walkTo(cubit, OnboardingStep.model);

      cubit.providerSaved(_done(key: const UseEnvVar('LLM_KEY')));
      expect(
        (cubit.state.model as ModelSaved).summary.keyStorage,
        const EnvKeyStorage('LLM_KEY'),
      );

      // «Set up again…»: повторное сохранение заменяет сводку.
      cubit.providerSaved(_done(key: const NoKey()));
      expect(
        (cubit.state.model as ModelSaved).summary.keyStorage,
        const NoKeyStorage(),
      );
    });

    test('Done при ConfigBroken и недоступных фактах игнорируется (мастер '
        'не пишет поверх битого файла)', () async {
      final broken = build(_FakeProbe.value(_facts(const ConfigBroken([]))));
      await settle();
      await walkTo(broken, OnboardingStep.model);
      broken.providerSaved(_done());
      expect(broken.state.model, const ModelChoose(ModelNotice.configBroken));

      final unavailable = build(_FakeProbe.failing(StateError('x')));
      await settle();
      await walkTo(unavailable, OnboardingStep.model);
      unavailable.providerSaved(_done());
      expect(
        unavailable.state.model,
        const ModelChoose(ModelNotice.unavailable),
      );
    });
  });

  group('завершение (D5)', () {
    Future<OnboardingCubit> atPrivacy() async {
      final cubit = build(
        _FakeProbe.value(_facts(const ProviderReady('llm/m1'))),
      );
      await settle();
      await walkTo(cubit, OnboardingStep.privacy);
      return cubit;
    }

    test('finish: markDone, затем onFinished, события completed', () async {
      final cubit = await atPrivacy();

      await cubit.finish();

      expect(preferences.marked, 1);
      expect(finished, 1);
      final completed = events('onboarding.completed').single;
      expect(completed['level'], 'info');
      expect(completed['model_step'], 'skipped');
    });

    test('двойное нажатие: одна запись и один переход', () async {
      final cubit = await atPrivacy();
      preferences.gate = Completer<void>();

      final first = cubit.finish();
      final second = cubit.finish();
      await settle();
      expect(cubit.state.finishing, isTrue);
      expect(finished, 0, reason: 'переход только после записи флага');

      preferences.gate!.complete();
      await Future.wait([first, second]);

      expect(preferences.marked, 1);
      expect(finished, 1);
      expect(events('onboarding.completed'), hasLength(1));
    });

    test('сбой записи флага не запирает: save_failed и переход', () async {
      final cubit = await atPrivacy();
      preferences.failure = StateError('нет места на /Users/x/disk');

      await cubit.finish();

      expect(finished, 1);
      final warning = events('onboarding.save_failed').single;
      expect(warning['level'], 'warning');
      expect(warning['error_type'], 'StateError');
      expect(logger.entries.toString(), isNot(contains('/Users/x')));
    });

    test('finish вне шага privacy игнорируется', () async {
      final cubit = build(
        _FakeProbe.value(_facts(const NoProviderConfigured())),
      );
      await settle();

      await cubit.finish();

      expect(preferences.marked, 0);
      expect(finished, 0);
    });

    test('completed.model_step: saved и later', () async {
      final saved = build(
        _FakeProbe.value(_facts(const NoProviderConfigured())),
      );
      await settle();
      await walkTo(saved, OnboardingStep.model);
      saved.providerSaved(_done(secret: 'codelab/llm'));
      await saved.next();
      await saved.finish();
      expect(events('onboarding.completed').single['model_step'], 'saved');

      logger.entries.clear();
      final later = build(
        _FakeProbe.value(_facts(const NoProviderConfigured())),
      );
      await settle();
      await walkTo(later, OnboardingStep.model);
      later.setUpLater();
      await later.finish();
      expect(events('onboarding.completed').single['model_step'], 'later');
    });
  });

  test('журнал полного прохода: только события D13, без путей, имён секретов, '
      'адресов и ключей (D13)', () async {
    final cubit = build(_FakeProbe.value(_facts(_keyMissing, backend: 'file')));
    await settle();
    await walkTo(cubit, OnboardingStep.model);
    cubit.providerSaved(
      _done(key: StoreSecret(SecretValue(_leak)), secret: 'codelab/llm'),
    );
    await cubit.next();
    await cubit.finish();

    const allowed = {
      'onboarding.shown',
      'onboarding.facts_loaded',
      'onboarding.step_shown',
      'onboarding.model_saved',
      'onboarding.completed',
    };
    for (final entry in logger.entries) {
      expect(allowed, contains(entry['event']));
    }
    final dump = logger.entries.toString();
    for (final forbidden in [
      _leak,
      'codelab/openai',
      'codelab/llm',
      'localhost',
      '~/.codelab',
      'Application Support',
      'llm/m1',
    ]) {
      expect(dump, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
