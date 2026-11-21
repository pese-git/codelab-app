// Открытие папки перетаскиванием (задача 3.3 change `add-empty-project-screen`;
// spec agent-workbench-ui «Открытие папки перетаскиванием»; design.md D4).
//
// Решение о брошенных элементах принимает `SettingsCubit.openDroppedPaths` по
// видам путей из порта `LocalPathKindOf`; виджет и плагин только передают
// список путей. Тест идёт через настоящие части рабочего места
// (`CodeLabShellParts.build`) с двойниками портов: вид пути, выбор папки,
// недавние проекты, триггер старта агента и два журнала (диагностика и
// события app).
//
// Красный до задачи 3.4: ни `LocalPathKindOf`, ни `openDroppedPaths`, ни
// `ProjectDropRejection` ещё нет, тест не компилируется. Типы отказов
// (`DropNotAFolder`, `DropMultiple`, `DropMissing`, `DropUnsupported`)
// импортируются через `settings_cubit.dart`: если реализация положит их в
// соседний файл `project_drop.dart`, `settings_cubit.dart` должен их
// реэкспортировать (или тест меняет импорт).

import 'dart:async';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/core/platform/local_path_kind.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/core/platform/startup_preferences.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/workbench/application/settings_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_strings.dart';
import '../../../support/fake_usage_csv_saver.dart';
import '../../../support/recording_logger.dart';

final class _FixedResolver implements TransportResolver {
  _FixedResolver(this.transport);

  final FakeAcpTransport transport;

  @override
  bool supports(ConnectionProfile profile) => true;

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async => transport;
}

/// Выбор папки, который завершает тест.
final class _Picker implements ProjectFolderPicker {
  var picks = 0;
  Completer<String?>? _open;

  @override
  Future<String?> pickFolder({String? initialDirectory}) {
    picks++;
    return (_open = Completer<String?>()).future;
  }

  void complete(String? path) => _open!.complete(path);
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

/// Вид пути: ответ из [kinds] сразу или после [gate]; [calls] — какие пути
/// проверялись (для «вид не запрашивается»).
final class _Kinds {
  final kinds = <String, LocalPathKind>{};
  final gates = <String, Completer<void>>{};
  final calls = <String>[];

  Future<LocalPathKind> call(String path) async {
    calls.add(path);
    final gate = gates[path];
    if (gate != null) await gate.future;
    return kinds[path] ?? LocalPathKind.missing;
  }
}

/// Порт чтения «Reopen the last project»: пока не открыт [gate], восстановление
/// проекта прошлого запуска стоит.
final class _GatedStartup implements StartupPreferences {
  final gate = Completer<void>();

  @override
  Future<StartupLoad> load() async {
    await gate.future;
    return const StartupLoad(true);
  }

  @override
  Future<void> save(bool reopenLastProject) async {}
}

final class _Scene {
  _Scene({StartupPreferences? startup}) {
    final application = AcpClientApplication(transport: FakeAcpTransport());
    workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: [_FixedResolver(FakeAcpTransport())],
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
      startupPreferences: startup,
      localPathKind: kinds.call,
    );
    addTearDown(parts.close);
    // Триггер старта агента (D13 п. 1) заменён записью: проверяется только
    // «вызван ли и с какой папкой», сам старт — в других тестах.
    parts.settings.bindProjectStart((project) async => started.add(project));
  }

  final picker = _Picker();
  final recents = _Recents();
  final kinds = _Kinds();
  final diagnostics = RecordingLogger();
  final events = RecordingLogger();
  final started = <String>[];
  late final ClientWorkspace workspace;
  late final CodeLabShellParts parts;

  SettingsCubit get settings => parts.settings;

  /// Диагностика проекта уровня и текста [text].
  Iterable<Map<String, Object?>> diagnostic(String level, String text) =>
      diagnostics.entries.where(
        (e) =>
            e['event'] == text &&
            e['level'] == level &&
            e['source'] == 'project',
      );

  List<Map<String, Object?>> dropEvents() => [
    for (final e in events.entries)
      if (e['event'] == 'project.drop') e,
  ];
}

