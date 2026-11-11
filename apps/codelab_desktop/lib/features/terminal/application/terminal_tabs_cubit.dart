import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart' show DirectoryExists;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:xterm2_core/xterm2_core.dart';

import '../../../core/platform/user_shell_launcher.dart';
import 'terminal_model.dart';
import 'terminal_owner.dart';
import 'terminal_tab.dart';
import 'terminal_tabs_state.dart';

/// Размер части записи в эмулятор по умолчанию (D3, «Запись порциями»).
const terminalWriteChunkSize = 4096;

/// Внутренняя запись реестра: процесс, модель и буфер вкладки (не состояние).
final class _Entry {
  _Entry(this.id, this.owner, this.terminal);

  final String id;
  final TerminalOwner owner;
  final Terminal terminal;
  UserShell? shell;
  StreamSubscription<String>? outputSub;
  TerminalTabStatus status = const TerminalTabStarting();

  /// Вкладку закрыли (или идёт `closeAll`): из состояния её уже нет.
  bool closed = false;
  bool exited = false;
  bool forced = false;
  bool closeLogged = false;
  Timer? killTimer;
  final Completer<void> done = Completer<void>();

  /// Накопленный вывод, ещё не записанный в [terminal]; [offset] — позиция в
  /// первой строке (нарезка без копирования остатка).
  final List<String> pending = [];
  int offset = 0;
}

/// Единственный владелец вкладок терминала и их процессов (D3, D4, D5).
///
/// Почему: процессы переживают закрытие панели, смену проекта и сессии
/// (Q18), поэтому владелец живёт в root scope, а не в виджете.
///
/// Для чего: вкладки по владельцу `TerminalOwner(profileId, sessionId)`,
/// запуск shell через порт [UserShellLauncher], закрытие `hangUp` → 2 с →
/// `kill`, `closeAll()` при выходе, буфер вывода с записью порциями. Cubit
/// только отображает `WorkspaceState` (источник — `ClientWorkspace`) и
/// решения политики не принимает: что опасно, решает агент (D8).
///
/// Как использовать: `newTab()` создаёт вкладку активной сессии; запись из
/// буфера в модели делает presentation-объект сброса на кадре через
/// [flushOutput] (бюджет времени — его забота, тест 2.7); `closeAll()` зовёт
/// выход из app; [close] только отписывает Cubit (процессам сигналов не шлёт,
/// их завершает `closeAll`). Содержимое терминала, пути и окружение в журнал
/// не пишутся (D9).
class TerminalTabsCubit extends Cubit<TerminalTabsState> {
  TerminalTabsCubit({
    required ClientWorkspace workspace,
    required UserShellLauncher launcher,
    required DirectoryExists directoryExists,
    required Logger logger,
    TerminalModelFactory modelFactory = terminalModel,
    Duration hangUpGrace = const Duration(seconds: 2),
    Duration closeAllGrace = const Duration(seconds: 3),
    int writeChunkSize = terminalWriteChunkSize,
  }) : _workspace = workspace,
       _launcher = launcher,
       _directoryExists = directoryExists,
       _logger = logger,
       _modelFactory = modelFactory,
       _hangUpGrace = hangUpGrace,
       _closeAllGrace = closeAllGrace,
       _chunk = writeChunkSize,
       super(const TerminalTabsState()) {
    _resolveOwner(workspace.current);
    _publish();
    _workspaceSub = workspace.state.listen((next) {
      _resolveOwner(next);
      _publish();
    });
  }

  final ClientWorkspace _workspace;
  final UserShellLauncher _launcher;
  final DirectoryExists _directoryExists;
  final Logger _logger;
  final TerminalModelFactory _modelFactory;
  final Duration _hangUpGrace;
  final Duration _closeAllGrace;
  final int _chunk;

  late final StreamSubscription<WorkspaceState> _workspaceSub;

  /// Есть ли PTY на этой платформе (D12): без него панели Terminal нет.
  /// Отдаётся из порта, чтобы виджеты не знали про платформу (`AGENTS.md` §11).
  bool get isSupported => _launcher.isSupported;

  /// Зовётся, когда в буфере вкладки появился вывод, ещё не записанный в
  /// модель. Для чего: presentation-объект сброса заказывает кадр, не опрашивая
  /// Cubit (D3). Cubit ничего не знает о кадрах; `null` — никто не слушает.
  void Function()? onPendingOutput;

  /// Владелец, запомненный при активации сессии (D5): профиль не
  /// пересобирается, пока `activeSessionId` тот же.
  TerminalOwner? _remembered;
  TerminalOwner? _shown;

