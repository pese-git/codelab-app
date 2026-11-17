// Спайк 1.1: `xterm2_core` в чистом Dart (без Flutter): буфер обмена через OSC и скорость.
//
// Запуск: `fvm dart run bin/core_probe.dart` из каталога спайка. Скрипт не
// импортирует ничего из Flutter: если импорт `package:xterm2_core/` тянет
// `dart:ui`, запуск упадёт — это и есть проверка пункта 1 спайка.
import 'dart:convert';
import 'dart:io';

import 'package:terminal_spike/pty_probe.dart';
import 'package:xterm2_core/xterm2_core.dart';

String _b64(String s) => base64.encode(utf8.encode(s));

/// Тест-последовательности четырёх путей записи/чтения буфера обмена.
Map<String, String> get _sequences => {
  'OSC 52 write': '\x1b]52;c;${_b64('SECRET')}\x07',
  'OSC 52 write primary': '\x1b]52;p;${_b64('SECRET')}\x07',
  'OSC 52 query': '\x1b]52;c;?\x07',
  'OSC 1337 CopyToClipboard':
      '\x1b]1337;CopyToClipboard=\x07SECRET\n\x1b]1337;EndCopy\x07',
  'OSC 5522 write': '\x1b]5522;type=write;${_b64('SECRET')}\x07',
};

/// Прогоняет все последовательности через терминал; возвращает, какие дошли
/// до обработчиков буфера и были ли ответы в `onOutput`.
Map<String, String> _run(
  Terminal Function(List<String> log, List<String> out) make,
) {
  final result = <String, String>{};
  for (final e in _sequences.entries) {
    final log = <String>[];
    final out = <String>[];
    final t = make(log, out);
    t.write(e.value);
    result[e.key] =
        'store/query вызовов: ${log.length}${log.isEmpty ? '' : ' $log'}, onOutput: ${out.length}';
  }
  return result;
}

void _print(String title, Map<String, String> r) {
  stdout.writeln('\n[$title]');
  r.forEach((k, v) => stdout.writeln('  $k -> $v'));
}

Future<void> main() async {
  // A. Настройки из D3/Q13: decoder null, флаги выключены, обработчиков нет.
  _print(
    'A: D3/Q13 (decoder null, флаги off, без обработчиков)',
    _run(
      (log, out) => Terminal(
        allowITerm2ClipboardCapture: false,
        allowKittyClipboard: false,
        onOutput: out.add,
      ),
    ),
  );

  // B. Контроль: те же флаги, но обработчик записи выставлен (как делает TerminalView через ??=).
  _print(
    'B: контроль — decoder null, флаги off, onClipboardStore+onClipboardQuery выставлены',
    _run(
      (log, out) => Terminal(
        allowITerm2ClipboardCapture: false,
        allowKittyClipboard: false,
        onOutput: out.add,
        onClipboardStore: (s, t) => log.add('store($s)'),
        onClipboardQuery: (s) {
          log.add('query($s)');
          return 'CLIPBOARD';
        },
      ),
    ),
  );

  // C. Контроль: флаги по умолчанию (true), обработчики выставлены.
  _print(
    'C: контроль — флаги по умолчанию, обработчики выставлены',
    _run(
      (log, out) => Terminal(
        onOutput: out.add,
        onClipboardStore: (s, t) => log.add('store($s)'),
        onClipboardQuery: (s) {
          log.add('query($s)');
          return 'CLIPBOARD';
        },
      ),
    ),
  );

  // D. Рекомендуемая защита: decoder отклоняет, store — пустой, query — null.
  _print(
    'D: decoder возвращает null, store no-op, query null, флаги off',
    _run(
      (log, out) => Terminal(
        allowITerm2ClipboardCapture: false,
        allowKittyClipboard: false,
        clipboardDecoder: (_, _) => null,
        onOutput: out.add,
        onClipboardStore: (s, t) => log.add('store($s)'),
        onClipboardQuery: (s) {
          log.add('query($s)');
          return null;
        },
      ),
    ),
  );

  // Скорость: синтетика одним куском и порциями по 4 КБ.
  final payload = 'y\n' * 200000;
  for (final chunk in [payload.length, 4096, 65536]) {
    final t = Terminal(maxLines: 10000);
    final sw = Stopwatch()..start();
    var worst = Duration.zero;
    for (var i = 0; i < payload.length; i += chunk) {
      final end = (i + chunk).clamp(0, payload.length);
      final s2 = Stopwatch()..start();
      t.write(payload.substring(i, end));
      if (s2.elapsed > worst) worst = s2.elapsed;
    }
    stdout.writeln(
      '\nyes×200000 синтетика, порции ${chunk == payload.length ? 'целиком' : chunk}: '
      'всего ${sw.elapsedMilliseconds} мс, худший write ${worst.inMilliseconds} мс, '
      'строк в буфере ${t.buffer.lines.length}',
    );
  }

  // Скорость: настоящий вывод `yes | head -n 200000` из PTY в модель.
  for (final cmd in [
    'yes | head -n 200000',
    'seq 1 200000',
    'yes "\x1b[31mred\x1b[0m line with colour and some text" | head -n 100000',
  ]) {
    final t = Terminal(maxLines: 10000);
    final sw = Stopwatch()..start();
    var chunks = 0;
    var bytes = 0;
    var worst = Duration.zero;
    var total = Duration.zero;
    final p = PtyProbe.start(
      '/bin/sh',
      ['-c', cmd],
      onData: (s) {
        chunks++;
        bytes += s.length;
        final s2 = Stopwatch()..start();
        t.write(s);
        total += s2.elapsed;
        if (s2.elapsed > worst) worst = s2.elapsed;
      },
    );
    await p.exit;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    stdout.writeln(
      'PTY `${cmd.length > 40 ? '${cmd.substring(0, 40)}…' : cmd}`: итого ${sw.elapsedMilliseconds} мс, '
      'в модели ${total.inMilliseconds} мс, чанков $chunks (${bytes ~/ 1024} КБ), худший write ${worst.inMilliseconds} мс',
    );
  }
  exit(0);
}
