import 'dart:async';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import 'support/provider_setup_fakes.dart';

/// Типизированные ошибки и пояснения мастера провайдера (spec
/// `client-agent-setup` «Типизированные ошибки и пояснения мастера
/// провайдера»; design.md change `add-desktop-localization`, D5 п. 5, D6
/// «Тексты моста настроек»).
///
/// Почему: app строит текст на своём языке по `errorCode`, `literalKeyInConfig`
/// и `notVerified`, а строки `error`, `notice` и `warnings` остаются для CLI.
/// Тесты красные до 4.1b: автомат пока не заполняет новые поля.
/// Порты — фейки, синхронизация — только `pumpEventQueue()`, без таймеров.
void main() {
  const userinfoError = 'Remove the user name and password from the address.';

  late FakeProviderCheck check;
  late FakeProviderKeys keys;
  late FakeConfigStore config;
  late List<ProviderSetupState> seen;
  late ProviderSetupFlow flow;

  /// Все состояния всех сценариев файла: по ним идёт итоговая проверка
  /// инварианта (последний тест файла).
  final allSeen = <ProviderSetupState>[];

  EditableSettings access() => const EditableSettings(
    ConfigPaths(codelabHome: '/h', projectDir: '/work/project'),
  );

  ProviderSetupFlow build({
    AgentConfigSnapshot? snapshot,
    ProviderEntryView? editing,
  }) {
    final snap = snapshot ?? snapshotOf();
    config.snapshotValue = snap;
    final built = ProviderSetupFlow(
      check: check,
      committer: ProviderSetupCommitter(config: config, keys: keys),
      keys: keys,
      snapshot: snap,
      access: access(),
      environment: const {},
      isLocalHost: (host) => host == 'localhost',
      logger: RecordingLogger(),
      editing: editing,
      entry: ProviderWizardEntry.app,
    );
    built.states.listen(seen.add);
    return built;
  }

  Future<void> send(ProviderSetupEvent event) async {
    flow.dispatch(event);
    await pumpEventQueue();
  }

  Future<void> toKey({String preset = 'openai', String? url}) async {
    await send(PresetChosen(preset));
    await send(BaseUrlSubmitted(url ?? 'https://api.openai.com/v1'));
  }

  Future<void> okWith(List<RemoteModel> models) async {
    check.respond(CheckOk(models));
    await pumpEventQueue();
  }

  Future<ProviderEntryView> viewOf(
    AgentConfigSnapshot snapshot,
    String id,
  ) async => (await providerEntriesOf(
    snapshot,
    environment: const {},
    isSecretSet: (_) async => true,
  )).firstWhere((e) => e.id == id);

  /// Дорогой вариант до `Reviewing` с ключом из окружения.
  Future<Reviewing> toReview() async {
    await toKey();
    await send(const KeySubmitted(UseEnvVar('K')));
    await okWith(const [RemoteModel('m', contextWindow: 8000)]);
    await send(const ModelChosen('m'));
    return flow.current as Reviewing;
  }

  setUp(() {
    check = FakeProviderCheck();
    keys = FakeProviderKeys();
    config = FakeConfigStore([]);
    seen = [];
    flow = build();
  });

  tearDown(() async {
    allSeen.addAll(seen);
    await flow.dispose();
  });

  group('Шаг адреса', () {
    test('адрес не http и не https — addressInvalid', () async {
      await send(const PresetChosen('custom-openai'));
      await send(const BaseUrlSubmitted('ftp://llm.test'));

      final step = flow.current as EnteringBaseUrl;
      expect(step.errorCode, ProviderSetupErrorCode.addressInvalid);
      expect(step.error, 'Enter an http or https address.');
    });

    test('адрес с userinfo — addressHasUserinfo', () async {
      await send(const PresetChosen('custom-openai'));
      await send(const BaseUrlSubmitted('https://u:p@llm.test/v1'));

      final step = flow.current as EnteringBaseUrl;
      expect(step.errorCode, ProviderSetupErrorCode.addressHasUserinfo);
      expect(step.error, userinfoError);
    });

    test('правка с userinfo: код уже в первом состоянии', () async {
      final snapshot = snapshotOf(
        user: {
          'providers': {
            'old': {
              'kind': 'openai-compatible',
              'base_url': 'https://u:p@llm.example/v1',
            },
          },
        },
      );
      await flow.dispose();
      flow = build(snapshot: snapshot, editing: await viewOf(snapshot, 'old'));

      final step = flow.current as EnteringBaseUrl;
      expect(step.errorCode, ProviderSetupErrorCode.addressHasUserinfo);
      expect(step.error, userinfoError);
    });
  });

  group('Шаг ключа', () {
    test('пустой ключ — keyEmpty', () async {
      await toKey();
      await send(KeySubmitted(StoreSecret(SecretValue(''))));

      final step = flow.current as ChoosingKey;
      expect(step.errorCode, ProviderSetupErrorCode.keyEmpty);
      expect(step.error, 'Enter the API key.');
    });

    test('сохранённый ключ уже есть (шаг ключа) — keyAlreadyStored', () async {
      await flow.dispose();
      keys = FakeProviderKeys(stored: {'codelab/openai'});
      flow = build();
      await toKey();
      await send(KeySubmitted(StoreSecret(SecretValue('sk-x'))));

      final step = flow.current as ChoosingKey;
      expect(step.errorCode, ProviderSetupErrorCode.keyAlreadyStored);
      expect(step.existingSecret, 'codelab/openai');
      expect(step.backend.id, 'file');
      expect(step.error, 'A stored key codelab/openai already exists in file.');
    });

    test(
      'ключ появился до записи (ProviderKeyAppeared) — keyAlreadyStored',
      () async {
        await toKey();
        await send(KeySubmitted(StoreSecret(SecretValue('sk-x'))));
        await okWith(const [RemoteModel('m', contextWindow: 8000)]);
        await send(const ModelChosen('m'));
        keys.storedAnswers.add(true);
        await send(const ConfirmSave());

        final step = flow.current as ChoosingKey;
        expect(step.errorCode, ProviderSetupErrorCode.keyAlreadyStored);
        expect(step.existingSecret, 'codelab/openai');
        expect(
          step.error,
          'A stored key codelab/openai already exists in file.',
        );
      },
    );

    test('хранилище только для чтения: с подсказкой', () async {
      await flow.dispose();
      keys = FakeProviderKeys(
        backend: const SecretBackendInfo(
          id: 'env',
          writable: false,
          unavailableReason: 'no OS store',
        ),
        readOnlyHint: 'Set the variable instead.',
      );
      flow = build();
      await toKey();
      await send(KeySubmitted(StoreSecret(SecretValue('sk-x'))));

      final step = flow.current as ChoosingKey;
      expect(step.errorCode, ProviderSetupErrorCode.secretStoreReadOnly);
      expect(step.readOnlyHint, 'Set the variable instead.');
      expect(step.error, 'Set the variable instead.');
    });

    test('хранилище только для чтения: с unavailableReason', () async {
      await flow.dispose();
      keys = FakeProviderKeys(
        backend: const SecretBackendInfo(
          id: 'env',
          writable: false,
          unavailableReason: 'no OS store',
        ),
      );
      flow = build();
      await toKey();
      await send(KeySubmitted(StoreSecret(SecretValue('sk-x'))));

      final step = flow.current as ChoosingKey;
      expect(step.errorCode, ProviderSetupErrorCode.secretStoreReadOnly);
      expect(step.backend.unavailableReason, 'no OS store');
      expect(step.error, 'no OS store');
    });

    test('хранилище только для чтения: без подсказки и причины', () async {
      await flow.dispose();
      keys = FakeProviderKeys(
        backend: const SecretBackendInfo(id: 'env', writable: false),
      );
      flow = build();
      await toKey();
      await send(KeySubmitted(StoreSecret(SecretValue('sk-x'))));

      final step = flow.current as ChoosingKey;
      expect(step.errorCode, ProviderSetupErrorCode.secretStoreReadOnly);
      expect(step.readOnlyHint, isNull);
      expect(step.backend.unavailableReason, isNull);
      expect(step.error, 'The secret store is read-only.');
    });

    test('нечего оставлять — nothingToKeep', () async {
      await toKey();
      await send(const KeySubmitted(KeepStoredSecret()));

      final step = flow.current as ChoosingKey;
      expect(step.errorCode, ProviderSetupErrorCode.nothingToKeep);
      expect(step.error, 'There is no stored key to keep.');
    });

    test('пустое имя переменной — envVarEmpty', () async {
      await toKey();
      await send(const KeySubmitted(UseEnvVar('  ')));

      final step = flow.current as ChoosingKey;
      expect(step.errorCode, ProviderSetupErrorCode.envVarEmpty);
      expect(step.error, 'Enter the environment variable name.');
    });

    test(
      'хранилище не записало ключ — keyNotStored, error = причина',
      () async {
        keys.onWrite = (_, _) => const ProviderKeyRefused('store failed');
        await toKey();
        await send(KeySubmitted(StoreSecret(SecretValue('sk-x'))));
        await okWith(const [RemoteModel('m', contextWindow: 8000)]);
        await send(const ModelChosen('m'));
        await send(const ConfirmSave());

        final step = flow.current as ChoosingKey;
        expect(step.errorCode, ProviderSetupErrorCode.keyNotStored);
        expect(step.error, 'store failed');
      },
    );

    test('без ошибки шага код не задан', () async {
      await toKey();

      final step = flow.current as ChoosingKey;
      expect(step.error, isNull);
      expect(step.errorCode, isNull);
    });
  });

  group('Детали модели', () {
    Future<void> toDetails() async {
      await toKey(preset: 'anthropic', url: 'https://api.anthropic.com');
      await send(const KeySubmitted(NoKey()));
      await okWith(const [RemoteModel('x')]);
      await send(const ModelEnteredManually('my-model'));
    }

    test('окно контекста не положительное — contextWindowInvalid', () async {
      await toDetails();
      await send(const ModelDetailsSubmitted(contextWindow: 0));

      final step = flow.current as EnteringModelDetails;
      expect(step.errorCode, ProviderSetupErrorCode.contextWindowInvalid);
      expect(step.error, 'Context window must be a positive number.');
    });

    test('лимит вывода не положительный — maxOutputInvalid', () async {
      await toDetails();
      await send(
        const ModelDetailsSubmitted(contextWindow: 8000, maxOutputTokens: 0),
      );

      final step = flow.current as EnteringModelDetails;
      expect(step.errorCode, ProviderSetupErrorCode.maxOutputInvalid);
      expect(step.error, 'Max output tokens must be a positive number.');
    });
  });

  group('Review', () {
    test(
      'id не подходит под шаблон — providerIdInvalid, без refusal',
      () async {
        await toReview();
        await send(const ReviewEdited(providerId: 'Bad Id'));

        final review = flow.current as Reviewing;
        expect(review.errorCode, ProviderSetupErrorCode.providerIdInvalid);
        expect(review.refusal, isNull);
        expect(
          review.error,
          'Provider id must be unused and match [a-z0-9_-]+.',
        );
      },
    );

    test('цель записи недоступна — targetUnavailable', () async {
      await toReview();
      await send(const ReviewEdited(target: ConfigTarget.projectLocal('/x')));

      final review = flow.current as Reviewing;
      expect(review.errorCode, ProviderSetupErrorCode.targetUnavailable);
      expect(review.refusal, isNull);
      expect(review.error, 'This target is not available.');
    });

    test('отказ записи плана — refusal без errorCode', () async {
      await toReview();
      config.outcome = const ConfigConflict('/h/config.yaml');
      config.snapshotValue = snapshotOf(
        user: {
          'providers': {
            'openai': {'kind': 'openai-compatible', 'base_url': 'https://h/v1'},
          },
        },
      );
      await send(const ConfirmSave());
      await send(const Back());
      await send(const ConfirmSave());

      final review = flow.current as Reviewing;
      expect(review.refusal, PlanRefusal.providerExists);
      expect(review.errorCode, isNull);
      expect(review.error, 'A provider with this id already exists.');
    });

    test('без ошибки на обзоре нет ни кода, ни refusal', () async {
      final review = await toReview();

      expect(review.error, isNull);
      expect(review.errorCode, isNull);
      expect(review.refusal, isNull);
    });
  });

  group('literalKeyInConfig', () {
    Map<String, Object?> provider([Map<String, Object?> extra = const {}]) => {
      'kind': 'openai-compatible',
      'base_url': 'https://old.test/v1',
      'models': {
        'm': {'context_window': 8000},
      },
      ...extra,
    };

    Future<ChoosingKey> editKey(Map<String, Object?> old) async {
      final snapshot = snapshotOf(
        user: {
          'agent': {'default_model': 'old/m'},
          'providers': {'old': old},
        },
      );
      await flow.dispose();
      flow = build(snapshot: snapshot, editing: await viewOf(snapshot, 'old'));
      await send(const BaseUrlSubmitted('https://old.test/v1'));
      return flow.current as ChoosingKey;
    }

    test('правка с литеральным ключом — true, notice прежний', () async {
      final step = await editKey(provider({'api_key': 'sk-literal-0123'}));

      expect(step.literalKeyInConfig, isTrue);
      expect(
        step.notice,
        'The key is written in config.yaml. Choose where to keep it instead.',
      );
    });

    test('правка без литерала — false, notice нет', () async {
      final step = await editKey(provider({'api_key_env': 'OLD_ENV'}));

      expect(step.literalKeyInConfig, isFalse);
      expect(step.notice, isNull);
    });

    test('добавление нового провайдера — false', () async {
      await toKey();

      final step = flow.current as ChoosingKey;
      expect(step.literalKeyInConfig, isFalse);
      expect(step.notice, isNull);
    });
  });

  group('Reviewing.notVerified', () {
    Future<Reviewing> skipped(ProviderCheckFailureKind kind) async {
      await toKey(preset: 'custom-openai', url: 'https://llm.test/v1');
      await send(const KeySubmitted(NoKey()));
      check.respond(
        CheckFailure(ProviderCheckFailure(kind: kind, message: 'failed')),
      );
      await pumpEventQueue();
      await send(const SkipCheck(confirmed: true));
      await send(const ModelEnteredManually('my-model'));
      await send(const ModelDetailsSubmitted(contextWindow: 8000));
      return flow.current as Reviewing;
    }

    test('timeout после SkipCheck', () async {
      final review = await skipped(ProviderCheckFailureKind.timeout);

      expect(review.notVerified, 'timeout');
      expect(review.warnings, ['Not verified: timeout']);
    });

    test('unreachable после SkipCheck', () async {
      final review = await skipped(ProviderCheckFailureKind.unreachable);

      expect(review.notVerified, 'unreachable');
      expect(review.warnings, ['Not verified: unreachable']);
    });

    test('успешная проверка — null, warnings пусты', () async {
      final review = await toReview();

      expect(review.notVerified, isNull);
      expect(review.warnings, isEmpty);
    });
  });

  test('CLI не меняется: строка ошибки «ключ уже есть» прежняя, '
      'поля error/notice/warnings — как до изменения', () async {
    await flow.dispose();
    keys = FakeProviderKeys(stored: {'codelab/openai'});
    flow = build();
    await toKey();
    await send(KeySubmitted(StoreSecret(SecretValue('sk-x'))));

    expect(
      (flow.current as ChoosingKey).error,
      'A stored key codelab/openai already exists in file.',
    );
  });

  // Должен идти последним: проверяет состояния, накопленные сценариями выше.
  // Отдельным тестом, а не `tearDown`, чтобы сценарий «CLI не меняется» не
  // краснел из-за инварианта (D6 «Тексты моста настроек»).
  test('инвариант: error и errorCode появляются вместе', () {
    expect(allSeen, isNotEmpty);
    for (final state in allSeen) {
      switch (state) {
        case EnteringBaseUrl(:final error, :final errorCode):
        case ChoosingKey(:final error, :final errorCode):
        case EnteringModelDetails(:final error, :final errorCode):
          expect(
            error == null,
            errorCode == null,
            reason: '$state: error=$error, errorCode=$errorCode',
          );
        case Reviewing(:final error, :final errorCode, :final refusal):
          if (error != null) {
            expect(
              (errorCode != null) != (refusal != null),
              isTrue,
              reason: '$state: errorCode=$errorCode, refusal=$refusal',
            );
          } else {
            expect(errorCode, isNull, reason: '$state');
            expect(refusal, isNull, reason: '$state');
          }
        default:
      }
    }
  });
}
