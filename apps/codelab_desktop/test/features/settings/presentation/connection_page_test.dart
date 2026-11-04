// Страница «Connection» в собранном приложении (задачи 2.5 и 2.15 change
// `add-app-settings-shell`; spec app-settings «Список профилей на странице
// «Connection»», «Блок «Behavior»», «Предупреждение и справка для удалённого
// агента»; design.md D4, D5, D8–D10, D20, D21).
//
// Проверяется поведение (какие элементы есть, что доступно, что изменилось в
// хранилище), а не пиксели. Хранилище профилей — в памяти (`testWidgets` не
// дружит с настоящим файлом); сам файл проверяют тесты Cubit-а.

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart'
    show CodeLabStdioTransportFactory, CodeLabWebSocketTransportFactory;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../workbench/application/shell_cubit_characterization/harness.dart'
    show ThrowingStartTransport;

import '../../../support/in_memory_profile_store.dart';
import '../../../support/test_app_scope.dart';

const _withConnection = SettingsPages(available: {SettingsPage.connection});

const _dev = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: 'codelab-agent',
  args: ['serve', '--stdio', '--secret-arg'],
  env: {'K': 'secret-env'},
  runInProjectDirectory: true,
);

final _devbox = ConnectionProfile.webSocket(
  id: 'devbox',
  label: 'Devbox',
  uri: Uri.parse('wss://u:p@devbox:7420/acp?x=1'),
  tokenRef: 'env:DEVBOX_TOKEN',
);

final _plain = ConnectionProfile.webSocket(
  id: 'plain',
  label: 'Plain',
  uri: Uri.parse('ws://plain:1/acp'),
);

final _named = ConnectionProfile.webSocket(
  id: 'named',
  label: 'Named',
  uri: Uri.parse('ws://named:2/acp'),
  tokenRef: 'sk-test-leak-0123456789',
);

const _legacyDefault = ConnectionProfile.stdio(
  id: 'default',
  label: 'Old',
  command: '/opt/secret-agent',
  args: ['--token', 'leak-arg'],
  env: {'T': 'leak-env'},
);

Finder _key(String key) => find.byKey(ValueKey(key));

