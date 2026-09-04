import 'package:codelab_app/core/platform/shared_preferences_recent_projects_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('record then load returns the recorded path', () async {
    const store = SharedPreferencesRecentProjectsStore();

    await store.record('/workspace/project-a');

    final recents = await store.load();
    expect(recents, hasLength(1));
    expect(recents.single.path, '/workspace/project-a');
  });

  test('recording an already-known path moves it to the front instead of '
      'duplicating it', () async {
    const store = SharedPreferencesRecentProjectsStore();

    await store.record('/workspace/project-a');
    await store.record('/workspace/project-b');
    await store.record('/workspace/project-a');

    final recents = await store.load();
    expect(recents.map((entry) => entry.path), [
      '/workspace/project-a',
      '/workspace/project-b',
    ]);
  });

  test(
    'exceeding the recents limit drops the least recently opened entries',
    () async {
      const store = SharedPreferencesRecentProjectsStore();

      for (var i = 0; i < kRecentProjectsLimit + 3; i++) {
        await store.record('/workspace/project-$i');
      }

      final recents = await store.load();
      expect(recents, hasLength(kRecentProjectsLimit));
      // Most-recently-recorded entries survive; the earliest ones are gone.
      expect(
        recents.first.path,
        '/workspace/project-${kRecentProjectsLimit + 2}',
      );
      expect(
        recents.map((entry) => entry.path),
        isNot(contains('/workspace/project-0')),
      );
    },
  );

  test('load returns an empty list when nothing has been recorded', () async {
    const store = SharedPreferencesRecentProjectsStore();

    expect(await store.load(), isEmpty);
  });
}
