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
  static Future<String>? _embeddedKernel;

  /// Прогон e2e идёт против встроенного агента (`CODELAB_E2E_AGENT=embedded`,
  /// testing-quality «Встроенный режим в e2e и conformance»).
  static bool get embeddedVariant =>
      Platform.environment['CODELAB_E2E_AGENT'] == 'embedded';

  /// Путь к `.dill` CLI, который запускают тесты варианта прогона.
  static Future<String> kernel() => kernelOf(CliEntry.variant);

  /// Путь к `.dill` выбранной точки входа; каждая собирается один раз.
  static Future<String> kernelOf(CliEntry entry) {
    final scripted = switch (entry) {
      CliEntry.variant => embeddedVariant,
      CliEntry.production => false,
      CliEntry.scriptedEmbedded => true,
    };
    return scripted
        ? _embeddedKernel ??= _compile(
            'test/e2e/support/embedded_cli_main.dart',
            'embedded_codelab.dill',
          )
        : _kernel ??= _compile('bin/codelab.dart', 'codelab.dill');
  }

  /// Запускает CLI; [environment] заменяет окружение целиком, кроме `PATH`.
  /// `HOME` по умолчанию — несуществующая папка, чтобы тест не видел
  /// настоящий `~/.codelab`.
  ///
  /// [entry] — какая точка входа: по умолчанию та, что задаёт вариант прогона
  /// ([CliEntry.variant]).
  static Future<CliProcess> start(
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
    CliEntry entry = CliEntry.variant,
  }) async {
    final process = await Process.start(
      dartExecutable(),
      [await kernelOf(entry), ...args],
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
    CliEntry entry = CliEntry.variant,
  }) async {
    final process = await start(
      args,
      environment: environment,
      workingDirectory: workingDirectory,
      entry: entry,
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

  /// Обе точки входа — файлы с окончанием `codelab.dill`: SIGTERM-тесты
  /// (`repl_turn_test.dart`, `tui_smoke_test.dart`) ищут процесс CLI
  /// `pkill -f '.*codelab\.dill --agent …'` в любом варианте прогона.
  static Future<String> _compile(String entry, String name) =>
      compileTestKernel(
        name,
        (work, output) => Process.run(dartExecutable(), [
          'compile',
          'kernel',
          entry,
          '-o',
          output,
        ], workingDirectory: appDirectory),
      );
}

/// Точка входа процесса `codelab` в тестах.
///
/// Почему три: рабочий `bin/codelab.dart` открывает встроенного агента
/// настоящим `localEmbeddedAgentOpener` — с конфигом, ключом и сетью, а e2e
/// нужен детерминированный сценарий модели. Его подставляет тестовая точка
/// входа `test/e2e/support/embedded_cli_main.dart` (design.md change
/// `add-embedded-agent-mode`, D8, D10); `package:codelab_embedded/testing.dart`
/// в рабочий код не попадает.
enum CliEntry {
  /// Как требует вариант прогона: в `embedded` — тестовая точка входа, иначе
  /// рабочая.
  variant,

  /// Всегда рабочий `bin/codelab.dart` (настоящий открыватель: конфиг, ключи,
  /// отладка секретов).
  production,

  /// Всегда тестовая точка входа со сценарием модели; сценарий задаёт
  /// `E2eCliLaunch.environment` варианта `embedded`.
  scriptedEmbedded,
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

/// Собирает kernel тестового бинаря в постоянный кэш приложения.
///
/// Почему: раньше каждый тестовый изолят (`dart test` запускает файл в своём
/// изоляте, статический `Future` живёт в нём) компилировал `.dill` в новый
/// `Directory.systemTemp.createTemp` и не удалял его — прогон `test:e2e:cli`
/// оставлял десятки каталогов по ~24 МБ, за месяцы набралось 100+ ГБ в
/// `$TMPDIR`. Удалять в `tearDownAll` нельзя: помощник вызывается из тестов,
/// а `tearDownAll` регистрируется только при объявлении; хука «изолят
/// завершается» в Dart нет.
///
/// Для чего: `.dill` лежит по постоянному пути
/// `<app>/.dart_tool/codelab_test_kernels/<name>` — один файл на имя, сколько
/// бы ни было прогонов. Компиляция идёт во временный подкаталог кэша, затем
/// `rename` атомарно заменяет файл: параллельные изоляты и процессы тестов
/// ничего не удаляют друг у друга, а процесс, уже запустивший старый
/// `.dill`, держит его inode. Содержимое одинаково — все собирают одни и те
/// же исходники рабочей копии; каждый изолят по-прежнему компилирует сам,
/// поэтому устаревший файл после правки кода не используется. Временный
/// подкаталог удаляется всегда, в том числе при ошибке компиляции.
///
/// Как использовать: `compileTestKernel('codelab.dill', (work, output) =>
/// Process.run(dart, ['compile', 'kernel', entry, '-o', output]))` — [build]
/// пишет `.dill` в `output`; [work] — пустой временный каталог для
/// сгенерированных исходников. Возвращает путь к файлу в кэше; ненулевой код
/// компиляции даёт [StateError].
Future<String> compileTestKernel(
  String name,
  Future<ProcessResult> Function(Directory work, String output) build,
) async {
  final cache = Directory('$appDirectory/.dart_tool/codelab_test_kernels');
  await cache.create(recursive: true);
  final work = await cache.createTemp('$name.');
  try {
    final output = '${work.path}/$name';
    final result = await build(work, output);
    if (result.exitCode != 0) {
      throw StateError(
        'dart compile kernel failed:\n${result.stdout}\n${result.stderr}',
      );
    }
    return (await File(output).rename('${cache.path}/$name')).path;
  } finally {
    await work.delete(recursive: true);
  }
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
