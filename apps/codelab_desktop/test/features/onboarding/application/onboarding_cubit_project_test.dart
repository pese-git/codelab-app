// Красные тесты шага «Open a project» в `OnboardingCubit` (задача 2.4 change
// `add-onboarding-project-step`; design.md D1, D2, D6; spec app-onboarding
// «Шаги onboarding и переходы», «Шаг «Open a project»», «Завершение
// onboarding и старт рабочего места»).
//
// Красные по причине компиляции: `OnboardingStep.project`,
// `ProjectStepPhase`, порт `OnboardingProjectPort` и методы шага появляются в
// задаче 2.5.
//
// Контракт сверх design.md (фиксируется этими тестами):
// - `OnboardingCubit(project: OnboardingProjectPort)` — обязательный;
// - методы шага: `openFolder()`, `openDropped(paths)`, `openRecent(path)`,
//   `continueWithProject()`, `skip()`; общий выход (D2) — приватный
//   `_complete`, наружу исходы доступны только через эти методы;
// - фаза шага — `state.project` (`ProjectStepPhase.idle | choosing`).

import 'dart:async';

import 'package:codelab_desktop/core/platform/onboarding_preferences.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_cubit.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_probe.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_project_port.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_state.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording_logger.dart';

/// Маркер папки: ни в событиях onboarding, ни в состоянии его быть не должно
/// (D8).
const _marker = '/tmp/codelab-project-marker';

/// Порт фактов: факты готовы сразу, провайдер уже настроен (шаг модели
/// пропускается, путь до шага проекта короче).
final class _Probe implements OnboardingProbe {
  @override
  Future<OnboardingFacts> read() async => const OnboardingFacts(
    readiness: ProviderReady('openai/gpt'),
    access: EditableSettings(ConfigPaths(codelabHome: '/home/u/.codelab')),
    backendId: 'file',
    backendWritable: true,
    mode: 'standard',
    homeLabel: '~/.codelab',
  );
}

/// Порт флага: запись считается, может ждать затвор или падать; [order] —
/// общий журнал порядка «выбор → флаг».
final class _Preferences implements OnboardingPreferences {
  _Preferences(this.order);

  final List<String> order;
  var marked = 0;
  Completer<void>? gate;
  Object? failure;

  @override
  Future<OnboardingLoad> load() async => const OnboardingLoad(false);

  @override
  Future<void> markDone() async {
    order.add('markDone');
    marked++;
    await gate?.future;
    if (failure != null) {
      throw failure!;
    }
  }
}

/// Двойник порта шага: каждый ответ — по затвору, который тест завершает
/// сам; [order] — общий журнал порядка.
final class _Port implements OnboardingProjectPort {
  _Port(this.order);

  final List<String> order;
  final pickGates = <Completer<String?>>[];
  final dropGates = <Completer<String?>>[];
  final recentGates = <Completer<String?>>[];
  final dropped = <List<String?>>[];
  final recents = <String>[];

  /// Если задана — порт бросает её вместо ответа (сбой адаптера).
  Object? pickError;

  @override
  String? selectedProject;

  @override
  Future<String?> pickFolder() {
    order.add('pickFolder');
    if (pickError != null) {
      return Future.error(pickError!);
    }
    final gate = Completer<String?>();
    pickGates.add(gate);
    return gate.future;
  }

  @override
  Future<String?> openDropped(List<String?> paths) {
    order.add('openDropped');
    dropped.add(paths);
    final gate = Completer<String?>();
    dropGates.add(gate);
    return gate.future;
  }

  @override
  Future<String?> openRecent(String path) {
    order.add('openRecent');
    recents.add(path);
    final gate = Completer<String?>();
    recentGates.add(gate);
    return gate.future;
  }
}

