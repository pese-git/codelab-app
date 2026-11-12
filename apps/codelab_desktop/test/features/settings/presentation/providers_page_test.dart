// Страница «Providers» в собранном приложении (задача 2.7 change
// `add-provider-setup-ui`; spec app-settings «Страница «Providers»», «Доступ
// к настройкам агента на страницах Providers и MCP servers»; design.md D10).
//
// Проверяется поведение (что есть на странице, что доступно и что вызвано),
// а не пиксели. Конфиг, секреты и проверка — двойники; Cubit и мост проверяют
// свои тесты.

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_provider_settings.dart';
import '../../../support/in_memory_profile_store.dart';
import '../../../support/test_app_scope.dart';

const _pages = SettingsPages(
  available: {SettingsPage.connection, SettingsPage.providers},
);

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

Map<String, Object?> _two() => {
  'agent': {'default_model': 'anthropic/m'},
  'providers': {
    'anthropic': providerMap(
      kind: 'anthropic',
      baseUrl: null,
      secret: 'codelab/anthropic',
    ),
    'local': providerMap(
      baseUrl: 'http://localhost:11434/v1',
      models: ['qwen'],
    ),
  },
};

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 1400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;
  var opens = 0;

  Future<void> openPage(
    WidgetTester tester, {
    ConnectionProfile? defaultProfile,
  }) async {
    opens = 0;
    final binding = CodeLabTestBinding(
      stdioDefault: false,
      profileStore: InMemoryProfileStore([?defaultProfile]),
      preferences: {'codelab.connection.default_profile': ?defaultProfile?.id},
      environment: {'HOME': '/home/u'},
      settingsPages: _pages,
      providerSettingsOpener: (access, env) async {
        opens++;
        return session;
      },
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
    await tester.pumpAndSettle();
    await tester.tap(_key(SettingsPage.providers.navKey));
    await tester.pumpAndSettle();
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }

  setUp(() {
    store = FakeAgentConfigStore(user: _two());
    session = FakeProviderSettingsSession(
      store,
      secrets: {'codelab/anthropic': leakMarker},
    );
  });

  group('page position (task 3.15, D24)', () {
    for (final height in const [900.0, 1600.0]) {
      testWidgets('the Providers body starts 28 px below the top of the '
          'content area at 1280x${height.toInt()}', (tester) async {
        final view = TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .views
            .single;
        view.physicalSize = Size(1280, height);
        await openPage(tester);

        // Область содержимого — под строкой заголовка окна до низа окна.
        final area = Rect.fromLTRB(
          0,
          tester.getRect(find.byType(TitleBar)).bottom,
          1280,
          height,
        );
        final body = tester.getTopLeft(_key('settings-providers'));
        expect(body.dy - area.top, 28);
        await tearDownApp(tester);
      });
    }
  });

  group('layout', () {
    testWidgets('has the header, default model, key storage, rows and the '
        'config path with the D10 keys', (tester) async {
      await openPage(tester);

      expect(_key('settings-providers'), findsOneWidget);
      expect(find.text('Providers'), findsWidgets);
      expect(_key('providers-add'), findsOneWidget);
      expect(_key('providers-default-model'), findsOneWidget);
      expect(_key('providers-key-storage'), findsOneWidget);
      expect(find.text('Key storage: file'), findsOneWidget);
      expect(find.text('writable'), findsOneWidget);
      expect(
        find.text(
          'Only key names and presence are read — values never enter the app',
        ),
        findsOneWidget,
      );
      expect(find.text('Configured providers'), findsOneWidget);
      for (final part in const [
        'row',
        'check',
        'edit',
        'remove',
        'status',
        'key',
      ]) {
        for (final id in const ['anthropic', 'local']) {
          expect(
            _key('providers-$part-$id'),
            findsOneWidget,
            reason: '$part-$id',
          );
        }
      }
      expect(find.text('Default'), findsOneWidget);
      expect(
        find.text('anthropic · Anthropic · Key: in file · 1 model'),
        findsOneWidget,
      );
      expect(find.text('Config file: ~/.codelab/config.yaml'), findsOneWidget);
      expect(find.textContaining(leakMarker), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('a file backend adds the open-file line and a read-only one '
        'shows its reason', (tester) async {
      await openPage(tester);
      expect(
        find.text(
          'Keys are stored in an open file ~/.codelab/secrets.yaml '
          '(mode 0600).',
        ),
        findsOneWidget,
      );
      expect(_key('providers-store-unavailable'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('a read-only backend shows the tag and the reason', (
      tester,
    ) async {
      store.backend = const SecretBackendInfo(
        id: 'env',
        writable: false,
        unavailableReason: 'OS key stores are not available yet',
      );
      await openPage(tester);

      expect(find.text('Key storage: env'), findsOneWidget);
      expect(find.text('read-only'), findsOneWidget);
      expect(_key('providers-store-unavailable'), findsOneWidget);
      expect(
        find.textContaining('OS key stores are not available yet'),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('expanding a row shows Key, Last check and Source', (
      tester,
    ) async {
      await openPage(tester);

      await tester.tap(_key('providers-row-anthropic'));
      await tester.pumpAndSettle();

      expect(find.text('Last check'), findsOneWidget);
      expect(find.text('Source'), findsOneWidget);
      expect(find.text('~/.codelab/config.yaml'), findsWidgets);
      expect(find.byType(CodeLabKeyValueList), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('a project-layer provider has no Edit or Remove and says '
        'where it is defined', (tester) async {
      store.project = {
        'providers': {
          'team': providerMap(models: ['big']),
        },
      };
      await openPage(tester);

      expect(_key('providers-row-team'), findsOneWidget);
      expect(_key('providers-check-team'), findsOneWidget);
      expect(_key('providers-edit-team'), findsNothing);
      expect(_key('providers-remove-team'), findsNothing);
      expect(
        find.textContaining('defined in /work/app/.codelab/config.yaml'),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('an empty config shows the empty line and Add provider', (
      tester,
    ) async {
      store.user = {};
      await openPage(tester);

      expect(_key('providers-empty'), findsOneWidget);
      expect(
        find.text(
          'No providers yet. The embedded agent needs one to run a turn.',
        ),
        findsOneWidget,
      );
      expect(_key('providers-add'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('a broken config.yaml shows the loader problems and no '
        'write controls', (tester) async {
      store.issues = [
        const ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'providers.anthropic.kind',
          source: FakeAgentConfigStore.userPath,
          message: 'must be openai-compatible',
        ),
      ];
      await openPage(tester);

      expect(_key('providers-unreadable'), findsOneWidget);
      expect(find.textContaining('providers.anthropic.kind'), findsOneWidget);
      expect(_key('providers-add'), findsNothing);
      expect(_key('providers-default-model'), findsNothing);
      await tearDownApp(tester);
    });
  });

  group('read-only agents', () {
    testWidgets('a WebSocket agent: the InfoBar without the path, no rows, no '
        'write controls and the local file is not read', (tester) async {
      await openPage(tester, defaultProfile: _remote);

      expect(_key('providers-read-only'), findsOneWidget);
      expect(
        find.textContaining('Read-only: this agent runs on wss://devbox:7420.'),
        findsOneWidget,
      );
      expect(find.textContaining('/acp'), findsNothing);
      expect(find.textContaining(leakMarker), findsNothing);
      expect(_key('providers-add'), findsNothing);
      expect(_key('providers-row-anthropic'), findsNothing);
      expect(opens, 0);
      await tearDownApp(tester);
    });

    testWidgets('a third-party stdio agent is managed by itself', (
      tester,
    ) async {
      await openPage(tester, defaultProfile: _foreign);

      expect(
        find.textContaining('Provider settings are managed by python.'),
        findsOneWidget,
      );
      expect(_key('providers-add'), findsNothing);
      expect(opens, 0);
      await tearDownApp(tester);
    });
  });

  group('wizard entry points and unencrypted keys', () {
    testWidgets('Add provider opens the wizard on the page session, without '
        'forcing the default model', (tester) async {
      await openPage(tester);

      await tester.tap(_key('providers-add'));
      await tester.pumpAndSettle();

      expect(_key('provider-wizard'), findsOneWidget);
      expect(find.text('Add provider'), findsWidgets);
      expect(session.wizards.single.editing, isNull);
      expect(session.wizards.single.forceDefault, isFalse);
      await tester.tap(_key('provider-wizard-cancel'));
      await tester.pumpAndSettle();
      expect(_key('provider-wizard'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('the empty state opens the wizard too', (tester) async {
      store.user = {};
      await openPage(tester);

      await tester.tap(_key('providers-empty-add'));
      await tester.pumpAndSettle();

      expect(_key('provider-wizard'), findsOneWidget);
      await tester.tap(_key('provider-wizard-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('Edit opens the wizard for the row: title and the row as '
        'the editing entry', (tester) async {
      await openPage(tester);

      await tester.tap(_key('providers-edit-local'));
      await tester.pumpAndSettle();

      expect(_key('provider-wizard'), findsOneWidget);
      expect(find.text('Edit provider local'), findsOneWidget);
      expect(session.wizards.single.editing!.id, 'local');
      await tester.tap(_key('provider-wizard-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('Edit is inactive with the Remove hint when the provider '
        'lives in several layers', (tester) async {
      store.projectLocal = {
        'providers': {
          'local': {'base_url': 'http://localhost:9999/v1'},
        },
      };
      await openPage(tester);

      expect(
        tester.widget<CodeLabButton>(_key('providers-edit-local')).onPressed,
        isNull,
      );
      expect(
        find.byTooltip(
          'This provider is defined in several config files. Change it there.',
        ),
        findsWidgets,
      );
      await tearDownApp(tester);
    });

    testWidgets('a saved provider: the page reloads and shows the saved '
        'banner', (tester) async {
      await openPage(tester);
      final before = store.snapshots;

      await tester.tap(_key('providers-add'));
      await tester.pumpAndSettle();
      await tester.tap(_key('provider-wizard-preset-custom-openai'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(_key('provider-wizard-next'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _key('provider-wizard-base-url-field'),
        'https://llm.example/v1',
      );
      await tester.tap(_key('provider-wizard-next'));
      await tester.pumpAndSettle();
      await tester.tap(_key('provider-wizard-key-none'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(_key('provider-wizard-next'));
      await tester.pump(const Duration(milliseconds: 100));
      session.wizardCheck.respond(
        const CheckOk([RemoteModel('m1', contextWindow: 8000)]),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(_key('provider-wizard-model-m1'));
      await tester.pumpAndSettle();
      await tester.tap(_key('provider-wizard-save'));
      await tester.pumpAndSettle();
      // Перечитывание снимка после закрытия диалога идёт через
      // `SharedPreferences` (профиль по умолчанию): нужны реальные тики.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(_key('provider-wizard'), findsNothing);
      expect(store.snapshots, greaterThan(before));
      expect(_key('providers-banner'), findsOneWidget);
      // Агент в этом тесте не запущен и сбоя старта не было: баннер говорит,
      // что агент возьмёт провайдера при следующем старте, и без кнопки
      // (Q22, B2.8). «Retry» появляется только после сбоя старта.
      expect(
        find.text('Saved. The agent uses it the next time it starts.'),
        findsOneWidget,
      );
      expect(_key('providers-banner-connect'), findsNothing);
      expect(_key('providers-banner-retry'), findsNothing);
      expect(_key('providers-row-llm-example'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('a remote http provider shows the warning, Check stays on', (
      tester,
    ) async {
      store.user = {
        'providers': {
          'remote': providerMap(
            baseUrl: 'http://api.example.com/v1',
            env: 'REMOTE_KEY',
          ),
        },
      };
      await openPage(tester);

      expect(_key('providers-unencrypted-remote'), findsOneWidget);
      expect(
        find.text('The key is sent unencrypted to api.example.com.'),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });
  });

  group('check availability', () {
    testWidgets('an unsupported kind has Check off and the hint', (
      tester,
    ) async {
      store.user = {
        'providers': {
          'g': providerMap(kind: 'gemini', baseUrl: null, env: 'G'),
        },
      };
      await openPage(tester);

      expect(
        tester.widget<CodeLabButton>(_key('providers-check-g')).onPressed,
        isNull,
      );
      expect(
        find.text('Check is not available for gemini providers yet.'),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('a removal that keeps a shared key says so', (tester) async {
      store.onApply = () {
        store.user['mcp'] = {'x': r'${secret:codelab/anthropic}'};
      };
      await openPage(tester);

      await tester.tap(_key('providers-remove-anthropic'));
      await tester.pumpAndSettle();
      await tester.tap(_key('providers-remove-new-default'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('local/qwen').last);
      await tester.pumpAndSettle();
      await tester.tap(_key('providers-remove-confirm'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('is kept because other settings'),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });
  });

  group('literal key', () {
    testWidgets('Check is disabled and the hint sits under the row', (
      tester,
    ) async {
      store.user = {
        'providers': {
          'lit': {...providerMap(), 'api_key': leakMarker},
          'other': providerMap(),
        },
      };
      await openPage(tester);

      expect(
        tester.widget<CodeLabButton>(_key('providers-check-lit')).onPressed,
        isNull,
      );
      expect(
        tester.widget<CodeLabButton>(_key('providers-check-other')).onPressed,
        isNotNull,
      );
      expect(
        find.text(
          'The key is written in config.yaml. Move it to the secret store: '
          'codelab secret migrate.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining(leakMarker), findsNothing);
      await tearDownApp(tester);
    });
  });

  group('actions', () {
    testWidgets('Check with a wrong key shows unauthorized and never the '
        'key', (tester) async {
      session.checkResult = () async => const CheckFailure(
        ProviderCheckFailure(
          kind: ProviderCheckFailureKind.unauthorized,
          statusCode: 401,
          message: 'x',
        ),
      );
      await openPage(tester);
      expect(
        find.descendant(
          of: _key('providers-status-anthropic'),
          matching: find.text('not checked'),
        ),
        findsOneWidget,
      );

      await tester.tap(_key('providers-check-anthropic'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: _key('providers-status-anthropic'),
          matching: find.text('unauthorized'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining(leakMarker), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('Remove of the default provider asks for the new default, '
        'keeps the delete-key box on and writes once', (tester) async {
      await openPage(tester);

      await tester.tap(_key('providers-remove-anthropic'));
      await tester.pumpAndSettle();

      expect(find.text('Remove provider anthropic?'), findsOneWidget);
      expect(_key('providers-remove-confirm'), findsOneWidget);
      expect(
        tester.widget<Checkbox>(_key('providers-remove-delete-key')).checked,
        isTrue,
      );
      await tester.tap(_key('providers-remove-new-default'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('local/qwen').last);
      await tester.pumpAndSettle();
      await tester.tap(_key('providers-remove-confirm'));
      await tester.pumpAndSettle();

      expect(store.applied, hasLength(1));
      expect(store.applied.single.edits, [
        const RemoveTable('providers.anthropic'),
        const SetValue('agent.default_model', 'local/qwen'),
      ]);
      expect(session.deleted, ['codelab/anthropic']);
      expect(_key('providers-banner'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('Cancel in the Remove dialog writes nothing', (tester) async {
      await openPage(tester);

      await tester.tap(_key('providers-remove-local'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('providers-remove-delete-key')),
        findsNothing,
      );
      await tester.tap(_key('providers-remove-cancel'));
      await tester.pumpAndSettle();

      expect(store.applied, isEmpty);
      await tearDownApp(tester);
    });

    testWidgets('the last provider has Remove disabled with the hint', (
      tester,
    ) async {
      store.user = {
        'providers': {'only': providerMap()},
      };
      await openPage(tester);

      expect(
        tester.widget<CodeLabButton>(_key('providers-remove-only')).onPressed,
        isNull,
      );
      expect(
        find.byTooltip(
          'The agent needs at least one provider. Add another provider first.',
        ),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('choosing another Default model writes it', (tester) async {
      await openPage(tester);

      await tester.tap(_key('providers-default-model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('local/qwen').last);
      await tester.pumpAndSettle();

      expect(store.applied.single.edits, [
        const SetValue('agent.default_model', 'local/qwen'),
      ]);
      await tearDownApp(tester);
    });

    testWidgets('a conflict shows the banner', (tester) async {
      await openPage(tester);
      store.nextOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);

      await tester.tap(_key('providers-default-model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('local/qwen').last);
      await tester.pumpAndSettle();

      expect(_key('providers-banner'), findsOneWidget);
      expect(find.textContaining('changed on disk'), findsOneWidget);
      await tearDownApp(tester);
    });
  });
}
