// Двойники мастера провайдера для app-тестов (change `add-provider-setup-ui`,
// D7, D9).
//
// Почему двойники: порядок записи ключа и конфига, автомат и тексты отказов
// проверяет мост `codelab_setup` (задачи 3.1, 3.2); тесты app проверяют, что
// Cubit и диалог показывают состояния автомата и посылают ему события. Сети,
// часов и файлов здесь нет.

import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart' show isLocalHost;
import 'package:codelab_desktop/app/embedded_logger.dart';
import 'package:codelab_setup/codelab_setup.dart';

import 'recording_logger.dart';

/// Вызов [ProviderCheck.listModels].
final class WizardCheckCall {
  WizardCheckCall({
    required this.kind,
    required this.baseUrl,
    required this.key,
    required this.cancel,
  });

  final String kind;
  final Uri baseUrl;

  /// Значение ключа, как его увидел порт (`null` — запрос без ключа).
  final String? key;
  final CancelToken? cancel;
  final completer = Completer<ProviderCheckResult>();
}

/// Проверка: каждый вызов ждёт ответа теста ([respond]).
final class FakeWizardCheck implements ProviderCheck {
  final calls = <WizardCheckCall>[];

  @override
  Future<ProviderCheckResult> listModels(
    String kind,
    Uri baseUrl,
    SecretValue? key, {
    Duration timeout = defaultProviderCheckTimeout,
    CancelToken? cancel,
  }) {
    final call = WizardCheckCall(
      kind: kind,
      baseUrl: baseUrl,
      key: key?.reveal(),
      cancel: cancel,
    );
    calls.add(call);
    return call.completer.future;
  }

  /// Отвечает на последний вызов.
  void respond(ProviderCheckResult result) =>
      calls.last.completer.complete(result);
}

/// Порт ключей поверх карты секретов сессии-двойника.
final class FakeWizardKeys implements ProviderKeys {
  FakeWizardKeys(
    this.secrets, {
    this.backend = const SecretBackendInfo(id: 'file', writable: true),
    this.readOnlyHint,
  });

  /// Хранилище секретов двойника: значения видны только этому порту.
  final Map<String, String> secrets;

  @override
  SecretBackendInfo backend;
  @override
  String? readOnlyHint;

  final journal = <String>[];

  /// Исключение, которое бросает [stored] (хранилище недоступно; ревью 5b).
  Object? storedError;

  /// Ожидание внутри [stored]: тест успевает сменить подключение посреди
  /// «Save» (ревью 5b, LOW-4).
  Future<void> Function()? onStored;

  /// Имена, которые первый вызов [stored] скрывает, хотя секрет уже есть:
  /// гонка «секрет появился после вопроса» (`McpSecretAppeared`).
  final hideFirstStored = <String>{};

  /// Ожидание внутри [write] (смена подключения посреди записи, ревью 6a).
  Future<void> Function()? onWrite;

  /// Исход удаления секрета (страница «MCP servers», задача 5.4: `failed` —
  /// баннер с `codelab secret delete <имя>`).
  SecretDeletion deletion = SecretDeletion.deleted;

  /// Причина отказа записи секрета (`McpSecretNotStored`); `null` — пишет.
  String? refusal;

  /// Если задано, отказ [refusal] касается только этого имени, остальные
  /// записи проходят (частичная запись нескольких секретов, ревью 5b).
  String? refuseOnly;

  @override
  Future<bool> stored(String name) async {
    journal.add('stored $name');
    await onStored?.call();
    if (storedError case final error?) {
      throw error;
    }
    if (hideFirstStored.remove(name)) {
      return false;
    }
    return secrets.containsKey(name);
  }

  @override
  Future<SecretValue?> read(String name) async {
    journal.add('read $name');
    final value = secrets[name];
    return value == null ? null : SecretValue(value);
  }

  @override
  Future<ProviderKeyWrite> write(String name, SecretValue value) async {
    journal.add('write $name');
    await onWrite?.call();
    if (refusal case final reason?
        when refuseOnly == null || refuseOnly == name) {
      return ProviderKeyRefused(reason);
    }
    final existed = secrets.containsKey(name);
    secrets[name] = value.reveal();
    return existed ? const ProviderKeyReplaced() : const ProviderKeyCreated();
  }

  @override
  Future<SecretDeletion> delete(String name) async {
    journal.add('delete $name');
    if (deletion != SecretDeletion.failed) {
      secrets.remove(name);
    }
    return deletion;
  }
}

/// Автомат поверх двойников: тот же набор портов, что собирает composition
/// root, но без файлов и сети.
Future<ProviderSetupFlow> buildWizardFlow({
  required AgentConfigStore store,
  required FakeWizardKeys keys,
  required FakeWizardCheck check,
  required EditableSettings access,
  required RecordingLogger log,
  Map<String, String> environment = const {},
  ProviderEntryView? editing,
  bool forceDefault = false,
  ProviderWizardEntry entry = ProviderWizardEntry.app,
}) async {
  final snapshot = await store.snapshot(cwd: access.cwd ?? '/home/u/.codelab');
  return ProviderSetupFlow(
    check: check,
    committer: ProviderSetupCommitter(config: store, keys: keys),
    keys: keys,
    snapshot: snapshot,
    access: access,
    environment: environment,
    isLocalHost: isLocalHost,
    logger: CodeLabEmbeddedLogger(logger: log),
    editing: editing,
    forceDefault: forceDefault,
    entry: entry,
  );
}
