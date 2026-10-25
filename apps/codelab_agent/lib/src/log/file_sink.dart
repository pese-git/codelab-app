import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../cli/serve_args.dart';
import 'host_logger.dart';

/// Пути, которые ведут в stdout процесса (§12.3.1, правило 1).
const _stdoutPaths = {'-', '/dev/stdout', '/dev/fd/1', '/proc/self/fd/1'};

/// Файл лога JSON Lines (документ ядра §12.3.1).
///
/// Почему: stderr агента видит только клиент, который его запустил; файл
/// нужен для разбора после сеанса. Файл по умолчанию из конфига на этапе 4
/// не создаётся — только по `--log-file` или `CODELAB_LOG_FILE` (design.md
/// change `add-codelab-agent-binary`, D5).
///
/// Для чего: второй sink [HostLogger]: каждая запись — одна строка
/// `{"ts","level","event", <поля>, "error", "stack"}`, записанная одним
/// вызовом `write`, поэтому несколько процессов могут дописывать один файл
/// без перемешивания строк.
///
/// Как использовать: `FileLogSink.open(path)` до создания runtime; путь в
/// stdout или неоткрываемый путь — [UsageError] (код выхода `64`). Новые
/// каталоги получают права `0700`, новый файл — `0600`; существующий файл
/// дописывается.
final class FileLogSink implements LogSink {
  FileLogSink._(this._file);

  final RandomAccessFile _file;

  static FileLogSink open(String path) {
    if (_stdoutPaths.contains(path)) {
      throw const UsageError(
        '--log-file cannot point to stdout: stdout carries the ACP protocol',
      );
    }
    try {
      final file = File(path);
      _createDirectories(file.parent);
      final existed = file.existsSync();
      final opened = file.openSync(mode: FileMode.append);
      if (!existed) {
        _chmod('600', file.path);
      }
      return FileLogSink._(opened);
    } on FileSystemException catch (error) {
      throw UsageError(
        'cannot open log file $path: '
        '${error.osError?.message ?? error.message}',
      );
    }
  }

  @override
  void write(LogRecord record) {
    final line = jsonEncode({
      'ts': record.time.toUtc().toIso8601String(),
      'level': record.level.name,
      'event': record.event,
      ...record.fields,
      'error': ?record.error,
      'stack': ?record.stack,
    }, toEncodable: (value) => value.toString());
    _file.writeStringSync('$line\n');
  }

  @override
  Future<void> close() async {
    await _file.flush();
    await _file.close();
  }

  /// Создаёт недостающие каталоги и закрывает каждый новый правами `0700`.
  static void _createDirectories(Directory directory) {
    final missing = <Directory>[];
    for (
      var current = directory.absolute;
      !current.existsSync();
      current = current.parent
    ) {
      missing.add(current);
      if (current.parent.path == current.path) {
        break;
      }
    }
    for (final dir in missing.reversed) {
      dir.createSync();
      _chmod('700', dir.path);
    }
  }

  /// В `dart:io` нет API прав доступа, поэтому — `chmod` ОС; на Windows прав
  /// POSIX нет.
  static void _chmod(String mode, String path) {
    if (Platform.isWindows) {
      return;
    }
    final result = Process.runSync('chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException('chmod $mode failed: ${result.stderr}', path);
    }
  }
}
