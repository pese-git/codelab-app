// Красные тесты подключения языка к app (задача 1.5 change
// `add-desktop-localization`; design.md D2, D9; spec app-settings «Ввод
// пользователя сохраняется», R6).
//
// `FluentApp` получает язык из `AppLanguageCubit`, а при смене языка не
// пересоздаётся: меняется только `locale`, поэтому State виджетов (ввод
// композера, фокус) сохраняется. Делегат кита `CodeLabLocalizations`
// появляется в задаче 1.8; его проверка добавляется вместе с ним.

import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/language/app_language_cubit.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app_scope.dart';

Finder _composerField() => find
    .descendant(
      of: find.byType(CodeLabPromptComposer),
      matching: find.byType(EditableText),
    )
    .last;

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1400, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  Future<void> pumpApp(WidgetTester tester, CodeLabTestBinding binding) =>
      tester.pumpWidget(
        binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
      );

  AppLocalizations strings(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(CodeLabPromptComposer)));

  testWidgets('FluentApp получает en и ru и делегаты app и Fluent', (
    tester,
  ) async {
    final binding = CodeLabTestBinding(project: '/workspace');
    await pumpApp(tester, binding);

    final app = tester.widget<FluentApp>(find.byType(FluentApp));
    expect(app.supportedLocales, const [Locale('en'), Locale('ru')]);
    expect(
      app.localizationsDelegates,
      containsAll(AppLocalizations.localizationsDelegates),
    );
    final context = tester.element(find.byType(CodeLabPromptComposer));
    expect(FluentLocalizations.of(context), isNotNull);
  });

  testWidgets('CodeLabTestBinding() даёт en в первом кадре', (tester) async {
    final binding = CodeLabTestBinding(project: '/workspace');
    await pumpApp(tester, binding);

    expect(
      tester.widget<FluentApp>(find.byType(FluentApp)).locale,
      const Locale('en'),
    );
    expect(strings(tester).localeName, 'en');
  });

  testWidgets('CodeLabTestBinding(locale: ru) даёт ru в первом кадре', (
    tester,
  ) async {
    final binding = CodeLabTestBinding(
      project: '/workspace',
      locale: const Locale('ru'),
    );
    await pumpApp(tester, binding);

    // Первый кадр сразу на языке шва, без кадра на английском.
    expect(
      tester.widget<FluentApp>(find.byType(FluentApp)).locale,
      const Locale('ru'),
    );
    expect(strings(tester).localeName, 'ru');
  });

  testWidgets('select(ru) не пересоздаёт FluentApp: ввод и фокус сохраняются', (
    tester,
  ) async {
    final binding = CodeLabTestBinding(project: '/workspace');
    await pumpApp(tester, binding);
    await tester.enterText(_composerField(), 'hello');
    await tester.pump();

    final appElement = tester.element(find.byType(FluentApp));
    final composerState = tester.state(find.byType(CodeLabPromptComposer));
    final focused = tester
        .widget<EditableText>(_composerField())
        .focusNode
        .hasFocus;

    await binding.scope.resolve<AppLanguageCubit>().select(
      AppLanguagePreference.ru,
    );
    await tester.pumpAndSettle();

    expect(strings(tester).localeName, 'ru');
    expect(tester.element(find.byType(FluentApp)), same(appElement));
    expect(
      tester.state(find.byType(CodeLabPromptComposer)),
      same(composerState),
    );
    expect(
      tester.widget<EditableText>(_composerField()).controller.text,
      'hello',
    );
    expect(
      tester.widget<EditableText>(_composerField()).focusNode.hasFocus,
      focused,
    );
    // Агенту при смене языка ничего не отправляется.
    expect(binding.transport.sentMessages, isEmpty);
  });
}
