// Спайк 1.1: пропускная способность чтения pty2 без эмулятора и без накопления.
import 'dart:io';

import 'package:pty2/pty2.dart';

Future<void> main(List<String> args) async {
  final cmd = args.isEmpty ? 'yes | head -n 200000' : args.first;
  final ack = args.length > 1 && args[1] == 'ack';
  final pty = PseudoTerminal.start('/bin/sh', ['-c', cmd], ackProcessed: ack);
  final sw = Stopwatch()..start();
  var chunks = 0, bytes = 0;
  pty.out.listen((s) {
    chunks++;
    bytes += s.length;
    if (ack) pty.ackProcessed();
  });
  await pty.exitCode;
  final tExit = sw.elapsedMilliseconds;
  await Future<void>.delayed(const Duration(milliseconds: 500));
  stdout.writeln(
    '\n`$cmd` ack=$ack: exitCode через $tExit мс, чанков $chunks, ${bytes ~/ 1024} КБ, '
    'последний чанк через ${sw.elapsedMilliseconds - 500} мс',
  );
  exit(0);
}
