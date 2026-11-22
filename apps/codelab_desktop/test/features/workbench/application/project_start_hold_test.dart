// Удержание старта агента на onboarding (задача 2.1 change
// `add-onboarding-project-step`; spec agent-workbench-ui «Агент стартует
// сам», сценарии «Папка, выбранная на шаге onboarding» и «Выбор после
// onboarding — обычный триггер»; design.md D5).
//
// Пока показан onboarding, `SettingsCubit(projectStartHeld: true)` делает при
// выборе проекта всё, кроме вызова триггера старта агента; удержание снимает
// `CodeLabShellCubit.startOnLaunch()` перед `ConnectionCubit.startOnLaunch()`.
// Тест идёт через настоящие части рабочего места с двойниками портов.
//
// Красный до задачи 2.3: параметра `projectStartHeld` и метода
// `releaseProjectStart` нет, тест не компилируется.

import 'dart:async';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/core/platform/local_path_kind.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/workbench/application/settings_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_strings.dart';
import '../../../support/fake_usage_csv_saver.dart';
import '../../../support/recording_logger.dart';

/// Резолвер, который считает открытия транспорта и их папки: «агент
/// стартовал» наблюдается как открытие транспорта (`concurrency.md` §69).
final class _CountingResolver implements TransportResolver {
  _CountingResolver(this.transport);

  final FakeAcpTransport transport;
  final opened = <String>[];

  @override
  bool supports(ConnectionProfile profile) => true;

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async {
    opened.add(projectDirectory);
    return transport;
  }
}

final class _Picker implements ProjectFolderPicker {
  String? answer;

  @override
  Future<String?> pickFolder({String? initialDirectory}) async => answer;
}

final class _Recents implements RecentProjectsStore {
  final paths = <String>[];

  @override
  Future<List<RecentProject>> load() async => [
    for (final path in paths.reversed)
      RecentProject(path: path, lastOpenedAt: DateTime(2026, 1, 1)),
  ];

  @override
  Future<void> record(String path) async => paths.add(path);
}

final class _Scene {
  _Scene({required bool held, bool bindTrigger = true}) {
    final application = AcpClientApplication(transport: FakeAcpTransport());
    workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: [resolver],
    );
    parts = CodeLabShellParts.build(
      initialProfile: embeddedConnectionProfile,
      application: application,
      workspace: workspace,
      projectFolderPicker: picker,
      recentProjectsStore: recents,
      usageCsvSaver: FakeUsageCsvSaver(),
      directoryExists: (_) async => true,
      strings: TestAppStrings(AppLocalizationsEn()),
      logger: diagnostics,
      appLogger: events,
      localPathKind: (path) async => LocalPathKind.directory,
      projectStartHeld: held,
    );
    shell = CodeLabShellCubit(
      application: application,
      workspace: workspace,
      parts: parts,
      projectFolderPicker: picker,
      recentProjectsStore: recents,
    );
    addTearDown(shell.close);
    if (bindTrigger) {
      // Триггер заменён записью: проверяется только «вызван ли и с какой
      // папкой», настоящий старт — в тесте через `startOnLaunch`.
      parts.settings.bindProjectStart((project) async => started.add(project));
    }
  }

  final resolver = _CountingResolver(FakeAcpTransport());
  final picker = _Picker();
  final recents = _Recents();
  final diagnostics = RecordingLogger();
  final events = RecordingLogger();
  final started = <String>[];
  late final ClientWorkspace workspace;
  late final CodeLabShellParts parts;
  late final CodeLabShellCubit shell;

  SettingsCubit get settings => parts.settings;

  Iterable<Map<String, Object?>> heldEvents() =>
      events.entries.where((e) => e['event'] == 'project.start_held');

  Iterable<Map<String, Object?>> selectedDiagnostics(String path) => diagnostics
      .entries
      .where((e) => e['event'] == 'Selected project: $path.');
}

