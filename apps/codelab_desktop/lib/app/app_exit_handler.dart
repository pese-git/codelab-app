import 'dart:ui' show AppExitResponse;

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;

import '../features/terminal/application/terminal_tabs_cubit.dart';

/// Завершает процессы терминала, когда ОС просит app выйти.
///
/// Почему: при штатном завершении (macOS `NSApplication terminate:`, Cmd+Q и
/// закрытие последнего окна) движок останавливается без размонтирования
/// дерева виджетов, поэтому `dispose` у `CodeLabBootstrap` и закрытие root
/// scope не выполняются. Dart VM при остановке ждёт все isolate, а isolate
/// `pty2` стоят в блокирующем `waitpid` на живых shell — app зависает.
/// Страховочная сеть PTY (закрытие мастера) при штатном выходе не срабатывает
/// (`add-integrated-terminal`, design.md D4 «Выход из app», D15 п. 9).
///
/// Для чего: единственная точка, где запрос выхода превращается в
/// `TerminalTabsCubit.closeAll()` — `hangUp` всем, через 3 с `kill`
/// оставшимся, `terminal.tab_closed` с `forced: true`. Только терминал, а не
/// весь `CodeLabRootLifecycle.dispose`: остальное закрытие (агент, журналы)
/// может ждать долго и не нужно для выхода, а срок ожидания выхода ограничен
/// (`concurrency.md` §45–§46). Отмены выхода нет.
///
/// Как использовать: composition root создаёт обработчик с Cubit из root
/// scope, логгером и функцией сброса журнала и отдаёт [onExitRequested] в
/// `AppLifecycleListener` (`CodeLabBootstrap`). Повторный запрос во время
/// `closeAll()` ждёт тот же проход (`closeAll()` идемпотентен), последующее
/// закрытие root scope не шлёт сигналов повторно.
///
/// Журнал: `app.exit_requested` до закрытия; при сбое закрытия —
/// `app.exit_close_failed` только с `error_type` (текст ошибки может нести
/// пути, D9). Перед выходом ждёт сброс файловых журналов не дольше
/// [flushTimeout]: при terminate `CodeLabLoggingLifecycle.dispose` не
/// вызывается, а `AsyncFileOutput` пишет с очередью, и без сброса хвост
/// (включая `terminal.tab_closed`) терялся бы.
final class AppExitHandler {
  AppExitHandler({
    required TerminalTabsCubit terminalTabs,
    required Logger logger,
    required Future<void> Function() flushLogs,
    this.flushTimeout = const Duration(milliseconds: 500),
  }) : _terminalTabs = terminalTabs,
       _logger = logger,
       _flushLogs = flushLogs;

  final TerminalTabsCubit _terminalTabs;
  final Logger _logger;
  final Future<void> Function() _flushLogs;

  /// Предел ожидания сброса журнала; истечение — не ошибка.
  final Duration flushTimeout;

  /// Колбэк `AppLifecycleListener.onExitRequested`: ждёт `closeAll()` и
  /// сброс журнала, разрешает выход. Сбой закрытия или сброса не должен
  /// держать app: он пишется в журнал, а ответ остаётся `exit`.
  Future<AppExitResponse> onExitRequested() async {
    _log(() => _logger.info('app.exit_requested'));
    try {
      await _terminalTabs.closeAll();
    } on Object catch (error) {
      _log(
        () => _logger.error(
          'app.exit_close_failed',
          context: {'error_type': error.runtimeType.toString()},
        ),
      );
    }
    try {
      await _flushLogs().timeout(flushTimeout);
    } on Object {
      // Таймаут или сбой записи журнала не повод держать выход: писать об
      // этом всё равно некуда.
    }
    return AppExitResponse.exit;
  }

  /// Запись в журнал без права помешать выходу: сбой журнала глотается,
  /// писать о нём всё равно некуда, а ответ `exit` обязателен (D4).
  void _log(void Function() write) {
    try {
      write();
    } on Object {
      // Намеренно пусто: см. doc-комментарий.
    }
  }
}
