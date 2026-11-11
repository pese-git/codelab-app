// Спайк 1.1: страховочная сеть D4 — остаётся ли shell/задание сиротой,
// если «app» убит `SIGKILL` без закрытия PTY.
import 'dart:convert';
import 'dart:io';

import 'package:terminal_spike/pty_probe.dart';

Future<void> main() async {
  final child = await Process.start(Platform.resolvedExecutable, [
    'run',
    'bin/orphan_child.dart',
  ]);
  final ready = Completer0();
  child.stdout.transform(utf8.decoder).listen((s) {
    if (s.contains('READY')) ready.done = true;
  });
  child.stderr.drain<void>();
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (!ready.done && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  stdout.writeln(
    'child ready=${ready.done}, sleep alive=${processAlive('sleep 7105')}',
  );
  // `dart run` порождает VM-процесс: убиваем всё поддерево по имени скрипта.
  Process.runSync('pkill', ['-9', '-f', 'orphan_child.dart']);
  await Future<void>.delayed(const Duration(seconds: 2));
  stdout.writeln(
    'after SIGKILL of app: sleep alive=${processAlive('sleep 7105')}',
  );
  Process.runSync('pkill', ['-f', 'sleep 7105']);
}

class Completer0 {
  bool done = false;
}
