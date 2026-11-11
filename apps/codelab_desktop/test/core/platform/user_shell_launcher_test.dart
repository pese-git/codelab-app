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

const _timeout = Duration(seconds: 10);

/// Накопитель вывода оболочки с ожиданием маркера.
///
/// Маркеры в командах пишутся так, чтобы эхо самой команды (PTY возвращает
/// набранное) им не соответствовало: `echo RES=$(...)` даёт `RES=tty` только
/// в результате выполнения.
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

    shell.write('echo RES=\$(test -t 0 && test -t 1 && echo tty)\n');

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

  test('окружение: окружение app целиком, добавки вызывающего, TERM и '
      'COLORTERM (Q9, D5)', () async {
    // Переменная app, которой нет в узком наборе pty2 (D2, «Окружение»).
    const narrow = {
      'LOGNAME',
      'USER',
      'DISPLAY',
      'LC_CTYPE',
      'HOME',
      'PATH',
      'TERM',
      'LANG',
      'PWD',
      'OLDPWD',
      'SHLVL',
      '_',
    };
    final candidates = Platform.environment.entries.where(
      (e) =>
          !narrow.contains(e.key) &&
          RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(e.key) &&
          RegExp(r'^[A-Za-z0-9_./:-]+$').hasMatch(e.value),
    );
    if (candidates.isEmpty) {
      fail(
        'В окружении тестового процесса нет простой переменной вне узкого '
        'набора pty2 (LOGNAME, USER, DISPLAY, LC_CTYPE, HOME, PATH, TERM, '
        'LANG): проверить наследование окружения нечем. Задайте любую '
        'переменную вида FOO=bar перед запуском.',
      );
    }
    final inherited = candidates.first;
    final shell = await start(
      '/bin/sh',
      const [],
      environment: {'CODELAB_TEST_EXTRA': 'extra-value'},
    );
    final out = _Output(shell);
    addTearDown(out.dispose);

    shell.write(
      'echo ENV=\$TERM,\$COLORTERM,\$CODELAB_TEST_EXTRA,'
      '\$${inherited.key}.\n',
    );

    await out.expect(
      RegExp(
        'ENV=xterm-256color,truecolor,extra-value,'
        '${RegExp.escape(inherited.value)}\\.',
      ),
    );
  });

  test('resize(100, 30): tput cols = 100', () async {
    final shell = await start('/bin/sh', const []);
    final out = _Output(shell);
    addTearDown(out.dispose);

    shell.resize(100, 30);
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
      "trap '' HUP; exec sleep 7201",
    ]);
    var exited = false;
    unawaited(shell.exitCode.then((_) => exited = true));
    await Future<void>.delayed(const Duration(seconds: 1));

    shell.hangUp();
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(exited, isFalse, reason: 'SIGHUP проигнорирован процессом');

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
}
