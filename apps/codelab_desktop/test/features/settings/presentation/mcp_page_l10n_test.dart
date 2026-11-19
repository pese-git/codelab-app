// Тесты задач 5.1c и 5.2 change `add-desktop-localization`: страница
// «MCP servers» на русском и английском, смена языка на странице (spec
// app-settings «Локализация интерфейса app», сценарии «Проблемы черновика
// MCP-сервера на русском», «Таблица «Agent status» на русском», «Ответ /mcp
// на русском не переводится», «Отклонённый агентом конфиг на русском»,
// «Источник конфигурации на русском», «Страницы настроек II пересобираются
// при смене языка»; design.md D5 «Уточнение итерации 5», D6, D7, D8, D9).
//
// Проверяется то, что видит пользователь. Страница строится на настоящем
// `McpSettingsCubit` с двойниками конфига, секретов и порта MCP, как в
// `mcp_page_test.dart`; язык меняет `PageLanguage` (`FluentApp.locale`),
// потому что Cubit без подписки на `AppStrings` текста не хранит (D5).
//
// Ожидания `en` — прежние строки. Ожидания `ru` — по глоссарию §4
// «Настройки II»: подписи колонок, состояния сервера, «Переподключить»,
// «Только этот проект», «Заменить»/«Оставить», источники строк. Фразы вне
// глоссария (проблемы черновика, баннеры, диалоги, заголовок отклонённого
// конфига) проверяются без выдуманного перевода: английской фразы на экране
// нет, а имена, пути, команды и тексты ядра агента остались как есть (D7,
// D6) под переведённым заголовком.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show AgentMessageChunk, SessionId, TextContent;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/settings/application/mcp_settings_cubit.dart';
import 'package:codelab_desktop/features/settings/presentation/mcp_page.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_embedded/codelab_embedded.dart' show McpServerState;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_mcp_status.dart';
import '../../../support/fake_provider_settings.dart';
import '../../../support/l10n_mix.dart';
import '../../../support/l10n_page_harness.dart';
import '../../../support/recording_logger.dart';

const _authorization = 'codelab/mcp/github/authorization';

final _s1 = SessionId('s1');

final _remote = ConnectionProfile.webSocket(
  id: 'devbox',
  label: 'Devbox',
  uri: Uri.parse('wss://devbox:7420/acp?t=$leakMarker'),
);

final _ownAgent = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: '/opt/bin/codelab-agent',
  args: const ['serve', '--stdio'],
);

Map<String, Object?> _layer(List<Map<String, Object?>> servers) => {
  'mcp': {'servers': servers},
};

Map<String, Object?> _github() => {
  'name': 'github',
  'type': 'http',
  'url': 'https://api.example.test/mcp/',
  'headers': {'Authorization': '\${secret:$_authorization}'},
};

Map<String, Object?> _postgres() => {
  'name': 'postgres',
  'type': 'stdio',
  'command': 'uvx',
  'args': ['postgres-mcp'],
  'env': {'DATABASE_URL': r'${PG_URL}'},
};

Map<String, Object?> _playwright() => {
  'name': 'playwright',
  'type': 'stdio',
  'command': 'npx',
  'args': ['@playwright/mcp'],
};

