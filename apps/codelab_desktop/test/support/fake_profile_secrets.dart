import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart';

/// [ProfileSecrets] в памяти для тестов диалога и страницы «Connection»
/// (change `add-provider-setup-ui`, D13, D14).
///
/// Почему свой двойник, а не из тестов kit: тесты app не импортируют
/// `test/` соседнего пакета. Для чего: `values` — то, что лежит в
/// «хранилище»; `calls` — порядок обращений; `storeGate` держит запись
/// посреди операции (состояние `Saving`); `nextWrite` и `nextDelete` подменяют
/// исход.
///
/// Как использовать: `FakeProfileSecrets(values: {'codelab/ws-ci': 'x'})`;
/// только для чтения — `backend: const ProfileSecretBackend(id: 'env',
/// writable: false, unavailableReason: '…')`.
final class FakeProfileSecrets implements ProfileSecrets {
  FakeProfileSecrets({
    Map<String, String>? values,
    this.backend = const ProfileSecretBackend(id: 'file', writable: true),
  }) : values = {...?values};

  final Map<String, String> values;

  /// Обращения вида `store:<имя>`, `delete:<имя>`, `isSet:<имя>`, `read:<имя>`.
  final calls = <String>[];

  @override
  ProfileSecretBackend backend;

  /// Если задано, `store` ждёт его, прежде чем что-либо записать.
  Completer<void>? storeGate;

  /// Подменяет исход `store`; `null` — обычное поведение.
  ProfileSecretWrite? nextWrite;

  /// Подменяет исход `delete`; `null` — обычное поведение.
  ProfileSecretDelete? nextDelete;

  /// Если задано, `names` бросает это (бэкенд не читается).
  Object? namesFailure;

  /// Если задано, `isSet` бросает это.
  Object? isSetFailure;

  @override
  Future<List<String>> names() async {
    if (namesFailure case final error?) {
      throw error;
    }
    return values.keys.toList()..sort();
  }

  @override
  Future<bool> isSet(String name) async {
    calls.add('isSet:$name');
    if (isSetFailure case final error?) {
      throw error;
    }
    return values.containsKey(name);
  }

  @override
  Future<String?> read(String name) async {
    calls.add('read:$name');
    return values[name];
  }

  @override
  Future<ProfileSecretWrite> store(String name, SecretText value) async {
    calls.add('store:$name');
    final gate = storeGate;
    if (gate != null) {
      await gate.future;
    }
    if (nextWrite case final forced?) {
      return forced;
    }
    if (values.containsKey(name)) {
      return const Exists();
    }
    values[name] = value.reveal();
    return const Stored();
  }

  @override
  Future<ProfileSecretDelete> delete(String name) async {
    calls.add('delete:$name');
    if (nextDelete case final forced?) {
      return forced;
    }
    return values.remove(name) == null ? const NotSet() : const Deleted();
  }
}
