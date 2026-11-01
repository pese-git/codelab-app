import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Тихий логгер подкоманд `config` и `secret`.
///
/// Почему: каталог моделей, `openSecretStore` и `SecretResolver` требуют
/// `Logger` и пишут в него события, а подкоманды печатают результат только
/// строками своего вывода (stdout/stderr — контракт `codelab-agent` и
/// `codelab`, design.md change `add-agent-configuration`, D13), поэтому
/// события лога были бы шумом.
///
/// Как использовать: передавать `const SilentLogger()` только внутри
/// подкоманд; в хостах (`serve`) живёт настоящий логгер. Не экспортируется
/// из бареля пакета.
final class SilentLogger implements Logger {
  const SilentLogger();

  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}
