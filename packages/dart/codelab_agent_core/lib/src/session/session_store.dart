import 'dart:convert';

import '../loop/agent_events.dart';
import 'records.dart';

/// Порт хранилища журнала сессий (`agent-core-architecture` §8.3).
///
/// Почему порт: разбор, дерево, ремонт в памяти и проекции живут в ядре, а
/// хранилище отвечает только за байты — дописать строку, прочитать всё,
/// перечислить журналы. Так файл на диске (`JsonlSessionStore`), документы
/// мобильного приложения и IndexedDB ведут себя одинаково (§8.1).
///
/// Для чего: `AgentSession` пишет журнал через `SessionWriter`, а
/// `AgentRuntime` открывает и перечисляет сессии.
///
/// Как использовать: [create] при создании сессии, затем [append] по
/// записи; [flush] — сброс на носитель в конце хода; [open] читает и
/// ремонтирует журнал; [close] дожидается очереди записи. Реализация
/// проходит контрактный набор тестов `session_store_contract.dart`.
abstract interface class SessionStore {
  /// Новый журнал с заголовком; существующий id — [StateError].
  Future<void> create(SessionHeader header);

  /// Одна полная строка за операцию (SES-4). [durable] — точка
  /// восстановления: запись сбрасывается на носитель по политике хранилища.
  /// Нет журнала — [SessionNotFound].
  Future<void> append(
    SessionId id,
    SessionRecord record, {
    bool durable = false,
  });

  /// Сброс записанного на носитель (`TurnEnded`, §8.3).
  Future<void> flush(SessionId id);

  /// Чтение, ремонт (§8.6) и снимок; нет журнала — [SessionNotFound],
  /// неизвестная версия — `SessionOpenException`.
  Future<SessionSnapshot> open(SessionId id);

  /// Страница сводок (§8.10); неверный курсор — [InvalidCursor].
  Future<SessionPage> list({String? cwd, String? cursor, int pageSize = 50});

  /// Дожидается очереди записи и закрывает дескриптор; журнал остаётся.
  Future<void> close(SessionId id);
}

/// Журнал сессии в памяти: заголовок, записи в порядке файла, лист.
///
/// Почему снимок, а не поток: проекции (§8.7, §8.10) — чистые функции над
/// одним неизменяемым значением, поэтому одинаковый снимок даёт одинаковый
/// контекст модели (SES-7).
final class SessionSnapshot {
  SessionSnapshot({
    required this.header,
    required List<SessionRecord> records,
    required this.leafId,
    this.repair = const RepairReport(),
  }) : records = List.unmodifiable(records),
       byId = Map.unmodifiable(_firstById(records));

  /// Журнал без записей — только что созданная сессия.
  SessionSnapshot.empty(SessionHeader header)
    : this(header: header, records: const [], leafId: null);

  final SessionHeader header;

  /// Порядок файла, без заголовка.
  final List<SessionRecord> records;

  /// Первая копия id выигрывает (§8.6, шаг 4d).
  final Map<String, SessionRecord> byId;

  /// Активный лист по §8.4; `null` — записей нет.
  final String? leafId;
  final RepairReport repair;

  /// Снимок после успешной записи [record] с новым листом [leaf].
  SessionSnapshot withRecord(SessionRecord record, String? leaf) =>
      SessionSnapshot(
        header: header,
        records: [...records, record],
        leafId: leaf,
        repair: repair,
      );

  SessionSnapshot withRepair(RepairReport repair) => SessionSnapshot(
    header: header,
    records: records,
    leafId: leafId,
    repair: repair,
  );
}

Map<String, SessionRecord> _firstById(List<SessionRecord> records) {
  final byId = <String, SessionRecord>{};
  for (final record in records) {
    byId.putIfAbsent(record.id, () => record);
  }
  return byId;
}

/// Что исправлено при открытии журнала (§8.6).
final class RepairReport {
  const RepairReport({
    this.quarantinedLines = 0,
    this.headerMissing = false,
    this.healedLeafFrom,
    this.brokenLinks = 0,
    this.interruptedToolCalls = const [],
  });

  /// Строки, ушедшие в `.corrupt`.
  final int quarantinedLines;
  final bool headerMissing;

