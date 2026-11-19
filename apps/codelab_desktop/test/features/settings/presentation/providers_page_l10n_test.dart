// Красные тесты задачи 4.1 change `add-desktop-localization`: страница
// «Providers» на русском и английском, смена языка на странице (spec
// app-settings «Страница «Providers»», «Локализация интерфейса app», сценарии
// «Смена языка применяется сразу на странице настроек», «Уже показанные
// ошибки и InfoBar пересобираются», «Команда в переведённой фразе»;
// design.md D5, D6, D7, D9, D12).
//
// Проверяется то, что видит пользователь: подписи строк и источники ключа
// (одним сообщением с плейсхолдерами, без склейки `'In $backendId as '`),
// итоги проверок, InfoBar «Read-only», исходы удаления провайдера с командой
// `codelab secret delete <имя>` без изменений, отказы, ошибки записи конфига,
// баннеры после мастера. Разовые сообщения (исходы удаления и записи) хранятся
// в состоянии Cubit-а типизированно, а их текст собирает presentation: они
// пересобираются при смене языка как текст виджета (D5). Имена провайдеров,
// секретов и переменных, пути и команды от языка не зависят (D7).
//
// Ожидания на `en` — прежние строки (зелёные); на `ru` — красные до задачи
// 4.2. Русские строки — по глоссарию («провайдер», «ключ», «модель по
// умолчанию», «хранилище секретов», «только чтение», «проверить», «изменить»,
// «удалить», «источник»); остальные — вне глоссария (отчёт задачи 4.1).
// Сообщения с меткой security (ключ открытым текстом, ключ уходит без
// шифрования, откат ключа) вычитывает пользователь (задача 4.3, D14).

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/language/app_language_cubit.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_provider_settings.dart';
import '../../../support/in_memory_profile_store.dart';
import '../../../support/l10n_mix.dart';
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

