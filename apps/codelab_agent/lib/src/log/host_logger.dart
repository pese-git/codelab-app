import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

abstract interface class LogSink {
  void write(LogRecord record);

  Future<void> close();
}

final class HostLogger implements Logger {
  HostLogger({required LogLevel level, required List<LogSink> sinks});

  @override
  bool isEnabled(LogLevel level) => throw UnimplementedError();

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) => throw UnimplementedError();
}

final class StderrLogSink implements LogSink {
  StderrLogSink(IOSink out);

  @override
  void write(LogRecord record) => throw UnimplementedError();

  @override
  Future<void> close() => throw UnimplementedError();
}

final class FileLogSink implements LogSink {
  static FileLogSink open(String path) => throw UnimplementedError();

  @override
  void write(LogRecord record) => throw UnimplementedError();

  @override
  Future<void> close() => throw UnimplementedError();
}
