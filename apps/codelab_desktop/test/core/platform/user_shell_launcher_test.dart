// Контрактный тест адаптера процессов терминала (задача 1.5 change
// `add-integrated-terminal`; спецификация `integrated-terminal` «Терминал —
// настоящий псевдотерминал» и «Жизненный цикл процессов терминала»; D2, D4,
// D13, D15).
//
// Почему настоящий PTY: сказать «stdin и stdout — терминал», «размер дошёл до
// ядра» и «SIGHUP/SIGKILL доходят до процесса» можно только на живом
// псевдотерминале. Native assets `pty2` собираются под `flutter test` на хосте
// (D15), поэтому тест идёт на Dart VM в `feature/*`, без устройства (§21).
//
// На код выхода тест НЕ опирается (D4, «Код выхода»): `pty2` иногда отдаёт `-1`
// вместо настоящего кода. Исключение — чистая функция перевода `-1` → `null`.
import 'dart:async';
import 'dart:io';

import 'package:codelab_desktop/core/platform/user_shell_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pty2/pty2.dart';

const _timeout = Duration(seconds: 10);

/// Накопитель вывода оболочки с ожиданием маркера.
///
/// PTY возвращает эхо набранной команды, поэтому маркер в команде пишут так,
/// чтобы он совпал только с результатом выполнения: `echo RES=t""ty` в эхо
/// выглядит как `RES=t""ty`, а выводит `RES=tty` (оболочка склеивает пустые
/// кавычки). Регулярное выражение ожидания ищет `RES=tty`.
class _Output {
  _Output(UserShell shell) {
    _sub = shell.output.listen((chunk) {
      buffer.write(chunk);
      for (final w in List.of(_waiters)) {
        if (w.$1.hasMatch(buffer.toString())) {
          _waiters.remove(w);
          w.$2.complete();
        }
      }
    });
  }

  final buffer = StringBuffer();
  final _waiters = <(RegExp, Completer<void>)>[];
  late final StreamSubscription<String> _sub;

  Future<void> expect(RegExp pattern) {
    if (pattern.hasMatch(buffer.toString())) return Future.value();
    final c = Completer<void>();
    _waiters.add((pattern, c));
    return c.future.timeout(
      _timeout,
      onTimeout: () =>
          throw TimeoutException('нет $pattern; вывод: ${buffer.toString()}'),
    );
  }

  Future<void> dispose() => _sub.cancel();
}

