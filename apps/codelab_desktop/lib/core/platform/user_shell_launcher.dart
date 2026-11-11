import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:pty2/pty2.dart';

/// Причина, по которой shell терминала не удалось запустить.
///
/// Почему: `pty2` не бросает исключений, если нет исполняемого файла или
/// папки: `fork` проходит, а ребёнок сразу выходит с кодом `1` или `-1`
/// (D15, п. 3). Пользователю нужна внятная причина, а не «вкладка тут же
/// вышла», поэтому типизированную ошибку (`error-handling.md`) адаптер
/// формирует сам, проверкой до `start` (D2, «Ошибка старта»).
///
/// Для чего: `TerminalTabsCubit` превращает её в статус вкладки `failed`.
///
/// Как использовать: ловить `on UserShellStartFailure` у
/// [UserShellLauncher.start]. В тексте ошибки НЕТ пути, окружения и вывода
/// (D9: содержимое и пути не попадают в журнал и интерфейс).
enum UserShellStartFailure implements Exception {
  /// Исполняемого файла нет, это не файл или у него нет бита исполнения.
  shellNotFound('Shell not found'),

  /// Рабочей папки нет.
  folderNotFound('Folder not found'),

  /// `pty2` не смог создать псевдотерминал или процесс (`PtyException` из
  /// `openpty`, `fork` и т. п.). Текст пакета может содержать пути и не
  /// показывается.
  ptyUnavailable('Terminal is unavailable');

  const UserShellStartFailure(this.message);

  /// Короткий англоязычный текст для вкладки; без путей.
  final String message;

  @override
  String toString() => 'UserShellStartFailure: $message';
}

/// Запущенный shell пользователя в псевдотерминале.
///
/// Почему: `TerminalTabsCubit` и тесты не должны знать про `pty2` (D2) —
/// порт повторяет только то, что `pty2` действительно умеет (D15, п. 5).
///
/// Для чего: один процесс одной вкладки терминала.
///
/// Как использовать: слушать [output] ровно один раз; ввод — [write]; размер
/// от `TerminalView` — [resize]; закрытие вкладки — [hangUp], через 2 с без
/// выхода [kill] (D4). Все методы после выхода процесса безопасны (no-op).
abstract interface class UserShell {
  /// Вывод процесса: `pty2` отдаёт уже декодированный UTF-8, байтов нет.
  Stream<String> get output;

  /// Отправляет ввод пользователя процессу.
  void write(String data);

  /// Сообщает процессу новый размер терминала в колонках и строках.
  void resize(int columns, int rows);

  /// Завершается при выходе процесса. `null` — код неизвестен (D4,
  /// «Код выхода»): ни тесты, ни логика на него не опираются.
  ///
  /// Future может завершиться ОШИБКОЙ (сбой ожидания выхода в `pty2`): адаптер
  /// её не глушит, обрабатывает Cubit — вкладка становится `exited(null)`,
  /// событие `terminal.exit_wait_failed` (D4, D9). После любого завершения
  /// (значением или ошибкой) методы shell — no-op.
  Future<int?> get exitCode;

  /// `SIGHUP`, как при закрытии окна терминала. Любой сигнал `pty2` сразу
  /// закрывает PTY-мастер: после него вывод не приходит, о выходе говорит
  /// только [exitCode].
  void hangUp();

  /// `SIGKILL`: на процесс, игнорирующий `SIGHUP`, действует только он (D15,
  /// п. 6).
  void kill();
}

/// Порт запуска shell пользователя в PTY.
///
/// Почему: PTY — нативный API и infrastructure (`AGENTS.md` §11); порт нужен
/// не ради второй реализации, а ради изоляции нативного пакета и независимого
/// теста `TerminalTabsCubit` с fake (D2). Лежит в `core/platform/` рядом с
/// другими платформенными портами app (образец — `DockLayoutStore`).
///
/// Для чего: единственная точка, через которую app создаёт процессы
/// терминала; `Platform.is*` есть только в реализации (D12).
///
/// Как использовать: composition root регистрирует [PtyUserShellLauncher];
/// Cubit проверяет [isSupported] и вызывает [start].
abstract interface class UserShellLauncher {
  /// `false` — панель Terminal, `/terminal` и Ctrl+` не предлагаются (D12,
  /// A13, шаг 6).
  bool get isSupported;

