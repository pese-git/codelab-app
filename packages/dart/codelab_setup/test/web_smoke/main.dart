// Точка входа web-smoke: `melos run web-compile` компилирует её в JS и Wasm и
// так доказывает, что основной барель моста настроек остаётся web-безопасным
// (без dart:io, dart:isolate, package:codelab_agent_io и
// package:http/io_client.dart). На Dart VM тот же код проверяет
// `web_smoke_test.dart` (design.md change `add-provider-setup-ui`, D20).
import 'dart:convert';

import 'package:codelab_setup/codelab_setup.dart';
import 'package:http/http.dart' as http;

/// Итог web-smoke: что построил основной барель без файлов и сети.
final class SetupWebSmokeReport {
  const SetupWebSmokeReport({
    required this.access,
    required this.models,
    required this.entries,
    required this.removal,
  });

  final String access;
  final List<String> models;
  final List<String> entries;
  final String removal;
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
