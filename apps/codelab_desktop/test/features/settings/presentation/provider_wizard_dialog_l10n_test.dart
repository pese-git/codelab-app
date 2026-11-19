// Красные тесты задачи 4.1 change `add-desktop-localization`: мастер
// провайдера на русском и английском, смена языка в открытом мастере (spec
// app-settings «Мастер провайдера в app», «Локализация интерфейса app»,
// сценарии «Смена языка применяется сразу на странице настроек», «Ввод
// пользователя сохраняется», «Команда в переведённой фразе»; design.md D5
// п. 9, D6, D7, D9, D12).
//
// Мастер открывается в собранном приложении со страницы «Providers»: язык
// переключает настоящий `AppLanguageCubit`. Автомат `ProviderSetupFlow`,
// конфиг, ключи и проверка — двойники (`fake_provider_settings.dart`).
// Проверяется то, что видит пользователь: строка шагов, подписи шагов, варианты
// ключа, отказы проверки, предупреждение об `http://`, обзор, уведомление об
// изменении конфига на диске, отказ записи с командой `codelab secret delete
// <имя>` без изменений. Введённое (адрес, ключ, имя модели) и выбранное при
// смене языка сохраняется (D5 п. 9). Пресеты и тексты шагов моста переводятся
// по типу, а не по готовой строке (решения пользователя 2026-11-19, D5 п. 5,
// D6 «Тексты моста настроек»): подписи `ollama`, `custom-openai`,
// `custom-anthropic` и значение «Type» сводки — по `id` пресета, ошибки шагов —
// по `errorCode`, предупреждение «Not verified» — по `notVerified`;
// `OpenAI`, `Anthropic`, `OpenRouter` — как есть.
//
// Ожидания на `en` — прежние строки (зелёные); на `ru` — красные до задачи
// 4.2. Русские строки — по глоссарию («провайдер», «ключ», «модель»,
// «окружение», «хранилище секретов», «только этот проект»); остальные — вне
// глоссария (отчёт задачи 4.1); сообщения с меткой security вычитывает
// пользователь (задача 4.3, D14).

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
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
import '../../../support/no_text_leak.dart';

const _pages = SettingsPages(
  available: {SettingsPage.connection, SettingsPage.providers},
);

