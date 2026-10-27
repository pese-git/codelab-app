// Декодер байтов терминала в клавиши (tasks 6.3; spec codelab-cli «Редактор
// строки и клавиши»; design.md change `add-codelab-cli`, D5).

import 'dart:async';
import 'dart:convert';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

/// Ручные часы декодера: таймер одиночного Esc срабатывает по [fire].
final class _ManualTimers {
  final pending = <void Function()>[];

  Timer start(Duration duration, void Function() callback) {
    pending.add(callback);
    return _ManualTimer(() => pending.remove(callback));
  }

  void fire() {
    final callbacks = [...pending];
    pending.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this._cancel);

  final void Function() _cancel;
  var _active = true;

  @override
  void cancel() {
    if (_active) {
      _active = false;
      _cancel();
    }
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

void main() {
  late List<KeyEvent> keys;
  late _ManualTimers timers;
  late KeyDecoder decoder;

  setUp(() {
    keys = [];
    timers = _ManualTimers();
    decoder = KeyDecoder(keys.add, startTimer: timers.start);
  });

  test('printable text in one read is one text event', () {
    decoder.add(utf8.encode('hello'));

    expect(keys, [const TextKey('hello')]);
  });

  test('UTF-8 split between reads is joined', () {
    final bytes = utf8.encode('й🙂');
    decoder.add(bytes.sublist(0, 1));
    expect(keys, isEmpty);
    decoder.add(bytes.sublist(1, 4));
    decoder.add(bytes.sublist(4));

    expect(keys.whereType<TextKey>().map((k) => k.text).join(), 'й🙂');
  });

  test('an invalid UTF-8 byte becomes the replacement character', () {
    decoder.add([0xff, 0x61]);

    expect(keys, [const TextKey('�a')]);
  });

  test('control bytes map to keys', () {
    decoder.add([0x0d, 0x0a, 0x09, 0x7f, 0x08, 0x03, 0x04, 0x0c]);
    decoder.add([0x01, 0x05, 0x15]);

    expect(keys, const [
      SpecialKey(Key.enter),
      SpecialKey(Key.ctrlJ),
      SpecialKey(Key.tab),
      SpecialKey(Key.backspace),
      SpecialKey(Key.backspace),
      SpecialKey(Key.ctrlC),
      SpecialKey(Key.ctrlD),
      SpecialKey(Key.ctrlL),
      SpecialKey(Key.ctrlA),
      SpecialKey(Key.ctrlE),
      SpecialKey(Key.ctrlU),
    ]);
  });

  test('arrows, Home, End and Delete in CSI and SS3 form', () {
    decoder.add(ascii.encode('\x1b[A\x1b[B\x1b[C\x1b[D'));
    decoder.add(ascii.encode('\x1b[H\x1b[F\x1b[1~\x1b[4~\x1b[3~'));
    decoder.add(ascii.encode('\x1bOA\x1bOH'));

    expect(keys, const [
      SpecialKey(Key.up),
      SpecialKey(Key.down),
      SpecialKey(Key.right),
      SpecialKey(Key.left),
      SpecialKey(Key.home),
      SpecialKey(Key.end),
      SpecialKey(Key.home),
      SpecialKey(Key.end),
      SpecialKey(Key.delete),
      SpecialKey(Key.up),
      SpecialKey(Key.home),
    ]);
  });

  test('a CSI sequence split between reads is joined', () {
    decoder.add([0x1b]);
    decoder.add(ascii.encode('['));
    decoder.add(ascii.encode('A'));

    expect(keys, const [SpecialKey(Key.up)]);
    expect(timers.pending, isEmpty);
  });

  test('an unknown CSI sequence is dropped', () {
    decoder.add(ascii.encode('\x1b[200~x'));

    expect(keys, const [TextKey('x')]);
  });

  test('a lone Esc is a key only after the timeout', () {
    decoder.add([0x1b]);
    expect(keys, isEmpty);

    timers.fire();

    expect(keys, const [SpecialKey(Key.escape)]);
  });

  test('ESC CR is Alt+Enter', () {
    decoder.add([0x1b, 0x0d]);

    expect(keys, const [SpecialKey(Key.altEnter)]);
    expect(timers.pending, isEmpty);
  });

  test('Esc followed by a letter is Esc and the letter', () {
    decoder.add([0x1b, 0x78]);

    expect(keys, const [SpecialKey(Key.escape), TextKey('x')]);
  });

  test('close flushes a pending Esc', () {
    decoder.add([0x1b]);
    decoder.close();

    expect(keys, const [SpecialKey(Key.escape)]);
  });
}
