// `wizardStepOf` и перенесённые чистые функции: тексты шагов `CliSetup` для
// каждого `ProviderSetupState` (задача 4.8a change `add-provider-setup-ui`;
// design.md D15, D17). Состояния собираются напрямую: автомата и портов нет.

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

const _anthropic = ProviderPreset(
  id: 'anthropic',
  label: 'Anthropic',
  kind: 'anthropic',
  baseUrl: 'https://api.anthropic.com',
  key: KeyRequirement.required,
  suggestedEnvVar: 'ANTHROPIC_API_KEY',
);

const _draft = ProviderDraft(
  providerId: 'anthropic',
  kind: 'anthropic',
  baseUrl: 'https://api.anthropic.com',
  preset: _anthropic,
);

ChoosingKey _key({
  bool ready = true,
  bool writable = true,
  String? existing,
  bool canKeep = false,
  String? error,
  String? notice,
  String? env = 'ANTHROPIC_API_KEY',
  String? hint,
}) => ChoosingKey(
  _draft,
  backend: SecretBackendInfo(
    id: 'file',
    writable: writable,
    unavailableReason: writable ? null : 'no OS store',
  ),
  ready: ready,
  canStoreSecret: writable,
  canKeepStored: canKeep,
  readOnlyHint: hint,
  existingSecret: existing,
  error: error,
  notice: notice,
  suggestedEnvVar: env,
);

List<String> labels(WizardStep step) => [for (final o in step.options) o.label];

ProviderSetupPlan _plan({KeyChoice key = const NoKey()}) => ProviderSetupPlan(
  providerId: 'anthropic',
  kind: 'anthropic',
  baseUrl: 'https://api.anthropic.com?token=sk-test-leak-0123456789',
  key: key,
  secretName: key is NoKey ? null : 'codelab/anthropic',
  replaceSecret: false,
  model: const PlannedModel(id: 'claude', contextWindow: 8000),
  makeDefault: true,
  target: const ConfigTarget.user(),
);

