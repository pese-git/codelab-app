// Тесты JSON-хранилищ профилей и недавних проектов (tasks 5.3; spec
// acp-client-kit «IO-адаптеры клиента», «Профили сохраняются в JSON»;
// удаление профиля — tasks 2.3 change `add-codelab-cli`).

import 'dart:convert';
import 'dart:io';

import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:codelab_client_io/src/stores/json_file.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  test('parallel writes to one file leave one whole document', () async {
    final path = '${tmp.path}/shared/profiles.json';
    final documents = [
      for (var i = 0; i < 20; i++)
        {'writer': i, 'payload': List.filled(2000, i)},
    ];

    await Future.wait([for (final d in documents) writeJsonObject(path, d)]);

    final result = await readJsonObject(path);
    // Файл целиком совпадает с записью ровно одного писателя.
    expect(result, isNotNull);
    expect(result, equals(documents[result!['writer'] as int]));
    // Временные файлы не остаются рядом.
    expect(Directory('${tmp.path}/shared').listSync().map((e) => e.path), [
      path,
    ]);
  });

  test('a rewrite replaces the whole previous content', () async {
    final path = '${tmp.path}/profiles.json';
    await writeJsonObject(path, {'a': List.filled(500, 1), 'old': true});

    await writeJsonObject(path, {'b': 2});

    expect(await readJsonObject(path), {'b': 2});
  });

  test('a failed rename removes the temporary file', () async {
    // Цель — каталог: rename файла на каталог падает.
    final path = '${tmp.path}/target';
    Directory(path).createSync();
    File('$path/keep').writeAsStringSync('x');

    await expectLater(
      writeJsonObject(path, {'a': 1}),
      throwsA(isA<FileSystemException>()),
    );

    expect(tmp.listSync().map((e) => e.path), [
      path,
    ], reason: 'tmp-файл удалён');
  });

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

    test('remove() deletes a profile by id and reports whether it '
        'existed', () async {
      final path = '${tmp.path}/profiles.json';
      final store = JsonFileProfileStore(path);
      await store.save(remote);
      await store.save(local);

      expect(await store.remove('remote'), isTrue);
      expect(await store.remove('missing'), isFalse);

      expect(await JsonFileProfileStore(path).load(), [local]);
    });

    test('remove() without a file creates no file', () async {
      final path = '${tmp.path}/profiles.json';

      expect(await JsonFileProfileStore(path).remove('remote'), isFalse);
      expect(File(path).existsSync(), isFalse);
    });

    test('the file keeps the token reference, not a token value', () async {
      final path = '${tmp.path}/profiles.json';
      await JsonFileProfileStore(path).save(remote);

      final text = File(path).readAsStringSync();
      expect(text, contains('env:CODELAB_TOKEN'));
      expect(text, isNot(contains('"token"')));
    });

    test('an embedded profile is not saved: ArgumentError, file unchanged '
        '(D7)', () async {
      final path = '${tmp.path}/profiles.json';
      final store = JsonFileProfileStore(path);
      await store.save(remote);
      final before = File(path).readAsStringSync();

      await expectLater(
        store.save(
          const ConnectionProfile.embedded(
            id: 'embedded',
            label: 'Embedded agent',
            hostProfile: 'embedded-cli',
          ),
        ),
        throwsArgumentError,
      );

      expect(File(path).readAsStringSync(), before);
    });

    test('a profile with a reserved id is not saved: ArgumentError, file '
        'unchanged (spec «Записи профилей с зарезервированным id»; '
        'D21)', () async {
      final path = '${tmp.path}/profiles.json';
      final store = JsonFileProfileStore(path);
      await store.save(remote);
      final before = File(path).readAsStringSync();

      for (final id in reservedProfileIds) {
        await expectLater(
          store.save(StdioProfile(id: id, label: id, command: 'x')),
          throwsArgumentError,
          reason: id,
        );
      }

      expect(File(path).readAsStringSync(), before);
    });

    test('an old "default" record is loaded as is and remove deletes '
        'it (D21)', () async {
      final path = '${tmp.path}/profiles.json';
      File(path).writeAsStringSync(
        '{"version": 1, "profiles": [{"type": "stdio", "id": "default", '
        '"label": "Default", "command": "/opt/old", "args": [], "env": {}, '
        '"runInProjectDirectory": false}, {"type": "stdio", "id": "local", '
        '"label": "Local", "command": "x", "args": [], "env": {}, '
        '"runInProjectDirectory": false}]}',
      );
      final store = JsonFileProfileStore(path);

      expect((await store.load()).map((p) => p.id), ['default', 'local']);
      expect(await store.remove('default'), isTrue);
      expect((await store.load()).map((p) => p.id), ['local']);
    });

    test('a "type": "embedded" record is an unknown type on load '
        '(FormatException, D7)', () async {
      final path = '${tmp.path}/profiles.json';
      File(path).writeAsStringSync(
        '{"version": 1, "profiles": [{"type": "embedded", "id": "embedded", '
        '"label": "Embedded agent", "hostProfile": "embedded-cli"}]}',
      );

      await expectLater(
        JsonFileProfileStore(path).load(),
        throwsA(isA<FormatException>()),
      );
    });

    test('a structurally broken record is a FormatException, not a '
        'TypeError', () async {
      final path = '${tmp.path}/profiles.json';
      for (final profiles in [
        '["not an object"]',
        '[{"type": "stdio", "label": "x", "command": "c", "args": [], '
            '"env": {}}]',
        '[{"type": "stdio", "id": "x", "label": "x", "args": [], "env": {}}]',
        '[{"type": "webSocket", "id": "w", "label": "w"}]',
        '[{"type": "stdio", "id": "x", "label": "x", "command": "c", '
            '"args": "oops", "env": {}}]',
      ]) {
        File(path).writeAsStringSync('{"version": 1, "profiles": $profiles}');

        await expectLater(
          JsonFileProfileStore(path).load(),
          throwsA(isA<FormatException>()),
          reason: profiles,
        );
      }
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

    // --- Задача 1.3 change `share-recent-projects-store` (spec acp-client-kit
    // «Хранилище недавних проектов в CODELAB_HOME»; D1–D3). Красные до 1.4. ---

    group('shared file contract', () {
      late String path;

      setUp(() => path = '${tmp.path}/recent_projects.json');

      test(
        'most recent first, at most the limit, file has version 1',
        () async {
          var now = DateTime.utc(2026, 11, 22, 9);
          final store = JsonFileRecentProjectsStore(path, clock: () => now);

          for (var i = 0; i < recentProjectsLimit + 2; i++) {
            await store.record('/work/p$i');
            now = now.add(const Duration(minutes: 1));
          }
          await store.record('/work/p0');

          final loaded = await JsonFileRecentProjectsStore(path).load();
          expect(loaded, hasLength(recentProjectsLimit));
          expect(loaded.first.path, '/work/p0');
          expect(loaded.first.lastOpenedAt, now);
          final document = jsonDecode(File(path).readAsStringSync());
          expect((document as Map<String, Object?>)['version'], 1);
        },
      );

      test('two record() calls without awaiting both survive', () async {
        final store = JsonFileRecentProjectsStore(path);

        await Future.wait([store.record('/work/a'), store.record('/work/b')]);

        final loaded = await JsonFileRecentProjectsStore(path).load();
        expect(
          loaded.map((p) => p.path),
          unorderedEquals(['/work/a', '/work/b']),
        );
      });

      test('a broken file is not overwritten', () async {
        File(path).writeAsStringSync('{not json');
        final store = JsonFileRecentProjectsStore(path);

        await expectLater(store.load(), throwsA(isA<FormatException>()));
        await expectLater(
          store.record('/work/a'),
          throwsA(isA<FormatException>()),
        );

        expect(File(path).readAsStringSync(), '{not json');
      });

      test('an unknown version is not overwritten', () async {
        const content = '{"version": 2, "projects": []}';
        File(path).writeAsStringSync(content);

        await expectLater(
          JsonFileRecentProjectsStore(path).record('/work/a'),
          throwsA(isA<FormatException>()),
        );

        expect(File(path).readAsStringSync(), content);
      });

      test('a file without version is a FormatException', () async {
        File(path).writeAsStringSync('{"projects": []}');

        await expectLater(
          JsonFileRecentProjectsStore(path).load(),
          throwsA(isA<FormatException>()),
        );
      });

      test('a file of the wrong shape is a FormatException, not '
          'TypeError', () async {
        for (final document in [
          '[]',
          '{"version": 1}',
          '{"version": 1, "projects": {}}',
          '{"version": 1, "projects": [42]}',
          '{"version": 1, "projects": [{"path": 42, '
              '"lastOpenedAt": "2026-11-22T10:00:00.000"}]}',
          '{"version": 1, "projects": [{"path": "", '
              '"lastOpenedAt": "2026-11-22T10:00:00.000"}]}',
          '{"version": 1, "projects": [{"path": "/a"}]}',
          '{"version": 1, "projects": [{"path": "/a", "lastOpenedAt": 1}]}',
          '{"version": 1, "projects": [{"path": "/a", '
              '"lastOpenedAt": "not a date"}]}',
        ]) {
          File(path).writeAsStringSync(document);

          await expectLater(
            JsonFileRecentProjectsStore(path).load(),
            throwsA(isA<FormatException>()),
            reason: document,
          );
        }
      });

      test(
        'merge() takes the later time per path and keeps the order',
        () async {
          var now = DateTime.utc(2026, 11, 22, 9);
          final store = JsonFileRecentProjectsStore(path, clock: () => now);
          await store.record('/work/a');
          final incoming = [
            RecentProject(
              path: '/work/a',
              lastOpenedAt: DateTime.utc(2026, 11, 22, 11),
            ),
            RecentProject(
              path: '/work/c',
              lastOpenedAt: DateTime.utc(2026, 11, 22, 8),
            ),
          ];

          await store.merge(incoming);

          final loaded = await JsonFileRecentProjectsStore(path).load();
          expect(loaded.map((p) => p.path), ['/work/a', '/work/c']);
          expect(loaded.first.lastOpenedAt, DateTime.utc(2026, 11, 22, 11));
        },
      );

      test('merging the same list twice changes nothing', () async {
        final store = JsonFileRecentProjectsStore(path);
        final incoming = [
          RecentProject(
            path: '/work/a',
            lastOpenedAt: DateTime.utc(2026, 11, 22, 10),
          ),
          RecentProject(
            path: '/work/b',
            lastOpenedAt: DateTime.utc(2026, 11, 22, 9),
          ),
        ];

        await store.merge(incoming);
        final first = await store.load();
        await store.merge(incoming);

        expect(await store.load(), first);
      });

      test('merge() on an unreadable file fails and keeps the bytes', () async {
        File(path).writeAsStringSync('{not json');

        await expectLater(
          JsonFileRecentProjectsStore(path).merge([
            RecentProject(
              path: '/work/a',
              lastOpenedAt: DateTime.utc(2026, 11, 22, 10),
            ),
          ]),
          throwsA(isA<FormatException>()),
        );

        expect(File(path).readAsStringSync(), '{not json');
      });

      test('a failed operation does not cancel the next one in the '
          'queue', () async {
        File(path).writeAsStringSync('{not json');
        final store = JsonFileRecentProjectsStore(path);

        final failing = store.record('/work/a');
        // Пока первая операция в очереди, файл чинят: следующая должна
        // стартовать после неё, а не быть отменённой её ошибкой.
        final next = store.record('/work/b');
        await expectLater(failing, throwsA(isA<FormatException>()));
        File(path).deleteSync();
        // `next` уже стоит в очереди; её исход зависит от файла в момент
        // старта, но очередь обязана её выполнить, а не оборвать.
        await next.then<void>((_) {}, onError: (_) {});

        await store.record('/work/c');
        final loaded = await store.load();
        expect(loaded.map((p) => p.path), contains('/work/c'));
      });
    });
  });
}
