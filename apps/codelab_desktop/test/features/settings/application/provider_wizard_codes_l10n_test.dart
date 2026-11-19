// Тесты задачи 4.2 change `add-desktop-localization`: тексты шагов мастера по
// типу, а не по готовой строке (D5 п. 5, D6 «Тексты моста настроек»; spec
// client-agent-setup «Типизированные ошибки и пояснения мастера провайдера»,
// app-settings «Сообщения мастера провайдера на русском»).
//
// Что проверяется. `wizardErrorText` строит текст по `errorCode` (ошибки
// деталей модели и правки на «Review»), по `refusal` (отказ записи плана) и по
// `literalKeyInConfig` (пояснение шага ключа); текст `error` и `notice` моста
// при этом нарочно подменён, чтобы тест падал, если app разбирает строку.
// Дедупликация «подпись существующего ключа — ошибка `keyAlreadyStored`» идёт
// по коду (`isKeyAlreadyStoredError`), а не по равенству строк.

import 'package:codelab_desktop/features/settings/application/provider_wizard_cubit.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_strings.dart';
import '../../../support/fake_provider_settings.dart';

final _en = AppLocalizationsEn();
final _ru = AppLocalizationsRu();

Map<String, Object?> _existing() => {
  'agent': {'default_model': 'local/qwen'},
  'providers': {
    'local': providerMap(
      baseUrl: 'http://localhost:11434/v1',
      models: ['qwen'],
    ),
    'lit': {...providerMap(), 'api_key': leakMarker},
  },
};

