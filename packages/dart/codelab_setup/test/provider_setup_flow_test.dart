import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show LogLevel, LogRecord, builtinModelInfo;
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import 'support/provider_setup_fakes.dart';

/// Мастер провайдера (client-agent-setup «Мастер провайдера», «Значение секрета
/// в памяти клиента»; design.md change `add-provider-setup-ui`, D7, D8).
///
/// Порты — фейки (`support/provider_setup_fakes.dart`): проверка отвечает по
/// команде теста, журнал порядка вызовов общий. Синхронизация — только
/// `pumpEventQueue()`, без таймеров.
void main() {
  const leak = 'sk-test-leak-0123456789';
  const userinfoError = 'Remove the user name and password from the address.';

  late FakeProviderCheck check;
  late FakeProviderKeys keys;
  late FakeConfigStore config;
  late List<String> journal;
  late RecordingLogger logger;
  late List<ProviderSetupState> seen;
  late ProviderSetupFlow flow;

  EditableSettings access({String? project = '/work/project'}) =>
      EditableSettings(ConfigPaths(codelabHome: '/h', projectDir: project));

  ProviderSetupFlow build({
    AgentConfigSnapshot? snapshot,
    bool Function(String host)? isLocalHost,
    Map<String, String> environment = const {},
    ProviderEntryView? editing,
    bool forceDefault = false,
    EditableSettings? settings,
    Stopwatch Function()? stopwatch,
    ProviderWizardEntry entry = ProviderWizardEntry.app,
  }) {
    final snap = snapshot ?? snapshotOf();
    config.snapshotValue = snap;
    final built = ProviderSetupFlow(
      check: check,
      committer: ProviderSetupCommitter(config: config, keys: keys),
      keys: keys,
      snapshot: snap,
      access: settings ?? access(),
      environment: environment,
      isLocalHost: isLocalHost ?? (host) => host == 'localhost',
      logger: logger,
      editing: editing,
      forceDefault: forceDefault,
      newStopwatch: stopwatch ?? Stopwatch.new,
      entry: entry,
    );
    built.states.listen(seen.add);
    return built;
  }

  Future<void> send(ProviderSetupEvent event) async {
    flow.dispatch(event);
    await pumpEventQueue();
  }

  /// Типы состояний подряд без повторов: порядок автомата, а не число
  /// промежуточных снимков.
  List<Type> kinds() {
    final out = <Type>[];
    for (final state in seen) {
      if (out.isEmpty || out.last != state.runtimeType) {
        out.add(state.runtimeType);
      }
    }
    return out;
  }

  /// Доходит до `Checking` с пресетом [preset] и адресом [url].
  Future<void> toChecking(
    String preset,
    String url, {
    KeyChoice? key,
    bool replace = false,
  }) async {
    await send(PresetChosen(preset));
    await send(BaseUrlSubmitted(url));
    await send(KeySubmitted(key ?? const NoKey(), replaceExisting: replace));
  }

  Future<void> okWith(List<RemoteModel> models) async {
    check.respond(CheckOk(models));
    await pumpEventQueue();
  }

  String logText() =>
      logger.records.map((r) => '${r.event} ${r.fields} ${r.error}').join('\n');

  setUp(() {
    journal = [];
    check = FakeProviderCheck();
    keys = FakeProviderKeys();
    config = FakeConfigStore(journal);
    logger = RecordingLogger();
    seen = [];
    flow = build();
  });

  tearDown(() => flow.dispose());

  test('старт — выбор пресета из таблицы MVP', () {
    final state = flow.current as ChoosingPreset;
    expect(state.presets.map((p) => p.id), [
      'openai',
      'anthropic',
      'openrouter',
      'ollama',
      'custom-openai',
      'custom-anthropic',
    ]);
    expect(
      state.presets.firstWhere((p) => p.id == 'ollama').label,
      ['Ollama (local, no key)'].single,
    );
  });

  group('От пресета до записи', () {
    test('anthropic: состояния и правки', () async {
      await send(const PresetChosen('anthropic'));
      await send(const BaseUrlSubmitted('https://api.anthropic.com'));
      await send(KeySubmitted(StoreSecret(SecretValue(leak))));
      expect(check.calls.single.kind, 'anthropic');
      expect(check.calls.single.key, leak);
      expect(check.calls.single.timeout, defaultProviderCheckTimeout);
      await okWith(const [RemoteModel('claude-x', contextWindow: 200000)]);
      await send(const ModelChosen('claude-x'));
      await send(const ConfirmSave());

      expect(kinds(), [
        EnteringBaseUrl,
        ChoosingKey,
        Checking,
        ChoosingModel,
        Reviewing,
        Saving,
        Done,
      ]);
      expect(config.applied.single.edits, [
        const SetValue('providers.anthropic.kind', 'anthropic'),
        const SetValue(
          'providers.anthropic.base_url',
          'https://api.anthropic.com',
        ),
        const SetValue(
          'providers.anthropic.api_key_secret',
          'codelab/anthropic',
        ),
        const SetValue(
          'providers.anthropic.models.claude-x.context_window',
          200000,
        ),
        const SetValue('agent.default_model', 'anthropic/claude-x'),
      ]);
      expect(keys.written, {'codelab/anthropic': leak});
      // «сначала секрет, потом конфиг» (SETUP-5)
      expect(journal, ['apply']);
      expect(keys.journal.indexOf('write codelab/anthropic'), isNonNegative);
    });
  });

  group('Ключ', () {
    test(
      'бэкенд только для чтения: без StoreSecret, причина — подсказка',
      () async {
        keys = FakeProviderKeys(
          backend: const SecretBackendInfo(
            id: 'env',
            writable: false,
            unavailableReason: 'read-only',
          ),
          readOnlyHint:
              'secret store env is read-only. Set X in the environment',
        );
        flow = build();
        await send(const PresetChosen('openai'));
        await send(const BaseUrlSubmitted('https://api.openai.com/v1'));

        final step = flow.current as ChoosingKey;
        expect(step.canStoreSecret, isFalse);
        expect(step.readOnlyHint, keys.readOnlyHint);

        await send(KeySubmitted(StoreSecret(SecretValue(leak))));
        expect(flow.current, isA<ChoosingKey>());
        expect((flow.current as ChoosingKey).error, isNotNull);
        expect(check.calls, isEmpty);
        expect(keys.written, isEmpty);
      },
    );

    test('пустое значение StoreSecret — ошибка шага, а не переход', () async {
      await send(const PresetChosen('openai'));
      await send(const BaseUrlSubmitted('https://api.openai.com/v1'));
      await send(KeySubmitted(StoreSecret(SecretValue(''))));

      expect(flow.current, isA<ChoosingKey>());
      expect((flow.current as ChoosingKey).error, isNotNull);
      expect(check.calls, isEmpty);
    });

    test(
      'существующий секрет: два варианта, без «Replace it» не пишется',
      () async {
        keys = FakeProviderKeys(
          stored: {'codelab/openai'},
          values: {'codelab/openai': 'stored-value'},
        );
        flow = build(
          // Переменная переопределения существующим секретом не считается.
          environment: {'CODELAB_SECRET_CODELAB_OPENAI': 'from-env'},
        );
        await send(const PresetChosen('openai'));
        await send(const BaseUrlSubmitted('https://api.openai.com/v1'));
        final step = flow.current as ChoosingKey;
        expect(step.existingSecret, 'codelab/openai');

        await send(KeySubmitted(StoreSecret(SecretValue(leak))));
        expect(flow.current, isA<ChoosingKey>());
        expect(check.calls, isEmpty);
        expect(keys.journal.where((j) => j.startsWith('write')), isEmpty);

        await send(const KeySubmitted(KeepStoredSecret()));
        // Ключ проверки — значение сохранённого секрета (keys.read).
        expect(check.calls.single.key, 'stored-value');
      },
    );

    test('«Replace it» даёт replaceSecret в плане', () async {
      keys = FakeProviderKeys(stored: {'codelab/openai'});
      flow = build();
      await toChecking(
        'openai',
        'https://api.openai.com/v1',
        key: StoreSecret(SecretValue(leak)),
        replace: true,
      );
      await okWith(const [RemoteModel('m', contextWindow: 8000)]);
      await send(const ModelChosen('m'));

      expect((flow.current as Reviewing).plan.replaceSecret, isTrue);
    });

    test('варианта «оставить» для нового провайдера без секрета нет', () async {
      await send(const PresetChosen('openai'));
      await send(const BaseUrlSubmitted('https://api.openai.com/v1'));
      await send(const KeySubmitted(KeepStoredSecret()));

      expect(flow.current, isA<ChoosingKey>());
      expect(check.calls, isEmpty);
    });

    test('до ответа порта stored шаг не принимает ключ', () async {
      keys.storedGate = Completer<void>();
      flow = build();
      await send(const PresetChosen('openai'));
      await send(const BaseUrlSubmitted('https://api.openai.com/v1'));
      expect((flow.current as ChoosingKey).ready, isFalse);

      await send(const KeySubmitted(NoKey()));
      expect(flow.current, isA<ChoosingKey>());
      expect(logger.eventsOf('provider_wizard.event_ignored'), isNotEmpty);

      keys.storedGate!.complete();
      await pumpEventQueue();
      expect((flow.current as ChoosingKey).ready, isTrue);
    });

    test('ключ проверки: UseEnvVar из environment, NoKey без ключа', () async {
      flow = build(environment: {'OPENAI_API_KEY': 'env-value'});
      await toChecking(
        'openai',
        'https://api.openai.com/v1',
        key: const UseEnvVar('OPENAI_API_KEY'),
      );
      expect(check.calls.single.key, 'env-value');

      await send(const Back());
      await send(const KeySubmitted(UseEnvVar('UNSET_VAR')));
      expect(check.calls.last.key, isNull);

      await send(const Back());
      await send(const KeySubmitted(NoKey()));
      expect(check.calls.last.key, isNull);
    });
  });

  group('Проверка', () {
    test(
      'отказ без пропуска: unauthorized — Retry и Back, SkipCheck игнорируется',
      () async {
        await toChecking('openai', 'https://api.openai.com/v1');
        check.respond(
          const CheckFailure(
            ProviderCheckFailure(
              kind: ProviderCheckFailureKind.unauthorized,
              message: 'Key rejected',
              statusCode: 401,
            ),
          ),
        );
        await pumpEventQueue();
        expect(flow.current, isA<CheckFailed>());
        expect((flow.current as CheckFailed).canSkip, isFalse);

        await send(const SkipCheck(confirmed: true));
        expect(flow.current, isA<CheckFailed>());

        await send(const RetryCheck());
        expect(flow.current, isA<Checking>());
        expect(check.calls, hasLength(2));

        check.respond(
          const CheckFailure(
            ProviderCheckFailure(
              kind: ProviderCheckFailureKind.unauthorized,
              message: 'Key rejected',
              statusCode: 401,
            ),
          ),
        );
        await pumpEventQueue();
        await send(const Back());
        expect(flow.current, isA<ChoosingKey>());
      },
    );

    test(
      'SkipCheck: только unreachable/timeout, после подтверждения',
      () async {
        await toChecking('custom-openai', 'https://llm.test/v1');
        check.respond(
          const CheckFailure(
            ProviderCheckFailure(
              kind: ProviderCheckFailureKind.unreachable,
              message: 'Server unreachable',
            ),
          ),
        );
        await pumpEventQueue();
        expect((flow.current as CheckFailed).canSkip, isTrue);

        await send(const SkipCheck(confirmed: false));
        expect(flow.current, isA<CheckFailed>());

        await send(const SkipCheck(confirmed: true));
        final model = flow.current as ChoosingModel;
        expect(model.checked, isFalse);
        expect(model.models, isEmpty);

        await send(const ModelEnteredManually('my-model'));
        await send(const ModelDetailsSubmitted(contextWindow: 8000));
        final review = flow.current as Reviewing;
        expect(review.warnings, contains('Not verified: unreachable'));
      },
    );

    test('notFound: ручная модель без пропуска и вариант с /v1', () async {
      await toChecking('custom-openai', 'https://llm.test');
      check.respond(
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.notFound,
            message: 'Model list not found',
            statusCode: 404,
          ),
        ),
      );
      await pumpEventQueue();
      final failed = flow.current as CheckFailed;
      expect(failed.canSkip, isFalse);
      expect(failed.canUseV1, isTrue);

      await send(const UseV1Address());
      expect(flow.current, isA<Checking>());
      expect(check.calls.last.baseUrl, Uri.parse('https://llm.test/v1'));
      expect(
        (flow.current as Checking).probeUrl,
        Uri.parse('https://llm.test/v1/models'),
      );

      check.respond(
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.notFound,
            message: 'Model list not found',
            statusCode: 404,
          ),
        ),
      );
      await pumpEventQueue();
      expect((flow.current as CheckFailed).canUseV1, isFalse);

      await send(const ModelEnteredManually('my-model'));
      final details = flow.current as EnteringModelDetails;
      expect(details.suggestedContextWindow, 32000);
    });

    test('CheckFailed несёт адрес без query и длительность', () async {
      flow = build(stopwatch: () => _FixedStopwatch(212));
      await toChecking(
        'custom-openai',
        'https://llm.test/v1?api-version=2024-10-01',
      );
      expect(
        (flow.current as Checking).probeUrl.toString(),
        'https://llm.test/v1/models',
      );
      check.respond(
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.notFound,
            message: 'Model list not found',
            statusCode: 404,
          ),
        ),
      );
      await pumpEventQueue();

      final failed = flow.current as CheckFailed;
      expect(failed.probeUrl.toString(), 'https://llm.test/v1/models');
      expect(failed.failure.statusCode, 404);
      expect(failed.elapsed, const Duration(milliseconds: 212));
    });

    test('поздний результат: Back, Back — состояние не меняется', () async {
      await toChecking('openai', 'https://api.openai.com/v1');
      final first = check.calls.single;

      await send(const Back());
      await send(const Back());
      expect(flow.current, isA<EnteringBaseUrl>());
      expect(first.cancel!.isCancelled, isTrue);

      await okWith(const [RemoteModel('m', contextWindow: 8000)]);
      expect(flow.current, isA<EnteringBaseUrl>());
      expect(logger.eventsOf('provider_wizard.check_discarded'), hasLength(1));
    });

    test('CheckCancelled состояние не меняет', () async {
      await toChecking('openai', 'https://api.openai.com/v1');
      check.respond(const CheckCancelled());
      await pumpEventQueue();

      expect(flow.current, isA<Checking>());
    });

    test(
      'Cancel и dispose отменяют попытку, отмена доходит до порта',
      () async {
        await toChecking('openai', 'https://api.openai.com/v1');
        await send(const Cancel());
        expect(flow.current, isA<Cancelled>());
        expect(check.calls.single.cancel!.isCancelled, isTrue);

        flow = build();
        await toChecking('openai', 'https://api.openai.com/v1');
        final second = check.calls.last;
        await flow.dispose();
        expect(second.cancel!.isCancelled, isTrue);
      },
    );
  });

  group('Модель и окно контекста', () {
    test('подсказка из каталога ядра и 32000', () async {
      await toChecking('anthropic', 'https://api.anthropic.com');
      await okWith(const [
        RemoteModel('claude-sonnet-5-5'),
        RemoteModel('weird'),
      ]);
      await send(const ModelChosen('claude-sonnet-5-5'));
      final review = flow.current as Reviewing;
      final window = builtinModelInfo('claude-sonnet-5-5')!.contextWindow;
      expect(review.plan.model.contextWindow, window);
      expect(
        review.plan.toEdits().whereType<SetValue>().map((e) => e.key),
        contains('providers.anthropic.models.claude-sonnet-5-5.context_window'),
      );

      // Модель из списка без окна и вне каталога — спрашиваем окно.
      await send(const Back());
      expect(flow.current, isA<ChoosingModel>());
      await send(const ModelChosen('weird'));
      expect(
        (flow.current as EnteringModelDetails).suggestedContextWindow,
        32000,
      );
    });

    test(
      'ручной ввод: всегда EnteringModelDetails, подсказка — каталог',
      () async {
        await toChecking('anthropic', 'https://api.anthropic.com');
        await okWith(const [RemoteModel('x')]);

        await send(const ModelEnteredManually('claude-sonnet-5-5'));
        expect(
          (flow.current as EnteringModelDetails).suggestedContextWindow,
          builtinModelInfo('claude-sonnet-5-5')!.contextWindow,
        );

        await send(const Back());
        await send(const ModelEnteredManually('my-model'));
        expect(
          (flow.current as EnteringModelDetails).suggestedContextWindow,
          32000,
        );
        await send(const ModelDetailsSubmitted(contextWindow: 0));
        expect((flow.current as EnteringModelDetails).error, isNotNull);

        await send(
          const ModelDetailsSubmitted(
            contextWindow: 32000,
            maxOutputTokens: 2048,
          ),
        );
        final plan = (flow.current as Reviewing).plan;
        expect(
          plan.toEdits(),
          containsAll([
            const SetValue(
              'providers.anthropic.models.my-model.context_window',
              32000,
            ),
            const SetValue(
              'providers.anthropic.models.my-model.max_output_tokens',
              2048,
            ),
          ]),
        );
      },
    );

    test('id модели с точкой или слэшем пишется в кавычках', () async {
      await toChecking('openrouter', 'https://openrouter.ai/api/v1');
      await okWith(const [RemoteModel('qwen/qwen2.5-coder', contextWindow: 9)]);
      await send(const ModelChosen('qwen/qwen2.5-coder'));

      expect(
        (flow.current as Reviewing).plan.toEdits(),
        contains(
          const SetValue(
            'providers.openrouter.models."qwen/qwen2.5-coder".context_window',
            9,
          ),
        ),
      );
    });
  });

  group('Адрес', () {
    test(
      '3.0: http к нелокальному хосту — подтверждение зависит от isLocalHost',
      () async {
        final asked = <String>[];
        flow = build(
          isLocalHost: (host) {
            asked.add(host);
            return false;
          },
        );
        await send(const PresetChosen('custom-openai'));
        await send(const BaseUrlSubmitted('http://example.test:8080/v1'));
        expect(asked, ['example.test']);
        expect((flow.current as EnteringBaseUrl).insecureHost, 'example.test');

        flow = build(isLocalHost: (_) => true);
        await send(const PresetChosen('custom-openai'));
        await send(const BaseUrlSubmitted('http://example.test:8080/v1'));
        expect(flow.current, isA<ChoosingKey>());
      },
    );

    test('3.0: https не требует подтверждения при любом isLocalHost', () async {
      flow = build(isLocalHost: (_) => false);
      await send(const PresetChosen('custom-openai'));
      await send(const BaseUrlSubmitted('https://llm.test/v1'));
      expect(flow.current, isA<ChoosingKey>());
    });

    test('подтверждение http сбрасывается правкой адреса', () async {
      flow = build(isLocalHost: (_) => false);
      await send(const PresetChosen('custom-openai'));
      await send(const BaseUrlSubmitted('http://a.test/v1'));
      expect(flow.current, isA<EnteringBaseUrl>());
      await send(const InsecureAddressConfirmed('http://a.test/v1'));
      expect(flow.current, isA<ChoosingKey>());

      await send(const Back());
      await send(const BaseUrlSubmitted('http://b.test/v1'));
      expect(flow.current, isA<EnteringBaseUrl>());
      expect((flow.current as EnteringBaseUrl).insecureHost, 'b.test');
    });

    test('подтверждение http запоминается для того же адреса', () async {
      flow = build(isLocalHost: (_) => false);
      await send(const PresetChosen('custom-openai'));
      await send(const BaseUrlSubmitted('http://a.test/v1'));
      expect((flow.current as EnteringBaseUrl).insecureHost, 'a.test');
      await send(const InsecureAddressConfirmed('http://a.test/v1'));
      expect(flow.current, isA<ChoosingKey>());

      // Тот же адрес после «Back» повторного подтверждения не просит.
      await send(const Back());
      expect(flow.current, isA<EnteringBaseUrl>());
      await send(const BaseUrlSubmitted('http://a.test/v1'));
      expect(flow.current, isA<ChoosingKey>());

      // Другой адрес — снова подтверждение.
      await send(const Back());
      await send(const BaseUrlSubmitted('http://b.test/v1'));
      expect((flow.current as EnteringBaseUrl).insecureHost, 'b.test');
    });

    test('схема только http/https, завершающий / убирается', () async {
      await send(const PresetChosen('custom-openai'));
      await send(const BaseUrlSubmitted('ftp://llm.test/v1'));
      expect((flow.current as EnteringBaseUrl).error, isNotNull);
      await send(const BaseUrlSubmitted('not a url'));
      expect((flow.current as EnteringBaseUrl).error, isNotNull);

      await send(const BaseUrlSubmitted('https://llm.test/v1/'));
      expect(
        (flow.current as ChoosingKey).draft.baseUrl,
        'https://llm.test/v1',
      );
    });

    test('адрес с userinfo отклонён, query допустим', () async {
      await send(const PresetChosen('custom-openai'));
      await send(BaseUrlSubmitted('https://u:$leak@llm.example/v1'));
      final rejected = flow.current as EnteringBaseUrl;
      expect(rejected.error, userinfoError);

      await send(
        const BaseUrlSubmitted('https://llm.example/v1?api-version=2024-10-01'),
      );
      expect(flow.current, isA<ChoosingKey>());

      for (final state in seen) {
        expect(state.toString(), isNot(contains(leak)));
      }
      expect(logText(), isNot(contains(leak)));
    });

    test('id custom-хоста и суффиксы', () async {
      await send(const PresetChosen('custom-openai'));
      await send(const BaseUrlSubmitted('http://localhost:1234/v1'));
      expect((flow.current as ChoosingKey).draft.providerId, 'local-1234');

      Map<String, Object?> provider() => {
        'kind': 'openai-compatible',
        'base_url': 'https://h/v1',
      };
      flow = build(
        snapshot: snapshotOf(
          user: {
            'providers': {
              'local-1234': provider(),
              'local-1234-2': provider(),
              'openai': provider(),
            },
          },
        ),
      );
      await send(const PresetChosen('custom-openai'));
      await send(const BaseUrlSubmitted('http://localhost:1234/v1'));
      expect((flow.current as ChoosingKey).draft.providerId, 'local-1234-3');

      flow = build(
        snapshot: snapshotOf(
          user: {
            'providers': {'openai': provider()},
          },
        ),
      );
      await send(const PresetChosen('openai'));
      await send(const BaseUrlSubmitted('https://api.openai.com/v1'));
      expect((flow.current as ChoosingKey).draft.providerId, 'openai-2');
    });
  });

  group('План', () {
    Future<Reviewing> toReview({bool? setDefault}) async {
      await toChecking('openai', 'https://api.openai.com/v1');
      await okWith(const [RemoteModel('m', contextWindow: 8000)]);
      await send(const ModelChosen('m'));
      return flow.current as Reviewing;
    }

    test('makeDefault: true без agent.default_model, иначе false', () async {
      expect((await toReview()).plan.makeDefault, isTrue);

      flow = build(
        snapshot: snapshotOf(
          user: {
            'agent': {'default_model': 'p/m'},
          },
        ),
      );
      expect((await toReview()).plan.makeDefault, isFalse);
      await send(const ReviewEdited(makeDefault: true));
      expect((flow.current as Reviewing).plan.makeDefault, isTrue);
      expect(
        (flow.current as Reviewing).plan.toEdits(),
        contains(const SetValue('agent.default_model', 'openai/m')),
      );
    });

    test('forceDefault не даёт снять makeDefault', () async {
      flow = build(
        forceDefault: true,
        snapshot: snapshotOf(
          user: {
            'agent': {'default_model': 'p/m'},
          },
        ),
      );
      expect((await toReview()).plan.makeDefault, isTrue);
      await send(const ReviewEdited(makeDefault: false));
      expect((flow.current as Reviewing).plan.makeDefault, isTrue);
    });

    test('«This project only» — только с папкой проекта', () async {
      await toReview();
      await send(const ReviewEdited(target: ConfigTarget.projectLocal('/x')));
      expect(
        (flow.current as Reviewing).plan.target,
        const ConfigTarget.user(),
      );

      flow = build(
        snapshot: snapshotOf(projectLocal: {}),
        settings: access(),
      );
      await toReview();
      await send(
        const ReviewEdited(target: ConfigTarget.projectLocal('/work/project')),
      );
      expect(
        (flow.current as Reviewing).plan.target,
        const ConfigTarget.projectLocal('/work/project'),
      );
      await send(const ConfirmSave());
      expect(
        config.applied.single.base.target,
        const ConfigTarget.projectLocal('/work/project'),
      );
    });
  });

  group('Правка провайдера', () {
    Future<ProviderEntryView> entry(Map<String, Object?> provider) async {
      final snapshot = snapshotOf(
        user: {
          'agent': {'default_model': 'old/m'},
          'providers': {'old': provider},
        },
      );
      final views = await providerEntriesOf(
        snapshot,
        environment: const {},
        isSecretSet: (_) async => true,
      );
      return views.single;
    }

    Map<String, Object?> base() => {
      'kind': 'openai-compatible',
      'base_url': 'https://old.test/v1',
      'models': {
        'm': {'context_window': 8000},
      },
    };

    test('литеральный ключ: «оставить» нет, UnsetValue api_key', () async {
      final provider = {...base(), 'api_key': leak};
      final view = await entry(provider);
      expect(view.key, isA<KeyLiteralInConfig>());
      flow = build(
        snapshot: snapshotOf(
          user: {
            'agent': {'default_model': 'old/m'},
            'providers': {'old': provider},
          },
        ),
        editing: view,
      );
      expect(flow.current, isA<EnteringBaseUrl>());
      expect((flow.current as EnteringBaseUrl).draft.providerId, 'old');

      await send(const BaseUrlSubmitted('https://old.test/v1'));
      final step = flow.current as ChoosingKey;
      expect(step.canKeepStored, isFalse);
      expect(
        step.notice,
        'The key is written in config.yaml. Choose where to keep it instead.',
      );
      await send(const KeySubmitted(KeepStoredSecret()));
      expect(flow.current, isA<ChoosingKey>());

      await send(const KeySubmitted(UseEnvVar('OLD_KEY')));
      check.respond(const CheckOk([RemoteModel('m', contextWindow: 8000)]));
      await pumpEventQueue();
      await send(const ModelChosen('m'));
      final edits = (flow.current as Reviewing).plan.toEdits();

      expect(
        edits,
        contains(const SetValue('providers.old.api_key_env', 'OLD_KEY')),
      );
      expect(edits, contains(const UnsetValue('providers.old.api_key')));
      expect(
        edits.whereType<SetValue>().map((e) => e.key),
        isNot(contains('providers.old.api_key_secret')),
      );
      for (final state in seen) {
        expect(state.toString(), isNot(contains(leak)));
      }
      expect(logText(), isNot(contains(leak)));
    });

    test(
      'KeepStoredSecret при api_key_secret: проверка через keys.read, правок ключа нет',
      () async {
        keys = FakeProviderKeys(
          stored: {'codelab/old'},
          values: {'codelab/old': 'stored-value'},
        );
        final provider = {...base(), 'api_key_secret': 'codelab/old'};
        final view = await entry(provider);
        flow = build(
          snapshot: snapshotOf(
            user: {
              'agent': {'default_model': 'old/m'},
              'providers': {'old': provider},
            },
          ),
          editing: view,
        );
        await send(const BaseUrlSubmitted('https://old.test/v1'));
        expect((flow.current as ChoosingKey).canKeepStored, isTrue);
        await send(const KeySubmitted(KeepStoredSecret()));
        expect(check.calls.single.key, 'stored-value');

        check.respond(const CheckOk([RemoteModel('m', contextWindow: 8000)]));
        await pumpEventQueue();
        await send(const ModelChosen('m'));
        final edits = (flow.current as Reviewing).plan.toEdits();
        expect(
          edits.whereType<SetValue>().map((e) => e.key),
          isNot(contains('providers.old.api_key_secret')),
        );
      },
    );

    test('смена источника ключа убирает второй из пары', () async {
      final provider = {...base(), 'api_key_env': 'OLD_ENV'};
      final view = await entry(provider);
      flow = build(
        snapshot: snapshotOf(
          user: {
            'agent': {'default_model': 'old/m'},
            'providers': {'old': provider},
          },
        ),
        editing: view,
        environment: {'OLD_ENV': 'env-value'},
      );
      await send(const BaseUrlSubmitted('https://old.test/v1'));
      await send(KeySubmitted(StoreSecret(SecretValue(leak))));
      check.respond(const CheckOk([RemoteModel('m', contextWindow: 8000)]));
      await pumpEventQueue();
      await send(const ModelChosen('m'));
      final edits = (flow.current as Reviewing).plan.toEdits();
      expect(
        edits,
        containsAll([
          const SetValue('providers.old.api_key_secret', 'codelab/old'),
          const UnsetValue('providers.old.api_key_env'),
        ]),
      );
    });
  });

  group('Запись', () {
    Future<void> toReviewWithSecret() async {
      await toChecking(
        'openai',
        'https://api.openai.com/v1',
        key: StoreSecret(SecretValue(leak)),
      );
      await okWith(const [RemoteModel('m', contextWindow: 8000)]);
      await send(const ModelChosen('m'));
    }

    test(
      'секрет появился до записи: назад на шаг ключа с вариантами',
      () async {
        await toReviewWithSecret();
        keys.storedAnswers.add(true);
        await send(const ConfirmSave());

        final step = flow.current as ChoosingKey;
        expect(step.existingSecret, 'codelab/openai');
        expect(config.applied, isEmpty);
        expect(keys.written, isEmpty);
      },
    );

    test('хранилище отказало: шаг ключа с причиной', () async {
      keys.onWrite = (_, _) => const ProviderKeyRefused('store failed');
      await toReviewWithSecret();
      await send(const ConfirmSave());

      final step = flow.current as ChoosingKey;
      expect(step.error, contains('store failed'));
      expect(config.applied, isEmpty);
    });

    test('конфиг не записан: SaveFailed, Back — в Reviewing', () async {
      config.outcome = const ConfigRejected([]);
      await toReviewWithSecret();
      await send(const ConfirmSave());

      final failed = flow.current as SaveFailed;
      expect(failed.failure.outcome, isA<ConfigRejected>());
      expect(keys.journal, contains('delete codelab/openai'));

      await send(const Back());
      expect(flow.current, isA<Reviewing>());
    });

    /// Снимок после внешней правки файла: другой отпечаток и чужой ключ.
    AgentConfigSnapshot fresh({
      Map<String, Object?> providers = const {},
      String? defaultModel,
    }) => AgentConfigSnapshot.fromLayers(
      cwd: '/work/project',
      layers: {
        ConfigLayer.user: ConfigSnapshot(
          target: const ConfigTarget.user(),
          path: '/h/config.yaml',
          fingerprint: 'fp-user-2',
          values: {
            'budget': {'max_steps': 5},
            if (defaultModel != null) 'agent': {'default_model': defaultModel},
            if (providers.isNotEmpty) 'providers': providers,
          },
        ),
      },
      loaded: const ConfigLoadResult(),
      secrets: const SecretBackendInfo(id: 'file', writable: true),
    );

    test(
      'конфликт: снимок перечитан, повторный Save пишет поверх свежего',
      () async {
        await toReviewWithSecret();
        config.outcome = const ConfigConflict('/h/config.yaml');
        config.snapshotValue = fresh();
        await send(const ConfirmSave());
        expect(flow.current, isA<SaveFailed>());
        expect(
          (flow.current as SaveFailed).failure.outcome,
          isA<ConfigConflict>(),
        );

        config.outcome = const ConfigSaved(
          fingerprint: 'fp-3',
          warnings: [],
          restartRequiredKeys: [],
        );
        await send(const Back());
        expect(flow.current, isA<Reviewing>());
        await send(const ConfirmSave());

        expect(flow.current, isA<Done>());
        expect(config.applied, hasLength(2));
        expect(config.applied.first.base.fingerprint, 'fp-user');
        expect(config.applied.last.base.fingerprint, 'fp-user-2');
        expect(config.applied.last.base.get('budget.max_steps'), 5);
        // Внешняя правка файла сохранена в основе записи. Введённый ключ сохранён в черновике: откат после конфликта и запись
        // при повторном Save, в конце секрет в хранилище.
        expect(
          keys.journal.where((j) => j.contains('codelab/openai')),
          containsAllInOrder([
            'write codelab/openai',
            'delete codelab/openai',
            'write codelab/openai',
          ]),
        );
        expect(keys.written, {'codelab/openai': leak});
      },
    );

    test('повторный конфликт откатывает секрет и не копит записи', () async {
      await toReviewWithSecret();
      config.outcome = const ConfigConflict('/h/config.yaml');
      config.snapshotValue = fresh();
      await send(const ConfirmSave());
      await send(const Back());
      await send(const ConfirmSave());

      expect(flow.current, isA<SaveFailed>());
      expect(keys.written, isEmpty);
      expect(keys.storedNames, isEmpty);
    });

    test(
      'провайдер с тем же id появился: типизированный отказ без записи',
      () async {
        await toReviewWithSecret();
        config.outcome = const ConfigConflict('/h/config.yaml');
        config.snapshotValue = fresh(
          providers: {
            'openai': {'kind': 'openai-compatible', 'base_url': 'https://h/v1'},
          },
        );
        await send(const ConfirmSave());
        await send(const Back());
        await send(const ConfirmSave());

        final review = flow.current as Reviewing;
        expect(review.refusal, PlanRefusal.providerExists);
        expect(config.applied, hasLength(1));
        expect(keys.written, isEmpty);
      },
    );

    test('Cancel недопустим в Done', () async {
      await toReviewWithSecret();
      await send(const ConfirmSave());
      expect(flow.current, isA<Done>());
      await send(const Cancel());
      expect(flow.current, isA<Done>());
    });
  });

  group('Ревью итерации 3', () {
    const userinfoError = 'Remove the user name and password from the address.';

    Map<String, Object?> openai() => {
      'kind': 'openai-compatible',
      'base_url': 'https://old.test/v1',
      'models': {
        'm': {'context_window': 8000},
        'n': {'context_window': 8000},
      },
    };

    AgentConfigSnapshot twoProviders({String? defaultModel = 'old/m'}) =>
        snapshotOf(
          user: {
            'agent': {'default_model': ?defaultModel},
            'providers': {
              'old': openai(),
              'other': {
                'kind': 'openai-compatible',
                'base_url': 'https://other.test/v1',
                'models': {
                  'x': {'context_window': 8000},
                },
              },
            },
          },
        );

    Future<ProviderEntryView> viewOf(
      AgentConfigSnapshot snapshot,
      String id,
    ) async => (await providerEntriesOf(
      snapshot,
      environment: const {},
      isSecretSet: (_) async => true,
    )).firstWhere((e) => e.id == id);

    AgentConfigSnapshot freshWith({String? defaultModel}) =>
        AgentConfigSnapshot.fromLayers(
          cwd: '/work/project',
          layers: {
            ConfigLayer.user: ConfigSnapshot(
              target: const ConfigTarget.user(),
              path: '/h/config.yaml',
              fingerprint: 'fp-user-2',
              values: {
                if (defaultModel != null)
                  'agent': {'default_model': defaultModel},
              },
            ),
          },
          loaded: const ConfigLoadResult(),
          secrets: const SecretBackendInfo(id: 'file', writable: true),
        );

    Future<void> toReview({KeyChoice? key, bool replace = false}) async {
      await toChecking(
        'openai',
        'https://api.openai.com/v1',
        key: key,
        replace: replace,
      );
      await okWith(const [RemoteModel('m', contextWindow: 8000)]);
      await send(const ModelChosen('m'));
    }

    group('1. переименование на Review', () {
      test('сбрасывает «Replace it» и пересчитывает имя секрета', () async {
        keys = FakeProviderKeys(stored: {'codelab/openai', 'codelab/second'});
        flow = build();
        await toReview(key: StoreSecret(SecretValue(leak)), replace: true);
        expect((flow.current as Reviewing).plan.replaceSecret, isTrue);

        await send(const ReviewEdited(providerId: 'second'));
        final plan = (flow.current as Reviewing).plan;
        expect(plan.replaceSecret, isFalse);
        expect(plan.secretName, 'codelab/second');

        await send(const ConfirmSave());
        expect((flow.current as ChoosingKey).existingSecret, 'codelab/second');
        expect(keys.journal.where((j) => j.startsWith('write')), isEmpty);
        expect(config.applied, isEmpty);
      });

      test('Back → Model → Review собирает согласованный план', () async {
        keys = FakeProviderKeys(stored: {'codelab/openai'});
        flow = build();
        await toReview(key: StoreSecret(SecretValue(leak)), replace: true);
        await send(const ReviewEdited(providerId: 'second'));
        await send(const Back());
        await send(const ModelChosen('m'));

        final plan = (flow.current as Reviewing).plan;
        expect(plan.providerId, 'second');
        expect(plan.secretName, 'codelab/second');
        expect(plan.replaceSecret, isFalse);
        expect(
          plan.toEdits(),
          contains(
            const SetValue('providers.second.api_key_secret', 'codelab/second'),
          ),
        );
      });
    });

    group('2. план после перечитывания снимка', () {
      Future<void> conflictThenBack({String? freshDefault}) async {
        await toReview(key: const UseEnvVar('K'));
        config.outcome = const ConfigConflict('/h/config.yaml');
        config.snapshotValue = freshWith(defaultModel: freshDefault);
        await send(const ConfirmSave());
        await send(const Back());
        config.outcome = const ConfigSaved(
          fingerprint: 'fp-3',
          warnings: [],
          restartRequiredKeys: [],
        );
      }

      Iterable<String> setKeys() =>
          config.applied.last.edits.whereType<SetValue>().map((e) => e.key);

      test(
        'внешний agent.default_model после конфликта не перезаписан',
        () async {
          await conflictThenBack(freshDefault: 'other/x');
          expect((flow.current as Reviewing).plan.makeDefault, isFalse);
          await send(const ConfirmSave());

          expect(flow.current, isA<Done>());
          expect(setKeys(), isNot(contains('agent.default_model')));
        },
      );

      test('явный выбор «Make default» переживает перечитывание', () async {
        await toReview(key: const UseEnvVar('K'));
        await send(const ReviewEdited(makeDefault: true));
        config.outcome = const ConfigConflict('/h/config.yaml');
        config.snapshotValue = freshWith(defaultModel: 'other/x');
        await send(const ConfirmSave());
        await send(const Back());
        config.outcome = const ConfigSaved(
          fingerprint: 'fp-3',
          warnings: [],
          restartRequiredKeys: [],
        );
        await send(const ConfirmSave());

        expect(setKeys(), contains('agent.default_model'));
      });
    });

    group('3. исключение при откате секрета', () {
      test(
        'rollback=failed, исход конфликта сохранён, снимок перечитан',
        () async {
          keys.throwOnDelete = StateError('boom $leak');
          await toReview(key: StoreSecret(SecretValue(leak)));
          config.outcome = const ConfigConflict('/h/config.yaml');
          config.snapshotValue = freshWith();
          await send(const ConfirmSave());

          final failed = (flow.current as SaveFailed).failure;
          expect(failed.outcome, isA<ConfigConflict>());
          expect(failed.rollback, KeyRollback.failed);
          expect(failed.toString(), isNot(contains(leak)));

          // Секрет остался в хранилище: повторный Save видит его и возвращает
          // на шаг ключа («Use the stored key» / «Replace it»), не пишет молча.
          await send(const Back());
          await send(const ConfirmSave());
          expect(
            (flow.current as ChoosingKey).existingSecret,
            'codelab/openai',
          );
          expect(config.applied, hasLength(1));
        },
      );
    });

    group('4. подтверждение http привязано к адресу поля', () {
      test('другой адрес в поле: подтверждение не уходит на прежний', () async {
        flow = build(isLocalHost: (_) => false);
        await send(const PresetChosen('custom-openai'));
        await send(const BaseUrlSubmitted('http://a.test/v1'));
        expect((flow.current as EnteringBaseUrl).insecureHost, 'a.test');

        await send(const InsecureAddressConfirmed('https://b.test/v1'));
        final step = flow.current as ChoosingKey;
        expect(step.draft.baseUrl, 'https://b.test/v1');
        expect(step.draft.confirmedInsecureUrl, isNull);

        // Подтверждение a.test не осталось в черновике.
        await send(const Back());
        await send(const BaseUrlSubmitted('http://a.test/v1'));
        expect((flow.current as EnteringBaseUrl).insecureHost, 'a.test');
      });

      test('другой http-адрес переоценивается как BaseUrlSubmitted', () async {
        flow = build(isLocalHost: (_) => false);
        await send(const PresetChosen('custom-openai'));
        await send(const BaseUrlSubmitted('http://a.test/v1'));
        await send(const InsecureAddressConfirmed('http://b.test/v1'));

        expect((flow.current as EnteringBaseUrl).insecureHost, 'b.test');
      });
    });

    group('5. Edit с userinfo в конфиге', () {
      test('черновик без userinfo, query сохранён, ошибка шага', () async {
        final snapshot = snapshotOf(
          user: {
            'providers': {
              'old': {
                ...openai(),
                'base_url': 'https://u:$leak@llm.example/v1?api-version=1',
              },
            },
          },
        );
        flow = build(
          snapshot: snapshot,
          editing: await viewOf(snapshot, 'old'),
        );

        final step = flow.current as EnteringBaseUrl;
        expect(step.error, userinfoError);
        expect(step.draft.baseUrl, 'https://llm.example/v1?api-version=1');
        expect(step.toString(), isNot(contains(leak)));
        expect(step.draft.toString(), isNot(contains(leak)));
        expect(logText(), isNot(contains(leak)));

        await send(
          const BaseUrlSubmitted('https://llm.example/v1?api-version=1'),
        );
        expect(flow.current, isA<ChoosingKey>());
        for (final state in seen) {
          expect(state.toString(), isNot(contains(leak)));
        }
        expect(logText(), isNot(contains(leak)));
      });
    });

    group('6. check_discarded пишется один раз', () {
      Iterable<LogRecord> discarded() =>
          logger.eventsOf('provider_wizard.check_discarded');

      test(
        'отмена: запись при отмене, CheckCancelled её не дублирует',
        () async {
          await toChecking('openai', 'https://api.openai.com/v1');
          await send(const Back());
          expect(discarded(), hasLength(1));
          expect(discarded().single.fields, {
            'operation_id': 1,
            'preset': 'openai',
            'endpoint': 'https://api.openai.com',
            'outcome': 'discarded',
          });

          check.respond(const CheckCancelled());
          await pumpEventQueue();
          expect(discarded(), hasLength(1));
        },
      );

      test('поздний результат той же попытки второй записи не даёт', () async {
        await toChecking('openai', 'https://api.openai.com/v1');
        await send(const Cancel());
        await okWith(const [RemoteModel('m')]);

        expect(discarded(), hasLength(1));
      });

      test('завершённая в срок проверка не пишется как отброшенная', () async {
        await toChecking('openai', 'https://api.openai.com/v1');
        await okWith(const [RemoteModel('m')]);
        await send(const Cancel());

        expect(discarded(), isEmpty);
      });
    });

    group('7. правило Edit — одно с Remove', () {
      AgentConfigSnapshot twoLayers() => snapshotOf(
        user: {
          'providers': {
            'old': {'kind': 'openai-compatible', 'base_url': 'https://h/v1'},
          },
        },
        projectLocal: {
          'providers': {
            'old': {
              'models': {
                'm': {'context_window': 8000},
              },
            },
          },
        },
      );

      test('providerEditRefusal различает отказы', () async {
        final snapshot = twoLayers();
        expect(
          providerEditRefusal(snapshot, 'old'),
          ProviderRemovalRefusal.multipleLayers,
        );
        expect(
          providerEditRefusal(snapshot, 'nope'),
          ProviderRemovalRefusal.unknownProvider,
        );
        expect(providerEditRefusal(twoProviders(), 'old'), isNull);

        final external = AgentConfigSnapshot.fromLayers(
          cwd: '/work/project',
          layers: const {},
          loaded: const ConfigLoadResult(
            values: {'providers.gw.kind': 'openai-compatible'},
          ),
          secrets: const SecretBackendInfo(id: 'file', writable: true),
          externalOrigin: (key) => const ConfigSourceView(
            kind: ConfigSourceKind.extraFile,
            label: '/etc/team.yaml',
          ),
        );
        expect(
          providerEditRefusal(external, 'gw'),
          ProviderRemovalRefusal.notEditable,
        );
      });

      test(
        'ConfirmSave при Edit с отказом — типизированный отказ без записи',
        () async {
          final snapshot = twoLayers();
          flow = build(
            snapshot: snapshot,
            editing: await viewOf(snapshot, 'old'),
          );
          await send(const BaseUrlSubmitted('https://h/v1'));
          await send(const KeySubmitted(NoKey()));
          await okWith(const [RemoteModel('m', contextWindow: 8000)]);
          await send(const ModelChosen('m'));
          await send(const ConfirmSave());

          expect(
            (flow.current as Reviewing).refusal,
            PlanRefusal.multipleLayers,
          );
          expect(config.applied, isEmpty);
        },
      );
    });

    group('8. entry', () {
      test('wire-значения D18', () {
        expect(
          {for (final e in ProviderWizardEntry.values) e: e.wire},
          {
            ProviderWizardEntry.app: 'app',
            ProviderWizardEntry.banner: 'banner',
            ProviderWizardEntry.cli: 'cli',
            ProviderWizardEntry.firstRun: 'first_run',
            ProviderWizardEntry.flags: 'flags',
          },
        );
      });

      test('started пишет wire-значение', () {
        flow = build(entry: ProviderWizardEntry.firstRun);
        expect(
          logger.eventsOf('provider_wizard.started').last.fields['entry'],
          'first_run',
        );
      });
    });

    group('10. save_failed: rollback', () {
      test('deleted при откате созданного секрета', () async {
        config.outcome = const ConfigRejected([]);
        await toReview(key: StoreSecret(SecretValue(leak)));
        await send(const ConfirmSave());

        final failed = logger.eventsOf('provider_wizard.save_failed').single;
        expect(failed.fields['rollback'], 'deleted');
        expect(failed.fields.containsKey('secret_rolled_back'), isFalse);
      });
    });

    group('11. UX', () {
      test('id любого локального хоста — local-<port>', () async {
        bool local(String host) =>
            host == 'localhost' || host == '127.0.0.1' || host == '::1';
        Future<String> idOf(String url) async {
          flow = build(isLocalHost: local);
          await send(const PresetChosen('custom-openai'));
          await send(BaseUrlSubmitted(url));
          return (flow.current as ChoosingKey).draft.providerId;
        }

        expect(await idOf('http://127.0.0.1:18765/v1'), 'local-18765');
        expect(await idOf('http://[::1]:8080/v1'), 'local-8080');
        expect(await idOf('http://localhost/v1'), 'local');
        expect(await idOf('https://llm.example/v1'), 'llm-example');
      });

      test(
        'Edit: текущая модель выбрана, «Make default» отражает состояние',
        () async {
          final snapshot = twoProviders();
          flow = build(
            snapshot: snapshot,
            editing: await viewOf(snapshot, 'old'),
          );
          await send(const BaseUrlSubmitted('https://old.test/v1'));
          await send(const KeySubmitted(NoKey()));
          await okWith(const [
            RemoteModel('m', contextWindow: 8000),
            RemoteModel('z', contextWindow: 8000),
          ]);
          expect((flow.current as ChoosingModel).currentModel, 'm');

          await send(const ModelChosen('z'));
          expect((flow.current as Reviewing).plan.makeDefault, isTrue);
        },
      );

      test('Edit не-default провайдера: default не навязывается', () async {
        final snapshot = twoProviders();
        flow = build(
          snapshot: snapshot,
          editing: await viewOf(snapshot, 'other'),
        );
        await send(const BaseUrlSubmitted('https://other.test/v1'));
        await send(const KeySubmitted(NoKey()));
        await okWith(const [RemoteModel('x', contextWindow: 8000)]);
        expect((flow.current as ChoosingModel).currentModel, 'x');

        await send(const ModelChosen('x'));
        expect((flow.current as Reviewing).plan.makeDefault, isFalse);
      });
    });
  });

  group('Прочее', () {
    test('событие не к месту: игнор и debug-запись', () async {
      await send(const RetryCheck());

      expect(flow.current, isA<ChoosingPreset>());
      final record = logger.eventsOf('provider_wizard.event_ignored').single;
      expect(record.level, LogLevel.debug);
      expect(record.fields['state'], 'ChoosingPreset');
    });

    test(
      'D18: started и saved несут поля таблицы, без env-имени и ключа',
      () async {
        flow = build(
          entry: ProviderWizardEntry.banner,
          environment: {'MY_ENV_KEY': 'env-secret'},
        );
        final started = logger.eventsOf('provider_wizard.started').last;
        expect(started.fields, {'mode': 'add', 'entry': 'banner'});

        await toChecking(
          'openai',
          'https://api.openai.com/v1',
          key: const UseEnvVar('MY_ENV_KEY'),
        );
        await okWith(const [RemoteModel('m', contextWindow: 8000)]);
        await send(const ModelChosen('m'));
        await send(const ConfirmSave());

        final saved = logger.eventsOf('provider_wizard.saved').single;
        expect(saved.fields, {
          'provider_id': 'openai',
          'key': 'env',
          'target': 'user',
          'make_default': true,
          'skipped_check': false,
        });
        final finished = logger
            .eventsOf('provider_wizard.check_finished')
            .single;
        expect(finished.fields['preset'], 'openai');
        expect(finished.fields['endpoint'], 'https://api.openai.com');
        expect(finished.fields['outcome'], 'ok');
        expect(finished.fields.containsKey('operation_id'), isTrue);
        expect(logText(), isNot(contains('MY_ENV_KEY')));
        expect(logText(), isNot(contains('env-secret')));
      },
    );

    test('D18: режим edit и save_failed с видом исхода', () async {
      keys.onWrite = (_, _) => const ProviderKeyRefused('store failed');
      await toChecking(
        'openai',
        'https://api.openai.com/v1',
        key: StoreSecret(SecretValue(leak)),
      );
      await okWith(const [RemoteModel('m', contextWindow: 8000)]);
      await send(const ModelChosen('m'));
      await send(const ConfirmSave());

      final failed = logger.eventsOf('provider_wizard.save_failed').single;
      expect(failed.fields['provider_id'], 'openai');
      expect(failed.fields['outcome'], 'secret_failed');
      expect(failed.fields['rollback'], 'none');
      expect(failed.fields.containsKey('secret_rolled_back'), isFalse);
      expect(failed.fields.containsKey('error_type'), isFalse);
      expect(logText(), isNot(contains('store failed')));
    });

    test('D18: error несёт только имя типа, cancelled — состояние', () async {
      config.throwOnApply = StateError('boom $leak');
      await toChecking('openai', 'https://api.openai.com/v1');
      await okWith(const [RemoteModel('m', contextWindow: 8000)]);
      await send(const ModelChosen('m'));
      await send(const ConfirmSave());

      final failed = logger.eventsOf('provider_wizard.save_failed').single;
      expect(failed.fields['outcome'], 'error');
      expect(failed.fields['error_type'], 'StateError');
      expect(logText(), isNot(contains(leak)));

      await send(const Back());
      await send(const Cancel());
      expect(
        logger.eventsOf('provider_wizard.cancelled').single.fields['state'],
        'Reviewing',
      );
    });

    test('Cancel допустим из любого шага, кроме Saving и Done', () async {
      await send(const PresetChosen('openai'));
      await send(const Cancel());
      expect(flow.current, isA<Cancelled>());
    });

    test(
      'значение не печатается ни в состояниях, ни в плане, ни в журнале',
      () async {
        await toChecking(
          'anthropic',
          'https://api.anthropic.com',
          key: StoreSecret(SecretValue(leak)),
        );
        await okWith(const [RemoteModel('m', contextWindow: 8000)]);
        await send(const ModelChosen('m'));
        final plan = (flow.current as Reviewing).plan;
        await send(const ConfirmSave());

        for (final state in seen) {
          expect(state.toString(), isNot(contains(leak)));
        }
        expect(plan.toString(), isNot(contains(leak)));
        for (final edit in plan.toEdits()) {
          expect(edit.toString(), isNot(contains(leak)));
          if (edit is SetValue) {
            expect('${edit.value}', isNot(contains(leak)));
          }
        }
        expect(logText(), isNot(contains(leak)));
      },
    );

    test('Done, Cancel и dispose сбрасывают ссылку на значение', () async {
      await toChecking(
        'anthropic',
        'https://api.anthropic.com',
        key: StoreSecret(SecretValue(leak)),
      );
      expect(flow.holdsSecret, isTrue);
      await send(const Cancel());
      expect(flow.holdsSecret, isFalse);

      flow = build();
      await toChecking(
        'anthropic',
        'https://api.anthropic.com',
        key: StoreSecret(SecretValue(leak)),
      );
      await flow.dispose();
      expect(flow.holdsSecret, isFalse);
    });

    test(
      'один автомат для двух клиентов: те же события — те же состояния и правки',
      () async {
        Future<(List<Type>, List<ConfigEdit>)> run() async {
          check = FakeProviderCheck();
          keys = FakeProviderKeys();
          config = FakeConfigStore(journal = []);
          seen = [];
          flow = build();
          await toChecking(
            'anthropic',
            'https://api.anthropic.com',
            key: StoreSecret(SecretValue(leak)),
          );
          await okWith(const [RemoteModel('claude-x', contextWindow: 1000)]);
          await send(const ModelChosen('claude-x'));
          await send(const ConfirmSave());
          return (kinds(), config.applied.single.edits);
        }

        final first = await run();
        final second = await run();

        expect(second.$1, first.$1);
        expect(second.$2, first.$2);
      },
    );
  });
}

final class _FixedStopwatch implements Stopwatch {
  _FixedStopwatch(int millis) : elapsed = Duration(milliseconds: millis);

  @override
  final Duration elapsed;
  @override
  int get frequency => 1000000;
  @override
  int get elapsedTicks => elapsed.inMicroseconds;
  @override
  int get elapsedMicroseconds => elapsed.inMicroseconds;
  @override
  int get elapsedMilliseconds => elapsed.inMilliseconds;
  @override
  bool get isRunning => false;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  void reset() {}
}
