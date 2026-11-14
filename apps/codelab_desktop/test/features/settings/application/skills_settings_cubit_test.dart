// `SkillsSettingsCubit` (задача 4.3 change `add-app-skills-page`; spec
// app-settings «Страница «Skills & extensions»: доступ и папка», «…открытие
// папок», «События журнала страницы Skills & extensions»; design.md D2, D6,
// D8, D10, D14; решения Q1–Q6).
//
// Красный тест: Cubit, его состояния и метод порта
// `ProviderSettingsSession.extensions` ещё не написаны (задача 4.4).
// Ожидаемый публичный API (имена выбраны здесь и фиксируют контракт):
//
// * `SkillsSettingsCubit({workspace, defaultProfile, open, environment,
//   codelabHome, projectDirectory, folderOpener, logger?})` — как у
//   `McpSettingsCubit` плюс порт `LocalFolderOpener`; методы `reload()`,
//   `openCodelabFolder()`, `openFolder(String directory)`;
// * состояния `SkillsSettingsLoading | SkillsSettingsReadOnly(notice, hint?)
//   | SkillsSettingsNoFolder | SkillsSettingsUnreadable(problems) |
//   SkillsSettingsReady(view, userConfigPath, banner?, saving)`;
//   `SkillsBanner(kind: SkillsBannerKind.openFailed, text)`;
// * порт сессии `Future<AgentExtensionsView> extensions(AgentConfigSnapshot)`
//   (двойник — `FakeProviderSettingsSession.extensions`).
//
// Что читает страница, решает мост (итерации 1–2); здесь — что Cubit
// вызывает, что показывает и что пишет в журнал. Маркер `sk-test-leak-…` лежит
// в описании навыка: журнал не должен содержать ни его, ни путей (D10).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/core/platform/local_folder_opener.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/settings/application/skills_settings_cubit.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_agent_extensions.dart';
import '../../../support/fake_local_folder_opener.dart';
import '../../../support/fake_provider_settings.dart';
import '../../../support/recording_logger.dart';

const _home = '/home/u/.codelab';

final _remote = ConnectionProfile.webSocket(
  id: 'devbox',
  label: 'Devbox',
  uri: Uri.parse('wss://devbox:7420/acp?t=$leakMarker'),
);

const _foreign = ConnectionProfile.stdio(
  id: 'other',
  label: 'Other',
  command: 'python',
  args: ['-m', 'other_agent'],
);

final _ownAgent = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: '/opt/bin/codelab-agent',
  args: const ['serve', '--stdio'],
  env: const {'CODELAB_HOME': '/srv/codelab'},
);

/// Рабочее пространство, считающее подписки на `state`: «одна подписка,
/// отменяется в `close()`» (D14, `AGENTS.md` §9). `FakeWorkspace` — `final`,
/// поэтому двойник свой, на тех же членах порта.
final class _CountingWorkspace implements ClientWorkspace {
  var listens = 0;
  var cancels = 0;
  final _own = StreamController<WorkspaceState>.broadcast(sync: true);
  var _current = const WorkspaceState();

  @override
  WorkspaceState get current => _current;

  @override
  Stream<WorkspaceState> get state => Stream.multi((controller) {
    listens++;
    final sub = _own.stream.listen(controller.add);
    controller.onCancel = () {
      cancels++;
      return sub.cancel();
    };
  }, isBroadcast: true);

  void emit(WorkspaceState next) {
    _current = next;
    _own.add(next);
  }

  @override
  SessionHandle? session(SessionId id) => null;

  @override
  Future<void> ensureAgent(String directory, {ConnectionProfile? profile}) =>
      Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;
  late FakeWorkspace workspace;
  late FakeLocalFolderOpener opener;
  late RecordingLogger logger;
  late List<SkillsSettingsCubit> cubits;
  late List<({EditableSettings access, Map<String, String> env})> opened;
  String? projectDir = '/work/app';

  SkillsSettingsCubit make({String? home = _home, ClientWorkspace? ws}) {
    final cubit = SkillsSettingsCubit(
      workspace: ws ?? workspace,
      defaultProfile: () async => embeddedConnectionProfile,
      open: (access, env) async {
        opened.add((access: access, env: env));
        return session;
      },
      environment: const {'HOME': '/home/u'},
      codelabHome: home,
      projectDirectory: () => projectDir,
      folderOpener: opener,
      logger: logger,
    );
    cubits.add(cubit);
    return cubit;
  }

