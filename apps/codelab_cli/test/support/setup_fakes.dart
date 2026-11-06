import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart' show isLocalHost;
import 'package:codelab_embedded/codelab_embedded.dart' show LogLevel, Logger;
import 'package:codelab_setup/codelab_setup.dart';

/// Фейки портов мастера провайдера для модульных тестов CLI (change
/// `add-provider-setup-ui`, D7, D9, D15–D17).
///
/// Почему свои: фейки `codelab_setup/test/support` лежат в тестах другого
/// пакета и CLI их не видит; мастеру CLI нужны те же порты, но без сети,
/// часов и файлов. Ответ проверки `/models` отдаёт тест, порядок вызовов
/// портов пишут сами фейки.
///
/// Как использовать: [buildWizardFlow] собирает настоящий
/// `ProviderSetupFlow` на этих портах; тест подаёт клавиши терминалу и
/// читает [FakeConfigStore.applied], [FakeProviderKeys.written] и
/// [FakeProviderCheck.calls].

/// Маркер утечки секрета: ни один вывод и ни один файл не должен его
/// содержать (design.md change `add-provider-setup-ui`, D22).
const leakMarker = 'sk-test-leak-0123456789';

/// Байты клавиш, которые терминал присылает в raw-режиме.
const keyEnter = [0x0d];
const keyDown = [0x1b, 0x5b, 0x42];
const keyUp = [0x1b, 0x5b, 0x41];
const keyEsc = [0x1b];
const keyCtrlC = [0x03];
const keyCtrlR = [0x12];
const keyCtrlU = [0x15];

/// Логгер, который запоминает записи.
final class RecordingLogger implements Logger {
  final records =
      <({LogLevel level, String event, Map<String, Object?> fields})>[];

  @override
  bool isEnabled(LogLevel level) => true;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) => records.add((level: level, event: event, fields: fields));

  /// Поля первой записи [event] или `null`.
  Map<String, Object?>? fieldsOf(String event) =>
      records.where((r) => r.event == event).firstOrNull?.fields;
}

/// Вызов [ProviderCheck.listModels].
final class CheckCall {
  CheckCall({required this.kind, required this.baseUrl, required this.key});

  final String kind;
  final Uri baseUrl;

  /// Значение ключа, как его увидел порт (`null` — запрос без ключа).
  final String? key;
  final completer = Completer<ProviderCheckResult>();
}

/// Проверка: каждый вызов ждёт ответа теста ([respond]).
final class FakeProviderCheck implements ProviderCheck {
  final calls = <CheckCall>[];

  @override
  Future<ProviderCheckResult> listModels(
    String kind,
    Uri baseUrl,
    SecretValue? key, {
    Duration timeout = defaultProviderCheckTimeout,
    CancelToken? cancel,
  }) {
    final call = CheckCall(kind: kind, baseUrl: baseUrl, key: key?.reveal());
    calls.add(call);
    return call.completer.future;
  }

  /// Отвечает на последний вызов.
  void respond(ProviderCheckResult result) =>
      calls.last.completer.complete(result);
}

/// Порт ключей на памяти.
final class FakeProviderKeys implements ProviderKeys {
  FakeProviderKeys({
    this.backend = const SecretBackendInfo(id: 'file', writable: true),
    this.readOnlyHint,
    Set<String>? stored,
  }) : storedNames = {...?stored};

  @override
  SecretBackendInfo backend;

  @override
  String? readOnlyHint;

  final Set<String> storedNames;

  /// Записанные секреты (имя -> значение).
  final written = <String, String>{};

  /// Журнал вызовов: `stored <имя>`, `write <имя>`, `delete <имя>`.
  final journal = <String>[];

  /// Что вернёт `write`; по умолчанию создание.
  ProviderKeyWrite Function(String name, SecretValue value)? onWrite;

  @override
  Future<bool> stored(String name) async {
    journal.add('stored $name');
    return storedNames.contains(name);
  }

  @override
  Future<SecretValue?> read(String name) async {
    journal.add('read $name');
    final value = written[name];
    return value == null ? null : SecretValue(value);
  }

  @override
  Future<ProviderKeyWrite> write(String name, SecretValue value) async {
    journal.add('write $name');
    if (onWrite case final handler?) {
      return handler(name, value);
    }
    final existed = storedNames.contains(name);
    storedNames.add(name);
    written[name] = value.reveal();
    return existed ? const ProviderKeyReplaced() : const ProviderKeyCreated();
  }

  @override
  Future<SecretDeletion> delete(String name) async {
    journal.add('delete $name');
    storedNames.remove(name);
    written.remove(name);
    return SecretDeletion.deleted;
  }
}

