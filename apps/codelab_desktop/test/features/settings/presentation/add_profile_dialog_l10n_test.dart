// Красные тесты задачи 4.1 change `add-desktop-localization`: диалог «Add
// connection profile» на русском и английском, смена языка в открытом диалоге
// (spec app-settings «Диалог «Add connection profile»», «Локализация
// интерфейса app», сценарии «Смена языка применяется сразу на странице
// настроек», «Ввод пользователя сохраняется», «Уже показанные ошибки и InfoBar
// пересобираются»; design.md D5 п. 9, D6 («`ProfileDraftIssue.message` — app
// переводит по коду», «`ProfileCommitter` — app переводит по варианту; причину
// хранилища секретов показывает как есть»), D7, D9, D12).
//
// Диалог открывается в собранном приложении со страницы «Connection»: язык
// переключает настоящий `AppLanguageCubit`, как на странице «General».
// Проверяется то, что видит пользователь: заголовок, подписи полей, четыре
// варианта токена с подсказками, ошибки по `ProfileDraftIssueCode`, заметка
// «<NAME> is not set in CodeLab's environment.», предупреждение `ws://` и
// подтверждение «Save anyway», исходы `ProfileCommitter` по варианту, экран
// «Profile saved». Черновик пользователя и подтверждение при смене языка
// сохраняются. Команды (`codelab -a <id>`, `codelab secret delete <имя>`),
// имена переменных и секретов, пути и адреса не переводятся (D7).
//
// Ожидания на `en` — прежние строки (зелёные); на `ru` — красные до задачи
// 4.2. Русские строки — по глоссарию («токен», «секрет», «окружение»,
// «профиль подключения»); остальные — вне глоссария (отчёт задачи 4.1);
// сообщения с меткой security (`ws://`, токены, секреты) вычитывает
// пользователь (задача 4.3, D14).

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/language/app_language_cubit.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_profile_secrets.dart';
import '../../../support/in_memory_profile_store.dart';
import '../../../support/l10n_mix.dart';
import '../../../support/test_app_scope.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

/// Хранилище, которое не пишет: исход — общий отказ записи профиля.
final class _FailingStore implements ProfileStore {
  @override
  Future<List<ConnectionProfile>> load() async => const [];

