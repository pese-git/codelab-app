// Шаг «Open a project» экрана onboarding (задача 3.1 change
// `add-onboarding-project-step`; spec app-onboarding «Шаг «Open a project»»,
// «Шаги onboarding и переходы»; design.md D1, D3, D4, D6, D7).
//
// Идёт через `CodeLabTestBinding` и `CodeLabApp`: шаг читает состояние рабочего
// места (`CodeLabShellState`: профиль окна, недавние, отказ броска) и вызывает
// порт, поэтому подделки здесь — швы графа (выбор папки, вид брошенного пути,
// хранилище недавних, открыватель встроенного агента), а не отдельные Cubit-ы.
// Перетаскивание из ОС тест не эмулирует плагином: он находит `OsDropRegion`
// и вызывает его колбэки так, как их вызвал бы плагин (как
// `open_project_screen_test.dart`).
//
// Проверяется поведение (какие блоки видны, что вызвано), а не пиксели.

import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/onboarding/onboarding_start.dart';
import 'package:codelab_desktop/core/platform/local_path_kind.dart';
import 'package:codelab_desktop/core/platform/os_drop_region.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/features/onboarding/presentation/onboarding_screen.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_setup/codelab_setup.dart' show ProviderReady;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../support/fake_onboarding.dart';
import '../../../support/press_shortcut.dart';
import '../../../support/test_app_scope.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

/// Системный выбор папки: считает вызовы; ответ — [result] либо ручной затвор.
final class _Picker implements ProjectFolderPicker {
  var picks = 0;
  String? result;
  Completer<String?>? gate;

  @override
  Future<String?> pickFolder({String? initialDirectory}) {
    picks++;
    final held = gate;
    return held != null ? held.future : Future.value(result);
  }
}

const _stdioProfile = ConnectionProfile.stdio(
  id: 'dev',
  label: 'dev',
  command: '/usr/local/bin/codelab-agent',
  args: ['serve', '--stdio', '--token', 'abc'],
);