/// Порт конфига на памяти: `apply` пишет в [applied] и отдаёт [outcome].
final class FakeConfigStore implements AgentConfigStore {
  FakeConfigStore({required this.snapshotValue});

  AgentConfigSnapshot snapshotValue;

  final applied = <({ConfigSnapshot base, List<ConfigEdit> edits})>[];

  /// Если задан, `apply` ждёт его завершения: запись «в полёте», мастер в
  /// состоянии `Saving`.
  Completer<void>? applyGate;

  /// Исход записи; `null` — `ConfigSaved`, где `restartRequiredKeys`
  /// содержит ключи правок, у которых дескриптор требует перезапуска.
  ConfigSaveOutcome? outcome;

  @override
  Future<AgentConfigSnapshot> snapshot({required String cwd}) async =>
      snapshotValue;

  @override
  Future<ConfigSaveOutcome> apply(
    ConfigSnapshot base,
    List<ConfigEdit> edits,
  ) async {
    applied.add((base: base, edits: edits));
    if (applyGate case final gate?) {
      await gate.future;
    }
    return outcome ??
        ConfigSaved(
          fingerprint: 'fp-new',
          warnings: const [],
          restartRequiredKeys: [
            for (final edit in edits)
              if (edit case SetValue(:final key) || UnsetValue(:final key))
                if (SettingsRegistry.lookup(key)?.restartRequired ?? false) key,
          ],
        );
  }
}

/// Снимок с пользовательским слоем [user] (путь `/h/config.yaml`) и, если
/// задан, слоем [projectLocal] (`<cwd>/.codelab/config.local.yaml`).
///
/// [values] — итоговые значения (`ConfigLoadResult.values`), [external] —
/// источники `config` и `env` по ключам (`--config`, окружение).
AgentConfigSnapshot snapshotOf({
  String cwd = '/work',
  Map<String, Object?> user = const {},
  Map<String, Object?>? projectLocal,
  Map<String, Object?>? project,
  Map<String, Object?> values = const {},
  Map<String, ConfigSourceKind> external = const {},
  SecretBackendInfo backend = const SecretBackendInfo(
    id: 'file',
    writable: true,
  ),
}) => AgentConfigSnapshot.fromLayers(
  cwd: cwd,
  layers: {
    ConfigLayer.user: ConfigSnapshot(
      target: const ConfigTarget.user(),
      path: '/h/config.yaml',
      fingerprint: 'fp-user',
      values: user,
    ),
    if (project != null)
      ConfigLayer.project: ConfigSnapshot(
        target: ConfigTarget.project(cwd),
        path: '$cwd/.codelab/config.yaml',
        fingerprint: 'fp-project',
        values: project,
      ),
    if (projectLocal != null)
      ConfigLayer.projectLocal: ConfigSnapshot(
        target: ConfigTarget.projectLocal(cwd),
        path: '$cwd/.codelab/config.local.yaml',
        fingerprint: 'fp-local',
        values: projectLocal,
      ),
  },
  loaded: ConfigLoadResult(values: values),
  secrets: backend,
  externalOrigin: (key) => switch (external[key]) {
    ConfigSourceKind.environment => const ConfigSourceView(
      kind: ConfigSourceKind.environment,
      label: 'env',
    ),
    ConfigSourceKind.extraFile => const ConfigSourceView(
      kind: ConfigSourceKind.extraFile,
      label: '/x/extra.yaml',
    ),
    _ => null,
  },
);

/// Настоящий `ProviderSetupFlow` на фейках: адрес `isLocalHost` — функция
/// kit (design.md change `add-provider-setup-ui`, D8; задача 4.0).
ProviderSetupFlow buildWizardFlow({
  required FakeProviderCheck check,
  required FakeProviderKeys keys,
  required FakeConfigStore config,
  RecordingLogger? logger,
  ProviderWizardEntry entry = ProviderWizardEntry.cli,
  bool forceDefault = false,
  String cwd = '/work',
}) => ProviderSetupFlow(
  check: check,
  committer: ProviderSetupCommitter(config: config, keys: keys),
  keys: keys,
  snapshot: config.snapshotValue,
  access: EditableSettings(ConfigPaths(codelabHome: '/h', projectDir: cwd)),
  environment: const {},
  isLocalHost: isLocalHost,
  logger: logger ?? RecordingLogger(),
  forceDefault: forceDefault,
  entry: entry,
);

/// Ответ `/models` с моделями [ids], у каждой известно окно контекста.
CheckOk modelsOk(List<String> ids, {int contextWindow = 8000}) => CheckOk([
  for (final id in ids) RemoteModel(id, contextWindow: contextWindow),
]);
