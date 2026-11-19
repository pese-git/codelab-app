// Красные тесты задачи 4.1 change `add-desktop-localization`: страница
// «Connection» на русском и английском, смена языка на странице (spec
// app-settings «Список профилей на странице «Connection»», «Блок «Behavior»»,
// «Локализация интерфейса app», сценарии «Смена языка применяется сразу на
// странице настроек», «Уже показанные ошибки и InfoBar пересобираются»,
// «Команда в переведённой фразе»; design.md D5, D6 («Подпись профиля
// встроенного агента»), D7, D9, D12).
//
// Проверяется то, что видит пользователь: строки профилей и их метки
// (`Default`/`Current`/`Selected`), бейджи попытки, источник токена, InfoBar
// записи `default` и ошибки чтения `profiles.json`, блок «Behavior»,
// подтверждения удаления. Ключи тестов и команды (`codelab profiles remove
// default`, `codelab secret delete <имя>`), имена переменных и секретов, пути
// и адреса `ws://` от языка не зависят (D7). Ожидания на `en` — прежние
// строки: эти проверки зелёные; на `ru` — красные до задачи 4.2.
//
// Русские строки — по глоссарию («подключение», «профиль подключения»,
// «встроенный агент», «перезапустить агента», «только чтение», «Выбрано»,
// «Подключено», «Сбой», «Подключение…»); остальные — вне глоссария и
// перечислены в отчёте задачи 4.1. Сообщения с меткой security вычитывает
// пользователь (задача 4.3, D14).

import 'dart:async';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/language/app_language_cubit.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/features/settings/application/profiles_unavailable.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart'
    show
        CodeLabShellCubit,
        CodeLabStdioTransportFactory,
        CodeLabWebSocketTransportFactory;
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_profile_secrets.dart';
import '../../../support/in_memory_profile_store.dart';
import '../../../support/l10n_mix.dart';
import '../../../support/test_app_scope.dart';
import '../../workbench/application/shell_cubit_characterization/harness.dart'
    show ThrowingStartTransport;

const _withConnection = SettingsPages(available: {SettingsPage.connection});

const _dev = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: 'codelab-agent',
  args: ['serve', '--stdio'],
);

final _devbox = ConnectionProfile.webSocket(
  id: 'devbox',
  label: 'Devbox',
  uri: Uri.parse('wss://devbox:7420/acp?x=1'),
  tokenRef: 'env:DEVBOX_TOKEN',
);

final _plain = ConnectionProfile.webSocket(
  id: 'plain',
  label: 'Plain',
  uri: Uri.parse('ws://plain:1/acp'),
);

final _ownSecret = ConnectionProfile.webSocket(
  id: 'owned',
  label: 'Owned',
  uri: Uri.parse('wss://owned:7420'),
  tokenRef: 'secret:codelab/profiles/owned/token',
);

final _foreignSecret = ConnectionProfile.webSocket(
  id: 'ci',
  label: 'CI',
  uri: Uri.parse('wss://ci:7420'),
  tokenRef: 'secret:codelab/ws-ci',
);

final _unsupported = ConnectionProfile.webSocket(
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
);

Finder _key(String key) => find.byKey(ValueKey(key));

/// Хранилище, у которого удаление можно сломать: разовое сообщение о сбое.
final class _RemoveFailsStore implements ProfileStore {
  _RemoveFailsStore(Iterable<ConnectionProfile> profiles)
    : _inner = InMemoryProfileStore(profiles);

  final InMemoryProfileStore _inner;

  @override
  Future<List<ConnectionProfile>> load() => _inner.load();

  @override
  Future<void> save(ConnectionProfile profile) => _inner.save(profile);

  @override
  Future<bool> remove(String id) async =>
      throw StateError('disk is read-only: /secret/path');
}

/// Хранилище, чтение которого падает не `FormatException`-ом.
final class _UnreadableStore implements ProfileStore {
  @override
  Future<List<ConnectionProfile>> load() async =>
      throw StateError('boom: sk-test-leak-0123456789');

  @override
  Future<void> save(ConnectionProfile profile) async {}

