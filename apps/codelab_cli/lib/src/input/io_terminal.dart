import 'dart:io' as io;

import 'terminal.dart';

/// [Terminal] процесса на `dart:io`.
///
/// Почему raw-режим через `stty`: `stdin.lineMode = false` в `dart:io`
/// снимает только канонический режим, а `ISIG` и `ICRNL` остаются — Ctrl+C
/// приходит сигналом, а не байтом `0x03`, и Enter неотличим от Ctrl+J. В
/// raw-режиме CLI клавиши должны приходить байтами таблицы клавиш
/// (design.md change `add-codelab-cli`, D5, D13). Вывод (`OPOST`) не
/// трогается: `\n` по-прежнему переводит строку.
///
/// Как использовать: composition root создаёт один экземпляр на процесс;
/// [restore] возвращает сохранённые `stty -g` настройки и безопасен при
/// повторном вызове — его зовут `finally` REPL и обработчик сигналов. На
/// Windows и без `/dev/tty` — запасной путь `echoMode`/`lineMode`.
final class IoTerminal implements Terminal {
  IoTerminal();

  /// Настройки `stty -g` до raw-режима; `null` — режим не менялся через
  /// `stty`.
  String? _saved;
  var _raw = false;

  @override
  Stream<List<int>> get input => io.stdin;

  @override
  StringSink get output => io.stdout;

  @override
  StringSink get errorOutput => io.stderr;

  @override
  bool get hasTerminal => io.stdin.hasTerminal && io.stdout.hasTerminal;

  @override
  int get columns => io.stdout.hasTerminal ? io.stdout.terminalColumns : 80;

  @override
  void enableRawMode() {
    if (_raw) {
      return;
    }
    _raw = true;
    if (!io.Platform.isWindows) {
      final saved = _stty('-g');
      if (saved != null &&
          _stty('-icanon -echo -isig -icrnl -ixon -iexten min 1 time 0') !=
              null) {
        _saved = saved.trim();
        return;
      }
    }
    io.stdin
      ..echoMode = false
      ..lineMode = false;
  }

  @override
  void restore() {
    if (!_raw) {
      return;
    }
    _raw = false;
    final saved = _saved;
    _saved = null;
    if (saved != null && _stty(saved) != null) {
      return;
    }
    io.stdin
      ..lineMode = true
      ..echoMode = true;
  }

  /// `stty <args>` на управляющем терминале; `null` — не удалось.
  static String? _stty(String args) {
    try {
      final result = io.Process.runSync('sh', ['-c', 'stty $args < /dev/tty']);
      return result.exitCode == 0 ? result.stdout as String : null;
    } on io.ProcessException {
      return null;
    }
  }
}
