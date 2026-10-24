/// Разбор текста журнала в снимок с ремонтом в памяти
/// (`agent-core-architecture` §8.6, шаги 1–4 и 6–8).
///
/// Почему в ядре: ремонт должен быть одинаковым у файла на диске, у
/// документов приложения и у IndexedDB (§8.12). Хранилище получает готовый
/// список строк для карантина и само решает, как переписать байты
/// (шаги 5a–5b).
///
/// Как использовать: хранилище читает весь журнал как текст
/// (`utf8.decode(..., allowMalformed: true)`) и вызывает
/// [parseSessionLines]; [id], [cwd] и [created] нужны только для синтеза
/// отсутствующего заголовка.
library;

import 'dart:convert';
import 'package:collection/collection.dart';
import '../loop/agent_events.dart';
import '../util/logger.dart';
import 'records.dart';
import 'session_store.dart';
import 'tree.dart';

/// Почему журнал не открывается.
enum SessionOpenError { unsupportedVersion }

/// Журнал нельзя открыть; файл не трогается.
///
/// Почему громкая ошибка: журнал новой версии, прочитанный старым ядром,
/// мог бы потерять данные при дописывании (SES-2).
final class SessionOpenException implements Exception {
  const SessionOpenException(this.error, {this.version});

  final SessionOpenError error;

  /// Версия заголовка при [SessionOpenError.unsupportedVersion].
  final Object? version;

  @override
  String toString() => 'SessionOpenException: ${error.name} ($version)';
}

/// Строка журнала, ушедшая в карантин (`.corrupt`).
final class QuarantinedLine {
  const QuarantinedLine({
    required this.line,
    required this.text,
    required this.reason,
  });

  /// Номер строки файла с 1.
  final int line;
  final String text;

  /// `truncated` — оборванная последняя строка; `invalid` — не разбирается;
  /// `duplicate id` — вторая копия id.
  final String reason;
}

/// Результат разбора: снимок и то, что хранилище должно исправить на
/// носителе.
final class ParsedJournal {
  ParsedJournal({
    required this.snapshot,
    required List<QuarantinedLine> quarantine,
    required this.onlyTailBroken,
    required this.missingFinalNewline,
    required List<String> keptLines,
  }) : quarantine = List.unmodifiable(quarantine),
       keptLines = List.unmodifiable(keptLines);

  final SessionSnapshot snapshot;
  final List<QuarantinedLine> quarantine;

  /// В карантине только оборванная последняя строка: файл достаточно
  /// усечь до конца последней целой строки, переписывать его не нужно.
  final bool onlyTailBroken;

  /// Последняя строка целая, но без `\n`: перед следующей записью его
  /// нужно дописать, иначе две записи склеятся в одну строку.
  final bool missingFinalNewline;

  /// Исходные строки заголовка и уцелевших записей без `\n` — для
  /// переписывания файла после карантина (§8.6, шаг 5b): строки
  /// переносятся как были, без повторного кодирования.
  final List<String> keptLines;
}

ParsedJournal parseSessionLines(
  String text, {
  required SessionId id,
  String cwd = '',
  DateTime? created,
  Logger? logger,
}) {
  final lines = text.split('\n');
  // Текст, оканчивающийся '\n', даёт пустой последний элемент; иначе
  // последний элемент — строка без перевода строки (tail, §8.6, шаг 2).
  final hasTail = lines.last.isNotEmpty;
  final tailIndex = lines.length - 1;
  final quarantine = <QuarantinedLine>[];
  final records = <SessionRecord>[];
  final kept = <String>[];
  final ids = <String>{};
  SessionHeader? header;
  var headerMissing = false;
  var tailParsed = false;
  var seenFirst = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].endsWith('\r')
        ? lines[i].substring(0, lines[i].length - 1)
        : lines[i];
    if (line.trim().isEmpty) {
      continue;
    }
    final isTail = hasTail && i == tailIndex;
    final decoded = _decode(line);
    if (!seenFirst) {
      seenFirst = true;
      if (decoded case {'type': 'session'}) {
        final version = decoded['version'];
        if (version != sessionFormatVersion) {
          throw SessionOpenException(
            SessionOpenError.unsupportedVersion,
            version: version,
          );
        }
        try {
          header = SessionHeader.fromJson(decoded);
          kept.add(line);
          continue;
        } on Object {
          // Заголовок без обязательных полей: синтез ниже, строка — в
          // карантин как нечитаемая.
          quarantine.add(
            QuarantinedLine(line: i + 1, text: line, reason: 'invalid'),
          );
          continue;
        }
      }
      headerMissing = true;
    }
    final record = decoded == null ? null : _record(decoded);
    if (record == null) {
      quarantine.add(
        QuarantinedLine(
          line: i + 1,
          text: line,
          reason: isTail ? 'truncated' : 'invalid',
        ),
      );
      continue;
    }
    if (!ids.add(record.id)) {
      quarantine.add(
        QuarantinedLine(line: i + 1, text: line, reason: 'duplicate id'),
      );
      continue;
    }
    if (isTail) {
      tailParsed = true;
    }
    records.add(record);
    kept.add(line);
  }

  header ??= SessionHeader(
    id: id,
    cwd: cwd,
    created: created ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    agent: const AgentInfo(name: 'unknown', version: 'unknown'),
  );

  String? leaf;
  for (final record in records) {
    leaf = leafAfter(record);
  }
  String? healedFrom;
  final present = {for (final r in records) r.id};
  if (leaf != null && !present.contains(leaf)) {
    // Dangling leaf (§8.6, шаг 7): лист — последняя уцелевшая запись не
    // `leaf`; в файл ничего не пишется, следующая запись прикрепится к ней.
    healedFrom = leaf;
    leaf = records.lastWhereOrNull((r) => r is! LeafRecord)?.id;
    logger?.log(
      LogLevel.warning,
      'session.leaf.healed',
      fields: {'from': healedFrom, 'to': leaf},
    );
  }
  final brokenLinks = records
      .where((r) => r.parentId != null && !present.contains(r.parentId))
      .length;

  return ParsedJournal(
    snapshot: SessionSnapshot(
      header: header,
      records: records,
      leafId: leaf,
      repair: RepairReport(
        quarantinedLines: quarantine.length,
        headerMissing: headerMissing,
        healedLeafFrom: healedFrom,
        brokenLinks: brokenLinks,
      ),
    ),
    quarantine: quarantine,
    onlyTailBroken:
        quarantine.length == 1 && quarantine.single.reason == 'truncated',
    missingFinalNewline: hasTail && tailParsed,
    keptLines: kept,
  );
}

Map<String, Object?>? _decode(String line) {
  try {
    return switch (jsonDecode(line)) {
      final Map<String, Object?> json => json,
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

SessionRecord? _record(Map<String, Object?> json) {
  try {
    return SessionRecord.fromJson(json);
  } on Object {
    // Битая запись любого вида (нет id, не те типы полей) — в карантин, а
    // не исключение: журнал должен открываться (SES-5).
    return null;
  }
}