  @override
  Future<void> save(ConnectionProfile profile) async =>
      throw StateError('disk is full: /secret/path');

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
    view.physicalSize = const Size(1440, 1400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  /// Приложение со страницей «Connection» и открытым диалогом «Add profile».
  Future<CodeLabTestBinding> openDialog(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    ProfileStore? store,
    FakeProfileSecrets? secrets,
    Map<String, String> environment = const {},
  }) async {
    final binding = CodeLabTestBinding(
      project: '/workspace',
      locale: locale,
      profileStore:
          store ??
          InMemoryProfileStore([
            const ConnectionProfile.stdio(
              id: 'dev',
              label: 'Dev',
              command: 'codelab-agent',
            ),
          ]),
      // Без двойника хранилище «не открыто» (env, только чтение): вариант «Store
      // a new token» был бы недоступен.
      profileSecrets: secrets ?? FakeProfileSecrets(),
      stdioDefault: false,
      environment: {'HOME': '/home/u', ...environment},
      settingsPages: const SettingsPages(available: {SettingsPage.connection}),
      stdioTransportFactory: (_) => FakeAcpTransport(),
      webSocketTransportFactory: (_) => FakeAcpTransport(),
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
    await tester.pumpAndSettle();
    await tester.tap(_key('connection-add-profile'));
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

  Future<void> toWebSocket(WidgetTester tester) async {
    await tester.tap(_key('add-profile-type-websocket'));
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester, Finder scope) => tester
      .widgetList<Text>(find.descendant(of: scope, matching: find.byType(Text)))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join(' ');

  group('en: прежние строки диалога', () {
    testWidgets('заголовок, подписи полей и кнопки', (tester) async {
      await openDialog(tester);

      expect(find.text('Add connection profile'), findsOneWidget);
      for (final label in const [
        'Type',
        'Name',
        'Command',
        'Arguments',
        'Folder',
        'Environment',
        'After saving',
        'Use by default',
        'Save',
        'Cancel',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });
  });

  group('ru: форма stdio', () {
    testWidgets('заголовок, подзаголовок с путём и командой, подписи, '
        'подсказки и кнопки', (tester) async {
      await openDialog(tester, locale: const Locale('ru'));

      expect(find.text('Добавить профиль подключения'), findsOneWidget);
      expect(
        find.textContaining(
          'Сохраняется в ~/.codelab/profiles.json и доступен в codelab_cli как '
          'codelab -a',
          findRichText: true,
        ),
        findsOneWidget,
      );
      for (final label in const [
        'Тип',
        'Имя',
        'Команда',
        'Аргументы',
        'Папка',
        'Окружение',
        'После сохранения',
        'Использовать по умолчанию',
        'Запускать в папке проекта',
        'Сохранить',
        'Отмена',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(
        find.text(
          'Запускает агента как дочерний процесс для каждого окна и говорит '
          'по ACP через stdin/stdout.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Разбираются как в командной оболочке: кавычки и экранирование '
          'работают.',
        ),
        findsOneWidget,
      );
      expect(find.text('Используется при запуске агента.'), findsOneWidget);
      expect(find.text('Локальный stdio'), findsOneWidget);
      // Название протокола не переводится (D7).
      expect(find.text('WebSocket'), findsOneWidget);
      expect(find.text('Add connection profile'), findsNothing);
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('id следует за именем: подпись «нельзя изменить после '
        'сохранения», команда `codelab -a <id>` без изменений', (tester) async {
      await openDialog(tester, locale: const Locale('ru'));

      await tester.enterText(_key('add-profile-name'), 'Build Box');
      await tester.pump();

      expect(
        find.textContaining('· нельзя изменить после сохранения'),
        findsOneWidget,
      );
      expect(
        find.textContaining('codelab -a build-box', findRichText: true),
        findsOneWidget,
      );
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets(
      'ошибки полей по коду на русском: id, команда, аргументы, окружение',
      (tester) async {
        await openDialog(tester, locale: const Locale('ru'));
        await tester.enterText(_key('add-profile-command'), '');
        await tester.enterText(_key('add-profile-name'), 'Embedded');
        await tester.pump();

        expect(
          find.text('«embedded» зарезервирован для встроенного агента.'),
          findsOneWidget,
        );
        expect(
          find.text('Введите команду, которая запускает агента.'),
          findsOneWidget,
        );

        await tester.enterText(_key('add-profile-name'), 'Dev');
        await tester.pump();
        expect(find.text('Профиль с id «dev» уже существует.'), findsOneWidget);

        await tester.enterText(_key('add-profile-args'), 'serve "unclosed');
        await tester.enterText(_key('add-profile-env'), 'API_KEY=x');
        await tester.pump();
        expect(find.text('В аргументах не закрыта кавычка.'), findsOneWidget);
        expect(
          find.text(
            r'API_KEY похоже на секрет. Задайте его в системном окружении или '
            r'сошлитесь на него в конфигурации агента как ${secret:…}.',
          ),
          findsOneWidget,
        );
        await tester.tap(_key('add-profile-cancel'));
        await tester.pumpAndSettle();
        await tearDownApp(tester);
      },
    );
  });

  group('ru: форма WebSocket и токен', () {
    testWidgets('четыре варианта токена и подписи полей', (tester) async {
      await openDialog(tester, locale: const Locale('ru'));

      await toWebSocket(tester);

      for (final label in const [
        'Без токена',
        'Использовать сохранённый секрет',
        'Сохранить новый токен',
        'Из переменной окружения',
        'Токен',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(
        find.text(
          'Подключается к codelab-agent serve --ws на этой или другой машине.',
        ),
        findsOneWidget,
      );
      expect(find.text('URL'), findsOneWidget);
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('«Использовать сохранённый секрет» без имён: подсказка с '
        'хранилищем', (tester) async {
      await openDialog(tester, locale: const Locale('ru'));
      await toWebSocket(tester);

      expect(find.text('В file нет сохранённых секретов.'), findsOneWidget);
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('«Сохранить новый токен»: поле, подсказка куда сохранится '
        'значение (security)', (tester) async {
      await openDialog(tester, locale: const Locale('ru'));
      await toWebSocket(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.tap(_key('add-profile-token-new'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<PasswordBox>(_key('add-profile-token-new-value'))
            .placeholder,
        'Вставьте токен',
      );
      expect(
        find.text(
          'Сохраняется как «codelab/profiles/box/token» в file. Значение больше '
          'не показывается и не записывается в profiles.json.',
        ),
        findsOneWidget,
      );
      expect(find.text('Введите токен.'), findsOneWidget);
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('хранилище только для чтения: вариант недоступен, причина '
        'приложения переведена', (tester) async {
      final secrets = FakeProfileSecrets(
        backend: const ProfileSecretBackend(id: 'env', writable: false),
      );
      await openDialog(tester, locale: const Locale('ru'), secrets: secrets);
      await toWebSocket(tester);

      expect(
        find.text('Хранилище секретов env доступно только для чтения.'),
        findsOneWidget,
      );
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('«Из переменной окружения»: пояснения и заметка «<NAME> не '
        'задана в окружении CodeLab.» (security)', (tester) async {
      await openDialog(tester, locale: const Locale('ru'));
      await toWebSocket(tester);

      await tester.tap(_key('add-profile-token-env'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _key('add-profile-token-env-name'),
        'DEVBOX_TOKEN',
      );
      await tester.pump();

      expect(
        find.text(
          'CodeLab читает токен из этой переменной окружения при '
          'подключении. Значения токенов не сохраняются в profiles.json.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Приложения, открытые из Finder, не видят переменных, заданных в '
          'профиле вашей оболочки.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('DEVBOX_TOKEN не задана в окружении CodeLab.'),
        findsOneWidget,
      );
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('переменная задана: заметки нет', (tester) async {
      await openDialog(
        tester,
        locale: const Locale('ru'),
        environment: const {'DEVBOX_TOKEN': 'x'},
      );
      await toWebSocket(tester);
      await tester.tap(_key('add-profile-token-env'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _key('add-profile-token-env-name'),
        'DEVBOX_TOKEN',
      );
      await tester.pump();

      expect(find.textContaining('не задана в окружении'), findsNothing);
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('ошибки URL и токена по коду: ws://, учётные данные в URL, '
        'имя переменной', (tester) async {
      await openDialog(tester, locale: const Locale('ru'));
      await toWebSocket(tester);

      await tester.enterText(_key('add-profile-url'), 'http://box');
      await tester.pump();
      expect(find.text('Укажите ws:// или wss:// и хост.'), findsOneWidget);

      await tester.enterText(
        _key('add-profile-url'),
        'wss://user:pass@box:7420',
      );
      await tester.pump();
      expect(
        find.text(
          'Уберите имя пользователя и пароль из URL; вместо этого используйте '
          'поле «Токен».',
        ),
        findsOneWidget,
      );

      await tester.tap(_key('add-profile-token-env'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('add-profile-token-env-name'), '1BAD');
      await tester.pump();
      expect(
        find.text(
          'Имя переменной: буквы, цифры и «_», не может начинаться с цифры.',
        ),
        findsOneWidget,
      );
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });
  });

  group('ru: `ws://` к другой машине (security)', () {
    testWidgets('предупреждение под URL, подтверждение и «Всё равно '
        'сохранить»', (tester) async {
      final store = InMemoryProfileStore();
      await openDialog(tester, locale: const Locale('ru'), store: store);
      await toWebSocket(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'ws://box:7420');
      await tester.pump();
      expect(
        find.text('ws:// к другой машине: трафик передаётся без шифрования.'),
        findsOneWidget,
      );

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      final bar = _key('add-profile-unencrypted');
      expect(
        find.descendant(
          of: bar,
          matching: find.text('Соединение без шифрования'),
        ),
        findsOneWidget,
      );
      expect(
        textOf(tester, bar),
        contains(
          'Промпты и файлы, отправленные на ws://box:7420, будут переданы '
          'открытым текстом. Используйте wss://, если хост это поддерживает.',
        ),
      );
      expect(
        find.descendant(of: bar, matching: find.text('Всё равно сохранить')),
        findsOneWidget,
      );
      expect(store.profiles, isEmpty);

      await tester.tap(_key('add-profile-save-anyway'));
      await tester.pumpAndSettle();
      expect(store.profiles.single.id, 'box');
      await tester.tap(_key('add-profile-done'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('с токеном: текст про токен, адрес без пути и учётных данных', (
      tester,
    ) async {
      await openDialog(
        tester,
        locale: const Locale('ru'),
        environment: const {'DEVBOX_TOKEN': 'x'},
      );
      await toWebSocket(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'ws://box:7420/acp?x=1');
      await tester.tap(_key('add-profile-token-env'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _key('add-profile-token-env-name'),
        'DEVBOX_TOKEN',
      );
      await tester.pump();
      expect(
        find.text('ws:// к другой машине: токен передаётся без шифрования.'),
        findsOneWidget,
      );

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      final text = textOf(tester, _key('add-profile-unencrypted'));
      expect(
        text,
        contains(
          'Токен для ws://box:7420 будет передан открытым текстом. '
          'Используйте wss://, если хост это поддерживает.',
        ),
      );
      expect(text, isNot(contains('/acp')));
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });
  });

  group('ru: исходы записи ProfileCommitter по варианту', () {
    testWidgets('профиль записан: «Профиль сохранён», адрес в profiles.json '
        'и пометка «используется по умолчанию»', (tester) async {
      await openDialog(tester, locale: const Locale('ru'));
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.tap(_key('add-profile-use-by-default'));
      await tester.pump();

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      expect(find.text('Профиль сохранён'), findsOneWidget);
      expect(
        find.textContaining(
          'Добавлен в profiles.json как box',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('· используется по умолчанию', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text(
          'Работающий агент не изменился. Выберите профиль кнопкой '
          '«Использовать» в его строке; применит его «Перезапустить агента».',
        ),
        findsOneWidget,
      );
      expect(find.text('Готово'), findsOneWidget);
      expect(find.text('Добавить ещё'), findsOneWidget);
      await tester.tap(_key('add-profile-done'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('запись профиля не удалась: общий текст без текста '
        'исключения', (tester) async {
      await openDialog(
        tester,
        locale: const Locale('ru'),
        store: _FailingStore(),
      );
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.pump();

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Не удалось сохранить профиль. Повторите попытку.'),
        findsOneWidget,
      );
      expect(find.textContaining('/secret/path'), findsNothing);
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('секрет токена не записан: «Не удалось сохранить токен.» '
        '(security)', (tester) async {
      final secrets = FakeProfileSecrets()
        ..nextWrite = const Failed('backend broke');
      await openDialog(tester, locale: const Locale('ru'), secrets: secrets);
      await toWebSocket(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'wss://box:7420');
      await tester.tap(_key('add-profile-token-new'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _key('add-profile-token-new-value'),
        'sk-test-leak-0123456789',
      );
      await tester.pump();

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Не удалось сохранить токен. Повторите попытку.'),
        findsOneWidget,
      );
      expect(find.textContaining('sk-test-leak-0123456789'), findsNothing);
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('профиль не записан, токен остался: имя секрета и команда '
        '`codelab secret delete <имя>` без изменений (security)', (
      tester,
    ) async {
      final secrets = FakeProfileSecrets()
        ..nextDelete = const Failed('cannot delete');
      await openDialog(
        tester,
        locale: const Locale('ru'),
        store: _FailingStore(),
        secrets: secrets,
      );
      await toWebSocket(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'wss://box:7420');
      await tester.tap(_key('add-profile-token-new'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _key('add-profile-token-new-value'),
        'sk-test-leak-0123456789',
      );
      await tester.pump();

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Профиль не сохранён; токен остался в file под именем '
          '«codelab/profiles/box/token». Удалите его командой codelab secret '
          'delete codelab/profiles/box/token.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('sk-test-leak-0123456789'), findsNothing);
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('хранилище отказало с причиной: причина как есть (сценарий '
        '«Текст хранилища секретов не переводится»)', (tester) async {
      final secrets = FakeProfileSecrets()
        ..nextWrite = const ReadOnly('secret store keychain is read-only.');
      await openDialog(tester, locale: const Locale('ru'), secrets: secrets);
      await toWebSocket(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'wss://box:7420');
      await tester.tap(_key('add-profile-token-new'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('add-profile-token-new-value'), 'v');
      await tester.pump();

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      expect(find.text('secret store keychain is read-only.'), findsOneWidget);
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('хранилище отказало без причины: перевод «The secret store '
        'is read-only.»', (tester) async {
      final secrets = FakeProfileSecrets()..nextWrite = const ReadOnly();
      await openDialog(tester, locale: const Locale('ru'), secrets: secrets);
      await toWebSocket(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'wss://box:7420');
      await tester.tap(_key('add-profile-token-new'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('add-profile-token-new-value'), 'v');
      await tester.pump();

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      expect(
        find.text('Хранилище секретов доступно только для чтения.'),
        findsOneWidget,
      );
      expect(find.text('The secret store is read-only.'), findsNothing);
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('секрет с таким именем уже есть: ошибка у поля токена '
        '(security)', (tester) async {
      final secrets = FakeProfileSecrets(
        values: {'codelab/profiles/box/token': 'old-secret-value'},
      );
      await openDialog(tester, locale: const Locale('ru'), secrets: secrets);
      await toWebSocket(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'wss://box:7420');
      await tester.tap(_key('add-profile-token-new'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _key('add-profile-token-new-value'),
        'new-secret-value',
      );
      await tester.pump();

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Сохранённый токен «codelab/profiles/box/token» уже есть в file. '
          'Выберите его в варианте «Использовать сохранённый секрет» или '
          'удалите командой codelab secret delete.',
        ),
        findsOneWidget,
      );
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });
  });

  group('смена языка в открытом диалоге (D5 п. 9)', () {
    testWidgets('форма: подписи и ошибки пересобираются, введённое и '
        'выбранное сохраняется', (tester) async {
      final binding = await openDialog(tester);
      await toWebSocket(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'http://box');
      await tester.tap(_key('add-profile-token-env'));
      await tester.pumpAndSettle();
      await tester.enterText(
        _key('add-profile-token-env-name'),
        'DEVBOX_TOKEN',
      );
      await tester.pump();
      expect(find.text('Use ws:// or wss:// with a host.'), findsOneWidget);
      expect(
        find.text("DEVBOX_TOKEN is not set in CodeLab's environment."),
        findsOneWidget,
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(find.text('Добавить профиль подключения'), findsOneWidget);
      expect(find.text('Укажите ws:// или wss:// и хост.'), findsOneWidget);
      expect(
        find.text('DEVBOX_TOKEN не задана в окружении CodeLab.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextBox>(_key('add-profile-name')).controller!.text,
        'Box',
      );
      expect(
        tester.widget<TextBox>(_key('add-profile-url')).controller!.text,
        'http://box',
      );
      expect(
        tester
            .widget<TextBox>(_key('add-profile-token-env-name'))
            .controller!
            .text,
        'DEVBOX_TOKEN',
      );
      await expectNoStaleLanguage(tester, from: en, to: ru);

      await selectLanguage(tester, binding, AppLanguagePreference.en);
      expect(find.text('Use ws:// or wss:// with a host.'), findsOneWidget);
      await expectNoStaleLanguage(tester, from: ru, to: en);
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('предупреждение `ws://` и подтверждение «Save anyway» '
        'сохраняются и переводятся', (tester) async {
      final store = InMemoryProfileStore();
      final binding = await openDialog(tester, store: store);
      await toWebSocket(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'ws://box:7420');
      await tester.pump();
      expect(
        find.text('ws:// to another machine: traffic is sent unencrypted.'),
        findsOneWidget,
      );
      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Unencrypted connection', findRichText: true),
        findsOneWidget,
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(_key('add-profile-unencrypted'), findsOneWidget);
      expect(
        find.textContaining('Соединение без шифрования', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Всё равно сохранить'), findsOneWidget);
      expect(
        find.text('ws:// к другой машине: трафик передаётся без шифрования.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextBox>(_key('add-profile-url')).controller!.text,
        'ws://box:7420',
      );
      expect(store.profiles, isEmpty);
      await expectNoStaleLanguage(tester, from: en, to: ru);

      // Подтверждение не потеряно: «Save anyway» записывает профиль.
      await tester.tap(_key('add-profile-save-anyway'));
      await tester.pumpAndSettle();
      expect(store.profiles.single.id, 'box');
      await tester.tap(_key('add-profile-done'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('экран «Profile saved» пересобирается', (tester) async {
      final binding = await openDialog(tester);
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.pump();
      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();
      expect(find.text('Profile saved'), findsOneWidget);

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(find.text('Профиль сохранён'), findsOneWidget);
      expect(find.text('Готово'), findsOneWidget);
      expect(textOf(tester, _key('add-profile-saved-bar')), contains('box'));
      await expectNoStaleLanguage(tester, from: en, to: ru);
      await tester.tap(_key('add-profile-done'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('отказ записи остаётся на экране и переводится', (
      tester,
    ) async {
      final binding = await openDialog(tester, store: _FailingStore());
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.pump();
      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not save the profile. Try again.'),
        findsOneWidget,
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        find.text('Не удалось сохранить профиль. Повторите попытку.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextBox>(_key('add-profile-name')).controller!.text,
        'Box',
      );
      await expectNoStaleLanguage(tester, from: en, to: ru);
      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });
  });
}
