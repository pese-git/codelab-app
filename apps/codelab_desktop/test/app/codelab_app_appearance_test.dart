// Красные тесты подключения оформления к app (задача 4.7 change
// `add-app-appearance-page`; design.md D4, D12, D13; spec app-settings «Режим
// оформления и темы режимов»: «Тёмная система», первый кадр в сохранённом
// оформлении; «Хранение оформления»: файл темы не прочитан за 1 с).
//
// `FluentApp` получает `theme`, `darkTheme` и `themeMode` из
// `AppAppearanceCubit` и НЕ пересоздаётся при смене оформления: State
// виджетов (ввод композера, фокус) сохраняется. Первый кадр рисуется уже в
// итоговом оформлении из шва `AppAppearanceStart` — без мигания темы.

import 'dart:async';
import 'dart:convert';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/appearance/app_appearance_cubit.dart';
import 'package:codelab_desktop/app/appearance/app_appearance_start.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/core/platform/app_appearance_preferences.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../support/test_app_scope.dart';

Finder _composerField() => find
    .descendant(
      of: find.byType(CodeLabPromptComposer),
      matching: find.byType(EditableText),
    )
    .last;

/// Библиотека, у которой чтение не завершается: файл «не прочитан за 1 с».
final class _HangingLibrary implements ThemeLibrary {
  @override
  Future<List<ThemeEntry>> list() => Completer<List<ThemeEntry>>().future;

  @override
  Future<ThemeEntry?> read(String name) => Completer<ThemeEntry?>().future;

  @override
  Future<ThemeImportResult> import(
    String sourcePath, {
    bool replace = false,
    String? expectedName,
  }) => throw UnimplementedError();
}

