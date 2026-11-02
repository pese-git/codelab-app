import 'package:codelab_client_acp/codelab_client_acp.dart' as client;
import 'package:codelab_embedded/codelab_embedded.dart';

/// Компонент записей встроенного агента в структурном журнале приложения
/// (`docs/architecture/observability.md` §3).
const embeddedComponent = 'embedded';

/// Переводит лог встроенного агента в структурный журнал приложения.
///
/// Почему: ядро агента пишет в собственный порт `Logger` (`codelab_embedded`
/// реэкспортирует его), а журнал приложения — `structured_log` с
/// маскированием секретов и окном лога (`LogBuffer`). Агент работает в
/// процессе приложения, поэтому его события должны быть видны там же, где
/// события клиента (`AGENTS.md` §16; design.md change
/// `add-embedded-agent-mode`, D9).
///
/// Для чего: адаптер ничего не добавляет к записи. Поля событий агента уже без
/// значений секретов (D6), а процессор `secretRedactionProcessor` журнала
/// маскирует ключи и тексты поверх. От ошибки берётся только её тип
/// (`error_class`): текст мог бы цитировать ответ провайдера, путь или
/// секрет; стек не пишется.
///
/// Как использовать: `app_scope.dart` передаёт его в
/// `localEmbeddedAgentOpener(logger: …)` после настройки журнала
/// (`CodeLabLoggingModule`). [logger] — шов тестов; по умолчанию логгер
/// `codelab_desktop.embedded` категории `application`.
final class CodeLabEmbeddedLogger implements Logger {
  CodeLabEmbeddedLogger({client.Logger? logger})
    : _logger =
          (logger ?? client.StructuredLogLogger('codelab_desktop.embedded'))
              .bind({
                client.logCategoryKey: client.applicationLogCategory,
                client.logComponentKey: embeddedComponent,
              });

  final client.Logger _logger;

  /// Уровни отсекают приёмники `structured_log` (`minLevel` у каждого): адаптеру
  /// решать нечего.
  @override
  bool isEnabled(LogLevel level) => true;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {
    final context = <String, Object?>{
      ...fields,
      if (error != null) 'error_class': '${error.runtimeType}',
    };
    switch (level) {
      case LogLevel.trace:
        _logger.trace(event, context: context);
      case LogLevel.debug:
        _logger.debug(event, context: context);
      case LogLevel.info:
        _logger.info(event, context: context);
      case LogLevel.warning:
        _logger.warning(event, context: context);
      case LogLevel.error:
        _logger.error(event, context: context);
    }
  }
}
