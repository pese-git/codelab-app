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

import 'package:codelab_desktop/app/navigation/app_destination.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/onboarding/onboarding_start.dart';
import 'package:codelab_desktop/core/platform/onboarding_preferences.dart';
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

  CodeLabTestBinding binding({OnboardingStart? onboarding, String? project}) =>
      CodeLabTestBinding(
        onboarding: onboarding,
        onboardingProbe: probe,
        onboardingPreferences: preferences,
        project: project,
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
    }

    testWidgets('проект восстановлен: агент ждёт «Start using CodeLab», затем '
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

      await tester.tap(_key('onboarding-finish'));
      await settleFrames(tester);

      expect(preferences.marked, 1);
      expect(find.byType(CodeLabShell), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(embeddedCalls, ['/work/app']);

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

      final finish = tester.getCenter(_key('onboarding-finish'));
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

      await tester.tap(_key('onboarding-finish'));
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
}
