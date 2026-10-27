/// Порт терминала REPL.
///
/// Почему: REPL читает клавиши и переключает режим stdin, а модульные тесты
/// должны идти без процесса и PTY; `dart:io` остаётся в `IoTerminal`
/// (design.md change `add-codelab-cli`, D2, D5).
///
/// Для чего: [input] — байты stdin; [output] — stdout, [errorOutput] —
/// stderr; [hasTerminal] — stdin и stdout подключены к терминалу (иначе
/// ввод построчный, без raw-режима); [columns] — ширина для перерисовки
/// строки ввода.
///
/// Как использовать: REPL вызывает [enableRawMode] при старте, если
/// [hasTerminal], и [restore] на любом выходе; [restore] идемпотентен.
abstract interface class Terminal {
  Stream<List<int>> get input;

  StringSink get output;

  StringSink get errorOutput;

  bool get hasTerminal;

  int get columns;

  void enableRawMode();

  void restore();
}
