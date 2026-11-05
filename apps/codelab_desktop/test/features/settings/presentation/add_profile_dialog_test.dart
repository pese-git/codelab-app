// Диалог «Add connection profile» (задача 3.5 change
// `add-app-settings-shell`; spec app-settings «Диалог «Add connection
// profile»»; design.md D12, D13, D20; макет
// `docs/design/claude-design/AddProfile.dc.html`).
//
// Проверяется поведение (какие элементы есть, что доступно, что записано), а
// не пиксели. Cubit собирается в тесте на хранилище в памяти и фейковом
// транспорте; виджеты окружения и файлов не видят.

import 'dart:async';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/core/platform/connection_preferences.dart';
import 'package:codelab_desktop/features/settings/application/add_profile_cubit.dart';
import 'package:codelab_desktop/features/settings/presentation/add_profile_dialog.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/in_memory_profile_store.dart';
import '../../../support/test_app_scope.dart';

const _both = [ProfileKind.stdio, ProfileKind.webSocket];
const _defaultKey = 'codelab.connection.default_profile';

Finder _key(String key) => find.byKey(ValueKey(key));

/// Текст поля по ключу `TextBox`.
String _text(WidgetTester tester, String key) =>
    tester.widget<TextBox>(_key(key)).controller!.text;

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<CodeLabButton>(_key(key)).onPressed != null;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 1000);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  late InMemoryProfileStore store;
  AddProfileCubit? openedCubit;

  /// Сколько раз проба открыла WebSocket: до подтверждения токен не уходит.
  var wsOpened = 0;

  /// Открывает диалог поверх пустого экрана и возвращает его Cubit.
  Future<AddProfileCubit> openDialog(
    WidgetTester tester, {
    List<ProfileKind> kinds = _both,
    Map<String, String> environment = const {},
    ProfileStore? profileStore,
    String? profilesPath,
  }) async {
    final cubit = AddProfileCubit(
      store: profileStore ?? store,
      preferences: const SharedPreferencesConnectionPreferences(),
      probe: ProfileProbe(
        resolvers: [
          ConfigTransportResolver(
            stdio: (_) => FakeAcpTransport(),
            webSocket: (_) {
              wsOpened++;
              return FakeAcpTransport();
            },
            secrets: ProfileSecretSource(environment),
          ),
        ],
      ),
      kinds: kinds,
      environment: environment,
      projectDirectory: () => '/work',
      profilesPath: profilesPath,
    );
    openedCubit = cubit;
    addTearDown(cubit.close);
    // Диалог открывает страница; она же загружает id профилей.
    await cubit.start();
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) => Center(
            child: Button(
              key: const ValueKey('open-dialog'),
              onPressed: () => showAddProfileDialog(context, cubit),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(_key('open-dialog'));
    await tester.pumpAndSettle();
    return cubit;
  }

  /// Ждёт конца проверки. Проба опирается на настоящие события (процессы,
  /// сокеты), которые fake-async зона сама не продвигает, поэтому реальное
  /// время и кадры чередуются, пока Cubit не выйдет из `Probing`.
  Future<void> settleProbe(WidgetTester tester) async {
    for (var i = 0; i < 100 && openedCubit!.state is Probing; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  setUp(() {
    store = InMemoryProfileStore();
    wsOpened = 0;
  });

  group('typography and layout of the mockup (fluent.css)', () {
    double? sizeOf(WidgetTester tester, Finder finder) =>
        tester.widget<Text>(finder).style?.fontSize;

    testWidgets('dialog titles are t-sub: 20 px, weight 600', (tester) async {
      await openDialog(tester);
      final title = tester.widget<Text>(find.text('Add connection profile'));
      expect(title.style?.fontSize, 20);
      expect(title.style?.fontWeight, FontWeight.w600);

      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.pump();
      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      final saved = tester.widget<Text>(find.text('Profile saved'));
      expect(saved.style?.fontSize, 20);
      expect(saved.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('"Unencrypted connection" is one caption row: text first, '
        '"Save anyway" to its right', (tester) async {
      await openDialog(tester, kinds: const [ProfileKind.webSocket]);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'ws://box:7420');
      await tester.pump();
      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      final bar = _key('add-profile-unencrypted');
      final text = find.descendant(of: bar, matching: find.byType(Text));
      expect(sizeOf(tester, text.first), 12);
      final textRect = tester.getRect(text.first);
      final button = tester.getRect(_key('add-profile-save-anyway'));
      expect(button.left, greaterThanOrEqualTo(textRect.right));
      expect(button.top, lessThan(textRect.bottom));
    });

    testWidgets('the "Profile saved" bar uses caption text', (tester) async {
      await openDialog(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.pump();
      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      final text = find.descendant(
        of: _key('add-profile-saved-bar'),
        matching: find.byType(Text),
      );
      expect(sizeOf(tester, text.first), 12);
    });
  });

  group('profiles path in the subtitle', () {
    testWidgets('shows the real file; under HOME it starts with ~', (
      tester,
    ) async {
      await openDialog(
        tester,
        environment: const {'HOME': '/Users/u'},
        profilesPath: '/Users/u/.codelab/profiles.json',
      );
      expect(
        find.textContaining('Saved to ~/.codelab/profiles.json and'),
        findsOneWidget,
      );
    });

    testWidgets('CODELAB_HOME outside HOME shows the absolute path', (
      tester,
    ) async {
      await openDialog(
        tester,
        environment: const {'HOME': '/Users/u'},
        profilesPath: '/private/tmp/ch/profiles.json',
      );
      expect(
        find.textContaining('Saved to /private/tmp/ch/profiles.json and'),
        findsOneWidget,
      );
      expect(find.textContaining('~/.codelab'), findsNothing);
    });
  });

  group('type', () {
    testWidgets('without a stdio resolver there is no type switch and the '
        'dialog opens on WebSocket (SETUP-22)', (tester) async {
      await openDialog(tester, kinds: const [ProfileKind.webSocket]);

      expect(_key('add-profile-type-stdio'), findsNothing);
      expect(_key('add-profile-type-websocket'), findsNothing);
      expect(_key('add-profile-url'), findsOneWidget);
      expect(_key('add-profile-command'), findsNothing);
    });

    testWidgets('with a stdio resolver the dialog opens on "Local stdio"', (
      tester,
    ) async {
      await openDialog(tester);

      expect(
        tester
            .widget<CodeLabSegmentedControl<ProfileKind>>(
              find.byType(CodeLabSegmentedControl<ProfileKind>).first,
            )
            .value,
        ProfileKind.stdio,
      );
      expect(_key('add-profile-command'), findsOneWidget);
      expect(_key('add-profile-url'), findsNothing);
    });

    testWidgets('with both kinds the switch changes the fields', (
      tester,
    ) async {
      await openDialog(tester);

      expect(find.text('Local stdio'), findsOneWidget);
      expect(find.text('WebSocket'), findsOneWidget);
      expect(_key('add-profile-command'), findsOneWidget);
      expect(_key('add-profile-url'), findsNothing);

      await tester.tap(_key('add-profile-type-websocket'));
      await tester.pumpAndSettle();

      expect(_key('add-profile-url'), findsOneWidget);
      expect(_key('add-profile-command'), findsNothing);

      await tester.tap(_key('add-profile-type-stdio'));
      await tester.pumpAndSettle();

      expect(_key('add-profile-command'), findsOneWidget);
    });
  });

  group('structure and texts of the mockup', () {
    testWidgets('title, subtitle, hints and fields of stdio', (tester) async {
      await openDialog(tester);

      expect(find.text('Add connection profile'), findsOneWidget);
      expect(
        find.textContaining(
          'Saved to ~/.codelab/profiles.json and shared with codelab_cli as '
          'codelab -a',
        ),
        findsOneWidget,
      );
      for (final label in const [
        'Type',
        'Name',
        'Command',
        'Arguments',
        'Folder',
        'Environment',
        'Check',
        'After saving',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(_text(tester, 'add-profile-command'), 'codelab-agent');
      expect(_text(tester, 'add-profile-args'), 'serve --stdio');
      expect(
        tester.widget<Checkbox>(_key('add-profile-run-in-project')).checked,
        isTrue,
      );
      expect(_key('add-profile-env'), findsOneWidget);
      expect(find.text('Run in the project folder'), findsOneWidget);
      expect(
        find.text('Parsed like a shell: quotes and escapes work.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Sends initialize only: no session is created, the process or '
          'socket closes right after.',
        ),
        findsOneWidget,
      );
      expect(find.text('Test connection'), findsOneWidget);
      expect(find.text('Use by default'), findsOneWidget);
      expect(find.text('Save without test'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('the id follows the name, can be edited and carries the '
        'caption "cannot change after saving"', (tester) async {
      await openDialog(tester);

      await tester.enterText(_key('add-profile-name'), 'Build Box');
      await tester.pump();

      expect(_text(tester, 'add-profile-id'), 'build-box');
      expect(find.textContaining('cannot change after saving'), findsOneWidget);
      expect(
        find.textContaining('codelab -a build-box'),
        findsOneWidget,
        reason: 'the subtitle shows the id',
      );

      await tester.enterText(_key('add-profile-id'), 'mine');
      await tester.pump();
      expect(find.textContaining('codelab -a mine'), findsOneWidget);
    });

    testWidgets('id errors appear at the field and block Save', (tester) async {
      store = InMemoryProfileStore([
        const ConnectionProfile.stdio(id: 'dev', label: 'Dev', command: 'c'),
      ]);
      await openDialog(tester);

      await tester.enterText(_key('add-profile-name'), 'Embedded');
      await tester.pump();
      expect(
        find.text('"embedded" is reserved for the built-in agent.'),
        findsOneWidget,
      );
      expect(_enabled(tester, 'add-profile-save'), isFalse);

      await tester.enterText(_key('add-profile-name'), 'Dev');
      await tester.pump();
      expect(
        find.text('A profile with id "dev" already exists.'),
        findsOneWidget,
      );
      expect(_enabled(tester, 'add-profile-save'), isFalse);
    });

    testWidgets('a secret-like env key shows the hint and keeps the value '
        'out of the text', (tester) async {
      await openDialog(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');

      await tester.enterText(_key('add-profile-env'), 'OPENAI_API_KEY=sk-x');
      await tester.pump();

      expect(
        find.text(
          'OPENAI_API_KEY looks like a secret. Set it in the system '
          r'environment or reference it from the agent config as ${secret:…}.',
        ),
        findsOneWidget,
      );
      expect(_enabled(tester, 'add-profile-save'), isFalse);
    });
  });

  group('WebSocket token', () {
    testWidgets('has exactly two choices, no field for the value and the '
        'hints of D13', (tester) async {
      await openDialog(tester, kinds: const [ProfileKind.webSocket]);

      expect(_key('add-profile-token-none'), findsOneWidget);
      expect(_key('add-profile-token-env'), findsOneWidget);
      expect(find.byType(RadioButton<bool>), findsNWidgets(2));
      expect(find.text('No token'), findsOneWidget);
      expect(find.text('From environment variable'), findsOneWidget);
      expect(find.text('Use stored secret'), findsNothing);
      expect(find.text('Store a new token'), findsNothing);
      expect(
        find.textContaining('Paste the token'),
        findsNothing,
        reason: 'the dialog does not accept token values',
      );
      expect(
        find.text(
          'CodeLab reads the token from this environment variable when it '
          'connects. Token values are not saved in profiles.json.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Apps opened from Finder do not see variables set in your shell '
          'profile.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the variable field defaults to CODELAB_AGENT_TOKEN', (
      tester,
    ) async {
      await openDialog(
        tester,
        kinds: const [ProfileKind.webSocket],
        environment: const {'CODELAB_AGENT_TOKEN': 'x'},
      );
      expect(_key('add-profile-token-env-name'), findsNothing);

      await tester.tap(_key('add-profile-token-env'));
      await tester.pumpAndSettle();

      expect(
        _text(tester, 'add-profile-token-env-name'),
        'CODELAB_AGENT_TOKEN',
      );
      expect(find.textContaining('is not set'), findsNothing);
    });

    testWidgets('an unset variable shows "<NAME> is not set in CodeLab\'s '
        'environment." and Save stays available', (tester) async {
      await openDialog(tester, kinds: const [ProfileKind.webSocket]);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'wss://box:1');
      await tester.tap(_key('add-profile-token-env'));
      await tester.pumpAndSettle();

      await tester.enterText(
        _key('add-profile-token-env-name'),
        'MISSING_TOKEN',
      );
      await tester.pump();

      expect(
        find.text("MISSING_TOKEN is not set in CodeLab's environment."),
        findsOneWidget,
      );
      expect(_enabled(tester, 'add-profile-save'), isTrue);
    });
  });

  group('check', () {
    testWidgets('Test connection shows the outcome and renames Save', (
      tester,
    ) async {
      await openDialog(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      expect(_key('add-profile-probe-result'), findsNothing);

      await tester.tap(_key('add-profile-test'));
      await tester.pump();
      expect(find.text('initialize…'), findsOneWidget);
      await settleProbe(tester);

      expect(_key('add-profile-probe-result'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('add-profile-probe-result'),
          matching: find.textContaining('Reachable · '),
        ),
        findsOneWidget,
      );
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Save without test'), findsNothing);
    });

    testWidgets('Test connection is unavailable for an invalid address', (
      tester,
    ) async {
      await openDialog(tester, kinds: const [ProfileKind.webSocket]);

      await tester.enterText(_key('add-profile-url'), 'nope');
      await tester.pump();

      expect(_enabled(tester, 'add-profile-test'), isFalse);
      expect(find.text('Use ws:// or wss:// with a host.'), findsOneWidget);
    });
  });

  group('save', () {
    testWidgets('Save without test writes the profile and shows "Profile '
        'saved" with "Not tested"; Done closes', (tester) async {
      await openDialog(tester);
      await tester.enterText(_key('add-profile-name'), 'Build box');
      await tester.pump();

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      expect(store.profiles.single.id, 'build-box');
      expect(_key('add-profile-saved'), findsOneWidget);
      expect(find.text('Profile saved'), findsOneWidget);
      expect(find.textContaining('Build box'), findsOneWidget);
      expect(
        find.textContaining('Added to profiles.json as build-box'),
        findsOneWidget,
      );
      expect(find.textContaining('marked "Not tested"'), findsOneWidget);
      expect(
        find.text(
          'The current connection is unchanged. Use Connect in the profile '
          'row to switch now.',
        ),
        findsOneWidget,
      );
      expect(_key('add-profile-done'), findsOneWidget);
      expect(_key('add-profile-add-another'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString(_defaultKey),
        isNull,
      );

      await tester.tap(_key('add-profile-done'));
      await tester.pumpAndSettle();
      expect(_key('add-profile-saved'), findsNothing);
    });

    testWidgets('after a successful test the screen has no "Not tested"; '
        '"Use by default" is written and named', (tester) async {
      await openDialog(tester);
      await tester.enterText(_key('add-profile-name'), 'Build box');
      await tester.tap(_key('add-profile-test'));
      await settleProbe(tester);
      await tester.tap(_key('add-profile-use-by-default'));
      await tester.pump();

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not tested'), findsNothing);
      expect(find.textContaining('used by default'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString(_defaultKey),
        'build-box',
      );
    });

    testWidgets('ws:// to another machine without a token: the hint and '
        'the confirmation speak about prompts and files; "Save anyway" '
        'writes', (tester) async {
      await openDialog(tester, kinds: const [ProfileKind.webSocket]);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(
        _key('add-profile-url'),
        'ws://box:7420/acp?t=sk-test-leak-0123456789',
      );
      await tester.pump();
      expect(
        find.text('ws:// to another machine: traffic is sent unencrypted.'),
        findsOneWidget,
      );

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      expect(store.profiles, isEmpty);
      expect(find.textContaining('Unencrypted connection'), findsOneWidget);
      expect(
        find.textContaining(
          'Prompts and files sent to ws://box:7420 will travel in clear '
          'text. Use wss:// if the host supports it.',
        ),
        findsOneWidget,
      );
      for (final secret in const ['u:p', '/acp', 't=', 'sk-test-leak']) {
        expect(
          find.descendant(
            of: _key('add-profile-unencrypted'),
            matching: find.textContaining(secret),
          ),
          findsNothing,
          reason: secret,
        );
      }

      await tester.tap(_key('add-profile-save-anyway'));
      await tester.pumpAndSettle();

      expect(store.profiles.single.id, 'box');
      expect(_key('add-profile-saved'), findsOneWidget);
    });

    testWidgets('ws:// to another machine with a token: the hint and the '
        'confirmation speak about the token; without "Save anyway" nothing '
        'is written', (tester) async {
      await openDialog(tester, kinds: const [ProfileKind.webSocket]);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'ws://box:7420');
      await tester.tap(_key('add-profile-token-env'));
      await tester.pump();
      expect(
        find.text('ws:// to another machine: the token is sent unencrypted.'),
        findsOneWidget,
      );

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unencrypted connection'), findsOneWidget);
      expect(
        find.textContaining(
          'The token for ws://box:7420 will travel in clear text. Use wss:// '
          'if the host supports it.',
        ),
        findsOneWidget,
      );
      expect(store.profiles, isEmpty);
      expect(_key('add-profile-saved'), findsNothing);
    });

    testWidgets('ws://localhost needs no confirmation and no hint', (
      tester,
    ) async {
      await openDialog(tester, kinds: const [ProfileKind.webSocket]);
      await tester.enterText(_key('add-profile-name'), 'Local');
      await tester.enterText(_key('add-profile-url'), 'ws://localhost:7420');
      await tester.pump();

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unencrypted connection'), findsNothing);
      expect(find.textContaining('ws:// to another machine'), findsNothing);
      expect(_key('add-profile-saved'), findsOneWidget);
      expect(store.profiles.single.id, 'local');
    });

    testWidgets('a write failure shows a generic message and keeps the '
        'form', (tester) async {
      await openDialog(tester, profileStore: _FailingStore());
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.pump();

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not save the profile. Try again.'),
        findsOneWidget,
      );
      expect(_key('add-profile-saved'), findsNothing);
      expect(_text(tester, 'add-profile-name'), 'Box');
    });

    testWidgets('Add another returns to an empty form', (tester) async {
      await openDialog(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.pump();
      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      await tester.tap(_key('add-profile-add-another'));
      await tester.pumpAndSettle();

      expect(_key('add-profile-saved'), findsNothing);
      expect(_text(tester, 'add-profile-name'), '');
    });
  });

  group('plaintext confirmation before Test connection (2026-11-05)', () {
    testWidgets('ws:// to another machine with a token: "Test connection" '
        'shows the same bar with "Test anyway"; nothing is sent before it', (
      tester,
    ) async {
      await openDialog(
        tester,
        kinds: const [ProfileKind.webSocket],
        environment: const {'CODELAB_AGENT_TOKEN': 'sk-test-leak'},
      );
      await tester.enterText(_key('add-profile-url'), 'ws://box:7420/acp');
      await tester.tap(_key('add-profile-token-env'));
      await tester.pump();

      await tester.tap(_key('add-profile-test'));
      await tester.pumpAndSettle();

      expect(_key('add-profile-unencrypted'), findsOneWidget);
      expect(
        find.textContaining(
          'The token for ws://box:7420 will travel in clear text. Use wss:// '
          'if the host supports it.',
        ),
        findsOneWidget,
      );
      expect(_key('add-profile-save-anyway'), findsNothing);
      expect(wsOpened, 0);
      expect(_key('add-profile-probe-result'), findsNothing);

      await tester.tap(_key('add-profile-test-anyway'));
      await settleProbe(tester);

      expect(wsOpened, 1);
      expect(_key('add-profile-unencrypted'), findsNothing);
      expect(_key('add-profile-probe-result'), findsOneWidget);
    });

    testWidgets('without a token the probe starts at once', (tester) async {
      await openDialog(tester, kinds: const [ProfileKind.webSocket]);
      await tester.enterText(_key('add-profile-url'), 'ws://box:7420');
      await tester.pump();

      await tester.tap(_key('add-profile-test'));
      await settleProbe(tester);

      expect(_key('add-profile-unencrypted'), findsNothing);
      expect(wsOpened, 1);
    });
  });

  group('userinfo in the URL (3.10.3)', () {
    testWidgets('the field explains the problem, Save is unavailable and the '
        'marker is not on screen', (tester) async {
      await openDialog(tester, kinds: const [ProfileKind.webSocket]);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(
        _key('add-profile-url'),
        'wss://u:sk-test-leak-0123456789@host:7420',
      );
      await tester.pump();

      expect(
        find.text(
          'Remove the user name and password from the URL; use the Token '
          'setting instead.',
        ),
        findsOneWidget,
      );
      expect(_enabled(tester, 'add-profile-save'), isFalse);
      // Кроме самого поля ввода (там текст пользователя) маркера нет нигде.
      expect(
        find.descendant(
          of: find.byType(ContentDialog),
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data ?? '').contains('sk-test-leak'),
          ),
        ),
        findsNothing,
      );
    });
  });

  group('Cancel and Esc while the profile is being written', () {
    Finder cancel() => find.byWidgetPredicate(
      (w) => w is CodeLabButton && w.label == 'Cancel',
    );

    testWidgets('Cancel is disabled and Esc does not close the dialog until '
        'the write finishes', (tester) async {
      final gate = Completer<void>();
      await openDialog(tester, profileStore: _GatedStore(gate));
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.pump();

      await tester.tap(_key('add-profile-save'));
      await tester.pump();
      expect(tester.widget<CodeLabButton>(cancel()).onPressed, isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Add connection profile'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(_key('add-profile-saved'), findsOneWidget);
    });
  });

  group('closing', () {
    testWidgets('Esc closes the dialog without writing anything', (
      tester,
    ) async {
      await openDialog(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.tap(_key('add-profile-use-by-default'));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Add connection profile'), findsNothing);
      expect(store.profiles, isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString(_defaultKey),
        isNull,
      );
    });

    testWidgets('Cancel closes the dialog without writing anything', (
      tester,
    ) async {
      await openDialog(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Add connection profile'), findsNothing);
      expect(store.profiles, isEmpty);
    });
  });

  group('in the app', () {
    testWidgets('"Add profile" opens the dialog; saving adds the row with '
        '"Not tested" and does not connect; Esc leaves the file alone', (
      tester,
    ) async {
      final binding = CodeLabTestBinding(
        profileStore: store,
        stdioDefault: false,
        environment: const {'HOME': '/home/u'},
        settingsPages: const SettingsPages(
          available: {SettingsPage.connection},
        ),
        stdioTransportFactory: (_) => FakeAcpTransport(),
        webSocketTransportFactory: (_) => FakeAcpTransport(),
      );
      await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
      await tester.pump();
      await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
      await tester.pumpAndSettle();

      await tester.tap(_key('connection-add-profile'));
      await tester.pumpAndSettle();
      expect(find.text('Add connection profile'), findsOneWidget);
      await tester.enterText(_key('add-profile-name'), 'Gone');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(store.profiles, isEmpty);

      await tester.tap(_key('connection-add-profile'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('add-profile-name'), 'Build box');
      await tester.pump();
      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();
      await tester.tap(_key('add-profile-done'));
      await tester.pumpAndSettle();

      expect(store.profiles.single.id, 'build-box');
      expect(_key('connection-profile-row-build-box'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('connection-profile-row-build-box'),
          matching: find.text('Not tested'),
        ),
        findsOneWidget,
      );
      expect(find.text('Current'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    });

    testWidgets('Add another then Cancel: every profile saved in the dialog '
        'gets its own mark, tested or "Not tested" (M1)', (tester) async {
      final binding = CodeLabTestBinding(
        profileStore: store,
        stdioDefault: false,
        environment: const {'HOME': '/home/u'},
        settingsPages: const SettingsPages(
          available: {SettingsPage.connection},
        ),
        stdioTransportFactory: (_) => FakeAcpTransport(),
        webSocketTransportFactory: (_) => FakeAcpTransport(),
      );
      await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
      await tester.pump();
      await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
      await tester.pumpAndSettle();

      await tester.tap(_key('connection-add-profile'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('add-profile-name'), 'First');
      await tester.pump();
      await tester.tap(_key('add-profile-test'));
      for (
        var i = 0;
        i < 100 && _key('add-profile-probe-result').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();
      await tester.tap(_key('add-profile-add-another'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('add-profile-name'), 'Second');
      await tester.pump();
      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();
      await tester.tap(_key('add-profile-add-another'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(store.profiles.map((p) => p.id), ['first', 'second']);
      Finder notTested(String id) => find.descendant(
        of: _key('connection-profile-row-$id'),
        matching: find.text('Not tested'),
      );
      expect(notTested('first'), findsNothing);
      expect(notTested('second'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScope();
    });
  });
}

/// Хранилище, чья запись ждёт сигнала: держит диалог в `Saving`.
final class _GatedStore implements ProfileStore {
  _GatedStore(this.gate);

  final Completer<void> gate;
  final _inner = InMemoryProfileStore();

  @override
  Future<List<ConnectionProfile>> load() => _inner.load();

  @override
  Future<void> save(ConnectionProfile profile) async {
    await gate.future;
    await _inner.save(profile);
  }

  @override
  Future<bool> remove(String id) => _inner.remove(id);
}

/// Хранилище, которое не пишет.
final class _FailingStore implements ProfileStore {
  @override
  Future<List<ConnectionProfile>> load() async => const [];

  @override
  Future<void> save(ConnectionProfile profile) async =>
      throw StateError('disk is full');

  @override
  Future<bool> remove(String id) async => false;
}
