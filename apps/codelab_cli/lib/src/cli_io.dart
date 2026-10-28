import 'dart:async';
import 'dart:io' as io;

/// Стандартные потоки процесса, которыми пользуется `runCodelab`.
///
/// Почему: stdout headless — данные для скриптов, и что в него попадает,
/// проверяется модульными тестами без процесса (design.md change
/// `add-codelab-cli`, D2). Порт отделяет логику запуска от `dart:io`.
///
/// Для чего: единственный путь вывода `runCodelab`; ответ агента — в
/// [stdout], диагностика и ошибки — в [stderr].
///
/// Как использовать: процесс — [ProcessCliIo]; тесты — фейк с буферами.
/// Перед выходом вызывается [flush].
abstract interface class CliIo {
  /// Ввод процесса; читается целиком только для промпта headless из stdin.
  Stream<List<int>> get stdin;

  /// Подключён ли stdin к терминалу: без него и без `-p` промпт — stdin
  /// (H-01).
  bool get stdinIsTerminal;

  /// Подключён ли stdout к терминалу: полноэкранному режиму нужны оба
  /// потока (design.md change `add-cli-tui`, D4).
  bool get stdoutIsTerminal;

  StringSink get stdout;

  StringSink get stderr;

  /// Дожидается записи stdout и stderr.
  Future<void> flush();
}

/// [CliIo] процесса на `dart:io`.
final class ProcessCliIo implements CliIo {
  const ProcessCliIo();

  @override
  Stream<List<int>> get stdin => io.stdin;

  @override
  bool get stdinIsTerminal => io.stdin.hasTerminal;

  @override
  bool get stdoutIsTerminal => io.stdout.hasTerminal;

  @override
  StringSink get stdout => io.stdout;

  @override
  StringSink get stderr => io.stderr;

  @override
  Future<void> flush() async {
    await io.stdout.flush();
    await io.stderr.flush();
  }
}
