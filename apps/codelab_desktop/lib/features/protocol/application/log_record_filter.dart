import 'package:structured_log/structured_log.dart' show LogLevel;

const _levelKey = 'level';
const _timestampKey = 'timestamp';

/// Записи сессии в фокусе и записи без сессии (design.md change
/// `redesign-protocol-pane`, D6, D8): для вида Log то же правило области, что
/// у `framesInScope`.
List<Map<String, Object?>> recordsInScope(
  Iterable<Map<String, Object?>> records, {
  String? focusedSessionId,
}) => [
  for (final record in records)
    if (record['session_id'] == null ||
        '${record['session_id']}' == focusedSessionId)
      record,
];

/// Фильтры вида Log: поиск, точная категория, минимальный уровень.
///
/// Почему своя функция: у `LogViewerController` пакета нет области сессии
/// (D8, п. 1), а смысл фильтров должен совпадать с полноэкранным просмотром;
/// совпадение проверяет `log_record_filter_test.dart`.
final class LogRecordFilter {
  const LogRecordFilter({this.query = '', this.category, this.minLevel});

  final String query;
  final String? category;

  /// `null` — все уровни (в макете «Debug and above», но запись TRACE
  /// `protocol_message` должна быть видна, D8).
  final LogLevel? minLevel;

  LogRecordFilter copyWith({
    String? query,
    Object? category = _keep,
    Object? minLevel = _keep,
  }) => LogRecordFilter(
    query: query ?? this.query,
    category: identical(category, _keep) ? this.category : category as String?,
    minLevel: identical(minLevel, _keep)
        ? this.minLevel
        : minLevel as LogLevel?,
  );

  @override
  bool operator ==(Object other) =>
      other is LogRecordFilter &&
      other.query == query &&
      other.category == category &&
      other.minLevel == minLevel;

  @override
  int get hashCode => Object.hash(query, category, minLevel);
}

const Object _keep = Object();

LogLevel? _levelOf(Map<String, Object?> record) {
  final name = record[_levelKey];
  if (name is! String) return null;
  for (final level in LogLevel.values) {
    if (level.name == name) return level;
  }
  return null;
}

/// Применяет [filter] к [records]; смысл — как у `LogViewerController`.
List<Map<String, Object?>> applyRecordFilter(
  List<Map<String, Object?>> records,
  LogRecordFilter filter,
) {
  final query = filter.query.toLowerCase();
  bool matches(Map<String, Object?> record) {
    final min = filter.minLevel;
    if (min != null) {
      final level = _levelOf(record);
      if (level == null || level.index < min.index) return false;
    }
    if (filter.category != null && record['category'] != filter.category) {
      return false;
    }
    if (query.isEmpty) return true;
    for (final entry in record.entries) {
      if (entry.key == _levelKey || entry.key == _timestampKey) continue;
      final value = entry.value;
      if (value != null && value.toString().toLowerCase().contains(query)) {
        return true;
      }
    }
    return false;
  }

  return [
    for (final record in records)
      if (matches(record)) record,
  ];
}
