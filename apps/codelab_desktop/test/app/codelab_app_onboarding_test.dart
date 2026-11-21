// Onboarding в composition root и корневом виджете (задача 3.7 change
// `add-app-onboarding`; design.md D3, D5; spec app-onboarding «Показ
// onboarding при первом запуске», «Завершение onboarding и старт рабочего
// места», «Шаги onboarding и переходы» (Esc и настройки); spec
// agent-workbench-ui «Агент стартует сам» — «Восстановленный проект при
// первом показе onboarding»).
//
// Красный по причине компиляции: `OnboardingStart`, шов
// `CodeLabTestBinding(onboarding:, onboardingProbe:, onboardingPreferences:)`,
// `OnboardingScreen` появляются в задачах 3.4 и 3.8.
//
// Контракт шва (принят при реализации 3.8): `main` читает флаг до `runApp` и
// передаёт `OnboardingStart` в `createCodeLabRootScope(onboarding:)`; без шва
// onboarding не показывается, поэтому прежние тесты рабочего места не меняются
// (D3). `onboardingProbe` и `onboardingPreferences` — швы портов; тестовая
// сборка подставляет их двойники. События чтения флага
// (`onboarding.shown`, `.flag_invalid`, `.flag_unreadable`) пишет модуль после
// настройки журнала, как `app.locale_resolved`.

import 'dart:async';

