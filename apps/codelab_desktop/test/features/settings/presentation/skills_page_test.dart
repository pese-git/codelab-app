// Страница «Skills & extensions», показ и «только чтение» (задача 4.5 change
// `add-app-skills-page`; spec app-settings «Страница «Skills & extensions»:
// доступ и папка», «…контекстные файлы и шаблоны», «…навыки», «…открытие
// папок»; design.md D8, D12, D13; артборд `Extensions`).
//
// Проверяется поведение (что показано, что вызвано), а не пиксели. Страница
// строится на настоящем `SkillsSettingsCubit` с двойниками сессии настроек и
// порта `LocalFolderOpener`: что читает мост, проверяют его тесты, а как Cubit
// переводит доступ и папку в состояние — `skills_settings_cubit_test.dart`.
//
// Красный тест: страницы нет (задача 4.6). Ожидаемый API (выбран здесь):
//
// * `SkillsPage` (читает `SkillsSettingsCubit` из `BlocProvider`),
//   `SkillsPageHost`; тело — ключ `settings-skills`;
// * ключи (D13): InfoBar `skills-read-only`, `skills-untrusted`,
//   `skills-unreadable`, `skills-banner`, `skills-warnings`; текст
//   `skills-no-folder`; кнопки `skills-reload`, `skills-open-codelab`,
//   `skills-open-context-<n>`, `skills-open-skill-<name>`,
//   `skills-open-template-<name>`; строки `skills-context-<n>`,
//   `skills-row-<name>`, `skills-template-<name>` (команда без `/`),
//   переключатель `skills-toggle-<name>` (`ToggleSwitch`, в итерации 4 —
//   только показ состояния «Enabled»), подпись порядка `skills-search-order`;
// * таблицы — `CodeLabStatusTable` (итерация 3, D12).
//
// Размер файла — 1024-ичный, одна цифра после точки (`4.8 KB`, `6.1 KB`).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/core/platform/local_folder_opener.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/settings/application/skills_settings_cubit.dart';
import 'package:codelab_desktop/features/settings/presentation/skills_page.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' hide DiagnosticLevel;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

import '../../../support/fake_agent_extensions.dart';
import '../../../support/fake_local_folder_opener.dart';
import '../../../support/fake_provider_settings.dart';
import '../../../support/recording_logger.dart';

const _home = '/home/u/.codelab';

Finder _key(String key) => find.byKey(ValueKey(key));

/// Текст [text] внутри элемента с ключом [owner].
Finder _in(String owner, String text) =>
    find.descendant(of: _key(owner), matching: find.text(text));

