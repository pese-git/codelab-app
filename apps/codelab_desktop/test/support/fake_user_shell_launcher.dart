import 'dart:async';

import 'package:codelab_desktop/core/platform/user_shell_launcher.dart';

/// Управляемый [UserShell] для тестов `TerminalTabsCubit` и панели терминала.
///
/// Почему: настоящий PTY нужен только контрактному тесту адаптера
/// (`user_shell_launcher_test.dart`); логику вкладок проверяют на двойнике,
/// которым тест сам "выводит" данные и "завершает" процесс.
///
/// Для чего: хранит всё, что Cubit сделал с процессом ([written], [hangUps],
/// [kills], [resizes]), и позволяет тесту управлять [output] и [exitCode].
///
/// Как использовать: `shell.emit('data')` шлёт вывод; `shell.exit(3)`
/// завершает процесс; `shell.failExit(StateError('x'))` завершает ожидание
/// выхода ошибкой, как адаптер при сбое `pty2` (D4).
final class FakeUserShell implements UserShell {
  FakeUserShell({this.exitsOnHangUp = false, this.exitsOnKill = true});

  /// `true` — процесс выходит на `SIGHUP` сам (отзывчивый shell).
  final bool exitsOnHangUp;

  /// `false` — `kill` лишь считается, процесс остаётся «живым» (проверка, что
  /// событие о принудительном закрытии пишется сразу после `kill`, а не по
  /// выходу процесса, D4, D9).
  final bool exitsOnKill;

  /// Если не `null`, `hangUp`/`kill` бросают его (после подсчёта вызова):
  /// сбой сигнала одной вкладки не должен оставлять живыми другие.
  Object? hangUpError;
  Object? killError;

  final StreamController<String> _output = StreamController<String>();
  final Completer<int?> _exit = Completer<int?>();

  final List<String> written = [];
  final List<(int, int)> resizes = [];
  int hangUps = 0;
  int kills = 0;

  /// Есть ли у вывода подписчик (Cubit отписывается после `exited`, D4).
  bool get hasOutputListener => _output.hasListener;

  /// Завершился ли [exitCode] (значением или ошибкой).
  bool get exited => _exit.isCompleted;

  void emit(String data) => _output.add(data);

  /// Завершает процесс значением; `null` — код неизвестен (D4).
  void exit([int? code = 0]) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  /// Завершает ожидание выхода ошибкой (сбой isolate или порта `pty2`).
  void failExit(Object error) {
    // Как адаптер: ошибка не «необработанная», пока Cubit не подписался.
    _exit.future.ignore();
    if (!_exit.isCompleted) _exit.completeError(error);
  }

  @override
  Stream<String> get output => _output.stream;

  @override
  Future<int?> get exitCode => _exit.future;

  @override
  void write(String data) => written.add(data);

  @override
  void resize(int columns, int rows) => resizes.add((columns, rows));

  @override
  void hangUp() {
    hangUps++;
    final error = hangUpError;
    if (error != null) throw error;
    if (exitsOnHangUp) exit(0);
  }

  @override
  void kill() {
    kills++;
    final error = killError;
    if (error != null) throw error;
    if (exitsOnKill) exit(null);
  }
}

/// Один вызов [UserShellLauncher.start] со всеми аргументами.
typedef FakeStartCall = ({
  String executable,
  List<String> arguments,
  String workingDirectory,
  Map<String, String> environment,
  int columns,
  int rows,
});

/// Старт, ожидающий решения теста (режим [FakeUserShellLauncher.deferStarts]).
final class PendingStart {
  PendingStart(this.call);

  final FakeStartCall call;
  final Completer<UserShell> _completer = Completer<UserShell>();

  /// Завершает старт процессом [shell]; без аргумента создаётся новый.
  FakeUserShell complete([FakeUserShell? shell]) {
    final result = shell ?? FakeUserShell();
    _completer.complete(result);
    return result;
  }

  /// Завершает старт ошибкой — `UserShellStartFailure` или любым объектом
  /// (дефект адаптера, D4, «Ошибка старта в Cubit»).
  void fail(Object error) => _completer.completeError(error);
}

/// Двойник порта [UserShellLauncher] (D2) для тестов app.
///
/// Почему: Cubit, панель и приёмка жизненного цикла не должны зависеть от
/// нативного `pty2` (D13); этим двойником пользуются тесты 2.1, 2.5, 2.9, 3.x.
///
/// Для чего: настраиваемые [isSupported] и [shell] (результат
/// `resolveShell()`), журнал [starts], созданные процессы [shells], режим
/// отложенных стартов и подмена ошибки старта.
///
/// Как использовать: по умолчанию `start` сразу возвращает новый
/// [FakeUserShell]. [deferStarts] кладёт вызов в [pending] — тест завершает
/// его сам (`complete`/`fail`). [startError] заставляет `start` бросить объект.
final class FakeUserShellLauncher implements UserShellLauncher {
  FakeUserShellLauncher({
    this.isSupported = true,
    this.shell = const (executable: '/bin/zsh', arguments: ['-l']),
  });

  @override
  bool isSupported;

  /// Результат [resolveShell]; `null` — подходящего shell нет.
  UserShellCommand? shell;

  /// Если не `null`, `start` бросает его.
  Object? startError;

  /// Складывать вызовы `start` в [pending], а не завершать сразу.
  bool deferStarts = false;

  /// Новые процессы отвечают на `SIGHUP` выходом (см. [FakeUserShell]).
  bool shellsExitOnHangUp = false;

  int resolveShellCalls = 0;
  final List<FakeStartCall> starts = [];
  final List<FakeUserShell> shells = [];
  final List<PendingStart> pending = [];

  @override
  UserShellCommand? resolveShell() {
    resolveShellCalls++;
    return shell;
  }

  @override
  Future<UserShell> start({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required Map<String, String> environment,
    required int columns,
    required int rows,
  }) {
    final call = (
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      columns: columns,
      rows: rows,
    );
    starts.add(call);
    final error = startError;
    if (error != null) return Future<UserShell>.error(error);
    if (deferStarts) {
      final start = PendingStart(call);
      pending.add(start);
      return start._completer.future.then((s) {
        if (s is FakeUserShell) shells.add(s);
        return s;
      });
    }
    final created = FakeUserShell(exitsOnHangUp: shellsExitOnHangUp);
    shells.add(created);
    return Future<UserShell>.value(created);
  }
}
