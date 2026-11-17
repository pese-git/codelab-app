import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Подставное [DescribedSecretStore] для тестов ядра: считает обращения,
/// умеет зависать до сигнала и отказывать как недоступное хранилище
/// (design.md change `add-agent-secret-store`, D12).
///
/// Как использовать: [values] — содержимое; [gate] — пока он не завершён,
/// `read` ждёт (проверка single-flight и отмены); [failWith] — `read` бросает
/// его. [reads] хранит имена по порядку вызовов.
final class FakeSecretStore implements DescribedSecretStore {
  FakeSecretStore({
    Map<String, String> values = const {},
    this.id = 'fake',
    this.writable = true,
    this.failWith,
    this.gate,
  }) : values = {...values};

  final String id;
  final bool writable;
  final Map<String, String> values;

  /// Если задан, `read` бросает его (после [gate]).
  Object? failWith;

  /// Если задан, `read` ждёт его завершения.
  Completer<void>? gate;

  final reads = <String>[];

  @override
  SecretBackendInfo get backend =>
      SecretBackendInfo(id: id, writable: writable);

  @override
  Future<String?> read(String name) async {
    reads.add(name);
    if (gate case final gate?) {
      await gate.future;
    }
    if (failWith case final error?) {
      throw error;
    }
    return values[name];
  }

  @override
  Future<void> write(String name, String value) async => values[name] = value;

  @override
  Future<void> delete(String name) async => values.remove(name);

  @override
  Future<List<String>> names() async => values.keys.toList()..sort();
}
