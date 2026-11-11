// Спайк 1.1: доля кода выхода -1 (вместо реального) у быстро завершающегося shell.
import 'dart:io';

import 'package:terminal_spike/pty_probe.dart';

Future<void> main() async {
  final counts = <int, int>{};
  for (var i = 0; i < 30; i++) {
    final p = PtyProbe.start('/bin/sh', []);
    p.pty.write('exit 3\n');
    counts.update(await p.exit, (v) => v + 1, ifAbsent: () => 1);
  }
  stdout.writeln('\nexit 3 сразу после старта, 30 запусков: $counts');
}