void main() {
  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;
  late List<ProviderWizardCubit> cubits;

  setUp(() {
    store = FakeAgentConfigStore(user: _existing());
    session = FakeProviderSettingsSession(store);
    cubits = [];
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

  Future<ProviderWizardCubit> open({ProviderEntryView? editing}) async {
    final flow = await session.openWizard(editing: editing);
    final cubit = ProviderWizardCubit(
      flow: flow,
      access: session.access,
      backendId: store.backend.id,
      editingId: editing?.id,
      isAgentConnected: () => true,
      strings: FixedAppStrings(_en),
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

  Future<void> toDetails(ProviderWizardCubit cubit) async {
    await toKeyStep(cubit);
    cubit.dispatch(const KeySubmitted(NoKey()));
    await pumpEventQueue();
    session.wizardCheck.respond(
      const CheckOk([RemoteModel('m1', contextWindow: 8000)]),
    );
    await pumpEventQueue();
    cubit.dispatch(const ModelEnteredManually('my-model'));
    await pumpEventQueue();
  }

  Future<void> toReview(ProviderWizardCubit cubit) async {
    await toKeyStep(cubit);
    cubit.dispatch(const KeySubmitted(NoKey()));
    await pumpEventQueue();
    session.wizardCheck.respond(
      const CheckOk([RemoteModel('m1', contextWindow: 8000)]),
    );
    await pumpEventQueue();
    cubit.dispatch(const ModelChosen('m1'));
    await pumpEventQueue();
  }

  group('ошибки шага деталей модели — по errorCode', () {
    test(
      'окно контекста и лимит вывода: en и ru, текст error не нужен',
      () async {
        final cubit = await open();
        await toDetails(cubit);
        expect(cubit.state.setup, isA<EnteringModelDetails>());

        cubit.dispatch(
          const ModelDetailsSubmitted(contextWindow: 0, maxOutputTokens: null),
        );
        await pumpEventQueue();
        var setup = cubit.state.setup as EnteringModelDetails;
        expect(setup.errorCode, ProviderSetupErrorCode.contextWindowInvalid);
        expect(
          wizardErrorText(setup, _en),
          'Context window must be a positive number.',
        );
        expect(
          wizardErrorText(setup, _ru),
          'Окно контекста должно быть положительным числом.',
        );

        cubit.dispatch(
          const ModelDetailsSubmitted(contextWindow: 8000, maxOutputTokens: 0),
        );
        await pumpEventQueue();
        setup = cubit.state.setup as EnteringModelDetails;
        expect(setup.errorCode, ProviderSetupErrorCode.maxOutputInvalid);
        expect(
          wizardErrorText(setup, _ru),
          'Максимум токенов вывода должен быть положительным числом.',
        );
      },
    );
  });

  group('ошибки правки на «Review» — по errorCode', () {
    test('занятый или неверный id и недоступная цель', () async {
      final cubit = await open();
      await toReview(cubit);

      cubit.dispatch(const ReviewEdited(providerId: 'Bad Id'));
      await pumpEventQueue();
      var review = cubit.state.setup as Reviewing;
      expect(review.errorCode, ProviderSetupErrorCode.providerIdInvalid);
      expect(review.refusal, isNull);
      expect(
        wizardErrorText(review, _en),
        'Provider id must be unused and match [a-z0-9_-]+.',
      );
      expect(
        wizardErrorText(review, _ru),
        'Id провайдера должен быть свободен и соответствовать [a-z0-9_-]+.',
      );

      cubit.dispatch(
        const ReviewEdited(
          target: ConfigTarget.projectLocal('/nowhere/config.local.yaml'),
        ),
      );
      await pumpEventQueue();
      review = cubit.state.setup as Reviewing;
      expect(review.errorCode, ProviderSetupErrorCode.targetUnavailable);
      expect(wizardErrorText(review, _en), 'This target is not available.');
      expect(wizardErrorText(review, _ru), 'Эта цель недоступна.');
    });
  });

  group('отказ записи плана — по refusal, а не по error', () {
    const ru = {
      PlanRefusal.providerExists: 'Провайдер с таким id уже существует.',
      PlanRefusal.providerMissing: 'Провайдера больше нет в конфигурации.',
      PlanRefusal.notEditable: 'Этот провайдер нельзя изменить здесь.',
      PlanRefusal.multipleLayers:
          'Этот провайдер определён в нескольких файлах конфигурации.',
      PlanRefusal.layerUnreadable: 'Файл конфигурации не читается.',
    };
    const en = {
      PlanRefusal.providerExists: 'A provider with this id already exists.',
      PlanRefusal.providerMissing: 'The provider is no longer in the config.',
      PlanRefusal.notEditable: 'This provider cannot be edited here.',
      PlanRefusal.multipleLayers:
          'This provider is defined in several config files.',
      PlanRefusal.layerUnreadable: 'The config file cannot be read.',
    };

    test('каждый отказ переводится, подмена строки моста ни на что не '
        'влияет', () async {
      final cubit = await open();
      await toReview(cubit);
      final plan = (cubit.state.setup as Reviewing).plan;

      for (final refusal in PlanRefusal.values) {
        final state = Reviewing(
          plan,
          const [],
          error: 'ТЕКСТ МОСТА, КОТОРЫЙ APP НЕ РАЗБИРАЕТ',
          refusal: refusal,
        );
        expect(wizardErrorText(state, _en), en[refusal], reason: refusal.name);
        expect(wizardErrorText(state, _ru), ru[refusal], reason: refusal.name);
      }
    });

    test('ошибки нет — текста нет', () async {
      final cubit = await open();
      await toReview(cubit);

      expect(wizardErrorText(cubit.state.setup, _ru), isNull);
    });
  });

  group('пояснение литерального ключа — по literalKeyInConfig', () {
    test(
      'правка провайдера с ключом в config.yaml: признак и перевод',
      () async {
        final cubit = await open(editing: await entryOf('lit'));
        cubit.dispatch(const BaseUrlSubmitted('https://h.example/v1'));
        await pumpEventQueue();
        final key = cubit.state.setup as ChoosingKey;

        expect(key.literalKeyInConfig, isTrue);
        expect(
          wizardKeyNotice(key, _en),
          'The key is written in config.yaml. Choose where to keep it instead.',
        );
        expect(
          wizardKeyNotice(key, _ru),
          'Ключ записан в config.yaml. Выберите, где его хранить вместо этого.',
        );
      },
    );

    test('без литерального ключа пояснения нет на любом языке', () async {
      final cubit = await open();
      await toKeyStep(cubit);
      final key = cubit.state.setup as ChoosingKey;

      expect(key.literalKeyInConfig, isFalse);
      expect(wizardKeyNotice(key, _en), isNull);
      expect(wizardKeyNotice(key, _ru), isNull);
    });
  });

  group('secretStoreReadOnly: заголовок каталога, подсказка хранилища — '
      'подробность (wizardReadOnlyDetail)', () {
    Future<ChoosingKey> readOnlyKey({String? hint}) async {
      store.backend = const SecretBackendInfo(
        id: 'env',
        writable: false,
        unavailableReason: 'Secrets are read from the environment.',
      );
      session.readOnlyHint = hint;
      final cubit = await open();
      await toKeyStep(cubit);
      cubit.dispatch(KeySubmitted(StoreSecret(SecretValue('v'))));
      await pumpEventQueue();
      final key = cubit.state.setup as ChoosingKey;
      expect(key.errorCode, ProviderSetupErrorCode.secretStoreReadOnly);
      return key;
    }

    test('en и ru: заголовок из каталога, подробность — текст хранилища '
        'как есть', () async {
      final key = await readOnlyKey(hint: 'Set CODELAB_SECRET_<NAME> instead.');

      expect(wizardErrorText(key, _en), 'The secret store is read-only.');
      expect(
        wizardErrorText(key, _ru),
        'Хранилище секретов доступно только для чтения.',
      );
      expect(wizardReadOnlyDetail(key), 'Set CODELAB_SECRET_<NAME> instead.');
    });

    test('подсказки нет: подробность — причина бэкенда', () async {
      final key = await readOnlyKey();

      expect(
        wizardErrorText(key, _ru),
        'Хранилище секретов доступно только для чтения.',
      );
      expect(
        wizardReadOnlyDetail(key),
        'Secrets are read from the environment.',
      );
    });

    test('бэкенд пишущий: подробности нет', () async {
      final cubit = await open();
      await toKeyStep(cubit);

      expect(wizardReadOnlyDetail(cubit.state.setup), isNull);
    });
  });

  group('дедупликация keyAlreadyStored — по коду', () {
    test(
      'подпись и ошибка строятся из одного сообщения, ошибка скрыта',
      () async {
        session.secrets['codelab/llm-example'] = 'old-value';
        final cubit = await open();
        await toKeyStep(cubit);
        await pumpEventQueue();
        // Запись нового ключа без «Replace it» — ошибка `keyAlreadyStored`.
        cubit.dispatch(KeySubmitted(StoreSecret(SecretValue(leakMarker))));
        await pumpEventQueue();
        final key = cubit.state.setup as ChoosingKey;

        expect(key.errorCode, ProviderSetupErrorCode.keyAlreadyStored);
        expect(key.existingSecret, 'codelab/llm-example');
        expect(isKeyAlreadyStoredError(key), isTrue);
        // Один текст для подписи и для ошибки: на каждом языке.
        expect(
          wizardErrorText(key, _en),
          'A stored key codelab/llm-example already exists in file.',
        );
        expect(
          wizardErrorText(key, _ru),
          'Сохранённый ключ «codelab/llm-example» уже есть в file.',
        );
      },
    );

    test('другие ошибки шага ключа не скрываются', () async {
      final cubit = await open();
      await toKeyStep(cubit);
      cubit.dispatch(KeySubmitted(StoreSecret(SecretValue(''))));
      await pumpEventQueue();
      final key = cubit.state.setup as ChoosingKey;

      expect(key.errorCode, ProviderSetupErrorCode.keyEmpty);
      expect(isKeyAlreadyStoredError(key), isFalse);
      expect(wizardErrorText(key, _ru), 'Введите ключ API.');
    });
  });
}
