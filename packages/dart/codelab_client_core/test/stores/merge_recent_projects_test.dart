// Красные тесты правила слияния недавних проектов `mergeRecentProjects`
// (задача 1.1 change `share-recent-projects-store`; spec acp-client-kit
// «Хранилище недавних проектов в CODELAB_HOME», сценарии «Слияние по пути с
// более поздним временем» и «Повторное слияние ничего не меняет»; D5).
//
// Почему в kit: правило «одна запись на путь, последний первым, не больше
// `recentProjectsLimit`» общее для app и CLI, а `codelab_client_io` политики
// не содержит.

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

RecentProject project(String path, int hour, [int minute = 0]) => RecentProject(
  path: path,
  lastOpenedAt: DateTime.utc(2026, 11, 22, hour, minute),
);

void main() {
  test('one entry per path with the latest time, newest first', () {
    final merged = mergeRecentProjects(
      [project('/work/a', 10), project('/work/b', 9)],
      [project('/work/a', 11), project('/work/c', 8)],
    );

    expect(merged, [
      project('/work/a', 11),
      project('/work/b', 9),
      project('/work/c', 8),
    ]);
  });

  test('the later time wins regardless of which side holds it', () {
    final merged = mergeRecentProjects(
      [project('/work/a', 12)],
      [project('/work/a', 10)],
    );

    expect(merged, [project('/work/a', 12)]);
  });

  test('duplicates inside one input collapse to the latest entry', () {
    final merged = mergeRecentProjects([
      project('/work/a', 9),
      project('/work/a', 10),
    ], const []);

    expect(merged, [project('/work/a', 10)]);
  });

  test('equal times keep the order of appearance: entries of a first', () {
    final merged = mergeRecentProjects(
      [project('/work/a', 10)],
      [project('/work/b', 10)],
    );

    expect(merged.map((p) => p.path), ['/work/a', '/work/b']);

    final swapped = mergeRecentProjects(
      [project('/work/b', 10)],
      [project('/work/a', 10)],
    );

    expect(swapped.map((p) => p.path), ['/work/b', '/work/a']);
  });

  test('paths are compared as exact strings', () {
    final merged = mergeRecentProjects(
      [project('/work/a', 10)],
      [project('/work/a/', 9), project('/work/A', 8)],
    );

    expect(merged.map((p) => p.path), ['/work/a', '/work/a/', '/work/A']);
  });

  test('is truncated to recentProjectsLimit, oldest dropped', () {
    final a = [
      for (var i = 0; i < recentProjectsLimit; i++) project('/work/a$i', 10, i),
    ];
    final b = [for (var i = 0; i < 3; i++) project('/work/b$i', 11, i)];

    final merged = mergeRecentProjects(a, b);

    expect(merged, hasLength(recentProjectsLimit));
    expect(merged.first.path, '/work/b2');
    // Три самых старых записи `a` отброшены.
    expect(merged.map((p) => p.path), isNot(contains('/work/a0')));
    expect(merged.map((p) => p.path), isNot(contains('/work/a1')));
    expect(merged.map((p) => p.path), isNot(contains('/work/a2')));
    expect(merged.last.path, '/work/a3');
  });

  test('empty inputs give an empty list', () {
    expect(mergeRecentProjects(const [], const []), isEmpty);
  });

  test('one empty input returns the other, sorted and limited', () {
    final entries = [project('/work/old', 8), project('/work/new', 9)];

    expect(mergeRecentProjects(entries, const []), [
      project('/work/new', 9),
      project('/work/old', 8),
    ]);
    expect(mergeRecentProjects(const [], entries), [
      project('/work/new', 9),
      project('/work/old', 8),
    ]);
  });

  test('merging the result with the same input again changes nothing', () {
    final input = [project('/work/a', 10), project('/work/b', 9)];
    final once = mergeRecentProjects(input, [project('/work/c', 8)]);

    expect(mergeRecentProjects(input, once), once);
  });

  test('does not mutate its inputs', () {
    final a = [project('/work/a', 10)];
    final b = [project('/work/a', 11)];

    mergeRecentProjects(a, b);

    expect(a, [project('/work/a', 10)]);
    expect(b, [project('/work/a', 11)]);
  });
}