const _own = ConnectionProfile.stdio(
  id: 'own',
  label: 'Own',
  command: 'codelab-agent',
  args: ['serve', '--stdio'],
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
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

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

  setUp(() {
    store = FakeAgentConfigStore(user: _two());
    session = FakeProviderSettingsSession(
      store,
      secrets: {'codelab/anthropic': leakMarker},
    );
  });

  /// Страница «Providers» на языке [locale]. С [connected] агент стартует
  /// (профиль `own` — наш stdio-агент), и мастер сообщает о записи баннером
  /// «агент уже работает».
  Future<CodeLabTestBinding> openPage(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ConnectionProfile? defaultProfile,
    bool connected = false,
  }) async {
    final profile = connected ? _own : defaultProfile;
    final binding = CodeLabTestBinding(
      project: '/workspace',
      locale: locale,
      stdioDefault: false,
      profileStore: InMemoryProfileStore([?profile]),
      preferences: {'codelab.connection.default_profile': ?profile?.id},
      environment: {'HOME': '/home/u'},
      settingsPages: _pages,
      stdioTransportFactory: (_) => FakeAcpTransport(),
      providerSettingsOpener: (access, env) async => session,
    );
    await tester.pumpWidget(
      binding.bootstrap(child: CodeLabApp(startOnLaunch: connected)),
    );
    await tester.pump();
    if (connected) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
    await tester.pumpAndSettle();
    await tester.tap(_key(SettingsPage.providers.navKey));
    await tester.pumpAndSettle();
    return binding;
  }

  Future<void> selectLanguage(
    WidgetTester tester,
    CodeLabTestBinding binding,
    AppLanguagePreference preference,
  ) async {
    await tester.runAsync(
      () => binding.scope.resolve<AppLanguageCubit>().select(preference),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }

  String textsOf(WidgetTester tester, Finder scope) => tester
      .widgetList<Text>(find.descendant(of: scope, matching: find.byType(Text)))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join(' | ');

  /// Удаляет провайдера [id] через диалог подтверждения; [newDefault] — модель
  /// для «New default model».
  Future<void> removeProvider(
    WidgetTester tester,
    String id, {
    String? newDefault,
  }) async {
    await tester.tap(_key('providers-remove-$id'));
    await tester.pumpAndSettle();
    if (newDefault != null) {
      await tester.tap(_key('providers-remove-new-default'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(newDefault).last);
      await tester.pumpAndSettle();
    }
    await tester.tap(_key('providers-remove-confirm'));
    await tester.pumpAndSettle();
  }

  /// Мастер: custom-пресет, адрес, способ ключа [keyOption], модель m1, «Save».
  Future<void> walkWizard(
    WidgetTester tester, {
    String keyOption = 'none',
    String? keyValue,
  }) async {
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
    await tester.tap(_key('provider-wizard-key-$keyOption'));
    await tester.pump(const Duration(milliseconds: 100));
    if (keyValue != null) {
      await tester.enterText(_key('provider-wizard-key-field'), keyValue);
    }
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
    // `SharedPreferences`: нужны реальные тики.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('en: прежние строки страницы', () {
    testWidgets('заголовок, строки, подписи кнопок и подвал', (tester) async {
      await openPage(tester);

      expect(find.text('Providers'), findsWidgets);
      expect(find.text('Add provider'), findsOneWidget);
      expect(find.text('Key storage: file'), findsOneWidget);
      expect(find.text('writable'), findsOneWidget);
      expect(find.text('Configured providers'), findsOneWidget);
      expect(
        find.text('anthropic · Anthropic · Key: in file · 1 model'),
        findsOneWidget,
      );
      expect(find.text('Config file: ~/.codelab/config.yaml'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('удаление с ключом: баннер, команда не нужна', (tester) async {
      await openPage(tester);

      await removeProvider(tester, 'anthropic', newDefault: 'local/qwen');

      expect(
        textsOf(tester, _key('providers-banner')),
        'Provider anthropic removed. Its stored key was deleted.',
      );
      await tearDownApp(tester);
    });
  });

  group('ru: страница «Providers»', () {
    testWidgets('заголовок, кнопка, «Default model», «Key storage», '
        'подвал и пояснение', (tester) async {
      await openPage(tester, locale: const Locale('ru'));

      expect(find.text(ru.settingsPageProvidersTitle), findsWidgets);
      expect(find.text('Добавить провайдера'), findsOneWidget);
      expect(find.text('Модель по умолчанию'), findsOneWidget);
      expect(find.text('Используется новыми сессиями.'), findsOneWidget);
      expect(find.text('Хранилище ключей: file'), findsOneWidget);
      expect(
        find.text(
          'Читаются только имена и наличие ключей — значения никогда не '
          'попадают в приложение',
        ),
        findsOneWidget,
      );
      expect(find.text('запись разрешена'), findsOneWidget);
      // security: ключи лежат в открытом файле.
      expect(
        find.text(
          'Ключи хранятся в открытом файле ~/.codelab/secrets.yaml '
          '(режим 0600).',
        ),
        findsOneWidget,
      );
      expect(find.text('Настроенные провайдеры'), findsOneWidget);
      expect(
        find.text('Файл конфигурации: ~/.codelab/config.yaml'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'При удалении запрашивается подтверждение с флажком «Также удалить '
          'сохранённый ключ»; при удалении провайдера по умолчанию '
          'запрашивается «Новая модель по умолчанию».',
        ),
        findsOneWidget,
      );
      expect(find.text('Add provider'), findsNothing);
      expect(find.text('Configured providers'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('«Choose a model»: подсказка выбора, когда модели по '
        'умолчанию нет в списке', (tester) async {
      store.user = {
        'agent': {'default_model': 'missing/model'},
        'providers': _two()['providers'],
      };
      await openPage(tester, locale: const Locale('ru'));

      expect(find.text('Выберите модель'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('строка провайдера: тег по умолчанию, подпись с источником '
        'ключа одним сообщением, кнопки и тег проверки', (tester) async {
      await openPage(tester, locale: const Locale('ru'));

      expect(
        find.text('anthropic · Anthropic · Ключ: в хранилище file · 1 модель'),
        findsOneWidget,
      );
      expect(
        find.text(
          'local · OpenAI-compatible · http://localhost:11434/v1 · Без ключа · '
          '1 модель',
        ),
        findsOneWidget,
      );
      final row = _key('providers-row-anthropic');
      expect(
        find.descendant(of: row, matching: find.text('По умолчанию')),
        findsOneWidget,
      );
      for (final label in const ['Проверить', 'Изменить', 'Удалить']) {
        expect(
          find.descendant(of: row, matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
      expect(
        find.descendant(
          of: _key('providers-status-anthropic'),
          matching: find.text('не проверялся'),
        ),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('раскрытая строка: «Ключ», «Последняя проверка», «Источник»; '
        'источник ключа — одно сообщение с именем секрета', (tester) async {
      await openPage(tester, locale: const Locale('ru'));

      await tester.tap(_key('providers-row-anthropic'));
      await tester.pumpAndSettle();

      expect(find.text('Ключ'), findsOneWidget);
      expect(find.text('Последняя проверка'), findsOneWidget);
      expect(find.text('Источник'), findsOneWidget);
      expect(find.text('Ещё не проверялся'), findsOneWidget);
      expect(
        find.textContaining(
          'В file как «codelab/anthropic»',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('Last check'), findsNothing);
      expect(
        find.textContaining('In file as', findRichText: true),
        findsNothing,
      );
      await tearDownApp(tester);
    });

    testWidgets('источник ключа: переменная окружения, секрета нет, ключ '
        'открытым текстом (security)', (tester) async {
      store.user = {
        'providers': {
          'envp': providerMap(env: 'REMOTE_KEY'),
          'gone': providerMap(secret: 'codelab/gone'),
          'lit': {...providerMap(), 'api_key': leakMarker},
        },
      };
      await openPage(tester, locale: const Locale('ru'));

      await tester.tap(_key('providers-row-envp'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Переменная окружения REMOTE_KEY (не задана)',
          findRichText: true,
        ),
        findsOneWidget,
      );
      await tester.tap(_key('providers-row-envp'));
      await tester.tap(_key('providers-row-gone'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Нет в file как «codelab/gone»',
          findRichText: true,
        ),
        findsOneWidget,
      );
      await tester.tap(_key('providers-row-gone'));
      await tester.tap(_key('providers-row-lit'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'В файле конфигурации (открытым текстом)',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.textContaining(leakMarker), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('подсказки под строкой: литеральный ключ, ключ уходит без '
        'шифрования, вид без проверки (security)', (tester) async {
      store.user = {
        'providers': {
          'lit': {...providerMap(), 'api_key': leakMarker},
          'remote': providerMap(
            baseUrl: 'http://api.example.com/v1',
            env: 'REMOTE_KEY',
          ),
          'g': providerMap(kind: 'gemini', baseUrl: null, env: 'G'),
        },
      };
      await openPage(tester, locale: const Locale('ru'));

      expect(
        find.text(
          'Ключ записан в config.yaml. Перенесите его в хранилище секретов: '
          'codelab secret migrate.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Ключ отправляется в открытом виде на api.example.com.'),
        findsOneWidget,
      );
      expect(
        find.text('Проверка для провайдеров gemini пока недоступна.'),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('количество моделей склоняется (2 модели, 5 моделей)', (
      tester,
    ) async {
      store.user = {
        'providers': {
          'two': providerMap(models: ['a', 'b'], env: 'K'),
          'five': providerMap(models: ['a', 'b', 'c', 'd', 'e'], env: 'K'),
        },
      };
      await openPage(tester, locale: const Locale('ru'));

      expect(find.textContaining('· 2 модели'), findsOneWidget);
      expect(find.textContaining('· 5 моделей'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('провайдер из файла проекта: «определён в <путь>», без '
        '«Изменить» и «Удалить»', (tester) async {
      store.project = {
        'providers': {
          'team': providerMap(models: ['big']),
        },
      };
      await openPage(tester, locale: const Locale('ru'));

      expect(
        find.textContaining(
          '· определён в ${FakeAgentConfigStore.projectPath}',
        ),
        findsOneWidget,
      );
      expect(_key('providers-edit-team'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('пустой конфиг: сообщение и кнопка добавления', (tester) async {
      store.user = {};
      await openPage(tester, locale: const Locale('ru'));

      expect(
        find.text(
          'Провайдеров пока нет. Встроенному агенту нужен хотя бы один, чтобы '
          'выполнить ход.',
        ),
        findsOneWidget,
      );
      expect(find.text('Добавить провайдера'), findsWidgets);
      await tearDownApp(tester);
    });

    testWidgets('хранилище только для чтения: тег и причина бэкенда как есть', (
      tester,
    ) async {
      store.backend = const SecretBackendInfo(
        id: 'env',
        writable: false,
        unavailableReason: 'OS key stores are not available yet',
      );
      await openPage(tester, locale: const Locale('ru'));

      expect(find.text('Хранилище ключей: env'), findsOneWidget);
      expect(find.text('только чтение'), findsOneWidget);
      expect(
        find.textContaining('OS key stores are not available yet'),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });
  });

  group('ru: InfoBar «Read-only» и нечитаемый конфиг', () {
    testWidgets('WebSocket-агент: заголовок без пути и запроса, подсказка с '
        'командами', (tester) async {
      await openPage(
        tester,
        locale: const Locale('ru'),
        defaultProfile: _remote,
      );

      final text = textsOf(tester, _key('providers-read-only'));
      expect(
        text,
        contains('Только чтение: агент работает на wss://devbox:7420.'),
      );
      expect(
        text,
        contains(
          'Изменить провайдеров и MCP можно на том хосте: codelab provider '
          'add, codelab mcp add, codelab config set.',
        ),
      );
      expect(text, isNot(contains('/acp')));
      expect(find.textContaining(leakMarker), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('сторонний stdio-агент: имя агента — плейсхолдер', (
      tester,
    ) async {
      await openPage(
        tester,
        locale: const Locale('ru'),
        defaultProfile: _foreign,
      );

      expect(
        find.textContaining('Настройками провайдеров управляет python.'),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('нечитаемый config.yaml: рамка по-русски, проблемы '
        'загрузчика как есть', (tester) async {
      store.omitUserLayer = true;
      await openPage(tester, locale: const Locale('ru'));

      final text = textsOf(tester, _key('providers-unreadable'));
      expect(
        text,
        contains(
          'Не удаётся прочитать конфигурацию агента. Исправьте или удалите '
          'файл; CodeLab его не перезапишет.',
        ),
      );
      expect(
        text,
        contains('Пользовательский config.yaml не удаётся прочитать.'),
      );
      await tearDownApp(tester);
    });
  });

  group('ru: проверка ключа', () {
    testWidgets('отказ: тег и «Последняя проверка» с кодом HTTP; ключ нигде '
        'не виден', (tester) async {
      session.checkResult = () async => const CheckFailure(
        ProviderCheckFailure(
          kind: ProviderCheckFailureKind.unauthorized,
          statusCode: 401,
          message: 'x',
        ),
      );
      await openPage(tester, locale: const Locale('ru'));

      await tester.tap(_key('providers-check-anthropic'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: _key('providers-status-anthropic'),
          matching: find.text('не авторизован'),
        ),
        findsOneWidget,
      );
      await tester.tap(_key('providers-row-anthropic'));
      await tester.pumpAndSettle();
      expect(find.textContaining('не авторизован (HTTP 401)'), findsOneWidget);
      expect(find.textContaining(leakMarker), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('успех: «успешно, N модели»', (tester) async {
      session.checkResult = () async =>
          const CheckOk([RemoteModel('a'), RemoteModel('b')]);
      await openPage(tester, locale: const Locale('ru'));

      await tester.tap(_key('providers-check-local'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: _key('providers-status-local'),
          matching: find.text('успешно, 2 модели'),
        ),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('ключа нет: запрос не отправляется, тег «Ключ: нет»', (
      tester,
    ) async {
      store.user = {
        'providers': {
          'team': providerMap(secret: 'codelab/team'),
          'other': providerMap(env: 'K'),
        },
      };
      await openPage(tester, locale: const Locale('ru'));

      await tester.tap(_key('providers-check-team'));
      await tester.pumpAndSettle();

      expect(session.checks, isEmpty);
      expect(
        find.descendant(
          of: _key('providers-status-team'),
          matching: find.text('Ключ: нет'),
        ),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });
  });

  group('ru: диалог удаления и подсказки кнопок', () {
    testWidgets('«Remove provider <id>?»: пояснение, флажок ключа, выбор '
        'новой модели', (tester) async {
      await openPage(tester, locale: const Locale('ru'));

      await tester.tap(_key('providers-remove-anthropic'));
      await tester.pumpAndSettle();

      expect(find.text('Удалить провайдера anthropic?'), findsOneWidget);
      expect(
        find.text(
          'Провайдер удаляется из файла конфигурации. Сессии, использующие его '
          'модели, продолжают работать, пока агент не перезагрузится.',
        ),
        findsOneWidget,
      );
      expect(find.text('Также удалить сохранённый ключ'), findsOneWidget);
      expect(find.text('Новая модель по умолчанию'), findsOneWidget);
      expect(find.text('Выберите модель'), findsOneWidget);
      expect(find.text('Отмена'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('providers-remove-confirm'),
          matching: find.text('Удалить'),
        ),
        findsOneWidget,
      );
      await tester.tap(_key('providers-remove-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('последний провайдер: «Удалить» недоступна, подсказка на '
        'русском', (tester) async {
      store.user = {
        'providers': {'only': providerMap(env: 'K')},
      };
      await openPage(tester, locale: const Locale('ru'));

      expect(
        tester.widget<CodeLabButton>(_key('providers-remove-only')).onPressed,
        isNull,
      );
      expect(
        find.byTooltip(
          'Агенту нужен хотя бы один провайдер. Сначала добавьте другого.',
        ),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('«Изменить» недоступна: провайдер в нескольких файлах', (
      tester,
    ) async {
      store.projectLocal = {
        'providers': {
          'local': {'base_url': 'http://localhost:9999/v1'},
        },
      };
      await openPage(tester, locale: const Locale('ru'));

      expect(
        find.byTooltip(
          'Этот провайдер определён в нескольких файлах конфигурации. '
          'Измените его там.',
        ),
        findsWidgets,
      );
      await tearDownApp(tester);
    });
  });

  group('ru: исходы удаления и записи (типизированные сообщения, D5)', () {
    testWidgets('ключ удалён вместе с провайдером', (tester) async {
      await openPage(tester, locale: const Locale('ru'));

      await removeProvider(tester, 'anthropic', newDefault: 'local/qwen');

      expect(
        textsOf(tester, _key('providers-banner')),
        'Провайдер anthropic удалён. Его сохранённый ключ удалён.',
      );
      await tearDownApp(tester);
    });

    testWidgets('провайдер без собственного ключа: короткий итог', (
      tester,
    ) async {
      await openPage(tester, locale: const Locale('ru'));

      await removeProvider(tester, 'local');

      expect(
        textsOf(tester, _key('providers-banner')),
        'Провайдер local удалён.',
      );
      await tearDownApp(tester);
    });

    testWidgets('ключ нужен другим настройкам: остаётся, имя секрета — '
        'плейсхолдер', (tester) async {
      store.onApply = () {
        store.user['mcp'] = {'x': r'${secret:codelab/anthropic}'};
      };
      await openPage(tester, locale: const Locale('ru'));

      await removeProvider(tester, 'anthropic', newDefault: 'local/qwen');

      expect(
        textsOf(tester, _key('providers-banner')),
        'Провайдер anthropic удалён. Сохранённый ключ «codelab/anthropic» '
        'оставлен, потому что его используют другие настройки.',
      );
      await tearDownApp(tester);
    });

    testWidgets('ключ удалить не удалось: команда `codelab secret delete '
        '<имя>` без изменений (security)', (tester) async {
      session.deletion = SecretDeletion.failed;
      await openPage(tester, locale: const Locale('ru'));

      await removeProvider(tester, 'anthropic', newDefault: 'local/qwen');

      expect(
        textsOf(tester, _key('providers-banner')),
        'Провайдер anthropic удалён, но его сохранённый ключ удалить не '
        'удалось. Удалите его командой: codelab secret delete '
        'codelab/anthropic',
      );
      await tearDownApp(tester);
    });

    testWidgets('модель по умолчанию изменена', (tester) async {
      await openPage(tester, locale: const Locale('ru'));

      await tester.tap(_key('providers-default-model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('local/qwen').last);
      await tester.pumpAndSettle();

      expect(
        textsOf(tester, _key('providers-banner')),
        'Модель по умолчанию сохранена.',
      );
      await tearDownApp(tester);
    });

    testWidgets('конфиг изменился на диске: конфликт записи', (tester) async {
      await openPage(tester, locale: const Locale('ru'));
      store.nextOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);

      await tester.tap(_key('providers-default-model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('local/qwen').last);
      await tester.pumpAndSettle();

      expect(
        textsOf(tester, _key('providers-banner')),
        'Конфигурация изменилась на диске, поэтому ничего не сохранено. '
        'Страница перезагружена; проверьте её и повторите попытку.',
      );
      await tearDownApp(tester);
    });

    testWidgets('конфиг отклонён: проблемы загрузчика как есть', (
      tester,
    ) async {
      await openPage(tester, locale: const Locale('ru'));
      store.nextOutcome = ConfigRejected([
        ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'agent.default_model',
          source: FakeAgentConfigStore.userPath,
          message: 'unknown model',
        ),
      ]);

      await tester.tap(_key('providers-default-model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('local/qwen').last);
      await tester.pumpAndSettle();

      expect(
        textsOf(tester, _key('providers-banner')),
        'Конфигурация не сохранена: agent.default_model: unknown model',
      );
      await tearDownApp(tester);
    });

    testWidgets('секрет значением в конфиге: путь ключа — плейсхолдер '
        '(security)', (tester) async {
      await openPage(tester, locale: const Locale('ru'));
      store.nextOutcome = const ConfigInlineSecret(
        key: 'providers.local.api_key',
        suggestedSecretName: 'codelab/local',
      );

      await tester.tap(_key('providers-default-model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('local/qwen').last);
      await tester.pumpAndSettle();

      expect(
        textsOf(tester, _key('providers-banner')),
        'Конфигурация не сохранена: providers.local.api_key не должен '
        'содержать секрет в открытом виде.',
      );
      await tearDownApp(tester);
    });

    testWidgets('отказ удаления: модель по умолчанию задана в файле, '
        'в который CodeLab не пишет', (tester) async {
      store.project = {
        'agent': {'default_model': 'anthropic/m'},
      };
      await openPage(tester, locale: const Locale('ru'));

      await removeProvider(tester, 'anthropic', newDefault: 'local/qwen');

      expect(
        textsOf(tester, _key('providers-banner')),
        'Модель по умолчанию задана в файле, в который CodeLab не пишет. '
        'Сначала измените её там.',
      );
      await tearDownApp(tester);
    });
  });

  group('ru: баннер после мастера', () {
    testWidgets('агент не запущен: «Saved. The agent uses it the next time '
        'it starts.»', (tester) async {
      await openPage(tester, locale: const Locale('ru'));

      await walkWizard(tester);

      expect(
        find.text(
          'Сохранено. Агент использует провайдера при следующем запуске.',
        ),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('агент работает: «Провайдер <id> сохранён.»', (tester) async {
      await openPage(tester, locale: const Locale('ru'), connected: true);

      await walkWizard(tester);

      expect(
        textsOf(tester, _key('providers-banner')),
        'Провайдер llm-example сохранён.',
      );
      await tearDownApp(tester);
    });

    testWidgets('ключ заменён: напоминание про «Перезапустить агента»', (
      tester,
    ) async {
      session.secrets['codelab/llm-example'] = 'old-value';
      await openPage(tester, locale: const Locale('ru'), connected: true);

      await walkWizard(tester, keyOption: 'replace', keyValue: leakMarker);

      expect(
        textsOf(tester, _key('providers-banner')),
        'Провайдер llm-example сохранён. Новый ключ вступит в силу после '
        '«Перезапустить агента» (Настройки › Подключение).',
      );
      expect(find.textContaining(leakMarker), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('мастер из пустого состояния открывается на русском', (
      tester,
    ) async {
      store.user = {};
      await openPage(tester, locale: const Locale('ru'));

      await tester.tap(_key('providers-empty-add'));
      await tester.pumpAndSettle();

      expect(find.text('Добавить провайдера'), findsWidgets);
      expect(_key('provider-wizard'), findsOneWidget);
      await tester.tap(_key('provider-wizard-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });
  });

  group('смена языка на странице «Providers» (spec: «Уже показанные ошибки '
      'и InfoBar пересобираются»)', () {
    testWidgets('только чтение: InfoBar пересобирается, адрес без пути', (
      tester,
    ) async {
      final binding = await openPage(tester, defaultProfile: _remote);
      expect(
        textsOf(tester, _key('providers-read-only')),
        contains('Read-only: this agent runs on wss://devbox:7420.'),
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        textsOf(tester, _key('providers-read-only')),
        contains('Только чтение: агент работает на wss://devbox:7420.'),
      );
      expect(find.text('Providers'), findsNothing);
      await expectNoStaleLanguage(tester, from: en, to: ru);

      await selectLanguage(tester, binding, AppLanguagePreference.en);
      expect(
        textsOf(tester, _key('providers-read-only')),
        contains('Read-only: this agent runs on wss://devbox:7420.'),
      );
      await expectNoStaleLanguage(tester, from: ru, to: en);
      await tearDownApp(tester);
    });

    testWidgets('исход удаления провайдера `anthropic`: тот же id и та же '
        'команда на русском', (tester) async {
      session.deletion = SecretDeletion.failed;
      final binding = await openPage(tester);
      await removeProvider(tester, 'anthropic', newDefault: 'local/qwen');
      expect(
        textsOf(tester, _key('providers-banner')),
        'Provider anthropic removed, but its stored key could not be deleted. '
        'Delete it with: codelab secret delete codelab/anthropic',
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        textsOf(tester, _key('providers-banner')),
        'Провайдер anthropic удалён, но его сохранённый ключ удалить не '
        'удалось. Удалите его командой: codelab secret delete '
        'codelab/anthropic',
      );
      await expectNoStaleLanguage(tester, from: en, to: ru);

      await selectLanguage(tester, binding, AppLanguagePreference.en);
      expect(
        textsOf(tester, _key('providers-banner')),
        contains('Provider anthropic removed'),
      );
      await tearDownApp(tester);
    });

    testWidgets('ошибка записи конфига остаётся на странице', (tester) async {
      final binding = await openPage(tester);
      store.nextOutcome = const ConfigInlineSecret(
        key: 'providers.local.api_key',
        suggestedSecretName: 'codelab/local',
      );
      await tester.tap(_key('providers-default-model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('local/qwen').last);
      await tester.pumpAndSettle();
      expect(
        textsOf(tester, _key('providers-banner')),
        'The config was not saved: providers.local.api_key must not hold a '
        'literal secret.',
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        textsOf(tester, _key('providers-banner')),
        'Конфигурация не сохранена: providers.local.api_key не должен '
        'содержать секрет в открытом виде.',
      );
      await expectNoStaleLanguage(tester, from: en, to: ru);
      await tearDownApp(tester);
    });

    testWidgets('строки, итог проверки и подвал пересобираются; Cubit '
        'не перечитывает конфиг', (tester) async {
      session.checkResult = () async =>
          const CheckOk([RemoteModel('a'), RemoteModel('b')]);
      final binding = await openPage(tester);
      await tester.tap(_key('providers-check-local'));
      await tester.pumpAndSettle();
      final snapshots = store.snapshots;

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        find.text('anthropic · Anthropic · Ключ: в хранилище file · 1 модель'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('providers-status-local'),
          matching: find.text('успешно, 2 модели'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('Файл конфигурации: ~/.codelab/config.yaml'),
        findsOneWidget,
      );
      expect(store.snapshots, snapshots);
      expect(store.applied, isEmpty);
      await expectNoStaleLanguage(tester, from: en, to: ru);

      await selectLanguage(tester, binding, AppLanguagePreference.en);
      expect(
        find.text('anthropic · Anthropic · Key: in file · 1 model'),
        findsOneWidget,
      );
      await expectNoStaleLanguage(tester, from: ru, to: en);
      await tearDownApp(tester);
    });

    testWidgets('открытый диалог удаления переводится, выбранная модель и '
        'флажок сохраняются', (tester) async {
      final binding = await openPage(tester);
      await tester.tap(_key('providers-remove-anthropic'));
      await tester.pumpAndSettle();
      await tester.tap(_key('providers-remove-delete-key'));
      await tester.pumpAndSettle();
      await tester.tap(_key('providers-remove-new-default'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('local/qwen').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Checkbox>(_key('providers-remove-delete-key')).checked,
        isFalse,
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(find.text('Удалить провайдера anthropic?'), findsOneWidget);
      expect(find.text('Также удалить сохранённый ключ'), findsOneWidget);
      expect(find.text('Новая модель по умолчанию'), findsOneWidget);
      expect(
        tester.widget<Checkbox>(_key('providers-remove-delete-key')).checked,
        isFalse,
      );
      expect(find.text('local/qwen'), findsWidgets);
      await expectNoStaleLanguage(tester, from: en, to: ru);
      await tester.tap(_key('providers-remove-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('нечитаемый конфиг: рамка пересобирается', (tester) async {
      store.omitUserLayer = true;
      final binding = await openPage(tester);
      expect(
        textsOf(tester, _key('providers-unreadable')),
        contains('The user config.yaml cannot be read.'),
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        textsOf(tester, _key('providers-unreadable')),
        contains('Пользовательский config.yaml не удаётся прочитать.'),
      );
      await expectNoStaleLanguage(tester, from: en, to: ru);
      await tearDownApp(tester);
    });
  });
}