  /// Выбирает shell пользователя по правилам D5 для текущей платформы:
  /// `$SHELL` → `/bin/zsh` → `/bin/bash` → `/bin/sh` с `-l`, на Windows —
  /// `%ComSpec%`. `null` — подходящего shell нет (вкладка станет `failed`).
  UserShellCommand? resolveShell();

  /// Запускает [executable] с [arguments] в [workingDirectory].
  ///
  /// Предусловие: [executable] — АБСОЛЮТНЫЙ путь (его даёт [resolveShell]).
  /// Относительный путь `pty2` искал бы от папки процесса app, а не от
  /// [workingDirectory]; такой путь — [UserShellStartFailure.shellNotFound].
  ///
  /// [environment] — ДОБАВКИ поверх окружения app (Q9, D5): реализация
  /// передаёт процессу окружение app целиком, затем [environment], затем
  /// `TERM` и `COLORTERM`. [columns] и [rows] — начальный размер.
  ///
  /// Бросает [UserShellStartFailure]: файла или папки нет, либо PTY не создан.
  Future<UserShell> start({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required Map<String, String> environment,
    required int columns,
    required int rows,
  });
}

/// Переводит код выхода `pty2` в код порта.
///
/// Почему: для быстро завершившегося процесса `pty2` иногда сообщает `-1`
/// вместо настоящего кода, и это зависит от тайминга (D15, п. 4; D4).
///
/// Для чего: `-1` — «код неизвестен» (`null`); настоящий код остаётся как есть.
int? userShellExitCode(int raw) => raw == -1 ? null : raw;

/// Команда запуска shell: исполняемый файл и аргументы.
typedef UserShellCommand = ({String executable, List<String> arguments});

/// Выбирает shell пользователя (D5, Q9; спецификация `integrated-terminal`
/// «Терминал — настоящий псевдотерминал»).
///
/// Почему: app из Finder получает минимальное окружение, а login shell (`-l`)
/// восстанавливает `PATH` из профиля пользователя (`apps/codelab_desktop/
/// AGENTS.md`, «Секреты»).
///
/// Для чего: чистая функция без обращения к платформе — [environment],
/// [isWindows] и [isExecutable] передаёт вызывающий, поэтому порядок выбора
/// проверяется тестом на fake-окружении, без реального `$SHELL`.
///
/// Порядок на POSIX: `$SHELL` (только абсолютный путь и [isExecutable]),
/// затем `/bin/zsh`, `/bin/bash`, `/bin/sh`; аргумент `-l`. На Windows —
/// `%ComSpec%` без аргументов (ветка не проверена на Windows, D12).
/// Ничего не подошло — `null`.
UserShellCommand? chooseUserShell({
  required Map<String, String> environment,
  required bool isWindows,
  required bool Function(String path) isExecutable,
}) {
  if (isWindows) {
    final comSpec = environment['ComSpec'];
    if (comSpec == null || comSpec.isEmpty || !isExecutable(comSpec)) {
      return null;
    }
    return (executable: comSpec, arguments: const <String>[]);
  }
  final fromEnvironment = environment['SHELL'];
  final candidates = [
    if (fromEnvironment != null && p.posix.isAbsolute(fromEnvironment))
      fromEnvironment,
    '/bin/zsh',
    '/bin/bash',
    '/bin/sh',
  ];
  for (final path in candidates) {
    if (isExecutable(path)) return (executable: path, arguments: const ['-l']);
  }
  return null;
}

/// Функция запуска PTY; шов для теста предпроверки (подставляется вместо
/// `PseudoTerminal.start`, чтобы убедиться, что при ошибке предпроверки
/// пакет не вызывается).
@visibleForTesting
typedef PtyStart =
    PseudoTerminal Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });

