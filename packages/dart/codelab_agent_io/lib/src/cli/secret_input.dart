import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../secrets/secret_value_checks.dart';

/// Источник значения для `secret set`: stdin процесса (design.md change
/// `add-agent-secret-store`, D8).
///
/// Почему интерфейс: значение секрета можно читать только из stdin (аргумент
/// виден через `ps` и попадает в историю оболочки), а тесту `SecretCommands`
/// нужен фейк — настоящий терминал в тесте недоступен.
///
/// Как использовать: `SecretCommands.set` проверяет всё, что не требует
/// значения, и только потом вызывает [readHidden] (при [hasTerminal]) или
/// [readAll].
abstract interface class SecretInput {
  /// Подключён ли stdin к терминалу: тогда значение вводит человек.
  bool get hasTerminal;

  /// Ввод с терминала: [prompt] — в stderr, эхо выключено, чтение до Enter.
  /// `null` — конец потока (Ctrl+D) без введённых символов. Ввод, продолжившийся
  /// после Enter (вставка нескольких строк), — [MultilineSecretException]:
  /// значение не возвращается, чтобы не сохранить молча только первую строку.
  Future<String?> readHidden(String prompt);

  /// Весь stdin без терминала (канал, файл, `<<<`).
  Future<String> readAll();
}

/// Ввод с терминала продолжился после Enter: вставлено несколько строк.
///
/// Почему исключение: значение секрета — одна строка (D14). Молча сохранить
/// только первую строку вставки значит записать неверный секрет и сообщить об
/// успехе, поэтому `SecretCommands.set` превращает это в код `64` и ничего не
/// сохраняет. Сообщение не содержит введённого текста.
final class MultilineSecretException implements Exception {
  const MultilineSecretException();

  @override
  String toString() => 'MultilineSecretException';
}

/// [SecretInput] над `dart:io` `stdin` (design.md change
/// `add-agent-secret-store`, D8).
///
/// Почему отдельный класс в пакете `dart:io`: ядро не знает терминала (PKG-1),
/// а общий код `codelab` и `codelab-agent` один.
///
/// Для чего: скрытый ввод и защита терминала. Терминал переводится в
/// неканонический режим (`echoMode = false`, `lineMode = false`) и читается
/// побайтово: канонический режим обрезает строку (около 1 КиБ на macOS) и
/// отдаёт вставку нескольких строк по одной, а `readLineSync` не прерывается
/// сигналом. Режимы ВОССТАНАВЛИВАЮТСЯ до отмены подписки на stdin (она закрывает fd 0) и по `SIGINT`, иначе
/// прерванный `secret set` оставил бы терминал пользователя без эха.
/// Подписка на `SIGINT` оформляется ДО выключения эха; `lineMode = false`
/// сохраняет `ISIG`, поэтому Ctrl+C остаётся сигналом, а байт `0x03` на
/// случай платформы без этого обрабатывается как отмена тоже.
///
/// Как использовать: `StdinSecretInput()` — приложения передают его в
/// `SecretCommands.set`. Значение в память читается ограниченно
/// (`maxSecretValueBytes` + запас): бесконечный поток не заполнит память, а
/// длиннее предела значение всё равно отвергнет `SecretAdmin`. Недопустимый
/// UTF-8 — `FormatException`, а продолжение ввода после Enter —
/// [MultilineSecretException]; оба превращает в код `64` `SecretCommands`.
final class StdinSecretInput implements SecretInput {
  /// [drainWindow] и [exitProcess] — только для тестов: окно «тишины» после
  /// Enter и замена `exit` (в тесте процесс завершаться не должен).
  StdinSecretInput({
    Stdin? input,
    IOSink? prompts,
    @visibleForTesting Duration drainWindow = _defaultDrainWindow,
    @visibleForTesting void Function(int code)? exitProcess,
  }) : _stdin = input ?? stdin,
       _prompts = prompts ?? stderr,
       _drainWindow = drainWindow,
       _exit = exitProcess ?? exit;

  final Stdin _stdin;
  final IOSink _prompts;
  final Duration _drainWindow;
  final void Function(int code) _exit;

  /// Сколько ждать продолжения после Enter: вставка многострочного текста
  /// приходит кусками подряд, интерактивный ввод человека — нет.
  static const _defaultDrainWindow = Duration(milliseconds: 50);

  /// Предел «сброса» оставшегося ввода: поток без конца не удержит команду.
  static const _maxDrainBytes = 1024 * 1024;

  /// Запас на завершающий `\r\n` и один лишний байт, чтобы значение сверх
  /// предела осталось сверх предела после усечения.
  static const _readCap = maxSecretValueBytes + 3;

  @override
  bool get hasTerminal => _stdin.hasTerminal;

