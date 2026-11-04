import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;

/// Логгер, складывающий записи в [entries] (поля, `event`, `level`).
final class RecordingLogger implements Logger {
  RecordingLogger([this._context = const {}, List<Map<String, Object?>>? sink])
    : entries = sink ?? [];

  final Map<String, Object?> _context;
  final List<Map<String, Object?>> entries;

  @override
  Logger bind(Map<String, Object?> context) =>
      RecordingLogger({..._context, ...context}, entries);

  @override
  Logger withCorrelation({
    String? sessionId,
    String? requestId,
    int? connectionGeneration,
    String? toolCallId,
    String? messageId,
    String? operationId,
  }) => this;

  void _log(String level, String? event, Map<String, Object?>? context) =>
      entries.add({..._context, ...?context, 'event': event, 'level': level});

  @override
  void trace(String? event, {Map<String, Object?>? context}) =>
      _log('trace', event, context);

  @override
  void debug(String? event, {Map<String, Object?>? context}) =>
      _log('debug', event, context);

  @override
  void info(String? event, {Map<String, Object?>? context}) =>
      _log('info', event, context);

  @override
  void warning(String? event, {Map<String, Object?>? context}) =>
      _log('warning', event, context);

  @override
  void error(String? event, {Map<String, Object?>? context}) =>
      _log('error', event, context);

  @override
  void critical(String? event, {Map<String, Object?>? context}) =>
      _log('critical', event, context);
}
