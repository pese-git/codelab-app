// Красные тесты задачи 4.1 change `add-desktop-localization`:
// `ProviderWizardCubit` и модель отображения мастера `provider_wizard_view.dart`
// (spec app-settings «Мастер провайдера в app», «Локализация интерфейса app»,
// сценарии «Команда в переведённой фразе», «Закрытый компонент не реагирует на
// смену языка»; design.md D5, D6, D7, D9, D12).
//
// Что проверяется. Сводка пройденных шагов, варианты ключа, заголовки отказов
// проверки, заголовок диалога и уведомление «Config changed on disk» —
// производный текст: функция «(входы, язык)». Функции модели получают каталог
// параметром `l10n` (`AppLocalizations`), а Cubit пересобирает `summary` и
// `reviewNotice` из последнего состояния автомата при смене языка и не трогает
// сам автомат. Текст отказа записи (`wizardSaveFailureText`) содержит команду
// `codelab secret delete <имя>`: она, имена секретов и ключи конфигурации —
// плейсхолдеры (сценарий «Команда в переведённой фразе»). Баннер после записи
// — разовое сообщение (D5), его текст собирает presentation
// (`providers_page_l10n_test.dart`).
//
// Заглушка задачи 4.1: параметр `strings` у `ProviderWizardCubit` и `l10n` у
// функций модели приняты и не используются, поэтому проверки перевода красные
// на `expect`, а проверки «прежние строки на en» зелёные. Русские строки — по
// глоссарию («провайдер», «ключ», «модель», «хранилище секретов», «окружение»);
// остальные — вне глоссария (отчёт задачи 4.1); сообщения с меткой security
// вычитывает пользователь (задача 4.3, D14).

import 'package:codelab_desktop/app/language/app_language_cubit.dart'
    show AppStrings;
import 'package:codelab_desktop/features/settings/application/provider_wizard_cubit.dart';
import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_strings.dart';
import '../../../support/fake_provider_settings.dart';
import '../../../support/recording_logger.dart';

final _en = AppLocalizationsEn();
final _ru = AppLocalizationsRu();

Map<String, Object?> _existing() => {
  'agent': {'default_model': 'local/qwen'},
  'providers': {
    'local': providerMap(
      baseUrl: 'http://localhost:11434/v1',
      models: ['qwen'],
    ),
  },
};

ProviderDraft _draft() =>
    const ProviderDraft(providerId: 'x', kind: 'openai-compatible');

CheckFailed _failed(
  ProviderCheckFailureKind kind, {
  int? status,
  bool v1 = false,
}) => CheckFailed(
  _draft(),
  ProviderCheckFailure(kind: kind, message: 'm', statusCode: status),
  Uri.parse('https://llm.internal.example/models'),
  const Duration(milliseconds: 212),
  canSkip: false,
  canUseV1: v1,
);