  @override
  Future<String?> readHidden(String prompt) async {
    _prompts.write(prompt);
    final echo = _stdin.echoMode;
    final line = _stdin.lineMode;
    var restored = false;
    void restore() {
      if (restored) {
        return;
      }
      restored = true;
      try {
        _stdin.lineMode = line;
        _stdin.echoMode = echo;
      } on StdinException {
        // Терминал закрыт: восстанавливать нечего.
      }
    }

    // Подписка ДО выключения эха: сигнал между выключением и подпиской
    // оставил бы терминал без эха. `onError` не даёт неподдерживаемому
    // сигналу стать необработанной асинхронной ошибкой.
    StreamSubscription<ProcessSignal>? interrupt;
    try {
      interrupt = ProcessSignal.sigint.watch().listen((_) {
        // Эхо возвращается до выхода, иначе оболочка пользователя осталась
        // бы без эха.
        restore();
        _prompts.writeln();
        _exit(130);
      }, onError: (Object _) {});
    } on SignalException {
      // Платформа не даёт перехватить сигнал: остаётся `finally`.
    }
    try {
      _stdin.echoMode = false;
      _stdin.lineMode = false;
      return await _readLine(
        restore: restore,
        onCancel: () {
          restore();
          _prompts.writeln();
          _exit(130);
        },
      );
    } finally {
      restore();
      await interrupt?.cancel();
      // Enter не отобразился (эхо выключено): перевод строки возвращает
      // следующий вывод на новую строку.
      _prompts.writeln();
    }
  }

  /// Побайтовое чтение до Enter и «сброс» хвоста до восстановления режимов.
  Future<String?> _readLine({
    required void Function() restore,
    required void Function() onCancel,
  }) async {
    final bytes = <int>[];
    var terminated = false;
    var overflow = false;
    var eof = false;
    var cancelled = false;
    var extra = false;
    var drained = 0;
    Timer? quiet;
    final done = Completer<void>();

    void finish() {
      quiet?.cancel();
      if (!done.isCompleted) {
        done.complete();
      }
    }

    final subscription = _stdin.listen(
      (chunk) {
        for (var i = 0; i < chunk.length; i++) {
          final byte = chunk[i];
          if (terminated || overflow) {
            // Всё, что пришло после Enter или после предела, сбрасывается;
            // после Enter это ещё и признак многострочной вставки.
            drained++;
            if (terminated) {
              extra = true;
            }
            continue;
          }
          switch (byte) {
            case 0x0a || 0x0d:
              terminated = true;
              // Пара `\r\n` — один терминатор.
              if (byte == 0x0d &&
                  i + 1 < chunk.length &&
                  chunk[i + 1] == 0x0a) {
                i++;
              }
            case 0x7f || 0x08:
              _removeLastCodePoint(bytes);
            case 0x04 when bytes.isEmpty:
              eof = true;
              finish();
              return;
            case 0x04:
              break;
            case 0x03:
              cancelled = true;
              finish();
              return;
            default:
              bytes.add(byte);
              if (bytes.length > _readCap) {
                overflow = true;
              }
          }
        }
        if (terminated || overflow) {
          if (drained > _maxDrainBytes) {
            finish();
          } else {
            quiet?.cancel();
            quiet = Timer(_drainWindow, finish);
          }
        }
      },
      onDone: finish,
      onError: (Object error, StackTrace stack) {
        quiet?.cancel();
        if (!done.isCompleted) {
          done.completeError(error, stack);
        }
      },
      cancelOnError: true,
    );
    try {
      await done.future;
    } finally {
      quiet?.cancel();
      // Режимы возвращаются ДО отмены подписки: отмена подписки на stdin
      // закрывает дескриптор 0, и после неё смена режимов даёт EBADF, который
      // `restore` проглатывает, оставляя терминал без эха.
      restore();
      await subscription.cancel();
    }
    if (cancelled) {
      onCancel();
      bytes.clear();
      return null;
    }
    if (extra) {
      bytes.clear();
      throw const MultilineSecretException();
    }
    if (eof || (!terminated && !overflow && bytes.isEmpty)) {
      return null;
    }
    return utf8.decode(bytes, allowMalformed: overflow);
  }

  /// Backspace с эхом выключено: терминал сам ничего не стирает, символ
  /// убираем из буфера целиком (продолжающие байты UTF-8 `10xxxxxx` и
  /// ведущий).
  static void _removeLastCodePoint(List<int> bytes) {
    while (bytes.isNotEmpty && (bytes.last & 0xc0) == 0x80) {
      bytes.removeLast();
    }
    if (bytes.isNotEmpty) {
      bytes.removeLast();
    }
  }

  @override
  Future<String> readAll() async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in _stdin) {
      bytes.add(chunk);
      if (bytes.length > _readCap) {
        break;
      }
    }
    final data = bytes.takeBytes();
    return utf8.decode(data, allowMalformed: data.length > _readCap);
  }
}
