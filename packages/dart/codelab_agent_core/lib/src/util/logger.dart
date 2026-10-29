/// Logging port of the core — `agent-core-architecture` §12.3.
///
/// The core writes only here; the host decides where records go (stderr of
/// `codelab-agent serve --stdio`, a log file, the app log panel). stdout is
/// never written: in stdio mode it carries ACP. `event` is a stable name
/// `<area>.<action>` (`llm.retry`, `llm.request.end`); field keys are
/// `snake_case`. Message texts and tool arguments are not logged at `info`
/// and above.
library;

enum LogLevel { trace, debug, info, warning, error }

abstract interface class Logger {
  bool isEnabled(LogLevel level);

  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  });
}

/// What the host sink receives (after redaction, once it exists).
final class LogRecord {
  const LogRecord({
    required this.time,
    required this.level,
    required this.event,
    this.fields = const {},
    this.error,
    this.stack,
  });

  final DateTime time;
  final LogLevel level;
  final String event;
  final Map<String, Object?> fields;
  final String? error;
  final String? stack;

  @override
  String toString() =>
      '${time.toIso8601String()} ${level.name} $event $fields'
      '${error == null ? '' : ' error=$error'}';
}

/// Логгер с постоянными полями записей поверх другого логгера.
///
/// Почему: код, не знающий сессии (транспорт MCP из `codelab_agent_io`),
/// обязан писать `session_id` в каждую запись (D13 change
/// `add-agent-mcp-client`, §12.3), а порт транспорта не должен тащить id
/// сессии отдельным параметром.
///
/// Как использовать: владелец контекста оборачивает логгер один раз —
/// `BoundLogger(logger, {'session_id': id.value})` — и отдаёт его дальше.
/// Поля вызова `log` перекрывают связанные при совпадении ключей.
final class BoundLogger implements Logger {
  BoundLogger(this._inner, Map<String, Object?> fields)
    : _fields = Map.unmodifiable(fields);

  final Logger _inner;
  final Map<String, Object?> _fields;

  @override
  bool isEnabled(LogLevel level) => _inner.isEnabled(level);

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) => _inner.log(
    level,
    event,
    fields: {..._fields, ...fields},
    error: error,
    stack: stack,
  );
}
