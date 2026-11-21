// Красные тесты задачи 4.1 change `share-recent-projects-store`: одноразовый
// перенос недавних проектов из `shared_preferences` в общий файл (spec
// agent-workbench-ui «Recent projects persist across app restarts», сценарии
// «Recents from an earlier version are moved once», «An unreadable recents
// file is kept»; design.md D4, D11).
//
// Решения пользователя 2026-11-22: Q1 (а) — список переносится как есть, без
// фильтрации; Q2 (б) — код переноса и этот тест удаляются change
// `remove-recent-projects-migration` до первого `stable` 1.0 (D9).
//
// Почему обычный `test()`: настоящий файл во временной папке и мок
// `SharedPreferences.setMockInitialValues`; в `testWidgets` файловый ввод-вывод
// зависал бы в fake-async зоне (D7).
//
// Красные до задачи 4.2: класса `MigratingRecentProjectsStore` ещё нет, файл не
// компилируется. Шов сбоя удаления ключа — параметр `legacyKeyRemover`
// (двойник, D4 п. 6); без него обёртка удаляет ключ в `shared_preferences`.

import 'dart:convert';
import 'dart:io';

import 'package:codelab_client_core/codelab_client_core.dart'
    show RecentProject;
import 'package:codelab_client_io/codelab_client_io.dart'
    show JsonFileRecentProjectsStore;
import 'package:codelab_desktop/core/platform/recent_projects_migration.dart'
    show MigratingRecentProjectsStore;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recording_logger.dart';

const _key = 'codelab.recent_projects';

/// Путь, которого не должно быть в событиях переноса (D11).
const _markerPath = '/secret-marker/project-xyz';

String _legacy(Map<String, DateTime> projects) => jsonEncode([
  for (final e in projects.entries)
    RecentProject(path: e.key, lastOpenedAt: e.value).toJson(),
]);