  @override
  Future<bool> remove(String id) async => false;
}

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

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

  /// Приложение с открытой страницей «Connection» на языке [locale].
  Future<CodeLabTestBinding> openPage(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    List<ConnectionProfile> stored = const [],
    ProfileStore? store,
    Map<String, String> environment = const {},
    CodeLabStdioTransportFactory? stdioTransportFactory,
    CodeLabWebSocketTransportFactory? webSocketTransportFactory,
    FakeProfileSecrets? secrets,
    String? project = '/workspace',
  }) async {
    final binding = CodeLabTestBinding(
      project: project,
      locale: locale,
      profileStore: store ?? InMemoryProfileStore(stored),
      profileSecrets: secrets,
      stdioDefault: false,
      environment: {'HOME': '/home/u', ...environment},
      settingsPages: _withConnection,
      stdioTransportFactory: stdioTransportFactory ?? (_) => FakeAcpTransport(),
      webSocketTransportFactory:
          webSocketTransportFactory ?? (_) => FakeAcpTransport(),
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
    await tester.pumpAndSettle();
    return binding;
  }

  Future<void> connectRow(WidgetTester tester, String id) async {
    await tester.tap(_key('connection-profile-use-$id'));
    await tester.pump();
    unawaited(
      codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit.startOnLaunch(),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
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

  group('en: прежние строки страницы', () {
    testWidgets('заголовок, секции, строка встроенного агента и метки', (
      tester,
    ) async {
      await openPage(tester, stored: [_dev]);

      expect(find.text('Connection'), findsWidgets);
      expect(find.text('Add profile'), findsOneWidget);
      expect(find.text('Profiles'), findsOneWidget);
      expect(find.text('Behavior'), findsOneWidget);
      expect(find.text('Embedded agent'), findsOneWidget);
      expect(
        find.text('Runs inside CodeLab; no separate process.'),
        findsOneWidget,
      );
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Selected'), findsOneWidget);
      expect(find.text('Restart agent'), findsOneWidget);
      await tearDownApp(tester);
    });
  });

  group('ru: страница «Connection»', () {
    testWidgets('заголовок, кнопка, секции и справка', (tester) async {
      await openPage(tester, locale: const Locale('ru'), stored: [_dev]);

      expect(find.text(ru.settingsPageConnectionTitle), findsWidgets);
      expect(find.text('Добавить профиль'), findsOneWidget);
      expect(find.text('Профили'), findsOneWidget);
      expect(find.text('Поведение'), findsOneWidget);
      expect(
        find.textContaining(
          'Общие с codelab_cli через profiles.json в \$CODELAB_HOME.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Присоединиться к сессии, запущенной в CLI'),
        findsOneWidget,
      );
      // Английские подписи ушли.
      expect(find.text('Add profile'), findsNothing);
      expect(find.text('Profiles'), findsNothing);
      expect(find.text('Behavior'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('справка «Join a session…» раскрывается на русском, команды '
        'без изменений', (tester) async {
      await openPage(tester, locale: const Locale('ru'));

      await tester.tap(_key('connection-join-cli-help'));
      await tester.pumpAndSettle();

      expect(find.textContaining('codelab-agent serve --ws'), findsOneWidget);
      expect(find.textContaining('codelab -a'), findsOneWidget);
      expect(find.textContaining('На хосте выполните'), findsOneWidget);
      expect(find.textContaining('On the host run'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('профиль встроенного агента переводится: подпись и сводка '
        '(D6), метки «По умолчанию» и «Выбрано»', (tester) async {
      await openPage(tester, locale: const Locale('ru'), stored: [_dev]);

      final embedded = _key('connection-profile-row-embedded');
      expect(
        find.descendant(of: embedded, matching: find.text('Встроенный агент')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: embedded,
          matching: find.text(
            'Работает внутри CodeLab, отдельного процесса нет.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: embedded, matching: find.text('По умолчанию')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: embedded, matching: find.text('Выбрано')),
        findsOneWidget,
      );
      expect(find.text('Embedded agent'), findsNothing);
      // Имя профиля пользователя не переводится.
      expect(find.text('Dev'), findsWidgets);
      await tearDownApp(tester);
    });

    testWidgets('кнопки строк: «Использовать», «Переименовать», «Удалить»', (
      tester,
    ) async {
      await openPage(tester, locale: const Locale('ru'), stored: [_dev]);

      final row = _key('connection-profile-row-dev');
      for (final label in const ['Использовать', 'Переименовать', 'Удалить']) {
        expect(
          find.descendant(of: row, matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
      await tearDownApp(tester);
    });

    testWidgets('источник токена: без токена, из переменной, не задана, '
        'секрет со статусом, нераспознанная ссылка', (tester) async {
      final secrets = FakeProfileSecrets(
        values: {'codelab/profiles/owned/token': 'sk-test-leak-0123456789'},
      );
      await openPage(
        tester,
        locale: const Locale('ru'),
        stored: [_plain, _devbox, _ownSecret, _foreignSecret, _unsupported],
        secrets: secrets,
      );

      String token(String id) =>
          textsOf(tester, _key('connection-profile-token-$id'));
      expect(token('plain'), 'Без токена');
      expect(token('devbox'), contains(r'Из $DEVBOX_TOKEN'));
      // «<NAME> is not set in CodeLab's environment.» с именем-плейсхолдером.
      expect(
        token('devbox'),
        contains('DEVBOX_TOKEN не задана в окружении CodeLab.'),
      );
      expect(
        token('owned'),
        contains('Секрет токена «codelab/profiles/owned/token»'),
      );
      expect(token('owned'), contains('file · задан'));
      expect(token('ci'), contains('Секрет токена «codelab/ws-ci»'));
      expect(token('ci'), contains('file · отсутствует'));
      expect(
        token('named'),
        'нераспознанная ссылка на токен (в этой версии не поддерживается)',
      );
      expect(find.textContaining('sk-test-leak-0123456789'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('переменная задана: заметки «не задана» нет', (tester) async {
      await openPage(
        tester,
        locale: const Locale('ru'),
        stored: [_devbox],
        environment: const {'DEVBOX_TOKEN': 'sk-leak-0123456789'},
      );

      expect(find.textContaining(r'Из $DEVBOX_TOKEN'), findsOneWidget);
      expect(find.textContaining('не задана'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('«Current» и бейдж попытки «Подключено»; удаление текущего '
        'недоступно с подсказкой', (tester) async {
      await openPage(
        tester,
        locale: const Locale('ru'),
        stored: [_dev, _plain],
      );

      await connectRow(tester, 'dev');

      final dev = _key('connection-profile-row-dev');
      expect(
        find.descendant(of: dev, matching: find.text('Текущий')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('connection-profile-status-dev'),
          matching: find.text('Подключено'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Сначала выберите другой профиль.'), findsWidgets);
      expect(find.text('Current'), findsNothing);
      expect(find.text('Connected'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('неудачная попытка: бейдж «Сбой» на строке попытки', (
      tester,
    ) async {
      await openPage(
        tester,
        locale: const Locale('ru'),
        stored: [_dev, _plain],
        webSocketTransportFactory: (_) =>
            ThrowingStartTransport(StateError('unreachable')),
      );
      await tester.tap(_key('connection-profile-use-plain'));
      await tester.pumpAndSettle();

      await tester.tap(_key('connection-restart-agent'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: _key('connection-profile-status-plain'),
          matching: find.text('Сбой'),
        ),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('«Current connection (not saved)»: профиль окна, которого '
        'нет в файле', (tester) async {
      final store = InMemoryProfileStore([_dev]);
      await openPage(tester, locale: const Locale('ru'), store: store);
      await connectRow(tester, 'dev');
      // Профиль пропал из файла (удалён из CLI), а окно к нему подключено:
      // при следующем открытии страницы он остаётся строкой «не сохранён».
      store.profiles.removeWhere((p) => p.id == 'dev');
      await tester.tap(_key('settings-back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
      await tester.pumpAndSettle();

      expect(find.text('Текущее подключение (не сохранено)'), findsOneWidget);
      expect(find.text('Current connection (not saved)'), findsNothing);
      await tearDownApp(tester);
    });
  });

  group('ru: блок «Behavior» (Restart agent)', () {
    testWidgets('заголовок, кнопка и описание для stdio-профиля', (
      tester,
    ) async {
      await openPage(tester, locale: const Locale('ru'), stored: [_dev]);
      await connectRow(tester, 'dev');

      final row = _key('connection-restart-row');
      expect(
        find.descendant(of: row, matching: find.text('Перезапустить агента')),
        findsOneWidget,
      );
      expect(
        tester.widget<CodeLabButton>(_key('connection-restart-agent')).label,
        'Перезапустить',
      );
      expect(
        find.textContaining(
          'Переподключает Dev и перезагружает открытые сессии. Выполняющийся '
          'ход прерывается; промпты в очереди сохраняются.',
        ),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('для WebSocket-профиля строка называется «Переподключиться»', (
      tester,
    ) async {
      await openPage(tester, locale: const Locale('ru'), stored: [_plain]);

      await connectRow(tester, 'plain');

      expect(
        tester.widget<CodeLabButton>(_key('connection-restart-agent')).label,
        'Переподключиться',
      );
      await tearDownApp(tester);
    });

    testWidgets('выбранный профиль не равен работающему: «Перезапустите '
        'агента, чтобы использовать <имя>.»', (tester) async {
      await openPage(
        tester,
        locale: const Locale('ru'),
        stored: [_dev, _plain],
      );
      await connectRow(tester, 'dev');

      await tester.tap(_key('connection-profile-use-plain'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Перезапустите агента, чтобы использовать Plain.'),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });

    testWidgets('без проекта: «Запустится, когда вы откроете проект.»', (
      tester,
    ) async {
      await openPage(
        tester,
        locale: const Locale('ru'),
        stored: [_dev],
        project: null,
      );

      expect(
        find.text('Запустится, когда вы откроете проект.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CodeLabButton>(_key('connection-restart-agent'))
            .onPressed,
        isNull,
      );
      await tearDownApp(tester);
    });
  });

  group('ru: InfoBar «Read-only» удалённого агента', () {
    testWidgets('заголовок с адресом без пути и подсказка с командами', (
      tester,
    ) async {
      await openPage(tester, locale: const Locale('ru'), stored: [_devbox]);

      await connectRow(tester, 'devbox');

      final text = textsOf(tester, _key('connection-remote-read-only'));
      expect(
        text,
        contains('Только чтение: агент работает на wss://devbox:7420'),
      );
      expect(
        text,
        contains(
          'Изменить провайдеров и MCP можно на том хосте: codelab provider '
          'add, codelab mcp add, codelab config set.',
        ),
      );
      for (final hidden in const ['/acp', 'x=1']) {
        expect(text, isNot(contains(hidden)));
      }
      await tearDownApp(tester);
    });
  });

  group('ru: запись `default` и ошибки чтения profiles.json', () {
    testWidgets('InfoBar записи default: текст по-русски, команда без '
        'изменений, кнопка «Удалить»', (tester) async {
      await openPage(
        tester,
        locale: const Locale('ru'),
        stored: [_legacyDefault, _dev],
      );

      final bar = _key('connection-profiles-ignored-default');
      expect(bar, findsOneWidget);
      final text = textsOf(tester, bar);
      expect(
        text,
        contains(
          'Профиль «default» в profiles.json игнорируется: default — это '
          'встроенный агент. Удалите его командой codelab profiles remove '
          'default.',
        ),
      );
      expect(
        find.descendant(of: bar, matching: find.text('Удалить')),
        findsOneWidget,
      );
      for (final hidden in const ['secret-agent', 'leak-arg']) {
        expect(find.textContaining(hidden), findsNothing, reason: hidden);
      }
      await tearDownApp(tester);
    });

    testWidgets('подтверждение удаления записи default на русском', (
      tester,
    ) async {
      final store = InMemoryProfileStore([_legacyDefault, _dev]);
      await openPage(tester, locale: const Locale('ru'), store: store);

      // Кнопка InfoBar — единственный `CodeLabButton` внутри него; по типу, а
      // не по подписи: подпись — предмет другой проверки.
      await tester.tap(
        find.descendant(
          of: _key('connection-profiles-ignored-default'),
          matching: find.byType(CodeLabButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Удалить игнорируемый профиль «default»?'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Из profiles.json удаляется только запись «default»; остальные '
          'профили остаются.',
        ),
        findsOneWidget,
      );
      expect(find.text('Отмена'), findsOneWidget);
      await tester.tap(_key('connection-remove-cancel'));
      await tester.pumpAndSettle();
      expect(store.profiles.map((p) => p.id), ['default', 'dev']);
      await tearDownApp(tester);
    });

    testWidgets('ошибка чтения profiles.json: путь — плейсхолдер, причина '
        'приложения переведена', (tester) async {
      final store = InMemoryProfileStore([_dev])..failLoad = true;
      await openPage(tester, locale: const Locale('ru'), store: store);

      final text = textsOf(tester, _key('connection-profiles-unreadable'));
      expect(
        text,
        contains(
          'Не удаётся прочитать /home/u/.codelab/profiles.json: файл имеет '
          'неподдерживаемую версию или неверную структуру. Исправьте или '
          'удалите файл; CodeLab его не перезапишет.',
        ),
      );
      expect(_key('connection-profile-row-embedded'), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('другая причина: только имя типа исключения, текст '
        'исключения не показывается', (tester) async {
      await openPage(
        tester,
        locale: const Locale('ru'),
        store: _UnreadableStore(),
      );

      final text = textsOf(tester, _key('connection-profiles-unreadable'));
      expect(text, contains('файл не удаётся прочитать (StateError)'));
      expect(find.textContaining('sk-test-leak-0123456789'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('без пути (недопустимый CODELAB_HOME): причина — текст '
        'composition root как есть (D7)', (tester) async {
      await openPage(
        tester,
        locale: const Locale('ru'),
        store: const UnavailableProfileStore(
          'CODELAB_HOME: ~user is not supported, use an absolute path',
        ),
        environment: const {'CODELAB_HOME': '~user/home'},
      );

      final text = textsOf(tester, _key('connection-profiles-unreadable'));
      expect(
        text,
        contains(
          'Не удаётся использовать профили: CODELAB_HOME: ~user is not supported, '
          'use an absolute path.',
        ),
      );
      await tearDownApp(tester);
    });
  });

  group('ru: подтверждения и сбои действий', () {
    testWidgets('удаление профиля: заголовок с именем, пояснение, флажок '
        'токена с именем секрета', (tester) async {
      final secrets = FakeProfileSecrets(
        values: {'codelab/profiles/owned/token': 'sk-test-leak-0123456789'},
      );
      await openPage(
        tester,
        locale: const Locale('ru'),
        stored: [_ownSecret],
        secrets: secrets,
      );

      await tester.tap(_key('connection-profile-remove-owned'));
      await tester.pumpAndSettle();

      expect(find.text('Удалить профиль Owned?'), findsOneWidget);
      expect(
        find.text(
          'Запись удаляется из profiles.json. Переменные окружения и другие '
          'настройки не затрагиваются.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Также удалить сохранённый токен «codelab/profiles/owned/token»',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('connection-remove-confirm'),
          matching: find.text('Удалить'),
        ),
        findsOneWidget,
      );
      expect(find.text('Отмена'), findsOneWidget);
      await tester.tap(_key('connection-remove-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('токен не удалился: имя секрета и команда `codelab secret '
        'delete <имя>` без изменений (security)', (tester) async {
      final secrets = FakeProfileSecrets(
        values: {'codelab/profiles/owned/token': 'sk-test-leak-0123456789'},
      )..nextDelete = const Failed('cannot delete');
      await openPage(
        tester,
        locale: const Locale('ru'),
        stored: [_ownSecret],
        secrets: secrets,
      );

      await tester.tap(_key('connection-profile-remove-owned'));
      await tester.pumpAndSettle();
      await tester.tap(_key('connection-remove-confirm'));
      await tester.pumpAndSettle();

      final text = textsOf(tester, _key('connection-failure'));
      expect(
        text,
        'Профиль удалён, но сохранённый токен «codelab/profiles/owned/token» не '
        'удалён. Удалите его командой codelab secret delete '
        'codelab/profiles/owned/token.',
      );
      expect(find.textContaining('sk-test-leak-0123456789'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('сбой записи: общий текст без текста исключения', (
      tester,
    ) async {
      await openPage(
        tester,
        locale: const Locale('ru'),
        store: _RemoveFailsStore([_dev]),
      );

      await tester.tap(_key('connection-profile-remove-dev'));
      await tester.pumpAndSettle();
      await tester.tap(_key('connection-remove-confirm'));
      await tester.pumpAndSettle();

      expect(
        textsOf(tester, _key('connection-failure')),
        'Не удалось сохранить изменение. Повторите попытку.',
      );
      expect(find.textContaining('/secret/path'), findsNothing);
      await tearDownApp(tester);
    });

    testWidgets('редактор «Rename»: подпись поля и кнопки', (tester) async {
      await openPage(tester, locale: const Locale('ru'), stored: [_dev]);

      await tester.tap(_key('connection-profile-rename-dev'));
      await tester.pumpAndSettle();

      final editor = _key('connection-profile-rename-editor-dev');
      expect(
        tester
            .widget<TextBox>(_key('connection-profile-rename-field-dev'))
            .placeholder,
        'Имя',
      );
      expect(
        find.descendant(of: editor, matching: find.text('Сохранить')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: editor, matching: find.text('Отмена')),
        findsOneWidget,
      );
      await tearDownApp(tester);
    });
  });

  group('ru: подпись встроенного агента в шапке рабочего места (D6)', () {
    testWidgets('подпись профиля и подсказка соединения называют встроенного '
        'агента по-русски', (tester) async {
      final binding = await openPage(tester, locale: const Locale('ru'));

      final shell = binding.scope.resolve<CodeLabShellCubit>().state;

      expect(shell.profileLabel, 'Встроенный агент');
      expect(shell.transportLabel, 'Встроенный агент');
      expect(shell.connectionDetail, 'codelab_embedded (embedded-app-desktop)');
      await tearDownApp(tester);
    });

    testWidgets('смена языка пересобирает подпись профиля в состоянии окна', (
      tester,
    ) async {
      final binding = await openPage(tester);
      final shell = binding.scope.resolve<CodeLabShellCubit>();
      expect(shell.state.profileLabel, 'Embedded agent');

      await selectLanguage(tester, binding, AppLanguagePreference.ru);
      expect(shell.state.profileLabel, 'Встроенный агент');

      await selectLanguage(tester, binding, AppLanguagePreference.en);
      expect(shell.state.profileLabel, 'Embedded agent');
      await tearDownApp(tester);
    });
  });

  group('смена языка на странице «Connection» (spec: «Уже показанные ошибки '
      'и InfoBar пересобираются»)', () {
    testWidgets('InfoBar записи default: en → ru → en, команда без '
        'изменений', (tester) async {
      final binding = await openPage(tester, stored: [_legacyDefault, _dev]);
      final bar = _key('connection-profiles-ignored-default');
      expect(
        textsOf(tester, bar),
        contains('Profile "default" in profiles.json'),
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        textsOf(tester, bar),
        contains('Профиль «default» в profiles.json'),
      );
      expect(textsOf(tester, bar), contains('codelab profiles remove default'));
      expect(find.text('Connection'), findsNothing);
      await expectNoStaleLanguage(tester, from: en, to: ru);

      await selectLanguage(tester, binding, AppLanguagePreference.en);
      expect(
        textsOf(tester, bar),
        contains('Profile "default" in profiles.json'),
      );
      await expectNoStaleLanguage(tester, from: ru, to: en);
      await tearDownApp(tester);
    });

    testWidgets('ошибка чтения profiles.json: рамка и причина пересобираются, '
        'путь сохраняется', (tester) async {
      final store = InMemoryProfileStore([_dev])..failLoad = true;
      final binding = await openPage(tester, store: store);
      final bar = _key('connection-profiles-unreadable');
      expect(
        textsOf(tester, bar),
        contains('Cannot read /home/u/.codelab/profiles.json'),
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        textsOf(tester, bar),
        contains(
          'Не удаётся прочитать /home/u/.codelab/profiles.json: файл имеет '
          'неподдерживаемую версию или неверную структуру.',
        ),
      );
      expect(textsOf(tester, bar), isNot(contains('Cannot read')));
      await expectNoStaleLanguage(tester, from: en, to: ru);
      await tearDownApp(tester);
    });

    testWidgets('сбой записи показан, затем язык меняется: сообщение '
        'остаётся и переведено', (tester) async {
      final binding = await openPage(tester, store: _RemoveFailsStore([_dev]));
      await tester.tap(_key('connection-profile-remove-dev'));
      await tester.pumpAndSettle();
      await tester.tap(_key('connection-remove-confirm'));
      await tester.pumpAndSettle();
      expect(
        textsOf(tester, _key('connection-failure')),
        'Could not save the change. Try again.',
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        textsOf(tester, _key('connection-failure')),
        'Не удалось сохранить изменение. Повторите попытку.',
      );
      await expectNoStaleLanguage(tester, from: en, to: ru);
      await tearDownApp(tester);
    });

    testWidgets('строки профилей и блок «Behavior» пересобираются, '
        'выбор по умолчанию и соединение не затронуты', (tester) async {
      final binding = await openPage(tester, stored: [_dev, _plain]);
      await connectRow(tester, 'dev');
      final shell = binding.scope.resolve<CodeLabShellCubit>();
      final connection = shell.state.connectionStatus;

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(find.text('Встроенный агент'), findsWidgets);
      expect(find.text('Текущий'), findsOneWidget);
      expect(find.text('Подключено'), findsWidgets);
      expect(find.text('Перезапустить агента'), findsOneWidget);
      expect(shell.state.connectionStatus, connection);
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'embedded',
      );
      await expectNoStaleLanguage(tester, from: en, to: ru);

      await selectLanguage(tester, binding, AppLanguagePreference.en);
      expect(find.text('Embedded agent'), findsWidgets);
      expect(find.text('Current'), findsOneWidget);
      await expectNoStaleLanguage(tester, from: ru, to: en);
      await tearDownApp(tester);
    });

    testWidgets('открытое подтверждение удаления переводится вместе с '
        'деревом, флажок сохраняет выбор', (tester) async {
      final secrets = FakeProfileSecrets(
        values: {'codelab/profiles/owned/token': 'sk-test-leak-0123456789'},
      );
      final binding = await openPage(
        tester,
        stored: [_ownSecret],
        secrets: secrets,
      );
      await tester.tap(_key('connection-profile-remove-owned'));
      await tester.pumpAndSettle();
      await tester.tap(_key('connection-remove-delete-token'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Checkbox>(_key('connection-remove-delete-token')).checked,
        isFalse,
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(find.text('Удалить профиль Owned?'), findsOneWidget);
      expect(
        find.text(
          'Также удалить сохранённый токен «codelab/profiles/owned/token»',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Checkbox>(_key('connection-remove-delete-token')).checked,
        isFalse,
      );
      await expectNoStaleLanguage(tester, from: en, to: ru);
      await tester.tap(_key('connection-remove-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('открытый редактор «Rename» сохраняет введённое имя', (
      tester,
    ) async {
      final binding = await openPage(tester, stored: [_dev]);
      await tester.tap(_key('connection-profile-rename-dev'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _key('connection-profile-rename-field-dev'),
        'Новое имя dev',
      );
      await tester.pump();

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        tester
            .widget<TextBox>(_key('connection-profile-rename-field-dev'))
            .controller!
            .text,
        'Новое имя dev',
      );
      expect(
        tester
            .widget<TextBox>(_key('connection-profile-rename-field-dev'))
            .placeholder,
        'Имя',
      );
      await tearDownApp(tester);
    });
  });
}
