// Страница «Appearance» на устройстве (задача 5.7 change
// `add-app-appearance-page`; spec app-settings «Страница «Appearance»»,
// «Импорт темы на странице «Appearance»», «Режим оформления и темы режимов»,
// «Хранение оформления»; design.md D9, D13).
//
// Сценарий: импорт файла темы во временный `CODELAB_HOME` → карточка выбрана и
// превью показано, действующая тема не изменилась → «Mode» Dark → «Use» →
// app в цветах темы, документ `codelab.app.appearance` называет тему →
// перезапуск app (оформление читается, как в `main`) → первый кадр уже в
// теме. Настоящие `~/.codelab` и диалог файлов не затрагиваются: дом —
// временный `CODELAB_HOME`, выбор файла — двойник порта.
//
// В `feature/*` файл только компилируется (`fvm flutter analyze`); на
// устройстве или симуляторе его запускает `release/<version>` скриптом
// `test:e2e:app:appearance` (AGENTS.md §21).

import 'dart:convert';
import 'dart:io';

import 'package:codelab_client_io/codelab_client_io.dart' show IoThemeLibrary;
import 'package:codelab_desktop/app/appearance/app_appearance_start.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/core/platform/app_appearance_preferences.dart';
import 'package:codelab_desktop/core/platform/theme_file_picker.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/e2e_agent.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

/// Двойник выбора файла: системный диалог на устройстве тест не закроет.
final class _PathPicker implements ThemeFilePicker {
  _PathPicker(this.path);

  final String path;

  @override
  Future<String?> pickThemeFile() async => path;
}

/// Акцент действующей темы в первом кадре рабочего места.
Color _accent(WidgetTester tester) => FluentTheme.of(
  tester.element(find.byType(CodeLabPromptComposer, skipOffstage: false)),
).accentColor.normal;

const _night = {
  'name': 'acme-night',
  'extends': 'dark',
  'colors': {'accent': '#b4a0ff', 'success': '#a6e3a1'},
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'import acme-night, preview, Use under Dark, restart keeps the theme'
    '${E2eAgent.current.skipStdioProcessNote}',
    skip: E2eAgent.current.skipStdioProcess,
    (tester) async {
      final home = File(E2eAgent.current.profilesPath).parent.path;
      final downloads = await Directory.systemTemp.createTemp(
        'codelab_appearance_e2e_',
      );
      addTearDown(() async {
        if (await downloads.exists()) await downloads.delete(recursive: true);
      });
      final source = File('${downloads.path}/night.json')
        ..writeAsStringSync(jsonEncode(_night));
      final library = IoThemeLibrary(home: home);

      await tester.pumpWidget(
        E2eAgent.current.bootstrap(
          themeLibrary: library,
          themeFilePicker: _PathPicker(source.path),
        ),
      );
      await tester.pumpAndSettle();

      // Импорт: карточка появилась и выбрана, действующая тема прежняя.
      await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
      await tester.pumpAndSettle();
      await tester.tap(_key('settings-nav-appearance'));
      await tester.pumpAndSettle();
      final before = _accent(tester);
      await tester.tap(_key('settings-appearance-import'));
      await tester.pumpAndSettle();
      // Идентификатор карточки живёт в пространстве вида: у импортированной
      // темы это `custom-<имя>`, у встроенных — `light`, `dark`,
      // `high-contrast` (change `add-app-appearance-page`, D9а).
      expect(
        _key('settings-appearance-theme-custom-acme-night'),
        findsOneWidget,
      );
      expect(find.text('Use acme-night'), findsOneWidget);
      expect(
        File('$home/themes/acme-night.json').existsSync(),
        isTrue,
        reason: 'импорт копирует файл в каталог тем',
      );
      expect(_accent(tester), before);

      // «Mode» Dark и «Use»: app рисуется в теме.
      await tester.tap(_key('settings-appearance-mode-dark'));
      await tester.pumpAndSettle();
      await tester.tap(_key('settings-appearance-use'));
      await tester.pumpAndSettle();
      expect(_accent(tester), const Color(0xFFB4A0FF));
      final stored =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  kAppAppearanceKey,
                )!,
              )
              as Map<String, Object?>;
      expect(stored['dark_theme'], 'acme-night');
      expect(stored['mode'], 'dark');

      // Перезапуск: оформление читается так же, как в `main` до `runApp`.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
      final start = await AppAppearanceStart.resolve(
        load: await const SharedPreferencesAppAppearancePreferences().load(),
        library: library,
      );
      await tester.pumpWidget(
        E2eAgent.current.bootstrap(
          appearance: start,
          themeLibrary: library,
          themeFilePicker: _PathPicker(source.path),
        ),
      );
      await tester.pumpAndSettle();
      expect(_accent(tester), const Color(0xFFB4A0FF));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );
}
