// Спайк 1.1: дочерний «app»: открывает PTY с shell и `sleep`, затем ждёт убийства.
import 'dart:io';

import 'package:terminal_spike/pty_probe.dart';

Future<void> main(List<String> args) async {
  final p = PtyProbe.start('/bin/sh', ['-l']);
  p.pty.write('sleep 7105\n');
  await waitAlive('sleep 7105');
  stdout.writeln('READY');
  await Future<void>.delayed(const Duration(minutes: 5));
}
