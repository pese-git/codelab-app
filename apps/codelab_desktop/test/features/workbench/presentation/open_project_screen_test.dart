// Экран «проект не выбран» в собранном приложении (задача 4.1 change
// `add-empty-project-screen`; spec agent-workbench-ui «Экран без выбранного
// проекта» и «Открытие папки перетаскиванием»; design.md D1, D2, D5, D6).
//
// Идёт через `CodeLabTestBinding`. Перетаскивание из ОС тест не эмулирует
// плагином: он находит `OsDropRegion` (адаптер, единственное место импорта
// `desktop_drop`) и вызывает его колбэки так, как их вызвал бы плагин. Вид
// брошенного пути подменяет фейк `LocalPathKindOf`.
//
// Красный до задач 4.2 и 5.4: нет `WorkbenchOpenProjectScreen`, ARB-текстов и
// адаптера `core/platform/os_drop_region.dart` (поэтому тест пока не
// компилируется).

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/core/platform/local_path_kind.dart';
import 'package:codelab_desktop/core/platform/os_drop_region.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../support/test_app_scope.dart';

const _screen = ValueKey('open-project-screen');
const _openButton = ValueKey('start-open-project');
const _zone = ValueKey('open-project-drop-zone');
const _message = ValueKey('open-project-drop-message');
const _agent = ValueKey('open-project-agent');
const _agentSettings = ValueKey('open-project-agent-settings');
const _info = ValueKey('open-project-info');

final class _Picker implements ProjectFolderPicker {
  _Picker([this.answer]);

  final String? answer;
  var picks = 0;

  @override
  Future<String?> pickFolder({String? initialDirectory}) async {
    picks++;
    return answer;
  }
}

const _stdioProfile = ConnectionProfile.stdio(
  id: 'dev',
  label: 'dev',
  command: '/usr/local/bin/codelab-agent',
  args: ['serve', '--stdio', '--token', 'abc'],
);

