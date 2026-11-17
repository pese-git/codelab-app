// Спайк 1.1: контракт PTY для будущего UserShellLauncher (задача 1.5).
// Один файл идёт и под `dart test`, и под `flutter test` (D13).
import 'dart:async';
import 'dart:io';

import 'package:terminal_spike/pty_probe.dart';
import 'package:test_api/scaffolding.dart';

String get _shell => Platform.environment['SHELL'] ?? '/bin/sh';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pty_spike'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('login shell в заданной папке, оба потока — tty', () async {
    final p = PtyProbe.start(_shell, ['-l'], cwd: tmp.path);
    addTearDown(p.close);
    final real = tmp.resolveSymbolicLinksSync();
    p.pty.write('pwd; test -t 0 && test -t 1; echo RC=\$?\n');
    await p.expect(RegExp('RC=0'));
    check(p.buffer.toString().contains(real), 'cwd $real');
  });

  test('resize(100, 30): tput cols = 100, rows = 30', () async {
    final p = PtyProbe.start('/bin/sh', ['-l']);
    addTearDown(p.close);
    p.pty.resize(100, 30);
    p.pty.write('echo SZ=\$(tput cols)x\$(tput lines)\n');
    await p.expect(RegExp('SZ=100x30'));
  });

  test('Ctrl+C прерывает sleep, shell жив', () async {
    final p = PtyProbe.start(_shell, ['-l']);
    addTearDown(p.close);
    p.pty.write('sleep 7101\n');
    check(await waitAlive('sleep 7101'), 'sleep стартовал');
    p.pty.write('\x03');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    check(!(processAlive('sleep 7101')), 'ожидалось false');
    p.pty.write('echo AL""IVE\n');
    await p.expect(RegExp('ALIVE'));
    check(!(p.exited), 'ожидалось false');
  });

  for (final sh in {'/bin/sh', _shell}) {
    test('SIGHUP завершает интерактивный shell и его задание ($sh)', () async {
      final p = PtyProbe.start(sh, ['-l']);
      addTearDown(p.close);
      p.pty.write('sleep 7102\n');
      check(await waitAlive('sleep 7102'), 'sleep стартовал');
      check(p.pty.kill(ProcessSignal.sighup), 'ожидалось true');
      await p.exit.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      check(!(processAlive('sleep 7102')), 'ожидалось false');
    });
  }

  test(
    'trap HUP, shell -c: hangUp не завершает, kill (SIGKILL) завершает',
    () async {
      final p = PtyProbe.start('/bin/sh', [
        '-c',
        "trap '' HUP; exec sleep 7103",
      ]);
      addTearDown(p.close);
      check(await waitAlive('sleep 7103'), 'sleep стартовал');
      p.pty.kill(ProcessSignal.sighup);
      await Future<void>.delayed(const Duration(seconds: 1));
      check(!p.exited, 'HUP проигнорирован');
      check(p.pty.kill(ProcessSignal.sigkill), 'kill доставлен');
      await p.exit.timeout(const Duration(seconds: 2));
      check(!processAlive('sleep 7103'), 'sleep убит');
    },
  );

  test('trap HUP в интерактивном sh: что происходит с заданием', () async {
    final p = PtyProbe.start('/bin/sh', []);
    addTearDown(p.close);
    p.pty.write("trap '' HUP; sleep 7104\n");
    check(await waitAlive('sleep 7104'), 'sleep стартовал');
    p.pty.kill(ProcessSignal.sighup);
    await Future<void>.delayed(const Duration(seconds: 1));
    final afterHup = (exited: p.exited, sleepAlive: processAlive('sleep 7104'));
    p.pty.kill(ProcessSignal.sigkill);
    await p.exit.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final afterKill = processAlive('sleep 7104');
    // ignore: avoid_print
    print(
      'interactive trap: afterHup=$afterHup, sleep alive after SIGKILL=$afterKill',
    );
    Process.runSync('pkill', ['-f', 'sleep 7104']);
  });

  test('повторные kill/hangUp после выхода — без ошибок', () async {
    final p = PtyProbe.start('/bin/sh', []);
    p.pty.write('exit 3\n');
    final code = await p.exit.timeout(const Duration(seconds: 3));
    // ignore: avoid_print
    print('exit 3 (сразу после старта) -> $code');
    p.pty.kill(ProcessSignal.sighup);
    p.pty.kill(ProcessSignal.sigkill);
    p.pty.kill(ProcessSignal.sigkill);
    p.pty.write('x');
    p.pty.resize(10, 10);
  });

  test(
    'несуществующий исполняемый файл: исключения нет, shell выходит сам',
    () async {
      // Адаптер UserShellLauncher обязан проверить файл заранее.
      final p = PtyProbe.start('/nonexistent/shell', []);
      final code = await p.exit.timeout(const Duration(seconds: 3));
      // ignore: avoid_print
      print('nonexistent exec -> code=$code (исключения нет)');
    },
  );

  test(
    'несуществующая cwd: исключения нет, дочерний процесс выходит',
    () async {
      final p = PtyProbe.start('/bin/sh', [], cwd: '${tmp.path}/nope');
      final code = await p.exit.timeout(const Duration(seconds: 3));
      // ignore: avoid_print
      print('nonexistent cwd -> code=$code (исключения нет)');
    },
  );

  test('окружение: без environment наследуется узкий набор', () async {
    final parentHas = Platform.environment.containsKey(
      '__CF_USER_TEXT_ENCODING',
    );
    final p = PtyProbe.start('/bin/sh', []);
    addTearDown(p.close);
    p.pty.write(
      'echo CF=\$([ -n "\${__CF_USER_TEXT_ENCODING+x}" ] && echo y || echo n).\n',
    );
    final m = await p.expect(RegExp(r'CF=([yn])\.'));
    // ignore: avoid_print
    print('parent has var=$parentHas, child has var=${m.group(1)}');
    final p2 = PtyProbe.start(
      '/bin/sh',
      [],
      environment: Map.of(Platform.environment),
    );
    addTearDown(p2.close);
    p2.pty.write(
      'echo CF=\$([ -n "\${__CF_USER_TEXT_ENCODING+x}" ] && echo y || echo n).\n',
    );
    final m2 = await p2.expect(RegExp(r'CF=([yn])\.'));
    // ignore: avoid_print
    print('with full env: child has var=${m2.group(1)}');
  });
}
