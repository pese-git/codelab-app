import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart'
    show CodelabCompatibleStdioAgentMode, writeCodelabCompatibleStdioAgent;

/// Процесс `codelab` для интеграционных тестов на Dart VM (design.md change
/// `add-codelab-cli`, D11).
///
/// Почему kernel: `dart run` компилирует точку входа при каждом запуске, а
/// тестам нужно много процессов. CLI один раз компилируется в `.dill` и
/// запускается `dart <файл>.dill` — тот же код на той же VM.
///
/// Как использовать: `await CliProcess.run(['-p', 'hi', …], environment:
/// …)` — запуск до конца с [CliResult]; [CliProcess.start] — для тестов,
/// которые шлют сигналы или пишут в stdin.
final class CliProcess {
  CliProcess._(this._process) {
    _stdoutDone = _process.stdout
        .transform(utf8.decoder)
        .listen(_stdout.write)
        .asFuture<void>();
    _stderrDone = _process.stderr
        .transform(utf8.decoder)
        .listen(_stderr.write)
        .asFuture<void>();
  }

  final Process _process;
  final _stdout = StringBuffer();
  final _stderr = StringBuffer();
  late final Future<void> _stdoutDone;
  late final Future<void> _stderrDone;

  static Future<String>? _kernel;

  /// Путь к `.dill` CLI.
  static Future<String> kernel() => _kernel ??= _compile();

  /// Запускает CLI; [environment] заменяет окружение целиком, кроме `PATH`.
  /// `HOME` по умолчанию — несуществующая папка, чтобы тест не видел
  /// настоящий `~/.codelab`.
  static Future<CliProcess> start(
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    final process = await Process.start(
      dartExecutable(),
      [await kernel(), ...args],
      workingDirectory: workingDirectory,
      environment: {
        'PATH': Platform.environment['PATH'] ?? '',
        'HOME': '${Directory.systemTemp.path}/codelab-cli-test-no-home',
        ...environment,
      },
      includeParentEnvironment: false,
    );
    return CliProcess._(process);
  }

  /// Запуск до конца; stdin закрывается сразу (или после [stdin]).
  static Future<CliResult> run(
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
    String? stdin,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final process = await start(
      args,
      environment: environment,
      workingDirectory: workingDirectory,
    );
    if (stdin != null) {
      process._process.stdin.write(stdin);
    }
    await process._process.stdin.close();
    return process.result(timeout: timeout);
  }

  void writeStdin(String text) => _process.stdin.write(text);

  bool kill(ProcessSignal signal) => _process.kill(signal);

  String get stdoutText => _stdout.toString();

  String get stderrText => _stderr.toString();

  /// Ждёт, пока в stdout или stderr появится [text].
  Future<void> waitFor(
    String text, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!stdoutText.contains(text) && !stderrText.contains(text)) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'no "$text" in the output:\nstdout:\n$stdoutText\nstderr:\n'
          '$stderrText',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<CliResult> result({
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final code = await _process.exitCode.timeout(
      timeout,
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        throw TimeoutException(
          'codelab did not exit:\nstdout:\n$stdoutText\nstderr:\n$stderrText',
        );
      },
    );
    await Future.wait([_stdoutDone, _stderrDone]);
    return CliResult(code, stdoutText, stderrText);
  }

  static Future<String> _compile() async {
    final dir = await Directory.systemTemp.createTemp('codelab_cli_kernel_');
    final output = '${dir.path}/codelab.dill';
    final result = await Process.run(dartExecutable(), [
      'compile',
      'kernel',
      'bin/codelab.dart',
      '-o',
      output,
    ], workingDirectory: appDirectory);
    if (result.exitCode != 0) {
      throw StateError(
        'dart compile kernel failed:\n${result.stdout}\n${result.stderr}',
      );
    }
    return output;
  }
}

/// Итог процесса `codelab`.
final class CliResult {
  const CliResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  @override
  String toString() => 'exit $exitCode\nstdout:\n$stdout\nstderr:\n$stderr';
}

/// Scripted stdio-агент из `codelab_acp_testing` во временной папке
/// [directory]; результат — значение `--agent`.
Future<String> scriptedAgent(
  Directory directory, {
  CodelabCompatibleStdioAgentMode mode = CodelabCompatibleStdioAgentMode.normal,
}) async {
  final file = await writeCodelabCompatibleStdioAgent(directory, mode: mode);
  return "stdio:'${dartExecutable()}' '${file.path}' serve --stdio";
}

/// Каталог `apps/codelab_cli`: тесты запускаются из него или из корня.
String get appDirectory {
  final current = Directory.current.path;
  return File('$current/bin/codelab.dart').existsSync()
      ? current
      : '$current/apps/codelab_cli';
}

/// Dart VM для дочерних процессов: под `flutter test` текущий исполняемый
/// файл — не `dart`, поэтому ищется SDK Flutter, затем FVM-копия выше по
/// дереву.
String dartExecutable() {
  final name = Platform.isWindows ? 'dart.exe' : 'dart';
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final dart = File('$flutterRoot/bin/cache/dart-sdk/bin/$name');
    if (dart.existsSync()) {
      return dart.path;
    }
  }
  final resolved = File(Platform.resolvedExecutable);
  if (resolved.uri.pathSegments.last == name) {
    return resolved.path;
  }
  for (
    var directory = Directory.current;
    directory.parent.path != directory.path;
    directory = directory.parent
  ) {
    final dart = File(
      '${directory.path}/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/$name',
    );
    if (dart.existsSync()) {
      return dart.path;
    }
  }
  return name;
}