void main() {
  test('ChoosingPreset: пресеты из состояния, действие — PresetChosen', () {
    final step = wizardStepOf(ChoosingPreset(ProviderPresets.all));

    expect(step.title, 'API type');
    expect(labels(step), [for (final p in ProviderPresets.all) p.label]);
    expect(
      (step.options[1].action as SendEvent).event,
      isA<PresetChosen>().having((e) => e.presetId, 'id', 'anthropic'),
    );
  });

  group('EnteringBaseUrl', () {
    test('поле адреса с начальным значением', () {
      final step = wizardStepOf(const EnteringBaseUrl(_draft));

      expect(step.field!.prompt, '? Base URL › ');
      expect(step.field!.initial, 'https://api.anthropic.com');
      expect(
        (step.field!.submit('x') as SendEvent).event,
        isA<BaseUrlSubmitted>(),
      );
    });

    test('ошибка шага — строка перед полем', () {
      final step = wizardStepOf(
        const EnteringBaseUrl(_draft, error: 'Enter an http or https address.'),
      );

      expect(step.notes, ['  Enter an http or https address.']);
    });

    test('небезопасный адрес: вопрос; y подтверждает, иначе поле адреса', () {
      final step = wizardStepOf(
        const EnteringBaseUrl(_draft, insecureHost: 'gw.example'),
      );

      expect(
        step.field!.prompt,
        '? Send the key unencrypted to gw.example? [y/N] ',
      );
      expect(
        (step.field!.submit('y') as SendEvent).event,
        isA<InsecureAddressConfirmed>(),
      );
      expect(step.field!.submit('n'), isA<AskField>());
    });
  });

  group('ChoosingKey', () {
    test('ещё не готов — шаг ждёт', () {
      expect(wizardStepOf(_key(ready: false)).waiting, isTrue);
    });

    test('записываемый бэкенд: Store, переменная, No key', () {
      final step = wizardStepOf(_key());

      expect(step.title, 'API key source');
      expect(labels(step), [
        'Store in file as "codelab/anthropic"',
        'Read from environment variable (ANTHROPIC_API_KEY)',
        'No key',
      ]);
      expect(step.options[0].action, isA<AskSecret>());
      expect(step.backend, 'file');
    });

    test('без предложенной переменной — вопрос имени', () {
      final step = wizardStepOf(_key(env: null));

      expect(labels(step)[1], 'Read from an environment variable');
      expect(step.options[1].action, isA<AskEnvName>());
    });

    test('существующий секрет: Use the stored key и Replace it', () {
      final step = wizardStepOf(
        _key(existing: 'codelab/anthropic', canKeep: true),
      );

      expect(step.notes, [
        'A stored key codelab/anthropic already exists in file.',
      ]);
      expect(labels(step).take(2), ['Use the stored key', 'Replace it']);
      expect((step.options[1].action as AskSecret).replace, isTrue);
    });

    test('бэкенд только для чтения: причина вместо варианта «Store…»', () {
      final step = wizardStepOf(_key(writable: false, hint: 'READONLY-HINT'));

      expect(step.notes, ['READONLY-HINT']);
      expect(labels(step).any((l) => l.startsWith('Store in')), isFalse);
    });

    test('без подсказки — причина бэкенда', () {
      final step = wizardStepOf(_key(writable: false));

      expect(step.notes, ['no OS store']);
    });

    test('notice и ошибка идут перед пояснениями', () {
      final step = wizardStepOf(_key(notice: 'N', error: 'E'));

      expect(step.notes, ['N', '  E']);
    });
  });

  test('поля ключа, переменной и модели', () {
    final secret = secretField(replace: true);
    expect(secret.prompt, '? API key › ');
    expect(secret.hidden, isTrue);
    expect(secret.submit(''), isA<Reask>());
    expect(
      ((secret.submit('k') as SendEvent).event as KeySubmitted).replaceExisting,
      isTrue,
    );
    expect(
      ((envNameField().submit(' GW_KEY ') as SendEvent).event as KeySubmitted)
          .choice,
      isA<UseEnvVar>().having((c) => c.name, 'name', 'GW_KEY'),
    );
    expect(modelIdField().prompt, '? Model id › ');
    expect(modelIdField().submit('  '), isA<Reask>());
    expect(
      (modelIdField().submit(' m ') as SendEvent).event,
      isA<ModelEnteredManually>().having((e) => e.modelId, 'id', 'm'),
    );
    expect(fieldOfAction(const AskEnvName())!.prompt, envNameField().prompt);
    expect(fieldOfAction(const AskModelId())!.prompt, modelIdField().prompt);
    expect(fieldOfAction(const AskSecret(replace: false))!.hidden, isTrue);
    expect(fieldOfAction(const Reask()), isNull);
  });

  test('Checking: строка прогресса без перевода строки', () {
    final step = wizardStepOf(
      Checking(_draft, Uri.parse('https://api.anthropic.com/v1/models'), 1),
    );

    expect(step.progress, 'Checking https://api.anthropic.com/v1/models … ');
  });

  group('CheckFailed', () {
    CheckFailed failed(
      ProviderCheckFailureKind kind, {
      int? status,
      bool v1 = false,
      bool skip = false,
    }) => CheckFailed(
      _draft,
      ProviderCheckFailure(kind: kind, statusCode: status, message: 'x'),
      Uri.parse('https://a/v1/models'),
      Duration.zero,
      canSkip: skip,
      canUseV1: v1,
    );

    test('заголовки отказов', () {
      expect(
        checkFailureTitle(
          const ProviderCheckFailure(
            kind: ProviderCheckFailureKind.unauthorized,
            statusCode: 401,
            message: '',
          ),
        ),
        'Key rejected (401)',
      );
      expect(
        checkFailureTitle(
          const ProviderCheckFailure(
            kind: ProviderCheckFailureKind.unreachable,
            message: '',
          ),
        ),
        'Server unreachable',
      );
      expect(
        checkFailureTitle(
          const ProviderCheckFailure(
            kind: ProviderCheckFailureKind.timeout,
            message: '',
          ),
        ),
        'Timed out after 10 s',
      );
      expect(
        checkFailureTitle(
          const ProviderCheckFailure(
            kind: ProviderCheckFailureKind.tlsError,
            message: '',
          ),
        ),
        'TLS error',
      );
      expect(
        checkFailureTitle(
          const ProviderCheckFailure(
            kind: ProviderCheckFailureKind.notFound,
            statusCode: 404,
            message: '',
          ),
        ),
        'Model list not found (404)',
      );
      expect(
        checkFailureTitle(
          const ProviderCheckFailure(
            kind: ProviderCheckFailureKind.badResponse,
            statusCode: 502,
            message: '',
          ),
        ),
        'Unexpected response (502)',
      );
    });

    test('варианты по возможностям', () {
      final step = wizardStepOf(
        failed(
          ProviderCheckFailureKind.notFound,
          status: 404,
          v1: true,
          skip: true,
        ),
      );

      expect(step.title, 'The check failed');
      expect(step.notes, ['failed: Model list not found (404)']);
      expect(labels(step), [
        'Retry',
        'Use the address with /v1',
        'Enter model id manually',
        'Continue without checking',
        'Back',
      ]);
      expect(step.options[2].action, isA<AskModelId>());
    });

    test('минимальный набор: Retry и Back', () {
      final step = wizardStepOf(failed(ProviderCheckFailureKind.unauthorized));

      expect(labels(step), ['Retry', 'Back']);
    });
  });

  group('ChoosingModel и модель', () {
    test('список моделей с фильтром', () {
      final step = wizardStepOf(
        const ChoosingModel(
          _draft,
          [RemoteModel('a'), RemoteModel('b')],
          checked: true,
          currentModel: 'b',
        ),
      );

      expect(step.notes, ['ok, 2 models']);
      expect(step.models, ['a', 'b']);
      expect(step.currentModel, 'b');
    });

    test('пустой список или без проверки — поле id модели', () {
      final step = wizardStepOf(
        const ChoosingModel(_draft, [], checked: false),
      );

      expect(step.notes, ['not verified; the model list is unknown']);
      expect(step.field!.prompt, '? Model id › ');
    });

    test('окно контекста: подсказка, значение и ошибка автомата', () {
      final step = wizardStepOf(
        const EnteringModelDetails(_draft, 'm1', 8000, error: 'bad'),
      );

      expect(step.notes, ['  bad']);
      expect(step.field!.prompt, '? Context window for m1 (tokens) › ');
      expect(step.field!.initial, '8000');
      expect(
        ((step.field!.submit('abc') as SendEvent).event
                as ModelDetailsSubmitted)
            .contextWindow,
        0,
        reason: 'проверка — у автомата',
      );
      expect(
        ((step.field!.submit(' 4096 ') as SendEvent).event
                as ModelDetailsSubmitted)
            .contextWindow,
        4096,
      );
    });
  });

  group('Reviewing, сводка и запись', () {
    test('сводка: ключ, модель по умолчанию, файл; адрес без query', () {
      final lines = reviewSummary(
        _plan(key: const KeepStoredSecret()),
        backend: 'file',
        path: '/h/config.yaml',
      );

      expect(lines, [
        'Provider "anthropic"',
        '  (anthropic, https://api.anthropic.com)',
        '  key    secret "codelab/anthropic" (file)',
        '  model  anthropic/claude (default)',
        '  file   /h/config.yaml',
      ]);
      expect(lines.join(), isNot(contains('sk-test-leak')));
    });

    test('ключ из переменной и без ключа', () {
      expect(
        reviewSummary(
          _plan(key: const UseEnvVar('GW_KEY')),
          backend: 'file',
        )[2],
        '  key    env GW_KEY',
      );
      expect(reviewSummary(_plan(), backend: 'file')[2], '  key    none');
    });

    test('шаг: сводка, предупреждения, вопрос; ответы y, Enter, n', () {
      final step = wizardStepOf(
        Reviewing(_plan(), const ['Not verified: timeout']),
        backend: 'file',
        pathOf: (_) => '/h/config.yaml',
      );

      expect(step.notes.first, 'Provider "anthropic"');
      expect(step.notes, contains('  Not verified: timeout'));
      expect(step.field!.prompt, '? Save? [Y/n] ');
      for (final yes in ['', 'y', 'YES']) {
        expect(
          (step.field!.submit(yes) as SendEvent).event,
          isA<ConfirmSave>(),
        );
      }
      expect((step.field!.submit('n') as SendEvent).event, isA<Cancel>());
      expect(step.field!.submit('?'), isA<Reask>());
      expect(step.failure, isNull);
    });

    test('отказ плана — failure с текстом', () {
      final step = wizardStepOf(
        Reviewing(
          _plan(),
          const [],
          error: 'A provider with this id already exists.',
          refusal: PlanRefusal.providerExists,
        ),
      );

      expect(step.failure, 'A provider with this id already exists.');
    });

    test('Saving блокирует Esc, Done и Cancelled — итоги', () {
      expect(wizardStepOf(Saving(_plan())).saving, isTrue);
      expect(
        wizardStepOf(
          Done(
            _plan(),
            const ProviderCommitted(
              saved: ConfigSaved(
                fingerprint: 'f',
                warnings: [],
                restartRequiredKeys: [],
              ),
              keyReplaced: false,
            ),
          ),
        ).savedProviderId,
        'anthropic',
      );
      expect(wizardStepOf(const Cancelled()).cancelled, isTrue);
    });

    test('savedProviderLine: с ключом — перезапуск, без — /model (R0-4)', () {
      expect(
        savedProviderLine('gw', hasKey: false),
        'Saved provider "gw". Models are available in /model.',
      );
      expect(
        savedProviderLine('gw', hasKey: true),
        'Saved provider "gw". Restart codelab to use its models.',
      );
      ProviderCommitted committed() => const ProviderCommitted(
        saved: ConfigSaved(
          fingerprint: 'f',
          warnings: [],
          restartRequiredKeys: [],
        ),
        keyReplaced: false,
      );
      for (final (key, expected) in [
        (const NoKey(), false),
        (const UseEnvVar('GW_KEY'), true),
        (const KeepStoredSecret(), true),
      ]) {
        expect(
          wizardStepOf(Done(_plan(key: key), committed())).savedHasKey,
          expected,
          reason: '$key',
        );
      }
    });

    test('тексты отказов записи без значений', () {
      expect(
        saveFailureText(
          const ProviderConfigNotSaved(
            outcome: ConfigConflict('/h/config.yaml'),
            errorType: null,
            keyReplaced: false,
            rollback: KeyRollback.none,
          ),
        ),
        'The config file changed; run the command again.',
      );
      expect(
        saveFailureText(
          const ProviderConfigNotSaved(
            outcome: null,
            errorType: 'FileSystemException',
            keyReplaced: false,
            rollback: KeyRollback.none,
          ),
        ),
        'Could not save the provider (FileSystemException).',
      );
    });

    test('SaveFailed: текст в notes и failure', () {
      final step = wizardStepOf(
        SaveFailed(
          _plan(),
          const ProviderConfigNotSaved(
            outcome: ConfigConflict('/h/config.yaml'),
            errorType: null,
            keyReplaced: false,
            rollback: KeyRollback.none,
          ),
        ),
      );

      expect(step.failure, 'The config file changed; run the command again.');
    });
  });
}