void main() {
  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;
  late RecordingLogger log;
  late List<ProviderWizardCubit> cubits;
  late TestAppStrings strings;

  setUp(() {
    store = FakeAgentConfigStore(user: _existing());
    session = FakeProviderSettingsSession(store);
    log = RecordingLogger();
    cubits = [];
    strings = TestAppStrings(AppLocalizationsEn());
    addTearDown(strings.close);
  });

  tearDown(() async {
    for (final cubit in cubits) {
      await cubit.close();
    }
  });

  Future<ProviderEntryView> entryOf(String id) async {
    final snapshot = await store.snapshot(cwd: '/work/app');
    final entries = await providerEntriesOf(
      snapshot,
      environment: const {},
      isSecretSet: session.isSecretSet,
    );
    return entries.firstWhere((e) => e.id == id);
  }

  Future<ProviderWizardCubit> open(
    AppStrings port, {
    ProviderEntryView? editing,
  }) async {
    final flow = await session.openWizard(editing: editing);
    final cubit = ProviderWizardCubit(
      flow: flow,
      access: session.access,
      backendId: store.backend.id,
      editingId: editing?.id,
      isAgentConnected: () => true,
      logger: log,
      strings: port,
    );
    cubits.add(cubit);
    return cubit;
  }

  Future<void> toKeyStep(ProviderWizardCubit cubit) async {
    cubit.dispatch(const PresetChosen('custom-openai'));
    await pumpEventQueue();
    cubit.dispatch(const BaseUrlSubmitted('https://llm.example/v1'));
    await pumpEventQueue();
  }

  Future<void> toReview(ProviderWizardCubit cubit, {KeyChoice? key}) async {
    await toKeyStep(cubit);
    cubit.dispatch(KeySubmitted(key ?? StoreSecret(SecretValue(leakMarker))));
    await pumpEventQueue();
    session.wizardCheck.respond(
      const CheckOk([RemoteModel('m1', contextWindow: 8000)]),
    );
    await pumpEventQueue();
    cubit.dispatch(const ModelChosen('m1'));
    await pumpEventQueue();
  }

  List<(String, String)> summaryOf(ProviderWizardCubit cubit) => [
    for (final row in cubit.state.summary) (row.label, row.value),
  ];

  Future<void> switchTo(AppLocalizations next) async {
    strings.emit(next);
    await pumpEventQueue();
  }

  group('FixedAppStrings(en): прежние строки', () {
    final fixedEn = FixedAppStrings(AppLocalizationsEn());

    test('заголовок диалога, сводка и варианты ключа', () async {
      final cubit = await open(fixedEn);
      expect(cubit.title, 'Add provider');
      await toKeyStep(cubit);
      expect(summaryOf(cubit).map((r) => r.$1), ['Type', 'Base URL']);

      final options = wizardKeyOptions(
        cubit.state.setup as ChoosingKey,
        l10n: _en,
      );
      expect(options.map((o) => o.label), [
        'Store in file as "codelab/llm-example"',
        'Read from environment variable',
        'No key',
      ]);

      final edit = await open(fixedEn, editing: await entryOf('local'));
      expect(edit.title, 'Edit provider local');
    });

    test('функции модели с каталогом en дают прежние тексты', () {
      expect(
        checkFailureTitle(
          _failed(ProviderCheckFailureKind.unauthorized, status: 401),
          l10n: _en,
        ),
        'Key rejected (401)',
      );
      expect(
        checkFailureTitle(_failed(ProviderCheckFailureKind.timeout), l10n: _en),
        'Timed out after 10 s',
      );
      expect(
        checkFailureNote(
          _failed(ProviderCheckFailureKind.notFound, status: 404),
          l10n: _en,
        ),
        'The server answered, but GET /models does not exist. '
        'OpenAI-compatible servers usually live under /v1.',
      );
    });
  });

  group('заголовок диалога и сводка шагов на ru', () {
    test(
      'заголовок: добавление и правка, id провайдера — плейсхолдер',
      () async {
        final add = await open(FixedAppStrings(AppLocalizationsRu()));
        expect(add.title, 'Добавить провайдера');

        final edit = await open(
          FixedAppStrings(AppLocalizationsRu()),
          editing: await entryOf('local'),
        );
        expect(edit.title, 'Изменить провайдера local');
      },
    );

    test('заголовок пересобирается при смене языка', () async {
      final cubit = await open(strings);
      expect(cubit.title, 'Add provider');

      await switchTo(AppLocalizationsRu());
      expect(cubit.title, 'Добавить провайдера');

      await switchTo(AppLocalizationsEn());
      expect(cubit.title, 'Add provider');
    });

    test('подписи сводки по шагам: адрес — как есть, ключ — одним '
        'сообщением с плейсхолдерами', () async {
      final cubit = await open(strings);
      await toKeyStep(cubit);
      expect(summaryOf(cubit).map((r) => r.$1), ['Type', 'Base URL']);

      await switchTo(AppLocalizationsRu());

      expect(summaryOf(cubit).map((r) => r.$1), ['Тип', 'Базовый URL']);
      // Значение «Type» — по `id` пресета, а не по английской подписи.
      expect(summaryOf(cubit).first.$2, 'Свой адрес, совместимый с OpenAI');
      expect(summaryOf(cubit).last.$2, 'https://llm.example/v1');
      expect(cubit.state.setup, isA<ChoosingKey>());

      cubit.dispatch(KeySubmitted(StoreSecret(SecretValue(leakMarker))));
      await pumpEventQueue();
      // Проверка идёт: сводка уже с ключом.
      expect(summaryOf(cubit).map((r) => r.$1), ['Тип', 'Базовый URL', 'Ключ']);
      expect(
        summaryOf(cubit).last.$2,
        'Сохранить в file как «codelab/llm-example»',
      );
    });

    test('сводка «Review»: провайдер, ключ, модель, файл на ru и обратно; '
        'значение ключа не попадает на экран', () async {
      final cubit = await open(strings);
      await toReview(cubit);
      expect(summaryOf(cubit), [
        ('Provider', 'llm-example (openai-compatible, https://llm.example/v1)'),
        ('Key', 'secret "codelab/llm-example" (file)'),
        ('Model', 'llm-example/m1'),
        ('File', '/home/u/.codelab/config.yaml'),
      ]);
      final setup = cubit.state.setup;

      await switchTo(AppLocalizationsRu());

      expect(summaryOf(cubit), [
        (
          'Провайдер',
          'llm-example (openai-compatible, https://llm.example/v1)',
        ),
        ('Ключ', 'секрет «codelab/llm-example» (file)'),
        ('Модель', 'llm-example/m1'),
        ('Файл', '/home/u/.codelab/config.yaml'),
      ]);
      // Автомат не тронут: тот же шаг, то же состояние.
      expect(identical(cubit.state.setup, setup), isTrue);
      expect(summaryOf(cubit).toString(), isNot(contains(leakMarker)));

      await switchTo(AppLocalizationsEn());
      expect(summaryOf(cubit).first.$1, 'Provider');
    });

    test('«Review» с переменной окружения, без ключа и с прежним ключом: '
        'способы хранения на ru', () async {
      strings = TestAppStrings(AppLocalizationsRu());
      final env = await open(strings);
      await toReview(env, key: const UseEnvVar('LLM_API_KEY'));
      expect(summaryOf(env)[1], ('Ключ', 'переменная окружения LLM_API_KEY'));

      final none = await open(strings);
      await toReview(none, key: const NoKey());
      expect(summaryOf(none)[1], ('Ключ', 'нет'));
    });

    test('шаг с выбранной переменной: «Читать из переменной окружения '
        '(NAME)»', () async {
      strings = TestAppStrings(AppLocalizationsRu());
      final cubit = await open(strings);
      await toKeyStep(cubit);
      cubit.dispatch(const KeySubmitted(UseEnvVar('LLM_API_KEY')));
      await pumpEventQueue();

      expect(summaryOf(cubit).last, (
        'Ключ',
        'Читать из переменной окружения (LLM_API_KEY)',
      ));
    });
  });

  group('варианты шага «API key source» на ru', () {
    test('запись в хранилище, переменная, без ключа', () async {
      final cubit = await open(strings);
      await toKeyStep(cubit);
      final key = cubit.state.setup as ChoosingKey;

      final options = wizardKeyOptions(key, l10n: _ru);

      expect(options.map((o) => o.kind), [
        WizardKeyKind.store,
        WizardKeyKind.environment,
        WizardKeyKind.none,
      ]);
      expect(options.map((o) => o.label), [
        'Сохранить в file как «codelab/llm-example»',
        'Читать из переменной окружения',
        'Без ключа',
      ]);
    });

    test('имя переменной по подсказке пресета — плейсхолдер', () async {
      final cubit = await open(strings);
      cubit.dispatch(const PresetChosen('openai'));
      await pumpEventQueue();
      cubit.dispatch(const BaseUrlSubmitted('https://api.openai.com/v1'));
      await pumpEventQueue();

      final options = wizardKeyOptions(
        cubit.state.setup as ChoosingKey,
        l10n: _ru,
      );

      expect(options.map((o) => o.label), [
        'Сохранить в file как «codelab/openai»',
        'Читать из переменной окружения (OPENAI_API_KEY)',
        'Без ключа',
      ]);
    });

    test('сохранённый ключ уже есть: «Использовать» и «Заменить»', () async {
      session.secrets['codelab/llm-example'] = 'old-value';
      final cubit = await open(strings);
      await toKeyStep(cubit);

      final options = wizardKeyOptions(
        cubit.state.setup as ChoosingKey,
        l10n: _ru,
      );

      expect(options.first.label, 'Использовать сохранённый ключ');
      expect(options[1].label, 'Заменить его');
    });

    test('правка: «Keep the current key»', () async {
      // Исправлено в задаче 4.2: у провайдера `local` из `_existing()` ключа
      // нет, а автомат предлагает «оставить текущий ключ» только у провайдера
      // с ключом, которого нет в хранилище (`_keyState`: `editing.key is!
      // KeyNone`, `existing == null`). Фикстура теста — провайдер с
      // переменной окружения; утверждение о подписи не менялось.
      store.user = {
        'agent': {'default_model': 'local/qwen'},
        'providers': {
          'local': providerMap(
            baseUrl: 'http://localhost:11434/v1',
            models: ['qwen'],
            env: 'LOCAL_API_KEY',
          ),
        },
      };
      final cubit = await open(strings, editing: await entryOf('local'));
      cubit.dispatch(const BaseUrlSubmitted('http://localhost:11434/v1'));
      await pumpEventQueue();

      final options = wizardKeyOptions(
        cubit.state.setup as ChoosingKey,
        l10n: _ru,
      );

      expect(options.map((o) => o.label), contains('Оставить текущий ключ'));
    });
  });

  group('отказ проверки на ru', () {
    test('заголовки по виду отказа; код HTTP и секунды — плейсхолдеры', () {
      String title(ProviderCheckFailureKind kind, {int? status}) =>
          checkFailureTitle(_failed(kind, status: status), l10n: _ru);

      expect(
        title(ProviderCheckFailureKind.unauthorized, status: 401),
        'Ключ отклонён (401)',
      );
      expect(title(ProviderCheckFailureKind.unauthorized), 'Ключ отклонён');
      expect(
        title(ProviderCheckFailureKind.notFound, status: 404),
        'Список моделей не найден (404)',
      );
      expect(
        title(ProviderCheckFailureKind.notFound),
        'Список моделей не найден (404)',
      );
      expect(title(ProviderCheckFailureKind.unreachable), 'Сервер недоступен');
      expect(
        title(ProviderCheckFailureKind.timeout),
        'Время ожидания истекло: 10 с',
      );
      expect(title(ProviderCheckFailureKind.tlsError), 'Ошибка TLS');
      expect(
        title(ProviderCheckFailureKind.badResponse, status: 500),
        'Неожиданный ответ (500)',
      );
      expect(title(ProviderCheckFailureKind.badResponse), 'Неожиданный ответ');
    });

    test('пояснение — только у «Model list not found»', () {
      expect(
        checkFailureNote(
          _failed(ProviderCheckFailureKind.notFound, status: 404),
          l10n: _ru,
        ),
        'Сервер ответил, но GET /models не существует. Серверы '
        'OpenAI-compatible обычно находятся по адресу /v1.',
      );
      expect(
        checkFailureNote(
          _failed(ProviderCheckFailureKind.unauthorized, status: 401),
          l10n: _ru,
        ),
        isNull,
      );
    });

    test('строка запроса — диагностика, язык её не меняет (D7)', () {
      expect(
        checkRequestLine(
          _failed(ProviderCheckFailureKind.notFound, status: 404),
        ),
        'GET https://llm.internal.example/models → 404 · 212 ms',
      );
    });
  });

  group('отказ записи: команда внутри переведённой фразы (security)', () {
    Future<SaveFailed> failedWith(
      ProviderWizardCubit cubit,
      ProviderConfigNotSaved failure,
    ) async {
      await toReview(cubit);
      final plan = (cubit.state.setup as Reviewing).plan;
      return SaveFailed(plan, failure);
    }

    test('сбой записи конфигурации: тип ошибки в скобках', () async {
      final cubit = await open(strings);
      final failed = await failedWith(
        cubit,
        const ProviderConfigNotSaved(
          outcome: null,
          errorType: 'StateError',
          keyReplaced: false,
          rollback: KeyRollback.deleted,
        ),
      );

      expect(
        wizardSaveFailureText(failed, l10n: _en),
        'The config was not saved (StateError).',
      );
      expect(
        wizardSaveFailureText(failed, l10n: _ru),
        'Конфигурация не сохранена (StateError).',
      );
    });

    test('ключ заменён, откат не удался: имя секрета и команда без '
        'изменений', () async {
      final cubit = await open(strings);
      final failed = await failedWith(
        cubit,
        const ProviderConfigNotSaved(
          outcome: null,
          errorType: null,
          keyReplaced: true,
          rollback: KeyRollback.failed,
        ),
      );

      expect(
        wizardSaveFailureText(failed, l10n: _en),
        'The config was not saved. The stored key codelab/llm-example was '
        'already replaced. The new key codelab/llm-example is still in the '
        'secret store. Delete it with: codelab secret delete '
        'codelab/llm-example',
      );
      expect(
        wizardSaveFailureText(failed, l10n: _ru),
        'Конфигурация не сохранена. Сохранённый ключ «codelab/llm-example» уже '
        'заменён. Новый ключ «codelab/llm-example» остался в хранилище '
        'секретов. Удалите его командой: codelab secret delete '
        'codelab/llm-example',
      );
    });

    test('секрет значением в конфиге: путь ключа — плейсхолдер', () async {
      final cubit = await open(strings);
      final failed = await failedWith(
        cubit,
        const ProviderConfigNotSaved(
          outcome: ConfigInlineSecret(
            key: 'providers.llm-example.api_key',
            suggestedSecretName: 'codelab/llm-example',
          ),
          errorType: null,
          keyReplaced: false,
          rollback: KeyRollback.none,
        ),
      );

      expect(
        wizardSaveFailureText(failed, l10n: _ru),
        'Конфигурация не сохранена: providers.llm-example.api_key не должен '
        'содержать секрет в открытом виде.',
      );
    });

    test('конфиг отклонён: проблемы загрузчика — как есть (D6, D7)', () async {
      final cubit = await open(strings);
      final failed = await failedWith(
        cubit,
        ProviderConfigNotSaved(
          outcome: ConfigRejected([
            ConfigIssue(
              kind: ConfigIssueKind.value,
              key: 'agent.default_model',
              source: FakeAgentConfigStore.userPath,
              message: 'unknown model',
            ),
          ]),
          errorType: null,
          keyReplaced: false,
          rollback: KeyRollback.none,
        ),
      );

      expect(
        wizardSaveFailureText(failed, l10n: _ru),
        'Конфигурация не сохранена: agent.default_model: unknown model',
      );
    });

    test('значение ключа в тексте отказа нет ни на каком языке', () async {
      final cubit = await open(strings);
      final failed = await failedWith(
        cubit,
        const ProviderConfigNotSaved(
          outcome: null,
          errorType: 'StateError',
          keyReplaced: true,
          rollback: KeyRollback.failed,
        ),
      );

      expect(
        wizardSaveFailureText(failed, l10n: _ru),
        isNot(contains(leakMarker)),
      );
    });
  });

  group('уведомление «Config changed on disk»', () {
    test('конфликт записи: уведомление на Review пересобирается при смене '
        'языка, а сам Review остаётся', () async {
      store.firstOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      final cubit = await open(strings);
      await toReview(cubit);
      cubit.dispatch(const ConfirmSave());
      await pumpEventQueue(times: 20);
      expect(
        cubit.state.reviewNotice,
        'Config changed on disk — review and save again',
      );
      final setup = cubit.state.setup;

      await switchTo(AppLocalizationsRu());

      expect(
        cubit.state.reviewNotice,
        'Конфигурация изменилась на диске — проверьте и сохраните снова',
      );
      expect(cubit.state.setup, isA<Reviewing>());
      expect(identical(cubit.state.setup, setup), isTrue);

      await switchTo(AppLocalizationsEn());
      expect(
        cubit.state.reviewNotice,
        'Config changed on disk — review and save again',
      );
    });

    test('без конфликта уведомления нет на любом языке', () async {
      final cubit = await open(strings);
      await toReview(cubit);

      await switchTo(AppLocalizationsRu());

      expect(cubit.state.reviewNotice, isNull);
    });
  });

  group('подписка на AppStrings (D5 правила 1–3; R3)', () {
    test('одна подписка с момента создания, снимается в close()', () async {
      final cubit = await open(strings);
      expect(strings.subscriberCount, 1);

      await toReview(cubit);
      cubit.dispatch(const ConfirmSave());
      await pumpEventQueue(times: 20);
      expect(strings.subscriberCount, 1);

      await cubit.close();

      expect(strings.hasListener, isFalse);
    });

    test('после close событие языка не меняет состояние', () async {
      final cubit = await open(strings);
      await toReview(cubit);
      final before = cubit.state;
      await cubit.close();

      await switchTo(AppLocalizationsRu());

      expect(identical(cubit.state, before), isTrue);
    });

    test('смена языка не посылает событий автомату и не пишет файл', () async {
      final cubit = await open(strings);
      await toReview(cubit);
      final events = log.entries.length;
      final wizardEvents = session.wizardLog.entries.length;

      await switchTo(AppLocalizationsRu());

      expect(store.applied, isEmpty);
      expect(session.wizardLog.entries, hasLength(wizardEvents));
      expect(log.entries, hasLength(events));
      expect(cubit.state.setup, isA<Reviewing>());
    });
  });
}
