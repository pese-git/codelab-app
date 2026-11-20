// Тесты задач 5.1c и 5.2 change `add-desktop-localization`: страница
// «Skills & extensions» на русском и английском, смена языка на странице
// (spec app-settings «Страница «Skills & extensions» на русском», «Страницы
// настроек II пересобираются при смене языка»; design.md D5 «Уточнение
// итерации 5», D6, D7, D8, D9).
//
// Страница строится на настоящем `SkillsSettingsCubit` с двойниками сессии
// настроек и `LocalFolderOpener`, как в `skills_page_test.dart`; язык меняет
// `PageLanguage`. Подписи перекрытия и дополнительной папки строятся по
// полям моста `overridesScope` и `extraEntry` (D6, В2), отказ списка — одной
// функцией `skillsRefusalText` для подсказки переключателя и баннера (D5).
//
// Ожидания `en` — прежние строки. Ожидания `ru` — по глоссарию §4:
// «Файлы контекста», «Порядок поиска», «Вызов как», «Только модель» / «Только
// команда», «Переопределяет навык пользователя / проекта / из дополнительной
// папки», «Переопределяет другой навык», «(дополнительная папка)», «Читать
// {entry}», «Согласие действует во всех доверенных проектах», «4.8 КБ». Фразы
// вне глоссария проверяются без выдуманного перевода (английской фразы на
// экране нет, значения сохранены). Имена и описания навыков и шаблонов,
// пути, команды и тексты ядра — как есть (D7, D6).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/settings/application/skills_settings_cubit.dart';
import 'package:codelab_desktop/features/settings/presentation/skills_page.dart';
import 'package:codelab_desktop/features/settings/presentation/skills_texts.dart'
    as texts;
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:fluent_ui/fluent_ui.dart' hide DiagnosticLevel;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_agent_extensions.dart';
import '../../../support/fake_local_folder_opener.dart';
import '../../../support/fake_provider_settings.dart';
import '../../../support/l10n_mix.dart';
import '../../../support/l10n_page_harness.dart';
import '../../../support/recording_logger.dart';

const _home = '/home/u/.codelab';

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String owner, String text) =>
    find.descendant(of: _key(owner), matching: find.text(text));

