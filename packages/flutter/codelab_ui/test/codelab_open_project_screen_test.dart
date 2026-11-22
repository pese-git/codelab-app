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

  // Ревью, итерация 1: расхождение с design.md D10 и кадром 11a
  // (`ProjectsEmpty.dc.html`: `.col` max-width 620, `.hero` с `accent-weak`,
  // `.drop` пунктиром).
  testWidgets('колонка экрана шириной до 620 px', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(_organism()));

    expect(tester.getSize(find.byKey(_zoneKey)).width, 620);
  });

  testWidgets('герой — плитка 56×56 со слабым фоном акцента', (tester) async {
    await tester.pumpWidget(_host(_organism()));

    final hero = find.byKey(const ValueKey('open-project-hero'));
    expect(hero, findsOneWidget);
    expect(tester.getSize(hero), const Size(56, 56));
    final decoration =
        tester.widget<DecoratedBox>(hero).decoration as BoxDecoration;
    final accent = CodeLabPalette.of(_lightTheme).accent;
    // Слабый акцент: тот же оттенок, но прозрачный (не сплошной цвет акцента).
    expect(decoration.color, isNotNull);
    expect(decoration.color!.a, lessThan(0.5));
    expect(decoration.color!.r, closeTo(accent.r, 0.01));
  });

  testWidgets('рамка зоны в покое — пунктир (CustomPaint), при dropActive — '
      'сплошная рамка акцента', (tester) async {
    Finder painter() => find.descendant(
      of: find.byKey(_zoneKey),
      matchRoot: true,
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter != null,
      ),
    );

    await tester.pumpWidget(_host(_organism()));
    expect(painter(), findsOneWidget);

    await tester.pumpWidget(_host(_organism(dropActive: true)));
    await tester.pump(const Duration(seconds: 1));
    expect(painter(), findsNothing);
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

  group('CodeLabOpenProjectBody', () {
    // Тело без героя, заголовка, InfoBar и прокрутки: его строит шаг
    // «Open a project» onboarding (design.md change
    // `add-onboarding-project-step`, D4). Красный до задачи 1.2: класса нет.
    CodeLabOpenProjectBody body({
      String? settingsLinkLabel,
      VoidCallback? onOpenSettings,
      VoidCallback? onOpen,
    }) => CodeLabOpenProjectBody(
      description: 'Choose the folder you want to work in.',
      openLabel: 'Open folder…',
      openShortcut: 'Ctrl+O',
      onOpen: onOpen ?? () {},
      dropLabel: 'Drop a folder here to open it',
      dropHint: 'Files are not accepted — only a folder',
      agentName: 'Embedded agent',
      agentDetail: 'in-process · profile of this window',
      agentNote: 'Starts when you open a folder. Nothing runs before that.',
      settingsLinkLabel: settingsLinkLabel,
      onOpenSettings: onOpenSettings,
    );

    Widget host(Widget child, {Size? size, FluentThemeData? theme}) {
      final app = FluentApp(
        theme: theme ?? _lightTheme,
        home: ScaffoldPage(content: child),
      );
      return size == null
          ? app
          : MediaQuery(
              data: MediaQueryData(size: size),
              child: app,
            );
    }

    testWidgets('слот beforeOpen стоит между пояснением и кнопкой '
        '«Open folder…» (строка «Last project» шага onboarding, D3)', (
      tester,
    ) async {
      const slot = ValueKey('slot');
      await tester.pumpWidget(
        host(
          CodeLabOpenProjectBody(
            description: 'Choose the folder you want to work in.',
            openLabel: 'Open folder…',
            onOpen: () {},
            dropLabel: 'Drop a folder here to open it',
            dropHint: 'Files are not accepted — only a folder',
            agentName: 'Embedded agent',
            agentDetail: 'in-process · profile of this window',
            agentNote: 'Starts when you open a folder.',
            beforeOpen: const SizedBox(key: slot, height: 10),
          ),
        ),
      );

      final description = tester.getTopLeft(
        find.text('Choose the folder you want to work in.'),
      );
      final slotTop = tester.getTopLeft(find.byKey(slot));
      final open = tester.getTopLeft(find.byKey(_openKey));
      expect(slotTop.dy, greaterThan(description.dy));
      expect(slotTop.dy, lessThan(open.dy));
    });

    testWidgets('onOpen == null: «Open folder…» неактивна и не нажимается '
        '(выбор уже идёт, шаг onboarding)', (tester) async {
      await tester.pumpWidget(
        host(
          const CodeLabOpenProjectBody(
            description: 'Choose the folder you want to work in.',
            openLabel: 'Open folder…',
            onOpen: null,
            dropLabel: 'Drop a folder here to open it',
            dropHint: 'Files are not accepted — only a folder',
            agentName: 'Embedded agent',
            agentDetail: 'in-process · profile of this window',
            agentNote: 'Starts when you open a folder.',
          ),
        ),
      );

      expect(
        tester.widget<CodeLabButton>(find.byKey(_openKey)).onPressed,
        isNull,
      );
    });

    testWidgets('рисует пояснение, кнопку с подсказкой, зону и карточку, '
        'но не героя, заголовок и InfoBar', (tester) async {
      await tester.pumpWidget(host(body()));

      for (final key in [_openKey, _zoneKey, _agentKey]) {
        expect(find.byKey(key), findsOneWidget, reason: '$key');
      }
      for (final text in [
        'Choose the folder you want to work in.',
        'Open folder…',
        'Ctrl+O',
        'Drop a folder here to open it',
        'Files are not accepted — only a folder',
        'Embedded agent',
        'in-process · profile of this window',
        'Starts when you open a folder. Nothing runs before that.',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.byKey(const ValueKey('open-project-hero')), findsNothing);
      expect(find.byKey(_infoKey), findsNothing);
      expect(find.byKey(_screen), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('без settingsLinkLabel и onOpenSettings ссылки нет', (
      tester,
    ) async {
      await tester.pumpWidget(host(body()));

      expect(find.byKey(_settingsKey), findsNothing);
    });

    testWidgets('с обоими параметрами ссылка есть и вызывает колбэк', (
      tester,
    ) async {
      var settings = 0;
      await tester.pumpWidget(
        host(
          body(
            settingsLinkLabel: 'Change in Settings › Connection',
            onOpenSettings: () => settings++,
          ),
        ),
      );

      await tester.tap(find.byKey(_settingsKey));
      await tester.pump(const Duration(milliseconds: 100));
      expect(settings, 1);
    });

    test('задан только один из двух параметров ссылки — assert', () {
      expect(
        () => body(settingsLinkLabel: 'Change in Settings › Connection'),
        throwsAssertionError,
      );
      expect(() => body(onOpenSettings: () {}), throwsAssertionError);
    });

    testWidgets('кнопка вызывает onOpen', (tester) async {
      var opened = 0;
      await tester.pumpWidget(host(body(onOpen: () => opened++)));

      await tester.tap(find.byKey(_openKey));
      await tester.pump(const Duration(milliseconds: 100));
      expect(opened, 1);
    });

    testWidgets('в колонке без ограничения высоты строится без ошибок '
        'раскладки', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(SingleChildScrollView(child: body()), theme: _darkTheme),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(_zoneKey), findsOneWidget);
    });
  });
}