Map<String, Object?> _docsFs() => {
  'name': 'docs-fs',
  'type': 'stdio',
  'command': 'npx',
  'args': ['docs-mcp'],
};

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String owner, String key) =>
    find.descendant(of: _key(owner), matching: _key(key));

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 2400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;
  late FakeWorkspace workspace;
  late FakeEmbeddedMcpStatusSource source;
  late RecordingLogger logger;
  late PageLanguage language;

  setUp(() {
    store = FakeAgentConfigStore(user: _layer([_github(), _postgres()]));
    session = FakeProviderSettingsSession(
      store,
      secrets: {_authorization: leakMarker},
    );
    workspace = FakeWorkspace();
    source = FakeEmbeddedMcpStatusSource();
    logger = RecordingLogger();
  });

  Future<McpSettingsCubit> openPage(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    language = PageLanguage(locale);
    addTearDown(language.dispose);
    final cubit = McpSettingsCubit(
      workspace: workspace,
      defaultProfile: () async => embeddedConnectionProfile,
      open: (access, env) async => session,
      environment: const {'HOME': '/home/u'},
      codelabHome: '/home/u/.codelab',
      projectDirectory: () => '/work/app',
      statusSource: source,
      logger: logger,
      now: () => DateTime(2026, 11, 8, 14, 2),
    );
    addTearDown(cubit.close);
    await cubit.reload();
    await tester.pumpWidget(
      language.wrap(
        ScaffoldPage(
          content: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 40),
            child: BlocProvider<McpSettingsCubit>.value(
              value: cubit,
              child: const McpPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

  Future<void> expand(WidgetTester tester, String name) async {
    await tester.tap(_key('mcp-row-$name'));
    await settle(tester);
  }

  void connect(ConnectionProfile profile, {SessionId? active}) {
    workspace.emit(
      WorkspaceState(
        connection: const ConnectionView.connected(),
        profile: profile,
        activeSessionId: active,
      ),
    );
  }

  FakeSessionHandle externalSession() {
    final handle = FakeSessionHandle(
      const SessionView(
        revision: 1,
        status: SessionStatusView.idle,
        agentCommands: [
          AgentCommandView(name: 'mcp', description: 'MCP servers'),
        ],
      ),
      id: _s1,
    );
    workspace.handles[_s1] = handle;
    return handle;
  }

  /// Живая таблица встроенного агента: `github` подключён, `postgres` в сбое
  /// с повтором через 24 с и ошибкой, `playwright` выключен.
  void liveStatus() {
    source.ports[_s1] = FakeMcpStatusPort(
      'p1',
      servers: [
        mcpSummary('github', tools: 42),
        mcpSummary(
          'postgres',
          state: McpServerState.failed,
          lastError: 'connection refused',
          retryIn: const Duration(seconds: 24),
        ),
        mcpSummary('playwright', state: McpServerState.disabled),
      ],
    );
    connect(embeddedConnectionProfile, active: _s1);
  }

  /// Сервер `GitHub` с секретным заголовком: имя занято секретом хранилища.
  Future<void> fillSecretHeader(WidgetTester tester) async {
    await tester.tap(_key('mcp-add'));
    await settle(tester);
    await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'GitHub');
    await tester.tap(_in('mcp-new', 'mcp-draft-type-http'));
    await settle(tester);
    await tester.enterText(
      _in('mcp-new', 'mcp-draft-url'),
      'https://x.example.test/mcp/',
    );
    await tester.tap(_in('mcp-new', 'mcp-draft-add-row'));
    await settle(tester);
    await tester.enterText(_in('mcp-new', 'mcp-draft-key-0'), 'Authorization');
    await tester.enterText(_in('mcp-new', 'mcp-draft-value-0'), 'Bearer x');
    await tester.tap(_in('mcp-new', 'mcp-draft-secret-0'));
    await settle(tester);
  }

  group('строки серверов', () {
    testWidgets('en: источники и счётчик прежние', (tester) async {
      store.project = _layer([_playwright()]);
      store.projectLocal = _layer([_docsFs()]);
      await openPage(tester);

      expect(find.text('user'), findsNWidgets(2));
      expect(find.text('this project'), findsOneWidget);
      expect(
        find.text('defined in ${FakeAgentConfigStore.projectPath}'),
        findsOneWidget,
      );
      expect(find.text('4 servers'), findsOneWidget);
    });

    testWidgets('ru: источник строки по ConfigSourceKind, stdio и http как '
        'есть, переключатель «Вкл»', (tester) async {
      store.project = _layer([_playwright()]);
      store.projectLocal = _layer([_docsFs()]);
      await openPage(tester, locale: const Locale('ru'));

      // user ×2 (github, postgres), local, слой 3 — путь файла как есть.
      expect(find.text('пользователь'), findsNWidgets(2));
      expect(find.text('этот проект'), findsOneWidget);
      expect(
        find.text('определён в ${FakeAgentConfigStore.projectPath}'),
        findsOneWidget,
      );
      expectNoEnglish(const ['this project', 'defined in']);
      expect(find.text('http'), findsOneWidget);
      expect(find.text('stdio'), findsNWidgets(3));
      expect(find.text('Вкл'), findsWidgets);
      expect(find.text('On'), findsNothing);
      expect(find.text('Добавить сервер'), findsWidgets);
      expect(find.text('Add server'), findsNothing);
      expect(find.text('4 сервера'), findsOneWidget);
    });

    for (final (count, text) in const [
      (1, '1 сервер'),
      (2, '2 сервера'),
      (5, '5 серверов'),
    ]) {
      testWidgets('ru: число серверов $count — форма ICU plural', (
        tester,
      ) async {
        store.user = _layer([
          for (var i = 0; i < count; i++)
            {'name': 's$i', 'type': 'stdio', 'command': 'npx'},
        ]);
        await openPage(tester, locale: const Locale('ru'));

        expect(find.text(text), findsOneWidget);
      });
    }

    testWidgets('ru: подписи «Вкл» и «Выкл» переключателя не переносятся', (
      tester,
    ) async {
      store.user = _layer([
        _github(),
        {..._postgres(), 'enabled': false},
      ]);
      await openPage(tester, locale: const Locale('ru'));

      for (final word in const ['Вкл', 'Выкл']) {
        final label = find.text(word);
        expect(label, findsOneWidget, reason: word);
        // Одна строка текста 14 pt ниже 26 pt, две — выше.
        expect(
          tester.getSize(label).height,
          lessThan(26),
          reason: 'подпись «$word» разорвана',
        );
      }
    });

    testWidgets('ru: пустой список и карточка нового сервера', (tester) async {
      store.user = _layer(const []);
      await openPage(tester, locale: const Locale('ru'));

      expect(find.text('MCP-серверов пока нет.'), findsOneWidget);
      expect(find.text('No MCP servers yet.'), findsNothing);

      await tester.tap(_key('mcp-add'));
      await settle(tester);
      expect(find.text('Новый сервер'), findsOneWidget);
      expect(find.text('New server'), findsNothing);
    });

    testWidgets('en и ru: строка слоя 3 — «Disable here» / «Отключить здесь»', (
      tester,
    ) async {
      store.project = _layer([_playwright()]);
      store.projectLocal = {};
      await openPage(tester, locale: const Locale('ru'));
      await expand(tester, 'playwright');

      expect(find.text('Отключить здесь'), findsOneWidget);
      expect(find.text('Disable here'), findsNothing);
      // Пояснение — вид, а не английская фраза; имя сервера и путь как есть.
      expectNoEnglish(const ['comes from the project file']);
    });
  });

  group('редактор', () {
    testWidgets('ru: «Заголовки», «Только этот проект», строка без перевода '
        'имён и значений', (tester) async {
      await openPage(tester, locale: const Locale('ru'));
      await expand(tester, 'github');

      expect(
        find.descendant(
          of: _key('mcp-row-github'),
          matching: find.text('Заголовки'),
        ),
        findsOneWidget,
      );
      expect(find.text('Headers'), findsNothing);
      expect(find.text('Только этот проект'), findsOneWidget);
      expect(find.text('This project only'), findsNothing);
      // Имя, адрес и ключ заголовка — данные, не переводятся (D7).
      expect(find.text('Authorization'), findsWidgets);
      expect(
        find.textContaining('https://api.example.test/mcp/'),
        findsWidgets,
      );
    });

    testWidgets('ru: секретный заголовок — «хранится в file», имя секрета '
        'как есть, английского «stored in» нет', (tester) async {
      await openPage(tester, locale: const Locale('ru'));
      await fillSecretHeader(tester);

      expect(
        find.textContaining('хранится в file', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(_authorization, findRichText: true),
        findsWidgets,
      );
      expectNoEnglish(const ['stored in', 'Secret —']);
    });

    testWidgets('ru: вопрос о замене секрета — «Заменить» и «Оставить», имя '
        'секрета как есть, фраз о последствиях по-английски нет', (
      tester,
    ) async {
      await openPage(tester, locale: const Locale('ru'));
      await fillSecretHeader(tester);
      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      expect(_key('mcp-replace-secret'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('mcp-replace-confirm'),
          matching: find.text('Заменить'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('mcp-replace-keep'),
          matching: find.text('Оставить'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('mcp-replace-secret'),
          matching: find.textContaining(_authorization, findRichText: true),
        ),
        findsOneWidget,
      );
      expectNoEnglish(const [
        'A secret with this name is already stored',
        'The new value replaces the secret',
        'A running agent keeps the old value',
        'Replace it',
        'Keep it',
      ]);
      expect(store.applied, isEmpty);
    });

    testWidgets('en: вопрос о замене прежний', (tester) async {
      await openPage(tester);
      await fillSecretHeader(tester);
      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      expect(
        find.text('A secret with this name is already stored'),
        findsOneWidget,
      );
      expect(find.text('Replace it'), findsOneWidget);
      expect(find.text('Keep it'), findsOneWidget);
    });

    testWidgets('ru: проблемы черновика по коду — каждая один раз, английской '
        'фразы и страничного дубля нет (сценарий «Проблемы черновика '
        'MCP-сервера на русском»)', (tester) async {
      await openPage(tester, locale: const Locale('ru'));
      await tester.tap(_key('mcp-add'));
      await settle(tester);
      await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'a b');
      await tester.tap(_in('mcp-new', 'mcp-draft-type-http'));
      await settle(tester);
      await tester.enterText(
        _in('mcp-new', 'mcp-draft-url'),
        'https://u:p@h/mcp',
      );
      for (var i = 0; i < 2; i++) {
        await tester.tap(_in('mcp-new', 'mcp-draft-add-row'));
        await settle(tester);
        await tester.enterText(
          _in('mcp-new', 'mcp-draft-key-$i'),
          'Authorization',
        );
        await tester.enterText(_in('mcp-new', 'mcp-draft-value-$i'), 'v$i');
      }

      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      expectNoEnglish(const [
        'Use a name without spaces',
        'Remove the user name and password from the URL.',
        'Two values are named',
      ]);
      // Три проблемы — три ошибочные заметки формы, каждая один раз:
      // имя, адрес с паролем и совпавшие ключи.
      final errors = find.descendant(
        of: _key('mcp-new'),
        matching: find.byWidgetPredicate(
          (w) => w is CodeLabFormNote && w.tone == CodeLabFormNoteTone.error,
        ),
      );
      expect(errors, findsNWidgets(3));
      // Пароль из адреса и значения заголовков в проблемы не попадают.
      expect(
        find.descendant(of: errors, matching: find.textContaining('u:p@h')),
        findsNothing,
      );
      // Имя ключа сохранено в одной из проблем.
      expect(
        find.descendant(
          of: errors,
          matching: find.textContaining('Authorization'),
        ),
        findsOneWidget,
      );
      expect(store.applied, isEmpty);
    });

    testWidgets('en: проблемы черновика прежние, дубль ключа строит мост', (
      tester,
    ) async {
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);
      await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'a b');
      await tester.enterText(_in('mcp-new', 'mcp-draft-command'), 'npx');
      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      expect(
        find.text('Use a name without spaces, [, ] or ".'),
        findsOneWidget,
      );
    });
  });

  group('удаление и баннеры', () {
    testWidgets('ru: подтверждение удаления с именем сервера и списком '
        'секретов; английского заголовка нет', (tester) async {
      await openPage(tester, locale: const Locale('ru'));
      await expand(tester, 'github');

      await tester.tap(_key('mcp-remove-github'));
      await settle(tester);

      expect(find.text('Remove github?'), findsNothing);
      expect(find.textContaining('github'), findsWidgets);
      expect(find.textContaining(_authorization), findsWidgets);
      expectNoEnglish(const [
        'The server is removed from the config file.',
        'These stored secrets will be deleted',
      ]);
    });

    testWidgets('ru: баннер удаления с оставленным секретом — имя и исход, '
        'без английской фразы', (tester) async {
      store.user = _layer([
        {
          'name': 'docs',
          'type': 'stdio',
          'command': 'docs-mcp',
          'env': {'TOKEN': r'${secret:team/docs-token}'},
        },
      ]);
      session.secrets['team/docs-token'] = 'manual';
      await openPage(tester, locale: const Locale('ru'));
      await expand(tester, 'docs');
      await tester.tap(_key('mcp-remove-docs'));
      await settle(tester);

      await tester.tap(_key('mcp-remove-confirm'));
      await settle(tester);

      expect(_key('mcp-banner'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('mcp-banner'),
          matching: find.textContaining('team/docs-token'),
        ),
        findsOneWidget,
      );
      expectNoEnglish(const [
        'Server docs removed.',
        'is kept: it was not created by this page.',
      ]);
    });

    testWidgets('ru: неудаляемый секрет — команда без изменений, заголовок '
        'на русском', (tester) async {
      session.mcpKeys.deletion = SecretDeletion.failed;
      await openPage(tester, locale: const Locale('ru'));
      await expand(tester, 'github');
      await tester.tap(_key('mcp-remove-github'));
      await settle(tester);

      await tester.tap(_key('mcp-remove-confirm'));
      await settle(tester);

      expect(
        find.descendant(
          of: _key('mcp-banner'),
          matching: find.text('codelab secret delete $_authorization'),
        ),
        findsNothing,
        reason: 'команда стоит внутри фразы, а не отдельной строкой',
      );
      expect(
        find.descendant(
          of: _key('mcp-banner'),
          matching: find.textContaining(
            'codelab secret delete $_authorization',
          ),
        ),
        findsOneWidget,
      );
      expectNoEnglish(const [
        'Server github removed.',
        'could not be deleted. Delete it with:',
      ]);
    });

    testWidgets('en: баннер удаления прежний', (tester) async {
      await openPage(tester);
      await expand(tester, 'github');
      await tester.tap(_key('mcp-remove-github'));
      await settle(tester);
      await tester.tap(_key('mcp-remove-confirm'));
      await settle(tester);

      expect(
        find.descendant(
          of: _key('mcp-banner'),
          matching: find.text('Server github removed.'),
        ),
        findsOneWidget,
      );
    });
  });

  group('InfoBar', () {
    ConfigIssue unset() => const ConfigIssue(
      kind: ConfigIssueKind.value,
      key: 'mcp.servers[postgres].env.DATABASE_URL',
      source: FakeAgentConfigStore.userPath,
      message: 'variable PG_URL is not set',
      event: 'config.variable.unset',
    );

    testWidgets('ru: mcp-rejected — заголовок и фразы по-русски, путь ключа и '
        'текст ядра как есть, кнопка называет сервер', (tester) async {
      store.issues = [unset()];
      await openPage(tester, locale: const Locale('ru'));

      expect(_key('mcp-rejected'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('mcp-rejected'),
          matching: find.textContaining(
            'mcp.servers[postgres].env.DATABASE_URL',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('mcp-rejected'),
          matching: find.textContaining('variable PG_URL is not set'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('mcp-rejected-edit'),
          matching: find.textContaining('postgres'),
        ),
        findsOneWidget,
      );
      expectNoEnglish(const [
        'The agent rejects the current config',
        'Config: invalid',
        'The agent keeps running on the previous config',
        'Edit postgres',
      ]);
    });

    testWidgets('ru: после своей записи заголовок другой, чем при открытии', (
      tester,
    ) async {
      store.onApply = () => store.issues = [unset()];
      await openPage(tester, locale: const Locale('ru'));
      await tester.tap(_key('mcp-add'));
      await settle(tester);
      await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'fresh');
      await tester.enterText(_in('mcp-new', 'mcp-draft-command'), 'npx');
      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      expect(_key('mcp-rejected'), findsOneWidget);
      expectNoEnglish(const [
        'Saved, but the agent rejected the new config',
        'The agent rejects the current config',
      ]);
    });

    testWidgets('ru: mcp-unreadable — заголовок по-русски, текст загрузчика '
        'как есть', (tester) async {
      store.issues = const [
        ConfigIssue(
          kind: ConfigIssueKind.syntax,
          key: '',
          source: FakeAgentConfigStore.userPath,
          message: 'cannot parse the file',
        ),
      ];
      await openPage(tester, locale: const Locale('ru'));

      expect(_key('mcp-unreadable'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('mcp-unreadable'),
          matching: find.textContaining('cannot parse the file'),
        ),
        findsOneWidget,
      );
      expectNoEnglish(const [
        'Cannot read the agent config',
        'CodeLab will not overwrite it',
      ]);
    });

    testWidgets('ru: mcp-read-only удалённого агента — адрес без пути и '
        'токена, команды как есть', (tester) async {
      connect(_remote, active: _s1);
      externalSession();
      await openPage(tester, locale: const Locale('ru'));

      expect(_key('mcp-read-only'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('mcp-read-only'),
          matching: find.textContaining('wss://devbox:7420'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('mcp-read-only'),
          matching: find.textContaining('codelab mcp add'),
        ),
        findsOneWidget,
      );
      expectNoEnglish(const [
        'Read-only: this agent runs on',
        'Change providers and MCP on that host',
      ]);
      expect(find.textContaining(leakMarker), findsNothing);
    });

    testWidgets('ru: mcp-read-only стороннего агента называет агента', (
      tester,
    ) async {
      connect(
        const ConnectionProfile.stdio(
          id: 'other',
          label: 'Other',
          command: 'python',
          args: ['-m', 'other_agent'],
        ),
      );
      await openPage(tester, locale: const Locale('ru'));

      expect(
        find.descendant(
          of: _key('mcp-read-only'),
          matching: find.textContaining('python'),
        ),
        findsOneWidget,
      );
      expectNoEnglish(const ['Provider settings are managed by']);
    });
  });

  group('панель «Agent status»', () {
    testWidgets('en: колонки и состояния прежние', (tester) async {
      liveStatus();
      await openPage(tester);

      for (final head in const ['SERVER', 'STATE', 'TOOLS', 'LAST ERROR']) {
        expect(find.text(head), findsOneWidget, reason: head);
      }
      expect(find.text('connected'), findsOneWidget);
      expect(find.text('failed · retry in 24 s'), findsOneWidget);
      expect(find.text('disabled'), findsOneWidget);
      expect(find.text('Live from the embedded agent · 14:02'), findsOneWidget);
    });

    testWidgets('ru: колонки полностью, состояния по McpServerState, повтор '
        'через 24 с, время HH:mm, прочерк у выключенного (сценарий «Таблица '
        '«Agent status» на русском»)', (tester) async {
      liveStatus();
      await openPage(tester, locale: const Locale('ru'));

      for (final head in const [
        'Сервер',
        'Состояние',
        'Инструменты',
        'Последняя ошибка',
      ]) {
        expect(find.text(head), findsOneWidget, reason: head);
      }
      expect(find.text('подключён'), findsOneWidget);
      expect(find.text('сбой · повтор через 24 с'), findsOneWidget);
      expect(find.text('отключён'), findsOneWidget);
      // Ошибка сервера — как есть (D6, D7).
      expect(find.text('connection refused'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Состояние агента'), findsOneWidget);
      expect(
        find.text('Текущие данные встроенного агента · 14:02'),
        findsOneWidget,
      );
      // У выключенного вместо числа и ошибки — прочерки (две ячейки).
      expect(
        find.descendant(
          of: _key('mcp-status-row-playwright'),
          matching: find.text('—'),
        ),
        findsNWidgets(2),
      );
      expect(
        _key('mcp-status-reconnect-playwright'),
        findsNothing,
        reason: 'выключенному «Переподключить» ничего не даёт',
      );
      expectNoEnglish(const [
        'connected',
        'retry in',
        'Live from the embedded agent',
        'Agent status',
      ]);
      for (final head in const ['SERVER', 'STATE', 'TOOLS', 'LAST ERROR']) {
        expect(find.text(head), findsNothing, reason: head);
      }
    });

    testWidgets('ru: «Переподключить» у сервера и «Переподключить все» — не '
        'то же, что «Переподключиться» подключения', (tester) async {
      liveStatus();
      await openPage(tester, locale: const Locale('ru'));

      expect(
        find.descendant(
          of: _key('mcp-status-reconnect-postgres'),
          matching: find.text('Переподключить'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('mcp-status-reload-all'),
          matching: find.text('Переподключить все'),
        ),
        findsOneWidget,
      );
      expect(find.text('Переподключиться'), findsNothing);
      expect(find.text('Reconnect'), findsNothing);
      expect(find.text('Reload all'), findsNothing);
    });

    testWidgets('ru: без сессии — подсказка по-русски', (tester) async {
      await openPage(tester, locale: const Locale('ru'));

      expect(
        find.text('Откройте сессию, чтобы увидеть состояние'),
        findsOneWidget,
      );
      expect(find.text('Open a session to see live status'), findsNothing);
    });

    testWidgets('ru: ответ /mcp в моноширинном блоке без изменений, кнопки и '
        'подвал по-русски (сценарий «Ответ /mcp на русском не '
        'переводится»)', (tester) async {
      connect(_ownAgent, active: _s1);
      final handle = externalSession();
      handle.onSend = (_) async => completedTurn(_s1, [
        AgentMessageChunk(
          content: const TextContent(
            text: 'MCP servers (1)\ngithub connected 3',
          ),
        ),
      ]);
      await openPage(tester, locale: const Locale('ru'));

      await tester.tap(_key('mcp-status-refresh'));
      await settle(tester);

      expect(handle.sent, ['/mcp list']);
      expect(
        find.descendant(
          of: _key('mcp-status-text'),
          matching: find.text('MCP servers (1)\ngithub connected 3'),
        ),
        findsOneWidget,
      );
      expect(find.text('Обновить'), findsOneWidget);
      expect(find.text('Переподключить все'), findsOneWidget);
      expect(find.text('Refresh'), findsNothing);
      expect(find.text('Reload all'), findsNothing);
      expectNoEnglish(const ['From the embedded agent. For a stdio']);
    });

    testWidgets('ru: сбой /mcp list — переведённая строка над прежним '
        'текстом, команда как есть', (tester) async {
      connect(_ownAgent, active: _s1);
      final handle = externalSession();
      handle.onSend = (_) async => completedTurn(_s1, [
        AgentMessageChunk(content: const TextContent(text: 'old reply')),
      ]);
      await openPage(tester, locale: const Locale('ru'));
      await tester.tap(_key('mcp-status-refresh'));
      await settle(tester);
      handle.onSend = (_) async =>
          PromptFailed(_s1, StateError('boom $leakMarker'));

      await tester.tap(_key('mcp-status-refresh'));
      await settle(tester);

      expect(
        find.descendant(
          of: _key('mcp-status-notice'),
          matching: find.textContaining('/mcp list'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('/mcp list did not complete. Try Refresh again.'),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _key('mcp-status-text'),
          matching: find.text('old reply'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('boom'), findsNothing);
    });
  });

  group('смена языка (D5, D9)', () {
    testWidgets('рабочее состояние с живой таблицей: en → ru → en, '
        'expectNoStaleLanguage', (tester) async {
      store.project = _layer([_playwright()]);
      store.projectLocal = _layer([_docsFs()]);
      liveStatus();
      await openPage(tester);

      await language.select(tester, const Locale('ru'));
      await expectNoStaleLanguage(tester, from: en, to: ru);
      expect(find.text('пользователь'), findsWidgets);
      expect(find.text('сбой · повтор через 24 с'), findsOneWidget);

      await language.select(tester, const Locale('en'));
      await expectNoStaleLanguage(tester, from: ru, to: en);
      expect(find.text('failed · retry in 24 s'), findsOneWidget);
    });

    testWidgets('с баннером удаления, InfoBar отклонённого конфига и '
        'ошибкой записи: баннеры пересобраны, имена не изменились', (
      tester,
    ) async {
      store.issues = const [
        ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'mcp.servers[postgres].env.DATABASE_URL',
          source: FakeAgentConfigStore.userPath,
          message: 'variable PG_URL is not set',
          event: 'config.variable.unset',
        ),
      ];
      session.mcpKeys.deletion = SecretDeletion.failed;
      await openPage(tester);
      await expand(tester, 'github');
      await tester.tap(_key('mcp-remove-github'));
      await settle(tester);
      await tester.tap(_key('mcp-remove-confirm'));
      await settle(tester);
      expect(_key('mcp-banner'), findsOneWidget);
      expect(_key('mcp-rejected'), findsOneWidget);

      await language.select(tester, const Locale('ru'));
      await expectNoStaleLanguage(tester, from: en, to: ru);
      expectNoEnglish(const [
        'Server github removed.',
        'The agent rejects the current config',
      ]);
      expect(
        find.textContaining('codelab secret delete $_authorization'),
        findsOneWidget,
      );
      expect(find.textContaining('postgres'), findsWidgets);

      await language.select(tester, const Locale('en'));
      await expectNoStaleLanguage(tester, from: ru, to: en);
      expect(find.text('Server github removed.'), findsOneWidget);
    });

    testWidgets('открытый редактор: введённые значения черновика не '
        'сбрасываются при смене языка', (tester) async {
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);
      await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'fresh');
      await tester.enterText(_in('mcp-new', 'mcp-draft-command'), 'npx');

      await language.select(tester, const Locale('ru'));

      String text(String key) => tester
          .widget<EditableText>(
            find.descendant(
              of: _in('mcp-new', key),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;
      expect(text('mcp-draft-name'), 'fresh');
      expect(text('mcp-draft-command'), 'npx');
      await expectNoStaleLanguage(tester, from: en, to: ru);
    });

    testWidgets('read-only и unreadable: пересобираются при смене языка', (
      tester,
    ) async {
      connect(_remote, active: _s1);
      externalSession();
      await openPage(tester);
      expect(
        find.textContaining('Read-only: this agent runs on wss://devbox:7420'),
        findsOneWidget,
      );

      await language.select(tester, const Locale('ru'));

      expectNoEnglish(const ['Read-only: this agent runs on']);
      expect(
        find.descendant(
          of: _key('mcp-read-only'),
          matching: find.textContaining('wss://devbox:7420'),
        ),
        findsOneWidget,
      );
      await expectNoStaleLanguage(tester, from: en, to: ru);
    });
  });
}