void main() {
  late FakeOnboardingPreferences preferences;
  late _Picker picker;
  late List<String> embeddedCalls;
  final kinds = <String, LocalPathKind>{};

  setUp(() {
    preferences = FakeOnboardingPreferences();
    picker = _Picker();
    embeddedCalls = [];
    kinds.clear();
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
    String? project,
    List<String> recents = const [],
    Locale locale = const Locale('en'),
  }) => CodeLabTestBinding(
    onboarding: const OnboardingStart(show: true),
    // Готовый провайдер: шаг модели пропускается, до проекта три «Next».
    onboardingProbe: FakeOnboardingProbe(
      onboardingFacts(const ProviderReady('llm/m1')),
    ),
    onboardingPreferences: preferences,
    project: project,
    recentProjects: recents,
    locale: locale,
    stdioDefault: false,
    projectFolderPicker: picker,
    localPathKind: (path) async => kinds[path] ?? LocalPathKind.missing,
    embeddedOpener: ({required cwd, required hostProfile}) async {
      embeddedCalls.add(cwd);
      throw StateError('the embedded agent is not part of this test');
    },
  );

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await frames(tester);
  }

  Future<CodeLabShellCubit> pumpApp(
    WidgetTester tester,
    CodeLabTestBinding b,
  ) async {
    await tester.pumpWidget(
      b.bootstrap(child: const CodeLabApp(startOnLaunch: true)),
    );
    await frames(tester);
    return b.scope.resolve<CodeLabShellCubit>();
  }

  Future<void> tapNext(WidgetTester tester) async {
    await tester.ensureVisible(_key('onboarding-next'));
    await tester.tap(_key('onboarding-next'));
    await frames(tester);
  }

  /// Welcome → Permissions → Privacy → Open a project.
  Future<void> toProject(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tapNext(tester);
    }
    expect(_key('onboarding-step-project'), findsOneWidget);
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }

  OsDropRegion region(WidgetTester tester) =>
      tester.widget<OsDropRegion>(find.byType(OsDropRegion));

  Finder inKey(String key, String text) => find.descendant(
    of: _key(key),
    matching: find.textContaining(text, findRichText: true),
  );

  group('строка шагов и кнопки', () {
    testWidgets('пять подписей; на «Privacy» — «Next», «Start using CodeLab» '
        'нет нигде', (tester) async {
      await pumpApp(tester, binding());
      for (final label in [
        'What CodeLab does',
        'Permissions',
        'Choose a model',
        'Privacy',
        'Open a project',
      ]) {
        expect(inKey('onboarding-steps', label), findsOneWidget, reason: label);
      }
      await tapNext(tester);
      await tapNext(tester);
      expect(_key('onboarding-step-privacy'), findsOneWidget);
      expect(_key('onboarding-next'), findsOneWidget);
      expect(_key('onboarding-finish'), findsNothing);

      await tapNext(tester);
      expect(_key('onboarding-next'), findsNothing);
      expect(_key('onboarding-finish'), findsNothing);
      expect(find.text('Start using CodeLab'), findsNothing);
      await tearDownApp(tester);
    });
  });

  group('содержимое шага', () {
    testWidgets('новая установка: все блоки, фокус на заголовке, агент не '
        'запущен', (tester) async {
      await pumpApp(tester, binding());
      await toProject(tester);

      final title = tester.widget<Focus>(_key('onboarding-title'));
      expect(title.focusNode!.hasPrimaryFocus, isTrue);
      expect(inKey('onboarding-title', 'Open a project'), findsOneWidget);
      expect(
        find.textContaining("The agent can't read or write outside it."),
        findsOneWidget,
      );
      expect(inKey('onboarding-step-project', 'Open folder…'), findsOneWidget);
      expect(inKey('onboarding-step-project', 'Ctrl+O'), findsOneWidget);
      expect(
        inKey('open-project-drop-zone', 'Drop a folder here to open it'),
        findsOneWidget,
      );
      expect(inKey('open-project-agent', 'Embedded agent'), findsOneWidget);
      expect(_key('open-project-agent-settings'), findsNothing);
      expect(_key('onboarding-back'), findsOneWidget);
      expect(_key('onboarding-project-skip'), findsOneWidget);
      expect(find.text('Skip for now'), findsOneWidget);
      expect(_key('onboarding-project-continue'), findsNothing);
      expect(_key('onboarding-project-recents'), findsNothing);
      expect(_key('onboarding-project-last'), findsNothing);
      expect(_key('open-project-info'), findsNothing);
      expect(find.text('New session needs a folder'), findsNothing);
      expect(embeddedCalls, isEmpty);
      await tearDownApp(tester);
    });

    testWidgets('проект восстановлен: Last project с путём, Continue in app, '
        'Skip for now нет, восстановленного нет среди недавних', (
      tester,
    ) async {
      await pumpApp(
        tester,
        binding(project: '/work/app', recents: ['/work/app', '/work/b']),
      );
      await toProject(tester);

      expect(
        inKey('onboarding-project-last', 'Last project: app'),
        findsOneWidget,
      );
      expect(inKey('onboarding-project-last', '/work/app'), findsOneWidget);
      expect(_key('onboarding-project-continue'), findsOneWidget);
      expect(find.text('Continue in app'), findsOneWidget);
      expect(_key('onboarding-project-skip'), findsNothing);
      expect(inKey('onboarding-project-recents', '/work/b'), findsOneWidget);
      expect(inKey('onboarding-project-recents', '/work/app'), findsNothing);
      // Кадр 07d.2: основная кнопка — «Continue in …», «Open folder…»
      // вторичная (tasks.md 3.7, сверка 7.1).
      expect(
        tester.widget<CodeLabButton>(_key('start-open-project')).emphasis,
        CodeLabButtonEmphasis.secondary,
      );
      expect(embeddedCalls, isEmpty);
      await tearDownApp(tester);
    });

    testWidgets('без восстановленного проекта «Open folder…» — основная', (
      tester,
    ) async {
      await pumpApp(tester, binding());
      await toProject(tester);

      expect(
        tester.widget<CodeLabButton>(_key('start-open-project')).emphasis,
        CodeLabButtonEmphasis.primary,
      );
      await tearDownApp(tester);
    });

    testWidgets('не более пяти недавних, в порядке недавних', (tester) async {
      final recents = [for (var i = 1; i <= 7; i++) '/work/p$i'];
      await pumpApp(tester, binding(recents: recents));
      await toProject(tester);

      expect(_key('onboarding-project-recents'), findsOneWidget);
      expect(find.text('Recent projects'), findsOneWidget);
      for (var i = 1; i <= 5; i++) {
        expect(
          inKey('onboarding-project-recents', '/work/p$i'),
          findsOneWidget,
          reason: 'p$i',
        );
      }
      for (var i = 6; i <= 7; i++) {
        expect(
          inKey('onboarding-project-recents', '/work/p$i'),
          findsNothing,
          reason: 'p$i',
        );
      }
      // Ключи записей закреплены spec: позиция в блоке с нуля.
      for (var i = 0; i < 5; i++) {
        expect(_key('onboarding-project-recent-$i'), findsOneWidget);
      }
      expect(_key('onboarding-project-recent-5'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('внешний профиль: имя, команда без аргументов, фраза про '
        'внешнего агента', (tester) async {
      final cubit = await pumpApp(tester, binding());
      await cubit.useProfile(_stdioProfile);
      await toProject(tester);

      expect(inKey('open-project-agent', 'dev'), findsOneWidget);
      expect(
        inKey(
          'open-project-agent',
          'stdio · /usr/local/bin/codelab-agent · profile of this window',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('--token'), findsNothing);
      expect(find.textContaining('abc'), findsNothing);
      expect(
        find.textContaining(
          'An external agent applies its own rules to files outside it.',
        ),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });
  });

  group('выход без выбора', () {
    testWidgets('«Skip for now»: флаг записан, рабочее место без агента, '
        'в журнале project: skipped', (tester) async {
      final b = binding();
      await pumpApp(tester, b);
      await toProject(tester);
      expect(preferences.marked, 0);

      await tester.tap(_key('onboarding-project-skip'));
      await frames(tester);

      expect(preferences.marked, 1);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(_key('open-project-screen'), findsOneWidget);
      expect(embeddedCalls, isEmpty);
      final completed = b.scope.resolve<LogBuffer>().entries.value.singleWhere(
        (e) => e['event'] == 'onboarding.completed',
      );
      expect(completed['project'], 'skipped');
      await tearDownApp(tester);
    });

    testWidgets('«Back» с шага проекта ведёт на «Privacy», флаг не записан', (
      tester,
    ) async {
      await pumpApp(tester, binding());
      await toProject(tester);

      await tester.tap(_key('onboarding-back'));
      await frames(tester);

      expect(_key('onboarding-step-privacy'), findsOneWidget);
      expect(preferences.marked, 0);
      await tearDownApp(tester);
    });
  });

  group('выбор папки', () {
    testWidgets('«Open folder…»: диалог, принятая папка завершает onboarding, '
        'флаг записан, агент открыт один раз', (tester) async {
      picker.result = '/work/app';
      final cubit = await pumpApp(tester, binding());
      await toProject(tester);

      await tester.tap(_key('start-open-project'));
      await settle(tester);

      expect(picker.picks, 1);
      expect(preferences.marked, 1);
      expect(cubit.state.selectedProjectPath, '/work/app');
      expect(embeddedCalls, ['/work/app']);
      await tearDownApp(tester);
    });

    testWidgets('отмена диалога: тот же шаг, флаг не записан', (tester) async {
      final cubit = await pumpApp(tester, binding());
      await toProject(tester);

      await pressShortcut(tester, CodeLabShortcut.openFolder);
      await settle(tester);

      expect(picker.picks, 1);
      expect(_key('onboarding-step-project'), findsOneWidget);
      expect(preferences.marked, 0);
      expect(cubit.state.selectedProjectPath, isNull);
      expect(embeddedCalls, isEmpty);
      await tearDownApp(tester);
    });

    testWidgets('недавний проект: выбор и завершение', (tester) async {
      final cubit = await pumpApp(
        tester,
        binding(recents: ['/work/a', '/work/b']),
      );
      await toProject(tester);

      await tester.tap(_key('onboarding-project-recent-1'));
      await settle(tester);

      expect(cubit.state.selectedProjectPath, '/work/b');
      expect(preferences.marked, 1);
      expect(embeddedCalls, ['/work/b']);
      await tearDownApp(tester);
    });

    testWidgets('пока диалог открыт, «Open folder…» и недавние неактивны', (
      tester,
    ) async {
      picker.gate = Completer<String?>();
      await pumpApp(tester, binding(recents: ['/work/a']));
      await toProject(tester);
      expect(
        tester.widget<CodeLabButton>(_key('start-open-project')).onPressed,
        isNotNull,
      );

      await tester.tap(_key('start-open-project'));
      await frames(tester);

      expect(
        tester.widget<CodeLabButton>(_key('start-open-project')).onPressed,
        isNull,
      );
      expect(
        tester.widget<Button>(_key('onboarding-project-recent-0')).onPressed,
        isNull,
      );
      await tester.tap(_key('start-open-project'));
      await frames(tester);
      expect(picker.picks, 1);

      picker.gate!.complete(null);
      await settle(tester);
      expect(
        tester.widget<CodeLabButton>(_key('start-open-project')).onPressed,
        isNotNull,
      );
      await tearDownApp(tester);
    });

    testWidgets('пока пишется флаг, «Open folder…» и недавние неактивны', (
      tester,
    ) async {
      picker.result = '/work/app';
      preferences.gate = Completer<void>();
      await pumpApp(tester, binding(recents: ['/work/a']));
      await toProject(tester);

      await tester.tap(_key('start-open-project'));
      await settle(tester);

      expect(preferences.marked, 1);
      expect(_key('onboarding-step-project'), findsOneWidget);
      expect(
        tester.widget<CodeLabButton>(_key('start-open-project')).onPressed,
        isNull,
      );
      expect(
        tester.widget<Button>(_key('onboarding-project-recent-0')).onPressed,
        isNull,
      );

      preferences.gate!.complete();
      await settle(tester);
      await tearDownApp(tester);
    });

    testWidgets('навигация во время выбора: Back, Skip и Ctrl+O не '
        'действуют, диалог вызван один раз', (tester) async {
      picker.gate = Completer<String?>();
      await pumpApp(tester, binding());
      await toProject(tester);

      await tester.tap(_key('start-open-project'));
      await frames(tester);
      await tester.tap(_key('onboarding-back'));
      await tester.tap(_key('onboarding-project-skip'));
      await pressShortcut(tester, CodeLabShortcut.openFolder);
      await frames(tester);

      expect(picker.picks, 1);
      expect(_key('onboarding-step-project'), findsOneWidget);
      expect(preferences.marked, 0);

      picker.gate!.complete(null);
      await settle(tester);
      expect(_key('onboarding-step-project'), findsOneWidget);
      await tearDownApp(tester);
    });
  });

  group('перетаскивание (колбэки найденного OsDropRegion)', () {
    testWidgets('региона нет на других шагах', (tester) async {
      await pumpApp(tester, binding());
      expect(find.byType(OsDropRegion), findsNothing);
      await tapNext(tester);
      await tapNext(tester);
      expect(_key('onboarding-step-privacy'), findsOneWidget);
      expect(find.byType(OsDropRegion), findsNothing);
      await toProjectFromPrivacy(tester, tapNext);
      expect(find.byType(OsDropRegion), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('брошенная папка завершает onboarding', (tester) async {
      kinds['/work/app'] = LocalPathKind.directory;
      final cubit = await pumpApp(tester, binding());
      await toProject(tester);

      region(tester).onDropped(['/work/app']);
      await settle(tester);

      expect(cubit.state.selectedProjectPath, '/work/app');
      expect(preferences.marked, 1);
      expect(embeddedCalls, ['/work/app']);
      await tearDownApp(tester);
    });

    testWidgets('брошенный файл: текст в зоне, шаг на месте, флага нет', (
      tester,
    ) async {
      kinds['/work/app/README.md'] = LocalPathKind.file;
      final cubit = await pumpApp(tester, binding());
      await toProject(tester);

      region(tester).onDropped(['/work/app/README.md']);
      await settle(tester);

      expect(
        inKey(
          'open-project-drop-message',
          "That's a file. Drop a folder to open it as a project.",
        ),
        findsOneWidget,
      );
      expect(_key('onboarding-step-project'), findsOneWidget);
      expect(preferences.marked, 0);
      expect(cubit.state.selectedProjectPath, isNull);
      expect(embeddedCalls, isEmpty);

      // Новый вход перетаскивания снимает отказ и подсвечивает зону.
      region(tester).onEntered?.call();
      await tester.pump();
      expect(_key('open-project-drop-message'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('несколько элементов: Drop one folder at a time.', (
      tester,
    ) async {
      kinds['/work/a'] = LocalPathKind.directory;
      kinds['/work/b'] = LocalPathKind.directory;
      final cubit = await pumpApp(tester, binding());
      await toProject(tester);

      region(tester).onDropped(['/work/a', '/work/b']);
      await settle(tester);

      expect(
        inKey('open-project-drop-message', 'Drop one folder at a time.'),
        findsOneWidget,
      );
      expect(preferences.marked, 0);
      expect(cubit.state.selectedProjectPath, isNull);
      await tearDownApp(tester);
    });
  });

  group('Ctrl+O', () {
    testWidgets('на шаге «Permissions» и «Privacy» выбор не открывается', (
      tester,
    ) async {
      await pumpApp(tester, binding());
      await tapNext(tester);
      expect(_key('onboarding-step-permissions'), findsOneWidget);
      await pressShortcut(tester, CodeLabShortcut.openFolder);
      await tapNext(tester);
      expect(_key('onboarding-step-privacy'), findsOneWidget);
      await pressShortcut(tester, CodeLabShortcut.openFolder);
      await frames(tester);

      expect(picker.picks, 0);
      await tearDownApp(tester);
    });

    testWidgets('при открытом документе на «Privacy» не действует', (
      tester,
    ) async {
      await pumpApp(tester, binding());
      await tapNext(tester);
      await tapNext(tester);
      await tester.ensureVisible(_key('onboarding-privacy-policy'));
      await tester.tap(_key('onboarding-privacy-policy'));
      await frames(tester);
      expect(_key('onboarding-document'), findsOneWidget);

      await pressShortcut(tester, CodeLabShortcut.openFolder);
      await frames(tester);

      expect(picker.picks, 0);
      await tearDownApp(tester);
    });

    testWidgets('⌘O на шаге проекта открывает выбор папки', (tester) async {
      await pumpApp(tester, binding());
      await toProject(tester);

      await pressShortcut(tester, CodeLabShortcut.openFolder, useMeta: true);
      await settle(tester);

      expect(picker.picks, 1);
      await tearDownApp(tester);
    });

    testWidgets('⌘N на шаге проекта не привязан', (tester) async {
      await pumpApp(tester, binding());
      await toProject(tester);

      await pressShortcut(tester, CodeLabShortcut.newSession);
      await settle(tester);

      expect(picker.picks, 0);
      expect(_key('onboarding-step-project'), findsOneWidget);
      await tearDownApp(tester);
    });
  });

  group('русский интерфейс и низкое окно', () {
    testWidgets('тёмная тема, 800×600, пять недавних: без переполнения, '
        'всё достижимо прокруткой', (tester) async {
      final view = tester.view;
      view.physicalSize = const Size(800, 600);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpApp(
        tester,
        binding(
          locale: const Locale('ru'),
          recents: [for (var i = 1; i <= 5; i++) '/work/project-$i'],
        ),
      );
      await toProject(tester);

      expect(find.text('Откройте проект'), findsWidgets);
      expect(find.text('Недавние проекты'), findsOneWidget);
      expect(find.text('Пока пропустить'), findsOneWidget);
      expect(find.text('Open folder…'), findsNothing);
      expect(find.text('Skip for now'), findsNothing);
      for (final key in [
        'start-open-project',
        'onboarding-project-recent-4',
        'onboarding-back',
        'onboarding-project-skip',
      ]) {
        await tester.ensureVisible(_key(key));
        await tester.pump();
        expect(_key(key), findsOneWidget, reason: key);
      }
      expect(tester.takeException(), isNull);
      await tearDownApp(tester);
    });
  });
}

/// «Next» на «Privacy» ведёт на шаг проекта (вынесено, чтобы тест региона
/// читался как последовательность шагов).
Future<void> toProjectFromPrivacy(
  WidgetTester tester,
  Future<void> Function(WidgetTester) tapNext,
) async {
  await tapNext(tester);
  expect(_key('onboarding-step-project'), findsOneWidget);
}
