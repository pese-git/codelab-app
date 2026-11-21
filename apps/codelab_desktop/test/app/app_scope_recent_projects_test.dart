// Красные тесты задачи 2.1 change `share-recent-projects-store`: привязка
// `RecentProjectsStore` в composition root app (spec agent-workbench-ui
// «Recent projects persist across app restarts», сценарии «A project opened in
// the CLI appears in the app» и «Invalid CODELAB_HOME»; design.md D8).
//
// Почему обычный `test()`: файл настоящий, а в fake-async зоне `testWidgets`
// файловый ввод-вывод зависал бы (так же устроен `app_scope_profiles_test.dart`).
// Путь файла выводится из окружения шва `createCodeLabRootScope(environment:)`,
// поэтому тест не трогает настоящий `~/.codelab` разработчика.
//
// Красные до задачи 2.2: у `createCodeLabRootScope` нет параметра
// `recentProjectsStore`, а `RecentProjectsUnavailableException` ещё не
// существует — файл не компилируется.

import 'dart:io';

import 'package:cherrypick/cherrypick.dart' show Scope;
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show RecentProject, RecentProjectsStore;
import 'package:codelab_client_io/codelab_client_io.dart'
    show JsonFileRecentProjectsStore;
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/core/platform/recent_projects_migration.dart'
    show RecentProjectsUnavailableException;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_app_scope.dart';

/// Хранилище-двойник шва: доказывает, что `recentProjectsStore:` подменяет
/// привязку (D8).
final class _SeamStore implements RecentProjectsStore {
  @override
  Future<List<RecentProject>> load() async => [
    RecentProject(path: '/from/seam', lastOpenedAt: DateTime.utc(2026, 1, 1)),
  ];

  @override
  Future<void> record(String path) async {}
}

void main() {
  late Directory home;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    home = await Directory.systemTemp.createTemp('codelab_scope_recents_');
    addTearDown(() => home.delete(recursive: true));
  });

  Scope scopeWith({
    required Map<String, String> environment,
    RecentProjectsStore? recentProjectsStore,
  }) {
    final scope = createCodeLabRootScope(
      transportFactory: FakeAcpTransport.new,
      environment: environment,
      directoryExists: (_) async => true,
      logDirectoryPath: home.path,
      recentProjectsStore: recentProjectsStore,
    );
    addTearDown(closeCodeLabRootScopeInTest);
    return scope;
  }

  test('CODELAB_HOME of the environment seam: the store is the file '
      'recent_projects.json, shared with the CLI (D8)', () async {
    final scope = scopeWith(environment: {'CODELAB_HOME': home.path});
    final store = scope.resolve<RecentProjectsStore>();

    await store.record('/work/app');

    // Тот же файл читает другой экземпляр — как это делает CLI.
    final other = JsonFileRecentProjectsStore(
      '${home.path}/recent_projects.json',
    );
    expect([for (final p in await other.load()) p.path], ['/work/app']);
  });

  test('a list written by the CLI is what the app store loads', () async {
    await JsonFileRecentProjectsStore(
      '${home.path}/recent_projects.json',
    ).record('/work/cli-project');
    final scope = scopeWith(environment: {'CODELAB_HOME': home.path});

    final recents = await scope.resolve<RecentProjectsStore>().load();

    expect([for (final p in recents) p.path], ['/work/cli-project']);
  });

  test('invalid CODELAB_HOME: load fails with the reason, no file is '
      'created, the key of the earlier version is kept (D8)', () async {
    SharedPreferences.setMockInitialValues({'codelab.recent_projects': '[]'});
    final scope = scopeWith(
      environment: {'CODELAB_HOME': '~bob/cl', 'HOME': home.path},
    );
    final store = scope.resolve<RecentProjectsStore>();

    await expectLater(
      store.load(),
      throwsA(
        isA<RecentProjectsUnavailableException>().having(
          (e) => e.reason,
          'reason',
          isNotEmpty,
        ),
      ),
    );
    await expectLater(
      store.record('/work/app'),
      throwsA(isA<RecentProjectsUnavailableException>()),
    );
    expect(Directory('${home.path}/cl').existsSync(), isFalse);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'codelab.recent_projects',
      ),
      isTrue,
    );
    expect(File('${home.path}/recent_projects.json').existsSync(), isFalse);
  });

  test('the seam recentProjectsStore: replaces the binding', () async {
    final scope = scopeWith(
      environment: {'CODELAB_HOME': home.path},
      recentProjectsStore: _SeamStore(),
    );

    final recents = await scope.resolve<RecentProjectsStore>().load();

    expect([for (final p in recents) p.path], ['/from/seam']);
    expect(File('${home.path}/recent_projects.json').existsSync(), isFalse);
  });
}