final _webSocketProfile = ConnectionProfile.webSocket(
  id: 'remote',
  label: 'remote',
  uri: Uri.parse('ws://user:pw@127.0.0.1:8765/acp?t=1'),
);

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  Future<CodeLabShellCubit> pump(
    WidgetTester tester,
    CodeLabTestBinding binding,
  ) async {
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    return binding.scope.resolve<CodeLabShellCubit>();
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }

  /// Текст внутри блока экрана с ключом [key].
  Finder inBlock(Object key, String text) =>
      find.descendant(of: find.byKey(key as Key), matching: find.text(text));

  OsDropRegion region(WidgetTester tester) =>
      tester.widget<OsDropRegion>(find.byType(OsDropRegion));

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  group('содержимое экрана', () {
    testWidgets('Встроенный агент без проекта: все шесть блоков, открыватель '
        'агента не вызван', (tester) async {
      var embeddedOpened = 0;
      final agent = FakeAcpTransport();
      final binding = CodeLabTestBinding(
        stdioDefault: false,
        stdioTransportFactory: (_) => agent,
        embeddedOpener: ({required cwd, required hostProfile}) async {
          embeddedOpened++;
          throw StateError('the embedded agent must not be opened');
        },
      );
      await pump(tester, binding);

      expect(find.byKey(_screen), findsOneWidget);
      expect(inBlock(_screen, 'Open a project'), findsOneWidget);
      expect(
        find.textContaining("The agent can't read or write outside it."),
        findsOneWidget,
      );
      expect(inBlock(_screen, 'Open folder…'), findsOneWidget);
      expect(inBlock(_screen, 'Ctrl+O'), findsOneWidget);
      expect(inBlock(_zone, 'Drop a folder here to open it'), findsOneWidget);
      expect(inBlock(_agent, 'Embedded agent'), findsOneWidget);
      expect(
        inBlock(_agent, 'in-process · profile of this window'),
        findsOneWidget,
      );
      expect(
        inBlock(
          _agent,
          'Starts when you open a folder. Nothing runs before that.',
        ),
        findsOneWidget,
      );
      expect(inBlock(_info, 'New session needs a folder'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_info),
          matching: find.textContaining('Ctrl+N without a project'),
        ),
        findsOneWidget,
      );
      expect(embeddedOpened, 0);
      expect(agent.sentMessages, isEmpty);
      await tearDownApp(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('Профиль stdio: имя и команда без аргументов, фраза внешнего '
        'агента', (tester) async {
      final binding = CodeLabTestBinding(stdioDefault: false);
      final cubit = await pump(tester, binding);

      await cubit.useProfile(_stdioProfile);
      await tester.pump();
      await tester.pump();

      expect(inBlock(_agent, 'dev'), findsOneWidget);
      expect(
        inBlock(
          _agent,
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

    testWidgets('Профиль WebSocket: адрес без userinfo, пути и query, '
        'Connects…', (tester) async {
      final binding = CodeLabTestBinding(stdioDefault: false);
      final cubit = await pump(tester, binding);

      await cubit.useProfile(_webSocketProfile);
      await tester.pump();
      await tester.pump();

      expect(inBlock(_agent, 'remote'), findsOneWidget);
      expect(
        inBlock(
          _agent,
          'WebSocket · ws://127.0.0.1:8765 · profile of this window',
        ),
        findsOneWidget,
      );
      expect(
        inBlock(
          _agent,
          'Connects when you open a folder. Nothing connects before that.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('The agent starts in it'), findsNothing);
      expect(find.textContaining('user:pw'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('Подсказки на macOS: ⌘O у кнопки и ⌘N в InfoBar', (
      tester,
    ) async {
      await pump(tester, CodeLabTestBinding(stdioDefault: false));

      expect(inBlock(_screen, '⌘O'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_info),
          matching: find.textContaining('⌘N without a project'),
        ),
        findsOneWidget,
      );
      await tearDownApp(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Проект выбран: экрана и зоны нет, «New session» как раньше', (
      tester,
    ) async {
      await pump(tester, CodeLabTestBinding(project: '/work/app'));

      expect(find.byKey(_screen), findsNothing);
      expect(find.byKey(_zone), findsNothing);
      expect(find.byKey(const ValueKey('start-new-session')), findsOneWidget);
      await tearDownApp(tester);
    });
  });

  group('действия', () {
    testWidgets('Ссылка на настройки подключения: открыта «Connection», '
        'событие settings.opened с источником start_screen, агент не '
        'запущен', (tester) async {
      final agent = FakeAcpTransport();
      final binding = CodeLabTestBinding(
        stdioDefault: false,
        stdioTransportFactory: (_) => agent,
        settingsPages: const SettingsPages(
          available: {SettingsPage.connection},
        ),
      );
      await pump(tester, binding);

      await tester.tap(find.byKey(_agentSettings));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-nav-connection')),
        findsOneWidget,
      );
      final opened = binding.scope
          .resolve<LogBuffer>()
          .entries
          .value
          .singleWhere((e) => e['event'] == 'settings.opened');
      expect('$opened', contains('start_screen'));
      expect(agent.sentMessages, isEmpty);
      await tearDownApp(tester);
    });

    testWidgets('Отмена выбора папки: экран остался, проект не выбран', (
      tester,
    ) async {
      final picker = _Picker();
      final cubit = await pump(
        tester,
        CodeLabTestBinding(stdioDefault: false, projectFolderPicker: picker),
      );

      await tester.tap(find.byKey(_openButton));
      await settle(tester);

      expect(picker.picks, 1);
      expect(cubit.state.selectedProjectPath, isNull);
      expect(find.byKey(_screen), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tearDownApp(tester);
    });
  });

  group('перетаскивание (вызов колбэков найденного OsDropRegion)', () {
    final kinds = <String, LocalPathKind>{};

    CodeLabTestBinding binding() => CodeLabTestBinding(
      stdioDefault: false,
      stdioTransportFactory: (_) => FakeAcpTransport(),
      localPathKind: (path) async => kinds[path] ?? LocalPathKind.missing,
    );

    setUp(kinds.clear);

    testWidgets('Брошенная папка открывает проект', (tester) async {
      kinds['/work/app'] = LocalPathKind.directory;
      final cubit = await pump(tester, binding());

      region(tester).onDropped(['/work/app']);
      await settle(tester);
      await tester.pump();

      expect(cubit.state.selectedProjectPath, '/work/app');
      expect(find.byKey(_screen), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      await tearDownApp(tester);
    });

    testWidgets('Файл отклоняется: текст в open-project-drop-message', (
      tester,
    ) async {
      kinds['/work/app/README.md'] = LocalPathKind.file;
      final cubit = await pump(tester, binding());

      region(tester).onDropped(['/work/app/README.md']);
      await settle(tester);
      await tester.pump();

      expect(cubit.state.selectedProjectPath, isNull);
      expect(
        inBlock(
          _message,
          "That's a file. Drop a folder to open it as a project.",
        ),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('Выделение зоны и сброс отказа: вход снимает сообщение, '
        'зона подсвечена, выход снимает подсветку', (tester) async {
      kinds['/work/a'] = LocalPathKind.directory;
      kinds['/work/b'] = LocalPathKind.directory;
      await pump(tester, binding());
      region(tester).onDropped(['/work/a', '/work/b']);
      await settle(tester);
      await tester.pump();
      expect(inBlock(_message, 'Drop one folder at a time.'), findsOneWidget);

      region(tester).onEntered?.call();
      await tester.pump();

      expect(find.byKey(_message), findsNothing);
      final active = tester.widget<CodeLabOpenProjectScreen>(
        find.byType(CodeLabOpenProjectScreen),
      );
      expect(active.dropActive, isTrue);

      region(tester).onExited?.call();
      await tester.pump();

      expect(
        tester
            .widget<CodeLabOpenProjectScreen>(
              find.byType(CodeLabOpenProjectScreen),
            )
            .dropActive,
        isFalse,
      );
      await tearDownApp(tester);
    });
  });
}