/// Id профиля по умолчанию — значение группы радиокнопок страницы.
String? _defaultId(WidgetTester tester) => tester
    .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
    .groupValue;

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  /// Приложение с открытой страницей «Connection».
  Future<CodeLabTestBinding> openPage(
    WidgetTester tester, {
    List<ConnectionProfile> stored = const [],
    InMemoryProfileStore? store,
    Map<String, Object> preferences = const {},
    Map<String, String> environment = const {},
    CodeLabStdioTransportFactory? stdioTransportFactory,
    CodeLabWebSocketTransportFactory? webSocketTransportFactory,
  }) async {
    final binding = CodeLabTestBinding(
      profileStore: store ?? InMemoryProfileStore(stored),
      stdioDefault: false,
      preferences: preferences,
      // Дом нужен для пути `profiles.json` в сообщении об ошибке чтения.
      environment: {'HOME': '/home/u', ...environment},
      settingsPages: _withConnection,
      stdioTransportFactory: stdioTransportFactory ?? (_) => FakeAcpTransport(),
      webSocketTransportFactory:
          webSocketTransportFactory ?? (_) => FakeAcpTransport(),
    );
    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
    await tester.pump();
    await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
    await tester.pumpAndSettle();
    return binding;
  }

  /// «Connect» в строке и ожидание исхода: подключение идёт через настоящие
  /// микрозадачи и таймеры клиента, поэтому одного `pumpAndSettle` мало.
  Future<void> connectRow(WidgetTester tester, String id) async {
    await tester.tap(_key('connection-profile-connect-$id'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  }

  group('rows and their actions', () {
    testWidgets('a stored profile has the row, default, connect, test, '
        'rename and remove controls', (tester) async {
      await openPage(tester, stored: [_dev]);

      for (final part in const [
        'row',
        'default',
        'connect',
        'test',
        'rename',
        'remove',
      ]) {
        expect(
          _key('connection-profile-$part-dev'),
          findsOneWidget,
          reason: part,
        );
      }
      expect(find.text('Dev'), findsWidgets);
      await tearDownApp(tester);
    });

    testWidgets('the embedded agent is the first row and has default and '
        'connect only: no test, rename or remove', (tester) async {
      await openPage(tester, stored: [_dev]);

      expect(_key('connection-profile-row-embedded'), findsOneWidget);
      expect(_key('connection-profile-default-embedded'), findsOneWidget);
      expect(_key('connection-profile-connect-embedded'), findsOneWidget);
      expect(_key('connection-profile-test-embedded'), findsNothing);
      expect(_key('connection-profile-rename-embedded'), findsNothing);
      expect(_key('connection-profile-remove-embedded'), findsNothing);
      final embedded = tester.getTopLeft(
        _key('connection-profile-row-embedded'),
      );
      final dev = tester.getTopLeft(_key('connection-profile-row-dev'));
      expect(embedded.dy, lessThan(dev.dy));
      await tearDownApp(tester);
    });

    testWidgets('Embedded agent is the default on a new install; the row '
        'text is "Runs inside CodeLab; no separate process."', (tester) async {
      await openPage(tester, stored: [_dev]);

      expect(_defaultId(tester), 'embedded');
      expect(
        find.text('Runs inside CodeLab; no separate process.'),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('the row shows the command or scheme://host:port only, '
        'without arguments, env or the path of the URL', (tester) async {
      await openPage(tester, stored: [_dev, _devbox]);

      expect(find.textContaining('codelab-agent'), findsWidgets);
      expect(find.textContaining('wss://devbox:7420'), findsWidgets);
      for (final secret in const ['secret-arg', 'secret-env', 'u:p', '/acp']) {
        expect(find.textContaining(secret), findsNothing, reason: secret);
      }
      await tearDownApp(tester);
    });

    testWidgets('selecting the radio of a profile saves it as the default', (
      tester,
    ) async {
      await openPage(tester, stored: [_dev]);

      await tester.tap(_key('connection-profile-default-dev'));
      await tester.pumpAndSettle();

      expect(
        (await SharedPreferences.getInstance()).getString(
          'codelab.connection.default_profile',
        ),
        'dev',
      );
      expect(_defaultId(tester), 'dev');
      await tearDownApp(tester);
    });

    testWidgets('Connect marks the row Current and keeps the default', (
      tester,
    ) async {
      await openPage(tester, stored: [_dev]);

      await connectRow(tester, 'dev');

      expect(find.text('Current'), findsOneWidget);
      expect(_defaultId(tester), 'embedded');
      await tearDownApp(tester);
    });

    testWidgets('Remove is unavailable for the current profile with the '
        'hint "Disconnect first" and available for others', (tester) async {
      await openPage(tester, stored: [_dev, _plain]);

      await connectRow(tester, 'dev');

      CodeLabButton remove(String id) =>
          tester.widget<CodeLabButton>(_key('connection-profile-remove-$id'));
      expect(remove('dev').onPressed, isNull);
      expect(remove('plain').onPressed, isNotNull);
      expect(find.byTooltip('Disconnect first'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('Remove asks for confirmation "Remove profile <label>?" and '
        'deletes only after it', (tester) async {
      final store = InMemoryProfileStore([_dev, _plain]);
      await openPage(tester, store: store);

      await tester.tap(_key('connection-profile-remove-plain'));
      await tester.pumpAndSettle();
      expect(find.text('Remove profile Plain?'), findsOneWidget);
      await tester.tap(_key('connection-remove-cancel'));
      await tester.pumpAndSettle();
      expect(store.profiles.map((p) => p.id), ['dev', 'plain']);

      await tester.tap(_key('connection-profile-remove-plain'));
      await tester.pumpAndSettle();
      await tester.tap(_key('connection-remove-confirm'));
      await tester.pumpAndSettle();

      expect(store.profiles.map((p) => p.id), ['dev']);
      expect(_key('connection-profile-row-plain'), findsNothing);
      await tearDownApp(tester);
    });
  });

  group('row title and status badge (manual run)', () {
    final py = ConnectionProfile.stdio(
      id: 'py',
      label: 'stdio:python -m "codelab agent" --stdio',
      command: 'python',
      args: const ['-m', 'codelab agent', '--stdio'],
    );
    final emptyLabel = ConnectionProfile.webSocket(
      id: 'ws',
      label: '',
      uri: Uri.parse('ws://ws:1/acp'),
    );
    const longLabel =
        'A very long label that does not fit the row title and keeps going '
        'and going until it is cut with an ellipsis at the end of the line';
    const longProfile = ConnectionProfile.stdio(
      id: 'dev',
      label: longLabel,
      command: 'codelab-agent',
    );

    testWidgets('the title is the id for stdio:-labels and empty labels; the '
        'second line is the command without arguments', (tester) async {
      await openPage(tester, stored: [py, emptyLabel]);

      Finder title(String id) => find.descendant(
        of: _key('connection-profile-row-$id'),
        matching: find.byKey(ValueKey('connection-profile-title-$id')),
      );
      expect(tester.widget<Text>(title('py')).data, 'py');
      expect(tester.widget<Text>(title('ws')).data, 'ws');
      expect(
        find.descendant(
          of: _key('connection-profile-row-py'),
          matching: find.text('python'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('codelab agent'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('a long label is one line with an ellipsis and the full '
        'text in the tooltip', (tester) async {
      await openPage(tester, stored: [longProfile]);

      final text = tester.widget<Text>(
        find.byKey(const ValueKey('connection-profile-title-dev')),
      );
      expect(text.data, longLabel);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(find.byTooltip(longLabel), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('the status badge of the current row follows the window '
        'connection and has no other rows or error text', (tester) async {
      await openPage(tester, stored: [_dev, _plain]);
      expect(_key('connection-profile-status-dev'), findsNothing);

      await connectRow(tester, 'dev');

      final badge = _key('connection-profile-status-dev');
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('Connected')),
        findsOneWidget,
      );
      expect(_key('connection-profile-status-plain'), findsNothing);
      expect(_key('connection-profile-status-embedded'), findsNothing);
      await tearDownApp(tester);
    });
  });

  group('keys for the shell and the help (manual run)', () {
    testWidgets('the search field and Back have keys; Back has a tooltip; '
        'the help key is on the tappable header', (tester) async {
      await openPage(tester);

      expect(_key('settings-search'), findsOneWidget);
      expect(_key('settings-back'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      // Ключ справки — на нажимаемом заголовке: тап по нему раскрывает.
      await tester.tap(_key('connection-join-cli-help'));
      await tester.pumpAndSettle();
      expect(find.textContaining('serve --ws'), findsOneWidget);
      await tearDownApp(tester);
    });
  });

  group('token source of a WebSocket row', () {
    testWidgets('No token / From \$NAME / not set / not supported', (
      tester,
    ) async {
      await openPage(
        tester,
        stored: [_plain, _devbox, _named],
        environment: const {},
      );

      String textOf(String id) => tester
          .widgetList<Text>(
            find.descendant(
              of: _key('connection-profile-token-$id'),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .join(' ');
      expect(textOf('plain'), 'No token');
      expect(textOf('devbox'), contains(r'From $DEVBOX_TOKEN'));
      expect(
        textOf('devbox'),
        contains("DEVBOX_TOKEN is not set in CodeLab's environment."),
      );
      expect(
        textOf('named'),
        'unrecognized token reference (not supported in this version)',
      );
      // Сама ссылка нигде не выводится (M2).
      expect(find.textContaining('sk-test-leak-0123456789'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('a set variable has no "not set" note and its value is '
        'nowhere on the screen', (tester) async {
      await openPage(
        tester,
        stored: [_devbox],
        environment: const {'DEVBOX_TOKEN': 'sk-leak-0123456789'},
      );

      expect(find.textContaining(r'From $DEVBOX_TOKEN'), findsOneWidget);
      expect(find.textContaining('is not set'), findsNothing);
      expect(find.textContaining('sk-leak-0123456789'), findsNothing);
      await tearDownApp(tester);
    });
  });

  group('page controls', () {
    testWidgets('the test button is called "Test connection"', (tester) async {
      await openPage(tester, stored: [_dev]);

      expect(
        tester.widget<CodeLabButton>(_key('connection-profile-test-dev')).label,
        'Test connection',
      );
      await tearDownApp(tester);
    });

    testWidgets('Add profile is the only CommandBar action and is available '
        'when the file is readable', (tester) async {
      await openPage(tester, stored: [_dev]);

      expect(_key('connection-add-profile'), findsOneWidget);
      // «Restart agent» живёт в блоке Behavior, дубля в CommandBar нет.
      expect(find.text('Restart agent'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('Connect on start is a toggle in Behavior; switching it '
        'persists the choice', (tester) async {
      await openPage(tester);
      expect(
        tester
            .widget<ToggleSwitch>(_key('connection-connect-on-start'))
            .checked,
        isFalse,
      );

      await tester.tap(_key('connection-connect-on-start'));
      await tester.pumpAndSettle();

      expect(
        (await SharedPreferences.getInstance()).getBool(
          'codelab.connection.connect_on_start',
        ),
        isTrue,
      );
      await tearDownApp(tester);
    });

    testWidgets('Restart agent is disabled without a current profile and '
        'enabled after Connect; it never promises session/cancel', (
      tester,
    ) async {
      await openPage(tester, stored: [_dev]);
      CodeLabButton restart() =>
          tester.widget<CodeLabButton>(_key('connection-restart-agent'));
      expect(restart().onPressed, isNull);

      await connectRow(tester, 'dev');

      expect(restart().onPressed, isNotNull);
      expect(restart().label, 'Restart');
      expect(find.textContaining('session/cancel'), findsNothing);
      expect(find.textContaining('queued prompts stay'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('for a WebSocket profile the row is called Reconnect', (
      tester,
    ) async {
      await openPage(tester, stored: [_plain]);

      await connectRow(tester, 'plain');

      expect(
        tester.widget<CodeLabButton>(_key('connection-restart-agent')).label,
        'Reconnect',
      );
      expect(find.text('Reconnect'), findsWidgets);
      expect(
        find.descendant(
          of: _key('connection-restart-row'),
          matching: find.textContaining('process'),
        ),
        findsNothing,
      );
      await tearDownApp(tester);
    });
  });

  group('remote agent (D10)', () {
    testWidgets('the read-only InfoBar appears for a connected WebSocket '
        'profile without path, query and userinfo; Add profile stays '
        'available', (tester) async {
      await openPage(tester, stored: [_devbox]);
      expect(_key('connection-remote-read-only'), findsNothing);

      await connectRow(tester, 'devbox');

      final bar = _key('connection-remote-read-only');
      expect(bar, findsOneWidget);
      final text = tester
          .widgetList<Text>(
            find.descendant(of: bar, matching: find.byType(Text)),
          )
          .map((t) => t.data ?? '')
          .join(' ');
      expect(text, contains('wss://devbox:7420'));
      expect(text, contains('codelab provider add'));
      for (final hidden in const ['/acp', 'x=1', 'u:p']) {
        expect(text, isNot(contains(hidden)));
      }
      // «Add profile» остаётся на странице: профили клиента редактируемы
      // (кнопка оживает с диалогом итерации 3).
      expect(_key('connection-add-profile'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('no read-only InfoBar for stdio', (tester) async {
      await openPage(tester, stored: [_dev]);

      await connectRow(tester, 'dev');

      expect(_key('connection-remote-read-only'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('the CLI help is collapsed, does not mention Fork or '
        'locks, and opens on tap', (tester) async {
      await openPage(tester);
      final help = _key('connection-join-cli-help');
      expect(help, findsOneWidget);
      expect(find.textContaining('serve --ws'), findsNothing);

      await tester.tap(find.text('Join a session started in the CLI'));
      await tester.pumpAndSettle();

      expect(find.textContaining('serve --ws'), findsOneWidget);
      expect(find.textContaining('Fork'), findsNothing);
      expect(find.textContaining('lock'), findsNothing);
      await tearDownApp(tester);
    });
  });

  group('unreadable profiles.json (data integrity)', () {
    testWidgets('the error InfoBar and the embedded row show; Add, Rename '
        'and Remove are unavailable', (tester) async {
      final store = InMemoryProfileStore([_dev])..failLoad = true;
      await openPage(tester, store: store);

      expect(_key('connection-profiles-unreadable'), findsOneWidget);
      expect(
        find.textContaining('CodeLab will not overwrite it'),
        findsOneWidget,
      );
      expect(_key('connection-profile-row-embedded'), findsOneWidget);
      expect(_key('connection-profile-row-dev'), findsNothing);
      expect(
        tester.widget<CodeLabButton>(_key('connection-add-profile')).onPressed,
        isNull,
      );
      // «Behavior» не зависит от файла и остаётся рабочим (D4).
      expect(_key('connection-connect-on-start'), findsOneWidget);
      expect(_key('connection-restart-agent'), findsOneWidget);
      await tester.tap(_key('connection-connect-on-start'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ToggleSwitch>(_key('connection-connect-on-start'))
            .checked,
        isTrue,
      );
      await tearDownApp(tester);
    });
  });

  group('legacy "default" entry (D5, D21, task 2.15)', () {
    testWidgets('the entry is not a row; the InfoBar names the problem '
        'without the command, arguments or env of the entry', (tester) async {
      final store = InMemoryProfileStore([_legacyDefault, _dev]);
      await openPage(tester, store: store);

      expect(_key('connection-profile-row-default'), findsNothing);
      expect(_key('connection-profile-row-dev'), findsOneWidget);
      final bar = _key('connection-profiles-ignored-default');
      expect(bar, findsOneWidget);
      expect(
        find.textContaining(
          'Profile "default" in profiles.json is ignored: default is the '
          'built-in agent. Remove it with codelab profiles remove default.',
        ),
        findsOneWidget,
      );
      for (final hidden in const ['secret-agent', 'leak-arg', 'leak-env']) {
        expect(find.textContaining(hidden), findsNothing, reason: hidden);
      }
      // Без действия пользователя файл не перезаписывается.
      expect(store.profiles.map((p) => p.id), ['default', 'dev']);
      await tearDownApp(tester);
    });

    testWidgets('Remove in the InfoBar deletes the entry only after the '
        'confirmation; the InfoBar disappears', (tester) async {
      final store = InMemoryProfileStore([_legacyDefault, _dev]);
      await openPage(tester, store: store);

      await tester.tap(
        find.descendant(
          of: _key('connection-profiles-ignored-default'),
          matching: find.text('Remove'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_key('connection-remove-cancel'));
      await tester.pumpAndSettle();
      expect(store.profiles.map((p) => p.id), ['default', 'dev']);

      await tester.tap(
        find.descendant(
          of: _key('connection-profiles-ignored-default'),
          matching: find.text('Remove'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_key('connection-remove-confirm'));
      await tester.pumpAndSettle();

      expect(store.profiles.map((p) => p.id), ['dev']);
      expect(_key('connection-profiles-ignored-default'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('no InfoBar without the entry', (tester) async {
      await openPage(tester, stored: [_dev]);

      expect(_key('connection-profiles-ignored-default'), findsNothing);
      await tearDownApp(tester);
    });
  });

  group('restart target after a failed Connect (MEDIUM-A)', () {
    testWidgets('the window on stdio, Connect to a WebSocket profile failed: '
        'Current and the Restart wording stay on stdio, and Restart '
        'reconnects stdio', (tester) async {
      var stdioStarts = 0;
      await openPage(
        tester,
        stored: [_dev, _plain],
        stdioTransportFactory: (_) {
          stdioStarts++;
          return FakeAcpTransport();
        },
        webSocketTransportFactory: (_) =>
            ThrowingStartTransport(StateError('unreachable')),
      );
      await connectRow(tester, 'dev');
      expect(stdioStarts, 1);

      await connectRow(tester, 'plain');

      // «Current» — только у профиля с живым соединением: после неудачи
      // его нет ни у кого, а бейдж `Failed` — на строке попытки.
      expect(find.text('Current'), findsNothing);
      expect(
        find.descendant(
          of: _key('connection-profile-status-plain'),
          matching: find.text('Failed'),
        ),
        findsOneWidget,
      );
      expect(_key('connection-profile-status-dev'), findsNothing);
      expect(
        tester.widget<CodeLabButton>(_key('connection-restart-agent')).label,
        'Restart',
      );
      // Подпись строки называет цель перезапуска.
      expect(
        find.textContaining(
          'Reconnects Dev and reloads open sessions. A running turn is '
          'interrupted; queued prompts stay.',
        ),
        findsOneWidget,
      );
      expect(_key('connection-remote-read-only'), findsNothing);

      await tester.tap(_key('connection-restart-agent'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(stdioStarts, 2);
      expect(
        find.descendant(
          of: _key('connection-profile-row-dev'),
          matching: find.text('Current'),
        ),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });
  });

  group('a CLI profile with a long label (LOW)', () {
    final cli = ConnectionProfile.stdio(
      id: 'py',
      label: 'stdio:python -m "codelab agent" --stdio',
      command: 'python',
      args: const ['-m', 'codelab agent', '--stdio'],
    );

    testWidgets('the Remove confirmation names the id, not the command '
        'line', (tester) async {
      await openPage(tester, stored: [cli]);

      await tester.tap(_key('connection-profile-remove-py'));
      await tester.pumpAndSettle();

      expect(find.text('Remove profile py?'), findsOneWidget);
      expect(find.textContaining('codelab agent'), findsNothing);
      await tester.tap(_key('connection-remove-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('the connection screen shows the id and no arguments', (
      tester,
    ) async {
      final binding = CodeLabTestBinding(
        profileStore: InMemoryProfileStore([cli]),
        stdioDefault: false,
        preferences: const {'codelab.connection.default_profile': 'py'},
      );
      await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
      await tester.pump();
      await tester.pump();

      expect(find.text('py'), findsWidgets);
      expect(find.textContaining('codelab agent'), findsNothing);
      expect(find.textContaining('--stdio'), findsNothing);
      await tearDownApp(tester);
    });
  });
}
