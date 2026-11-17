// Панель Files в собранном приложении (задачи 2.5a и 2.9 change
// `add-file-preview-and-tree`; spec workspace-file-browser «Панель Files в
// доке инструментов» — «Открытие панели для встроенного агента», «Повторное
// сочетание закрывает панель», «Нет панели для WebSocket-агента», «Корень без
// сессии»; «Просмотр файла только для чтения» — «Copy path копирует
// относительный путь»; «Предупреждение для файлов с секретами» — «Открытие
// `.env`»; agent-workbench-ui «Tool dock with closable pane tabs» —
// «Unavailable pane is hidden but kept in the layout»; design.md D5, D7, D13).
//
// Файлы — двойник `FakeProjectFiles`: настоящая файловая система в
// `testWidgets` зависает (`AGENTS.md` приложения, «Тесты»).

import 'dart:async';
import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ConnectionProfile,
        SessionStatusView,
        SessionSummaryView,
        TextPreview,
        WorkspaceState;
import 'package:codelab_desktop/features/project_files/application/project_files_cubit.dart';
import 'package:codelab_desktop/features/project_files/presentation/project_files_pane.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../support/fake_project_files.dart';
import '../../support/fake_provider_settings.dart' show FakeWorkspace;
import '../../support/test_app_scope.dart';
import '../../support/start_agent.dart';

const _marker = 'test-marker';

FakeProjectFiles _files() => FakeProjectFiles(
  listings: {
    '/work/app': {
      '': listingOf('', [
        dirEntry('lib'),
        fileEntry('README.md'),
        fileEntry('.env'),
        outsideEntry('secrets'),
      ]),
      'lib': listingOf('lib', [dirEntry('lib/src')]),
      'lib/src': listingOf('lib/src', [fileEntry('lib/src/a.dart')]),
    },
  },
  files: {
    '/work/app': {
      'README.md': const TextPreview('# readme'),
      '.env': const TextPreview('API_KEY=$_marker'),
      'lib/src/a.dart': const TextPreview('class A {}\nclass B {}'),
    },
  },
);

final _webSocket = ConnectionProfile.webSocket(
  id: 'remote',
  label: 'Remote',
  uri: Uri.parse('wss://devbox:7420/acp'),
);

