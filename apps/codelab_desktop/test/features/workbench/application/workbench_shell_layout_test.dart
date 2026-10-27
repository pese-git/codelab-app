// Состояние каркаса рабочего места и его мапперы (tasks 3.1–3.4 change
// `redesign-workbench-shell`; design D1, D4, D5, D6, D7).

import 'package:codelab_client_core/codelab_client_core.dart'
    show ConfigOptionValueView, ConfigOptionView;
import 'package:codelab_desktop/core/platform/dock_layout_store.dart';
import 'package:codelab_desktop/features/workbench/application/layout_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/shell_part.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('LayoutCubit', () {
    late LayoutCubit cubit;

    setUp(() => cubit = LayoutCubit(changes: ShellChanges()));
    tearDown(() => cubit.close());

    test('a pane toggle opens, activates and then closes the pane', () {
      cubit.togglePane(ToolPane.plan);
      expect(cubit.state.openPanes, [ToolPane.plan]);
      expect(cubit.state.activePane, ToolPane.plan);
      expect(cubit.state.dockOverlayOpen, isTrue);

      cubit.togglePane(ToolPane.plan);
      expect(cubit.state.openPanes, isEmpty);
      expect(cubit.state.activePane, isNull);
      expect(cubit.state.dockOverlayOpen, isFalse);
    });

    test('toggling an open but inactive pane activates it', () {
      cubit
        ..togglePane(ToolPane.plan)
        ..togglePane(ToolPane.protocol)
        ..togglePane(ToolPane.plan);

      expect(cubit.state.openPanes, [ToolPane.plan, ToolPane.protocol]);
      expect(cubit.state.activePane, ToolPane.plan);
    });

    test('closing the active tab activates the last remaining pane', () {
      cubit
        ..openPane(ToolPane.plan)
        ..openPane(ToolPane.protocol)
        ..closePane(ToolPane.protocol);

      expect(cubit.state.openPanes, [ToolPane.plan]);
      expect(cubit.state.activePane, ToolPane.plan);
    });

    test('dismissing the overlay keeps the panes open', () {
      cubit
        ..openPane(ToolPane.plan)
        ..dismissDockOverlay();

      expect(cubit.state.dockOverlayOpen, isFalse);
      expect(cubit.state.openPanes, [ToolPane.plan]);
    });

    test('dock width is clamped to its bounds', () {
      cubit.resizeDock(10);
      expect(cubit.state.dockWidth, kDockMinWidth);
      cubit.resizeDock(10000);
      expect(cubit.state.dockWidth, kDockMaxWidth);
    });

    test('sidebar collapse and overlay toggle independently', () {
      cubit.toggleSidebarCollapsed();
      expect(cubit.state.sidebarCollapsed, isTrue);
      cubit.toggleSidebarOverlay();
      expect(cubit.state.sidebarOverlayOpen, isTrue);
      cubit.closeSidebarOverlay();
      expect(cubit.state.sidebarOverlayOpen, isFalse);
      expect(cubit.state.sidebarCollapsed, isTrue);
    });
  });

  group('dock layout persistence', () {
    test(
      'open panes, the active pane and the width survive a restart',
      () async {
        const store = SharedPreferencesDockLayoutStore();
        final first = LayoutCubit(
          changes: ShellChanges(),
          dockLayoutStore: store,
        );
        await settle();
        first
          ..openPane(ToolPane.plan)
          ..openPane(ToolPane.protocol)
          ..resizeDock(420);
        await settle();
        await first.close();

        final restarted = LayoutCubit(
          changes: ShellChanges(),
          dockLayoutStore: store,
        );
        addTearDown(restarted.close);
        await settle();
        await settle();

        expect(restarted.state.openPanes, [ToolPane.plan, ToolPane.protocol]);
        expect(restarted.state.activePane, ToolPane.protocol);
        expect(restarted.state.dockWidth, 420);
        expect(restarted.state.dockOverlayOpen, isFalse);
      },
    );

    test('an unknown pane name from another version is skipped', () async {
      SharedPreferences.setMockInitialValues({
        'codelab.dock.open_panes': ['plan', 'hologram'],
        'codelab.dock.active_pane': 'hologram',
        'codelab.dock.width': 300.0,
      });
      final cubit = LayoutCubit(
        changes: ShellChanges(),
        dockLayoutStore: const SharedPreferencesDockLayoutStore(),
      );
      addTearDown(cubit.close);
      await settle();
      await settle();

      expect(cubit.state.openPanes, [ToolPane.plan]);
      expect(cubit.state.activePane, ToolPane.plan);
      expect(cubit.state.dockWidth, 300);
    });
  });

  group('sidebar and header mappers', () {
    const sessions = [
      CodeLabSessionListItem(
        id: 's-1',
        title: 'Fix reconnect race',
        status: CodeLabSessionStatus.running,
      ),
    ];

    test('projectNameOf takes the last path segment', () {
      expect(projectNameOf('/work/codelab-app'), 'codelab-app');
      expect(projectNameOf('/work/codelab-app/'), 'codelab-app');
      expect(projectNameOf(r'C:\work\notes'), 'notes');
    });

    test('the selected project is an expanded group, recents are '
        'collapsed groups without duplicates', () {
      final projects = sidebarProjectsOf(
        selectedProjectPath: '/work/codelab-app',
        sessions: sessions,
        recentProjects: const [
          CodeLabRecentProject(path: '/work/codelab-app'),
          CodeLabRecentProject(path: '/work/notes-app'),
        ],
      );

      expect(projects.map((p) => p.name), ['codelab-app', 'notes-app']);
      expect(projects.first.current, isTrue);
      expect(projects.first.sessions, sessions);
      expect(projects.last.current, isFalse);
      expect(projects.last.sessions, isEmpty);
    });

    test('without a selected project the sessions go to "No project"', () {
      final projects = sidebarProjectsOf(
        selectedProjectPath: null,
        sessions: sessions,
        recentProjects: const [],
      );

      expect(projects.single.name, 'No project');
      expect(projects.single.sessions, sessions);
    });

    test('modeLabelOf reads the option of category mode', () {
      const options = [
        ConfigOptionView(
          id: 'model',
          name: 'Model',
          currentValue: 'scripted-1',
          category: 'model',
          values: [ConfigOptionValueView(value: 'scripted-1', name: 'S1')],
        ),
        ConfigOptionView(
          id: 'mode',
          name: 'Mode',
          currentValue: 'standard',
          category: 'mode',
          values: [
            ConfigOptionValueView(value: 'plan', name: 'Plan'),
            ConfigOptionValueView(value: 'standard', name: 'Standard'),
          ],
        ),
      ];

      expect(modeLabelOf(options), 'Standard');
      expect(modeLabelOf(options.take(1).toList()), isNull);
    });

    test('the connection tooltip carries profile, transport and detail', () {
      expect(
        connectionTooltipOf(
          profileLabel: 'Codelab Agent',
          transportLabel: 'stdio',
          connectionDetail: 'codelab serve --stdio',
        ),
        'Codelab Agent · stdio · codelab serve --stdio',
      );
    });
  });
}
