import 'dart:async';

import 'package:codelab_desktop/features/protocol/application/log_record_source.dart';

/// Двойник порта [LogRecordSource] для тестов панели Protocol (design.md
/// change `redesign-protocol-pane`, D7, D8).
///
/// Для чего: тест добавляет записи через [add] и видит число `clear` в
/// [clearCalls]. Поток [changes] синхронный; [hasListener] показывает, что
/// подписку сняли при `close()` Cubit.
final class FakeLogRecordSource implements LogRecordSource {
  FakeLogRecordSource([Iterable<Map<String, Object?>> initial = const []])
    : _records = [...initial];

  final List<Map<String, Object?>> _records;
  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );
  int clearCalls = 0;

  @override
  List<Map<String, Object?>> get records => List.unmodifiable(_records);

  @override
  Stream<void> get changes => _changes.stream;

  bool get hasListener => _changes.hasListener;

  @override
  void clear() {
    clearCalls++;
    _records.clear();
    _changes.add(null);
  }

  void add(Map<String, Object?> record) {
    _records.add(record);
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}