void main() {
  void setWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<CodeLabShellCubit> pumpApp(
    WidgetTester tester,
    CodeLabTestBinding binding,
  ) async {
    setWindow(tester);
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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    // Кнопки и строки Fluent отпускают нажатие по таймеру 100 мс.
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> shortcut(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
  }

  final toggleFiles = find.byKey(CodeLabAppBar.toggleKey(ToolPane.files));
  final filesPane = find.byKey(CodeLabToolDock.paneKey(ToolPane.files));

  testWidgets('Cmd/Ctrl+Shift+E opens the Files tab for a stdio or embedded '
      'agent and keeps the session sidebar, the same chord closes it', (
    tester,
  ) async {
    final binding = CodeLabTestBinding(projectFiles: _files());
    final cubit = await pumpApp(tester, binding);
    expect(toggleFiles, findsOneWidget);
    expect(filesPane, findsNothing);

    await shortcut(tester);

    expect(cubit.state.openPanes, [ToolPane.files]);
    expect(cubit.state.activePane, ToolPane.files);
    expect(filesPane, findsOneWidget);
    expect(find.byKey(CodeLabWorkbenchLayout.sidebarKey), findsOneWidget);

    await shortcut(tester);

    expect(cubit.state.openPanes, isEmpty);
    expect(filesPane, findsNothing);

    await tearDownApp(tester);
  });

  testWidgets('the app bar toggle and the palette item “Files” open the '
      'panel', (tester) async {
    final binding = CodeLabTestBinding(projectFiles: _files());
    final cubit = await pumpApp(tester, binding);

    tester.widget<ToggleButton>(toggleFiles).onChanged!(true);
    await settle(tester);
    expect(filesPane, findsOneWidget);

    tester.widget<ToggleButton>(toggleFiles).onChanged!(false);
    await settle(tester);
    expect(filesPane, findsNothing);

    cubit.openCommandPalette();
    await settle(tester);
    // Поиск палитры идёт по каталогу kit: «files» оставляет один пункт.
    await tester.enterText(
      find.byKey(CodeLabCommandPaletteSurface.queryFieldKey),
      'files',
    );
    await settle(tester);
    final item = find.descendant(
      of: find.byKey(CodeLabCommandPaletteSurface.listKey),
      matching: find.text('Files'),
    );
    expect(item, findsOneWidget);
    await tester.tap(item);
    await settle(tester);

    expect(cubit.state.isCommandPaletteOpen, isFalse);
    expect(filesPane, findsOneWidget);

    await tearDownApp(tester);
  });

  testWidgets('without a ProjectFiles binding there is no toggle, no palette '
      'item and the chord does nothing', (tester) async {
    final binding = CodeLabTestBinding();
    final cubit = await pumpApp(tester, binding);

    expect(toggleFiles, findsNothing);
    await shortcut(tester);
    expect(cubit.state.openPanes, isEmpty);

    expect([
      for (final action in cubit.state.paletteActions) action.id,
    ], isNot(contains('files')));

    await tearDownApp(tester);
  });

  testWidgets('a WebSocket profile hides the toggle, the palette item and '
      'the chord, yet the saved Files tab returns with the local agent', (
    tester,
  ) async {
    final binding = CodeLabTestBinding(
      projectFiles: _files(),
      webSocketTransportFactory: (_) => FakeAcpTransport(),
    );
    final cubit = await pumpApp(tester, binding);
    cubit.togglePane(ToolPane.files);
    cubit.togglePane(ToolPane.plan);
    await settle(tester);
    expect(filesPane, findsNothing); // активна Plan
    cubit.selectPane(ToolPane.files);
    await settle(tester);
    expect(filesPane, findsOneWidget);

    unawaited(cubit.startWith(_webSocket));
    await settle(tester);

    expect(toggleFiles, findsNothing);
    expect(filesPane, findsNothing);
    expect(
      find.byKey(CodeLabToolDock.paneKey(ToolPane.plan)),
      findsOneWidget,
      reason: 'the dock shows only Plan on a WebSocket profile',
    );
    // Раскладка не потеряна.
    expect(cubit.state.openPanes, contains(ToolPane.files));

    cubit.closePane(ToolPane.plan);
    expect([
      for (final action in cubit.state.paletteActions) action.id,
    ], isNot(contains('files')));
    await shortcut(tester);
    // Сочетание не привязано: сохранённая вкладка не закрыта и не сдвинута.
    expect(cubit.state.openPanes, contains(ToolPane.files));
    expect(cubit.state.activePane, ToolPane.files);

    unawaited(cubit.startWith(testStdioProfile));
    await settle(tester);

    expect(toggleFiles, findsOneWidget);
    expect(cubit.state.openPanes, contains(ToolPane.files));
    expect(filesPane, findsOneWidget);
    expect([
      for (final action in cubit.state.paletteActions) action.id,
    ], contains('files'));

    await tearDownApp(tester);
  });

  testWidgets('without a session the tree shows the selected project folder', (
    tester,
  ) async {
    final files = _files();
    final binding = CodeLabTestBinding(projectFiles: files);
    final cubit = await pumpApp(tester, binding);
    await cubit.selectProject('/work/app');
    cubit.openPane(ToolPane.files);
    await settle(tester);

    expect(find.byKey(const ValueKey('file-tree-row-lib')), findsOneWidget);
    expect(find.byKey(const ValueKey('file-tree-row-.env')), findsOneWidget);
    expect(files.canonicalCalls, contains('/work/app'));
    expect(
      find.byKey(const ValueKey('file-tree-outside-secrets')),
      findsOneWidget,
    );

    await tearDownApp(tester);
  });

  testWidgets('Copy path puts exactly the relative path on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final binding = CodeLabTestBinding(projectFiles: _files());
    final cubit = await pumpApp(tester, binding);
    await cubit.selectProject('/work/app');
    cubit.openPane(ToolPane.files);
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('file-tree-row-lib')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('file-tree-row-lib/src')));
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('file-tree-row-lib/src/a.dart')),
    );
    await settle(tester);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('file-preview-path')),
        matching: find.text('lib/src/a.dart'),
      ),
      findsOneWidget,
    );
    expect(find.text('class B {}'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('file-preview-copy-path')));
    await settle(tester);

    expect(copied, 'lib/src/a.dart');

    await tearDownApp(tester);
  });

  testWidgets('opening .env shows the content and the warning, and neither '
      'the log nor the window state holds the marker', (tester) async {
    final binding = CodeLabTestBinding(projectFiles: _files());
    final cubit = await pumpApp(tester, binding);
    await cubit.selectProject('/work/app');
    cubit.openPane(ToolPane.files);
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('file-tree-row-.env')));
    await settle(tester);

    expect(find.text('API_KEY=$_marker'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('file-preview-secret-warning')),
      findsOneWidget,
    );
    expect(find.text('This file may contain secrets.'), findsOneWidget);
    final buffer = binding.scope.resolve<LogBuffer>();
    expect(jsonEncode(buffer.entries.value), isNot(contains(_marker)));
    expect(
      [for (final row in cubit.state.transcriptRows) row.toString()].join(),
      isNot(contains(_marker)),
    );
    // Журнал не хранит и самого пути файла выше уровня debug.
    for (final entry in buffer.entries.value) {
      if ('${entry['event']}'.startsWith('project_files.') &&
          entry['level'] != 'debug') {
        expect(jsonEncode(entry), isNot(contains('.env')));
      }
    }

    await tearDownApp(tester);
  });

  testWidgets('a README gets no secret warning, and Refresh re-reads the '
      'tree', (tester) async {
    final files = _files();
    final binding = CodeLabTestBinding(projectFiles: files);
    final cubit = await pumpApp(tester, binding);
    await cubit.selectProject('/work/app');
    cubit.openPane(ToolPane.files);
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('file-tree-row-README.md')));
    await settle(tester);
    expect(find.text('# readme'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('file-preview-secret-warning')),
      findsNothing,
    );

    files.listCalls.clear();
    await tester.tap(find.byKey(const ValueKey('project-files-refresh')));
    await settle(tester);

    expect(files.listCalls, [('/work/app', '')]);

    await tearDownApp(tester);
  });

  testWidgets('the folders stay expanded after switching to another tab and '
      'back: the window, not the tab, owns the tree (D6)', (tester) async {
    final files = _files();
    final binding = CodeLabTestBinding(projectFiles: files);
    final cubit = await pumpApp(tester, binding);
    await cubit.selectProject('/work/app');
    cubit.openPane(ToolPane.files);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('file-tree-row-lib')));
    await settle(tester);
    expect(find.byKey(const ValueKey('file-tree-row-lib/src')), findsOneWidget);

    cubit.togglePane(ToolPane.plan);
    await settle(tester);
    expect(filesPane, findsNothing);
    cubit.selectPane(ToolPane.files);
    await settle(tester);

    expect(find.byKey(const ValueKey('file-tree-row-lib/src')), findsOneWidget);
    expect(files.canonicalCalls, ['/work/app']);
    expect(files.listCalls, [('/work/app', ''), ('/work/app', 'lib')]);

    // Свернуть и открыть док целиком — то же самое.
    cubit.closePane(ToolPane.files);
    cubit.closePane(ToolPane.plan);
    await settle(tester);
    cubit.openPane(ToolPane.files);
    await settle(tester);

    expect(find.byKey(const ValueKey('file-tree-row-lib/src')), findsOneWidget);
    expect(files.listCalls, hasLength(2));

    await tearDownApp(tester);
  });

  group('the view over a cubit', () {
    Future<ProjectFilesCubit> pumpView(
      WidgetTester tester,
      FakeProjectFiles files,
      WorkspaceState state,
    ) async {
      final cubit = ProjectFilesCubit(
        files: files,
        workspace: FakeWorkspace(state),
      );
      addTearDown(cubit.close);
      await tester.pumpWidget(
        FluentApp(
          home: BlocProvider.value(
            value: cubit,
            child: const ScaffoldPage(
              padding: EdgeInsets.zero,
              content: ProjectFilesView(),
            ),
          ),
        ),
      );
      await settle(tester);
      return cubit;
    }

    WorkspaceState withCwd(String cwd) => WorkspaceState(
      projectDirectory: '/work/app',
      sessions: [
        SessionSummaryView(
          id: SessionId('s1'),
          cwd: cwd,
          status: SessionStatusView.idle,
        ),
      ],
      activeSessionId: SessionId('s1'),
    );

    testWidgets('a root outside the project folder shows its absolute path '
        'and the mark, a root inside does not (Q18)', (tester) async {
      final files = _files();
      files.listings['/'] = {
        '': listingOf('', [fileEntry('etc')]),
      };
      await pumpView(tester, files, withCwd('/'));
      final mark = find.byKey(const ValueKey('project-files-root-outside'));
      expect(mark, findsOneWidget);
      expect(
        find.descendant(
          of: mark,
          matching: find.textContaining('outside the project folder'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: mark, matching: find.textContaining('/')),
        findsWidgets,
      );

      await pumpView(tester, files, withCwd('/work/app'));
      expect(
        find.byKey(const ValueKey('project-files-root-outside')),
        findsNothing,
      );
    });

    testWidgets('a missing folder and an unreadable one have their own '
        'messages', (tester) async {
      final files = _files()..missingFolders.add('/work/app');
      await pumpView(
        tester,
        files,
        const WorkspaceState(projectDirectory: '/work/app'),
      );
      expect(find.text('The project folder does not exist.'), findsOneWidget);

      files.missingFolders.clear();
      files.canonicalError = StateError('x');
      await pumpView(
        tester,
        files,
        const WorkspaceState(projectDirectory: '/work/app'),
      );
      expect(find.text('The project folder cannot be read.'), findsOneWidget);
    });
  });
}
