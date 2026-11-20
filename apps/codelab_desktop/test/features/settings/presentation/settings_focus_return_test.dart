// Возврат фокуса из настроек при управлении мышью (spec app-settings
// «Переход в настройки и обратно»: «После возврата фокус SHALL восстанавливаться
// в элементе, где он был до ухода, если тот ещё существует, иначе — в композере
// активной сессии»; сценарий «… после «Back» фокус снова в композере»).
//
// Дефект ручной проверки на macOS: клик в композер → «Настройки» → «Назад» →
// без клика ⌘K ничего не делал. Тесты идут тем же путём, только мышью, и
// проверяют поведение: фокус внутри рабочего места и сочетание срабатывает.

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/press_shortcut.dart';
import '../../../support/start_agent.dart';
import '../../../support/test_app_scope.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 1400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  late CodeLabTestBinding binding;

  Future<void> pump(WidgetTester tester) async {
    binding = CodeLabTestBinding(
      project: '/workspace',
      transport: FakeAcpTransport(),
      stdioTransportFactory: (_) => FakeAcpTransport(),
      settingsPages: const SettingsPages(available: {SettingsPage.connection}),
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await tester.runAsync(() => cubit.startWith());
    await tester.pump();
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }

  Future<void> frames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder composerField() => find
      .descendant(
        of: find.byType(CodeLabPromptComposer),
        matching: find.byType(EditableText),
      )
      .last;

  bool focusInComposer() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<CodeLabPromptComposer>() !=
      null;

  /// Путь мышью. [clickFocusesButton] моделирует macOS: клик по кнопке берёт на
  /// неё фокус, и «узел до ухода» в момент перехода — не композер.
  Future<void> toSettingsAndBack(
    WidgetTester tester, {
    bool clickFocusesButton = false,
  }) async {
    if (clickFocusesButton) {
      Focus.of(
        tester.element(find.byKey(CodeLabSessionSidebar.settingsKey).first),
      ).requestFocus();
      await tester.pump();
    }
    await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey).first);
    await frames(tester);
    expect(find.byKey(CodeLabSettingsNavigation.backKey), findsOneWidget);
    await tester.tap(find.byKey(CodeLabSettingsNavigation.backKey));
    await frames(tester);
    expect(find.byKey(CodeLabSettingsNavigation.backKey), findsNothing);
  }

  Future<void> expectPaletteOpens(WidgetTester tester) async {
    await pressShortcut(tester, CodeLabShortcut.commandPalette);
    await frames(tester);
    expect(find.byType(CodeLabCommandPaletteSurface), findsOneWidget);
  }

  testWidgets('мышью: композер → «Настройки» → «Назад»: фокус в композере, '
      'сочетание рабочего места работает без клика', (tester) async {
    await pump(tester);
    await tester.tap(composerField());
    await tester.pump();
    expect(focusInComposer(), isTrue);

    await toSettingsAndBack(tester, clickFocusesButton: true);

    expect(focusInComposer(), isTrue, reason: 'фокус вернулся в композер');
    await expectPaletteOpens(tester);
    await tearDownApp(tester);
  });

  testWidgets('без фокуса до ухода: после «Назад» фокус в композере', (
    tester,
  ) async {
    await pump(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await toSettingsAndBack(tester);

    expect(focusInComposer(), isTrue);
    await expectPaletteOpens(tester);
    await tearDownApp(tester);
  });
}
