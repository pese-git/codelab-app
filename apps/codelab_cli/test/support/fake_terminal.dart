import 'dart:async';
import 'dart:convert';

import 'package:codelab_cli/codelab_cli.dart';

/// Терминал модульных тестов REPL.
///
/// Почему: REPL работает через порт `Terminal`, и клавиши, raw-режим и
/// восстановление проверяются без процесса и PTY (design.md change
/// `add-codelab-cli`, D5).
///
/// Как использовать: [type] и [press] подают байты клавиш, [closeInput] —
/// конец ввода; [text] — весь вывод, [errorText] — вывод stderr;
/// [rawEnabled] и [restoreCount] — что REPL сделал с режимом терминала.
final class FakeTerminal implements Terminal {
  FakeTerminal({this.hasTerminal = true, this.columns = 80});

  final _input = StreamController<List<int>>();
  final _output = StringBuffer();
  final _error = StringBuffer();

  @override
  final bool hasTerminal;

  @override
  final int columns;

  var rawEnabled = false;
  var restoreCount = 0;

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  StringSink get output => _output;

  @override
  StringSink get errorOutput => _error;

  String get text => _output.toString();

  String get errorText => _error.toString();

  @override
  void enableRawMode() => rawEnabled = true;

  @override
  void restore() {
    rawEnabled = false;
    restoreCount++;
  }

  void type(String text) => _input.add(utf8.encode(text));

  void press(List<int> bytes) => _input.add(bytes);

  Future<void> closeInput() => _input.close();
}

/// Ждёт, пока [condition] станет истинным, не дольше [timeout].
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(reason ?? 'condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
