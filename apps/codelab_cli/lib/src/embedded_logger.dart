import 'package:codelab_client_acp/codelab_client_acp.dart' as client;
import 'package:codelab_embedded/codelab_embedded.dart';

import 'render/sanitize.dart';

/// Логгер встроенного агента для CLI: строки в stderr с `--verbose`, иначе
/// никуда.
///
/// Почему отдельный класс: порт `Logger` ядра агента (`package:codelab_embedded`
/// реэкспортирует его) не совпадает с портом `Logger` клиентского ядра, а
/// stdout headless — данные для скриптов (H-01): лог агента не должен в него
/// попадать (spec codelab-cli «Встроенный агент в CLI», «Логи встроенного
/// агента»).
///
/// Как использовать: composition root передаёт его в
/// `localEmbeddedAgentOpener(logger: …)`. Поля записей агента уже без
/// значений секретов (D6); поверх них ключи и значения проходят
/// `SecretRedactor` клиента и очистку управляющих символов терминала, как у
/// `CliLogger`.
final class CliEmbeddedLogger implements Logger {
  /// Пишет записи с уровня `info` в [sink].
  CliEmbeddedLogger(StringSink sink) : _sink = sink, _lookupsOnly = false;

  /// Не пишет ничего.
  const CliEmbeddedLogger.silent() : _sink = null, _lookupsOnly = false;

  /// Пишет только события `secrets.lookup` (имя, назначение, источник,
  /// `found` — без значений): `--debug-secrets` без `--verbose`. Остальной лог
  /// агента остаётся выключенным.
  const CliEmbeddedLogger.secretLookupsOnly(StringSink sink)
    : _sink = sink,
      _lookupsOnly = true;

  final StringSink? _sink;
  final bool _lookupsOnly;

  static const _redactor = client.SecretRedactor();

  @override
  bool isEnabled(LogLevel level) =>
      _sink != null && level.index >= LogLevel.info.index;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {
    final sink = _sink;
    if (sink == null || !isEnabled(level)) {
      return;
    }
    if (_lookupsOnly && event != 'secrets.lookup') {
      return;
    }
    final redacted = _redactor.redactMap(fields);
    final line = StringBuffer('[${level.name}] $event');
    for (final MapEntry(:key, :value) in redacted.entries) {
      line.write(' $key=$value');
    }
    if (error != null) {
      // Только тип: текст ошибки мог бы цитировать ответ провайдера или
      // секрет (D6).
      line.write(' error_class=${error.runtimeType}');
    }
    sink.writeln(sanitizeTerminalText(line.toString()));
  }
}
