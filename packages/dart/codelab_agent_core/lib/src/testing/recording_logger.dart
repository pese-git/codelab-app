import '../util/clock.dart';
import '../util/logger.dart';

/// [Logger] that keeps records in memory for assertions on log events.
final class RecordingLogger implements Logger {
  RecordingLogger({this.minLevel = LogLevel.trace, this.clock});

  final LogLevel minLevel;

  /// Time source of records; without it records carry the epoch.
  final Clock? clock;
  final _records = <LogRecord>[];

  List<LogRecord> get records => List.unmodifiable(_records);

  /// Records with [event], in order.
  List<LogRecord> eventsOf(String event) =>
      _records.where((r) => r.event == event).toList(growable: false);

  @override
  bool isEnabled(LogLevel level) => level.index >= minLevel.index;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {
    if (!isEnabled(level)) {
      return;
    }
    _records.add(
      LogRecord(
        time:
            clock?.now() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        level: level,
        event: event,
        fields: Map.unmodifiable(fields),
        error: error?.toString(),
        stack: stack?.toString(),
      ),
    );
  }
}
