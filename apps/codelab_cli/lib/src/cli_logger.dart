import 'package:codelab_client_acp/codelab_client_acp.dart';

import 'render/sanitize.dart';

/// [Logger] ядра клиента (`AcpClientApplication`) для CLI.
///
/// Почему: логгер ядра по умолчанию пишет JSON в stdout процесса, а stdout
/// headless — данные для скриптов: в нём только ответ агента (H-01;
/// design.md change `add-codelab-cli`, D9). CLI пишет лог только в stderr и
/// только с `--verbose`.
///
/// Для чего: одна строка `[уровень] событие ключ=значение…` на запись с
/// уровня `info`; контекст проходит `SecretRedactor`, как логи app
/// (`AGENTS.md` §16).
///
/// Как использовать: composition root передаёт `CliLogger(stderr)` при
/// `--verbose`, иначе `CliLogger.silent()`.
final class CliLogger implements Logger {
  CliLogger(StringSink sink) : this._(sink, const {});

  /// Логгер без вывода.
  CliLogger.silent() : this._(null, const {});

  CliLogger._(this._sink, this._context);

  final StringSink? _sink;
  final Map<String, Object?> _context;

  static const _redactor = SecretRedactor();

  @override
  Logger bind(Map<String, Object?> context) =>
      CliLogger._(_sink, {..._context, ...context});

  @override
  Logger withCorrelation({
    String? sessionId,
    String? requestId,
    int? connectionGeneration,
    String? toolCallId,
    String? messageId,
    String? operationId,
  }) => bind({
    'session_id': ?sessionId,
    'request_id': ?requestId,
    'connection_generation': ?connectionGeneration,
    'tool_call_id': ?toolCallId,
    'message_id': ?messageId,
    'operation_id': ?operationId,
  });

  @override
  void trace(String? event, {Map<String, Object?>? context}) {}

  @override
  void debug(String? event, {Map<String, Object?>? context}) {}

  @override
  void info(String? event, {Map<String, Object?>? context}) =>
      _write('info', event, context);

  @override
  void warning(String? event, {Map<String, Object?>? context}) =>
      _write('warning', event, context);

  @override
  void error(String? event, {Map<String, Object?>? context}) =>
      _write('error', event, context);

  @override
  void critical(String? event, {Map<String, Object?>? context}) =>
      _write('critical', event, context);

  void _write(String level, String? event, Map<String, Object?>? context) {
    final sink = _sink;
    if (sink == null) {
      return;
    }
    final fields = _redactor.redactMap({..._context, ...?context});
    final line = StringBuffer('[$level] ${event ?? '-'}');
    for (final MapEntry(:key, :value) in fields.entries) {
      line.write(' $key=$value');
    }
    // Значения из контекста могут нести текст агента: управляющие символы
    // терминала в stderr не пропускаются.
    sink.writeln(sanitizeTerminalText(line.toString()));
  }
}