  setUp(() {
    store = FakeAgentConfigStore();
    session = FakeProviderSettingsSession(store);
    workspace = FakeWorkspace();
    opener = FakeLocalFolderOpener();
    logger = RecordingLogger();
    cubits = [];
    opened = [];
    projectDir = '/work/app';
  });

  tearDown(() async {
    for (final cubit in cubits) {
      await cubit.close();
    }
  });

  Iterable<Object?> events() => logger.entries.map((e) => e['event']);

  Map<String, Object?> event(String name) =>
      logger.entries.lastWhere((e) => e['event'] == name);

  SkillsSettingsReady ready(SkillsSettingsCubit cubit) =>
      cubit.state as SkillsSettingsReady;

  void connect(ConnectionProfile profile) => workspace.emit(
    WorkspaceState(
      connection: const ConnectionView.connected(),
      profile: profile,
    ),
  );

  /// Вид, который вернёт порт: навык с маркером в описании, чтобы журнал
  /// доказал, что описаний не пишет.
  AgentExtensionsView richView() => extensionsView(
    files: [contextFile('AGENTS.md', bytes: 4800)],
    skills: [
      skillEntry('code-review', description: 'Review code $leakMarker'),
      skillEntry('flutter-golden', availability: SkillAvailability.disabled),
    ],
    skillWarnings: [diagnostic('skill skipped: $leakMarker')],
    templates: [templateEntry('/review-pr')],
  );

  group('access (D2, SETUP-2)', () {
    test('the embedded agent is read from files: Ready with the view the '
        'port returned and the user config path', () async {
      final view = richView();
      session.onExtensions = (_) async => view;
      final cubit = make();

      expect(cubit.state, isA<SkillsSettingsLoading>());
      await cubit.reload();

      expect(ready(cubit).view, same(view));
      expect(ready(cubit).userConfigPath, FakeAgentConfigStore.userPath);
      expect(ready(cubit).banner, isNull);
      expect(ready(cubit).saving, isFalse);
      expect(opened.single.access.cwd, '/work/app');
      expect(opened.single.access.paths.codelabHome, _home);
      // Порт получает снимок конфига именно этой папки.
      expect(session.extensionsCalls.single.cwd, '/work/app');
    });

    test('a stdio profile of our own agent passes its env to the session '
        'and its CODELAB_HOME decides the home', () async {
      connect(_ownAgent);
      final cubit = make();

      await cubit.reload();

      expect(opened.single.env['CODELAB_HOME'], '/srv/codelab');
      expect(opened.single.env['HOME'], '/home/u');
      expect(opened.single.access.paths.codelabHome, '/srv/codelab');
      expect(cubit.state, isA<SkillsSettingsReady>());
    });

    test('a WebSocket agent is read-only: the origin without path and '
        'secrets, and the port is never called', () async {
      connect(_remote);
      final cubit = make();

      await cubit.reload();

      final state = cubit.state as SkillsSettingsReadOnly;
      expect(state.notice, 'Read-only: this agent runs on wss://devbox:7420.');
      expect(
        state.hint,
        'Its skills, context files and prompt templates are read on that '
        'host: codelab-agent config check.',
      );
      expect(state.toString(), isNot(contains(leakMarker)));
      expect(opened, isEmpty);
      expect(session.extensionsCalls, isEmpty);
      expect(store.snapshots, 0);
      expect(event('skills_settings.read_only')['access'], 'remote');
    });

    test('a foreign stdio agent: "managed by <command>" and no port '
        'call', () async {
      connect(_foreign);
      final cubit = make();

      await cubit.reload();

      final state = cubit.state as SkillsSettingsReadOnly;
      expect(state.notice, 'Skills are managed by python.');
      expect(state.hint, isNull);
      expect(opened, isEmpty);
      expect(session.extensionsCalls, isEmpty);
      expect(event('skills_settings.read_only')['access'], 'not_managed');
    });

    test('no profile connected: the default profile decides', () async {
      final cubit = SkillsSettingsCubit(
        workspace: workspace,
        defaultProfile: () async => _remote,
        open: (access, env) async => session,
        environment: const {},
        codelabHome: _home,
        projectDirectory: () => projectDir,
        folderOpener: opener,
        logger: logger,
      );
      cubits.add(cubit);

      await cubit.reload();

      expect(cubit.state, isA<SkillsSettingsReadOnly>());
    });
  });

