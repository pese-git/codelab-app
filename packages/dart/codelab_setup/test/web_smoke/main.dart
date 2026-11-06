// Точка входа web-smoke: `melos run web-compile` компилирует её в JS и Wasm и
// так доказывает, что основной барель моста настроек остаётся web-безопасным
// (без dart:io, dart:isolate, package:codelab_agent_io и
// package:http/io_client.dart). На Dart VM тот же код проверяет
// `web_smoke_test.dart` (design.md change `add-provider-setup-ui`, D20).
import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show LogLevel, Logger;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:http/http.dart' as http;

/// Итог web-smoke: что построил основной барель без файлов и сети.
final class SetupWebSmokeReport {
  const SetupWebSmokeReport({
    required this.access,
    required this.models,
    required this.entries,
    required this.removal,
    required this.wizard,
    required this.settings,
  });

  final String access;
  final List<String> models;
  final List<String> entries;
  final String removal;

  /// Правки плана мастера, прошедшего от пресета до обзора.
  final List<String> wizard;

  /// Строки `/settings` снимка: `ключ:источник` для заданных ключей и число
  /// строк реестра `shared`; проверяет реэкспорт `SettingsRegistry` и др.
  final List<String> settings;
}

/// Клиент, который отвечает списком моделей без сети.
final class _FakeModelsClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(
          utf8.encode('{"data":[{"id":"m","context_length":4096}]}'),
        ),
        200,
      );
}

/// Хранилище конфига в памяти: записывает правки и отвечает `ConfigSaved`.
final class _MemoryStore implements AgentConfigStore {
  final applied = <List<ConfigEdit>>[];

  @override
  Future<ConfigSaveOutcome> apply(
    ConfigSnapshot base,
    List<ConfigEdit> edits,
  ) async {
    applied.add(edits);
    return const ConfigSaved(
      fingerprint: 'fp',
      warnings: [],
      restartRequiredKeys: [],
    );
  }

  @override
  Future<AgentConfigSnapshot> snapshot({required String cwd}) =>
      throw UnimplementedError('smoke работает по готовому снимку');
}

/// Журнал, который молчит: smoke не проверяет записи.
final class _SilentLogger implements Logger {
  const _SilentLogger();

  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}

/// Порт ключей в памяти: бэкенд только для чтения, секретов нет.
final class _NoKeys implements ProviderKeys {
  @override
  SecretBackendInfo get backend =>
      const SecretBackendInfo(id: 'env', writable: false);

  @override
  String? get readOnlyHint => 'read-only';

  @override
  Future<bool> stored(String name) async => false;

  @override
  Future<SecretValue?> read(String name) async => null;

  @override
  Future<ProviderKeyWrite> write(String name, SecretValue value) async =>
      const ProviderKeyRefused('read-only');

  @override
  Future<SecretDeletion> delete(String name) async => SecretDeletion.notSet;
}

/// Прогоняет мастер провайдера от пресета до обзора на портах в памяти.
Future<List<String>> _runWizard(AgentConfigSnapshot snapshot) async {
  final keys = _NoKeys();
  final store = _MemoryStore();
  final flow = ProviderSetupFlow(
    check: HttpProviderCheck(_FakeModelsClient.new),
    committer: ProviderSetupCommitter(config: store, keys: keys),
    keys: keys,
    snapshot: snapshot,
    access: const EditableSettings(ConfigPaths(codelabHome: '/home')),
    environment: const {},
    isLocalHost: (host) => host == 'localhost',
    logger: const _SilentLogger(),
    entry: ProviderWizardEntry.app,
  );
  // Подписка раньше, чем автомат дойдёт до нужного состояния.
  flow
    ..dispatch(const PresetChosen('openrouter'))
    ..dispatch(const BaseUrlSubmitted('https://openrouter.ai/api/v1'));
  await flow.states.firstWhere((s) => s is ChoosingKey && s.ready);
  flow.dispatch(const KeySubmitted(NoKey()));
  await flow.states.firstWhere((s) => s is ChoosingModel);
  flow.dispatch(const ModelChosen('m'));
  final edits = [
    for (final edit in (flow.current as Reviewing).plan.toEdits())
      edit.toString(),
  ];
  await flow.dispose();
  return edits;
}

/// Строки `/settings` и символы реестра, реэкспортированные мостом.
List<String> _settingRows(AgentConfigSnapshot snapshot) {
  final rows = settingFieldsOf(snapshot);
  final kind = SettingsRegistry.lookup('providers.a.kind')!;
  Object? parsed;
  try {
    SettingsRegistry.parseCliValue(
      SettingsRegistry.lookup('budget.max_steps')!,
      'x',
    );
  } on ConfigValueException catch (e) {
    parsed = e.expected;
  }
  return [
    for (final r in rows)
      if (r.source != null) '${r.key}:${r.sourceName}',
    'type:${kind.type == SettingType.enumeration}',
    'scope:${kind.scope == SettingScope.shared}',
    'bad:${parsed != null}',
  ];
}

/// Прогоняет доступ, проверку `/models`, список провайдеров и удаление.
Future<SetupWebSmokeReport> runSetupWebSmoke() async {
  final access = resolveSettingsAccess(
    kind: AgentLaunchKind.embedded,
    cwd: '/web',
    defaultCodelabHome: '/home',
  );
  final check = HttpProviderCheck(_FakeModelsClient.new);
  final result = await check.listModels(
    'openai-compatible',
    Uri.parse('https://smoke.invalid/v1'),
    SecretValue('smoke'),
  );
  final snapshot = AgentConfigSnapshot.fromLayers(
    cwd: '/web',
    layers: {
      ConfigLayer.user: ConfigSnapshot(
        target: const ConfigTarget.user(),
        path: '/home/config.yaml',
        fingerprint: 'f',
        values: {
          'providers': {
            'a': {'kind': 'openai-compatible', 'api_key_env': 'SMOKE_KEY'},
            'b': {'kind': 'anthropic'},
          },
        },
      ),
    },
    loaded: const ConfigLoadResult(),
    secrets: const SecretBackendInfo(id: 'env', writable: false),
  );
  final entries = await providerEntriesOf(
    snapshot,
    environment: const {},
    isSecretSet: (_) async => false,
  );
  final store = _MemoryStore();
  final removal = await ProviderRemover(
    config: store,
    deleteSecret: (_) async => SecretDeletion.notSet,
  ).remove(snapshot, providerId: 'b');
  return SetupWebSmokeReport(
    access: access.runtimeType.toString(),
    models: [
      if (result case CheckOk(:final models)) ...models.map((m) => m.id),
    ],
    entries: [for (final entry in entries) '${entry.id}:${entry.key.label}'],
    removal: removal.runtimeType.toString(),
    wizard: await _runWizard(snapshot),
    settings: _settingRows(snapshot),
  );
}

Future<void> main() async {
  final report = await runSetupWebSmoke();
  // ignore: avoid_print
  print(
    'setup web smoke: ${report.access} ${report.models} ${report.entries} '
    '${report.removal}',
  );
}