  final Map<TerminalOwner, List<_Entry>> _entries = {};
  final Map<TerminalOwner, String?> _active = {};
  final List<_Entry> _closing = [];
  int _seq = 0;
  bool _shuttingDown = false;
  Future<void>? _closeAllFuture;
  bool _disclosureShown = false;

  // --- владелец ---

  void _resolveOwner(WorkspaceState ws) {
    final id = ws.activeSessionId;
    // Сессия без `SessionHandle` — «нет сессии» (Q17).
    if (id == null || _workspace.session(id) == null) {
      _remembered = null;
      _shown = null;
      return;
    }
    final remembered = _remembered;
    if (remembered != null && remembered.sessionId == id) {
      _shown = remembered;
      return;
    }
    final profile = ws.profile;
    if (profile == null) {
      _remembered = null;
      _shown = null;
      return;
    }
    _remembered = _shown = TerminalOwner(profile.id, id);
  }

  void _publish() {
    if (isClosed) return;
    final owner = _shown;
    emit(
      TerminalTabsState(
        owner: owner,
        tabs: owner == null
            ? const []
            : [
                for (final e in _entries[owner] ?? const <_Entry>[])
                  TerminalTab(
                    id: e.id,
                    title: 'Terminal ${e.id.substring(1)}',
                    status: e.status,
                  ),
              ],
        activeTabId: owner == null ? null : _active[owner],
        disclosureShown: _disclosureShown,
      ),
    );
  }

  // --- действия пользователя ---

  /// Создаёт вкладку в активной сессии и запускает в ней shell.
  ///
  /// Без активной сессии, после `closeAll()` и после [close] ничего не
  /// делает (Q17). Id вкладки выдаётся синхронно, до первого `await`:
  /// каждое действие даёт ровно одну вкладку (D4).
  Future<void> newTab() async {
    final owner = _shown;
    if (isClosed || _shuttingDown || owner == null) return;
    final handle = _workspace.session(owner.sessionId);
    if (handle == null) return;
    // Снимок папки в момент создания (Q19).
    final cwd = handle.cwd;

    final id = 't${++_seq}';
    final entry = _Entry(
      id,
      owner,
      _modelFactory(
        onOutput: (data) => _onModelOutput(id, data),
        onResize: (columns, rows) => _onModelResize(id, columns, rows),
      ),
    );
    (_entries[owner] ??= []).add(entry);
    _active[owner] = id;
    _publish();

    final command = _launcher.resolveShell();
    if (command == null) {
      _fail(entry, UserShellStartFailure.shellNotFound);
      return;
    }
    final bool exists;
    try {
      exists = await _directoryExists(cwd);
    } on Object catch (error) {
      _failStart(entry, UserShellStartFailure.ptyUnavailable, error: error);
      return;
    }
    if (entry.closed || _shuttingDown) return;
    if (!exists) {
      _fail(entry, UserShellStartFailure.folderNotFound);
      return;
    }

    const columns = 80;
    const rows = 24;
    final UserShell shell;
    try {
      shell = await _launcher.start(
        executable: command.executable,
        arguments: command.arguments,
        workingDirectory: cwd,
        environment: const {},
        columns: columns,
        rows: rows,
      );
    } on UserShellStartFailure catch (failure) {
      _failStart(entry, failure);
      return;
    } on Object catch (error) {
      // Дефект адаптера или неожиданное исключение: наружу не выходит, в
      // журнал — только тип (D4, «Ошибка старта в Cubit»).
      _failStart(entry, UserShellStartFailure.ptyUnavailable, error: error);
      return;
    }

    if (isClosed || entry.closed || _shuttingDown) {
      // Stale result (`concurrency.md` §10): вкладки уже нет. На `exitCode`
      // подписываемся с `onError`, иначе его ошибка ушла бы в зону мимо
      // `terminal.exit_wait_failed`.
      shell.kill();
      unawaited(
        shell.exitCode.then<void>(
          (_) {},
          onError: (Object error) => _logExitWaitFailed(entry.id, error),
        ),
      );
      return;
    }

    entry.shell = shell;
    entry.status = const TerminalTabRunning();
    entry.outputSub = shell.output.listen((data) {
      entry.pending.add(data);
      onPendingOutput?.call();
    });
    unawaited(
      shell.exitCode.then<void>(
        (code) => _onExit(entry, code),
        onError: (Object error) => _onExitError(entry, error),
      ),
    );
    _logger.info(
      'terminal.tab_opened',
      context: {
        'tab_id': entry.id,
        'session_id': owner.sessionId.value,
        'shell': p.basename(command.executable),
        'columns': columns,
        'rows': rows,
      },
    );
    _publish();
  }

