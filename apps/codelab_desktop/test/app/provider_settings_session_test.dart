// Адаптер Check страницы «Providers» (задача 2.6 change
// `add-provider-setup-ui`; D4, SETUP-1): ключ читается в `lib/app/` и сразу
// уходит `ProviderCheck`; наружу значение не возвращается.
//
// Секрет приходит через `CODELAB_SECRET_*` (переменная побеждает бэкенд, как у
// резолвера агента), поэтому файлов секретов в тесте нет; `CODELAB_HOME` —
// временная папка.

import 'dart:io';

import 'package:codelab_desktop/app/provider_settings_session.dart';
import 'package:codelab_desktop/features/settings/application/provider_settings_session.dart';
import 'package:codelab_desktop/features/settings/application/provider_wizard_cubit.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart' as setup;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_provider_settings.dart';
import '../support/real_config_session.dart' show realHomeConfig;

final class _CapturingCheck implements ProviderCheck {
  final seen = <SecretValue?>[];
  final tokens = <CancelToken?>[];

  @override
  Future<ProviderCheckResult> listModels(
    String kind,
    Uri baseUrl,
    SecretValue? key, {
    Duration timeout = defaultProviderCheckTimeout,
    CancelToken? cancel,
  }) async {
    seen.add(key);
    tokens.add(cancel);
    return const CheckOk([RemoteModel('m')]);
  }
}