void main() {
  late Directory tmp;
  late PtyUserShellLauncher launcher;
  final shells = <UserShell>[];

  Future<UserShell> start(
    String executable,
    List<String> args, {
    Map<String, String> environment = const {},
  }) async {
    final shell = await launcher.start(
      executable: executable,
      arguments: args,
      workingDirectory: tmp.path,
      environment: environment,
      columns: 80,
      rows: 24,
    );
    shells.add(shell);
    return shell;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('user_shell_launcher_test');
    launcher = PtyUserShellLauncher();
  });

  tearDown(() async {
    // Подстраховка: ни один тест не оставляет процесс в системе.
    for (final shell in shells) {
      shell.kill();
    }
    shells.clear();
    tmp.deleteSync(recursive: true);
  });

  test(
    'isSupported на macOS — true (D12)',
    () => expect(launcher.isSupported, isTrue),
    skip: Platform.isMacOS ? false : 'проверка только для macOS',
  );

  test('stdin и stdout процесса — терминал', () async {
    final shell = await start('/bin/sh', const []);
    final out = _Output(shell);
    addTearDown(out.dispose);

    // Не `$(...)`: в подстановке stdout — канал, и `test -t 1` ложно ложен.
    // Кавычки в `t""ty` не дают эху набранной команды совпасть с маркером.
    shell.write('test -t 0 && test -t 1 && echo RES=t""ty\n');

    await out.expect(RegExp('RES=tty'));
  });

  test('рабочая папка соблюдается', () async {
    final shell = await start('/bin/sh', const []);
    final out = _Output(shell);
    addTearDown(out.dispose);
    // На macOS tmp — симлинк (/var → /private/var), shell печатает реальный путь.
    final real = tmp.resolveSymbolicLinksSync();

    shell.write('echo CWD=\$(pwd -P).\n');

    await out.expect(RegExp('CWD=${RegExp.escape(real)}\\.'));
  });

  test('окружение: добавки вызывающего, TERM и COLORTERM видны в shell '
      '(Q9, D5)', () async {
    // Значения чужих переменных окружения тест не читает и не печатает:
    // там могут быть секреты. Наследование окружения app — детерминированный
    // тест через fake-стартёр ниже.
    final shell = await start(
      '/bin/sh',
      const [],
      environment: {'CODELAB_TERM_TEST': 'extra-value'},
    );
    final out = _Output(shell);
    addTearDown(out.dispose);

    shell.write('echo ENV=\$TERM,\$COLORTERM,\$CODELAB_TERM_TEST.\n');

    await out.expect(RegExp(r'ENV=xterm-256color,truecolor,extra-value\.'));
  });

  test('resize(100, 30): tput cols = 100', () async {
    final shell = await start('/bin/sh', const []);
    final out = _Output(shell);
    addTearDown(out.dispose);

    shell.resize(100, 30);
    shell.write('echo SZ=\$(tput cols)x\$(tput lines).\n');

    await out.expect(RegExp(r'SZ=100x30\.'));
  });

  test('начальный размер columns x rows применяется при старте, без '
      'resize (D2: pty2.start размера не принимает)', () async {
    final shell = await launcher.start(
      executable: '/bin/sh',
      arguments: const [],
      workingDirectory: tmp.path,
      environment: const {},
      columns: 100,
      rows: 30,
    );
    shells.add(shell);
    final out = _Output(shell);
    addTearDown(out.dispose);

    shell.write('echo SZ=\$(tput cols)x\$(tput lines).\n');

    await out.expect(RegExp(r'SZ=100x30\.'));
  });

  test('hangUp() завершает интерактивный sh', () async {
    final shell = await start('/bin/sh', const []);

    shell.hangUp();

    await shell.exitCode.timeout(_timeout);
  });

  test('kill() завершает процесс, на который hangUp() не действует '
      '(D15, п. 6)', () async {
    final shell = await start('/bin/sh', const [
      '-c',
      "trap '' HUP; echo READY; exec sleep 7201",
    ]);
    final out = _Output(shell);
    addTearDown(out.dispose);
    // Маркер READY печатается после `trap`: сигнал уже будет проигнорирован.
    await out.expect(RegExp('READY'));

    shell.hangUp();
    // Отрицательный результат ждать нечем: даём SIGHUP секунду подействовать,
    // если бы процесс его не игнорировал; выход за это время — провал.
    await expectLater(
      shell.exitCode.timeout(const Duration(seconds: 1)),
      throwsA(isA<TimeoutException>()),
      reason: 'SIGHUP проигнорирован процессом',
    );

    shell.kill();

    await shell.exitCode.timeout(_timeout);
  });

  test(
    'повторные kill, hangUp, write и resize после выхода — без ошибок',
    () async {
      final shell = await start('/bin/sh', const []);
      shell.write('exit\n');
      await shell.exitCode.timeout(_timeout);

      shell
        ..hangUp()
        ..kill()
        ..kill()
        ..write('x')
        ..resize(10, 10);
    },
  );

  test('-1 от pty2 адаптер отдаёт как null, настоящий код — как есть '
      '(D4, «Код выхода»)', () {
    expect(userShellExitCode(-1), isNull);
    expect(userShellExitCode(0), 0);
    expect(userShellExitCode(3), 3);
  });

  group('предпроверка старта (D2, «Ошибка старта»)', () {
    // pty2 не бросает при отсутствии файла или папки, а сразу выходит;
    // типизированную ошибку адаптер формирует сам и до `start` пакета не
    // доходит: подставленный стартёр падает, если его всё же вызвали.
    late PtyUserShellLauncher guarded;

    setUp(() {
      guarded = PtyUserShellLauncher(
        startPty: (executable, args, {workingDirectory, environment}) =>
            fail('pty2.start не должен вызываться при ошибке предпроверки'),
      );
    });

    Future<UserShell> startGuarded(String executable, String folder) =>
        guarded.start(
          executable: executable,
          arguments: const [],
          workingDirectory: folder,
          environment: const {},
          columns: 80,
          rows: 24,
        );

    test('несуществующий исполняемый файл → shellNotFound без пути', () async {
      await expectLater(
        startGuarded('/nonexistent-codelab/shell', tmp.path),
        throwsA(UserShellStartFailure.shellNotFound),
      );
      expect(
        UserShellStartFailure.shellNotFound.toString(),
        isNot(contains('/')),
      );
    });

    test('файл не исполняемый → shellNotFound', () async {
      final plain = File('${tmp.path}/plain.txt')..writeAsStringSync('x');

      await expectLater(
        startGuarded(plain.path, tmp.path),
        throwsA(UserShellStartFailure.shellNotFound),
      );
    });

    test('несуществующая папка → folderNotFound без пути', () async {
      await expectLater(
        startGuarded('/bin/sh', '${tmp.path}/nope'),
        throwsA(UserShellStartFailure.folderNotFound),
      );
      expect(
        UserShellStartFailure.folderNotFound.toString(),
        isNot(contains('/')),
      );
    });
  });

  group('адаптер на fake-PTY', () {
    late _FakePty fake;
    late Map<String, String>? capturedEnvironment;
    late PtyUserShellLauncher fakeLauncher;

    setUp(() {
      fake = _FakePty();
      capturedEnvironment = null;
      fakeLauncher = PtyUserShellLauncher(
        startPty: (executable, args, {workingDirectory, environment}) {
          capturedEnvironment = environment;
          return fake;
        },
      );
    });

    Future<UserShell> startFake({
      Map<String, String> environment = const {},
      String executable = '/bin/sh',
    }) => fakeLauncher.start(
      executable: executable,
      arguments: const [],
      workingDirectory: tmp.path,
      environment: environment,
      columns: 100,
      rows: 30,
    );

    test('окружение: Platform.environment целиком, добавки, TERM и COLORTERM '
        'не переопределяются добавками (Q9, D5)', () async {
      await startFake(
        environment: {
          'CODELAB_TERM_TEST': 'extra',
          'TERM': 'dumb',
          'COLORTERM': 'none',
        },
      );

      final env = capturedEnvironment!;
      // В сообщениях только ключи: значения реального окружения не печатаются.
      final lost = Platform.environment.keys
          .where(
            (k) =>
                k != 'TERM' &&
                k != 'COLORTERM' &&
                env[k] != Platform.environment[k],
          )
          .toList();
      expect(lost, isEmpty, reason: 'потеряны переменные app: $lost');
      expect(env['CODELAB_TERM_TEST'], 'extra');
      expect(env['TERM'], 'xterm-256color');
      expect(env['COLORTERM'], 'truecolor');
    });

    test(
      'начальный размер выставляется вызовом resize(columns, rows)',
      () async {
        await startFake();

        expect(fake.calls, contains('resize:100,30'));
      },
    );

    test('после выхода процесса kill, hangUp, write и resize не доходят до '
        'пакета: pid мог уйти другому процессу', () async {
      final shell = await startFake();
      fake.exit.complete(0);
      await shell.exitCode;
      fake.calls.clear();

      shell
        ..hangUp()
        ..kill()
        ..write('x')
        ..resize(10, 10);

      expect(fake.calls, isEmpty);
    });

    test('до выхода процесса kill и hangUp доходят до пакета', () async {
      final shell = await startFake();
      fake.calls.clear();

      shell
        ..hangUp()
        ..kill();

      expect(fake.calls, hasLength(2));
    });

    test('PtyException при старте → ptyUnavailable без путей', () async {
      final throwing = PtyUserShellLauncher(
        startPty: (executable, args, {workingDirectory, environment}) =>
            throw PtyException('openpty failed at /dev/ptmx'),
      );

      await expectLater(
        throwing.start(
          executable: '/bin/sh',
          arguments: const [],
          workingDirectory: tmp.path,
          environment: const {},
          columns: 80,
          rows: 24,
        ),
        throwsA(UserShellStartFailure.ptyUnavailable),
      );
      expect(
        UserShellStartFailure.ptyUnavailable.toString(),
        isNot(contains('/')),
      );
    });

    test('ошибка ожидания выхода не глушится: exitCode бросает, дальше все '
        'методы no-op', () async {
      final shell = await startFake();
      fake.exit.completeError(StateError('wait failed'));
      await expectLater(shell.exitCode, throwsA(isA<StateError>()));
      fake.calls.clear();

      shell
        ..hangUp()
        ..kill()
        ..write('x')
        ..resize(10, 10);

      expect(fake.calls, isEmpty);
    });

    test('Exception (не PtyException) при старте → ptyUnavailable', () async {
      final throwing = PtyUserShellLauncher(
        startPty: (executable, args, {workingDirectory, environment}) =>
            throw const FormatException('no native library at /x'),
      );

      await expectLater(
        throwing.start(
          executable: '/bin/sh',
          arguments: const [],
          workingDirectory: tmp.path,
          environment: const {},
          columns: 80,
          rows: 24,
        ),
        throwsA(UserShellStartFailure.ptyUnavailable),
      );
    });

    test('Error при старте (дефект окружения или программы) пробрасывается '
        'как есть', () async {
      final throwing = PtyUserShellLauncher(
        startPty: (executable, args, {workingDirectory, environment}) =>
            throw StateError('library missing'),
      );

      await expectLater(
        throwing.start(
          executable: '/bin/sh',
          arguments: const [],
          workingDirectory: tmp.path,
          environment: const {},
          columns: 80,
          rows: 24,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('сбой resize после старта → kill(SIGKILL) и ptyUnavailable: процесс '
        'не остаётся без владельца', () async {
      fake.resizeError = PtyException('ioctl failed');

      await expectLater(
        startFake(),
        throwsA(UserShellStartFailure.ptyUnavailable),
      );

      expect(fake.calls, contains('kill:${ProcessSignal.sigkill.name}'));
    });

    test('Error при resize после старта → kill(SIGKILL) и Error пробрасывается '
        'как есть: дефект не выдаётся за отказ терминала (D2)', () async {
      fake.resizeError = StateError('defect');

      await expectLater(startFake(), throwsA(isA<StateError>()));

      expect(fake.calls, contains('kill:${ProcessSignal.sigkill.name}'));
    });

    test('не абсолютный executable → shellNotFound, даже если файл найдётся '
        'от текущей папки процесса', () async {
      final script = File('${tmp.path}/relative_shell')
        ..writeAsStringSync('#!/bin/sh\n');
      await Process.run('chmod', ['+x', script.path]);
      final relative = p.relative(script.path, from: Directory.current.path);
      expect(p.isAbsolute(relative), isFalse);

      await expectLater(
        startFake(executable: relative),
        throwsA(UserShellStartFailure.shellNotFound),
      );
      expect(fake.calls, isEmpty, reason: 'pty2.start не вызывался');
    });
  });

  group('выбор shell (D5, Q9)', () {
    const posix = false;
    bool Function(String) existing(Set<String> paths) => paths.contains;

    UserShellCommand? choose(
      Map<String, String> env,
      Set<String> paths, {
      bool windows = posix,
    }) => chooseUserShell(
      environment: env,
      isWindows: windows,
      isExecutable: existing(paths),
    );

    test(r'$SHELL имеет приоритет и запускается как login shell (-l)', () {
      final c = choose(
        {'SHELL': '/usr/bin/fish'},
        {'/usr/bin/fish', '/bin/zsh', '/bin/bash', '/bin/sh'},
      );

      expect(c?.executable, '/usr/bin/fish');
      expect(c?.arguments, ['-l']);
    });

    test(r'$SHELL не абсолютный или не исполняемый → запасные пути по '
        'порядку zsh, bash, sh', () {
      expect(
        choose(
          {'SHELL': 'zsh'},
          {'/bin/zsh', '/bin/bash', '/bin/sh'},
        )?.executable,
        '/bin/zsh',
      );
      expect(
        choose({'SHELL': '/gone/shell'}, {'/bin/zsh', '/bin/bash'})?.executable,
        '/bin/zsh',
      );
      expect(
        choose(const {}, {'/bin/bash', '/bin/sh'})?.executable,
        '/bin/bash',
      );
      expect(choose(const {}, {'/bin/sh'})?.executable, '/bin/sh');
      expect(choose({'SHELL': ''}, {'/bin/sh'})?.arguments, ['-l']);
    });

    test('ни одного shell → null', () {
      expect(choose({'SHELL': '/gone/shell'}, const {}), isNull);
    });

    test(r'Windows: %ComSpec% без аргументов, нет файла → null', () {
      const cmd = r'C:\Windows\System32\cmd.exe';

      final c = choose({'ComSpec': cmd}, {cmd}, windows: true);

      expect(c?.executable, cmd);
      expect(c?.arguments, isEmpty);
      expect(choose({'ComSpec': cmd}, const {}, windows: true), isNull);
      expect(choose(const {}, {'/bin/sh'}, windows: true), isNull);
    });
  });
}

/// Подставной PTY: пишет вызовы в [calls], завершение — [exit].
class _FakePty implements PseudoTerminal {
  final exit = Completer<int>();
  final calls = <String>[];

  /// Что бросить из [resize] (проверка сбоя после старта).
  Object? resizeError;

  @override
  void init() {}

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    calls.add('kill:${signal.name}');
    return true;
  }

  @override
  Future<int> get exitCode => exit.future;

  @override
  void write(String input) => calls.add('write');

  @override
  Stream<String> get out => const Stream.empty();

  @override
  void ackProcessed() {}

  @override
  void resize(int width, int height) {
    calls.add('resize:$width,$height');
    if (resizeError case final error?) throw error;
  }
}