void main() {
  late RecordingLogger logger;
  late List<String> order;
  late _Preferences preferences;
  late _Port port;
  late int finished;
  final cubits = <OnboardingCubit>[];

  setUp(() {
    logger = RecordingLogger();
    order = [];
    preferences = _Preferences(order);
    port = _Port(order);
    finished = 0;
  });

  tearDown(() async {
    for (final cubit in cubits) {
      await cubit.close();
    }
    cubits.clear();
  });

  OnboardingCubit build() {
    final cubit = OnboardingCubit(
      probe: _Probe(),
      preferences: preferences,
      project: port,
      onFinished: () {
        order.add('onFinished');
        finished++;
      },
      logger: logger,
    );
    cubits.add(cubit);
    return cubit;
  }

  Iterable<Map<String, Object?>> events(String name) =>
      logger.entries.where((e) => e['event'] == name);

  Future<void> settle() => pumpEventQueue(times: 30);

  /// Доводит onboarding до шага «Open a project» кнопкой «Next».
  Future<OnboardingCubit> atProject() async {
    final cubit = build();
    while (cubit.state.step != OnboardingStep.project) {
      final before = cubit.state.step;
      await cubit.next();
      if (cubit.state.step == before) {
        fail('«Next» не сдвинул шаг $before');
      }
    }
    return cubit;
  }

  group('переходы', () {
    test('«Next» на privacy ведёт на project, «Back» — обратно', () async {
      final cubit = build();
      await cubit.next();
      await cubit.next();
      expect(cubit.state.step, OnboardingStep.privacy);

      await cubit.next();
      expect(cubit.state.step, OnboardingStep.project);
      expect(cubit.state.project, ProjectStepPhase.idle);
      expect(events('onboarding.step_shown').last['step'], 'project');

      cubit.back();
      expect(cubit.state.step, OnboardingStep.privacy);
      expect(finished, 0);
      expect(preferences.marked, 0);
    });

    test('«Next» на шаге project ничего не делает', () async {
      final cubit = await atProject();

      await cubit.next();

      expect(cubit.state.step, OnboardingStep.project);
    });

    test('исходы шага вне шага project ничего не делают', () async {
      final cubit = build();
      await cubit.next();
      expect(cubit.state.step, OnboardingStep.permissions);
      port.selectedProject = '/work/restored';

      await cubit.skip();
      await cubit.continueWithProject();
      await cubit.openFolder();
      await cubit.openDropped(['/work/a']);
      await cubit.openRecent('/work/b');
      await settle();

      expect(preferences.marked, 0);
      expect(finished, 0);
      expect(cubit.state.finishing, isFalse);
      expect(order, isEmpty);
    });

    test('skip() вне шага project ничего не делает', () async {
      final cubit = build();
      await cubit.next();

      await cubit.skip();

      expect(preferences.marked, 0);
      expect(finished, 0);
    });
  });

  group('openFolder', () {
    test('принятая папка: флаг после ответа порта, один onFinished, '
        'project: picker', () async {
      final cubit = await atProject();

      final opening = cubit.openFolder();
      await settle();
      expect(cubit.state.project, ProjectStepPhase.choosing);
      expect(preferences.marked, 0);
      port.pickGates.single.complete(_marker);
      await opening;

      expect(order, ['pickFolder', 'markDone', 'onFinished']);
      expect(finished, 1);
      final completed = events('onboarding.completed').single;
      expect(completed['project'], 'picker');
      expect(completed['model_step'], 'skipped');
    });

    test('отмена диалога: шаг на месте, флага нет, событие', () async {
      final cubit = await atProject();

      final opening = cubit.openFolder();
      await settle();
      port.pickGates.single.complete(null);
      await opening;

      expect(cubit.state.step, OnboardingStep.project);
      expect(cubit.state.project, ProjectStepPhase.idle);
      expect(preferences.marked, 0);
      expect(finished, 0);
      expect(events('onboarding.project_pick_cancelled'), hasLength(1));
      expect(events('onboarding.completed'), isEmpty);

      // После отмены выбор доступен снова.
      final again = cubit.openFolder();
      await settle();
      expect(port.pickGates, hasLength(2));
      port.pickGates.last.complete(null);
      await again;
    });
  });

  group('openDropped', () {
    test('принятая папка: project: drop, порт получил пути как есть', () async {
      final cubit = await atProject();

      final dropping = cubit.openDropped([_marker]);
      await settle();
      expect(port.dropped.single, [_marker]);
      port.dropGates.single.complete(_marker);
      await dropping;

      expect(order, ['openDropped', 'markDone', 'onFinished']);
      expect(events('onboarding.completed').single['project'], 'drop');
    });

    test('отказ (null): шаг на месте, флаг не пишется', () async {
      final cubit = await atProject();

      final dropping = cubit.openDropped(['/work/file']);
      await settle();
      port.dropGates.single.complete(null);
      await dropping;

      expect(cubit.state.step, OnboardingStep.project);
      expect(cubit.state.project, ProjectStepPhase.idle);
      expect(preferences.marked, 0);
      expect(finished, 0);
      expect(events('onboarding.project_pick_cancelled'), isEmpty);
    });
  });

  group('openRecent, continueWithProject, skip', () {
    test('openRecent: project: recent', () async {
      final cubit = await atProject();

      final opening = cubit.openRecent('/work/app');
      await settle();
      expect(port.recents, ['/work/app']);
      port.recentGates.single.complete('/work/app');
      await opening;

      expect(order, ['openRecent', 'markDone', 'onFinished']);
      expect(events('onboarding.completed').single['project'], 'recent');
    });

    test('continueWithProject при выбранном проекте: project: restored, '
        'порт выбора не вызывается', () async {
      final cubit = await atProject();
      port.selectedProject = '/work/restored';

      await cubit.continueWithProject();

      expect(order, ['markDone', 'onFinished']);
      expect(events('onboarding.completed').single['project'], 'restored');
    });

    test('continueWithProject без проекта ничего не делает', () async {
      final cubit = await atProject();

      await cubit.continueWithProject();

      expect(preferences.marked, 0);
      expect(finished, 0);
    });

    test('skip без проекта: project: skipped', () async {
      final cubit = await atProject();

      await cubit.skip();

      expect(order, ['markDone', 'onFinished']);
      expect(events('onboarding.completed').single['project'], 'skipped');
    });

    test('skip при выбранном проекте ничего не делает', () async {
      final cubit = await atProject();
      port.selectedProject = '/work/restored';

      await cubit.skip();

      expect(preferences.marked, 0);
      expect(finished, 0);
    });
  });

  group('один выбор за раз', () {
    test('пока порт не ответил, остальные действия игнорируются, порт '
        'вызван один раз', () async {
      final cubit = await atProject();
      port.selectedProject = '/work/restored';

      final opening = cubit.openFolder();
      await settle();
      expect(cubit.state.project, ProjectStepPhase.choosing);

      cubit.back();
      await cubit.skip();
      await cubit.continueWithProject();
      await cubit.openFolder();
      await cubit.openDropped(['/work/a']);
      await cubit.openRecent('/work/b');
      await settle();

      expect(cubit.state.step, OnboardingStep.project);
      expect(preferences.marked, 0);
      expect(order, ['pickFolder']);
      expect(port.pickGates, hasLength(1));
      expect(port.dropGates, isEmpty);
      expect(port.recentGates, isEmpty);

      port.pickGates.single.complete(_marker);
      await opening;
      expect(finished, 1);
      expect(preferences.marked, 1);
    });

    test('двойной skip: одна запись флага, один onFinished, одно '
        'onboarding.completed', () async {
      final cubit = await atProject();
      preferences.gate = Completer<void>();

      final first = cubit.skip();
      final second = cubit.skip();
      await settle();
      preferences.gate!.complete();
      await first;
      await second;

      expect(preferences.marked, 1);
      expect(finished, 1);
      expect(events('onboarding.completed'), hasLength(1));
    });

    test('после принятой папки повторные действия игнорируются', () async {
      final cubit = await atProject();
      preferences.gate = Completer<void>();

      final opening = cubit.openFolder();
      await settle();
      port.pickGates.single.complete(_marker);
      await settle();
      expect(preferences.marked, 1);

      await cubit.skip();
      await cubit.openFolder();
      cubit.back();
      preferences.gate!.complete();
      await opening;

      expect(preferences.marked, 1);
      expect(finished, 1);
      expect(port.pickGates, hasLength(1));
    });
  });

  group('сбои и закрытие', () {
    test('порт выбора бросил: шаг на месте, флага нет, project_port_failed '
        'без текста ошибки и без project_pick_cancelled', () async {
      final cubit = await atProject();
      port.pickError = StateError('boom: $_marker');

      await cubit.openFolder();

      expect(cubit.state.step, OnboardingStep.project);
      expect(cubit.state.project, ProjectStepPhase.idle);
      expect(preferences.marked, 0);
      expect(finished, 0);
      final failed = events('onboarding.project_port_failed').single;
      expect(failed['level'], 'warning');
      expect(failed['error_type'], 'StateError');
      expect(events('onboarding.project_pick_cancelled'), isEmpty);
      expect('${logger.entries}', isNot(contains('boom')));
      expect('${logger.entries}', isNot(contains(_marker)));
    });

    test('сбой markDone: save_failed, затем completed и onFinished', () async {
      final cubit = await atProject();
      preferences.failure = StateError('disk full: $_marker');

      await cubit.skip();

      final failed = events('onboarding.save_failed').single;
      expect(failed['error_type'], 'StateError');
      expect(finished, 1);
      expect(events('onboarding.completed'), hasLength(1));
      expect('${logger.entries}', isNot(contains('disk full')));
      expect('${logger.entries}', isNot(contains(_marker)));
    });

    test('закрытие во время ответа порта: без onFinished, событий и '
        'исключений', () async {
      final cubit = await atProject();
      final before = logger.entries.length;

      final opening = cubit.openFolder();
      await settle();
      await cubit.close();
      port.pickGates.single.complete(_marker);
      await opening;

      expect(preferences.marked, 0);
      expect(finished, 0);
      expect(logger.entries.length, before);
    });

    test('закрытие во время markDone: без onFinished и completed', () async {
      final cubit = await atProject();
      preferences.gate = Completer<void>();

      final skipping = cubit.skip();
      await settle();
      await cubit.close();
      preferences.gate!.complete();
      await skipping;

      expect(finished, 0);
      expect(events('onboarding.completed'), isEmpty);
    });
  });

  test('в событиях onboarding нет путей и имён папок (D8)', () async {
    final cubit = await atProject();

    final opening = cubit.openFolder();
    await settle();
    port.pickGates.single.complete(_marker);
    await opening;

    expect('${logger.entries}', isNot(contains('codelab-project-marker')));
    expect('${cubit.state}', isNot(contains('codelab-project-marker')));
  });
}