import 'package:codelab_desktop/app/navigation/app_destination.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/onboarding/onboarding_start.dart';
import 'package:codelab_client_io/codelab_client_io.dart' show DirectoryExists;
import 'package:codelab_desktop/core/platform/local_path_kind.dart';
import 'package:codelab_desktop/core/platform/onboarding_preferences.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/core/platform/os_drop_region.dart';
import 'package:codelab_desktop/features/onboarding/presentation/onboarding_screen.dart';
import 'package:codelab_desktop/features/workbench/presentation/workbench_shell.dart';
import 'package:codelab_setup/codelab_setup.dart' show NoProviderConfigured;
import 'package:codelab_ui/codelab_ui.dart' show CodeLabShortcut;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../support/fake_onboarding.dart';
import '../support/press_shortcut.dart';
import '../support/test_app_scope.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  late FakeOnboardingPreferences preferences;
  late FakeOnboardingProbe probe;
  late List<String> embeddedCalls;

  setUp(() {
    preferences = FakeOnboardingPreferences();
    probe = FakeOnboardingProbe(onboardingFacts(const NoProviderConfigured()));
    embeddedCalls = [];
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1400, 1000);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  CodeLabTestBinding binding({
    OnboardingStart? onboarding,
    String? project,
    OnboardingPreferences? flag,
    ProjectFolderPicker? picker,
    DirectoryExists? directoryExists,
    LocalPathKindOf? localPathKind,
  }) => CodeLabTestBinding(
    onboarding: onboarding,
    onboardingProbe: probe,
    onboardingPreferences: flag ?? preferences,
    project: project,
    projectFolderPicker: picker,
    directoryExists: directoryExists,
    localPathKind: localPathKind,
    stdioDefault: false,
    // Открыватель считает вызовы и падает: агент в тесте не нужен, важно
    // только когда и с какой папкой его пытаются открыть.
    embeddedOpener: ({required cwd, required hostProfile}) async {
      embeddedCalls.add(cwd);
      throw StateError('the embedded agent is not part of this test');
    },
  );

  Future<void> pumpApp(WidgetTester tester, CodeLabTestBinding b) async {
    await tester.pumpWidget(
      b.bootstrap(child: const CodeLabApp(startOnLaunch: true)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> settleFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('OnboardingStart', () {
    test('fromLoad: нет ключа — показать; пройден, повреждён, сбой — нет', () {
      expect(
        OnboardingStart.fromLoad(const OnboardingLoad(false)).show,
        isTrue,
      );
      expect(
        OnboardingStart.fromLoad(const OnboardingLoad(true)).show,
        isFalse,
      );

      final invalid = OnboardingStart.fromLoad(
        const OnboardingLoad(true, storedValueInvalid: true),
      );
      expect(invalid.show, isFalse);
      expect(invalid.storedValueInvalid, isTrue);

      final unreadable = OnboardingStart.fromLoad(
        const OnboardingLoad(true, readFailure: 'StateError'),
      );
      expect(unreadable.show, isFalse);
      expect(unreadable.readFailure, 'StateError');
    });
  });

  group('показ при запуске (D3)', () {
    testWidgets('первый запуск: экран onboarding, рабочего места нет, '
        'onboarding.shown в журнале', (tester) async {
      final b = binding(onboarding: const OnboardingStart(show: true));

      await pumpApp(tester, b);

      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(CodeLabShell), findsNothing);
      expect(
        b.scope.resolve<NavigationCubit>().state,
        const OnboardingDestination(),
      );
      final events = b.scope.resolve<LogBuffer>().entries.value;
      expect(
        events.where((e) => e['event'] == 'onboarding.shown'),
        hasLength(1),
      );
    });

    testWidgets('onboarding пройден: первый кадр — рабочее место', (
      tester,
    ) async {
      final b = binding(onboarding: const OnboardingStart(show: false));

      await pumpApp(tester, b);

      expect(find.byType(CodeLabShell), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      final events = b.scope.resolve<LogBuffer>().entries.value;
      expect(events.where((e) => e['event'] == 'onboarding.shown'), isEmpty);
    });

    testWidgets('без шва onboarding не показывается', (tester) async {
      final b = binding();

      await pumpApp(tester, b);

      expect(find.byType(CodeLabShell), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('повреждённое значение флага: рабочее место и '
        'onboarding.flag_invalid', (tester) async {
      final b = binding(
        onboarding: const OnboardingStart(
          show: false,
          storedValueInvalid: true,
        ),
      );

      await pumpApp(tester, b);

      expect(find.byType(CodeLabShell), findsOneWidget);
      final invalid = b.scope.resolve<LogBuffer>().entries.value.singleWhere(
        (e) => e['event'] == 'onboarding.flag_invalid',
      );
      expect(invalid['level'], 'warning');
    });

    testWidgets('хранилище не читается: рабочее место и flag_unreadable с '
        'типом ошибки', (tester) async {
      final b = binding(
        onboarding: const OnboardingStart(
          show: false,
          readFailure: 'StateError',
        ),
      );

      await pumpApp(tester, b);

      expect(find.byType(CodeLabShell), findsOneWidget);
      final unreadable = b.scope.resolve<LogBuffer>().entries.value.singleWhere(
        (e) => e['event'] == 'onboarding.flag_unreadable',
      );
      expect(unreadable['level'], 'warning');
      expect(unreadable['error_type'], 'StateError');
    });
  });

  group('Esc и настройки на onboarding', () {
    testWidgets('назначение остаётся OnboardingDestination', (tester) async {
      final b = binding(onboarding: const OnboardingStart(show: true));
      await pumpApp(tester, b);
      await tester.tap(_key('onboarding-next'));
      await settleFrames(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pressShortcut(tester, CodeLabShortcut.openSettings);
      await pressShortcut(tester, CodeLabShortcut.openSettings, useMeta: true);
      await settleFrames(tester);

      expect(_key('onboarding-step-permissions'), findsOneWidget);
      expect(
        b.scope.resolve<NavigationCubit>().state,
        const OnboardingDestination(),
      );
    });
  });

  group('отложенный старт агента (D5)', () {
    Future<void> walkToFinish(WidgetTester tester) async {
      await tester.tap(_key('onboarding-next'));
      await settleFrames(tester);
      await tester.tap(_key('onboarding-next'));
      await settleFrames(tester);
      await tester.tap(_key('onboarding-model-later'));
      await settleFrames(tester);
      await tester.tap(_key('onboarding-next'));
      await settleFrames(tester);
    }

    testWidgets('проект восстановлен: агент ждёт конца onboarding, затем '
        'стартует один раз с папкой проекта', (tester) async {
      final b = binding(
        onboarding: const OnboardingStart(show: true),
        project: '/work/app',
      );
      await pumpApp(tester, b);
      await settleFrames(tester);

      // Пока показан onboarding: рабочего места и старта агента нет.
      expect(find.byType(CodeLabShell), findsNothing);
      expect(embeddedCalls, isEmpty);

      await walkToFinish(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(
        embeddedCalls,
        isEmpty,
        reason: 'конец onboarding ещё не наступил',
      );

      await tester.tap(_key('onboarding-project-continue'));
      await settleFrames(tester);

      expect(preferences.marked, 1);
      expect(find.byType(CodeLabShell), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(embeddedCalls, ['/work/app']);
      final completed = b.scope.resolve<LogBuffer>().entries.value.singleWhere(
        (e) => e['event'] == 'onboarding.completed',
      );
      expect(completed['project'], 'restored');

      // Ровно один раз за жизнь app: дальнейшие кадры старт не повторяют.
      await settleFrames(tester);
      expect(embeddedCalls, hasLength(1));
    });

    testWidgets('двойное нажатие: одна запись флага и один старт', (
      tester,
    ) async {
      final b = binding(
        onboarding: const OnboardingStart(show: true),
        project: '/work/app',
      );
      await pumpApp(tester, b);
      await walkToFinish(tester);

      final finish = tester.getCenter(_key('onboarding-project-continue'));
      await tester.tapAt(finish);
      await tester.tapAt(finish);
      await settleFrames(tester);

      expect(preferences.marked, 1);
      expect(embeddedCalls, hasLength(1));
      final completed = b.scope.resolve<LogBuffer>().entries.value.where(
        (e) => e['event'] == 'onboarding.completed',
      );
      expect(completed, hasLength(1));
    });

    testWidgets('флаг не записался: рабочее место показано, старт состоялся', (
      tester,
    ) async {
      preferences.failure = StateError('disk is full at /Users/x');
      final b = binding(
        onboarding: const OnboardingStart(show: true),
        project: '/work/app',
      );
      await pumpApp(tester, b);
      await walkToFinish(tester);

      await tester.tap(_key('onboarding-project-continue'));
      await settleFrames(tester);

      expect(find.byType(CodeLabShell), findsOneWidget);
      expect(embeddedCalls, ['/work/app']);
      final failed = b.scope.resolve<LogBuffer>().entries.value.singleWhere(
        (e) => e['event'] == 'onboarding.save_failed',
      );
      expect(failed['error_type'], 'StateError');
      expect('$failed', isNot(contains('/Users/x')));
    });
  });

  group('шаг «Open a project»: выбор, флаг, старт (D2, D5)', () {
    Future<void> toProjectStep(WidgetTester tester) async {
      for (var i = 0; i < 2; i++) {
        await tester.tap(_key('onboarding-next'));
        await settleFrames(tester);
      }
      await tester.tap(_key('onboarding-model-later'));
      await settleFrames(tester);
      await tester.tap(_key('onboarding-next'));
      await settleFrames(tester);
      expect(_key('onboarding-step-project'), findsOneWidget);
    }

    testWidgets('папка с шага: до перехода агента нет, после — один старт с '
        'этой папкой', (tester) async {
      final flag = _GatedPreferences();
      final b = binding(
        onboarding: const OnboardingStart(show: true),
        flag: flag,
        picker: _PickerOf('/work/app'),
      );
      await pumpApp(tester, b);
      await toProjectStep(tester);

      await tester.tap(_key('start-open-project'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await settleFrames(tester);

      // Выбор принят, флаг ещё пишется: onboarding на месте, агент не
      // стартовал, а удержание триггера записано в журнал.
      expect(flag.pending, isNotNull);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(
        b.scope.resolve<NavigationCubit>().state,
        const OnboardingDestination(),
      );
      expect(embeddedCalls, isEmpty);
      final events = b.scope.resolve<LogBuffer>().entries.value;
      expect(
        events.where((e) => e['event'] == 'project.start_held'),
        hasLength(1),
      );

      flag.pending!.complete();
      await settleFrames(tester);

      expect(find.byType(CodeLabShell), findsOneWidget);
      expect(
        b.scope.resolve<NavigationCubit>().state,
        const WorkbenchDestination(),
      );
      expect(embeddedCalls, ['/work/app']);
      await settleFrames(tester);
      expect(embeddedCalls, hasLength(1));
    });

    testWidgets('выбор не принят (отмена диалога): флаг не пишется', (
      tester,
    ) async {
      final b = binding(
        onboarding: const OnboardingStart(show: true),
        picker: _PickerOf(null),
      );
      await pumpApp(tester, b);
      await toProjectStep(tester);

      await tester.tap(_key('start-open-project'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await settleFrames(tester);

      expect(preferences.marked, 0);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(embeddedCalls, isEmpty);
    });

    testWidgets('другая папка при восстановленном проекте: старт один раз в '
        'выбранной папке, восстановленная не открывается (spec «Другая '
        'папка при восстановленном проекте»)', (tester) async {
      final b = binding(
        onboarding: const OnboardingStart(show: true),
        project: '/work/app',
        picker: _PickerOf('/work/other'),
      );
      await pumpApp(tester, b);
      await toProjectStep(tester);
      expect(_key('onboarding-project-continue'), findsOneWidget);

      await tester.tap(_key('start-open-project'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await settleFrames(tester);
      await settleFrames(tester);

      expect(embeddedCalls, ['/work/other']);
      expect(preferences.marked, 1);
      expect(find.byType(CodeLabShell), findsOneWidget);
      final completed = b.scope.resolve<LogBuffer>().entries.value.singleWhere(
        (e) => e['event'] == 'onboarding.completed',
      );
      expect(completed['project'], 'picker');
    });

    testWidgets('сбой системного выбора папки: флаг не пишется, шаг на месте, '
        'журнал без текста ошибки, диагностика по spec', (tester) async {
      final b = binding(
        onboarding: const OnboardingStart(show: true),
        picker: _PickerOf(null, error: StateError('boom: /secret/location')),
      );
      await pumpApp(tester, b);
      await toProjectStep(tester);

      await tester.tap(_key('start-open-project'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await settleFrames(tester);

      expect(preferences.marked, 0);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(_key('onboarding-step-project'), findsOneWidget);
      expect(embeddedCalls, isEmpty);
      final entries = b.scope.resolve<LogBuffer>().entries.value;
      final failed = entries.singleWhere(
        (e) => e['event'] == 'project.picker_failed',
      );
      expect(failed['error_class'], 'StateError');
      expect(
        entries.where((e) => e['event'] == 'Failed to open the folder picker.'),
        hasLength(1),
      );
      expect('$entries', isNot(contains('boom')));
      expect('$entries', isNot(contains('/secret')));
      expect(
        entries.where((e) => e['event'] == 'onboarding.completed'),
        isEmpty,
      );
    });

    testWidgets('закрытие во время записи флага: без перехода, старта и '
        'события completed', (tester) async {
      final flag = _GatedPreferences();
      final b = binding(
        onboarding: const OnboardingStart(show: true),
        flag: flag,
        picker: _PickerOf('/work/app'),
      );
      await pumpApp(tester, b);
      await toProjectStep(tester);
      await tester.tap(_key('start-open-project'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await settleFrames(tester);
      expect(flag.pending, isNotNull);

      // Выход из app: экран onboarding закрывается, пока флаг ещё пишется.
      await tester.pumpWidget(const SizedBox.shrink());
      flag.pending!.complete();
      await settleFrames(tester);

      expect(embeddedCalls, isEmpty);
      expect(
        b.scope.resolve<NavigationCubit>().state,
        const OnboardingDestination(),
      );
      final events = b.scope.resolve<LogBuffer>().entries.value;
      expect(
        events.where((e) => e['event'] == 'onboarding.completed'),
        isEmpty,
      );
    });

    testWidgets('«Skip for now» при незавершённом восстановлении: рабочее '
        'место, затем один старт в восстановленной папке', (tester) async {
      final restore = Completer<bool>();
      final b = binding(
        onboarding: const OnboardingStart(show: true),
        project: '/work/app',
        directoryExists: (_) => restore.future,
      );
      await pumpApp(tester, b);
      await toProjectStep(tester);
      // Чтение снимка ещё идёт: проекта нет, на шаге «Skip for now».
      expect(_key('onboarding-project-continue'), findsNothing);

      await tester.tap(_key('onboarding-project-skip'));
      await settleFrames(tester);
      expect(preferences.marked, 1);
      expect(find.byType(CodeLabShell), findsOneWidget);
      expect(embeddedCalls, isEmpty);

      restore.complete(true);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await settleFrames(tester);

      expect(embeddedCalls, ['/work/app']);
    });

    testWidgets('в журнале нет путей: бросок папки /tmp/codelab-project-marker '
        '(D8)', (tester) async {
      const marker = '/tmp/codelab-project-marker';
      final b = binding(
        onboarding: const OnboardingStart(show: true),
        localPathKind: (_) async => LocalPathKind.directory,
      );
      await pumpApp(tester, b);
      await toProjectStep(tester);

      tester.widget<OsDropRegion>(find.byType(OsDropRegion)).onDropped([
        marker,
      ]);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await settleFrames(tester);

      final events = b.scope.resolve<LogBuffer>().entries.value.where((e) {
        final name = '${e['event']}';
        return name.startsWith('onboarding.') || name.startsWith('project.');
      });
      expect(events.map((e) => e['event']), contains('onboarding.shown'));
      final completed = events.singleWhere(
        (e) => e['event'] == 'onboarding.completed',
      );
      expect(completed['project'], 'drop');
      // Шаг модели отложен («Set up later»), поэтому `later`. Ключ провайдера
      // и `CODELAB_HOME` в события не попадают: это проверяют
      // `onboarding_cubit_test.dart` (события завершения и шага модели) и
      // `integration_test/onboarding_flow_test.dart` (полный проход с
      // реальным домом).
      expect(completed['model_step'], 'later');
      expect(events.map((e) => e['event']), contains('project.drop'));
      for (final event in events) {
        expect('$event', isNot(contains('codelab-project-marker')));
      }
    });
  });
}

/// Выбор папки с готовым ответом.
final class _PickerOf implements ProjectFolderPicker {
  _PickerOf(this.result, {this.error});

  final String? result;

  /// Если задана — плагин выбора папки бросает её (сбой платформы).
  final Object? error;

  @override
  Future<String?> pickFolder({String? initialDirectory}) async {
    if (error != null) {
      throw error!;
    }
    return result;
  }
}

/// Флаг onboarding, запись которого держит тест: [pending] — незавершённая
/// запись; пока её не завершили, onboarding не может перейти на рабочее место.
final class _GatedPreferences implements OnboardingPreferences {
  Completer<void>? pending;

  @override
  Future<OnboardingLoad> load() async => const OnboardingLoad(false);

  @override
  Future<void> markDone() {
    final gate = pending = Completer<void>();
    return gate.future;
  }
}