  void selectTab(String id) {
    final owner = _shown;
    if (owner == null) return;
    if (!(_entries[owner] ?? const <_Entry>[]).any((e) => e.id == id)) return;
    _active[owner] = id;
    _publish();
  }

  /// Скрывает предупреждение до конца жизни Cubit (Q7).
  void acknowledgeDisclosure() {
    if (_disclosureShown) return;
    _disclosureShown = true;
    _publish();
  }

  /// Открытие панели действием пользователя (D1): при активной сессии без
  /// вкладок создаёт одну. Восстановленный док его не зовёт и shell не
  /// запускает; без сессии, при наличии вкладок и после `closeAll()` — no-op.
  Future<void> ensureTab() async {
    if (state.hasSession && state.tabs.isEmpty) await newTab();
  }

  /// Закрывает вкладку: она исчезает сразу, процесс получает `hangUp`, через
  /// [hangUpGrace] без выхода — `kill` (D4). Повторный вызов — no-op.
  void closeTab(String id) {
    for (final entries in _entries.values) {
      for (final entry in entries) {
        if (entry.id != id) continue;
        if (entry.closed) return;
        entries.remove(entry);
        _detach(entry);
        final shell = entry.shell;
        if (shell == null || entry.exited) {
          // Нечего сигналить: старт в полёте (поздний процесс убьёт
          // `newTab`), процесс уже вышел или не запустился.
          entry.done.isCompleted ? null : entry.done.complete();
          if (shell != null) _logClosed(entry);
        } else {
          _closing.add(entry);
          shell.hangUp();
          entry.killTimer = Timer(_hangUpGrace, () {
            if (entry.exited) return;
            entry.forced = true;
            shell.kill();
            _logClosed(entry);
          });
        }
        final owner = entry.owner;
        if (_active[owner] == id) {
          _active[owner] = entries.isEmpty ? null : entries.last.id;
        }
        _publish();
        return;
      }
    }
  }

  /// Выход из app: `hangUp` всем, через [closeAllGrace] `kill` оставшимся;
  /// новые вкладки после вызова не создаются, повтор — без действий (D4).
  Future<void> closeAll() => _closeAllFuture ??= _closeAll();

  Future<void> _closeAll() async {
    _shuttingDown = true;
    final live = <_Entry>[];
    for (final entry in [
      for (final list in _entries.values) ...list,
      ..._closing,
    ]) {
      final already = entry.closed;
      _detach(entry);
      final shell = entry.shell;
      if (shell == null || entry.exited) continue;
      entry.killTimer?.cancel();
      if (!already) shell.hangUp();
      live.add(entry);
    }
    _entries.clear();
    _active.clear();
    _publish();

    if (live.isEmpty) {
      _logger.info(
        'terminal.close_all',
        context: {'count': 0, 'forced': false},
      );
      return;
    }
    var forced = false;
    await Future.wait(live.map((e) => e.done.future)).timeout(
      _closeAllGrace,
      onTimeout: () {
        forced = true;
        for (final entry in live) {
          if (!entry.exited) entry.shell!.kill();
        }
        return <void>[];
      },
    );
    _logger.info(
      'terminal.close_all',
      context: {'count': live.length, 'forced': forced},
    );
  }

  // --- вывод ---

  /// Есть ли вывод, ещё не записанный в модели видимых вкладок.
  bool get hasPendingOutput =>
      _entries.values.any((list) => list.any((e) => e.pending.isNotEmpty));

  /// Записывает накопленный вывод в модели частями не больше размера части;
  /// остаток остаётся на следующий вызов (D3). [canContinue] спрашивается
  /// перед каждой частью — так объект сброса держит бюджет кадра. Возвращает
  /// число записанных частей.
  int flushOutput({bool Function()? canContinue}) {
    var written = 0;
    for (final list in _entries.values) {
      for (final entry in list) {
        while (entry.pending.isNotEmpty) {
          if (canContinue != null && !canContinue()) return written;
          entry.terminal.write(_takeChunk(entry));
          written++;
        }
      }
    }
    return written;
  }

  String _takeChunk(_Entry entry) {
    final buffer = StringBuffer();
    var size = 0;
    while (entry.pending.isNotEmpty && size < _chunk) {
      final head = entry.pending.first;
      final take = (head.length - entry.offset).clamp(0, _chunk - size);
      buffer.write(head.substring(entry.offset, entry.offset + take));
      size += take;
      entry.offset += take;
      if (entry.offset >= head.length) {
        entry.pending.removeAt(0);
        entry.offset = 0;
      }
    }
    return buffer.toString();
  }