void main() {
  group('брошенная папка', () {
    test(
      'открывает проект: недавние, триггер один раз, событие без пути',
      () async {
        final scene = _Scene();
        scene.kinds.kinds['/work/app'] = LocalPathKind.directory;
        await scene.settings.projectRestored;

        await scene.settings.openDroppedPaths(['/work/app']);

        expect(scene.settings.projectDirectory, '/work/app');
        expect(scene.settings.state.dropRejection, isNull);
        expect(scene.recents.paths, ['/work/app']);
        expect(scene.started, ['/work/app']);
        expect(scene.workspace.current.projectDirectory, '/work/app');
        expect(
          scene.diagnostic('info', 'Selected project: /work/app.'),
          hasLength(1),
        );
        final drops = scene.dropEvents();
        expect(drops, hasLength(1));
        expect(drops.single['outcome'], 'opened');
        expect(drops.single['count'], 1);
        expect(drops.single.values, isNot(contains('/work/app')));
      },
    );

    test('символическая ссылка на папку: путь берётся как отдала ОС, без '
        'раскрытия', () async {
      final scene = _Scene();
      scene.kinds.kinds['/work/link-to-app'] = LocalPathKind.directory;
      await scene.settings.projectRestored;

      await scene.settings.openDroppedPaths(['/work/link-to-app']);

      expect(scene.settings.projectDirectory, '/work/link-to-app');
    });

    test(
      'пакет macOS `.app` — папка: проект выбран (решение Q5 (а))',
      () async {
        final scene = _Scene();
        scene.kinds.kinds['/Applications/Foo.app'] = LocalPathKind.directory;
        await scene.settings.projectRestored;

        await scene.settings.openDroppedPaths(['/Applications/Foo.app']);

        expect(scene.settings.projectDirectory, '/Applications/Foo.app');
        expect(scene.started, ['/Applications/Foo.app']);
      },
    );
  });

  group('отказы', () {
    Future<_Scene> rejected(
      Map<String, LocalPathKind> kinds,
      List<String?> paths,
    ) async {
      final scene = _Scene();
      scene.kinds.kinds.addAll(kinds);
      await scene.settings.projectRestored;
      await scene.settings.openDroppedPaths(paths);
      return scene;
    }

    void expectNothingStarted(_Scene scene) {
      expect(scene.settings.projectDirectory, isNull);
      expect(scene.started, isEmpty);
      expect(scene.recents.paths, isEmpty);
    }

    test(
      'файл: DropNotAFolder, диагностика warning и событие без пути',
      () async {
        final scene = await rejected(
          {'/work/app/README.md': LocalPathKind.file},
          ['/work/app/README.md'],
        );

        expect(
          scene.settings.state.dropRejection,
          isA<DropNotAFolder>().having(
            (r) => r.path,
            'path',
            '/work/app/README.md',
          ),
        );
        expectNothingStarted(scene);
        expect(
          scene.diagnostic(
            'warning',
            'Dropped item rejected (not_a_folder): /work/app/README.md.',
          ),
          hasLength(1),
        );
        final event = scene.dropEvents().single;
        expect(event['outcome'], 'rejected');
        expect(event['reason'], 'not_a_folder');
        expect(
          event.values.whereType<String>(),
          everyElement(isNot(contains('/work'))),
        );
      },
    );

    test(
      'несколько элементов: DropMultiple, вид путей не запрашивается',
      () async {
        final scene = await rejected(
          {
            '/work/a': LocalPathKind.directory,
            '/work/b': LocalPathKind.directory,
          },
          ['/work/a', '/work/b'],
        );

        expect(
          scene.settings.state.dropRejection,
          isA<DropMultiple>().having((r) => r.count, 'count', 2),
        );
        expect(scene.kinds.calls, isEmpty);
        expectNothingStarted(scene);
        expect(
          scene.diagnostic(
            'warning',
            'Dropped items rejected (multiple): 2 items.',
          ),
          hasLength(1),
        );
        final event = scene.dropEvents().single;
        expect(event['reason'], 'multiple');
        expect(event['count'], 2);
      },
    );

    test('пропавший путь: DropMissing', () async {
      final scene = await rejected({}, ['/work/gone']);

      expect(
        scene.settings.state.dropRejection,
        isA<DropMissing>().having((r) => r.path, 'path', '/work/gone'),
      );
      expectNothingStarted(scene);
      expect(scene.dropEvents().single['reason'], 'missing');
    });

    for (final (name, paths, kinds)
        in <(String, List<String?>, Map<String, LocalPathKind>)>[
          ('null без локального пути', [null], {}),
          ('пустая строка', [''], {}),
          ('путь из пробелов', ['   '], {}),
          (
            'другой вид пути (устройство, сокет)',
            ['/dev/null'],
            {'/dev/null': LocalPathKind.other},
          ),
        ]) {
      test('$name: DropUnsupported', () async {
        final scene = await rejected(kinds, paths);

        expect(scene.settings.state.dropRejection, isA<DropUnsupported>());
        expectNothingStarted(scene);
        expect(scene.dropEvents().single['reason'], 'unsupported');
      });
    }

    test('пустой список — ничего не происходит', () async {
      final scene = await rejected({}, const []);

      expect(scene.settings.state.dropRejection, isNull);
      expect(scene.dropEvents(), isEmpty);
    });
  });

  group('сброс сообщения об отказе', () {
    test('clearDropRejection снимает отказ', () async {
      final scene = _Scene();
      await scene.settings.projectRestored;
      await scene.settings.openDroppedPaths(['/work/gone']);
      expect(scene.settings.state.dropRejection, isNotNull);

      scene.settings.clearDropRejection();

      expect(scene.settings.state.dropRejection, isNull);
    });

    test('любой выбор проекта (selectProject) снимает отказ', () async {
      final scene = _Scene();
      await scene.settings.projectRestored;
      await scene.settings.openDroppedPaths(['/work/gone']);

      await scene.settings.selectProject('/work/app');

      expect(scene.settings.state.dropRejection, isNull);
    });
  });

  group('поздний результат (корневой AGENTS.md §9, §12)', () {
    test('другой выбор во время проверки вида: побеждает выбор через «Open '
        'folder…», отказа нет, триггер один раз', () async {
      final scene = _Scene();
      scene.kinds.kinds['/work/dropped'] = LocalPathKind.directory;
      scene.kinds.gates['/work/dropped'] = Completer<void>();
      await scene.settings.projectRestored;

      final dropping = scene.settings.openDroppedPaths(['/work/dropped']);
      await pumpEventQueue();
      final browsing = scene.settings.browseForProject();
      await pumpEventQueue();
      scene.picker.complete('/work/picked');
      await browsing;
      scene.kinds.gates['/work/dropped']!.complete();
      await dropping;

      expect(scene.settings.projectDirectory, '/work/picked');
      expect(scene.settings.state.dropRejection, isNull);
      expect(scene.started, ['/work/picked']);
    });

    test('результат-отказ устаревшего броска тоже не показывается', () async {
      final scene = _Scene();
      scene.kinds.kinds['/work/file'] = LocalPathKind.file;
      scene.kinds.gates['/work/file'] = Completer<void>();
      await scene.settings.projectRestored;

      final dropping = scene.settings.openDroppedPaths(['/work/file']);
      await pumpEventQueue();
      await scene.settings.selectProject('/work/app');
      scene.kinds.gates['/work/file']!.complete();
      await dropping;

      expect(scene.settings.projectDirectory, '/work/app');
      expect(scene.settings.state.dropRejection, isNull);
    });

    test('бросок во время восстановления проекта: бросок побеждает', () async {
      final startup = _GatedStartup();
      final scene = _Scene(startup: startup);
      scene.kinds.kinds['/work/dropped'] = LocalPathKind.directory;

      await scene.settings.openDroppedPaths(['/work/dropped']);
      startup.gate.complete();
      await scene.settings.projectRestored;

      expect(scene.settings.projectDirectory, '/work/dropped');
      expect(scene.started, ['/work/dropped']);
    });

    test('close() во время проверки вида: ничего не выбрано', () async {
      final scene = _Scene();
      scene.kinds.kinds['/work/dropped'] = LocalPathKind.directory;
      scene.kinds.gates['/work/dropped'] = Completer<void>();
      await scene.settings.projectRestored;

      final dropping = scene.settings.openDroppedPaths(['/work/dropped']);
      await pumpEventQueue();
      await scene.settings.close();
      scene.kinds.gates['/work/dropped']!.complete();
      await dropping;

      expect(scene.started, isEmpty);
      expect(scene.recents.paths, isEmpty);
      expect(scene.workspace.current.projectDirectory, isNull);
    });
  });
}