void main() {
  group('projectStartHeld: true', () {
    test('selectProject: проект выбран, недавние записаны, триггер не '
        'вызван, событие без пути', () async {
      final scene = _Scene(held: true);
      await scene.settings.projectRestored;

      await scene.settings.selectProject('/work/app');

      expect(scene.settings.projectDirectory, '/work/app');
      expect(scene.workspace.current.projectDirectory, '/work/app');
      expect(scene.recents.paths, ['/work/app']);
      expect(scene.selectedDiagnostics('/work/app'), hasLength(1));
      expect(scene.started, isEmpty);
      final held = scene.heldEvents();
      expect(held, hasLength(1));
      expect(held.single['level'], 'debug');
      expect(
        held.single.values.whereType<String>(),
        everyElement(isNot(contains('/work'))),
      );
    });

    test('принятый browseForProject не вызывает триггер', () async {
      final scene = _Scene(held: true);
      scene.picker.answer = '/work/picked';
      await scene.settings.projectRestored;

      await scene.settings.browseForProject();

      expect(scene.settings.projectDirectory, '/work/picked');
      expect(scene.recents.paths, ['/work/picked']);
      expect(scene.started, isEmpty);
      expect(scene.heldEvents(), hasLength(1));
    });

    test('принятый openDroppedPaths не вызывает триггер', () async {
      final scene = _Scene(held: true);
      await scene.settings.projectRestored;

      await scene.settings.openDroppedPaths(['/work/dropped']);

      expect(scene.settings.projectDirectory, '/work/dropped');
      expect(scene.recents.paths, ['/work/dropped']);
      expect(scene.selectedDiagnostics('/work/dropped'), hasLength(1));
      expect(scene.started, isEmpty);
      expect(scene.heldEvents(), hasLength(1));
    });

    test('releaseProjectStart снимает удержание и сам триггер не вызывает; '
        'следующий выбор вызывает триггер', () async {
      final scene = _Scene(held: true);
      await scene.settings.projectRestored;
      await scene.settings.selectProject('/work/a');

      scene.settings.releaseProjectStart();

      expect(scene.started, isEmpty);

      await scene.settings.selectProject('/work/b');

      expect(scene.started, ['/work/b']);
      expect(scene.heldEvents(), hasLength(1));
    });

    test('повторный releaseProjectStart безвреден', () async {
      final scene = _Scene(held: true);
      await scene.settings.projectRestored;

      scene.settings.releaseProjectStart();
      scene.settings.releaseProjectStart();
      await scene.settings.selectProject('/work/a');

      expect(scene.started, ['/work/a']);
    });

    test('CodeLabShellCubit.startOnLaunch снимает удержание: выбор под '
        'удержанием даёт ровно один старт с этой папкой', () async {
      final scene = _Scene(held: true, bindTrigger: false);
      await scene.settings.projectRestored;
      await scene.settings.selectProject('/work/app');
      await pumpEventQueue();

      expect(scene.resolver.opened, isEmpty);

      // Старт агента ждёт ответов fake-транспорта; наблюдаем только
      // открытие транспорта.
      unawaited(scene.shell.startOnLaunch());
      await pumpEventQueue();

      expect(scene.resolver.opened, ['/work/app']);

      // Удержание снято: следующий выбор — обычный триггер, а не событие
      // `project.start_held`.
      expect(scene.heldEvents(), hasLength(1));
    });
  });

  group('projectStartHeld: false', () {
    test('поведение прежнее: выбор вызывает триггер, события нет', () async {
      final scene = _Scene(held: false);
      await scene.settings.projectRestored;

      await scene.settings.selectProject('/work/app');

      expect(scene.started, ['/work/app']);
      expect(scene.heldEvents(), isEmpty);
    });

    test('releaseProjectStart без удержания ничего не меняет', () async {
      final scene = _Scene(held: false);
      await scene.settings.projectRestored;

      scene.settings.releaseProjectStart();
      await scene.settings.selectProject('/work/app');

      expect(scene.started, ['/work/app']);
    });
  });
}
