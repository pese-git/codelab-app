import 'dart:async';

import '../input/key_decoder.dart';
import '../input/terminal.dart';
import 'prompt_line.dart';

/// Читает строки с терминала по одной: вопрос `[Y/n]` и скрытое поле ключа
/// (первый запуск D16, ключ и сводка флаговой формы D15).
///
/// Почему не `LineEditor`: поле ключа не должно попасть в `History`; здесь
/// тот же ввод, что у мастера ([PromptLine]: маска, Ctrl+R, Ctrl+U).
///
/// Как использовать: [read] по одному вопросу за раз, в конце [close]. Пока
/// вопроса нет, клавиши отбрасываются, а хвост чтения после Enter в
/// следующее поле не переносится: опережающий ввод не должен попасть
/// открытым текстом в чужую строку (D17).
/// Ключ отклонён: вставлено несколько строк или значение слишком длинное
/// (как `MultilineSecretException` у `StdinSecretInput`, D14). Значение в
/// исключении не хранится.
final class KeyInputRejected implements Exception {
  const KeyInputRejected();

  @override
  String toString() => 'KeyInputRejected';
}

final class PromptReader {
  PromptReader(this._terminal) {
    _decoder = KeyDecoder(_onKey);
    _input = _terminal.input.listen(
      _decoder.add,
      onDone: () {
        _decoder.close();
        _finish(null);
      },
    );
    // Raw-режим — только после успешной подписки: при сбое `listen` терминал
    // остался бы без эха (`close` не вызвали бы).
    if (_terminal.hasTerminal) {
      _terminal.enableRawMode();
    }
  }

  final Terminal _terminal;
  late final KeyDecoder _decoder;
  late final StreamSubscription<List<int>> _input;
  PromptLine? _line;
  Completer<String?>? _pending;

  /// Enter уже принят, ответ ещё не выдан (микрозадача): клавиши этого же
  /// чтения, пришедшие после Enter, — «вставка нескольких строк» у скрытого
  /// поля.
  var _submitting = false;
  var _trailing = false;

  /// Ответ или `null` при Ctrl+C, Esc и конце ввода.
  Future<String?> read(String prompt, {bool hidden = false}) {
    final pending = _pending = Completer<String?>();
    final line = _line = PromptLine(prompt: prompt, hidden: hidden);
    line.draw(_terminal.output, columns: _terminal.columns);
    return pending.future;
  }

  /// Завершает вопрос и сбрасывает поле: следующий ввод идёт в новый вопрос.
  void _finish(String? value) {
    _line?.clear();
    _line = null;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(value);
    }
  }

  void _onKey(KeyEvent event) {
    final line = _line;
    if (line == null) {
      if (_submitting) {
        _trailing = true;
      }
      return;
    }
    switch (applyLineKey(line, event)) {
      case LineKey.edited:
        line.draw(_terminal.output, columns: _terminal.columns, redraw: true);
      case LineKey.submit:
        _terminal.output.write('\n');
        final value = line.text;
        final hidden = line.hidden;
        final pending = _pending;
        _line?.clear();
        _line = null;
        _pending = null;
        _submitting = hidden;
        _trailing = false;
        if (!hidden) {
          pending?.complete(value);
          break;
        }
        // Ответ отдаётся после разбора всего чтения: остаток после Enter —
        // вставка нескольких строк, ключ не принимается (D14).
        scheduleMicrotask(() {
          _submitting = false;
          if (_trailing) {
            pending?.completeError(const KeyInputRejected());
          } else {
            pending?.complete(value);
          }
        });
      case LineKey.multiline:
        _terminal.output.write('\n');
        final pending = _pending;
        _line?.clear();
        _line = null;
        _pending = null;
        pending?.completeError(const KeyInputRejected());
      case LineKey.cancel:
        _terminal.output.write('\n');
        _finish(null);
      case LineKey.ignored:
        break;
    }
  }

  /// Отменяет подписку и восстанавливает терминал: поток ввода свободен для
  /// следующего владельца (REPL, TUI).
  Future<void> close() async {
    _finish(null);
    await _input.cancel();
    _decoder.close();
    _terminal.restore();
  }
}
