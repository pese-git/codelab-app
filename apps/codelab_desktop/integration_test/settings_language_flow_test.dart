// Смена языка интерфейса на устройстве (задача 6.6 change
// `add-desktop-localization`; design.md D9, D2).
//
// Сценарий: живая сессия с ответом агента и черновиком в композере →
// «Settings» → «General» → `Русский` → возврат на рабочее место: тексты на
// русском без перезапуска, сессия и черновик на месте → `English` → снова
// английский. Язык машины не важен: `flutter_test_config.dart` кладёт
// `codelab.app.language = en` в подменённое хранилище перед каждым тестом.
//
// В feature-ветке файл только проходит анализатор; на
// устройстве или симуляторе его запускает `release/<version>` скриптом
// `test:e2e:app:language` (AGENTS.md §21).

import 'dart:io';

import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/e2e_agent.dart';

/// Ключ выбора языка в хранилище; значение пишет `AppLanguageCubit`.
const _languageKey = 'codelab.app.language';

Future<void> _openSettingsGeneral(WidgetTester tester) async {
  await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('settings-nav-general')));
  await tester.pumpAndSettle();
}

Future<void> _chooseLanguage(WidgetTester tester, String optionKey) async {
  // Выбор языка лежит ниже блока «Agent defaults» страницы General: у
  // агента с реестром настроек (Dart-агент, встроенный) он за краем
  // области прокрутки, и `tap` без прокрутки не попадает по кнопке
  // (ряды настроек агента на странице General).
  final option = find.byKey(ValueKey(optionKey));
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _backToWorkbench(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

/// Текст в поле композера; композер под настройками скрыт `Offstage`
/// (дерево живёт), поэтому поиск без пропуска скрытого.
String _composerText(WidgetTester tester) => tester
    .widget<TextBox>(
      find.byKey(const ValueKey('composer-text-box'), skipOffstage: false),
    )
    .controller!
    .text;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'switching the language in General re-renders a live workbench in '
    'Russian and back to English without a restart; session and draft stay'
    '${E2eAgent.current.skipStdioProcessNote}',
    skip: E2eAgent.current.skipStdioProcess,
    (tester) async {
      await tester.pumpWidget(E2eAgent.current.bootstrap());
      await tester.pumpAndSettle();

      final agentDirectory = await Directory.systemTemp.createTemp(
        'codelab_app_language_e2e_',
      );
      addTearDown(() async {
        if (await agentDirectory.exists()) {
          await agentDirectory.delete(recursive: true);
        }
      });
      final launch = await E2eAgent.current.launch(agentDirectory);
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      await launch.connect(tester, shellCubit);

      // Живая сессия с ответом агента: подпись «Connected» и текст ленты.
      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('composer-text-box')),
        'hello from the e2e test',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send-button')));
      await tester.pump();
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (shellCubit.state.isPromptSubmitting &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.text('hello from compatible stdio agent'), findsWidgets);
      expect(find.text('Connected'), findsWidgets);

      // Черновик, который не должен пропасть при смене языка (D2, D5).
      // Явный tap на поле перед `enterText`: после нажатия «Send» фокус
      // остаётся на кнопке, и `enterText` без него молча ничего не вводит
      // (тот же обход, что в prompt_queue_flow_test.dart).
      const draft = 'draft that must survive';
      await tester.tap(find.byKey(const ValueKey('composer-text-box')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('composer-text-box')),
        draft,
      );
      await tester.pump();
      expect(_composerText(tester), draft, reason: 'черновик не введён');

      // English → Русский.
      await _openSettingsGeneral(tester);
      await _chooseLanguage(tester, 'settings-language-ru');
      // Выбор применён сразу и записан в хранилище.
      expect(
        (await SharedPreferences.getInstance()).getString(_languageKey),
        'ru',
      );
      expect(find.text('Настройки'), findsWidgets);
      await _backToWorkbench(tester);

      // Рабочее место на русском: те же объекты, перезапуска не было.
      expect(find.text('Подключено'), findsWidgets);
      expect(find.text('Connected'), findsNothing);
      expect(find.text('hello from compatible stdio agent'), findsWidgets);
      expect(find.text('hello from the e2e test'), findsWidgets);
      expect(_composerText(tester), draft);
      expect(shellCubit.state.isPromptSubmitting, isFalse);

      // Русский → English.
      await _openSettingsGeneral(tester);
      await _chooseLanguage(tester, 'settings-language-en');
      expect(
        (await SharedPreferences.getInstance()).getString(_languageKey),
        'en',
      );
      await _backToWorkbench(tester);
      expect(find.text('Connected'), findsWidgets);
      expect(find.text('Подключено'), findsNothing);
      expect(find.text('hello from compatible stdio agent'), findsWidgets);
      expect(_composerText(tester), draft);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );
}
