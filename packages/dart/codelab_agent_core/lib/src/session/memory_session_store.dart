import 'dart:convert';

import '../loop/agent_events.dart';
import '../util/logger.dart';
import 'parse.dart';
import 'records.dart';
import 'session_store.dart';
import 'summary.dart';

/// Журналы в памяти процесса (`agent-core-architecture` §8.3).
///
/// Почему не просто список записей: хранилище держит журнал текстом JSONL,
/// как файл, и открывает его тем же разбором и ремонтом. Поэтому оно
/// проходит тот же контрактный набор, что `JsonlSessionStore`, а тесты
/// могут подложить «журнал после сбоя» ([putText]) и сравнить байты
/// ([textOf]).
///
/// Для чего: тесты ядра и хосты без постоянного носителя — тогда capability
/// `sessionPersistence` выключена (design.md, D12).
final class MemorySessionStore implements SessionStore {
  MemorySessionStore({this.logger});

  final Logger? logger;
  final _texts = <SessionId, String>{};
  final _corrupt = <SessionId, String>{};

  /// Текст журнала, как был бы в файле; `null` — журнала нет.
  String? textOf(SessionId id) => _texts[id];

  /// Строки карантина (`.corrupt`); `null` — карантина не было.
  String? corruptOf(SessionId id) => _corrupt[id];

  /// Подкладывает журнал как есть — например, оборванный при сбое.
  void putText(SessionId id, String text) => _texts[id] = text;

  @override
  Future<void> create(SessionHeader header) async {
    if (_texts.containsKey(header.id)) {
      throw StateError('session ${header.id.value} already exists');
    }
    _texts[header.id] = '${jsonEncode(header.toJson())}\n';
  }

  @override
  Future<void> append(
    SessionId id,
    SessionRecord record, {
    bool durable = false,
  }) async {
    final line = jsonEncode(record.toJson());
    if (line.contains('\n') || line.contains('\r')) {
      throw StateError('a journal line must not contain line breaks');
    }
    final text = _texts[id] ?? (throw SessionNotFound(id));
    _texts[id] = '$text$line\n';
  }

  @override
  Future<void> flush(SessionId id) async {}

  @override
  Future<SessionSnapshot> open(SessionId id) async {
    final text = _texts[id] ?? (throw SessionNotFound(id));
    final parsed = parseSessionLines(text, id: id, logger: logger);
    if (parsed.quarantine.isNotEmpty) {
      _corrupt[id] = [
        _corrupt[id] ?? '',
        for (final q in parsed.quarantine)
          '${jsonEncode({'line': q.line, 'text': q.text, 'reason': q.reason})}\n',
      ].join();
      // Те же шаги 5a–5b §8.6, что у файла: усечение оборванного хвоста или
      // переписывание из уцелевших строк.
      _texts[id] = parsed.onlyTailBroken
          ? text.substring(0, text.lastIndexOf('\n') + 1)
          : '${parsed.keptLines.join('\n')}\n';
    } else if (parsed.missingFinalNewline) {
      _texts[id] = '$text\n';
    }
    return parsed.snapshot;
  }

  @override
  Future<SessionPage> list({
    String? cwd,
    String? cursor,
    int pageSize = 50,
  }) async {
    final summaries = [
      for (final MapEntry(key: id, value: text) in _texts.entries)
        if (_snapshotOrNull(id, text) case final snapshot?)
          if (cwd == null || snapshot.header.cwd == cwd)
            summarize(snapshot, logger: logger),
    ];
    return pageOf(summaries, cursor: cursor, pageSize: pageSize);
  }

  @override
  Future<void> close(SessionId id) async {}

  /// Только чтение для списка: журнал новой версии пропускается.
  SessionSnapshot? _snapshotOrNull(SessionId id, String text) {
    try {
      return parseSessionLines(text, id: id, logger: logger).snapshot;
    } on SessionOpenException {
      return null;
    }
  }
}