PseudoTerminal _defaultPtyStart(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => PseudoTerminal.start(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
);

/// Адаптер [UserShellLauncher] на `pty2` 0.8.1 (D2, D11, D15).
///
/// Почему: выбор пакета сделал спайк 1.1; native assets `pty2` собираются под
/// `flutter test`, поэтому адаптер проверяется контрактным тестом на Dart VM.
///
/// Для чего: проверка файла и папки до `start`, окружение app целиком,
/// начальный размер, перевод кода выхода.
///
/// Как использовать: `PtyUserShellLauncher()`; [startPty] — только для тестов.
final class PtyUserShellLauncher implements UserShellLauncher {
  PtyUserShellLauncher({@visibleForTesting PtyStart? startPty})
    : _startPty = startPty ?? _defaultPtyStart;

  final PtyStart _startPty;

  /// `true` там, где у `pty2` есть бэкенд. App сейчас собирается только под
  /// macOS; Linux и Windows не проверены (D12). Единственное место с
  /// `Platform.is*` вместе с [resolveShell] и [_isExecutableFile].
  @override
  bool get isSupported =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  @override
  UserShellCommand? resolveShell() => chooseUserShell(
    environment: Platform.environment,
    isWindows: Platform.isWindows,
    isExecutable: _isExecutableFile,
  );

  @override
  Future<UserShell> start({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required Map<String, String> environment,
    required int columns,
    required int rows,
  }) async {
    // Гонка «удалили между проверкой и start» даёт обычный мгновенный выход
    // процесса (D2): вкладка станет exited, как при любом выходе shell.
    if (!p.isAbsolute(executable) || !_isExecutableFile(executable)) {
      throw UserShellStartFailure.shellNotFound;
    }
    if (!await Directory(workingDirectory).exists()) {
      throw UserShellStartFailure.folderNotFound;
    }

    // Без environment pty2 даёт ребёнку узкий набор ключей (D15, п. 2), а
    // терминал — собственный shell пользователя: урезанное окружение сломало
    // бы его инструменты (Q9, D5). Порядок важен: TERM и COLORTERM выставляет
    // сам терминал, их нельзя переопределить добавками.
    final PseudoTerminal pty;
    try {
      pty = _startPty(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: {
          ...Platform.environment,
          ...environment,
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
        },
      );
    } on Exception {
      // Штатный отказ платформы: `PtyException`, на Windows ещё
      // `WindowsException`, `FormatException`, `HttpException`. Текст пакета
      // может содержать пути (D9), поэтому наружу — только вариант. `Error`
      // (нет нативной библиотеки, `StateError`) не ловим: это дефект окружения
      // или программы, он не должен выглядеть как отказ терминала.
      throw UserShellStartFailure.ptyUnavailable;
    }
    // `start` пакета размера не принимает: начальный размер выставляется
    // сразу после старта; если shell успел прочитать размер раньше, он
    // получит SIGWINCH. Сбой здесь — отдельно от старта: процесс уже
    // запущен, и без `kill` он остался бы без владельца. Как и при старте,
    // `Exception` — отказ платформы (`ptyUnavailable`), а `Error` — дефект:
    // он пробрасывается как есть, чтобы не выглядеть отказом терминала (D2).
    try {
      pty.resize(columns, rows);
    } on Exception {
      pty.kill(ProcessSignal.sigkill);
      throw UserShellStartFailure.ptyUnavailable;
    } on Error {
      pty.kill(ProcessSignal.sigkill);
      rethrow;
    }
    return _PtyUserShell(pty);
  }

  /// Эвристика предпроверки: это файл и у него выставлен ЛЮБОЙ бит `x`
  /// (`mode & 0x49`). Она не доказывает, что запуск разрешён именно этому
  /// пользователю; при отказе по правам процесс сразу выходит, и вкладка
  /// становится `exited`, как при любом выходе shell.
  ///
  /// Ветка Windows (только «это файл») не проверена на Windows (D12).
  static bool _isExecutableFile(String path) {
    final stat = FileStat.statSync(path);
    if (stat.type != FileSystemEntityType.file) return false;
    if (Platform.isWindows) return true;
    return stat.mode & 0x49 != 0; // --x--x--x
  }
}

final class _PtyUserShell implements UserShell {
  _PtyUserShell(this._pty) {
    // Флаг ставится на обоих путях, ошибка уходит дальше: её обрабатывает
    // Cubit (D4), адаптер без логгера (D9).
    exitCode = _pty.exitCode
        .whenComplete(() => _exited = true)
        .then(userShellExitCode);
  }

  final PseudoTerminal _pty;

  /// Процесс завершён. `pty2` делает `waitpid` в воркере и сам флаг в главном
  /// изоляте не ставит, поэтому сигнал или запись после выхода могли бы уйти
  /// процессу, получившему тот же pid. После выхода все методы — no-op (D4).
  bool _exited = false;

  @override
  late final Future<int?> exitCode;

  @override
  Stream<String> get output => _pty.out;

  @override
  void write(String data) {
    if (!_exited) _pty.write(data);
  }

  @override
  void resize(int columns, int rows) {
    if (!_exited) _pty.resize(columns, rows);
  }

  @override
  void hangUp() {
    if (!_exited) _pty.kill(ProcessSignal.sighup);
  }

  @override
  void kill() {
    if (!_exited) _pty.kill(ProcessSignal.sigkill);
  }
}
