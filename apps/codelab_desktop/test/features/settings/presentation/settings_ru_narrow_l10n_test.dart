// Тесты задачи 4.2 change `add-desktop-localization`: русский текст не
// переполняет узкие места итерации 4 при ширине окна 760 px (D8, «Длина
// строк»): диалог «Add connection profile» (все варианты токена, предупреждение
// `ws://`), строки провайдеров и шапка мастера. Проверяется поведение —
// `tester.takeException()` пуст, а не пиксели.

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/settings/application/agents_modes_cubit.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/settings/application/mcp_settings_cubit.dart';
import 'package:codelab_desktop/features/settings/application/skills_settings_cubit.dart';
import 'package:codelab_desktop/features/settings/presentation/agents_modes_page.dart';
import 'package:codelab_desktop/features/settings/presentation/mcp_page.dart';
import 'package:codelab_desktop/features/settings/presentation/skills_page.dart';
import 'package:codelab_embedded/codelab_embedded.dart' show McpServerState;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_agent_extensions.dart';
import '../../../support/fake_agents_modes_cubit.dart';
import '../../../support/fake_local_folder_opener.dart';
import '../../../support/fake_mcp_status.dart';
import '../../../support/fake_profile_secrets.dart';
import '../../../support/l10n_page_harness.dart';
import '../../../support/recording_logger.dart';
import '../../../support/fake_provider_settings.dart';
import '../../../support/in_memory_profile_store.dart';
import '../../../support/test_app_scope.dart';

