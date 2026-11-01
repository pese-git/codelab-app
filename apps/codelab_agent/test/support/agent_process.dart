import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Процесс бинаря `codelab-agent` для интеграционных тестов на Dart VM
/// (design.md change `add-codelab-agent-binary`, D10).
///
/// Почему kernel: `dart run` компилирует точку входа при каждом запуске, а
/// тестам нужно много процессов. Бинарь один раз компилируется в
/// `.dill` и дальше запускается `dart <файл>.dill` — тот же код на той же VM.
///
/// Как использовать: `await AgentProcess.start(['serve', '--stdio', …])`;
/// [sendLine] пишет строку в stdin, [nextStdoutLine] ждёт строку stdout,
/// [stderrText] — накопленный stderr, [exitCode] — код выхода.
final class AgentProcess {
  AgentProcess._(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _stdoutLog.writeln(line);
          _stdout.add(line);
        }, onDone: _stdout.close);
    _process.stderr.transform(utf8.decoder).listen(_stderr.write);
  }

  final Process _process;
  final _stdout = StreamController<String>();
  late final StreamIterator<String> _lines = StreamIterator(_stdout.stream);
  final _stderr = StringBuffer();
  final _stdoutLog = StringBuffer();

  static Future<String>? _kernel;

  /// Путь к `.dill` бинаря: для клиентских транспортов, которые запускают
  /// процесс сами (`StdioAcpTransport`).
  static Future<String> kernel() => _kernel ??= _compile();

  /// Запускает бинарь с [args]; [environment] заменяет окружение целиком,
  /// кроме `PATH` и `HOME`.
  static Future<AgentProcess> start(
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    final kernel = await AgentProcess.kernel();
    final process = await Process.start(
      dartExecutable(),
      [kernel, ...args],
      workingDirectory: workingDirectory ?? appDirectory,
      environment: {
        'PATH': Platform.environment['PATH'] ?? '',
        'HOME': Platform.environment['HOME'] ?? '',
        ...environment,
      },
      includeParentEnvironment: false,
    );
    return AgentProcess._(process);
  }

  int get pid => _process.pid;

  Future<int> get exitCode => _process.exitCode;

  String get stderrText => _stderr.toString();

  /// Все строки stdout (кадры ACP), пришедшие к этому моменту, в том числе
  /// уже прочитанные [nextStdoutLine]: тест проверяет, что в них нет секретов.
  String get stdoutText => _stdoutLog.toString();

  void sendLine(String line) => _process.stdin.writeln(line);

  /// JSON-RPC сообщение одной строкой.
  void sendJson(Map<String, Object?> message) => sendLine(jsonEncode(message));

  Future<void> closeStdin() => _process.stdin.close();

  bool kill(ProcessSignal signal) => _process.kill(signal);

  /// Следующая строка stdout; `null` — stdout закрыт.
  Future<String?> nextStdoutLine({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final hasNext = await _lines.moveNext().timeout(timeout);
    return hasNext ? _lines.current : null;
  }

  /// Читает stdout до ответа с [id]; уведомления по дороге — в [seen].
  Future<Map<String, Object?>> responseTo(
    int id, {
    List<Map<String, Object?>>? seen,
  }) async {
    while (true) {
      final line = await nextStdoutLine();
      if (line == null) {
        throw StateError(
          'stdout closed before the response $id; '
          'stderr:\n$stderrText',
        );
      }
      final message = jsonDecode(line) as Map<String, Object?>;
      if (message['id'] == id &&
          (message.containsKey('result') || message.containsKey('error'))) {
        return message;
      }
      seen?.add(message);
    }
  }

  /// Ждёт строки stderr, содержащей [text].
  Future<void> stderrContains(
    String text, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!stderrText.contains(text)) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('stderr has no "$text":\n$stderrText');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> kill9() async {
    _process.kill(ProcessSignal.sigkill);
    await exitCode;
  }

  static Future<String> _compile() async {
    final dir = await Directory.systemTemp.createTemp('codelab_agent_kernel_');
    final output = '${dir.path}/codelab_agent.dill';
    final result = await Process.run(dartExecutable(), [
      'compile',
      'kernel',
      'bin/codelab_agent.dart',
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

/// Каталог `apps/codelab_agent`: тесты запускаются из него или из корня.
String get appDirectory {
  final current = Directory.current.path;
  return File('$current/bin/codelab_agent.dart').existsSync()
      ? current
      : '$current/apps/codelab_agent';
}

/// Dart VM для дочерних процессов: под `flutter test` текущий исполняемый
/// файл — не `dart`, поэтому ищется SDK Flutter, затем FVM-копия в корне.
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
