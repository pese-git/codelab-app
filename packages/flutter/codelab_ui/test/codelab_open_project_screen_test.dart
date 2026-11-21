// Экран «проект не выбран» `CodeLabOpenProjectScreen` (задача 2.1 change
// `add-empty-project-screen`; design.md D1, D10; spec agent-workbench-ui
// «Экран без выбранного проекта»): организм без логики, только показывает
// переданные строки и вызывает колбэки. Приём перетаскивания — в app (D3).
//
// Красный до задачи 2.2: организма ещё нет, тест не компилируется.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _screen = ValueKey('open-project-screen');
const _openKey = ValueKey('start-open-project');
const _zoneKey = ValueKey('open-project-drop-zone');
const _messageKey = ValueKey('open-project-drop-message');
const _agentKey = ValueKey('open-project-agent');
const _settingsKey = ValueKey('open-project-agent-settings');
const _infoKey = ValueKey('open-project-info');

final _lightTheme = FluentThemeData(brightness: Brightness.light);
final _darkTheme = FluentThemeData(brightness: Brightness.dark);

CodeLabOpenProjectScreen _organism({
  bool dropActive = false,
  String? dropMessage,
  VoidCallback? onOpen,
  VoidCallback? onOpenSettings,
}) => CodeLabOpenProjectScreen(
  title: 'Open a project',
  description: 'Choose the folder you want to work in.',
  openLabel: 'Open folder…',
  openShortcut: 'Ctrl+O',
  onOpen: onOpen ?? () {},
  dropLabel: 'Drop a folder here to open it',
  dropHint: 'Files are not accepted — only a folder',
  dropActive: dropActive,
  dropMessage: dropMessage,
  agentName: 'Embedded agent',
  agentDetail: 'in-process · profile of this window',
  agentNote: 'Starts when you open a folder. Nothing runs before that.',
  settingsLinkLabel: 'Change in Settings › Connection',
  onOpenSettings: onOpenSettings ?? () {},
  infoTitle: 'New session needs a folder',
  infoBody: 'Ctrl+N without a project opens the same folder picker.',
);

Widget _host(
  CodeLabOpenProjectScreen screen, {
  FluentThemeData? theme,
  Size? size,
}) {
  final app = FluentApp(
    theme: theme ?? _lightTheme,
    darkTheme: _darkTheme,
    themeMode: (theme ?? _lightTheme).brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light,
    home: ScaffoldPage(content: screen),
  );
  return size == null
      ? app
      : MediaQuery(
          data: MediaQueryData(size: size),
          child: app,
        );
}

/// Цвета рамок всех `BoxDecoration` внутри [of] (рамка зоны).
Set<Color> _borderColors(WidgetTester tester, Finder of) {
  final colors = <Color>{};
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(
      of: of,
      matching: find.byType(DecoratedBox),
      matchRoot: true,
    ),
  )) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration) {
      final border = decoration.border;
      if (border is Border) {
        colors.add(border.top.color);
      }
    }
  }
  return colors;
}

void main() {
  testWidgets('шесть блоков: ключи и тексты берутся из параметров', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_organism()));

    for (final key in [
      _screen,
      _openKey,
      _zoneKey,
      _agentKey,
      _settingsKey,
      _infoKey,
    ]) {
      expect(find.byKey(key), findsOneWidget, reason: '$key');
    }
    for (final text in [
      'Open a project',
      'Choose the folder you want to work in.',
      'Open folder…',
      'Ctrl+O',
      'Drop a folder here to open it',
      'Files are not accepted — only a folder',
      'Embedded agent',
      'in-process · profile of this window',
      'Starts when you open a folder. Nothing runs before that.',
      'Change in Settings › Connection',
      'New session needs a folder',
      'Ctrl+N without a project opens the same folder picker.',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.byKey(_messageKey), findsNothing);
  });

  testWidgets('нажатие кнопки вызывает onOpen, ссылки — onOpenSettings', (
    tester,
  ) async {
    var opened = 0;
    var settings = 0;
    await tester.pumpWidget(
      _host(
        _organism(onOpen: () => opened++, onOpenSettings: () => settings++),
      ),
    );

    await tester.tap(find.byKey(_openKey));
    await tester.pump(const Duration(milliseconds: 100));
    expect((opened, settings), (1, 0));

    await tester.tap(find.byKey(_settingsKey));
    await tester.pump(const Duration(milliseconds: 100));
    expect((opened, settings), (1, 1));
  });

  testWidgets('dropActive: true — рамка зоны в цвете акцента', (tester) async {
    await tester.pumpWidget(_host(_organism()));
    final idle = _borderColors(tester, find.byKey(_zoneKey));

    await tester.pumpWidget(_host(_organism(dropActive: true)));
    await tester.pump(const Duration(seconds: 1));
    final active = _borderColors(tester, find.byKey(_zoneKey));
    final accent = CodeLabPalette.of(_lightTheme).accent;

    expect(active, contains(accent));
    expect(idle, isNot(contains(accent)));
  });

  testWidgets('dropMessage: текст с тоном warning и иконкой, подписи зоны '
      'заменены', (tester) async {
    await tester.pumpWidget(
      _host(
        _organism(
          dropMessage: "That's a file. Drop a folder to open it as a project.",
        ),
      ),
    );

    final message = find.byKey(_messageKey);
    expect(message, findsOneWidget);
    final text = find.descendant(
      of: message,
      matching: find.text(
        "That's a file. Drop a folder to open it as a project.",
      ),
    );
    expect(text, findsOneWidget);
    expect(
      tester.widget<Text>(text).style?.color,
      CodeLabPalette.of(_lightTheme).warning,
    );
    expect(
      find.descendant(of: message, matching: find.byType(Icon)),
      findsWidgets,
    );
    // Сообщение показывается вместо подписи и подсказки зоны.
    expect(find.text('Drop a folder here to open it'), findsNothing);
    expect(find.text('Files are not accepted — only a folder'), findsNothing);
  });

  testWidgets('без dropMessage зона показывает dropLabel и dropHint', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_organism()));

    expect(
      find.descendant(
        of: find.byKey(_zoneKey),
        matching: find.text('Drop a folder here to open it'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(_zoneKey),
        matching: find.text('Files are not accepted — only a folder'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('тёмная тема и окно 800×600: без переполнения, всё доступно '
      'прокруткой', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        _organism(dropMessage: 'Drop one folder at a time.'),
        theme: _darkTheme,
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(_infoKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(_infoKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('семантика: кнопка — кнопка, ссылка — ссылка', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(_organism()));

    final button = tester.getSemantics(find.byKey(_openKey));
    expect(
      // ignore: deprecated_member_use — флаги семантики в этой версии Flutter
      button.getSemanticsData().hasFlag(SemanticsFlag.isButton),
      isTrue,
    );
    final link = tester.getSemantics(find.byKey(_settingsKey));
    expect(
      // ignore: deprecated_member_use — флаги семантики в этой версии Flutter
      link.getSemanticsData().hasFlag(SemanticsFlag.isLink),
      isTrue,
    );
    expect(link.label, contains('Change in Settings › Connection'));
    handle.dispose();
  });
}
