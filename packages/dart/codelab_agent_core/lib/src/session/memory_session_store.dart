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

  /// Журналы потомков: отдельно от [_texts], чтобы `open` и `list` их не
  /// видели (D7).
  final _children = <SessionId, String>{};

  /// Текст журнала, как был бы в файле; `null` — журнала нет.
  String? textOf(SessionId id) => _texts[id] ?? _children[id];

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
  Future<String> createChild(SessionHeader header) async {
    final parent =
        header.parent ??
        (throw ArgumentError.value(
          header.parent,
          'header.parent',
          'a child journal needs the parent link',
        ));
    if (_texts.containsKey(header.id) || _children.containsKey(header.id)) {
      throw StateError('session ${header.id.value} already exists');
    }
    _children[header.id] = '${jsonEncode(header.toJson())}\n';
    return 'subagents/${parent.rootSessionId.value}/${header.id.value}.jsonl';
  }

  @override
  Future<SessionSnapshot> openChild(
    String journal, {
    required SessionId rootSessionId,
  }) async {
    final id = _childIdOf(journal);
    final (:text, :parsed) = _readChild(journal, id, rootSessionId);
    if (parsed.quarantine.isNotEmpty) {
      _children[id] = parsed.onlyTailBroken
          ? text.substring(0, text.lastIndexOf('\n') + 1)
          : '${parsed.keptLines.join('\n')}\n';
    } else if (parsed.missingFinalNewline) {
      _children[id] = '$text\n';
    }
    return parsed.snapshot;
  }

  /// Тот же разбор и те же проверки, что у [openChild], но текст журнала и
  /// карантин не меняются (D47 Т5): оборванная строка просто не попадает в
  /// снимок.
  @override
  Future<SessionSnapshot> openChildReadOnly(
    String journal, {
    required SessionId rootSessionId,
  }) async =>
      _readChild(journal, _childIdOf(journal), rootSessionId).parsed.snapshot;

  /// Читает и проверяет журнал потомка: адрес — `subagents/<корень>/<id>.jsonl`,
  /// дерево чужого корня и заголовок с другим id отвергаются.
  ({String text, ParsedJournal parsed}) _readChild(
    String journal,
    SessionId id,
    SessionId rootSessionId,
  ) {
    final segments = journal.split('/');
    final text = _children[id] ?? (throw SessionNotFound(id));
    final parsed = parseSessionLines(text, id: id, logger: logger);
    if (segments.length != 3 ||
        segments[1] != rootSessionId.value ||
        parsed.snapshot.header.id != id ||
        parsed.snapshot.header.parent?.rootSessionId != rootSessionId) {
      throw SessionNotFound(id);
    }
    return (text: text, parsed: parsed);
  }

  /// Id потомка из адреса `subagents/<корень>/<id>.jsonl`.
  static SessionId _childIdOf(String journal) {
    final name = journal.split('/').last;
    return SessionId(
      name.endsWith('.jsonl')
          ? name.substring(0, name.length - '.jsonl'.length)
          : name,
    );
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
    if (_children[id] case final child?) {
      _children[id] = '$child$line\n';
      return;
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
