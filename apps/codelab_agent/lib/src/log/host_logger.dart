import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Получатель готовых записей лога.
///
/// Почему: `Logger` ядра — порт, а куда идут записи, решает хост
/// (документ ядра §12.3): бинарь пишет в stderr и, по флагу, в файл.
///
/// Как использовать: [HostLogger] раздаёт каждую запись всем sink по
/// порядку; [write] не должен блокировать надолго; [close] — в конце
/// процесса.
abstract interface class LogSink {
  void write(LogRecord record);

  Future<void> close();
}

/// `Logger` бинаря: фильтр по уровню и раздача записи sink'ам.
///
/// Почему: одна запись должна одинаково попасть в stderr и в файл
/// (§12.3.1), а сбой файла не должен ронять агента (OBS-4).
///
/// Для чего: логгер ядра, сервера и хоста `codelab-agent`.
///
/// Как использовать: `HostLogger(level: …, sinks: [StderrLogSink(stderr),
/// fileSink])` — первый sink основной. Если sink бросил при записи, он
/// отключается до конца процесса, а в основной sink уходит одна запись
/// `log.file.write_failed` (design.md change `add-codelab-agent-binary`,
/// D5). Редакции секретов на этом этапе нет (§12.4, этап 8): значения
/// аргументов и текстов в лог `info` не попадают по правилу ядра.
final class HostLogger implements Logger {
  HostLogger({
    required this.level,
    required List<LogSink> sinks,
    Clock clock = const SystemClock(),
  }) : _sinks = List.of(sinks),
       _clock = clock;

  final LogLevel level;
  final List<LogSink> _sinks;
  final Clock _clock;

  @override
  bool isEnabled(LogLevel level) => level.index >= this.level.index;

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
    _dispatch(
      LogRecord(
        time: _clock.now(),
        level: level,
        event: event,
        fields: fields,
        error: error?.toString(),
        stack: stack?.toString(),
      ),
    );
  }

  /// Закрывает все sink'и; записи после этого теряются.
  Future<void> close() async {
    for (final sink in List.of(_sinks)) {
      try {
        await sink.close();
      } on Object {
        // Конец процесса: сообщить об ошибке закрытия уже некуда.
      }
    }
    _sinks.clear();
  }

  void _dispatch(LogRecord record) {
    for (final sink in List.of(_sinks)) {
      try {
        sink.write(record);
      } on Object catch (error) {
        _sinks.remove(sink);
        if (_sinks.isNotEmpty && !identical(_sinks.first, sink)) {
          _dispatch(
            LogRecord(
              time: _clock.now(),
              level: LogLevel.warning,
              event: 'log.file.write_failed',
              error: error.toString(),
            ),
          );
        }
      }
    }
  }
}
