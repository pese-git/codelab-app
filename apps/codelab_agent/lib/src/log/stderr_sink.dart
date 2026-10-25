import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'host_logger.dart';

/// Основной sink бинаря: одна строка на запись в stderr.
///
/// Почему stderr: в режиме `--stdio` stdout несёт протокол ACP (R-13), а
/// клиент показывает stderr агента как поток диагностики (§12.3.1).
///
/// Как использовать: `StderrLogSink(stderr)`; тесты передают `IOSink` в
/// памяти. [close] закрывает поток — в конце процесса.
final class StderrLogSink implements LogSink {
  StderrLogSink(this._out);

  final IOSink _out;

  @override
  void write(LogRecord record) => _out.writeln(record.toString());

  @override
  Future<void> close() async {
    await _out.flush();
    await _out.close();
  }
}
