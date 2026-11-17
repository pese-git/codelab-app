// Чистая функция построения строк дерева (задача 2.7 change
// `add-file-preview-and-tree`; design.md D1, D6): плоский список из
// перечислений раскрытых папок. Красный тест написан с задачей 2.6.

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/project_files/application/project_tree_rows.dart';
import 'package:codelab_ui/codelab_ui.dart' show CodeLabFileTreeRowKind;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_project_files.dart';

void main() {
  final listings = {
    '': listingOf('', [
      dirEntry('lib'),
      dirEntry('docs'),
      fileEntry('README.md'),
      outsideEntry('secrets'),
    ]),
    'lib': listingOf('lib', [dirEntry('lib/src'), fileEntry('lib/a.dart')]),
    'lib/src': listingOf('lib/src', [fileEntry('lib/src/b.dart')]),
  };

  test('a collapsed root lists only its own entries at depth 0', () {
    final rows = buildProjectTreeRows(listings: listings, expanded: {});

    expect(
      [for (final r in rows) r.relativePath],
      ['lib', 'docs', 'README.md', 'secrets'],
    );
    expect(rows.every((r) => r.depth == 0), isTrue);
    expect(rows.every((r) => !r.expanded), isTrue);
  });

  test('children follow their folder with a deeper indent and folders keep '
      'their expanded flag', () {
    final rows = buildProjectTreeRows(
      listings: listings,
      expanded: {'lib', 'lib/src'},
    );

    expect(
      [for (final r in rows) r.relativePath],
      [
        'lib',
        'lib/src',
        'lib/src/b.dart',
        'lib/a.dart',
        'docs',
        'README.md',
        'secrets',
      ],
    );
    expect([for (final r in rows) r.depth], [0, 1, 2, 1, 0, 0, 0]);
    expect(rows[0].expanded, isTrue);
    expect(rows[1].expanded, isTrue);
    expect(rows[4].expanded, isFalse);
  });

  test('an expanded folder without a listing yet is marked loading', () {
    final rows = buildProjectTreeRows(
      listings: listings,
      expanded: {'docs'},
      loading: {'docs'},
    );

    final docs = rows.firstWhere((r) => r.relativePath == 'docs');
    expect(docs.loading, isTrue);
    expect(docs.expanded, isTrue);
    expect(rows.where((r) => r.depth > 0), isEmpty);
  });

  test('a failed folder gets one error row right below it', () {
    final rows = buildProjectTreeRows(
      listings: listings,
      expanded: {'docs'},
      failed: {'docs'},
    );

    final i = rows.indexWhere((r) => r.relativePath == 'docs');
    expect(rows[i + 1].kind, CodeLabFileTreeRowKind.error);
    expect(rows[i + 1].depth, 1);
    expect(rows[i + 1].relativePath, 'docs/\u0000error');
  });

  test('omitted entries add a “… N more” row after the folder entries', () {
    final rows = buildProjectTreeRows(
      listings: {
        '': listingOf('', [dirEntry('big')]),
        'big': listingOf('big', [fileEntry('big/a')], omitted: 42),
      },
      expanded: {'big'},
    );

    expect(
      [for (final r in rows) r.relativePath],
      ['big', 'big/a', 'big/\u0000more'],
    );
    expect(rows.last.kind, CodeLabFileTreeRowKind.more);
    expect(rows.last.name, '… 42 more');
    expect(rows.last.depth, 1);
  });

  test('synthetic rows never share a key with a real entry named #more or '
      '#error', () {
    final rows = buildProjectTreeRows(
      listings: {
        '': listingOf('', [fileEntry('#more'), dirEntry('#error')], omitted: 7),
      },
      expanded: {'#error'},
      failed: {'#error'},
    );

    final keys = [for (final r in rows) r.relativePath];
    expect(keys.toSet(), hasLength(keys.length), reason: '$keys');
    expect(keys, containsAll(['#more', '#error']));
    expect(rows.last.kind, CodeLabFileTreeRowKind.more);
    expect(rows.last.relativePath, isNot('#more'));
  });

  test('entry kinds map to row kinds', () {
    final rows = buildProjectTreeRows(
      listings: {
        '': listingOf('', [
          dirEntry('d'),
          fileEntry('f'),
          outsideEntry('o'),
          const ProjectEntry(
            relativePath: 'x',
            name: 'x',
            kind: ProjectEntryKind.other,
          ),
        ]),
      },
      expanded: {},
    );

    expect(
      [for (final r in rows) r.kind],
      [
        CodeLabFileTreeRowKind.directory,
        CodeLabFileTreeRowKind.file,
        CodeLabFileTreeRowKind.outsideLink,
        CodeLabFileTreeRowKind.other,
      ],
    );
  });

  test('without the root listing there are no rows', () {
    expect(buildProjectTreeRows(listings: {}, expanded: {}), isEmpty);
  });
}
