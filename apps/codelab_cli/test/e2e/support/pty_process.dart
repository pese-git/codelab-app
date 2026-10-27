import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Процесс в псевдотерминале системной утилиты `script`.
///
/// Почему: REPL ведёт себя в терминале иначе, чем в pipe (raw-режим,
/// клавиши, строка ввода), а своего FFI-пакета PTY в репозитории нет — новая
/// зависимость была бы решением по `AGENTS.md` §4 (§9.11 «Обвязка PTY для
/// e2e»; design.md change `add-codelab-cli`, D11).
///
/// Для чего: дочерний процесс получает терминал на stdin и stdout; запись в
/// обвязку — нажатия клавиш, [text] — вывод терминала с переводами строк,
/// приведёнными к `\n`. Синтаксис `script` разный по ОС, поэтому команда
/// собирается только здесь: BSD `script` на macOS, util-linux `script` на
/// Linux; на Windows и без утилиты [unavailableReason] даёт причину
/// пропуска.
///
/// Как использовать: в `main` теста — `skip: await
/// PtyProcess.unavailableReason()`; в тесте — `await PtyProcess.start(…)`,
/// затем [write], [waitFor] и [exitCode]. Процесс убивается в `tearDown`
/// теста, если ещё жив.
final class PtyProcess {
  PtyProcess._(this._process) {
    _done = Future.wait([
      _process.stdout.listen(_bytes.addAll).asFuture<void>(),
      _process.stderr.listen(_bytes.addAll).asFuture<void>(),
    ]);
  }

  final Process _process;
  final _bytes = <int>[];
  late final Future<void> _done;

  static Future<_Flavor?>? _flavor;

  /// Причина пропуска PTY-тестов или `null`, если `script` есть.
  static Future<String?> unavailableReason() async {
    if (Platform.isWindows) {
      return 'PTY tests do not run on Windows (§9.11)';
    }
    return await _detect() == null
        ? 'the "script" utility is not in PATH'
        : null;
  }

  static Future<_Flavor?> _detect() => _flavor ??= () async {
    final found = await Process.run('sh', ['-c', 'command -v script']);
    if (found.exitCode != 0) {
      return null;
    }
    // `--version` есть только у util-linux; BSD `script` его не знает.
    final version = await Process.run('script', ['--version']);
    return version.exitCode == 0 && '${version.stdout}'.contains('util-linux')
        ? _Flavor.utilLinux
        : _Flavor.bsd;
  }();

  /// Запускает [executable] с [args] в терминале [columns]×[rows].
  /// [environment] добавляется к `PATH`, `HOME` и `TERM=xterm-256color`;
  /// остальное окружение родителя не наследуется.
  static Future<PtyProcess> start(
    String executable,
    List<String> args, {
    int columns = 100,
    int rows = 30,
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    final flavor = await _detect();
    if (flavor == null) {
      throw StateError('the "script" utility is not in PATH');
    }
    final size = 'stty cols $columns rows $rows';
    final scriptArgs = switch (flavor) {
      _Flavor.bsd => [
        '-q',
        '/dev/null',
        'sh',
        '-c',
        '$size; exec "\$0" "\$@"',
        executable,
        ...args,
      ],
      _Flavor.utilLinux => [
        '-q',
        '-e',
        '-f',
        '-c',
        '$size; exec ${[executable, ...args].map(_quote).join(' ')}',
        '/dev/null',
      ],
    };
    final process = await Process.start(
      'script',
      scriptArgs,
      workingDirectory: workingDirectory,
      environment: {
        'PATH': Platform.environment['PATH'] ?? '',
        'HOME': Platform.environment['HOME'] ?? '/tmp',
        'TERM': 'xterm-256color',
        ...environment,
      },
      includeParentEnvironment: false,
    );
    final pty = PtyProcess._(process);
    addTearDown(pty.kill);
    return pty;
  }

  /// Вывод терминала: `\r\n` → `\n`, одиночные `\r` удалены.
  String get text => const Utf8Decoder(
    allowMalformed: true,
  ).convert(_bytes).replaceAll('\r\n', '\n').replaceAll('\r', '');

  /// Нажатия клавиш: байты [text] в stdin терминала.
  void write(String text) => _process.stdin.add(utf8.encode(text));

  /// Ждёт [needle] в [text] начиная с позиции [from].
  Future<void> waitFor(
    String needle, {
    int from = 0,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!text.substring(from.clamp(0, text.length)).contains(needle)) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('no "$needle" in the terminal:\n$text');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Код выхода дочернего процесса; вывод к этому моменту прочитан целиком.
  Future<int> get exitCode async {
    final code = await _process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        kill();
        throw TimeoutException('the PTY process did not exit:\n$text');
      },
    );
    await _done;
    return code;
  }

  void kill() => _process.kill(ProcessSignal.sigkill);

  static String _quote(String value) => "'${value.replaceAll("'", r"'\''")}'";
}

enum _Flavor { bsd, utilLinux }
