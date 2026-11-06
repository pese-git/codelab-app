import 'dart:async';

import 'package:codelab_setup/codelab_setup.dart';

/// Фейки портов мастера провайдера (change `add-provider-setup-ui`, D7, D9).
///
/// Нет сети, часов и файлов: ответ проверки отдаёт тест, порядок вызовов
/// портов пишет один журнал.

/// Вызов [ProviderCheck.listModels].
final class CheckCall {
  CheckCall({
    required this.kind,
    required this.baseUrl,
    required this.key,
    required this.timeout,
    required this.cancel,
  });

  final String kind;
  final Uri baseUrl;

  /// Значение ключа, как его увидел порт (`null` — запрос без ключа).
  final String? key;
  final Duration timeout;
  final CancelToken? cancel;
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
    final call = CheckCall(
      kind: kind,
      baseUrl: baseUrl,
      key: key?.reveal(),
      timeout: timeout,
      cancel: cancel,
    );
    calls.add(call);
    return call.completer.future;
  }

  /// Отвечает на вызов номер [index] (по умолчанию — последний).
  void respond(ProviderCheckResult result, {int? index}) =>
      calls[index ?? calls.length - 1].completer.complete(result);
}

/// Порт ключей на памяти.
final class FakeProviderKeys implements ProviderKeys {
  FakeProviderKeys({
    this.backend = const SecretBackendInfo(id: 'file', writable: true),
    this.readOnlyHint,
    Set<String>? stored,
    Map<String, String>? values,
  }) : storedNames = {...?stored},
       values = {...?values};

  @override
  SecretBackendInfo backend;
  @override
  String? readOnlyHint;

  final Set<String> storedNames;
  final Map<String, String> values;

  /// Журнал вызовов: `stored <имя>`, `write <имя>`, `delete <имя>`, `read <имя>`.
  final journal = <String>[];

  /// Что записано (имя → значение): проверка записи ключа.
  final written = <String, String>{};

  /// Если задан, `stored` ждёт его завершения (ответ порта ещё не пришёл).
  Completer<void>? storedGate;

  /// Ответы `stored` по очереди; после исчерпания — по `storedNames`.
  final storedAnswers = <bool>[];

  ProviderKeyWrite Function(String name, SecretValue value)? onWrite;
  SecretDeletion deletion = SecretDeletion.deleted;

  /// Если задан, `delete` бросает его (сбой отката секрета).
  Object? throwOnDelete;

  @override
  Future<bool> stored(String name) async {
    journal.add('stored $name');
    if (storedGate case final gate?) {
      await gate.future;
    }
    if (storedAnswers.isNotEmpty) {
      return storedAnswers.removeAt(0);
    }
    return storedNames.contains(name);
  }

  @override
  Future<SecretValue?> read(String name) async {
    journal.add('read $name');
    final value = values[name];
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
    if (throwOnDelete case final error?) {
      throw error;
    }
    if (deletion == SecretDeletion.deleted) {
      storedNames.remove(name);
      written.remove(name);
    }
    return deletion;
  }
}

/// Порт конфига на памяти: `apply` пишет журнал и отдаёт заданный исход.
final class FakeConfigStore implements AgentConfigStore {
  FakeConfigStore(this.journal, {this.snapshotValue});

  final List<String> journal;
  AgentConfigSnapshot? snapshotValue;

  final applied = <({ConfigSnapshot base, List<ConfigEdit> edits})>[];
  ConfigSaveOutcome outcome = const ConfigSaved(
    fingerprint: 'fp-new',
    warnings: [],
    restartRequiredKeys: [],
  );

  /// Если задан, `apply` бросает его.
  Object? throwOnApply;

  @override
  Future<AgentConfigSnapshot> snapshot({required String cwd}) async =>
      snapshotValue!;

  @override
  Future<ConfigSaveOutcome> apply(
    ConfigSnapshot base,
    List<ConfigEdit> edits,
  ) async {
    journal.add('apply');
    applied.add((base: base, edits: edits));
    if (throwOnApply case final error?) {
      throw error;
    }
    return outcome;
  }
}

/// Снимок с пользовательским слоем [user] и, если задан, слоем [projectLocal].
AgentConfigSnapshot snapshotOf({
  Map<String, Object?> user = const {},
  Map<String, Object?>? projectLocal,
  SecretBackendInfo backend = const SecretBackendInfo(
    id: 'file',
    writable: true,
  ),
}) => AgentConfigSnapshot.fromLayers(
  cwd: '/work/project',
  layers: {
    ConfigLayer.user: ConfigSnapshot(
      target: const ConfigTarget.user(),
      path: '/h/config.yaml',
      fingerprint: 'fp-user',
      values: user,
    ),
    if (projectLocal != null)
      ConfigLayer.projectLocal: ConfigSnapshot(
        target: const ConfigTarget.projectLocal('/work/project'),
        path: '/work/project/.codelab/config.local.yaml',
        fingerprint: 'fp-local',
        values: projectLocal,
      ),
  },
  loaded: const ConfigLoadResult(),
  secrets: backend,
);