void main() {
  late Directory home;
  late _CapturingCheck check;

  setUp(() {
    home = Directory.systemTemp.createTempSync('codelab_providers_');
    addTearDown(() => home.deleteSync(recursive: true));
    check = _CapturingCheck();
  });

  Future<ProviderSettingsSession> open(
    Map<String, String> env, {
    ProviderCheck? useCheck,
  }) async {
    final environment = {'CODELAB_HOME': home.path, ...env};
    return openProviderSettingsSession(
      EditableSettings(ConfigPaths(codelabHome: home.path)),
      environment,
      check: useCheck ?? check,
      logger: const _Silent(),
    );
  }

  test('hands a stored key straight to the check', () async {
    final session = await open({
      SecretNames.envOverride('codelab/anthropic'): leakMarker,
    });

    final result = await session.checkProvider(
      kind: 'anthropic',
      baseUrl: Uri.parse('https://api.anthropic.com'),
      key: const KeyInSecretStore(name: 'codelab/anthropic', backendId: 'env'),
    );

    expect(result, isA<CheckOk>());
    expect(check.seen.single?.reveal(), leakMarker);
    expect(check.seen.single.toString(), isNot(contains(leakMarker)));
    expect(result.toString(), isNot(contains(leakMarker)));
  });

  test(
    'hands an environment key to the check and nothing for no key',
    () async {
      final session = await open({'OPENAI_API_KEY': leakMarker});

      await session.checkProvider(
        kind: 'openai-compatible',
        baseUrl: Uri.parse('https://h/v1'),
        key: const KeyFromEnv(name: 'OPENAI_API_KEY', isSet: true),
      );
      await session.checkProvider(
        kind: 'openai-compatible',
        baseUrl: Uri.parse('https://h/v1'),
        key: const KeyNone(),
      );

      expect(check.seen.first?.reveal(), leakMarker);
      expect(check.seen.last, isNull);
    },
  );

  test('passes the cancel token to the check', () async {
    final session = await open({});
    final source = CancelTokenSource();

    await session.checkProvider(
      kind: 'openai-compatible',
      baseUrl: Uri.parse('https://h/v1'),
      key: const KeyNone(),
      cancel: source.token,
    );

    expect(check.tokens.single, same(source.token));
  });

  test('isSecretSet answers without reading the value', () async {
    final session = await open({
      SecretNames.envOverride('codelab/anthropic'): leakMarker,
    });

    expect(await session.isSecretSet('codelab/anthropic'), isTrue);
    expect(await session.isSecretSet('codelab/other'), isFalse);
    expect(session.backend.id, 'env');
  });

  // Задача 5.4 change `add-provider-setup-ui` (design.md D11 «Сверка с кодом
  // перед итерацией 5b»; задача 5.10): порты записи страницы «MCP servers»
  // собраны на `providerKeysOf` того же хранилища, что и `isSecretSet`.
  test('mcpCommitter and mcpRemover work on the secret store that '
      'isSecretSet reads', () async {
    const name = 'codelab/mcp/github/authorization';
    Process.runSync('/bin/chmod', ['700', home.path]);
    File('${home.path}/config.yaml').writeAsStringSync('''
secrets:
  backend: file
agent:
  default_model: gw/m
providers:
  gw:
    kind: openai-compatible
    base_url: https://gw.test/v1
    models:
      m:
        context_window: 8000
''');
    final session = await open({'HOME': home.path});
    expect(session.backend.id, 'file');
    final snapshot = await session.config.snapshot(cwd: home.path);
    final draft = McpServerDraft(
      name: 'github',
      kind: McpTransportKind.http,
      url: 'https://mcp.test/mcp',
      headers: {
        'Authorization': McpValueDraft.secret(
          SecretValue('Bearer $leakMarker'),
        ),
      },
    );

    final saved = await session.mcpCommitter().commit(
      draft,
      snapshot.layers[ConfigLayer.user]!,
      cwd: home.path,
    );

    expect(saved, isA<McpServerCommitted>());
    expect(await session.isSecretSet(name), isTrue);
    final text = File('${home.path}/config.yaml').readAsStringSync();
    expect(text, contains('\${secret:$name}'));
    expect(text, isNot(contains(leakMarker)));

    final fresh = await session.config.snapshot(cwd: home.path);
    final removed = await session.mcpRemover().remove(fresh, name: 'github');

    expect(removed, isA<McpServerRemoved>());
    expect((removed as McpServerRemoved).secrets, {
      name: SecretCleanup.deleted,
    });
    expect(await session.isSecretSet(name), isFalse);
  });

  // Ревью 6a, Q35: подсказка «Restart agent» после мастера на настоящей
  // IO-сессии и настоящем `CODELAB_HOME`. Снимок «до» берёт Cubit мастера
  // (он же читает свежий после записи), правило даёт мост. Хранилище
  // секретов — по умолчанию (`env`, только чтение; хранилищ ОС в этой версии
  // нет), ключ провайдера берётся из переменной окружения теста.
  group('the Restart agent hint on the IO session (Q35)', () {
    const env = {'LLM_KEY': 'value-from-env'};

    Future<void> until(bool Function() ok) async {
      for (var i = 0; i < 300 && !ok(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(ok(), isTrue);
    }

    Future<ProviderWizardCubit> wizard(
      ProviderSettingsSession session, {
      ProviderEntryView? editing,
    }) async {
      final access = EditableSettings(ConfigPaths(codelabHome: home.path));
      final before = await session.config.snapshot(cwd: home.path);
      final flow = await session.openWizard(editing: editing);
      return ProviderWizardCubit(
        flow: flow,
        access: access,
        backendId: session.backend.id,
        editingId: editing?.id,
        isAgentConnected: () => true,
        before: before,
        readSnapshot: () => session.config.snapshot(cwd: home.path),
      );
    }

    Future<void> walk(ProviderWizardCubit cubit, String model) async {
      await until(() => cubit.state.setup is EnteringBaseUrl);
      cubit.dispatch(const BaseUrlSubmitted('https://llm.example/v1'));
      await until(() => cubit.state.setup is ChoosingKey);
      cubit.dispatch(const KeySubmitted(UseEnvVar('LLM_KEY')));
      await until(() => cubit.state.setup is ChoosingModel);
      cubit.dispatch(ModelChosen(model));
      await until(() => cubit.state.setup is Reviewing);
      cubit.dispatch(const ConfirmSave());
      await until(() => cubit.state.setup is Done);
    }

    test('a new provider with a key points to Restart agent; editing its '
        'models with the same key does not', () async {
      // Нужен загружаемый конфиг «до»: из пустого дома `loaded.config` нет и
      // мост ничего не называет.
      File('${home.path}/config.yaml').writeAsStringSync(realHomeConfig);
      final models = _ModelsCheck();
      final session = await open(env, useCheck: models);

      final add = await wizard(session);
      add.dispatch(const PresetChosen('custom-openai'));
      await walk(add, 'm1');
      expect(
        add.savedBanner!.text,
        'Provider llm-example saved. Its models are available after Restart '
        'agent (Settings › Connection).',
      );
      await add.close();

      final snapshot = await session.config.snapshot(cwd: home.path);
      final entry = (await providerEntriesOf(
        snapshot,
        environment: {...env},
        isSecretSet: session.isSecretSet,
      )).firstWhere((e) => e.id == 'llm-example');
      models.names = ['m1', 'm2'];
      final edit = await wizard(session, editing: entry);
      await walk(edit, 'm2');
      expect(edit.savedBanner!.text, 'Provider llm-example saved.');
      await edit.close();
    });
  });
}

/// Проверка `/models` с окном контекста: мастер не спрашивает его отдельно.
final class _ModelsCheck implements ProviderCheck {
  List<String> names = ['m1'];

  @override
  Future<ProviderCheckResult> listModels(
    String kind,
    Uri baseUrl,
    SecretValue? key, {
    Duration timeout = defaultProviderCheckTimeout,
    CancelToken? cancel,
  }) async => CheckOk([
    for (final name in names) RemoteModel(name, contextWindow: 8000),
  ]);
}

final class _Silent implements setup.Logger {
  const _Silent();

  @override
  bool isEnabled(setup.LogLevel level) => false;

  @override
  void log(
    setup.LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}
