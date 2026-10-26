// Тесты JSON-хранилищ профилей и недавних проектов (tasks 5.3; spec
// acp-client-kit «IO-адаптеры клиента», «Профили сохраняются в JSON»).

import 'dart:io';

import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('acp_client_io_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('JsonFileProfileStore', () {
    final remote = WebSocketProfile(
      id: 'remote',
      label: 'Remote agent',
      uri: Uri.parse('wss://agent.example.test/acp'),
      tokenRef: 'env:CODELAB_TOKEN',
    );
    const local = StdioProfile(
      id: 'local',
      label: 'Local agent',
      command: 'codelab-agent',
      args: ['serve', '--stdio'],
      env: {'CODELAB_LOG_LEVEL': 'debug'},
      runInProjectDirectory: true,
    );

    test('no file means no profiles', () async {
      final store = JsonFileProfileStore('${tmp.path}/profiles.json');

      expect(await store.load(), isEmpty);
    });

    test('saved profiles are restored in full by a new store', () async {
      final path = '${tmp.path}/.codelab/profiles.json';
      final store = JsonFileProfileStore(path);

      await store.save(remote);
      await store.save(local);

      expect(await JsonFileProfileStore(path).load(), [remote, local]);
    });

    test('saving a profile with a known id replaces it in place', () async {
      final store = JsonFileProfileStore('${tmp.path}/profiles.json');
      await store.save(remote);
      await store.save(local);

      await store.save(remote.copyWith(label: 'Renamed'));

      final loaded = await store.load();
      expect(loaded.map((profile) => profile.label), [
        'Renamed',
        'Local agent',
      ]);
    });

    test('the file keeps the token reference, not a token value', () async {
      final path = '${tmp.path}/profiles.json';
      await JsonFileProfileStore(path).save(remote);

      final text = File(path).readAsStringSync();
      expect(text, contains('env:CODELAB_TOKEN'));
      expect(text, isNot(contains('"token"')));
    });

    test('a broken file is a FormatException, not silently empty', () async {
      final path = '${tmp.path}/profiles.json';
      File(path).writeAsStringSync('{not json');

      await expectLater(
        JsonFileProfileStore(path).load(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('JsonFileRecentProjectsStore', () {
    test('no file means no recent projects', () async {
      final store = JsonFileRecentProjectsStore('${tmp.path}/recent.json');

      expect(await store.load(), isEmpty);
    });

    test('record() moves a path to the front and survives a new '
        'store', () async {
      final path = '${tmp.path}/recent.json';
      var now = DateTime.utc(2026, 10, 26, 9);
      final store = JsonFileRecentProjectsStore(path, clock: () => now);

      await store.record('/work/a');
      now = now.add(const Duration(minutes: 1));
      await store.record('/work/b');
      now = now.add(const Duration(minutes: 1));
      await store.record('/work/a');

      final loaded = await JsonFileRecentProjectsStore(path).load();
      expect(loaded.map((project) => project.path), ['/work/a', '/work/b']);
      expect(loaded.first.lastOpenedAt, now);
    });

    test('keeps at most recentProjectsLimit entries', () async {
      final store = JsonFileRecentProjectsStore('${tmp.path}/recent.json');

      for (var i = 0; i < recentProjectsLimit + 3; i++) {
        await store.record('/work/project-$i');
      }

      final loaded = await store.load();
      expect(loaded, hasLength(recentProjectsLimit));
      expect(loaded.first.path, '/work/project-${recentProjectsLimit + 2}');
    });
  });
}
