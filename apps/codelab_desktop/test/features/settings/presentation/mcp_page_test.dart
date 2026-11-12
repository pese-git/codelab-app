// Страница «MCP servers» (задача 5.5 change `add-provider-setup-ui`; spec
// app-settings «Страница «MCP servers»», «Панель «Agent status» страницы MCP
// servers», «Доступ к настройкам агента на страницах Providers и MCP
// servers»; design.md D11, D12, D24, решения Q23, Q25–Q27; артборд
// `docs/design/claude-design/Mcp.dc.html`).
//
// Проверяется поведение (что есть на странице, что доступно и что вызвано),
// а не пиксели. Страница строится на настоящем `McpSettingsCubit` с
// двойниками конфига, секретов и порта MCP; порядок записи и правила
// проверяют тесты Cubit-а и моста. Так тест не зависит от composition root
// (его проверяет `settings_shell_test.dart`).
//
// Красный тест: страницы, Cubit-а и порта ещё нет (задача 5.10). Ожидаемый
// публичный API: `McpPage` (читает `McpSettingsCubit` из `BlocProvider`),
// `buildMcpPage`, `McpPageHost`. Ключи — design.md D11 «Ключи»; ключ стоит
// на самом виджете `ToggleSwitch`, `Checkbox`, `RadioButton`, `CodeLabButton`
// или поле ввода (как на страницах Connection и Providers), поля редактора —
// `mcp-draft-*` внутри `mcp-row-<name>` или `mcp-new`.

import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show AgentMessageChunk, SessionId, TextContent;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/settings/application/mcp_settings_cubit.dart';
import 'package:codelab_desktop/features/settings/presentation/mcp_page.dart';
import 'package:codelab_embedded/codelab_embedded.dart' show McpServerState;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_mcp_status.dart';
import '../../../support/fake_provider_settings.dart';
import '../../../support/real_config_session.dart';
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

Finder _key(String key) => find.byKey(ValueKey(key));

/// Элемент [key] внутри строки или карточки [owner] (`mcp-row-<name>`,
/// `mcp-new`): ключи полей не содержат имени сервера (D11).
Finder _in(String owner, String key) =>
    find.descendant(of: _key(owner), matching: _key(key));