  /// Лист указывал на этот отсутствующий id.
  final String? healedLeafFrom;

  /// Записи с ненайденным `parentId`.
  final int brokenLinks;

  /// `toolCallId` вызовов, получивших синтетический `interrupted` (§8.8);
  /// заполняет сессия после записи результатов.
  final List<String> interruptedToolCalls;

  bool get isClean =>
      quarantinedLines == 0 &&
      !headerMissing &&
      healedLeafFrom == null &&
      brokenLinks == 0 &&
      interruptedToolCalls.isEmpty;

  RepairReport withInterrupted(List<String> toolCallIds) => RepairReport(
    quarantinedLines: quarantinedLines,
    headerMissing: headerMissing,
    healedLeafFrom: healedLeafFrom,
    brokenLinks: brokenLinks,
    interruptedToolCalls: List.unmodifiable(toolCallIds),
  );
}

/// Сводка сессии для списка (§8.10, поля MVP — design.md, D5).
final class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.cwd,
    required this.updatedAt,
    this.title,
    this.messageCount = 0,
    this.lastTurnFailed = false,
  });

  final SessionId id;
  final String cwd;
  final String? title;
  final DateTime updatedAt;

  /// Слова пользователя и ответы модели на активной ветке.
  final int messageCount;

  /// Последний ответ ветки — ошибка.
  final bool lastTurnFailed;
}

final class SessionPage {
  SessionPage({required List<SessionSummary> items, this.nextCursor})
    : items = List.unmodifiable(items);

  final List<SessionSummary> items;

  /// `null` — страница последняя.
  final String? nextCursor;
}

/// Журнала с таким id нет.
final class SessionNotFound implements Exception {
  const SessionNotFound(this.id);

  final SessionId id;

  @override
  String toString() => 'SessionNotFound: ${id.value}';
}

/// Курсор `list` не разбирается (ACP: `-32602`).
final class InvalidCursor implements Exception {
  const InvalidCursor(this.cursor);

  final String cursor;

  @override
  String toString() => 'InvalidCursor: $cursor';
}

/// Сортировка и страница по курсору — общие для всех хранилищ (§8.10,
/// шаги 4–6).
///
/// Почему в ядре: порядок и формат курсора видны клиенту через ACP, и они
/// не должны зависеть от хранилища.
SessionPage pageOf(
  List<SessionSummary> summaries, {
  String? cursor,
  int pageSize = 50,
}) {
  final sorted = [...summaries]..sort(_newestFirst);
  var start = 0;
  if (cursor != null) {
    final (after, afterId) = _decodeCursor(cursor);
    final position = SessionSummary(
      id: SessionId(afterId),
      cwd: '',
      updatedAt: after,
    );
    start = sorted.indexWhere((s) => _newestFirst(s, position) > 0);
    if (start < 0) {
      start = sorted.length;
    }
  }
  final end = (start + pageSize).clamp(start, sorted.length);
  final items = sorted.sublist(start, end);
  return SessionPage(
    items: items,
    nextCursor: end < sorted.length ? _encodeCursor(items.last) : null,
  );
}

/// `updatedAt` по убыванию, при равенстве — `id` по убыванию.
int _newestFirst(SessionSummary a, SessionSummary b) {
  final byTime = b.updatedAt.compareTo(a.updatedAt);
  return byTime != 0 ? byTime : b.id.value.compareTo(a.id.value);
}

String _encodeCursor(SessionSummary last) => base64Url
    .encode(
      utf8.encode(
        jsonEncode({
          'v': 1,
          'after': '${formatJournalTime(last.updatedAt)}|${last.id.value}',
        }),
      ),
    )
    .replaceAll('=', '');

(DateTime, String) _decodeCursor(String cursor) {
  try {
    final json =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(cursor))))
            as Map<String, Object?>;
    final after = json['after']! as String;
    final bar = after.indexOf('|');
    if (json['v'] != 1 || bar < 0) {
      throw const FormatException('bad cursor');
    }
    return (DateTime.parse(after.substring(0, bar)), after.substring(bar + 1));
  } on Object {
    throw InvalidCursor(cursor);
  }
}