const _pages = SettingsPages(
  available: {SettingsPage.connection, SettingsPage.providers},
);

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    // Открываем настройки в обычном окне: в узком сайдбар свёрнут.
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }

  /// Страница настроек [page] на русском в окне 760 px.
  Future<void> openSettings(
    WidgetTester tester,
    SettingsPage page, {
    ProviderSettingsSession? session,
    FakeProfileSecrets? secrets,
    Map<String, String> environment = const {},
  }) async {
    final binding = CodeLabTestBinding(
      project: '/workspace',
      locale: const Locale('ru'),
      stdioDefault: false,
      profileStore: InMemoryProfileStore(),
      profileSecrets: secrets,
      environment: {'HOME': '/home/u', ...environment},
      settingsPages: _pages,
      stdioTransportFactory: (_) => FakeAcpTransport(),
      webSocketTransportFactory: (_) => FakeAcpTransport(),
      providerSettingsOpener: session == null
          ? null
          : (access, env) async => session,
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
    await tester.pumpAndSettle();
    if (page != SettingsPage.connection) {
      await tester.tap(_key(page.navKey));
      await tester.pumpAndSettle();
    }
    // Затем окно сужается до 760 px (D8): страница и диалоги перестраиваются.
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single
        .physicalSize = const Size(
      760,
      900,
    );
    await tester.pumpAndSettle();
  }

  group('ru, 760 px', () {
    testWidgets('диалог профиля: stdio, WebSocket, все варианты токена и '
        'предупреждение ws://', (tester) async {
      await openSettings(
        tester,
        SettingsPage.connection,
        secrets: FakeProfileSecrets(values: {'codelab/ci/token': 'v'}),
      );
      await tester.tap(_key('connection-add-profile'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'stdio');

      await tester.enterText(_key('add-profile-env'), 'API_KEY=x');
      await tester.enterText(_key('add-profile-command'), '');
      await tester.enterText(_key('add-profile-args'), 'serve "unclosed');
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'ошибки stdio');

      await tester.tap(_key('add-profile-type-websocket'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'ws://box:7420');
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'WebSocket');

      for (final token in const ['stored', 'new', 'env', 'none']) {
        await tester.tap(_key('add-profile-token-$token'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'токен: $token');
      }

      await tester.tap(_key('add-profile-token-env'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('add-profile-token-env-name'), 'MISSING_VAR');
      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();
      expect(_key('add-profile-unencrypted'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'подтверждение ws://');

      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('строки провайдеров: свёрнутые и раскрытые, подсказки и '
        'теги', (tester) async {
      final store = FakeAgentConfigStore(
        user: {
          'agent': {'default_model': 'anthropic/m'},
          'providers': {
            'anthropic': providerMap(
              kind: 'anthropic',
              baseUrl: null,
              secret: 'codelab/anthropic',
            ),
            'remote': providerMap(
              baseUrl: 'http://api.example.com/v1',
              env: 'REMOTE_KEY',
              models: ['a', 'b', 'c', 'd', 'e'],
            ),
            'lit': {...providerMap(), 'api_key': leakMarker},
            'g': providerMap(kind: 'gemini', baseUrl: null, env: 'G'),
          },
        },
      );
      final session = FakeProviderSettingsSession(
        store,
        secrets: {'codelab/anthropic': leakMarker},
      );
      session.checkResult = () async => const CheckFailure(
        ProviderCheckFailure(
          kind: ProviderCheckFailureKind.unauthorized,
          statusCode: 401,
          message: 'x',
        ),
      );
      await openSettings(tester, SettingsPage.providers, session: session);
      expect(tester.takeException(), isNull, reason: 'свёрнутые');

      await tester.tap(_key('providers-check-anthropic'));
      await tester.pumpAndSettle();
      for (final id in const ['anthropic', 'remote', 'lit', 'g']) {
        await tester.tap(_key('providers-row-$id'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'раскрыта: $id');
        await tester.tap(_key('providers-row-$id'));
        await tester.pumpAndSettle();
      }
      await tearDownApp(tester);
    });

    testWidgets('шапка мастера: строка шагов, сводка и подпись шагов на всём '
        'пути', (tester) async {
      final store = FakeAgentConfigStore(
        user: {
          'providers': {
            'local': providerMap(
              baseUrl: 'http://localhost:11434/v1',
              models: ['qwen'],
            ),
          },
        },
      );
      final session = FakeProviderSettingsSession(store);
      await openSettings(tester, SettingsPage.providers, session: session);

      await tester.tap(_key('providers-add'));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'тип API');
      await tester.tap(_key('provider-wizard-preset-custom-anthropic'));
      await frames(tester, 2);
      await tester.tap(_key('provider-wizard-next'));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'базовый URL');
      await tester.enterText(
        _key('provider-wizard-base-url-field'),
        'https://llm.example/v1',
      );
      await tester.tap(_key('provider-wizard-next'));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'ключ');
      await tester.tap(_key('provider-wizard-key-store'));
      await frames(tester, 2);
      await tester.tap(_key('provider-wizard-next'));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'ошибка ключа');
      await tester.tap(_key('provider-wizard-key-none'));
      await frames(tester, 2);
      await tester.tap(_key('provider-wizard-next'));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'проверка');
      session.wizardCheck.respond(
        const CheckOk([RemoteModel('m1', contextWindow: 8000)]),
      );
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'модель');
      await tester.tap(_key('provider-wizard-model-m1'));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'обзор');

      await tester.tap(_key('provider-wizard-cancel'));
      await frames(tester);
      await tearDownApp(tester);
    });
  });

  // --- Настройки II (change `add-desktop-localization`, итерация 5;
  // design.md D8 «Длина строк итерации 5»). Страницы строятся напрямую, без
  // оболочки настроек: окно 440 pt с полями 40 даёт колонке 360 pt — столько
  // же, сколько остаётся странице при окне 760 px после навигации настроек
  // (320 pt) и полей. Проверяется поведение: `tester.takeException()` пуст,
  // подписи колонок и состояние повтора на месте (длинный заголовок может
  // уйти в многоточие с подсказкой кита).
  group('ru, 760 px: настройки II', () {
    setUp(() {
      final view = TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .single;
      view.physicalSize = const Size(440, 2400);
      view.devicePixelRatio = 1.0;
      addTearDown(view.resetPhysicalSize);
      addTearDown(view.resetDevicePixelRatio);
    });

    Widget framed(Widget page) => ScaffoldPage(
      content: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 28, 40, 40),
        child: page,
      ),
    );

    testWidgets('«Agent status»: полные колонки и «сбой · повтор через 24 с» '
        'на месте, переполнения нет', (tester) async {
      final store = FakeAgentConfigStore(
        user: {
          'mcp': {
            'servers': [
              {'name': 'github', 'type': 'stdio', 'command': 'npx'},
            ],
          },
        },
      );
      final session = FakeProviderSettingsSession(store);
      final workspace = FakeWorkspace();
      final source = FakeEmbeddedMcpStatusSource();
      final s1 = SessionId('s1');
      source.ports[s1] = FakeMcpStatusPort(
        'p1',
        servers: [
          mcpSummary('github', tools: 42),
          mcpSummary(
            'postgres',
            state: McpServerState.failed,
            lastError: 'connection refused by the remote host',
            retryIn: const Duration(seconds: 24),
          ),
          mcpSummary('playwright', state: McpServerState.disabled),
        ],
      );
      workspace.emit(
        WorkspaceState(
          connection: const ConnectionView.connected(),
          profile: embeddedConnectionProfile,
          activeSessionId: s1,
        ),
      );
      final cubit = McpSettingsCubit(
        workspace: workspace,
        defaultProfile: () async => embeddedConnectionProfile,
        open: (access, env) async => session,
        environment: const {'HOME': '/home/u'},
        codelabHome: '/home/u/.codelab',
        projectDirectory: () => '/work/app',
        statusSource: source,
        logger: RecordingLogger(),
        now: () => DateTime(2026, 11, 8, 14, 2),
      );
      addTearDown(cubit.close);
      await cubit.reload();
      final language = PageLanguage(const Locale('ru'));
      addTearDown(language.dispose);
      await tester.pumpWidget(
        language.wrap(
          framed(
            BlocProvider<McpSettingsCubit>.value(
              value: cubit,
              child: const McpPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 760 px (колонка ~360 pt): переполнения нет; длинные заголовки могут
      // уйти в многоточие с подсказкой кита (D8).
      expect(tester.takeException(), isNull);
      // Подпись переключателя сервера не рвётся на слоги даже на узкой колонке.
      expect(tester.getSize(find.text('Вкл')).height, lessThan(26));
      expect(find.text('Сервер'), findsOneWidget);
      expect(find.text('Последняя ошибка'), findsOneWidget);
      // Окно 800 pt (колонка ~400 pt, веса D8): переполнения нет, а подпись
      // колонки и состояние повтора на месте. Заголовок «Инструменты» в
      // тестовом шрифте Ahem (вдвое шире настоящего) не помещается ни при
      // каких весах, как и ячейка «сбой · повтор через 24 с» (`didExceedMaxLines`
      // истинно и при колонке 480 pt): «целиком» проверяется глазами на
      // реальном шрифте, а здесь — подсказка кита с полным текстом.
      TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .single
          .physicalSize = const Size(
        480,
        2400,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Инструменты'), findsOneWidget);
      expect(find.byTooltip('Инструменты'), findsOneWidget);
      expect(find.text('сбой · повтор через 24 с'), findsOneWidget);
      expect(find.text('Переподключить все'), findsOneWidget);
    });

    testWidgets('«Agents & modes»: таблица определений с длинными статусами, '
        'диалог bypass и баннер записи — без переполнения', (tester) async {
      final cubit = FakeAgentsModesCubit(
        AgentsModesReady(
          mode: 'ask',
          blocksWriteAndExec: true,
          modeSourceKind: ConfigSourceKind.user,
          narrowedByProject: true,
          effort: 'high',
          effortSourceKind: ConfigSourceKind.projectLocal,
          target: ConfigLayer.user,
          canTargetProject: true,
          banner: const AgentsModesBanner(
            AgentsModesBannerKind.warning,
            message: AgentsSavedOverriddenMessage(
              setting: AgentsModesSetting.mode,
              target: ConfigLayer.user,
              source: ConfigSourceKind.projectLocal,
              value: 'ask',
              when: AgentsApplyWhen.afterRestart,
              blocksWriteAndExec: true,
            ),
          ),
          definitions: AgentsDefinitionsView(
            rows: [
              for (final (i, (status, by)) in [
                (AgentRowStatus.overridden, '~/.codelab/agents/general.md'),
                (AgentRowStatus.duplicate, null),
                (AgentRowStatus.shadowed, null),
                (AgentRowStatus.subagentsOff, null),
                (AgentRowStatus.modelNotConfigured, null),
                (AgentRowStatus.error, null),
              ].indexed)
                AgentsDefinitionRow(
                  name: 'definition-$i',
                  descriptionText: 'Длинное описание определения номер $i',
                  sourcePath: '~/.codelab/agents/definition-$i.md',
                  scope: AgentRowScope.both,
                  rowStatus: status,
                  errorLine: status == AgentRowStatus.error ? 4 : null,
                  overriddenBy: by,
                  tone: AgentsStatusTone.warning,
                ),
            ],
            projectFolderAvailable: true,
            projectFolderExists: true,
          ),
        ),
      );
      addTearDown(cubit.close);
      final language = PageLanguage(const Locale('ru'));
      addTearDown(language.dispose);
      await tester.pumpWidget(
        language.wrap(
          framed(
            BlocProvider<AgentsModesCubit>.value(
              value: cubit,
              child: const AgentsModesPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'страница');
      expect(find.text('Доступен в'), findsOneWidget);
      expect(find.text('Перекрыто проектом'), findsOneWidget);
      expect(find.text('Субагенты отключены'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('agents-modes-mode-bypass')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'диалог bypass');
      expect(find.text('Использовать bypass'), findsOneWidget);
    });

    testWidgets('«Skills & extensions»: таблицы навыков, шаблонов и согласия '
        'на длинных русских подписях — без переполнения', (tester) async {
      final store = FakeAgentConfigStore();
      final session = FakeProviderSettingsSession(store);
      session.onExtensions = (_) async => extensionsView(
        files: [
          contextFile('AGENTS.md', bytes: 4915),
          contextFile('packages/ui/AGENTS.md', bytes: 1331, truncated: true),
        ],
        skills: [
          skillEntry(
            'release-notes',
            root: projectSkillRoot(),
            overrides: [extraSkillRoot()],
            overridesLabel: 'Overrides extra skill',
            overridesScope: ExtensionScope.extra,
            warnings: [diagnostic('a core warning')],
          ),
          skillEntry('deploy-check', modelVisible: false),
          skillEntry('background', userInvocable: false),
          skillEntry('imported', root: extraSkillRoot()),
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
        templates: [templateEntry('/review', description: 'Review a diff')],
      );
      final cubit = SkillsSettingsCubit(
        workspace: FakeWorkspace(),
        defaultProfile: () async => embeddedConnectionProfile,
        open: (access, env) async => session,
        environment: const {'HOME': '/home/u'},
        codelabHome: '/home/u/.codelab',
        projectDirectory: () => '/work/app',
        folderOpener: FakeLocalFolderOpener(),
        logger: RecordingLogger(),
      );
      addTearDown(cubit.close);
      await cubit.reload();
      final language = PageLanguage(const Locale('ru'));
      addTearDown(language.dispose);
      await tester.pumpWidget(
        language.wrap(
          framed(
            BlocProvider<SkillsSettingsCubit>.value(
              value: cubit,
              child: const SkillsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Файлы контекста'), findsWidgets);
      expect(
        find.text('Переопределяет навык из дополнительной папки'),
        findsOneWidget,
      );
      expect(find.text('Только команда'), findsOneWidget);
      expect(find.text('Читать .claude/skills'), findsOneWidget);
    });
  });
}