String _editable(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .controller
    .text;

void main() {
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
  var projectDir = '/work/app';

  setUp(() {
    store = FakeAgentConfigStore(user: _layer([_github(), _postgres()]));
    session = FakeProviderSettingsSession(
      store,
      secrets: {_authorization: leakMarker},
    );
    workspace = FakeWorkspace();
    source = FakeEmbeddedMcpStatusSource();
    logger = RecordingLogger();
    projectDir = '/work/app';
  });

  Future<McpSettingsCubit> openPage(
    WidgetTester tester, {
    ProviderSettingsSession? realSession,
  }) async {
    final cubit = McpSettingsCubit(
      workspace: workspace,
      defaultProfile: () async => embeddedConnectionProfile,
      open: (access, env) async => realSession ?? session,
      environment: const {'HOME': '/home/u'},
      codelabHome: '/home/u/.codelab',
      projectDirectory: () => projectDir,
      statusSource: source,
      logger: logger,
      now: () => DateTime(2026, 11, 8, 14, 2),
    );
    addTearDown(cubit.close);
    // Настоящий файловый ввод-вывод не идёт в fake-async зоне теста.
    if (realSession == null) {
      await cubit.reload();
    } else {
      await tester.runAsync(cubit.reload);
    }
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
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

  Future<void> expand(WidgetTester tester, String name) async {
    await tester.tap(_key('mcp-row-$name'));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

  void connect(ConnectionProfile profile, {SessionId? active}) {
    workspace.emit(
      WorkspaceState(
        connection: const ConnectionView.connected(),
        profile: profile,
        activeSessionId: active,
      ),
    );
  }

  FakeSessionHandle externalSession({
    SessionStatusView sessionStatus = SessionStatusView.idle,
  }) {
    final handle = FakeSessionHandle(
      SessionView(
        revision: 1,
        status: sessionStatus,
        agentCommands: const [
          AgentCommandView(name: 'mcp', description: 'MCP servers'),
        ],
      ),
      id: _s1,
    );
    workspace.handles[_s1] = handle;
    return handle;
  }

  group('layout (artboard Mcp, D11)', () {
    testWidgets('has the header, the count line, a row per server with the '
        'D11 keys and the tags', (tester) async {
      store.project = _layer([_playwright()]);
      store.projectLocal = {};
      await openPage(tester);

      expect(_key('settings-mcp'), findsOneWidget);
      expect(find.text('MCP servers'), findsWidgets);
      expect(_key('mcp-add'), findsOneWidget);
      // Два блока артборда: слева число серверов, справа индикатор.
      expect(find.text('3 servers'), findsOneWidget);
      expect(
        find.text('Composition from the config · agent status below'),
        findsOneWidget,
      );
      for (final part in const ['row', 'toggle']) {
        for (final name in const ['github', 'postgres', 'playwright']) {
          expect(
            _key('mcp-$part-$name'),
            findsOneWidget,
            reason: '$part-$name',
          );
        }
      }
      expect(find.text('http'), findsOneWidget);
      expect(find.text('stdio'), findsNWidgets(2));
      expect(find.text('https://api.example.test/mcp/'), findsOneWidget);
      expect(find.textContaining('uvx postgres-mcp'), findsOneWidget);
      expect(
        find.text('defined in ${FakeAgentConfigStore.projectPath}'),
        findsOneWidget,
      );
      expect(find.textContaining(leakMarker), findsNothing);
    });

    testWidgets('the toggle writes the whole element with the new enabled '
        'and shows it off', (tester) async {
      await openPage(tester);
      expect(
        tester.widget<ToggleSwitch>(_key('mcp-toggle-github')).checked,
        isTrue,
      );

      await tester.tap(_key('mcp-toggle-github'));
      await settle(tester);

      final element =
          (store.applied.single.edits.single as UpsertMcpServer).server;
      expect(element['enabled'], false);
      expect(element['url'], 'https://api.example.test/mcp/');
      expect(
        tester.widget<ToggleSwitch>(_key('mcp-toggle-github')).checked,
        isFalse,
      );
    });

    testWidgets('the footer says where the table comes from; without a '
        'session the panel asks to open one (Q23)', (tester) async {
      await openPage(tester);

      expect(_key('mcp-status'), findsOneWidget);
      expect(find.text('Agent status'), findsOneWidget);
      expect(_key('mcp-status-unavailable'), findsOneWidget);
      expect(find.text('Open a session to see live status'), findsOneWidget);
      expect(
        find.text(
          'From the embedded agent. For a stdio or remote agent this panel '
          'shows the reply of /mcp list as text.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an empty list shows the line and Add server, which opens '
        'the card (Q25 (2))', (tester) async {
      store.user = {};
      await openPage(tester);

      expect(_key('mcp-empty'), findsOneWidget);
      expect(find.text('No MCP servers yet.'), findsOneWidget);

      await tester.tap(_key('mcp-empty-add'));
      await settle(tester);

      expect(_key('mcp-new'), findsOneWidget);
    });
  });

  group('the editor of an existing server (D11, Q27)', () {
    testWidgets('an http server: type, URL, header rows, name and Save to '
        'are read-only, a stored secret says stored', (tester) async {
      await openPage(tester);

      await expand(tester, 'github');

      expect(_in('mcp-row-github', 'mcp-draft-url'), findsOneWidget);
      expect(_in('mcp-row-github', 'mcp-draft-command'), findsNothing);
      expect(
        _editable(tester, _in('mcp-row-github', 'mcp-draft-name')),
        'github',
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: _in('mcp-row-github', 'mcp-draft-name'),
                matching: find.byType(EditableText),
              ),
            )
            .readOnly,
        isTrue,
      );
      expect(
        _editable(tester, _in('mcp-row-github', 'mcp-draft-url')),
        'https://api.example.test/mcp/',
      );
      expect(
        _editable(tester, _in('mcp-row-github', 'mcp-draft-key-0')),
        'Authorization',
      );
      expect(
        find.descendant(
          of: _in('mcp-row-github', 'mcp-draft-value-0'),
          matching: find.text('stored'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Checkbox>(_in('mcp-row-github', 'mcp-draft-secret-0'))
            .checked,
        isTrue,
      );
      expect(
        find.textContaining(
          'Secret — stored in file as $_authorization',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // Перенос между слоями — «Remove» и «Add server»: переключатель
      // только для чтения (Q27).
      expect(
        tester
            .widget<RadioButton<dynamic>>(
              _in('mcp-row-github', 'mcp-draft-target-user'),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<RadioButton<dynamic>>(
              _in('mcp-row-github', 'mcp-draft-target-local'),
            )
            .enabled,
        isFalse,
      );
      for (final part in const ['save', 'reconnect', 'remove']) {
        expect(_in('mcp-row-github', 'mcp-$part-github'), findsOneWidget);
      }
    });

    testWidgets('a stdio server shows the command and a plain env value', (
      tester,
    ) async {
      await openPage(tester);

      await expand(tester, 'postgres');

      expect(_in('mcp-row-postgres', 'mcp-draft-url'), findsNothing);
      expect(
        _editable(tester, _in('mcp-row-postgres', 'mcp-draft-command')),
        'uvx',
      );
      expect(
        _editable(tester, _in('mcp-row-postgres', 'mcp-draft-key-0')),
        'DATABASE_URL',
      );
      expect(
        _editable(tester, _in('mcp-row-postgres', 'mcp-draft-value-0')),
        r'${PG_URL}',
      );
      expect(
        tester
            .widget<Checkbox>(_in('mcp-row-postgres', 'mcp-draft-secret-0'))
            .checked,
        isFalse,
      );
    });

    testWidgets('arguments are one per line as they are: an argument with a '
        'space survives an edit of another field (decision 2026-11-08)', (
      tester,
    ) async {
      store.user = _layer([
        {
          'name': 'docs',
          'type': 'stdio',
          'command': 'docs-mcp',
          'args': ['--root', '~/My Docs'],
        },
      ]);
      await openPage(tester);
      await expand(tester, 'docs');

      expect(find.text('One argument per line.'), findsOneWidget);
      expect(
        _editable(tester, _in('mcp-row-docs', 'mcp-draft-args')),
        '--root\n~/My Docs',
      );

      await tester.enterText(
        _in('mcp-row-docs', 'mcp-draft-command'),
        'docs-mcp2',
      );
      await tester.tap(_key('mcp-save-docs'));
      await settle(tester);

      final element =
          (store.applied.single.edits.single as UpsertMcpServer).server;
      expect(element['command'], 'docs-mcp2');
      expect(element['args'], ['--root', '~/My Docs']);
    });

    testWidgets('an edited arguments field is split by lines only; empty '
        'lines are dropped', (tester) async {
      store.user = _layer([
        {'name': 'docs', 'type': 'stdio', 'command': 'docs-mcp'},
      ]);
      await openPage(tester);
      await expand(tester, 'docs');

      await tester.enterText(
        _in('mcp-row-docs', 'mcp-draft-args'),
        '--root\n~/My Docs\n\nextra  ',
      );
      await tester.tap(_key('mcp-save-docs'));
      await settle(tester);

      final element =
          (store.applied.single.edits.single as UpsertMcpServer).server;
      expect(element['args'], ['--root', '~/My Docs', 'extra  ']);
    });

    testWidgets('values the row masks are not shown in the editor and Save '
        'without a touch keeps them as they are (review 5b, MEDIUM-1)', (
      tester,
    ) async {
      final stdio = {
        'name': 'tok',
        'type': 'stdio',
        'command': 'tok-mcp',
        'args': ['--token', leakMarker],
        'env': {'API_TOKEN': leakMarker},
      };
      final http = {
        'name': 'web',
        'type': 'http',
        'url': 'https://api.example.test/mcp/?token=$leakMarker',
        'headers': {'X-Workspace': leakMarker},
      };
      store.user = _layer([stdio, http]);
      await openPage(tester);
      await expand(tester, 'tok');
      await expand(tester, 'web');

      expect(find.textContaining(leakMarker), findsNothing);
      expect(find.textContaining(leakMarker, findRichText: true), findsNothing);

      await tester.tap(_key('mcp-save-tok'));
      await settle(tester);
      await tester.tap(_key('mcp-save-web'));
      await settle(tester);

      final saved = [
        for (final apply in store.applied)
          (apply.edits.single as UpsertMcpServer).server,
      ];
      expect(saved[0]['args'], ['--token', leakMarker]);
      expect(saved[0]['env'], {'API_TOKEN': leakMarker});
      expect(
        saved[1]['url'],
        'https://api.example.test/mcp/?token=$leakMarker',
      );
      expect(saved[1]['headers'], {'X-Workspace': leakMarker});
    });

    testWidgets('a masked command is hidden and Save without a touch keeps '
        'it byte for byte; hidden values of the other table stay hidden '
        'after a switch of the type (second review 5b)', (tester) async {
      final command = ' tok-mcp --key=$leakMarker ';
      store.user = _layer([
        {
          'name': 'tok',
          'type': 'stdio',
          'command': command,
          'env': {'API_TOKEN': leakMarker},
          'headers': {'X-Workspace': leakMarker},
        },
      ]);
      await openPage(tester);
      await expand(tester, 'tok');

      expect(find.textContaining(leakMarker), findsNothing);
      await tester.tap(_in('mcp-row-tok', 'mcp-draft-type-http'));
      await settle(tester);
      expect(find.textContaining(leakMarker), findsNothing);
      await tester.tap(_in('mcp-row-tok', 'mcp-draft-type-stdio'));
      await settle(tester);

      await tester.tap(_key('mcp-save-tok'));
      await settle(tester);

      final element =
          (store.applied.single.edits.single as UpsertMcpServer).server;
      expect(element['command'], command);
      expect(element['env'], {'API_TOKEN': leakMarker});
    });

    testWidgets('a key with spaces around it is a problem of the bridge '
        'draft, shown under the form', (tester) async {
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);
      await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'fresh');
      await tester.enterText(_in('mcp-new', 'mcp-draft-command'), 'npx');
      await tester.tap(_in('mcp-new', 'mcp-draft-add-row'));
      await settle(tester);
      await tester.enterText(_in('mcp-new', 'mcp-draft-key-0'), 'TOKEN ');

      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      expect(
        find.descendant(
          of: _key('mcp-new'),
          matching: find.text('Remove spaces around the name TOKEN .'),
        ),
        findsOneWidget,
      );
      expect(store.applied, isEmpty);
    });

    testWidgets('two rows without a name are the bridge problem, not a '
        'duplicate', (tester) async {
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);
      await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'fresh');
      await tester.enterText(_in('mcp-new', 'mcp-draft-command'), 'npx');
      for (var i = 0; i < 2; i++) {
        await tester.tap(_in('mcp-new', 'mcp-draft-add-row'));
        await settle(tester);
      }

      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      expect(
        find.descendant(
          of: _key('mcp-new'),
          matching: find.text('Enter a name for every value.'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Two values are named'), findsNothing);
      expect(store.applied, isEmpty);
    });

    testWidgets('leftover headers and url of a stdio server stay hidden after '
        'a switch to http and Save keeps them raw (L-c)', (tester) async {
      final url = 'https://api.example.test/mcp/?token=$leakMarker';
      store.user = _layer([
        {
          'name': 'tok',
          'type': 'stdio',
          'command': 'tok-mcp',
          'url': url,
          'headers': {'X-Workspace': leakMarker},
        },
      ]);
      await openPage(tester);
      await expand(tester, 'tok');

      await tester.tap(_in('mcp-row-tok', 'mcp-draft-type-http'));
      await settle(tester);

      expect(find.textContaining(leakMarker), findsNothing);
      expect(find.textContaining(leakMarker, findRichText: true), findsNothing);

      await tester.tap(_key('mcp-save-tok'));
      await settle(tester);

      final element =
          (store.applied.single.edits.single as UpsertMcpServer).server;
      expect(element['url'], url);
      expect(element['headers'], {'X-Workspace': leakMarker});
    });

    testWidgets('the name field of a header row is wide enough for '
        'Authorization and DATABASE_URL at the smoke window width; a narrow '
        'window does not overflow (smoke 5b)', (tester) async {
      final view = TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .single;
      view.physicalSize = const Size(1176, 1400);
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);
      await tester.tap(_in('mcp-new', 'mcp-draft-add-row'));
      await settle(tester);
      await tester.enterText(
        _in('mcp-new', 'mcp-draft-key-0'),
        'Authorization',
      );
      await settle(tester);

      final field = _in('mcp-new', 'mcp-draft-key-0');
      final value = _in('mcp-new', 'mcp-draft-value-0');
      // Моноширинный текст 12.5 px: 13 символов ≈ 100 px плюс поля поля ввода.
      expect(tester.getSize(field).width, greaterThanOrEqualTo(160));
      // Как на артборде, ключ уже значения, но не крошечный.
      expect(
        tester.getSize(field).width,
        lessThan(tester.getSize(value).width),
      );
      expect(tester.takeException(), isNull);

      view.physicalSize = const Size(640, 1400);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('typing into a masked field replaces the value as a whole', (
      tester,
    ) async {
      store.user = _layer([
        {
          'name': 'web',
          'type': 'http',
          'url': 'https://api.example.test/mcp/',
          'headers': {'X-Workspace': leakMarker},
        },
      ]);
      await openPage(tester);
      await expand(tester, 'web');

      await tester.enterText(_in('mcp-row-web', 'mcp-draft-value-0'), 'new');
      await tester.tap(_key('mcp-save-web'));
      await settle(tester);

      final element =
          (store.applied.single.edits.single as UpsertMcpServer).server;
      expect(element['headers'], {'X-Workspace': 'new'});
    });

    testWidgets('two rows with the same name are a form problem, not '
        'collapsed silently', (tester) async {
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);
      await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'fresh');
      await tester.tap(_in('mcp-new', 'mcp-draft-type-http'));
      await settle(tester);
      await tester.enterText(
        _in('mcp-new', 'mcp-draft-url'),
        'https://x.example.test/mcp/',
      );
      for (var i = 0; i < 2; i++) {
        await tester.tap(_in('mcp-new', 'mcp-draft-add-row'));
        await settle(tester);
        await tester.enterText(_in('mcp-new', 'mcp-draft-key-$i'), 'X-Team');
        await tester.enterText(_in('mcp-new', 'mcp-draft-value-$i'), 'v$i');
      }

      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      expect(
        find.descendant(
          of: _key('mcp-new'),
          matching: find.text('Two values are named X-Team.'),
        ),
        findsOneWidget,
      );
      expect(store.applied, isEmpty);
    });

    testWidgets('Save writes the edited element of its own layer', (
      tester,
    ) async {
      await openPage(tester);
      await expand(tester, 'github');

      await tester.enterText(
        _in('mcp-row-github', 'mcp-draft-url'),
        'https://new.example.test/mcp/',
      );
      await tester.tap(_key('mcp-save-github'));
      await settle(tester);

      final apply = store.applied.single;
      expect(apply.base.path, FakeAgentConfigStore.userPath);
      expect(
        (apply.edits.single as UpsertMcpServer).server['url'],
        'https://new.example.test/mcp/',
      );
      expect(session.mcpKeys.journal, isEmpty);
    });

    testWidgets('a project-layer server shows the note instead of the '
        'editor, with Disable here and no Remove', (tester) async {
      store.project = _layer([_playwright()]);
      store.projectLocal = {};
      await openPage(tester);
      expect(_key('mcp-disable-here-playwright'), findsOneWidget);
      expect(_key('mcp-enable-here-playwright'), findsNothing);
      expect(
        tester.widget<ToggleSwitch>(_key('mcp-toggle-playwright')).onChanged,
        isNull,
      );

      await expand(tester, 'playwright');

      expect(
        find.text(
          'playwright comes from the project file: it can\'t be edited or '
          'removed here; "Disable here" writes enabled: false to '
          '.codelab/config.local.yaml.',
        ),
        findsOneWidget,
      );
      expect(_key('mcp-note-playwright'), findsOneWidget);
      expect(_in('mcp-row-playwright', 'mcp-draft-name'), findsNothing);
      expect(_key('mcp-save-playwright'), findsNothing);
      expect(_key('mcp-remove-playwright'), findsNothing);
    });

    testWidgets('Disable here and Enable here: the row switches and the '
        'explanation is shown', (tester) async {
      store.project = _layer([_playwright()]);
      store.projectLocal = {};
      await openPage(tester);

      await tester.tap(_key('mcp-disable-here-playwright'));
      await settle(tester);

      expect(
        store.applied.single.base.path,
        FakeAgentConfigStore.projectLocalPath,
      );
      expect(_key('mcp-disable-here-playwright'), findsNothing);
      expect(_key('mcp-enable-here-playwright'), findsOneWidget);
      await expand(tester, 'playwright');
      expect(
        find.text(
          'playwright is disabled in .codelab/config.local.yaml. '
          '"Enable here" removes this override.',
        ),
        findsOneWidget,
      );

      await tester.tap(_key('mcp-enable-here-playwright'));
      await settle(tester);

      expect(
        store.applied.last.edits.single,
        const RemoveMcpServer('playwright'),
      );
      expect(_key('mcp-disable-here-playwright'), findsOneWidget);
      expect(_key('mcp-enable-here-playwright'), findsNothing);
    });
  });

  group('the New server card (Q25 (1))', () {
    testWidgets('opens at the top with an empty stdio editor, Save and '
        'Cancel, without Reconnect and Remove; a second Add server adds '
        'nothing', (tester) async {
      await openPage(tester);

      await tester.tap(_key('mcp-add'));
      await settle(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);

      expect(_key('mcp-new'), findsOneWidget);
      expect(find.text('New server'), findsOneWidget);
      expect(_editable(tester, _in('mcp-new', 'mcp-draft-name')), isEmpty);
      expect(_in('mcp-new', 'mcp-draft-command'), findsOneWidget);
      expect(_in('mcp-new', 'mcp-draft-url'), findsNothing);
      expect(_key('mcp-new-save'), findsOneWidget);
      expect(_key('mcp-new-cancel'), findsOneWidget);
      expect(
        find.descendant(of: _key('mcp-new'), matching: find.text('Remove')),
        findsNothing,
      );
      expect(
        find.descendant(of: _key('mcp-new'), matching: find.text('Reconnect')),
        findsNothing,
      );
      // Карточка стоит выше первой строки списка.
      expect(
        tester.getTopLeft(_key('mcp-new')).dy,
        lessThan(tester.getTopLeft(_key('mcp-row-github')).dy),
      );
    });

    testWidgets('the type radios switch the fields', (tester) async {
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);

      await tester.tap(_in('mcp-new', 'mcp-draft-type-http'));
      await settle(tester);

      expect(_in('mcp-new', 'mcp-draft-url'), findsOneWidget);
      expect(_in('mcp-new', 'mcp-draft-command'), findsNothing);
    });

    testWidgets('Save writes a stdio server to the user file and the card '
        'goes away', (tester) async {
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);

      await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'fresh');
      await tester.enterText(_in('mcp-new', 'mcp-draft-command'), 'npx');
      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      final apply = store.applied.single;
      expect(apply.base.path, FakeAgentConfigStore.userPath);
      final element = (apply.edits.single as UpsertMcpServer).server;
      expect(element['name'], 'fresh');
      expect(element['command'], 'npx');
      expect(_key('mcp-new'), findsNothing);
      expect(_key('mcp-row-fresh'), findsOneWidget);
      expect(_key('mcp-banner'), findsOneWidget);
    });

    testWidgets('"This project only" writes to the local project file', (
      tester,
    ) async {
      store.projectLocal = {};
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);

      await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'fresh');
      await tester.enterText(_in('mcp-new', 'mcp-draft-command'), 'npx');
      await tester.tap(_in('mcp-new', 'mcp-draft-target-local'));
      await settle(tester);
      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      expect(
        store.applied.single.base.path,
        FakeAgentConfigStore.projectLocalPath,
      );
    });

    testWidgets('"This project only" is inactive without a project folder', (
      tester,
    ) async {
      projectDir = '';
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);

      expect(
        tester
            .widget<RadioButton<dynamic>>(
              _in('mcp-new', 'mcp-draft-target-local'),
            )
            .enabled,
        isFalse,
      );
    });

    testWidgets('Cancel removes the card without a write (scenario "new '
        'server and cancel")', (tester) async {
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);
      await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'fresh');

      await tester.tap(_key('mcp-new-cancel'));
      await settle(tester);

      expect(_key('mcp-new'), findsNothing);
      expect(store.applied, isEmpty);
    });

    testWidgets('a taken name is a problem in the card and nothing is '
        'written', (tester) async {
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);

      await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'github');
      await tester.enterText(_in('mcp-new', 'mcp-draft-command'), 'npx');
      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      expect(
        find.descendant(
          of: _key('mcp-new'),
          matching: find.text('A server with this name already exists.'),
        ),
        findsOneWidget,
      );
      expect(_key('mcp-new'), findsOneWidget);
      expect(store.applied, isEmpty);
    });

    testWidgets('a secret header names its secret and an existing one asks '
        '"Replace it" with the name before anything is written', (
      tester,
    ) async {
      await openPage(tester);
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
      await tester.enterText(
        _in('mcp-new', 'mcp-draft-key-0'),
        'Authorization',
      );
      await tester.enterText(_in('mcp-new', 'mcp-draft-value-0'), 'Bearer x');
      await tester.tap(_in('mcp-new', 'mcp-draft-secret-0'));
      await settle(tester);

      expect(
        find.textContaining(
          'Secret — stored in file as $_authorization',
          findRichText: true,
        ),
        findsOneWidget,
      );

      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      expect(_key('mcp-replace-secret'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('mcp-replace-secret'),
          matching: find.textContaining(_authorization, findRichText: true),
        ),
        findsOneWidget,
      );
      expect(store.applied, isEmpty);
      expect(session.secrets[_authorization], leakMarker);

      await tester.tap(_key('mcp-replace-confirm'));
      await settle(tester);

      expect(store.applied, hasLength(1));
      expect(session.secrets[_authorization], 'Bearer x');
      expect(_key('mcp-replace-secret'), findsNothing);
    });

    testWidgets('the replace question states the consequences and "Keep it" '
        'closes it without a write', (tester) async {
      await openPage(tester);
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
      await tester.enterText(
        _in('mcp-new', 'mcp-draft-key-0'),
        'Authorization',
      );
      await tester.enterText(_in('mcp-new', 'mcp-draft-value-0'), 'Bearer x');
      await tester.tap(_in('mcp-new', 'mcp-draft-secret-0'));
      await settle(tester);
      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      for (final text in const [
        'The new value replaces the secret for every server that refers to it.',
        'A running agent keeps the old value until the server reconnects.',
      ]) {
        expect(
          find.descendant(
            of: _key('mcp-replace-secret'),
            matching: find.text(text),
          ),
          findsOneWidget,
          reason: text,
        );
      }

      await tester.tap(_key('mcp-replace-keep'));
      await settle(tester);

      expect(_key('mcp-replace-secret'), findsNothing);
      expect(store.applied, isEmpty);
      expect(session.secrets[_authorization], leakMarker);
    });

    testWidgets('a read-only backend makes the Secret box inactive and '
        'says why', (tester) async {
      store.backend = const SecretBackendInfo(
        id: 'env',
        writable: false,
        unavailableReason: 'OS key stores are not available yet',
      );
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);
      await tester.tap(_in('mcp-new', 'mcp-draft-type-http'));
      await settle(tester);
      await tester.tap(_in('mcp-new', 'mcp-draft-add-row'));
      await settle(tester);

      expect(
        tester.widget<Checkbox>(_in('mcp-new', 'mcp-draft-secret-0')).onChanged,
        isNull,
      );
      expect(
        find.textContaining(
          'OS key stores are not available yet',
          findRichText: true,
        ),
        findsWidgets,
      );
    });
  });

  group('Remove (Q22, Q25 (3), (4))', () {
    testWidgets('asks first, names the page secrets and writes nothing on '
        'Cancel (scenario "removal confirmation")', (tester) async {
      await openPage(tester);
      await expand(tester, 'github');

      await tester.tap(_key('mcp-remove-github'));
      await settle(tester);

      expect(find.text('Remove github?'), findsOneWidget);
      expect(
        find.text(
          'These stored secrets will be deleted if nothing else uses them:',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('mcp-remove-secrets'),
          matching: find.textContaining(_authorization, findRichText: true),
        ),
        findsOneWidget,
      );

      await tester.tap(_key('mcp-remove-cancel'));
      await settle(tester);

      expect(find.text('Remove github?'), findsNothing);
      expect(store.applied, isEmpty);
      expect(session.mcpKeys.journal, isEmpty);
      expect(session.secrets, contains(_authorization));
      expect(_key('mcp-row-github'), findsOneWidget);
    });

    testWidgets('a server without page secrets has no secret list', (
      tester,
    ) async {
      await openPage(tester);
      await expand(tester, 'postgres');

      await tester.tap(_key('mcp-remove-postgres'));
      await settle(tester);

      expect(find.text('Remove postgres?'), findsOneWidget);
      expect(_key('mcp-remove-secrets'), findsNothing);
      expect(_key('mcp-remove-confirm'), findsOneWidget);
    });

    testWidgets('Remove deletes the server and its secret and shows the '
        'banner', (tester) async {
      await openPage(tester);
      await expand(tester, 'github');
      await tester.tap(_key('mcp-remove-github'));
      await settle(tester);

      await tester.tap(_key('mcp-remove-confirm'));
      await settle(tester);

      expect(
        store.applied.single.edits.single,
        const RemoveMcpServer('github'),
      );
      expect(session.secrets, isNot(contains(_authorization)));
      expect(_key('mcp-row-github'), findsNothing);
      expect(
        find.descendant(
          of: _key('mcp-banner'),
          matching: find.text('Server github removed.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the banner names a kept manual secret', (tester) async {
      store.user = _layer([
        {
          'name': 'docs',
          'type': 'stdio',
          'command': 'docs-mcp',
          'env': {'TOKEN': r'${secret:team/docs-token}'},
        },
      ]);
      session.secrets['team/docs-token'] = 'manual';
      await openPage(tester);
      await expand(tester, 'docs');
      await tester.tap(_key('mcp-remove-docs'));
      await settle(tester);

      await tester.tap(_key('mcp-remove-confirm'));
      await settle(tester);

      expect(
        find.descendant(
          of: _key('mcp-banner'),
          matching: find.text(
            'team/docs-token is kept: it was not created by this page.',
          ),
        ),
        findsOneWidget,
      );
      expect(session.secrets, contains('team/docs-token'));
    });

    testWidgets('a secret that could not be deleted is an error banner with '
        'the command', (tester) async {
      session.mcpKeys.deletion = SecretDeletion.failed;
      await openPage(tester);
      await expand(tester, 'github');
      await tester.tap(_key('mcp-remove-github'));
      await settle(tester);

      await tester.tap(_key('mcp-remove-confirm'));
      await settle(tester);

      expect(
        find.descendant(
          of: _key('mcp-banner'),
          matching: find.text(
            '$_authorization could not be deleted. Delete it with: '
            'codelab secret delete $_authorization',
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('the mcp-rejected InfoBar (Q26, D24)', () {
    ConfigIssue unset() => const ConfigIssue(
      kind: ConfigIssueKind.value,
      key: 'mcp.servers[postgres].env.DATABASE_URL',
      source: FakeAgentConfigStore.userPath,
      message: 'variable PG_URL is not set',
      event: 'config.variable.unset',
    );

    testWidgets('shows the current-config header, the key path and the '
        'Edit button on a page opened with such a config; writing stays '
        'available', (tester) async {
      store.issues = [unset()];
      await openPage(tester);

      expect(_key('mcp-rejected'), findsOneWidget);
      expect(_key('mcp-unreadable'), findsNothing);
      for (final text in const [
        'The agent rejects the current config',
        'Config: invalid',
        'The agent keeps running on the previous config until this is fixed.',
        'Edit postgres',
      ]) {
        expect(
          find.descendant(of: _key('mcp-rejected'), matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      expect(
        find.descendant(
          of: _key('mcp-rejected'),
          matching: find.textContaining(
            'mcp.servers[postgres].env.DATABASE_URL',
          ),
        ),
        findsOneWidget,
      );
      expect(_key('mcp-add'), findsOneWidget);
      expect(_key('mcp-row-postgres'), findsOneWidget);

      await tester.tap(find.text('Edit postgres'));
      await settle(tester);

      expect(_in('mcp-row-postgres', 'mcp-draft-command'), findsOneWidget);
      expect(_key('mcp-save-postgres'), findsOneWidget);
    });

    testWidgets('after a save the header says the new config was rejected', (
      tester,
    ) async {
      store.onApply = () => store.issues = [unset()];
      await openPage(tester);
      await tester.tap(_key('mcp-add'));
      await settle(tester);
      await tester.enterText(_in('mcp-new', 'mcp-draft-name'), 'fresh');
      await tester.enterText(_in('mcp-new', 'mcp-draft-command'), 'npx');

      await tester.tap(_key('mcp-new-save'));
      await settle(tester);

      expect(
        find.descendant(
          of: _key('mcp-rejected'),
          matching: find.text('Saved, but the agent rejected the new config'),
        ),
        findsOneWidget,
      );
    });
  });

  group('unreadable and read-only pages (D5, SETUP-2)', () {
    testWidgets('a broken config shows mcp-unreadable with the problem, no '
        'write buttons and still the panel', (tester) async {
      store.issues = const [
        ConfigIssue(
          kind: ConfigIssueKind.syntax,
          key: '',
          source: FakeAgentConfigStore.userPath,
          message: 'cannot parse the file',
        ),
      ];
      await openPage(tester);

      expect(_key('mcp-unreadable'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('mcp-unreadable'),
          matching: find.textContaining('cannot parse the file'),
        ),
        findsOneWidget,
      );
      expect(_key('mcp-add'), findsNothing);
      expect(_key('mcp-row-github'), findsNothing);
      expect(_key('mcp-status'), findsOneWidget);
    });

    testWidgets('a remote agent shows only mcp-read-only and the panel', (
      tester,
    ) async {
      connect(_remote, active: _s1);
      externalSession();
      await openPage(tester);

      expect(_key('mcp-read-only'), findsOneWidget);
      expect(
        find.textContaining('Read-only: this agent runs on wss://devbox:7420.'),
        findsOneWidget,
      );
      expect(_key('mcp-add'), findsNothing);
      expect(_key('mcp-row-github'), findsNothing);
      expect(_key('mcp-status'), findsOneWidget);
      expect(_key('mcp-status-refresh'), findsOneWidget);
      expect(find.textContaining(leakMarker), findsNothing);
    });
  });

  group('the Agent status panel (D12, Q24)', () {
    testWidgets('the embedded agent shows the live table: cells, time, '
        'Reconnect per row and Reload all', (tester) async {
      final port = FakeMcpStatusPort(
        'p1',
        servers: [
          mcpSummary('github', tools: 42),
          mcpSummary(
            'postgres',
            state: McpServerState.failed,
            lastError: 'ECONNREFUSED 127.0.0.1:5432',
            retryIn: const Duration(seconds: 24),
          ),
          mcpSummary('playwright', state: McpServerState.disabled),
        ],
      );
      source.ports[_s1] = port;
      connect(embeddedConnectionProfile, active: _s1);
      await openPage(tester);

      expect(_key('mcp-status-unavailable'), findsNothing);
      expect(find.text('Live from the embedded agent · 14:02'), findsOneWidget);
      for (final head in const ['SERVER', 'STATE', 'TOOLS', 'LAST ERROR']) {
        expect(find.text(head), findsOneWidget, reason: head);
      }
      for (final name in const ['github', 'postgres', 'playwright']) {
        expect(_key('mcp-status-row-$name'), findsOneWidget, reason: name);
      }
      expect(find.text('connected'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('failed · retry in 24 s'), findsOneWidget);
      expect(find.text('ECONNREFUSED 127.0.0.1:5432'), findsOneWidget);
      expect(find.text('disabled'), findsOneWidget);
      // Выключенному серверу переподключение ничего не даёт.
      expect(_key('mcp-status-reconnect-playwright'), findsNothing);

      await tester.tap(_key('mcp-status-reconnect-postgres'));
      await settle(tester);
      expect(port.reconnected, ['postgres']);

      await tester.tap(_key('mcp-status-reload-all'));
      await settle(tester);
      expect(port.reconnected, ['postgres', 'github', 'postgres']);
    });

    testWidgets('scenario "a blocked server": the row shows failed and the '
        'core reason, never mcp-rejected', (tester) async {
      const reason =
          'key bound to another address: move the server to '
          'config.local.yaml or the user config '
          '(secret codelab/mcp/postgres/database_url)';
      source.ports[_s1] = FakeMcpStatusPort(
        'p1',
        servers: [
          mcpSummary(
            'postgres',
            state: McpServerState.failed,
            lastError: reason,
          ),
        ],
      );
      connect(embeddedConnectionProfile, active: _s1);
      await openPage(tester);

      expect(_key('mcp-status-row-postgres'), findsOneWidget);
      expect(find.text('failed'), findsOneWidget);
      expect(find.text(reason), findsOneWidget);
      expect(_key('mcp-rejected'), findsNothing);
      expect(find.textContaining('rejected'), findsNothing);
      expect(find.textContaining(leakMarker), findsNothing);
    });

    testWidgets('a change of the port updates the table', (tester) async {
      final port = FakeMcpStatusPort(
        'p1',
        servers: [mcpSummary('github', tools: 1)],
      );
      source.ports[_s1] = port;
      connect(embeddedConnectionProfile, active: _s1);
      await openPage(tester);

      port.emit([mcpSummary('github', tools: 5)]);
      await settle(tester);

      expect(find.text('5'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('an agent outside the process shows the /mcp list reply as '
        'a monospace block after Refresh, and nothing before it', (
      tester,
    ) async {
      connect(_ownAgent, active: _s1);
      final handle = externalSession();
      handle.onSend = (_) async => completedTurn(_s1, [
        AgentMessageChunk(
          content: const TextContent(text: 'github   connected'),
        ),
      ]);
      await openPage(tester);
      expect(handle.sent, isEmpty);
      expect(_key('mcp-status-text'), findsNothing);
      expect(
        tester.widget<CodeLabButton>(_key('mcp-status-refresh')).onPressed,
        isNotNull,
      );

      await tester.tap(_key('mcp-status-refresh'));
      await settle(tester);

      expect(handle.sent, ['/mcp list']);
      expect(_key('mcp-status-text'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('mcp-status-text'),
          matching: find.text('github   connected'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Reconnect of a row sends one /mcp reload <name> and shows '
        'its reply (Q29)', (tester) async {
      connect(_ownAgent, active: _s1);
      final handle = externalSession();
      handle.onSend = (_) async => completedTurn(_s1, [
        AgentMessageChunk(content: const TextContent(text: 'github reloaded')),
      ]);
      await openPage(tester);
      await expand(tester, 'github');

      await tester.tap(_key('mcp-reconnect-github'));
      await settle(tester);

      expect(handle.sent, ['/mcp reload github']);
      expect(
        find.descendant(
          of: _key('mcp-status-text'),
          matching: find.text('github reloaded'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the buttons are inactive while a turn is running', (
      tester,
    ) async {
      connect(_ownAgent, active: _s1);
      externalSession(sessionStatus: SessionStatusView.running);
      await openPage(tester);

      expect(
        tester.widget<CodeLabButton>(_key('mcp-status-refresh')).onPressed,
        isNull,
      );
      expect(
        tester.widget<CodeLabButton>(_key('mcp-status-reload-all')).onPressed,
        isNull,
      );
    });

    testWidgets('a failed /mcp list shows the line above the old text '
        'without the error text', (tester) async {
      connect(_ownAgent, active: _s1);
      final handle = externalSession();
      handle.onSend = (_) async => completedTurn(_s1, [
        AgentMessageChunk(content: const TextContent(text: 'old reply')),
      ]);
      await openPage(tester);
      await tester.tap(_key('mcp-status-refresh'));
      await settle(tester);
      handle.onSend = (_) async =>
          PromptFailed(_s1, StateError('boom $leakMarker'));

      await tester.tap(_key('mcp-status-refresh'));
      await settle(tester);

      expect(
        find.text('/mcp list did not complete. Try Refresh again.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('mcp-status-text'),
          matching: find.text('old reply'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('boom'), findsNothing);
      expect(find.textContaining(leakMarker), findsNothing);
    });
  });

  // Задача 6.1b-2 change `add-provider-setup-ui` (Q31): текст баннера
  // `saved` после записи сервера, который агент применит после «Restart
  // agent». Признак — настоящая функция моста по снимкам настоящего
  // хранилища, запись идёт через `runAsync` (файловый ввод-вывод).
  group('the saved banner after a write that needs Restart agent (6.1b-2)', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('codelab_mcp_page_restart_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/home').createSync();
      Directory('${root.path}/project').createSync();
    });

    Future<(McpSettingsCubit, RealConfigSession)> openReal(
      WidgetTester tester, {
      String config = realHomeConfig,
    }) async {
      final real = await tester.runAsync(
        () => RealConfigSession.open(
          home: '${root.path}/home',
          project: '${root.path}/project',
          config: config,
        ),
      );
      projectDir = '${root.path}/project';
      connect(embeddedConnectionProfile);
      final cubit = await openPage(tester, realSession: real);
      return (cubit, real!);
    }

    testWidgets('a new stdio server: the banner names Restart agent', (
      tester,
    ) async {
      final (cubit, _) = await openReal(tester);

      await tester.runAsync(
        () => cubit.save(
          McpServerDraft(
            name: 'fresh',
            kind: McpTransportKind.stdio,
            command: 'npx',
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: _key('mcp-banner'),
          matching: find.text(
            'Server fresh saved. It starts after Restart agent '
            '(Settings › Connection).',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the switch that enables a server: the banner says enabled '
        'and names Restart agent', (tester) async {
      final (cubit, _) = await openReal(
        tester,
        config:
            '''
$realHomeConfig
mcp:
  servers:
    - name: docs
      type: stdio
      command: docs-mcp
      enabled: false
''',
      );

      await tester.runAsync(() => cubit.setEnabled('docs', enabled: true));
      await tester.pump();

      expect(
        find.descendant(
          of: _key('mcp-banner'),
          matching: find.text(
            'Server docs enabled. It starts after Restart agent '
            '(Settings › Connection).',
          ),
        ),
        findsOneWidget,
      );
    });
  });

  // Задача 6.1e (Q34): панель показывает ответ без внешнего ограждения.
  group('the fence of the /mcp reply on the page (6.1e)', () {
    testWidgets('a fenced reply is shown without the fence lines; a reply '
        'with text around the block is shown as it is', (tester) async {
      connect(_ownAgent, active: _s1);
      final handle = externalSession();
      handle.onSend = (_) async => completedTurn(_s1, [
        AgentMessageChunk(
          content: const TextContent(
            text: '```text\nMCP servers (1)\ngithub connected 3\n```',
          ),
        ),
      ]);
      await openPage(tester);

      await tester.tap(_key('mcp-status-refresh'));
      await settle(tester);

      final block = tester.widget<CodeLabMonospaceBlock>(
        _key('mcp-status-text'),
      );
      expect(block.data, 'MCP servers (1)\ngithub connected 3');
      expect(find.textContaining('```'), findsNothing);

      const around = 'Servers:\n```\nA\n```';
      handle.onSend = (_) async => completedTurn(_s1, [
        AgentMessageChunk(content: const TextContent(text: around)),
      ]);
      await tester.tap(_key('mcp-status-refresh'));
      await settle(tester);

      expect(
        tester.widget<CodeLabMonospaceBlock>(_key('mcp-status-text')).data,
        around,
      );
    });
  });
}