  /// Модель вкладки для виджета; `null` — вкладки нет.
  Terminal? terminalOf(String id) {
    for (final list in _entries.values) {
      for (final entry in list) {
        if (entry.id == id) return entry.terminal;
      }
    }
    return null;
  }

  // --- события моделей и процессов ---

  _Entry? _find(String id) {
    for (final list in _entries.values) {
      for (final entry in list) {
        if (entry.id == id) return entry;
      }
    }
    return null;
  }

  void _onModelOutput(String id, String data) {
    final entry = _find(id);
    if (entry == null || entry.closed || entry.exited) return;
    // Ввод в вышедшую вкладку игнорируется (D4): `shell` есть только у
    // работающей.
    if (entry.status is TerminalTabRunning) entry.shell?.write(data);
  }

  void _onModelResize(String id, int columns, int rows) {
    final entry = _find(id);
    if (entry == null || entry.closed || entry.exited) return;
    if (entry.status is TerminalTabRunning) {
      entry.shell?.resize(columns, rows);
    }
  }

  void _onExit(_Entry entry, int? code) {
    if (isClosed || entry.exited) return;
    _finishExit(entry);
    if (entry.closed) {
      _logClosed(entry);
      return;
    }
    entry.status = TerminalTabExited(code);
    entry.pending.add(
      code == null
          ? '\r\n[Process exited]\r\n'
          : '\r\n[Process exited with code $code]\r\n',
    );
    onPendingOutput?.call();
    _logger.info(
      'terminal.tab_exited',
      context: {'tab_id': entry.id, 'exit_code': ?code},
    );
    _publish();
  }

  void _onExitError(_Entry entry, Object error) {
    if (isClosed || entry.exited) return;
    _finishExit(entry);
    _logExitWaitFailed(entry.id, error);
    if (entry.closed) {
      _logClosed(entry);
      return;
    }
    // Процесс считается вышедшим, сигналов не шлём (D4).
    entry.status = const TerminalTabExited(null);
    entry.pending.add('\r\n[Process exited]\r\n');
    onPendingOutput?.call();
    _publish();
  }

  void _finishExit(_Entry entry) {
    entry.exited = true;
    entry.killTimer?.cancel();
    unawaited(entry.outputSub?.cancel());
    entry.outputSub = null;
    _closing.remove(entry);
    if (!entry.done.isCompleted) entry.done.complete();
  }

  /// Вкладку закрыли: вывод больше не нужен, остаток отбрасывается (D4).
  void _detach(_Entry entry) {
    entry.closed = true;
    entry.pending.clear();
    entry.offset = 0;
    unawaited(entry.outputSub?.cancel());
    entry.outputSub = null;
  }

  void _fail(_Entry entry, UserShellStartFailure reason) {
    entry.status = TerminalTabFailed(reason);
    _logger.warning(
      'terminal.start_failed',
      context: {'tab_id': entry.id, 'reason': reason.name},
    );
    _publish();
  }

  void _failStart(_Entry entry, UserShellStartFailure reason, {Object? error}) {
    if (isClosed) return;
    _logger.warning(
      'terminal.start_failed',
      context: {
        'tab_id': entry.id,
        'reason': reason.name,
        if (error != null) 'error_type': error.runtimeType.toString(),
      },
    );
    // Вкладку закрыли до конца старта: только событие, состояние не трогаем.
    if (entry.closed || _shuttingDown) return;
    entry.status = TerminalTabFailed(reason);
    _publish();
  }

  void _logExitWaitFailed(String tabId, Object error) {
    if (isClosed) return;
    _logger.warning(
      'terminal.exit_wait_failed',
      context: {'tab_id': tabId, 'error_type': error.runtimeType.toString()},
    );
  }

  void _logClosed(_Entry entry) {
    if (isClosed || entry.closeLogged) return;
    entry.closeLogged = true;
    _logger.info(
      'terminal.tab_closed',
      context: {'tab_id': entry.id, 'forced': entry.forced},
    );
  }

  /// Отписывает Cubit от рабочего пространства и процессов. Сигналов
  /// процессам не шлёт: их завершает [closeAll] (root lifecycle, D4).
  @override
  Future<void> close() async {
    // Повторный close (root lifecycle и dispose) — no-op: второй `await` на
    // уже закрытом контроллере состояния не завершается, если первый close
    // шёл в другой зоне.
    if (isClosed) return;
    unawaited(_workspaceSub.cancel());
    for (final entry in [
      for (final list in _entries.values) ...list,
      ..._closing,
    ]) {
      entry.killTimer?.cancel();
      unawaited(entry.outputSub?.cancel());
      entry.outputSub = null;
    }
    return super.close();
  }
}