Map<String, Object?> _existing() => {
  'agent': {'default_model': 'local/qwen'},
  'providers': {
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
    store = FakeAgentConfigStore(user: _existing());
    session = FakeProviderSettingsSession(store);
  });

  /// Страница «Providers» на языке [locale]; мастер открывает [openWizard].
  Future<CodeLabTestBinding> openPage(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    final binding = CodeLabTestBinding(
      project: '/workspace',
      locale: locale,
      stdioDefault: false,
      profileStore: InMemoryProfileStore(),
      environment: {'HOME': '/home/u'},
      settingsPages: _pages,
      stdioTransportFactory: (_) => FakeAcpTransport(),
      providerSettingsOpener: (access, env) async => session,
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
    await tester.pumpAndSettle();
    await tester.tap(_key(SettingsPage.providers.navKey));
    await tester.pumpAndSettle();
    return binding;
  }

  Future<void> frames(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openWizard(WidgetTester tester, {String? editId}) async {
    await tester.tap(
      editId == null ? _key('providers-add') : _key('providers-edit-$editId'),
    );
    await frames(tester);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(_key('provider-wizard-next'));
    await frames(tester);
  }

  /// Выбирает custom-пресет и доходит до шага адреса.
  Future<void> toBaseUrl(WidgetTester tester) async {
    await openWizard(tester);
    await tester.tap(_key('provider-wizard-preset-custom-openai'));
    await frames(tester, 2);
    await next(tester);
  }

  Future<void> toKey(
    WidgetTester tester, {
    String url = 'https://llm.example/v1',
  }) async {
    await toBaseUrl(tester);
    await tester.enterText(_key('provider-wizard-base-url-field'), url);
    await next(tester);
  }

  /// До проверки без ключа: проверка ждёт ответа теста.
  Future<void> toCheck(
    WidgetTester tester, {
    String url = 'https://llm.example/v1',
  }) async {
    await toKey(tester, url: url);
    await tester.tap(_key('provider-wizard-key-none'));
    await frames(tester, 2);
    await next(tester);
  }

  Future<void> toModel(WidgetTester tester) async {
    await toCheck(tester);
    session.wizardCheck.respond(
      const CheckOk([RemoteModel('m1', contextWindow: 8000)]),
    );
    await frames(tester);
  }

  Future<void> toReview(WidgetTester tester) async {
    await toModel(tester);
    await tester.tap(_key('provider-wizard-model-m1'));
    await frames(tester);
  }

  Future<void> selectLanguage(
    WidgetTester tester,
    CodeLabTestBinding binding,
    AppLanguagePreference preference,
  ) async {
    await tester.runAsync(
      () => binding.scope.resolve<AppLanguageCubit>().select(preference),
    );
    await frames(tester, 4);
  }

  Future<void> cancelWizard(WidgetTester tester) async {
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }

  List<String> steps(WidgetTester tester) => tester
      .widget<CodeLabStepBreadcrumb>(find.byType(CodeLabStepBreadcrumb))
      .steps;

  String textsOf(WidgetTester tester, Finder scope) => tester
      .widgetList<Text>(find.descendant(of: scope, matching: find.byType(Text)))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join(' | ');

  group('en: прежние строки мастера', () {
    testWidgets('заголовок, строка шагов и кнопки первого шага', (
      tester,
    ) async {
      await openPage(tester);

      await openWizard(tester);

      expect(find.text('Add provider'), findsWidgets);
      expect(steps(tester), [
        'API type',
        'Base URL',
        'Key',
        'Check',
        'Model',
        'Review',
      ]);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });
  });

  group('ru: шаги мастера', () {
    testWidgets('шаг «API type»: заголовок, строка шагов, кнопки; подписи '
        'пресетов от моста не переводятся', (tester) async {
      await openPage(tester, locale: const Locale('ru'));

      await openWizard(tester);

      expect(_key('provider-wizard'), findsOneWidget);
      expect(find.text('Добавить провайдера'), findsWidgets);
      expect(steps(tester), [
        'Тип API',
        'Базовый URL',
        'Ключ',
        'Проверка',
        'Модель',
        'Обзор',
      ]);
      expect(find.text('Тип API'), findsWidgets);
      expect(find.text('Далее'), findsOneWidget);
      expect(find.text('Отмена'), findsOneWidget);
      expect(_key('provider-wizard-back'), findsNothing);
      // Пресеты: `ollama`, `custom-openai`, `custom-anthropic` переводятся по
      // `id`, имена провайдеров — нет.
      expect(find.text('OpenAI'), findsOneWidget);
      expect(find.text('Anthropic'), findsOneWidget);
      expect(find.text('OpenRouter'), findsOneWidget);
      expect(find.text('Ollama (локально, без ключа)'), findsOneWidget);
      expect(find.text('Свой адрес, совместимый с OpenAI'), findsOneWidget);
      expect(find.text('Свой адрес, совместимый с Anthropic'), findsOneWidget);
      expect(find.text('Ollama (local, no key)'), findsNothing);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('правка провайдера: «Изменить провайдера <id>»', (
      tester,
    ) async {
      await openPage(tester, locale: const Locale('ru'));

      await openWizard(tester, editId: 'local');

      expect(find.text('Изменить провайдера local'), findsOneWidget);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('шаг «Base URL»: подпись, сводка пройденного, «Назад»', (
      tester,
    ) async {
      await openPage(tester, locale: const Locale('ru'));

      await toBaseUrl(tester);

      expect(find.text('Базовый URL'), findsWidgets);
      // Сводка пройденных шагов: подпись «Type» и значение по `id` пресета.
      expect(find.text('Тип'), findsOneWidget);
      expect(find.text('Свой адрес, совместимый с OpenAI'), findsOneWidget);
      expect(find.text('Назад'), findsOneWidget);
      expect(find.text('Далее'), findsOneWidget);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('`http://` к другой машине: ключ уйдёт без шифрования '
        '(security)', (tester) async {
      await openPage(tester, locale: const Locale('ru'));
      await toBaseUrl(tester);

      await tester.enterText(
        _key('provider-wizard-base-url-field'),
        'http://api.example.com/v1',
      );
      await next(tester);

      expect(
        find.text('Ключ отправляется в открытом виде на api.example.com.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('provider-wizard-insecure'),
          matching: find.text('Всё равно использовать http'),
        ),
        findsOneWidget,
      );
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('шаг «Key»: подпись, способы ключа и поля', (tester) async {
      await openPage(tester, locale: const Locale('ru'));

      await toKey(tester);

      expect(find.text('Источник ключа API'), findsOneWidget);
      expect(
        find.text('Сохранить в file как «codelab/llm-example»'),
        findsOneWidget,
      );
      expect(find.text('Читать из переменной окружения'), findsOneWidget);
      expect(find.text('Без ключа'), findsOneWidget);
      await tester.tap(_key('provider-wizard-key-store'));
      await frames(tester, 2);
      expect(find.text('Ключ API'), findsOneWidget);
      await tester.tap(_key('provider-wizard-key-env'));
      await frames(tester, 2);
      expect(find.text('Имя переменной'), findsOneWidget);
      // Сводка пройденных шагов: адрес как есть.
      expect(find.text('https://llm.example/v1'), findsOneWidget);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('бэкенд только для чтения: жёлтый баннер — заголовок на '
        'русском, подсказка хранилища под ним как есть, один раз', (
      tester,
    ) async {
      store.backend = const SecretBackendInfo(
        id: 'env',
        writable: false,
        unavailableReason: 'Secrets are read from the environment.',
      );
      session.readOnlyHint =
          "secret store env is read-only. Add 'secrets.backend: file' to "
          'config.yaml.';
      await openPage(tester, locale: const Locale('ru'));
      await toKey(tester);

      final banner = _key('provider-wizard-key-readonly');
      expect(banner, findsOneWidget);
      final text = textsOf(tester, banner);
      expect(text, contains('Хранилище секретов доступно только для чтения.'));
      expect(text, contains("secret store env is read-only. Add 'secrets."));
      expect(
        find.textContaining("secret store env is read-only. Add 'secrets."),
        findsOneWidget,
      );
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('пустой ключ: ошибка шага по коду моста, перевод «Enter the '
        'API key.»', (tester) async {
      await openPage(tester, locale: const Locale('ru'));
      await toKey(tester);
      await tester.tap(_key('provider-wizard-key-store'));
      await frames(tester, 2);

      await next(tester);

      expect(find.text('Введите ключ API.'), findsOneWidget);
      expect(find.text('Enter the API key.'), findsNothing);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('пустое имя переменной: ошибка шага по коду', (tester) async {
      await openPage(tester, locale: const Locale('ru'));
      await toKey(tester);
      await tester.tap(_key('provider-wizard-key-env'));
      await frames(tester, 2);
      await tester.enterText(_key('provider-wizard-env-field'), '');

      await next(tester);

      expect(find.text('Введите имя переменной окружения.'), findsOneWidget);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('en: сообщение о существующем ключе показано один раз', (
      tester,
    ) async {
      session.secrets['codelab/llm-example'] = 'old-value';
      await openPage(tester);

      await toKey(tester);

      expect(
        find.text('A stored key codelab/llm-example already exists in file.'),
        findsOneWidget,
      );
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('план без проверки: «Not verified» словами (timeout и '
        'unreachable)', (tester) async {
      for (final (kind, ruText) in [
        (
          ProviderCheckFailureKind.timeout,
          'Не проверено: истекло время ожидания',
        ),
        (
          ProviderCheckFailureKind.unreachable,
          'Не проверено: сервер недоступен',
        ),
      ]) {
        await openPage(tester, locale: const Locale('ru'));
        await toCheck(tester);
        session.wizardCheck.respond(
          CheckFailure(ProviderCheckFailure(kind: kind, message: 'x')),
        );
        await frames(tester);
        await tester.tap(_key('provider-wizard-skip-check'));
        await frames(tester, 2);
        await tester.tap(_key('provider-wizard-skip-confirm'));
        await frames(tester);
        await tester.enterText(
          _key('provider-wizard-model-manual-field'),
          'my-model',
        );
        await next(tester);
        await next(tester);

        expect(find.text(ruText), findsOneWidget, reason: kind.name);
        expect(find.textContaining('Not verified'), findsNothing);
        await cancelWizard(tester);
        await tearDownApp(tester);
      }
    });

    testWidgets('en: «Not verified: unreachable» — значение провода как есть', (
      tester,
    ) async {
      await openPage(tester);
      await toCheck(tester);
      session.wizardCheck.respond(
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.unreachable,
            message: 'x',
          ),
        ),
      );
      await frames(tester);
      await tester.tap(_key('provider-wizard-skip-check'));
      await frames(tester, 2);
      await tester.tap(_key('provider-wizard-skip-confirm'));
      await frames(tester);
      await tester.enterText(
        _key('provider-wizard-model-manual-field'),
        'my-model',
      );
      await next(tester);
      await next(tester);

      expect(find.text('Not verified: unreachable'), findsOneWidget);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('сохранённый ключ уже есть: замечание с именем и хранилищем, '
        'варианты «Использовать» и «Заменить» (security)', (tester) async {
      session.secrets['codelab/llm-example'] = 'old-value';
      await openPage(tester, locale: const Locale('ru'));

      await toKey(tester);

      expect(
        find.text('Сохранённый ключ «codelab/llm-example» уже есть в file.'),
        findsOneWidget,
      );
      expect(find.text('Использовать сохранённый ключ'), findsOneWidget);
      expect(find.text('Заменить его'), findsOneWidget);
      // Английский дубль замечания не показывается.
      expect(find.textContaining('A stored key'), findsNothing);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('шаг «Check»: ожидание ответа и сводка с «Без ключа»', (
      tester,
    ) async {
      await openPage(tester, locale: const Locale('ru'));

      await toCheck(tester);

      expect(find.text('Проверяем адрес и ключ…'), findsOneWidget);
      expect(find.text('Ключ'), findsWidgets);
      expect(find.text('Без ключа'), findsWidgets);
      expect(
        find.textContaining('GET https://llm.example/v1/models'),
        findsOneWidget,
      );
      session.wizardCheck.respond(const CheckOk([RemoteModel('m1')]));
      await frames(tester);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('отказ «Model list not found»: заголовок, пояснение, '
        'строка запроса, варианты продолжения', (tester) async {
      await openPage(tester, locale: const Locale('ru'));
      await toCheck(tester, url: 'https://llm.example');

      session.wizardCheck.respond(
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.notFound,
            statusCode: 404,
            message: 'x',
          ),
        ),
      );
      await frames(tester);

      final failure = _key('provider-wizard-check-failure');
      final text = textsOf(tester, failure);
      expect(text, contains('Список моделей не найден (404)'));
      expect(
        text,
        contains(
          'Сервер ответил, но GET /models не существует. Серверы '
          'OpenAI-compatible обычно находятся по адресу /v1.',
        ),
      );
      // Строка запроса — диагностика, не переводится (D7).
      expect(text, contains('GET https://llm.example/models → 404'));
      expect(find.text('Как продолжить?'), findsOneWidget);
      expect(find.text('Использовать https://llm.example/v1'), findsOneWidget);
      expect(find.text('Ввести модель вручную'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);

      await tester.tap(_key('provider-wizard-manual-model'));
      await frames(tester, 2);
      expect(
        tester
            .widget<TextBox>(_key('provider-wizard-manual-model-field'))
            .placeholder,
        'ID модели',
      );
      expect(find.text('Продолжить'), findsOneWidget);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('сервер недоступен: «Save without check» и подтверждение '
        'без проверки', (tester) async {
      await openPage(tester, locale: const Locale('ru'));
      await toCheck(tester);

      session.wizardCheck.respond(
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.unreachable,
            message: 'x',
          ),
        ),
      );
      await frames(tester);

      expect(
        textsOf(tester, _key('provider-wizard-check-failure')),
        contains('Сервер недоступен'),
      );
      expect(find.text('Сохранить без проверки'), findsOneWidget);
      await tester.tap(_key('provider-wizard-skip-check'));
      await frames(tester, 2);
      expect(
        textsOf(tester, _key('provider-wizard-skip-warning')),
        contains(
          'Адрес и ключ не проверены, список моделей недоступен. Модель '
          'придётся ввести самостоятельно.',
        ),
      );
      expect(find.text('Продолжить без проверки'), findsOneWidget);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('другие отказы проверки: заголовки по виду', (tester) async {
      await openPage(tester, locale: const Locale('ru'));
      await toCheck(tester);

      session.wizardCheck.respond(
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.unauthorized,
            statusCode: 401,
            message: 'x',
          ),
        ),
      );
      await frames(tester);

      expect(
        textsOf(tester, _key('provider-wizard-check-failure')),
        contains('Ключ отклонён (401)'),
      );
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('шаг «Model»: фильтр и ручной ввод', (tester) async {
      await openPage(tester, locale: const Locale('ru'));

      await toModel(tester);

      expect(find.text('Модель (введите для фильтра)'), findsOneWidget);
      expect(find.text('Ввести ID модели вручную'), findsOneWidget);
      await tester.tap(_key('provider-wizard-model-manual'));
      await frames(tester, 2);
      expect(
        tester
            .widget<TextBox>(_key('provider-wizard-model-manual-field'))
            .placeholder,
        'ID модели',
      );
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('проверка пропущена: список моделей не проверен, '
        'ограничения модели', (tester) async {
      await openPage(tester, locale: const Locale('ru'));
      await toCheck(tester);
      session.wizardCheck.respond(
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.unreachable,
            message: 'x',
          ),
        ),
      );
      await frames(tester);
      await tester.tap(_key('provider-wizard-skip-check'));
      await frames(tester, 2);
      await tester.tap(_key('provider-wizard-skip-confirm'));
      await frames(tester);

      expect(
        find.text('Список моделей не проверен: введите ID модели.'),
        findsOneWidget,
      );
      await tester.enterText(
        _key('provider-wizard-model-manual-field'),
        'my-model',
      );
      await next(tester);

      expect(find.text('Ограничения my-model'), findsOneWidget);
      expect(find.text('Окно контекста'), findsOneWidget);
      expect(
        find.text('Максимум токенов вывода (необязательно)'),
        findsOneWidget,
      );
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('шаг «Review»: сводка плана, флажки и кнопка «Сохранить»', (
      tester,
    ) async {
      await openPage(tester, locale: const Locale('ru'));

      await toReview(tester);

      for (final label in const ['Провайдер', 'Ключ', 'Модель', 'Файл']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Без ключа'), findsNothing);
      expect(
        find.text('llm-example (openai-compatible, https://llm.example/v1)'),
        findsOneWidget,
      );
      expect(find.text('Сделать моделью по умолчанию'), findsOneWidget);
      expect(find.text('Только этот проект'), findsOneWidget);
      expect(find.text('Сохранить'), findsOneWidget);
      expect(find.text('Назад'), findsOneWidget);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('конфиг изменился на диске: уведомление на «Review»', (
      tester,
    ) async {
      store.firstOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      await openPage(tester, locale: const Locale('ru'));
      await toReview(tester);

      await tester.tap(_key('provider-wizard-save'));
      await frames(tester, 20);

      expect(
        textsOf(tester, _key('provider-wizard-review-notice')),
        'Конфигурация изменилась на диске — проверьте и сохраните снова',
      );
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('запись не удалась: текст отказа без текста исключения', (
      tester,
    ) async {
      store.onApply = () =>
          throw StateError('yaml near sk-test-leak-0123456789');
      await openPage(tester, locale: const Locale('ru'));
      await toReview(tester);

      await tester.tap(_key('provider-wizard-save'));
      await frames(tester, 20);

      expect(
        textsOf(tester, _key('provider-wizard-save-failed')),
        'Конфигурация не сохранена (StateError).',
      );
      expect(find.textContaining('sk-test-leak-0123456789'), findsNothing);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });
  });

  group('смена языка в открытом мастере (D5 п. 9)', () {
    testWidgets('шаг «Base URL»: подписи пересобираются, введённый адрес и '
        'предупреждение об `http://` остаются', (tester) async {
      final binding = await openPage(tester);
      await toBaseUrl(tester);
      await tester.enterText(
        _key('provider-wizard-base-url-field'),
        'http://api.example.com/v1',
      );
      await next(tester);
      expect(
        find.text('The key is sent unencrypted to api.example.com.'),
        findsOneWidget,
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(find.text('Добавить провайдера'), findsWidgets);
      expect(steps(tester).first, 'Тип API');
      expect(find.text('Базовый URL'), findsWidgets);
      expect(
        find.text('Ключ отправляется в открытом виде на api.example.com.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextBox>(_key('provider-wizard-base-url-field'))
            .controller!
            .text,
        'http://api.example.com/v1',
      );
      await expectNoStaleLanguage(tester, from: en, to: ru);

      await selectLanguage(tester, binding, AppLanguagePreference.en);
      expect(steps(tester).first, 'API type');
      await expectNoStaleLanguage(tester, from: ru, to: en);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('шаг «Key»: варианты пересобираются, выбор и введённый ключ '
        'остаются; значение ключа на экран не попадает', (tester) async {
      final binding = await openPage(tester);
      await toKey(tester);
      await tester.tap(_key('provider-wizard-key-store'));
      await frames(tester, 2);
      await tester.enterText(
        _key('provider-wizard-key-field'),
        'sk-test-leak-0123456789',
      );
      await frames(tester, 2);
      expect(
        find.text('Store in file as "codelab/llm-example"'),
        findsOneWidget,
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        find.text('Сохранить в file как «codelab/llm-example»'),
        findsOneWidget,
      );
      expect(find.text('Ключ API'), findsOneWidget);
      expect(
        tester
            .widget<PasswordBox>(_key('provider-wizard-key-field'))
            .controller!
            .text,
        'sk-test-leak-0123456789',
      );
      // Скрытое поле ввода остаётся на экране, а `find.textContaining` видит и
      // `EditableText`; значения нет ни в одном `Text` (как в en-тестах).
      expect(
        findVisibleTextContaining('sk-test-leak-0123456789'),
        findsNothing,
      );
      await expectNoStaleLanguage(tester, from: en, to: ru);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('отказ проверки: заголовок и пояснение пересобираются, '
        'выбранный способ и введённая модель остаются', (tester) async {
      final binding = await openPage(tester);
      await toCheck(tester, url: 'https://llm.example');
      session.wizardCheck.respond(
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.notFound,
            statusCode: 404,
            message: 'x',
          ),
        ),
      );
      await frames(tester);
      await tester.tap(_key('provider-wizard-manual-model'));
      await frames(tester, 2);
      await tester.enterText(
        _key('provider-wizard-manual-model-field'),
        'my-model',
      );
      await frames(tester, 2);
      expect(
        textsOf(tester, _key('provider-wizard-check-failure')),
        contains('Model list not found (404)'),
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        textsOf(tester, _key('provider-wizard-check-failure')),
        contains('Список моделей не найден (404)'),
      );
      expect(
        tester
            .widget<TextBox>(_key('provider-wizard-manual-model-field'))
            .controller!
            .text,
        'my-model',
      );
      expect(find.text('Продолжить'), findsOneWidget);
      await expectNoStaleLanguage(tester, from: en, to: ru);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('«Review» с уведомлением о конфликте: сводка и уведомление '
        'пересобираются, план и автомат не тронуты', (tester) async {
      store.firstOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      final binding = await openPage(tester);
      await toReview(tester);
      await tester.tap(_key('provider-wizard-save'));
      await frames(tester, 20);
      expect(
        textsOf(tester, _key('provider-wizard-review-notice')),
        'Config changed on disk — review and save again',
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        textsOf(tester, _key('provider-wizard-review-notice')),
        'Конфигурация изменилась на диске — проверьте и сохраните снова',
      );
      expect(find.text('Провайдер'), findsWidgets);
      expect(store.applied, hasLength(1));
      await expectNoStaleLanguage(tester, from: en, to: ru);

      await selectLanguage(tester, binding, AppLanguagePreference.en);
      expect(
        textsOf(tester, _key('provider-wizard-review-notice')),
        'Config changed on disk — review and save again',
      );
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('отказ записи остаётся на экране и переводится', (
      tester,
    ) async {
      store.onApply = () => throw StateError('disk is full');
      final binding = await openPage(tester);
      await toReview(tester);
      await tester.tap(_key('provider-wizard-save'));
      await frames(tester, 20);
      expect(
        textsOf(tester, _key('provider-wizard-save-failed')),
        'The config was not saved (StateError).',
      );

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(
        textsOf(tester, _key('provider-wizard-save-failed')),
        'Конфигурация не сохранена (StateError).',
      );
      await expectNoStaleLanguage(tester, from: en, to: ru);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });

    testWidgets('смена языка не посылает автомату событий и ничего не '
        'пишет', (tester) async {
      final binding = await openPage(tester);
      await toReview(tester);
      final events = session.wizardLog.entries.length;

      await selectLanguage(tester, binding, AppLanguagePreference.ru);

      expect(session.wizardLog.entries, hasLength(events));
      expect(store.applied, isEmpty);
      expect(_key('provider-wizard-review'), findsOneWidget);
      await cancelWizard(tester);
      await tearDownApp(tester);
    });
  });
}