void main() {
  late Directory dir;
  late File file;
  late RecordingLogger logger;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('codelab_recents_migration_');
    addTearDown(() => dir.delete(recursive: true));
    file = File('${dir.path}/recent_projects.json');
    logger = RecordingLogger();
  });

  void legacyPrefs(String? value) =>
      SharedPreferences.setMockInitialValues({_key: ?value});

  MigratingRecentProjectsStore storeOf({
    Future<void> Function(String key)? legacyKeyRemover,
  }) => MigratingRecentProjectsStore(
    target: JsonFileRecentProjectsStore(file.path),
    logger: logger,
    legacyKeyRemover: legacyKeyRemover,
  );

  Future<List<String>> filePaths() async => [
    for (final p in await JsonFileRecentProjectsStore(file.path).load()) p.path,
  ];

  Future<bool> keyPresent() async =>
      (await SharedPreferences.getInstance()).containsKey(_key);

  List<Map<String, Object?>> events(String name) => [
    for (final e in logger.entries)
      if (e['event'] == name) e,
  ];

  test('merges with the file of the CLI: the later time wins, one entry per '
      'path, then the key is removed (Q1 (a): nothing is filtered)', () async {
    legacyPrefs(
      _legacy({
        '/work/old': DateTime.utc(2026, 1, 1, 9),
        '/tmp/smoke-run': DateTime.utc(2026, 1, 1, 7),
      }),
    );
    final target = JsonFileRecentProjectsStore(file.path);
    await target.merge([
      RecentProject(
        path: '/work/old',
        lastOpenedAt: DateTime.utc(2026, 1, 1, 10),
      ),
      RecentProject(
        path: '/work/cli',
        lastOpenedAt: DateTime.utc(2026, 1, 1, 8),
      ),
    ]);

    final loaded = await storeOf().load();

    expect(
      [for (final p in loaded) p.path],
      ['/work/old', '/work/cli', '/tmp/smoke-run'],
    );
    expect(loaded.first.lastOpenedAt.toUtc(), DateTime.utc(2026, 1, 1, 10));
    expect(await filePaths(), ['/work/old', '/work/cli', '/tmp/smoke-run']);
    expect(await keyPresent(), isFalse);
    expect(events('recent_projects.migrated').single['count'], 2);
  });

  test('the second start changes neither the file nor the key', () async {
    legacyPrefs(_legacy({'/work/old': DateTime.utc(2026, 1, 1, 9)}));
    await storeOf().load();
    final bytes = await file.readAsBytes();

    final again = await storeOf().load();

    expect([for (final p in again) p.path], ['/work/old']);
    expect(await file.readAsBytes(), bytes);
    expect(await keyPresent(), isFalse);
    expect(events('recent_projects.migrated'), hasLength(1));
  });

  test('no key: no file is created and no event is logged', () async {
    legacyPrefs(null);

    expect(await storeOf().load(), isEmpty);

    expect(file.existsSync(), isFalse);
    expect(
      logger.entries.where(
        (e) => '${e['event']}'.startsWith('recent_projects'),
      ),
      isEmpty,
    );
  });

  test('an unparseable key value: the key is removed, the file is not '
      'touched, a warning without fields (D4 item 3)', () async {
    legacyPrefs('{not json $_markerPath');
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'projects': [
          RecentProject(
            path: '/work/cli',
            lastOpenedAt: DateTime.utc(2026, 1, 1),
          ).toJson(),
        ],
      }),
    );
    final bytes = await file.readAsBytes();

    final loaded = await storeOf().load();

    expect([for (final p in loaded) p.path], ['/work/cli']);
    expect(await file.readAsBytes(), bytes);
    expect(await keyPresent(), isFalse);
    final event = events('recent_projects.legacy_unreadable').single;
    expect(event['level'], 'warning');
    expect('${logger.entries}', isNot(contains(_markerPath)));
  });

  test('an unreadable file: the key is kept, load and record throw '
      'FormatException, the bytes are unchanged (D4 item 5, D2)', () async {
    legacyPrefs(_legacy({_markerPath: DateTime.utc(2026, 1, 1, 9)}));
    await file.writeAsString('{not json}');
    final bytes = await file.readAsBytes();
    final store = storeOf();

    await expectLater(store.load(), throwsFormatException);
    await expectLater(store.record('/work/app'), throwsFormatException);

    expect(await file.readAsBytes(), bytes);
    expect(await keyPresent(), isTrue);
    final event = events('recent_projects.migration_failed').single;
    expect(event['level'], 'warning');
    expect(event['error_class'], 'FormatException');
    expect('${logger.entries}', isNot(contains(_markerPath)));
    expect('${logger.entries}', isNot(contains('/work/app')));
  });

  test('record called in parallel with the first load writes after the '
      'move: the file holds both records and the moved projects', () async {
    legacyPrefs(_legacy({'/work/old': DateTime.utc(2020, 1, 1)}));
    final store = storeOf();

    final recording = store.record('/work/new');
    final loading = store.load();
    await recording;
    await loading;

    expect(await filePaths(), containsAll(['/work/new', '/work/old']));
    expect((await filePaths()).first, '/work/new');
    expect(await keyPresent(), isFalse);
  });

  test('the key cannot be removed: the move is finished, load does not '
      'throw, the retry gives the same file (D4 item 6)', () async {
    legacyPrefs(_legacy({'/work/old': DateTime.utc(2026, 1, 1, 9)}));
    Future<void> failing(String key) async =>
        throw StateError('cannot remove $key: $_markerPath');

    final first = await storeOf(legacyKeyRemover: failing).load();

    expect([for (final p in first) p.path], ['/work/old']);
    expect(await keyPresent(), isTrue);
    final event = events('recent_projects.migration_failed').single;
    expect(event['error_class'], 'StateError');
    final bytes = await file.readAsBytes();

    final retry = await storeOf().load();

    expect([for (final p in retry) p.path], ['/work/old']);
    expect(await file.readAsBytes(), bytes);
    expect(await keyPresent(), isFalse);
  });

  test('events carry no project paths (D11)', () async {
    legacyPrefs(_legacy({_markerPath: DateTime.utc(2026, 1, 1, 9)}));

    await storeOf().load();

    expect(events('recent_projects.migrated').single['count'], 1);
    expect('${logger.entries}', isNot(contains(_markerPath)));
  });
}
