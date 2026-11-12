// `ProjectFilesCubit` (задача 2.6 change `add-file-preview-and-tree`; spec
// workspace-file-browser «Панель Files в доке инструментов» — «Корень без
// сессии», «Смена сессии в фокусе»; «Ленивое перечисление папок» —
// «Раскрытие папки читает один уровень», «Refresh показывает новый файл»;
// «Просмотр файла только для чтения» — «Поздний результат чтения»; «Граница
// рабочей папки браузера»; design.md D5, D6).
//
// Порт `ProjectFiles` — двойник (`fake_project_files.dart`): настоящая
// файловая система здесь не нужна. Поздние результаты воспроизводятся
// придерживанием ответа двойника и его отпусканием после смены файла или
// корня.

import 'dart:async';
import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/project_files/application/project_files_cubit.dart';
import 'package:codelab_desktop/features/project_files/application/project_tree_state.dart';
import 'package:codelab_ui/codelab_ui.dart' show CodeLabFileTreeRowKind;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_project_files.dart';
import '../../support/fake_provider_settings.dart' show FakeWorkspace;
import '../../support/recording_logger.dart';

SessionSummaryView _session(String id, String cwd) => SessionSummaryView(
  id: SessionId(id),
  cwd: cwd,
  status: SessionStatusView.idle,
);

WorkspaceState _stateOf({
  String? project,
  List<SessionSummaryView> sessions = const [],
  String? active,
}) => WorkspaceState(
  projectDirectory: project,
  sessions: sessions,
  activeSessionId: active == null ? null : SessionId(active),
);

List<String> _paths(ProjectTreeState state) => [
  for (final row in state.rows) row.relativePath,
];