Finder _containing(String owner, String text) =>
    find.descendant(of: _key(owner), matching: find.textContaining(text));

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 3200);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;
  late FakeWorkspace workspace;
  late FakeLocalFolderOpener opener;
  late RecordingLogger logger;
  String? projectDir = '/work/app';

  setUp(() {
    store = FakeAgentConfigStore();
    session = FakeProviderSettingsSession(store);
    workspace = FakeWorkspace();
    opener = FakeLocalFolderOpener();
    logger = RecordingLogger();
    projectDir = '/work/app';
  });

  Future<SkillsSettingsCubit> openPage(
    WidgetTester tester, {
    AgentExtensionsView? view,
    ConnectionProfile? profile,
  }) async {
    if (view != null) {
      session.onExtensions = (_) async => view;
    }
    if (profile != null) {
      workspace.emit(
        WorkspaceState(
          connection: const ConnectionView.connected(),
          profile: profile,
        ),
      );
    }
    final cubit = SkillsSettingsCubit(
      workspace: workspace,
      defaultProfile: () async => embeddedConnectionProfile,
      open: (access, env) async => session,
      environment: const {'HOME': '/home/u'},
      codelabHome: _home,
      projectDirectory: () => projectDir,
      folderOpener: opener,
      logger: logger,
    );
    addTearDown(cubit.close);
    await cubit.reload();
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 40),
            child: BlocProvider<SkillsSettingsCubit>.value(
              value: cubit,
              child: const SkillsPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  group('layout (artboard Extensions, D13)', () {
    testWidgets('has the body key, the three sections and none of the '
        'sections that are out of scope', (tester) async {
      await openPage(tester, view: extensionsView());

      expect(_key('settings-skills'), findsOneWidget);
      expect(find.text('Skills & extensions'), findsWidgets);
      expect(find.text('Context files'), findsOneWidget);
      expect(find.text('Skills'), findsOneWidget);
      expect(find.text('Prompt templates'), findsOneWidget);
      expect(_key('skills-reload'), findsOneWidget);
      expect(_key('skills-open-codelab'), findsOneWidget);
      for (final absent in const [
        'Hooks',
        'Plugins',
        'Plugins (Dart)',
        'System prompt override',
        'Read context files of other agents',
      ]) {
        expect(find.text(absent), findsNothing, reason: absent);
      }
    });

    testWidgets('empty sections say so', (tester) async {
      await openPage(tester, view: extensionsView());

      expect(find.text('No AGENTS.md files for this folder.'), findsOneWidget);
      expect(find.text('No prompt templates.'), findsOneWidget);
    });
  });

  group('context files', () {
    testWidgets('a chain from the outer to the nearest file with sizes '
        'and the total', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          files: [
            contextFile('AGENTS.md', bytes: 4915),
            contextFile('packages/ui/AGENTS.md', bytes: 1331),
          ],
        ),
      );

      expect(_in('skills-context-0', 'AGENTS.md'), findsOneWidget);
      expect(_in('skills-context-0', '4.8 KB'), findsOneWidget);
      expect(_in('skills-context-1', 'packages/ui/AGENTS.md'), findsOneWidget);
      expect(_in('skills-context-1', '1.3 KB'), findsOneWidget);
      expect(find.text('2 files · 6.1 KB'), findsOneWidget);
      expect(find.textContaining('truncated'), findsNothing);
      expect(find.textContaining('not included'), findsNothing);
      expect(
        tester.getTopLeft(_key('skills-context-0')).dy,
        lessThan(tester.getTopLeft(_key('skills-context-1')).dy),
      );
    });

    testWidgets('CLAUDE.md used instead of AGENTS.md has the note', (
      tester,
    ) async {
      await openPage(
        tester,
        view: extensionsView(
          files: [contextFile('packages/ui/CLAUDE.md', isClaudeAlias: true)],
        ),
      );

      expect(_in('skills-context-0', 'packages/ui/CLAUDE.md'), findsOneWidget);
      expect(
        _in('skills-context-0', 'used because this folder has no AGENTS.md'),
        findsOneWidget,
      );
    });

    testWidgets('the budget marks a truncated file and an omitted one, '
        'as the core decided', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          files: [
            contextFile('AGENTS.md', bytes: 4096),
            contextFile('a/AGENTS.md', bytes: 3000, shownBytes: 2048),
            contextFile('a/b/AGENTS.md', bytes: 2000, omitted: true),
          ],
          truncatedCount: 1,
          omittedCount: 1,
        ),
      );

      expect(_in('skills-context-0', 'truncated to 4.0 KB'), findsNothing);
      expect(_in('skills-context-1', 'truncated to 2.0 KB'), findsOneWidget);
      expect(_in('skills-context-2', 'not included (budget)'), findsOneWidget);
    });

    testWidgets('"Open" of a row passes the directory of the file to the '
        'port (Q5)', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          files: [
            contextFile(
              'packages/ui/AGENTS.md',
              openDir: '/work/app/packages/ui',
            ),
          ],
        ),
      );

      await tester.tap(_key('skills-open-context-0'));
      await tester.pumpAndSettle();

      expect(opener.opened, ['/work/app/packages/ui']);
    });
  });

  group('prompt templates', () {
    testWidgets('the command with the argument hint, the description and '
        'the source; a replaced user template is not listed twice', (
      tester,
    ) async {
      await openPage(
        tester,
        view: extensionsView(
          templates: [
            templateEntry(
              '/review-pr',
              argumentHint: '<number>',
              description: 'Review a pull request',
              sourcePath: '/work/app/.codelab/prompts/review-pr.md',
            ),
            templateEntry(
              '/explain',
              description: 'Explain a file',
              scope: ExtensionScope.user,
              sourcePath: '/home/u/.codelab/prompts/explain.md',
            ),
          ],
        ),
      );

      expect(
        _in('skills-template-review-pr', '/review-pr <number>'),
        findsOneWidget,
      );
      expect(
        _in('skills-template-review-pr', 'Review a pull request'),
        findsOneWidget,
      );
      expect(
        _containing('skills-template-review-pr', 'review-pr.md'),
        findsOneWidget,
      );
      expect(_in('skills-template-explain', '/explain'), findsOneWidget);
      expect(
        _containing('skills-template-explain', 'explain.md'),
        findsOneWidget,
      );
      expect(find.text('/review-pr <number>'), findsOneWidget);
      expect(find.text('No prompt templates.'), findsNothing);
    });

    testWidgets('"Open" of a template passes the directory of the '
        'file', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          templates: [
            templateEntry(
              '/explain',
              sourcePath: '/home/u/.codelab/prompts/explain.md',
            ),
          ],
        ),
      );

      await tester.tap(_key('skills-open-template-explain'));
      await tester.pumpAndSettle();

      expect(opener.opened, ['/home/u/.codelab/prompts']);
    });

    testWidgets('a template description is plain text with visible '
        'control characters', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          templates: [
            templateEntry('/x', description: '**bold** \u202Egpj.exe'),
          ],
        ),
      );

      expect(find.text('**bold** \\u202egpj.exe'), findsOneWidget);
    });
  });

  group('skills table', () {
    testWidgets('a row has the name, the description, "Invoke as" and the '
        'source; a model-only skill says so', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [
            skillEntry(
              'pdf-tools',
              description: 'Work with PDF files',
              argumentHint: '<file>',
              root: userSkillRoot(),
            ),
            skillEntry(
              'background',
              description: 'Used by the model',
              userInvocable: false,
              root: projectSkillRoot(),
            ),
          ],
        ),
      );

      expect(find.byType(CodeLabStatusTable), findsWidgets);
      expect(_in('skills-row-pdf-tools', 'pdf-tools'), findsOneWidget);
      expect(
        _in('skills-row-pdf-tools', 'Work with PDF files'),
        findsOneWidget,
      );
      expect(
        _in('skills-row-pdf-tools', '/skill:pdf-tools <file>'),
        findsOneWidget,
      );
      expect(_in('skills-row-pdf-tools', '~/.agents/skills'), findsOneWidget);
      expect(_in('skills-row-background', 'Model only'), findsOneWidget);
      expect(_in('skills-row-background', '.codelab/skills'), findsOneWidget);
      expect(find.text('Skills are switched off'), findsNothing);
    });

    testWidgets('the extra root is shown as written with the note', (
      tester,
    ) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [
            skillEntry(
              'imported',
              root: const SkillRootView(
                scope: ExtensionScope.extra,
                label: '.claude/skills (extra root)',
                path: '/work/app/.claude/skills',
              ),
            ),
          ],
        ),
      );

      expect(
        _in('skills-row-imported', '.claude/skills (extra root)'),
        findsOneWidget,
      );
    });

    testWidgets('tags: "Overrides user skill", "Command only" and '
        '"1 warning" with the text in the tooltip', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [
            skillEntry(
              'release-notes',
              root: projectSkillRoot(),
              overrides: [userSkillRoot()],
              overridesLabel: 'Overrides user skill',
            ),
            skillEntry('deploy-check', modelVisible: false),
            skillEntry(
              'pdf_tools',
              warnings: [
                diagnostic(
                  'the skill name differs from its directory name; '
                  'the name from the frontmatter is used',
                  path: '/home/u/.agents/skills/pdf-tools/SKILL.md',
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        _in('skills-row-release-notes', 'Overrides user skill'),
        findsOneWidget,
      );
      expect(_in('skills-row-deploy-check', 'Command only'), findsOneWidget);
      expect(
        _in('skills-row-deploy-check', '/skill:deploy-check'),
        findsOneWidget,
      );
      expect(_in('skills-row-pdf_tools', '1 warning'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Tooltip &&
              (w.message ?? '').contains(
                'the skill name differs from its directory name; the name '
                'from the frontmatter is used',
              ),
        ),
        findsOneWidget,
      );
      expect(find.text('Command only'), findsOneWidget);
    });

    testWidgets('a skill switched off by skills.disabled is listed with '
        'Enabled off and without "Command only"', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [
            skillEntry('code-review'),
            skillEntry(
              'flutter-golden',
              availability: SkillAvailability.disabled,
              modelVisible: false,
            ),
          ],
        ),
      );

      expect(_key('skills-row-flutter-golden'), findsOneWidget);
      expect(
        tester
            .widget<ToggleSwitch>(_key('skills-toggle-flutter-golden'))
            .checked,
        isFalse,
      );
      expect(
        tester.widget<ToggleSwitch>(_key('skills-toggle-code-review')).checked,
        isTrue,
      );
      expect(_in('skills-row-flutter-golden', 'Command only'), findsNothing);
    });

    testWidgets('names and descriptions from files are plain text with '
        'visible control characters, no markdown (D12)', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [
            skillEntry(
              'na\u202Eme',
              description: '**bold** [x](http://evil.test) \u202Egpj.exe',
            ),
          ],
        ),
      );

      expect(find.text('na\\u202eme'), findsOneWidget);
      expect(
        find.text('**bold** [x](http://evil.test) \\u202egpj.exe'),
        findsOneWidget,
      );
      expect(find.text('na\u202Eme'), findsNothing);
    });

    testWidgets('"Open" of a skill passes SkillEntryView.directory, not '
        'SKILL.md and not <root>/<name>', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [
            skillEntry('pdf-tools', root: userSkillRoot()),
            skillEntry(
              'pdf_tools',
              root: userSkillRoot(),
              directory: '/home/u/.agents/skills/pdf-tools',
            ),
          ],
        ),
      );

      await tester.tap(_key('skills-open-skill-pdf-tools'));
      await tester.pumpAndSettle();
      await tester.tap(_key('skills-open-skill-pdf_tools'));
      await tester.pumpAndSettle();

      expect(opener.opened, [
        '/home/u/.agents/skills/pdf-tools',
        '/home/u/.agents/skills/pdf-tools',
      ]);
    });

    testWidgets('the caption under the table: the search order and the '
        'fixed-list note', (tester) async {
      await openPage(tester, view: extensionsView(skills: [skillEntry('a')]));

      for (final part in const [
        '.codelab/skills',
        '.agents/skills',
        r'$CODELAB_HOME/skills',
        '~/.agents/skills',
        'extra roots',
      ]) {
        expect(
          _containing('skills-search-order', part),
          findsOneWidget,
          reason: part,
        );
      }
      expect(
        find.text(
          'The list is fixed when a session opens: new and changed skills '
          'apply to new sessions.',
        ),
        findsOneWidget,
      );
    });
  });

  group('warnings and states of the sections', () {
    testWidgets('InfoBar skills-warnings: the count, the fixed texts and '
        'the paths; info is not shown', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [skillEntry('a')],
          skillWarnings: [
            diagnostic(
              'the skill was skipped: the description is missing',
              path: '/home/u/.agents/skills/broken/SKILL.md',
            ),
            diagnostic(
              'the skill is overridden by another root',
              path: '/home/u/.agents/skills/release-notes/SKILL.md',
              code: 'shadowed',
            ),
            diagnostic(
              'a note',
              path: '/home/u/.agents/skills/x/SKILL.md',
              level: DiagnosticLevel.info,
            ),
          ],
        ),
      );

      expect(_key('skills-warnings'), findsOneWidget);
      expect(
        tester.widget<InfoBar>(_key('skills-warnings')).severity,
        InfoBarSeverity.warning,
      );
      expect(_containing('skills-warnings', '2 warnings'), findsOneWidget);
      expect(
        _containing(
          'skills-warnings',
          'the skill was skipped: the description is missing',
        ),
        findsOneWidget,
      );
      expect(
        _containing(
          'skills-warnings',
          '/home/u/.agents/skills/release-notes/SKILL.md',
        ),
        findsOneWidget,
      );
      expect(_containing('skills-warnings', 'a note'), findsNothing);
    });

    testWidgets('no warnings: no InfoBar', (tester) async {
      await openPage(tester, view: extensionsView(skills: [skillEntry('a')]));

      expect(_key('skills-warnings'), findsNothing);
    });

    testWidgets('skills.enabled: false: the note names the file, there is '
        'no table, the other sections stay', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skillsOutcome: const SectionOff('.codelab/config.local.yaml'),
          files: [contextFile('AGENTS.md')],
          templates: [templateEntry('/explain')],
        ),
      );

      expect(
        find.text(
          'Skills are switched off: skills.enabled is false in '
          '.codelab/config.local.yaml.',
        ),
        findsOneWidget,
      );
      expect(_key('skills-search-order'), findsNothing);
      expect(_key('skills-context-0'), findsOneWidget);
      expect(_key('skills-template-explain'), findsOneWidget);
    });

    testWidgets('a skills phase that timed out or failed: its text, the '
        'other sections stay', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skillsOutcome: const SectionTimedOut(),
          files: [contextFile('AGENTS.md')],
        ),
      );
      expect(find.text('Skills were not read within 5 s.'), findsOneWidget);
      expect(_key('skills-context-0'), findsOneWidget);
    });

    testWidgets('a skills phase that failed names the exception type '
        'only', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skillsOutcome: const SectionFailed('PathAccessException'),
        ),
      );

      expect(
        find.text('Skills could not be read (PathAccessException).'),
        findsOneWidget,
      );
    });

    testWidgets('the project files phase that failed marks the context '
        'chain and the templates, skills stay', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          contextOutcome: const SectionFailed('FileSystemException'),
          templatesOutcome: const SectionFailed('FileSystemException'),
          skills: [skillEntry('a')],
        ),
      );

      expect(
        find.text('Context files could not be read (FileSystemException).'),
        findsOneWidget,
      );
      expect(
        find.text('Prompt templates could not be read (FileSystemException).'),
        findsOneWidget,
      );
      expect(_key('skills-row-a'), findsOneWidget);
    });
  });

  group('access and folder (D2)', () {
    testWidgets('an untrusted project: InfoBar with the exact text and the '
        'file of the user config', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          trusted: false,
          files: [contextFile('AGENTS.md')],
          skills: [skillEntry('notes')],
        ),
      );

      expect(_key('skills-untrusted'), findsOneWidget);
      expect(
        _containing(
          'skills-untrusted',
          'This project is not in trusted_projects, so the agent does not '
              'read its skills and prompt templates. Your own skills and '
              'AGENTS.md files are shown.',
        ),
        findsOneWidget,
      );
      expect(
        _containing(
          'skills-untrusted',
          'Trust is set in trusted_projects of '
              '${FakeAgentConfigStore.userPath}.',
        ),
        findsOneWidget,
      );
      expect(_key('skills-context-0'), findsOneWidget);
      expect(_key('skills-row-notes'), findsOneWidget);
    });

    testWidgets('a trusted project has no skills-untrusted', (tester) async {
      await openPage(tester, view: extensionsView());

      expect(_key('skills-untrusted'), findsNothing);
    });

    testWidgets('a WebSocket agent: skills-read-only with the origin, no '
        'tables, no reload, no open, no file read', (tester) async {
      await openPage(
        tester,
        profile: ConnectionProfile.webSocket(
          id: 'devbox',
          label: 'Devbox',
          uri: Uri.parse('wss://devbox:7420/acp'),
        ),
      );

      expect(
        tester.widget<InfoBar>(_key('skills-read-only')).severity,
        InfoBarSeverity.warning,
      );
      expect(
        _containing('skills-read-only', 'wss://devbox:7420'),
        findsOneWidget,
      );
      expect(find.textContaining('/acp'), findsNothing);
      expect(
        _containing('skills-read-only', 'codelab-agent config check'),
        findsOneWidget,
      );
      expect(find.byType(CodeLabStatusTable), findsNothing);
      expect(find.byType(ToggleSwitch), findsNothing);
      expect(_key('skills-reload'), findsNothing);
      expect(_key('skills-open-codelab'), findsNothing);
      expect(session.extensionsCalls, isEmpty);
    });

    testWidgets('a foreign stdio agent: "Skills are managed by python."', (
      tester,
    ) async {
      await openPage(
        tester,
        profile: const ConnectionProfile.stdio(
          id: 'other',
          label: 'Other',
          command: 'python',
          args: ['-m', 'other_agent'],
        ),
      );

      expect(
        _containing('skills-read-only', 'Skills are managed by python.'),
        findsOneWidget,
      );
      expect(find.byType(CodeLabStatusTable), findsNothing);
    });

    testWidgets('no folder: the text, no sections; "Open .codelab folder" '
        'stays and opens CODELAB_HOME', (tester) async {
      projectDir = null;
      await openPage(tester);

      expect(
        find.text(
          'Open a project folder to see the context files, skills and prompt '
          'templates the agent uses there.',
        ),
        findsOneWidget,
      );
      expect(_key('skills-no-folder'), findsOneWidget);
      expect(find.byType(CodeLabStatusTable), findsNothing);
      expect(find.text('Context files'), findsNothing);

      await tester.tap(_key('skills-open-codelab'));
      await tester.pumpAndSettle();
      expect(opener.opened, [_home]);
    });

    testWidgets('a broken config: skills-unreadable with the problem, no '
        'tables and no toggles', (tester) async {
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
      await openPage(tester);

      expect(
        tester.widget<InfoBar>(_key('skills-unreadable')).severity,
        InfoBarSeverity.error,
      );
      expect(
        _containing('skills-unreadable', 'skills.max_skills'),
        findsOneWidget,
      );
      expect(find.byType(CodeLabStatusTable), findsNothing);
      expect(find.byType(ToggleSwitch), findsNothing);
      expect(session.extensionsCalls, isEmpty);
    });
  });

  group('untrusted text from files is escaped everywhere (D12)', () {
    // Управляющий символ в тексте, пришедшем из файла, должен быть виден
    // escape-последовательностью, а не применён.
    const raw = 'x\u202Ey';
    const shown = 'x\\u202ey';

    testWidgets('the path of a context file', (tester) async {
      await openPage(
        tester,
        view: extensionsView(files: [contextFile('dir/$raw/AGENTS.md')]),
      );

      expect(_in('skills-context-0', 'dir/$shown/AGENTS.md'), findsOneWidget);
      expect(find.text('dir/$raw/AGENTS.md'), findsNothing);
    });

    testWidgets('the source file of a template', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          templates: [
            templateEntry(
              '/explain',
              sourcePath: '/work/app/.codelab/prompts/$raw.md',
            ),
          ],
        ),
      );

      expect(
        _in('skills-template-explain', '.codelab/prompts/$shown.md'),
        findsOneWidget,
      );
      expect(find.textContaining(raw), findsNothing);
    });

    testWidgets('"Invoke as" of a skill', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [skillEntry('pdf-tools', invokeAs: '/skill:$raw')],
        ),
      );

      expect(_in('skills-row-pdf-tools', '/skill:$shown'), findsOneWidget);
      expect(find.textContaining(raw), findsNothing);
    });

    testWidgets('the source label of a skill', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [
            skillEntry(
              'pdf-tools',
              root: userSkillRoot(label: '~/$raw/skills'),
            ),
          ],
        ),
      );

      expect(_in('skills-row-pdf-tools', '~/$shown/skills'), findsOneWidget);
      expect(find.textContaining(raw), findsNothing);
    });

    testWidgets('the message of a diagnostic in skills-warnings', (
      tester,
    ) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [skillEntry('a')],
          skillWarnings: [diagnostic('the skill was skipped $raw')],
        ),
      );

      expect(
        _containing('skills-warnings', 'the skill was skipped $shown'),
        findsOneWidget,
      );
      expect(find.textContaining(raw), findsNothing);
    });
  });

  group('review of iteration 4', () {
    String? tooltipOfOpenCodelab(WidgetTester tester) {
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: _key('skills-open-codelab'),
          matching: find.byType(Tooltip),
        ),
      );
      return tooltip.message;
    }

    testWidgets('the tooltip of "Open .codelab folder" names the project '
        '.codelab and the CODELAB_HOME fallback', (tester) async {
      await openPage(tester, view: extensionsView());

      final message = tooltipOfOpenCodelab(tester)!;
      expect(message, contains('/work/app/.codelab'));
      expect(message, contains(_home));
    });

    testWidgets('without a folder the tooltip names CODELAB_HOME', (
      tester,
    ) async {
      projectDir = null;
      await openPage(tester);

      expect(tooltipOfOpenCodelab(tester), contains(_home));
    });

    testWidgets('the banner shows the path with visible control '
        'characters', (tester) async {
      opener.outcome = FolderOpenOutcome.failed;
      await openPage(
        tester,
        view: extensionsView(
          skills: [
            skillEntry(
              'pdf-tools',
              directory: '/home/u/.agents/skills/x\u202Ey',
            ),
          ],
        ),
      );

      await tester.tap(_key('skills-open-skill-pdf-tools'));
      await tester.pumpAndSettle();

      expect(
        _containing(
          'skills-banner',
          'Could not open /home/u/.agents/skills/x\\u202ey.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('x\u202Ey'), findsNothing);
    });
  });

  // Задача 5.1 change `add-app-skills-page` (spec app-settings «Страница
  // «Skills & extensions»: запись и применение»; design.md D5, D9, D12).
  // Красные до задачи 5.2. Ожидаемое поведение страницы:
  // * `skills-toggle-<name>` активен, если `entry.toggle.isAvailable`, иначе
  //   неактивен, а подсказка называет причину отказа моста:
  //   `Set in <файл>; edit that file.` (NotEditable),
  //   `Disabled by the project config (<файл>).` (DisabledByProject),
  //   `Trust this project to read <элемент>.` (UntrustedProject),
  //   `The config file of this layer cannot be read. Fix it first.`
  //   (LayerUnreadable);
  // * строка согласия `skills-consent-<project|home>` (`ToggleSwitch` с этим
  //   ключом) на каждого кандидата `view.skills.consents`, подпись —
  //   `skills-consent-note-<project|home>`: число найденных каталогов
  //   (`3 skill folders found`), область (`in every trusted project` для
  //   относительного элемента) и что `.agents/skills` читается без согласия;
  // * баннер `skills-banner`: `saved` — InfoBar success с текстом
  //   `Saved. New sessions use it; open sessions keep their skills.`;
  //   `conflict` и `error` — warning с текстом Cubit;
  // * пока идёт запись, переключатели неактивны.
  group('write: toggles and consent (iteration 5)', () {
    const savedText =
        'Saved. New sessions use it; open sessions keep their skills.';

    SkillConsentView consent(
      String entry, {
      int? dirs = 3,
      bool granted = false,
      SkillToggle toggle = const SkillToggle.available(),
    }) => SkillConsentView(
      entry: entry,
      path: entry.startsWith('~')
          ? '/home/u/.claude/skills'
          : '$skillsFolder/.claude/skills',
      skillDirs: dirs,
      granted: granted,
      toggle: toggle,
    );

    Finder tooltipOf(String key) =>
        find.ancestor(of: _key(key), matching: find.byType(Tooltip));

    String? hint(WidgetTester tester, String key) =>
        tester.widget<Tooltip>(tooltipOf(key)).message;

    testWidgets('an available switch writes skills.disabled through the '
        'plan and the page shows the saved banner', (tester) async {
      await openPage(
        tester,
        view: extensionsView(skills: [skillEntry('code-review')]),
      );
      expect(
        tester
            .widget<ToggleSwitch>(_key('skills-toggle-code-review'))
            .onChanged,
        isNotNull,
      );

      await tester.tap(_key('skills-toggle-code-review'));
      await tester.pumpAndSettle();

      final edit = store.applied.single.edits.single as SetValue;
      expect(edit.key, 'skills.disabled');
      expect(edit.value, ['code-review']);
      expect(
        tester.widget<InfoBar>(_key('skills-banner')).severity,
        InfoBarSeverity.success,
      );
      expect(_containing('skills-banner', savedText), findsOneWidget);
      expect(session.extensionsCalls, hasLength(2));
    });

    testWidgets('a disabled skill is turned on by the same switch', (
      tester,
    ) async {
      store.user = {
        'skills': {
          'disabled': ['flutter-golden', 'other'],
        },
      };
      await openPage(
        tester,
        view: extensionsView(
          skills: [
            skillEntry(
              'flutter-golden',
              availability: SkillAvailability.disabled,
            ),
          ],
        ),
      );

      await tester.tap(_key('skills-toggle-flutter-golden'));
      await tester.pumpAndSettle();

      expect((store.applied.single.edits.single as SetValue).value, ['other']);
    });

    testWidgets('a refused toggle is inactive and the tooltip says why', (
      tester,
    ) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [
            skillEntry(
              'a',
              toggle: SkillToggle.refused(
                const SkillsListNotEditable('/etc/team.yaml'),
              ),
            ),
            skillEntry(
              'b',
              toggle: SkillToggle.refused(
                const SkillsListDisabledByProject('.codelab/config.yaml'),
              ),
            ),
            skillEntry(
              'c',
              toggle: SkillToggle.refused(
                const SkillsListLayerUnreadable(ConfigLayer.projectLocal),
              ),
            ),
          ],
        ),
      );

      for (final name in const ['a', 'b', 'c']) {
        expect(
          tester.widget<ToggleSwitch>(_key('skills-toggle-$name')).onChanged,
          isNull,
          reason: name,
        );
      }
      expect(
        hint(tester, 'skills-toggle-a'),
        'Set in /etc/team.yaml; edit that file.',
      );
      expect(
        hint(tester, 'skills-toggle-b'),
        'Disabled by the project config (.codelab/config.yaml).',
      );
      expect(
        hint(tester, 'skills-toggle-c'),
        'The config file of this layer cannot be read. Fix it first.',
      );
      await tester.tap(_key('skills-toggle-a'));
      await tester.pumpAndSettle();
      expect(store.applied, isEmpty);
    });

    testWidgets('consent rows exist only for the candidates of the view, '
        'with the count and the scope in the caption', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          consents: [
            consent('.claude/skills'),
            consent('~/.claude/skills', dirs: 1, granted: true),
          ],
        ),
      );

      expect(_key('skills-consent-project'), findsOneWidget);
      expect(_key('skills-consent-home'), findsOneWidget);
      expect(
        tester.widget<ToggleSwitch>(_key('skills-consent-project')).checked,
        isFalse,
      );
      expect(
        tester.widget<ToggleSwitch>(_key('skills-consent-home')).checked,
        isTrue,
      );
      expect(
        _containing('skills-consent-note-project', '3 skill folders'),
        findsOneWidget,
      );
      expect(
        _containing('skills-consent-note-project', 'in every trusted project'),
        findsOneWidget,
      );
      expect(
        _containing('skills-consent-note-project', '.agents/skills'),
        findsOneWidget,
      );
      expect(
        _containing('skills-consent-note-home', '1 skill folder'),
        findsOneWidget,
      );
      expect(
        _containing('skills-consent-note-home', 'in every trusted project'),
        findsNothing,
      );
    });

    testWidgets('without candidates there are no consent rows', (tester) async {
      await openPage(tester, view: extensionsView());

      expect(_key('skills-consent-project'), findsNothing);
      expect(_key('skills-consent-home'), findsNothing);
    });

    testWidgets('the consent switch gives the home root: extra_roots with '
        'the element, the saved banner', (tester) async {
      await openPage(
        tester,
        view: extensionsView(consents: [consent('~/.claude/skills')]),
      );

      await tester.tap(_key('skills-consent-home'));
      await tester.pumpAndSettle();

      final edit = store.applied.single.edits.single as SetValue;
      expect(edit.key, 'skills.extra_roots');
      expect(edit.value, ['~/.claude/skills']);
      expect(_containing('skills-banner', savedText), findsOneWidget);
    });

    testWidgets('a granted consent is revoked by the same switch', (
      tester,
    ) async {
      store.user = {
        'skills': {
          'extra_roots': ['~/.claude/skills', '/opt/more'],
        },
      };
      await openPage(
        tester,
        view: extensionsView(
          consents: [consent('~/.claude/skills', granted: true)],
        ),
      );

      await tester.tap(_key('skills-consent-home'));
      await tester.pumpAndSettle();

      expect((store.applied.single.edits.single as SetValue).value, [
        '/opt/more',
      ]);
    });

    testWidgets('a refused consent is inactive with the Q3 hint', (
      tester,
    ) async {
      await openPage(
        tester,
        view: extensionsView(
          trusted: false,
          consents: [
            consent(
              '.claude/skills',
              toggle: SkillToggle.refused(const SkillsListUntrustedProject()),
            ),
            consent(
              '~/.claude/skills',
              toggle: SkillToggle.refused(
                const SkillsListNotEditable('/etc/team.yaml'),
              ),
            ),
          ],
        ),
      );

      expect(
        tester.widget<ToggleSwitch>(_key('skills-consent-project')).onChanged,
        isNull,
      );
      expect(
        hint(tester, 'skills-consent-project'),
        'Trust this project to read .claude/skills.',
      );
      expect(
        hint(tester, 'skills-consent-home'),
        'Set in /etc/team.yaml; edit that file.',
      );
    });

    testWidgets('a conflict is the warning banner and the page is '
        're-read', (tester) async {
      store.firstOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      await openPage(tester, view: extensionsView(skills: [skillEntry('a')]));

      await tester.tap(_key('skills-toggle-a'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<InfoBar>(_key('skills-banner')).severity,
        InfoBarSeverity.warning,
      );
      expect(_containing('skills-banner', 'changed on disk'), findsOneWidget);
      expect(store.applied, hasLength(1));
      expect(session.extensionsCalls, hasLength(2));
    });

    testWidgets('a rejected write is the banner with the loader problem', (
      tester,
    ) async {
      store.nextOutcome = const ConfigRejected([
        ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'skills.disabled',
          source: FakeAgentConfigStore.userPath,
          message: 'must be a list of names',
        ),
      ]);
      await openPage(tester, view: extensionsView(skills: [skillEntry('a')]));

      await tester.tap(_key('skills-toggle-a'));
      await tester.pumpAndSettle();

      expect(
        _containing('skills-banner', 'must be a list of names'),
        findsOneWidget,
      );
    });

    testWidgets('while the write runs the switches are inactive and a '
        'second tap is not a second write', (tester) async {
      final gate = Completer<void>();
      store.onApply = () => gate.future;
      await openPage(
        tester,
        view: extensionsView(skills: [skillEntry('a'), skillEntry('b')]),
      );

      await tester.tap(_key('skills-toggle-a'));
      await tester.pump();
      expect(
        tester.widget<ToggleSwitch>(_key('skills-toggle-a')).onChanged,
        isNull,
      );
      expect(
        tester.widget<ToggleSwitch>(_key('skills-toggle-b')).onChanged,
        isNull,
      );
      await tester.tap(_key('skills-toggle-b'));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();

      expect(store.applied, hasLength(1));
    });
  });

  group('actions', () {
    testWidgets('"Reload" re-reads the config and the files and sends '
        'nothing to the agent', (tester) async {
      await openPage(tester, view: extensionsView());
      expect(session.extensionsCalls, hasLength(1));
      final snapshots = store.snapshots;

      await tester.tap(_key('skills-reload'));
      await tester.pumpAndSettle();

      expect(session.extensionsCalls, hasLength(2));
      expect(store.snapshots, snapshots + 1);
    });

    testWidgets('"Open .codelab folder" passes <folder>/.codelab and its '
        'tooltip names the path', (tester) async {
      await openPage(tester, view: extensionsView());

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Tooltip && (w.message ?? '').contains('/work/app/.codelab'),
        ),
        findsOneWidget,
      );

      await tester.tap(_key('skills-open-codelab'));
      await tester.pumpAndSettle();

      expect(opener.opened, ['/work/app/.codelab']);
      expect(_key('skills-banner'), findsNothing);
    });

    testWidgets('a refusal of the platform is the banner with the '
        'path', (tester) async {
      opener.outcome = FolderOpenOutcome.failed;
      await openPage(
        tester,
        view: extensionsView(
          skills: [skillEntry('pdf-tools', root: userSkillRoot())],
        ),
      );

      await tester.tap(_key('skills-open-skill-pdf-tools'));
      await tester.pumpAndSettle();

      expect(
        _containing(
          'skills-banner',
          'Could not open /home/u/.agents/skills/pdf-tools.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a read-only page (WebSocket agent) has no skill switches '
        'and no consent rows, and nothing is written', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [skillEntry('a')],
          consents: [
            SkillConsentView(
              entry: '~/.claude/skills',
              path: '/home/u/.claude/skills',
              skillDirs: 1,
              granted: false,
              toggle: const SkillToggle.available(),
            ),
          ],
        ),
        profile: ConnectionProfile.webSocket(
          id: 'devbox',
          label: 'Devbox',
          uri: Uri.parse('wss://devbox:7420/acp'),
        ),
      );

      expect(_key('skills-read-only'), findsOneWidget);
      expect(find.byType(ToggleSwitch), findsNothing);
      expect(_key('skills-consent-home'), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(store.applied, isEmpty);
    });
  });
}