  group('folder and readability (D2)', () {
    test('no folder: NoFolder, nothing is read', () async {
      projectDir = null;
      final cubit = make();

      await cubit.reload();

      expect(cubit.state, isA<SkillsSettingsNoFolder>());
      expect(session.extensionsCalls, isEmpty);
      expect(store.snapshots, 0);
    });

    test('an empty folder string is "no folder" too', () async {
      projectDir = '';
      final cubit = make();

      await cubit.reload();

      expect(cubit.state, isA<SkillsSettingsNoFolder>());
    });

    test('a config that violates the schema is Unreadable with the '
        'loader problems and the files are not read', () async {
      // Проблема значения относится к ключу, заданному в слое: без него
      // снимок переносит её в проблемы запуска, а не в проблемы файла.
      store.user = {
        'skills': {'max_skills': 0},
      };
      store.issues = [
        const ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'skills.max_skills',
          source: FakeAgentConfigStore.userPath,
          message: 'must be a positive number',
        ),
      ];
      final cubit = make();

      await cubit.reload();

      final state = cubit.state as SkillsSettingsUnreadable;
      expect(state.problems, hasLength(1));
      expect(state.problems.single, contains('skills.max_skills'));
      expect(session.extensionsCalls, isEmpty);
      expect(event('skills_settings.unreadable')['issues'], 1);
    });

    test('a user config that cannot be read is Unreadable', () async {
      store.omitUserLayer = true;
      final cubit = make();

      await cubit.reload();

      expect(cubit.state, isA<SkillsSettingsUnreadable>());
      expect(session.extensionsCalls, isEmpty);
    });

    test('an exception of the port is Unreadable and the log has only the '
        'runtimeType', () async {
      session.onExtensions = (_) async =>
          throw FormatException('secret text $leakMarker /home/u/x');
      final cubit = make();

      await cubit.reload();

      expect(cubit.state, isA<SkillsSettingsUnreadable>());
      expect(
        (cubit.state as SkillsSettingsUnreadable).problems.join(),
        isNot(contains(leakMarker)),
      );
      final entry = event('skills_settings.unreadable');
      expect(entry['error_type'], 'FormatException');
      expect(logger.entries.toString(), isNot(contains(leakMarker)));
      expect(logger.entries.toString(), isNot(contains('/home/u/x')));
    });

    test('an exception of the config store is Unreadable too', () async {
      store.snapshotError = StateError('disk $leakMarker');
      final cubit = make();

      await cubit.reload();

      expect(cubit.state, isA<SkillsSettingsUnreadable>());
      expect(logger.entries.toString(), isNot(contains(leakMarker)));
    });

    test('an untrusted project is Ready: the view carries the flag', () async {
      session.onExtensions = (_) async => extensionsView(trusted: false);
      final cubit = make();

      await cubit.reload();

      expect(ready(cubit).view.trusted, isFalse);
    });
  });

  group('reload on workspace changes (D2, D14)', () {
    test('switching the profile to WebSocket re-reads the page and the '
        'earlier load that finishes later is discarded', () async {
      final gate = Completer<AgentExtensionsView>();
      session.onExtensions = (_) => gate.future;
      final cubit = make();
      final first = cubit.reload();
      await pumpEventQueue();

      connect(_remote);
      await pumpEventQueue();
      expect(cubit.state, isA<SkillsSettingsReadOnly>());

      gate.complete(richView());
      await first;

      expect(cubit.state, isA<SkillsSettingsReadOnly>());
      expect(events(), contains('skills_settings.load_discarded'));
    });

    test('a change of the focused session folder re-reads the page for '
        'the new folder', () async {
      final cubit = make();
      await cubit.reload();
      expect(session.extensionsCalls.single.cwd, '/work/app');

      projectDir = '/work/other';
      workspace.emit(
        WorkspaceState(
          connection: const ConnectionView.connected(),
          profile: embeddedConnectionProfile,
          activeSessionId: SessionId('s2'),
        ),
      );
      await pumpEventQueue();

      expect(session.extensionsCalls, hasLength(2));
      expect(session.extensionsCalls.last.cwd, '/work/other');
    });

    test('a workspace event without a change of profile or folder does '
        'not re-read', () async {
      connect(_ownAgent);
      final cubit = make();
      await cubit.reload();

      connect(_ownAgent);
      await pumpEventQueue();

      expect(session.extensionsCalls, hasLength(1));
    });

    test('a late result after a newer load is discarded and logged without '
        'a path', () async {
      final gates = [
        Completer<AgentExtensionsView>(),
        Completer<AgentExtensionsView>(),
      ];
      var call = 0;
      session.onExtensions = (_) => gates[call++].future;
      final cubit = make();

      final first = cubit.reload();
      await pumpEventQueue();
      final second = cubit.reload();
      await pumpEventQueue();
      final fresh = extensionsView(skills: [skillEntry('fresh')]);
      gates[1].complete(fresh);
      await second;
      gates[0].complete(extensionsView(skills: [skillEntry('stale')]));
      await first;

      expect(ready(cubit).view, same(fresh));
      expect(events(), contains('skills_settings.load_discarded'));
      expect(logger.entries.toString(), isNot(contains('/work/app')));
    });

    test('a result that arrives after close() is discarded without a '
        'state error', () async {
      final gate = Completer<AgentExtensionsView>();
      session.onExtensions = (_) => gate.future;
      final cubit = make();
      final load = cubit.reload();
      await pumpEventQueue();

      await cubit.close();
      gate.complete(richView());
      await load;

      expect(events(), contains('skills_settings.load_discarded'));
    });

    test('exactly one subscription to the workspace state, cancelled in '
        'close()', () async {
      final counting = _CountingWorkspace();
      final cubit = make(ws: counting);
      await cubit.reload();
      await cubit.reload();
      expect(counting.listens, 1);
      expect(counting.cancels, 0);

      await cubit.close();

      expect(counting.cancels, 1);
    });
  });

  group('events without content (D10)', () {
    test('loaded carries the counts and no path, description or '
        'marker', () async {
      session.onExtensions = (_) async => richView();
      final cubit = make();

      await cubit.reload();

      final loaded = event('skills_settings.loaded');
      expect(loaded['access'], 'editable');
      expect(loaded['trusted'], isTrue);
      expect(loaded['context_files'], 1);
      expect(loaded['skills'], 1);
      expect(loaded['disabled'], 1);
      expect(loaded['templates'], 1);
      expect(loaded['warnings'], 1);
      final text = logger.entries.toString();
      expect(text, isNot(contains(leakMarker)));
      expect(text, isNot(contains('/work')));
      expect(text, isNot(contains('/home')));
      expect(text, isNot(contains('code-review')));
    });

    test('a timed-out or failed phase is phase_failed with a reason and '
        'the page is still Ready', () async {
      session.onExtensions = (_) async => extensionsView(
        skillsOutcome: const SectionTimedOut(),
        contextOutcome: const SectionFailed('PathAccessException'),
        templatesOutcome: const SectionFailed('PathAccessException'),
      );
      final cubit = make();

      await cubit.reload();

      expect(cubit.state, isA<SkillsSettingsReady>());
      final failed = logger.entries
          .where((e) => e['event'] == 'skills_settings.phase_failed')
          .toList();
      expect(
        failed.map((e) => '${e['phase']}:${e['reason']}'),
        containsAll(['skills:timeout', 'project_files:PathAccessException']),
      );
      expect(logger.entries.toString(), isNot(contains('/work')));
    });
  });

  group('opening folders (D8, Q4, Q5)', () {
    setUp(() {
      session.onExtensions = (_) async => extensionsView(
        files: [contextFile('AGENTS.md', openDir: '/work/app')],
        skills: [
          skillEntry('pdf-tools', root: userSkillRoot()),
          skillEntry(
            'pdf_tools',
            root: userSkillRoot(),
            directory: '/home/u/.agents/skills/pdf-tools-dir',
          ),
        ],
        templates: [
          templateEntry(
            '/review-pr',
            sourcePath: '/work/app/.codelab/prompts/review-pr.md',
          ),
        ],
      );
    });

    test(
      '"Open .codelab folder" passes <folder>/.codelab to the port',
      () async {
        final cubit = make();
        await cubit.reload();

        await cubit.openCodelabFolder();

        expect(opener.opened, ['/work/app/.codelab']);
        expect(ready(cubit).banner, isNull);
      },
    );

    test('without .codelab in the project the port is asked for the '
        'CODELAB_HOME of the profile', () async {
      opener.outcomes.add(FolderOpenOutcome.missing);
      final cubit = make();
      await cubit.reload();

      await cubit.openCodelabFolder();

      expect(opener.opened, ['/work/app/.codelab', _home]);
      expect(ready(cubit).banner, isNull);
    });

    test('a directory shown by the page is opened as it is', () async {
      final cubit = make();
      await cubit.reload();

      await cubit.openFolder('/work/app');
      await cubit.openFolder('/home/u/.agents/skills/pdf-tools');
      await cubit.openFolder('/work/app/.codelab/prompts');
      // Имя навыка из frontmatter может не совпадать с каталогом: открывается
      // `SkillEntryView.directory`, а не `<root>/<name>`.
      await cubit.openFolder('/home/u/.agents/skills/pdf-tools-dir');

      expect(opener.opened, [
        '/work/app',
        '/home/u/.agents/skills/pdf-tools',
        '/work/app/.codelab/prompts',
        '/home/u/.agents/skills/pdf-tools-dir',
      ]);
    });

    test('a path the page did not show is refused without the port '
        '(the path comes only from the view)', () async {
      final cubit = make();
      await cubit.reload();

      await cubit.openFolder('/etc');
      // Склейка `<root>/<name>` не показанного каталога не допускается.
      await cubit.openFolder('/home/u/.agents/skills/pdf_tools');
      await cubit.openFolder('/work/app/AGENTS.md');

      expect(opener.opened, isEmpty);
    });

    test('a refusal of the platform is a banner with the path and an '
        'event without it', () async {
      opener.outcome = FolderOpenOutcome.failed;
      final cubit = make();
      await cubit.reload();

      await cubit.openFolder('/work/app');

      final banner = ready(cubit).banner!;
      expect(banner.kind, SkillsBannerKind.openFailed);
      expect(banner.text, 'Could not open /work/app.');
      final entry = event('skills_settings.open_failed');
      expect(entry['target'], 'file_dir');
      expect(logger.entries.toString(), isNot(contains('/work')));
    });

    test('a failed .codelab folder is target codelab_folder', () async {
      opener.outcome = FolderOpenOutcome.failed;
      final cubit = make();
      await cubit.reload();

      await cubit.openCodelabFolder();

      expect(ready(cubit).banner!.text, startsWith('Could not open /'));
      expect(event('skills_settings.open_failed')['target'], 'codelab_folder');
    });

    test('without a folder "Open .codelab folder" opens CODELAB_HOME '
        '(Q4)', () async {
      projectDir = null;
      final cubit = make();
      await cubit.reload();

      await cubit.openCodelabFolder();

      expect(opener.opened, [_home]);
    });
  });

  group('mutation hardening (iteration 4)', () {
    AgentExtensionsView shownView() => extensionsView(
      files: [contextFile('AGENTS.md', openDir: '/work/app')],
      skills: [skillEntry('pdf-tools')],
    );

    for (final entry in {
      'a WebSocket agent': _remote,
      'a foreign stdio agent': _foreign,
    }.entries) {
      test('after Ready -> ReadOnly (${entry.key}) no folder is opened: '
          'neither .codelab nor a directory of the former view', () async {
        session.onExtensions = (_) async => shownView();
        final cubit = make();
        await cubit.reload();
        expect(cubit.state, isA<SkillsSettingsReady>());

        connect(entry.value);
        await pumpEventQueue();
        expect(cubit.state, isA<SkillsSettingsReadOnly>());

        await cubit.openCodelabFolder();
        await cubit.openFolder('/work/app');
        await cubit.openFolder('/home/u/.agents/skills/pdf-tools');

        expect(opener.opened, isEmpty);
        expect(cubit.state, isA<SkillsSettingsReadOnly>());
      });

      test(
        'a cubit that starts ReadOnly (${entry.key}) opens nothing',
        () async {
          connect(entry.value);
          final cubit = make();
          await cubit.reload();

          await cubit.openCodelabFolder();
          await cubit.openFolder('/work/app');

          expect(opener.opened, isEmpty);
          expect(cubit.state, isA<SkillsSettingsReadOnly>());
        },
      );
    }

    test('a profile without CODELAB_HOME is Unreadable and the port is '
        'not called', () async {
      final cubit = make(home: '');

      await cubit.reload();

      final state = cubit.state as SkillsSettingsUnreadable;
      expect(state.problems, ['The CodeLab home folder is not available.']);
      expect(session.extensionsCalls, isEmpty);
      expect(store.snapshots, 0);
    });

    test('a change of the folder alone, with the same profile, re-reads '
        'the page', () async {
      connect(embeddedConnectionProfile);
      final cubit = make();
      await cubit.reload();
      expect(session.extensionsCalls.single.cwd, '/work/app');

      projectDir = '/work/other';
      connect(embeddedConnectionProfile);
      await pumpEventQueue();

      expect(session.extensionsCalls, hasLength(2));
      expect(session.extensionsCalls.last.cwd, '/work/other');
    });

    test('a failed .codelab folder does not fall back to CODELAB_HOME: '
        'only <folder>/.codelab is tried', () async {
      opener.outcome = FolderOpenOutcome.failed;
      final cubit = make();
      await cubit.reload();

      await cubit.openCodelabFolder();

      expect(opener.opened, ['/work/app/.codelab']);
    });

    test('the unreadable event has the number of problems, not their '
        'text', () async {
      store.user = {
        'skills': {'max_skills': 0},
      };
      store.issues = [
        const ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'skills.max_skills',
          source: FakeAgentConfigStore.userPath,
          message: 'must be a positive number',
        ),
      ];
      final cubit = make();

      await cubit.reload();

      expect(cubit.state, isA<SkillsSettingsUnreadable>());
      expect(event('skills_settings.unreadable')['issues'], 1);
      final text = logger.entries.toString();
      expect(text, isNot(contains('must be a positive number')));
      expect(text, isNot(contains('skills.max_skills')));
      expect(text, isNot(contains(FakeAgentConfigStore.userPath)));
    });
  });

  group('review of iteration 4', () {
    test(
      'a failure of defaultProfile is Unreadable with the type only',
      () async {
        final cubit = SkillsSettingsCubit(
          workspace: workspace,
          defaultProfile: () async =>
              throw FormatException('profiles.json: $leakMarker /home/u/x'),
          open: (access, env) async => session,
          environment: const {},
          codelabHome: _home,
          projectDirectory: () => projectDir,
          folderOpener: opener,
          logger: logger,
        );
        cubits.add(cubit);

        await cubit.reload();

        final state = cubit.state as SkillsSettingsUnreadable;
        expect(state.problems, ['Cannot read the agent settings.']);
        expect(
          event('skills_settings.unreadable')['error_type'],
          'FormatException',
        );
        expect(logger.entries.toString(), isNot(contains(leakMarker)));
        expect(logger.entries.toString(), isNot(contains('/home/u/x')));
      },
    );

    test('Ready keeps the folder and CODELAB_HOME of the shown view', () async {
      final cubit = make();

      await cubit.reload();

      expect(ready(cubit).folder, '/work/app');
      expect(ready(cubit).codelabHome, _home);
    });

    test('NoFolder keeps CODELAB_HOME for the tooltip', () async {
      projectDir = null;
      final cubit = make();

      await cubit.reload();

      expect((cubit.state as SkillsSettingsNoFolder).codelabHome, _home);
    });

    test('while a reload for another folder is pending, "Open .codelab '
        'folder" opens the .codelab of the folder that is shown', () async {
      final cubit = make();
      await cubit.reload();
      expect(ready(cubit).folder, '/work/app');
      final gate = Completer<AgentExtensionsView>();
      session.onExtensions = (_) => gate.future;
      projectDir = '/work/other';

      final reloading = cubit.reload();
      await pumpEventQueue();
      await cubit.openCodelabFolder();

      expect(opener.opened, ['/work/app/.codelab']);
      gate.complete(extensionsView());
      await reloading;
    });

    test('openTemplateFolder opens the directory of the template file '
        'once, computed by the cubit', () async {
      final template = templateEntry(
        '/review-pr',
        sourcePath: '/work/app/.codelab/prompts/review-pr.md',
      );
      session.onExtensions = (_) async => extensionsView(templates: [template]);
      final cubit = make();
      await cubit.reload();

      await cubit.openTemplateFolder(template);

      expect(opener.opened, ['/work/app/.codelab/prompts']);
    });

    test(
      'openTemplateFolder refuses a template the page did not show',
      () async {
        final cubit = make();
        await cubit.reload();

        await cubit.openTemplateFolder(
          templateEntry('/other', sourcePath: '/etc/evil/other.md'),
        );

        expect(opener.opened, isEmpty);
      },
    );
  });

  test('close() makes later actions harmless', () async {
    final cubit = make();
    await cubit.reload();
    await cubit.close();

    await cubit.openCodelabFolder();
    await cubit.reload();

    expect(opener.opened, isEmpty);
  });
}