Finder _containing(String owner, String text) =>
    find.descendant(of: _key(owner), matching: find.textContaining(text));

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

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
  late PageLanguage language;
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
    Locale locale = const Locale('en'),
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
    language = PageLanguage(locale);
    addTearDown(language.dispose);
    await tester.pumpWidget(
      language.wrap(
        ScaffoldPage(
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

  /// Вид с файлами контекста, навыками разных областей и шаблоном.
  AgentExtensionsView richView() => extensionsView(
    files: [
      contextFile('AGENTS.md', bytes: 4915),
      contextFile('packages/ui/AGENTS.md', bytes: 1331),
    ],
    skills: [
      skillEntry(
        'release-notes',
        root: projectSkillRoot(),
        overrides: [userSkillRoot()],
        overridesLabel: 'Overrides user skill',
        overridesScope: ExtensionScope.user,
      ),
      skillEntry(
        'ship',
        root: projectSkillRoot(),
        overrides: [extraSkillRoot()],
        overridesLabel: 'Overrides extra skill',
        overridesScope: ExtensionScope.extra,
      ),
      skillEntry('deploy-check', modelVisible: false),
      skillEntry('background', userInvocable: false),
      skillEntry('imported', root: extraSkillRoot()),
      skillEntry(
        'pdf_tools',
        warnings: [
          diagnostic(
            'the skill name differs from its directory name',
            path: '/home/u/.agents/skills/pdf-tools/SKILL.md',
          ),
        ],
      ),
    ],
    templates: [templateEntry('/review', description: 'Review a diff')],
  );

  group('файлы контекста, навыки и шаблоны', () {
    testWidgets('en: размеры, перекрытие и теги — прежние строки', (
      tester,
    ) async {
      await openPage(tester, view: richView());

      expect(_in('skills-context-0', '4.8 KB'), findsOneWidget);
      expect(find.text('2 files · 6.1 KB'), findsOneWidget);
      expect(
        _in('skills-row-release-notes', 'Overrides user skill'),
        findsOneWidget,
      );
      expect(_in('skills-row-deploy-check', 'Command only'), findsOneWidget);
      expect(_in('skills-row-background', 'Model only'), findsOneWidget);
      expect(
        _in('skills-row-imported', '.claude/skills (extra root)'),
        findsOneWidget,
      );
    });

    testWidgets('ru: размер файла «4.8 КБ» и заголовки разделов (сценарий '
        '«Страница «Skills & extensions» на русском»)', (tester) async {
      await openPage(tester, view: richView(), locale: const Locale('ru'));

      expect(_in('skills-context-0', '4.8 КБ'), findsOneWidget);
      expect(_in('skills-context-1', '1.3 КБ'), findsOneWidget);
      expect(find.textContaining('6.1 КБ'), findsOneWidget);
      expect(find.text('Файлы контекста'), findsWidgets);
      expect(find.text('Шаблоны промптов'), findsWidgets);
      expect(find.textContaining('KB'), findsNothing);
      expectNoEnglish(const ['Context files', 'Prompt templates']);
      // Имена файлов, навыков и шаблонов — как есть.
      expect(find.text('AGENTS.md'), findsWidgets);
      expect(_key('skills-row-release-notes'), findsOneWidget);
      expect(_key('skills-template-review'), findsOneWidget);
    });

    testWidgets('ru: подпись перекрытия по overridesScope', (tester) async {
      await openPage(tester, view: richView(), locale: const Locale('ru'));

      expect(
        _in('skills-row-release-notes', 'Переопределяет навык пользователя'),
        findsOneWidget,
      );
      expect(
        _in('skills-row-ship', 'Переопределяет навык из дополнительной папки'),
        findsOneWidget,
      );
      expectNoEnglish(const ['Overrides user skill', 'Overrides extra skill']);
    });

    testWidgets('ru: «Переопределяет навык проекта» и «Переопределяет '
        'другой навык»', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [
            skillEntry(
              'a',
              overrides: [projectSkillRoot()],
              overridesLabel: 'Overrides project skill',
              overridesScope: ExtensionScope.project,
            ),
            skillEntry(
              'b',
              overrides: [projectSkillRoot()],
              overridesLabel: 'Overrides another skill',
            ),
          ],
        ),
        locale: const Locale('ru'),
      );

      expect(
        _in('skills-row-a', 'Переопределяет навык проекта'),
        findsOneWidget,
      );
      expect(
        _in('skills-row-b', 'Переопределяет другой навык'),
        findsOneWidget,
      );
    });

    testWidgets('ru: «Только команда», «Только модель», «Вызов как» и '
        '`/skill:<name>` как есть', (tester) async {
      await openPage(tester, view: richView(), locale: const Locale('ru'));

      expect(_in('skills-row-deploy-check', 'Только команда'), findsOneWidget);
      expect(_in('skills-row-background', 'Только модель'), findsOneWidget);
      expect(
        _in('skills-row-deploy-check', '/skill:deploy-check'),
        findsOneWidget,
      );
      expect(find.text('Вызов как'), findsOneWidget);
      expectNoEnglish(const ['Command only', 'Model only', 'Invoke as']);
    });

    testWidgets('ru: дополнительная папка по extraEntry, неизвестная — своей '
        'подписью', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          skills: [
            skillEntry('imported', root: extraSkillRoot()),
            skillEntry(
              'stray',
              root: const SkillRootView(
                scope: ExtensionScope.extra,
                label: '(unknown root)',
                path: '/work/app/.x/skills',
              ),
            ),
          ],
        ),
        locale: const Locale('ru'),
      );

      expect(
        _in('skills-row-imported', '.claude/skills (дополнительная папка)'),
        findsOneWidget,
      );
      expect(_in('skills-row-stray', '(неизвестная папка)'), findsOneWidget);
      expectNoEnglish(const ['extra root', 'unknown root']);
    });

    testWidgets('ru: предупреждение ядра — как есть под переведённым '
        'заголовком, число — форма plural', (tester) async {
      for (final (count, tag) in const [
        (1, '1 предупреждение'),
        (2, '2 предупреждения'),
        (5, '5 предупреждений'),
      ]) {
        await openPage(
          tester,
          view: extensionsView(
            skills: [
              skillEntry(
                'warned',
                warnings: [
                  for (var i = 0; i < count; i++)
                    diagnostic('the core warning $i'),
                ],
              ),
            ],
          ),
          locale: const Locale('ru'),
        );

        expect(_in('skills-row-warned', tag), findsOneWidget, reason: tag);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Tooltip &&
                (w.message ?? '').contains('the core warning 0'),
          ),
          findsOneWidget,
          reason: 'текст ядра в подсказке как есть: $tag',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('ru: пустые разделы — без английского', (tester) async {
      await openPage(
        tester,
        view: extensionsView(),
        locale: const Locale('ru'),
      );

      expectNoEnglish(const [
        'No AGENTS.md files for this folder.',
        'No prompt templates.',
        'No skills found.',
      ]);
    });
  });

  group('согласие на папки навыков другого агента', () {
    SkillConsentView consent(
      String entry, {
      bool granted = false,
      SkillToggle toggle = const SkillToggle.available(),
    }) => SkillConsentView(
      entry: entry,
      path: entry.startsWith('~')
          ? '/home/u/.claude/skills'
          : '$skillsFolder/.claude/skills',
      skillDirs: 3,
      granted: granted,
      toggle: toggle,
    );

    testWidgets('ru: «Читать {entry}» и «Согласие действует во всех '
        'доверенных проектах» — элемент и путь как есть', (tester) async {
      await openPage(
        tester,
        view: extensionsView(
          consents: [consent('.claude/skills'), consent('~/.claude/skills')],
        ),
        locale: const Locale('ru'),
      );

      expect(find.text('Читать .claude/skills'), findsOneWidget);
      expect(find.text('Читать ~/.claude/skills'), findsOneWidget);
      expect(
        _containing(
          'skills-consent-note-project',
          'Согласие действует во всех доверенных проектах',
        ),
        findsOneWidget,
      );
      expectNoEnglish(const [
        'Consent applies in every trusted project',
        'Read .claude/skills',
        'skill folders found',
      ]);
    });

    testWidgets('en: строки согласия прежние', (tester) async {
      await openPage(
        tester,
        view: extensionsView(consents: [consent('.claude/skills')]),
      );

      expect(find.text('Read .claude/skills'), findsOneWidget);
      expect(
        _containing(
          'skills-consent-note-project',
          'Consent applies in every trusted project',
        ),
        findsOneWidget,
      );
    });
  });

  group('отказы записи: подсказка и баннер — один текст', () {
    String? hint(WidgetTester tester, String key) => tester
        .widget<Tooltip>(
          find.ancestor(of: _key(key), matching: find.byType(Tooltip)),
        )
        .message;

    testWidgets('ru: подсказка переключателя равна skillsRefusalText на ru, '
        'путь без изменений', (tester) async {
      const notEditable = SkillsListNotEditable('/etc/team.yaml');
      const untrusted = SkillsListUntrustedProject();
      await openPage(
        tester,
        view: extensionsView(
          skills: [skillEntry('a', toggle: SkillToggle.refused(notEditable))],
          consents: [
            SkillConsentView(
              entry: '.claude/skills',
              path: '/work/app/.claude/skills',
              skillDirs: null,
              granted: false,
              toggle: SkillToggle.refused(untrusted),
            ),
          ],
        ),
        locale: const Locale('ru'),
      );

      expect(
        hint(tester, 'skills-toggle-a'),
        texts.skillsRefusalText(ru, notEditable),
      );
      expect(hint(tester, 'skills-toggle-a'), contains('/etc/team.yaml'));
      expect(hint(tester, 'skills-toggle-a'), isNot(contains('Set in')));
      expect(
        hint(tester, 'skills-consent-project'),
        texts.skillsRefusalText(ru, untrusted, element: '.claude/skills'),
      );
      expect(
        hint(tester, 'skills-consent-project'),
        contains('.claude/skills'),
      );
    });

    testWidgets('en: подсказки прежние', (tester) async {
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
          ],
        ),
      );

      expect(
        hint(tester, 'skills-toggle-a'),
        'Set in /etc/team.yaml; edit that file.',
      );
    });

    testWidgets('ru: баннер конфликта записи — переведённый заголовок и текст '
        'сообщения, имя навыка не затронуто', (tester) async {
      store.firstOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      await openPage(
        tester,
        view: extensionsView(skills: [skillEntry('a')]),
        locale: const Locale('ru'),
      );

      await tester.tap(_key('skills-toggle-a'));
      await tester.pumpAndSettle();

      expect(_key('skills-banner'), findsOneWidget);
      expect(
        _containing(
          'skills-banner',
          texts.skillsMessageText(ru, const SkillsConflictMessage()),
        ),
        findsOneWidget,
      );
      expect(find.text('Not saved'), findsNothing);
      expectNoEnglish(const ['changed on disk', 'Not saved']);
      expect(_key('skills-row-a'), findsOneWidget);
    });

    testWidgets('ru: отказ ядра в баннере — заголовок по-русски, текст '
        'проверки как есть', (tester) async {
      store.nextOutcome = const ConfigRejected([
        ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'skills.disabled',
          source: FakeAgentConfigStore.userPath,
          message: 'must be a list of names',
        ),
      ]);
      await openPage(
        tester,
        view: extensionsView(skills: [skillEntry('a')]),
        locale: const Locale('ru'),
      );

      await tester.tap(_key('skills-toggle-a'));
      await tester.pumpAndSettle();

      expect(
        _containing(
          'skills-banner',
          'skills.disabled: must be a list of names',
        ),
        findsOneWidget,
      );
      expectNoEnglish(const ['The config was not saved', 'Not saved']);
    });

    testWidgets('en: баннер сохранения и конфликта прежние', (tester) async {
      store.firstOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      await openPage(tester, view: extensionsView(skills: [skillEntry('a')]));
      await tester.tap(_key('skills-toggle-a'));
      await tester.pumpAndSettle();

      expect(_in('skills-banner', 'Not saved'), findsOneWidget);
      expect(_containing('skills-banner', 'changed on disk'), findsOneWidget);
    });
  });

  group('InfoBar и пустые состояния', () {
    testWidgets('ru: «только чтение» удалённого агента — адрес без пути, '
        'команда как есть', (tester) async {
      await openPage(
        tester,
        profile: ConnectionProfile.webSocket(
          id: 'devbox',
          label: 'Devbox',
          uri: Uri.parse('wss://devbox:7420/acp'),
        ),
        locale: const Locale('ru'),
      );

      expect(
        _containing('skills-read-only', 'wss://devbox:7420'),
        findsOneWidget,
      );
      expect(
        _containing('skills-read-only', 'codelab-agent config check'),
        findsOneWidget,
      );
      expect(find.textContaining('/acp'), findsNothing);
      expectNoEnglish(const [
        'Read-only: this agent runs on',
        'Its skills, context files and prompt templates',
      ]);
    });

    testWidgets('ru: сторонний агент называет агента', (tester) async {
      await openPage(
        tester,
        profile: const ConnectionProfile.stdio(
          id: 'other',
          label: 'Other',
          command: 'python',
          args: ['-m', 'other_agent'],
        ),
        locale: const Locale('ru'),
      );

      expect(_containing('skills-read-only', 'python'), findsOneWidget);
      expectNoEnglish(const ['Skills are managed by']);
    });

    testWidgets('ru: нет папки проекта — текст по-русски, кнопка открывает '
        'CODELAB_HOME', (tester) async {
      projectDir = null;
      await openPage(tester, locale: const Locale('ru'));

      expect(_key('skills-no-folder'), findsOneWidget);
      expectNoEnglish(const [
        'Open a project folder to see',
        'Open .codelab folder',
      ]);
      await tester.tap(_key('skills-open-codelab'));
      await tester.pumpAndSettle();
      expect(opener.opened, [_home]);
    });

    testWidgets('ru: недоверенный проект и нечитаемый конфиг — без '
        'английского, путь и текст загрузчика как есть', (tester) async {
      await openPage(
        tester,
        view: extensionsView(trusted: false),
        locale: const Locale('ru'),
      );

      expect(
        _containing('skills-untrusted', FakeAgentConfigStore.userPath),
        findsOneWidget,
      );
      expectNoEnglish(const [
        'This project is not in trusted_projects',
        'Trust is set in',
      ]);

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
      await openPage(tester, locale: const Locale('ru'));

      expect(
        _containing('skills-unreadable', 'skills.max_skills'),
        findsOneWidget,
      );
      expectNoEnglish(const [
        'Cannot read the agent config',
        'CodeLab will not overwrite it',
      ]);
    });
  });

  group('смена языка (D5, D9)', () {
    testWidgets('рабочее состояние: en → ru → en, expectNoStaleLanguage', (
      tester,
    ) async {
      await openPage(tester, view: richView());

      await language.select(tester, const Locale('ru'));
      await expectNoStaleLanguage(tester, from: en, to: ru);
      expect(_in('skills-context-0', '4.8 КБ'), findsOneWidget);

      await language.select(tester, const Locale('en'));
      await expectNoStaleLanguage(tester, from: ru, to: en);
      expect(_in('skills-context-0', '4.8 KB'), findsOneWidget);
    });

    testWidgets('с баннером отказа записи, подсказкой переключателя и '
        'согласием: пересобираются, пути не изменились', (tester) async {
      store.firstOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      await openPage(
        tester,
        view: extensionsView(
          skills: [
            skillEntry('a'),
            skillEntry(
              'b',
              toggle: SkillToggle.refused(
                const SkillsListNotEditable('/etc/team.yaml'),
              ),
            ),
          ],
          consents: [
            SkillConsentView(
              entry: '.claude/skills',
              path: '/work/app/.claude/skills',
              skillDirs: 3,
              granted: false,
              toggle: const SkillToggle.available(),
            ),
          ],
        ),
      );
      await tester.tap(_key('skills-toggle-a'));
      await tester.pumpAndSettle();
      expect(_key('skills-banner'), findsOneWidget);

      await language.select(tester, const Locale('ru'));
      await expectNoStaleLanguage(tester, from: en, to: ru);
      expectNoEnglish(const ['changed on disk', 'Not saved']);
      expect(find.text('Читать .claude/skills'), findsOneWidget);
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(
                of: _key('skills-toggle-b'),
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        contains('/etc/team.yaml'),
      );

      await language.select(tester, const Locale('en'));
      await expectNoStaleLanguage(tester, from: ru, to: en);
      expect(_in('skills-banner', 'Not saved'), findsOneWidget);
    });

    testWidgets('read-only: пересобирается при смене языка', (tester) async {
      await openPage(
        tester,
        profile: ConnectionProfile.webSocket(
          id: 'devbox',
          label: 'Devbox',
          uri: Uri.parse('wss://devbox:7420/acp'),
        ),
      );

      await language.select(tester, const Locale('ru'));
      await expectNoStaleLanguage(tester, from: en, to: ru);
      expectNoEnglish(const ['Read-only: this agent runs on']);
      expect(
        _containing('skills-read-only', 'wss://devbox:7420'),
        findsOneWidget,
      );
    });
  });
}