void main() {
  late FakeProjectFiles files;
  late FakeWorkspace workspace;
  late RecordingLogger logger;
  late ProjectFilesCubit cubit;

  ProjectFilesCubit make(WorkspaceState initial) {
    workspace = FakeWorkspace(initial);
    cubit = ProjectFilesCubit(
      files: files,
      workspace: workspace,
      logger: logger,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> settle() => pumpEventQueue();

  setUp(() {
    logger = RecordingLogger();
    files = FakeProjectFiles(
      listings: {
        '/work/app': {
          '': listingOf('', [
            dirEntry('lib'),
            dirEntry('docs'),
            fileEntry('README.md'),
            fileEntry('.env'),
            outsideEntry('secrets'),
          ]),
          'lib': listingOf('lib', [
            dirEntry('lib/src'),
            fileEntry('lib/a.dart'),
          ]),
          'lib/src': listingOf('lib/src', [fileEntry('lib/src/b.dart')]),
          'docs': listingOf('docs', [fileEntry('docs/x.md')]),
        },
        '/work/b': {
          '': listingOf('', [dirEntry('pkg'), fileEntry('b.txt')]),
          'pkg': listingOf('pkg', [fileEntry('pkg/c.txt')]),
        },
      },
      files: {
        '/work/app': {
          'README.md': const TextPreview('# readme'),
          '.env': const TextPreview('API_KEY=test-marker'),
          'lib/a.dart': const TextPreview('class A {}'),
          'lib/src/b.dart': const TextPreview('class B {}'),
          'big.bin': const TooLargePreview(3 << 20),
        },
        '/work/b': {'b.txt': const TextPreview('bee')},
      },
    );
  });

  group('root', () {
    test('without a project and a session there is no folder', () async {
      make(_stateOf());
      await settle();

      expect(cubit.state.status, ProjectTreeStatus.noFolder);
      expect(cubit.state.rows, isEmpty);
      expect(files.canonicalCalls, isEmpty);
    });

    test('without a session the root is the selected project folder: '
        'loading, then ready with one listing of the root', () async {
      final states = <ProjectTreeStatus>[];
      make(_stateOf(project: '/work/app'));
      final sub = cubit.stream.listen((s) => states.add(s.status));
      addTearDown(sub.cancel);
      expect(cubit.state.status, ProjectTreeStatus.loading);
      await settle();

      expect(states, [ProjectTreeStatus.ready]);
      expect(cubit.state.root, '/work/app');
      expect(files.canonicalCalls, ['/work/app']);
      expect(files.listCalls, [('/work/app', '')]);
      // Папки первыми — порядок записей задаёт порт.
      expect(_paths(cubit.state), [
        'lib',
        'docs',
        'README.md',
        '.env',
        'secrets',
      ]);
      expect(cubit.state.rows.last.kind, CodeLabFileTreeRowKind.outsideLink);
    });

    test('the root is the realpath given by the port', () async {
      files.roots['/tmp/app'] = '/work/app';
      make(_stateOf(project: '/tmp/app'));
      await settle();

      expect(cubit.state.root, '/work/app');
      expect(files.listCalls, [('/work/app', '')]);
    });

    test(
      'a missing folder makes the pane unavailable and lists nothing',
      () async {
        files.missingFolders.add('/gone');
        make(_stateOf(project: '/gone'));
        await settle();

        expect(cubit.state.status, ProjectTreeStatus.unavailable);
        expect(cubit.state.rows, isEmpty);
        expect(files.listCalls, isEmpty);
      },
    );

    test(
      'the cwd of the focused session wins over the project folder',
      () async {
        make(
          _stateOf(
            project: '/work/app',
            sessions: [_session('s1', '/work/b')],
            active: 's1',
          ),
        );
        await settle();

        expect(cubit.state.root, '/work/b');
        // Второй вызов — realpath папки проекта для подписи «outside» (Q18).
        expect(files.canonicalCalls, ['/work/b', '/work/app']);
      },
    );

    test('focusing another session switches the tree and a late reading of '
        'the old root changes nothing', () async {
      make(
        _stateOf(
          project: '/work/app',
          sessions: [_session('s1', '/work/app'), _session('s2', '/work/b')],
          active: 's1',
        ),
      );
      await settle();
      final gate = files.gateRead('/work/app', 'README.md');
      final late = cubit.selectFile('README.md');
      await settle();
      expect(cubit.state.preview, isA<PreviewLoading>());

      workspace.emit(
        _stateOf(
          project: '/work/app',
          sessions: [_session('s1', '/work/app'), _session('s2', '/work/b')],
          active: 's2',
        ),
      );
      await settle();
      expect(cubit.state.root, '/work/b');
      expect(_paths(cubit.state), ['pkg', 'b.txt']);
      expect(cubit.state.preview, isA<PreviewNone>());

      gate.complete();
      await late;
      await settle();

      expect(cubit.state.root, '/work/b');
      expect(cubit.state.selected, isNull);
      expect(cubit.state.preview, isA<PreviewNone>());
    });

    test('a late listing of the old root is dropped', () async {
      final gate = files.gateList('/work/app', '');
      make(
        _stateOf(project: '/work/app', sessions: [_session('s2', '/work/b')]),
      );
      await settle();
      expect(cubit.state.status, ProjectTreeStatus.loading);

      workspace.emit(
        _stateOf(
          project: '/work/app',
          sessions: [_session('s2', '/work/b')],
          active: 's2',
        ),
      );
      await settle();
      expect(cubit.state.root, '/work/b');

      gate.complete();
      await settle();

      expect(cubit.state.root, '/work/b');
      expect(_paths(cubit.state), ['pkg', 'b.txt']);
    });

    test('a workspace change that keeps the folder does not reload', () async {
      make(_stateOf(project: '/work/app'));
      await settle();

      workspace.emit(_stateOf(project: '/work/app'));
      await settle();

      expect(files.canonicalCalls, ['/work/app']);
      expect(files.listCalls, hasLength(1));
    });

    test(
      'expanded folders are remembered per root when focus returns',
      () async {
        make(
          _stateOf(
            project: '/work/app',
            sessions: [_session('s1', '/work/app'), _session('s2', '/work/b')],
            active: 's1',
          ),
        );
        await settle();
        await cubit.toggleDirectory('lib');
        await settle();
        expect(cubit.state.expanded, {'lib'});

        workspace.emit(
          _stateOf(
            project: '/work/app',
            sessions: [_session('s1', '/work/app'), _session('s2', '/work/b')],
            active: 's2',
          ),
        );
        await settle();
        expect(cubit.state.expanded, isEmpty);

        workspace.emit(
          _stateOf(
            project: '/work/app',
            sessions: [_session('s1', '/work/app'), _session('s2', '/work/b')],
            active: 's1',
          ),
        );
        await settle();

        expect(cubit.state.expanded, {'lib'});
        expect(
          _paths(cubit.state),
          containsAllInOrder(['lib', 'lib/src', 'lib/a.dart']),
        );
      },
    );
  });

  group('listing', () {
    test('expanding a folder reads exactly one level', () async {
      make(_stateOf(project: '/work/app'));
      await settle();
      files.listCalls.clear();

      await cubit.toggleDirectory('lib');
      await settle();

      expect(files.listCalls, [('/work/app', 'lib')]);
      expect(_paths(cubit.state), [
        'lib',
        'lib/src',
        'lib/a.dart',
        'docs',
        'README.md',
        '.env',
        'secrets',
      ]);
      expect(cubit.state.rows[1].depth, 1);
      expect(cubit.state.rows.first.expanded, isTrue);
    });

    test('a folder shows progress while its listing is in flight', () async {
      make(_stateOf(project: '/work/app'));
      await settle();
      final gate = files.gateList('/work/app', 'lib');

      final pending = cubit.toggleDirectory('lib');
      await settle();
      expect(cubit.state.rows.first.loading, isTrue);

      gate.complete();
      await pending;
      await settle();
      expect(cubit.state.rows.first.loading, isFalse);
    });

    test(
      'collapsing hides the children and expanding again lists again',
      () async {
        make(_stateOf(project: '/work/app'));
        await settle();
        await cubit.toggleDirectory('lib');
        await settle();

        await cubit.toggleDirectory('lib');
        await settle();
        expect(cubit.state.expanded, isEmpty);
        expect(_paths(cubit.state), [
          'lib',
          'docs',
          'README.md',
          '.env',
          'secrets',
        ]);

        files.listCalls.clear();
        await cubit.toggleDirectory('lib');
        await settle();
        expect(files.listCalls, [('/work/app', 'lib')]);
      },
    );

    test('a listing that arrives after collapsing is dropped', () async {
      make(_stateOf(project: '/work/app'));
      await settle();
      final gate = files.gateList('/work/app', 'lib');

      final pending = cubit.toggleDirectory('lib');
      await settle();
      await cubit.toggleDirectory('lib');
      await settle();
      expect(cubit.state.expanded, isEmpty);

      gate.complete();
      await pending;
      await settle();

      expect(cubit.state.expanded, isEmpty);
      expect(_paths(cubit.state), [
        'lib',
        'docs',
        'README.md',
        '.env',
        'secrets',
      ]);
    });

    test('a failed folder gets an error row below it and the rest of the '
        'tree stays', () async {
      files.failingDirs[('/work/app', 'lib')] =
          ProjectFilesFailureKind.unreadable;
      make(_stateOf(project: '/work/app'));
      await settle();

      await cubit.toggleDirectory('lib');
      await settle();

      final rows = cubit.state.rows;
      expect(rows[0].relativePath, 'lib');
      expect(rows[1].kind, CodeLabFileTreeRowKind.error);
      expect(rows[1].depth, 1);
      expect(rows.map((r) => r.relativePath), contains('README.md'));
      expect(cubit.state.status, ProjectTreeStatus.ready);
    });

    test('links outside the root and special files cannot be expanded or '
        'selected', () async {
      make(_stateOf(project: '/work/app'));
      await settle();
      files.listCalls.clear();

      await cubit.toggleDirectory('secrets');
      await cubit.selectFile('secrets');
      await cubit.toggleDirectory('README.md');
      await settle();

      expect(files.listCalls, isEmpty);
      expect(files.readCalls, isEmpty);
      expect(cubit.state.expanded, isEmpty);
      expect(cubit.state.selected, isNull);
    });

    test('an omitted tail becomes the “… N more” row', () async {
      files.listings['/work/app']![''] = listingOf('', [
        fileEntry('a'),
      ], omitted: 5000);
      make(_stateOf(project: '/work/app'));
      await settle();

      final more = cubit.state.rows.last;
      expect(more.kind, CodeLabFileTreeRowKind.more);
      expect(more.name, '… 5000 more');
    });

    test('Refresh re-reads the root and the expanded folders and shows a '
        'new file, keeping folders expanded', () async {
      make(_stateOf(project: '/work/app'));
      await settle();
      await cubit.toggleDirectory('lib');
      await settle();
      files.listCalls.clear();

      files.listings['/work/app']!['lib'] = listingOf('lib', [
        dirEntry('lib/src'),
        fileEntry('lib/a.dart'),
        fileEntry('lib/b.dart'),
      ]);
      await cubit.refresh();
      await settle();

      expect(files.listCalls.toSet(), {
        ('/work/app', ''),
        ('/work/app', 'lib'),
      });
      expect(files.listCalls, hasLength(2));
      expect(_paths(cubit.state), contains('lib/b.dart'));
      expect(cubit.state.expanded, {'lib'});
    });

    test('Refresh also re-reads the selected file', () async {
      make(_stateOf(project: '/work/app'));
      await settle();
      await cubit.selectFile('README.md');
      await settle();
      files.readCalls.clear();
      files.files['/work/app']!['README.md'] = const TextPreview('# new');

      await cubit.refresh();
      await settle();

      expect(files.readCalls, [('/work/app', 'README.md')]);
      final preview = cubit.state.preview as PreviewShown;
      expect((preview.preview as TextPreview).text, '# new');
    });

    test('pressing Refresh again while it runs is ignored', () async {
      make(_stateOf(project: '/work/app'));
      await settle();
      files.listCalls.clear();
      final gate = files.gateList('/work/app', '');

      final first = cubit.refresh();
      await settle();
      final second = cubit.refresh();
      await settle();
      gate.complete();
      await Future.wait([first, second]);
      await settle();

      expect(files.listCalls, hasLength(1));

      files.listCalls.clear();
      await cubit.refresh();
      expect(files.listCalls, hasLength(1));
    });

    test('Refresh without a folder does nothing', () async {
      make(_stateOf());
      await cubit.refresh();

      expect(files.listCalls, isEmpty);
    });
  });

  group('preview', () {
    test('a file goes loading then shown, without the secret flag', () async {
      make(_stateOf(project: '/work/app'));
      await settle();
      final gate = files.gateRead('/work/app', 'README.md');

      final pending = cubit.selectFile('README.md');
      await settle();
      expect(cubit.state.selected, 'README.md');
      expect((cubit.state.preview as PreviewLoading).path, 'README.md');

      gate.complete();
      await pending;
      await settle();

      final shown = cubit.state.preview as PreviewShown;
      expect(shown.path, 'README.md');
      expect((shown.preview as TextPreview).text, '# readme');
      expect(shown.maybeSecret, isFalse);
      expect(shown.line, isNull);
    });

    test('a secret-like file name sets the secret flag but keeps the '
        'content', () async {
      make(_stateOf(project: '/work/app'));
      await settle();

      await cubit.selectFile('.env');
      await settle();

      final shown = cubit.state.preview as PreviewShown;
      expect(shown.maybeSecret, isTrue);
      expect((shown.preview as TextPreview).text, 'API_KEY=test-marker');
    });

    test('a nested file is read by its relative path', () async {
      make(_stateOf(project: '/work/app'));
      await settle();
      await cubit.toggleDirectory('lib');
      await settle();

      await cubit.selectFile('lib/a.dart');
      await settle();

      expect(files.readCalls, [('/work/app', 'lib/a.dart')]);
    });

    test(
      'the reading of a file that is no longer selected is dropped',
      () async {
        files.files['/work/app']!['a.txt'] = const TextPreview('A');
        files.files['/work/app']!['b.txt'] = const TextPreview('B');
        files.listings['/work/app']![''] = listingOf('', [
          fileEntry('a.txt'),
          fileEntry('b.txt'),
        ]);
        make(_stateOf(project: '/work/app'));
        await settle();
        final gateA = files.gateRead('/work/app', 'a.txt');

        final first = cubit.selectFile('a.txt');
        await settle();
        final second = cubit.selectFile('b.txt');
        await settle();
        expect(cubit.state.selected, 'b.txt');

        gateA.complete();
        await Future.wait([first, second]);
        await settle();

        final shown = cubit.state.preview as PreviewShown;
        expect(shown.path, 'b.txt');
        expect((shown.preview as TextPreview).text, 'B');
        expect(cubit.state.selected, 'b.txt');
      },
    );

    test('binary and too large results are kept as they are', () async {
      files.listings['/work/app']![''] = listingOf('', [fileEntry('big.bin')]);
      make(_stateOf(project: '/work/app'));
      await settle();

      await cubit.selectFile('big.bin');
      await settle();

      final shown = cubit.state.preview as PreviewShown;
      expect(shown.preview, isA<TooLargePreview>());
    });

    test(
      'a failed reading is reported with its kind and the tree stays',
      () async {
        files.failingFiles[('/work/app', 'README.md')] =
            ProjectFilesFailureKind.outsideRoot;
        make(_stateOf(project: '/work/app'));
        await settle();

        await cubit.selectFile('README.md');
        await settle();

        final failed = cubit.state.preview as PreviewFailed;
        expect(failed.path, 'README.md');
        expect(failed.kind, ProjectFilesFailureKind.outsideRoot);
        expect(cubit.state.status, ProjectTreeStatus.ready);
      },
    );
  });

  group('lifecycle and log', () {
    test('after close the subscription is gone and late results change '
        'nothing', () async {
      make(_stateOf(project: '/work/app'));
      await settle();
      final gate = files.gateRead('/work/app', 'README.md');
      final pending = cubit.selectFile('README.md');
      await settle();

      await cubit.close();
      files.canonicalCalls.clear();
      workspace.emit(_stateOf(project: '/work/b'));
      gate.complete();
      await pending;
      await settle();

      expect(files.canonicalCalls, isEmpty);
      expect(cubit.isClosed, isTrue);
    });

    test('events carry no content, and the relative path appears only at '
        'debug level (D5)', () async {
      files.failingFiles[('/work/app', 'lib/a.dart')] =
          ProjectFilesFailureKind.unreadable;
      files.failingDirs[('/work/app', 'docs')] =
          ProjectFilesFailureKind.unreadable;
      make(
        _stateOf(
          project: '/work/app',
          sessions: [_session('s1', '/work/app')],
          active: 's1',
        ),
      );
      await settle();
      await cubit.selectFile('.env');
      await cubit.toggleDirectory('lib');
      await cubit.toggleDirectory('docs');
      await cubit.selectFile('lib/a.dart');
      await cubit.refresh();
      await settle();

      expect(logger.entries, isNotEmpty);
      final everything = jsonEncode(logger.entries);
      expect(everything, isNot(contains('test-marker')));
      expect(everything, isNot(contains('API_KEY')));
      for (final entry in logger.entries) {
        expect(entry['event'], startsWith('project_files.'));
        if (entry['level'] != 'debug') {
          final text = jsonEncode(entry);
          expect(text, isNot(contains('.env')), reason: text);
          expect(text, isNot(contains('lib/a.dart')), reason: text);
          expect(text, isNot(contains('/work/app')), reason: text);
        }
      }
      // Сбои пишутся видом сбоя, а не текстом исключения.
      expect(logger.entries.any((e) => e['kind'] == 'unreadable'), isTrue);
    });
  });

  group('review fixes', () {
    test('a session that is not loaded in this connection falls back to the '
        'project folder (Q17)', () async {
      for (final status in [
        SessionStatusView.detached,
        SessionStatusView.notLoaded,
      ]) {
        files.canonicalCalls.clear();
        make(
          WorkspaceState(
            projectDirectory: '/work/app',
            sessions: [
              SessionSummaryView(
                id: SessionId('s1'),
                cwd: '/work/b',
                status: status,
              ),
            ],
            activeSessionId: SessionId('s1'),
          ),
        );
        await settle();

        expect(cubit.state.root, '/work/app', reason: '$status');
        expect(files.canonicalCalls, ['/work/app']);
      }
    });

    test('a root inside the project folder has no outside mark, one outside '
        'it has (Q18)', () async {
      files.listings['/work/app/pkg'] = {'': listingOf('', [])};
      files.listings['/work/app2'] = {'': listingOf('', [])};
      Future<bool> outside(String project, String? cwd) async {
        make(
          _stateOf(
            project: project,
            sessions: [if (cwd != null) _session('s1', cwd)],
            active: cwd == null ? null : 's1',
          ),
        );
        await settle();
        return cubit.state.rootOutsideProject;
      }

      expect(await outside('/work/app', null), isFalse);
      expect(await outside('/work/app', '/work/app'), isFalse);
      expect(await outside('/work/app', '/work/app/pkg'), isFalse);
      expect(await outside('/work/app', '/work/b'), isTrue);
      // Общий префикс имени — не вложенность.
      expect(await outside('/work/app', '/work/app2'), isTrue);
    });

    test('the absolute root never reaches the log above debug (D5)', () async {
      make(
        _stateOf(
          project: '/work/app',
          sessions: [_session('s1', '/work/b')],
          active: 's1',
        ),
      );
      await settle();

      for (final entry in logger.entries) {
        if (entry['level'] != 'debug') {
          expect(jsonEncode(entry), isNot(contains('/work/b')));
        }
      }
    });

    test('the selected file is remembered per root and read again on '
        'return', () async {
      final both = _stateOf(
        project: '/work/app',
        sessions: [_session('s1', '/work/app'), _session('s2', '/work/b')],
      );
      WorkspaceState focus(String id) =>
          both.copyWith(activeSessionId: SessionId(id));
      make(focus('s1'));
      await settle();
      await cubit.selectFile('README.md');
      await settle();

      workspace.emit(focus('s2'));
      await settle();
      expect(cubit.state.selected, isNull);

      files.readCalls.clear();
      workspace.emit(focus('s1'));
      await settle();

      expect(cubit.state.selected, 'README.md');
      expect(files.readCalls, [('/work/app', 'README.md')]);
      expect(cubit.state.preview, isA<PreviewShown>());
    });

    test('a remembered file that is gone is not restored', () async {
      final both = _stateOf(
        project: '/work/app',
        sessions: [_session('s1', '/work/app'), _session('s2', '/work/b')],
      );
      WorkspaceState focus(String id) =>
          both.copyWith(activeSessionId: SessionId(id));
      make(focus('s1'));
      await settle();
      await cubit.selectFile('README.md');
      await settle();
      workspace.emit(focus('s2'));
      await settle();
      files.listings['/work/app']![''] = listingOf('', [dirEntry('lib')]);
      files.readCalls.clear();

      workspace.emit(focus('s1'));
      await settle();

      expect(cubit.state.selected, isNull);
      expect(files.readCalls, isEmpty);
    });

    test(
      'an unexpected exception of the port on the root ends in '
      'unavailable, not in endless loading, and the log has a kind only',
      () async {
        files.canonicalError = StateError('boom-secret-text');
        make(_stateOf(project: '/work/app'));
        await settle();

        expect(cubit.state.status, ProjectTreeStatus.unavailable);
        expect(cubit.state.failure, ProjectFilesFailureKind.unreadable);
        expect(jsonEncode(logger.entries), isNot(contains('boom-secret-text')));
        expect(
          logger.entries.any(
            (e) =>
                e['event'] == 'project_files.root_unavailable' &&
                e['kind'] == 'unexpected',
          ),
          isTrue,
        );
      },
    );

    test(
      'an unexpected exception while listing the root is unavailable',
      () async {
        files.listErrors[('/work/app', '')] = StateError('boom');
        make(_stateOf(project: '/work/app'));
        await settle();

        expect(cubit.state.status, ProjectTreeStatus.unavailable);
      },
    );

    test(
      'an unexpected exception while listing a folder gives an error row',
      () async {
        make(_stateOf(project: '/work/app'));
        await settle();
        files.listErrors[('/work/app', 'lib')] = StateError('boom');

        await cubit.toggleDirectory('lib');
        await settle();

        expect(cubit.state.status, ProjectTreeStatus.ready);
        expect(cubit.state.rows[1].kind, CodeLabFileTreeRowKind.error);
      },
    );

    test(
      'an unexpected exception while reading a file fails the preview',
      () async {
        make(_stateOf(project: '/work/app'));
        await settle();
        files.readErrors[('/work/app', 'README.md')] = StateError('boom');

        await cubit.selectFile('README.md');
        await settle();

        final failed = cubit.state.preview as PreviewFailed;
        expect(failed.kind, ProjectFilesFailureKind.unreadable);
        expect(
          logger.entries.any(
            (e) =>
                e['event'] == 'project_files.read_failed' &&
                e['kind'] == 'unexpected',
          ),
          isTrue,
        );
      },
    );

    test('the root failure kind is kept: a missing folder is notFound, an '
        'unreadable one is not', () async {
      files.missingFolders.add('/gone');
      make(_stateOf(project: '/gone'));
      await settle();
      expect(cubit.state.failure, ProjectFilesFailureKind.notFound);

      files.listings['/locked'] = {};
      files.failingDirs[('/locked', '')] = ProjectFilesFailureKind.unreadable;
      make(_stateOf(project: '/locked'));
      await settle();
      expect(cubit.state.status, ProjectTreeStatus.unavailable);
      expect(cubit.state.failure, ProjectFilesFailureKind.unreadable);
    });
  });

  group('availability (Q8)', () {
    test('while Files is unavailable the port gets no call and nothing is '
        'logged, and the root is read when it becomes available', () async {
      final availability = StreamController<bool>.broadcast(sync: true);
      addTearDown(availability.close);
      workspace = FakeWorkspace(
        _stateOf(
          project: '/work/app',
          sessions: [_session('s1', '/work/b')],
          active: 's1',
        ),
      );
      cubit = ProjectFilesCubit(
        files: files,
        workspace: workspace,
        logger: logger,
        available: false,
        availability: availability.stream,
      );
      addTearDown(cubit.close);
      await settle();

      expect(cubit.state.status, ProjectTreeStatus.noFolder);
      expect(files.canonicalCalls, isEmpty);
      expect(files.listCalls, isEmpty);
      expect(logger.entries, isEmpty);

      // Изменение рабочего пространства при недоступной панели тоже не
      // обращается к диску.
      workspace.emit(
        _stateOf(
          project: '/work/app',
          sessions: [_session('s1', '/remote/net')],
          active: 's1',
        ),
      );
      await settle();
      expect(files.canonicalCalls, isEmpty);

      workspace.emit(
        _stateOf(
          project: '/work/app',
          sessions: [_session('s1', '/work/b')],
          active: 's1',
        ),
      );
      availability.add(true);
      await settle();

      expect(cubit.state.status, ProjectTreeStatus.ready);
      expect(cubit.state.root, '/work/b');
    });

    test(
      'becoming unavailable drops the tree and a reading in flight',
      () async {
        final availability = StreamController<bool>.broadcast(sync: true);
        addTearDown(availability.close);
        workspace = FakeWorkspace(_stateOf(project: '/work/app'));
        cubit = ProjectFilesCubit(
          files: files,
          workspace: workspace,
          logger: logger,
          availability: availability.stream,
        );
        addTearDown(cubit.close);
        await settle();
        final gate = files.gateRead('/work/app', 'README.md');
        final pending = cubit.selectFile('README.md');
        await settle();
        files.canonicalCalls.clear();

        availability.add(false);
        await settle();
        expect(cubit.state.status, ProjectTreeStatus.noFolder);
        gate.complete();
        await pending;
        await settle();

        expect(cubit.state.status, ProjectTreeStatus.noFolder);
        expect(cubit.state.preview, isA<PreviewNone>());
        expect(files.canonicalCalls, isEmpty);

        availability.add(true);
        await settle();
        expect(cubit.state.root, '/work/app');
      },
    );
  });

  group('outside the project by realpath (Q18)', () {
    Future<bool> outside(
      String project,
      String cwd, {
      Map<String, String> roots = const {},
    }) async {
      files.roots.addAll(roots);
      files.listings.putIfAbsent(
        roots[cwd] ?? cwd,
        () => {'': listingOf('', [])},
      );
      make(
        _stateOf(
          project: project,
          sessions: [_session('s1', cwd)],
          active: 's1',
        ),
      );
      await settle();
      return cubit.state.rootOutsideProject;
    }

    test('a path with .. that leaves the project is outside', () async {
      expect(
        await outside('/proj', '/proj/../etc', roots: {'/proj/../etc': '/etc'}),
        isTrue,
      );
    });

    test('a link inside the project that points out is outside', () async {
      expect(
        await outside('/proj', '/proj/link', roots: {'/proj/link': '/etc'}),
        isTrue,
      );
    });

    test('the same folder under two names is not outside', () async {
      expect(
        await outside(
          '/tmp/w',
          '/private/tmp/w',
          roots: {'/tmp/w': '/private/tmp/w'},
        ),
        isFalse,
      );
      expect(
        await outside(
          '/tmp/w',
          '/tmp/w/sub',
          roots: {
            '/tmp/w': '/private/tmp/w',
            '/tmp/w/sub': '/private/tmp/w/sub',
          },
        ),
        isFalse,
      );
    });

    test('a backslash is an ordinary name character on POSIX, not a '
        'separator', () async {
      expect(await outside('/work/app', r'/work/app\evil'), isTrue);
    });

    test('a project that does not resolve shows the mark', () async {
      files.missingFolders.add('/gone');
      expect(await outside('/gone', '/work/b'), isTrue);
    });

    test('the project is resolved once and again when it changes', () async {
      files.listings['/work/app/pkg'] = {'': listingOf('', [])};
      make(
        _stateOf(
          project: '/work/app',
          sessions: [
            _session('s1', '/work/b'),
            _session('s2', '/work/app/pkg'),
          ],
          active: 's1',
        ),
      );
      await settle();
      WorkspaceState focus(String id, String project) => _stateOf(
        project: project,
        sessions: [_session('s1', '/work/b'), _session('s2', '/work/app/pkg')],
        active: id,
      );
      workspace.emit(focus('s2', '/work/app'));
      await settle();
      workspace.emit(focus('s1', '/work/app'));
      await settle();
      expect(
        files.canonicalCalls.where((c) => c == '/work/app').length,
        1,
        reason: 'one resolution of the project per project',
      );

      // Папка проекта сменилась, корень сессии тот же: подпись пересчитана.
      files.listings['/work/b'] = {'': listingOf('', [])};
      expect(cubit.state.rootOutsideProject, isTrue);
      workspace.emit(focus('s1', '/work/b'));
      await settle();
      expect(cubit.state.rootOutsideProject, isFalse);
    });
  });

  group('log of unexpected failures', () {
    test('carries the exception type but never its text', () async {
      files.canonicalError = StateError('boom-secret-text');
      make(_stateOf(project: '/work/app'));
      await settle();

      final entry = logger.entries.singleWhere(
        (e) => e['event'] == 'project_files.root_unavailable',
      );
      expect(entry['kind'], 'unexpected');
      expect(entry['error_type'], 'StateError');
      expect(jsonEncode(entry), isNot(contains('boom-secret-text')));
    });
  });
}