final _night = jsonEncode({
  'name': 'acme-night',
  'extends': 'dark',
  'colors': {'accent': '#b4a0ff', 'success': '#00ff00'},
});

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

  FluentThemeData appTheme(WidgetTester tester) =>
      FluentTheme.of(tester.element(find.byType(CodeLabPromptComposer)));

  testWidgets('FluentApp получает theme, darkTheme и themeMode из Cubit; '
      'палитра кита зарегистрирована в обеих темах', (tester) async {
    final binding = CodeLabTestBinding(project: '/workspace');
    await pumpApp(tester, binding);

    final app = tester.widget<FluentApp>(find.byType(FluentApp));
    expect(app.themeMode, ThemeMode.system);
    for (final theme in [app.theme, app.darkTheme]) {
      expect(theme, isNotNull);
      expect(theme!.extensions[CodeLabPalette], isA<CodeLabPalette>());
      expect(theme.extensions[CodeLabCodeTheme], isA<CodeLabCodeTheme>());
    }
    expect(app.theme!.brightness, Brightness.light);
    expect(app.darkTheme!.brightness, Brightness.dark);
  });

  testWidgets('«Тёмная система»: Match system следует режиму системы без '
      'пересоздания FluentApp, ввод и фокус сохранены', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final binding = CodeLabTestBinding(project: '/workspace');
    await pumpApp(tester, binding);
    expect(appTheme(tester).brightness, Brightness.light);
    await tester.enterText(_composerField(), 'hello');
    await tester.pump();

    final appElement = tester.element(find.byType(FluentApp));
    final composerState = tester.state(find.byType(CodeLabPromptComposer));
    final focused = tester
        .widget<EditableText>(_composerField())
        .focusNode
        .hasFocus;

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();

    expect(appTheme(tester).brightness, Brightness.dark);
    expect(
      CodeLabPalette.of(appTheme(tester)),
      same(appTheme(tester).extensions[CodeLabPalette]),
      reason: 'палитру регистрирует app, а не выводит кит',
    );
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
    // Агенту при смене оформления ничего не отправляется.
    expect(binding.transport.sentMessages, isEmpty);
  });

  testWidgets('смена режима через Cubit не пересоздаёт FluentApp', (
    tester,
  ) async {
    final binding = CodeLabTestBinding(project: '/workspace');
    await pumpApp(tester, binding);
    await tester.enterText(_composerField(), 'draft');
    await tester.pump();
    final appElement = tester.element(find.byType(FluentApp));
    final composerState = tester.state(find.byType(CodeLabPromptComposer));

    await tester.runAsync(
      () => binding.scope.resolve<AppAppearanceCubit>().setMode(
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<FluentApp>(find.byType(FluentApp)).themeMode,
      ThemeMode.dark,
    );
    expect(appTheme(tester).brightness, Brightness.dark);
    expect(tester.element(find.byType(FluentApp)), same(appElement));
    expect(
      tester.state(find.byType(CodeLabPromptComposer)),
      same(composerState),
    );
    expect(
      tester.widget<EditableText>(_composerField()).controller.text,
      'draft',
    );
  });

  group('первый кадр в оформлении из AppAppearanceStart', () {
    testWidgets('фиксированный Dark и пользовательская тема сразу в первом '
        'кадре', (tester) async {
      final binding = CodeLabTestBinding(
        project: '/workspace',
        appearance: AppAppearanceStart(
          settings: const AppAppearanceSettings(
            mode: AppearanceMode.dark,
            darkTheme: 'acme-night',
          ),
          darkTheme: ThemeFile.parse('acme-night.json', _night) as ThemeLoaded,
        ),
      );

      await pumpApp(tester, binding);

      expect(
        tester.widget<FluentApp>(find.byType(FluentApp)).themeMode,
        ThemeMode.dark,
      );
      expect(appTheme(tester).brightness, Brightness.dark);
      expect(
        CodeLabPalette.of(appTheme(tester)).success,
        const Color(0xFF00FF00),
      );
      expect(appTheme(tester).accentColor.normal, const Color(0xFFB4A0FF));
    });

    testWidgets('системный акцент из шва перекрывает accent темы', (
      tester,
    ) async {
      final binding = CodeLabTestBinding(
        project: '/workspace',
        appearance: const AppAppearanceStart(
          settings: AppAppearanceSettings(
            mode: AppearanceMode.light,
            systemAccent: true,
          ),
          systemAccentSupported: true,
          systemAccent: 0xFFFF2D55,
        ),
      );

      await pumpApp(tester, binding);

      expect(appTheme(tester).accentColor.normal, const Color(0xFFFF2D55));
    });
  });

  group('файл темы не прочитан за 1 с (spec «Хранение оформления»)', () {
    testWidgets('встроенная тема режима, fallback и app.appearance_resolved '
        'без имени темы', (tester) async {
      final start = (await tester.runAsync(
        () => AppAppearanceStart.resolve(
          load: const AppAppearanceLoad(
            AppAppearanceSettings(
              mode: AppearanceMode.dark,
              darkTheme: 'acme-night',
            ),
          ),
          library: _HangingLibrary(),
          fileTimeout: const Duration(milliseconds: 50),
        ),
      ))!;
      expect(start.darkTheme, isNull);
      expect(start.fallback, AppearanceFallback.dark);

      final binding = CodeLabTestBinding(
        project: '/workspace',
        appearance: start,
      );
      await pumpApp(tester, binding);

      expect(appTheme(tester).brightness, Brightness.dark);
      expect(
        CodeLabPalette.of(appTheme(tester)).success,
        isNot(const Color(0xFF00FF00)),
      );
      final events = binding.scope
          .resolve<LogBuffer>()
          .entries
          .value
          .where((e) => e['event'] == 'app.appearance_resolved')
          .toList();
      expect(events, hasLength(1));
      expect(events.single['mode'], 'dark');
      expect(events.single['light_theme'], 'light');
      expect(events.single['dark_theme'], 'custom');
      expect(events.single['system_accent'], false);
      expect(events.single['fallback'], 'dark');
      expect(events.single.values.join(' '), isNot(contains('acme-night')));
    });

    testWidgets('файл прочитан вовремя: fallback none', (tester) async {
      final start = (await tester.runAsync(
        () => AppAppearanceStart.resolve(
          load: const AppAppearanceLoad(
            AppAppearanceSettings(
              mode: AppearanceMode.dark,
              darkTheme: 'acme-night',
            ),
          ),
          library: InMemoryThemeLibrary(themes: {'acme-night': _night}),
        ),
      ))!;

      expect(start.darkTheme, isNotNull);
      expect(start.fallback, AppearanceFallback.none);
    });
  });

  group('«База пользовательской темы сменила режим» при старте', () {
    final dayAsDark = jsonEncode({
      'name': 'acme-night',
      'extends': 'light',
      'colors': {'success': '#00ff00'},
    });

    testWidgets('имя в документе сохраняется, тема режима не загружена, '
        'документ не помечен повреждённым', (tester) async {
      final start = (await tester.runAsync(
        () => AppAppearanceStart.resolve(
          load: const AppAppearanceLoad(
            AppAppearanceSettings(
              mode: AppearanceMode.dark,
              darkTheme: 'acme-night',
            ),
          ),
          library: InMemoryThemeLibrary(themes: {'acme-night': dayAsDark}),
        ),
      ))!;

      expect(start.settings.darkTheme, 'acme-night');
      expect(start.storedValueInvalid, isFalse);
      expect(start.darkTheme, isNull);
      expect(start.fallback, AppearanceFallback.dark);
      expect(start.themeProblems.single.code, 'wrongMode');
    });

    testWidgets('первый кадр — Fluent Dark, в журнале appearance.theme_invalid '
        'с wrongMode', (tester) async {
      final start = (await tester.runAsync(
        () => AppAppearanceStart.resolve(
          load: const AppAppearanceLoad(
            AppAppearanceSettings(
              mode: AppearanceMode.dark,
              darkTheme: 'acme-night',
            ),
          ),
          library: InMemoryThemeLibrary(themes: {'acme-night': dayAsDark}),
        ),
      ))!;
      final binding = CodeLabTestBinding(
        project: '/workspace',
        appearance: start,
      );
      await pumpApp(tester, binding);

      expect(
        CodeLabPalette.of(appTheme(tester)).success,
        isNot(const Color(0xFF00FF00)),
      );
      final events = binding.scope
          .resolve<LogBuffer>()
          .entries
          .value
          .where((e) => e['event'] == 'appearance.theme_invalid')
          .toList();
      expect(events, hasLength(1));
      expect(events.single['code'], 'wrongMode');
      expect(events.single['theme'], 'custom');
      expect(events.single.values.join(' '), isNot(contains('acme-night')));
    });

    testWidgets('светлая тема в поле светлого режима с базой dark — то же', (
      tester,
    ) async {
      final start = (await tester.runAsync(
        () => AppAppearanceStart.resolve(
          load: const AppAppearanceLoad(
            AppAppearanceSettings(lightTheme: 'acme-day'),
          ),
          library: InMemoryThemeLibrary(
            themes: {'acme-day': _night.replaceAll('acme-night', 'acme-day')},
          ),
        ),
      ))!;

      expect(start.settings.lightTheme, 'acme-day');
      expect(start.lightTheme, isNull);
      expect(start.fallback, AppearanceFallback.light);
    });
  });

  testWidgets('диагностика чтения документа: appearance.stored_value_invalid '
      'без значения', (tester) async {
    final binding = CodeLabTestBinding(
      project: '/workspace',
      appearance: const AppAppearanceStart(storedValueInvalid: true),
    );
    await pumpApp(tester, binding);

    final events = binding.scope
        .resolve<LogBuffer>()
        .entries
        .value
        .where((e) => e['event'] == 'appearance.stored_value_invalid')
        .toList();
    expect(events, hasLength(1));
    expect(events.single['level'], 'warning');
  });
}
