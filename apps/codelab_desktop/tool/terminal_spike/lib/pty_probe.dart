// Спайк 1.1 add-integrated-terminal (D14, D15): вспомогательный класс проверок PTY.
// Каталог удаляется в задаче 3.9; в `lib/` приложения ничего из него не попадает.
import 'dart:async';
import 'dart:io';

import 'package:pty2/pty2.dart';

/// Сеанс PTY с накоплением вывода: нужен, чтобы тесты ждали маркеры в потоке.
///
/// Почему: `pty2` отдаёт только `Stream<String>`, а проверкам спайка нужно
/// «подождать, пока в выводе появится строка».
class PtyProbe {
  PtyProbe._(this.pty, {this.onData}) {
    _sub = pty.out.listen((chunk) {
      onData?.call(chunk);
      buffer.write(chunk);
      _check();
    });
    exit = pty.exitCode.then((code) {
      exited = true;
      return code;
    });
  }

  /// Стартует [executable] в PTY. `environment` передаётся как есть (pty2
  /// сам добавляет только узкий набор унаследованных ключей, см. итог спайка).
  factory PtyProbe.start(
    String executable,
    List<String> args, {
    String? cwd,
    Map<String, String>? environment,
    void Function(String chunk)? onData,
  }) => PtyProbe._(
    PseudoTerminal.start(
      executable,
      args,
      workingDirectory: cwd,
      environment: environment,
    ),
    onData: onData,
  );

  final PseudoTerminal pty;

  /// Синхронный приёмник чанков (для замеров); `buffer` копит всё независимо.
  final void Function(String chunk)? onData;
  final StringBuffer buffer = StringBuffer();
  late final Future<int> exit;
  bool exited = false;
  late final StreamSubscription<String> _sub;
  final List<(RegExp, Completer<Match>)> _waiters = [];

  void _check() {
    if (_waiters.isEmpty) return; // иначе toString() на каждом чанке — O(n²)
    final text = buffer.toString();
    for (final w in List.of(_waiters)) {
      final m = w.$1.firstMatch(text);
      if (m != null) {
        _waiters.remove(w);
        w.$2.complete(m);
      }
    }
  }

  /// Ждёт совпадения [pattern] во всём накопленном выводе.
  Future<Match> expect(
    RegExp pattern, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final m = pattern.firstMatch(buffer.toString());
    if (m != null) return Future.value(m);
    final c = Completer<Match>();
    _waiters.add((pattern, c));
    return c.future.timeout(
      timeout,
      onTimeout: () =>
          throw TimeoutException('нет $pattern; вывод: ${_tail()}'),
    );
  }

  String _tail() {
    final s = buffer.toString();
    return s.length > 400 ? s.substring(s.length - 400) : s;
  }

  Future<void> close() async {
    pty.kill(ProcessSignal.sigkill);
    await _sub.cancel();
  }
}

/// Ждёт появления процесса с [needle] до [timeout]: login shell стартует долго.
Future<bool> waitAlive(
  String needle, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (processAlive(needle)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

/// Живёт ли процесс, чья командная строка содержит [needle] (через `pgrep -f`).
bool processAlive(String needle) =>
    Process.runSync('pgrep', ['-f', needle]).exitCode == 0;

/// Утверждение без matcher: файл одинаково работает под `dart test` и `flutter test`.
void check(bool cond, String message) {
  if (!cond) throw StateError('check failed: $message');
}
