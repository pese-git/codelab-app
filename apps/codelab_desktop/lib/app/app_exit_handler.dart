import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;

/// Закрывает процессы клиента, когда ОС просит app выйти.
///
/// Почему: при штатном завершении (macOS `NSApplication terminate:`, Cmd+Q и
/// закрытие последнего окна) движок останавливается без размонтирования
/// дерева виджетов, поэтому `dispose` у `CodeLabBootstrap` и закрытие root
/// scope не выполняются. Dart VM при остановке ждёт все isolate, а isolate
/// `pty2` стоят в блокирующем `waitpid` на живых shell — app зависает.
/// Раньше обработчик закрывал только вкладки Terminal; процессы `terminal/*`
/// внешнего агента, stdio-агент и встроенный агент (`exec`, MCP stdio)
/// оставались сиротами. Теперь вызывается весь `CodeLabRootLifecycle`
/// (`add-client-process-shutdown-on-exit`, D1, D2; прежнее решение —
/// `add-integrated-terminal`, D4 «Выход из app», D15 п. 9).
///
/// Для чего: единственная точка, где запрос выхода превращается в
/// [closeRoot] (`CodeLabRootLifecycle.dispose`) с общим пределом
/// [exitTimeout] = 5 с от первого запроса (`concurrency.md` §45–§46). Не
/// уложилось — пишется `app.exit_timeout` с именами незавершённых шагов, а
/// ответ всё равно `exit`: незавершённые шаги продолжают работать до остановки
/// VM, отдельного прохода «убить всех» нет (D2). Шаги с сигналами (`terminal`,
/// `client`) не стоят за закрытием встроенного агента (D11), но не начатый к
/// пределу шаг не послал ничего — поэтому `pending` перечисляет и такие шаги
/// (D10), и по журналу видно, кто остался без сигналов. Отмены выхода нет.
///
/// Как использовать: composition root создаёт обработчик с `closeRoot`
/// (`CodeLabRootLifecycle.dispose`), `pendingSteps` (`CodeLabRootLifecycle`
/// `.pendingSteps`), логгером и функцией сброса журнала и отдаёт
/// [onExitRequested] в `AppLifecycleListener` (`CodeLabBootstrap`). Повторный
/// запрос возвращает тот же `Future`: предел отсчитывается от первого, второго
/// прохода нет (D5), а `closeRoot` идемпотентен и при закрытии scope после
/// выхода сигналов не шлёт.
///
/// Журнал (D6): `app.exit_requested` до закрытия; затем `app.exit_closed
/// {duration_ms}` или `app.exit_timeout {timeout_ms, pending}`; при сбое
/// `closeRoot` целиком — `app.exit_close_failed` только с `error_type`
/// (текст ошибки может нести пути). Перед выходом ждёт сброс файловых журналов
/// не дольше [flushTimeout]: при terminate `CodeLabLoggingLifecycle.dispose`
/// не вызывается, а `AsyncFileOutput` пишет с очередью, и без сброса хвост
/// (включая `terminal.tab_closed`) терялся бы.
final class AppExitHandler {
  AppExitHandler({
    required Future<void> Function() closeRoot,
    required List<String> Function() pendingSteps,
    required Logger logger,
    required Future<void> Function() flushLogs,
    this.exitTimeout = const Duration(seconds: 5),
    this.flushTimeout = const Duration(milliseconds: 500),
  }) : _closeRoot = closeRoot,
       _pendingSteps = pendingSteps,
       _logger = logger,
       _flushLogs = flushLogs;

  final Future<void> Function() _closeRoot;
  final List<String> Function() _pendingSteps;
  final Logger _logger;
  final Future<void> Function() _flushLogs;

  /// Общий предел закрытия от запроса выхода; шов тестов (D2), не настройка
  /// пользователя. Худшее время от Cmd+Q до выхода — [exitTimeout] плюс
  /// [flushTimeout].
  final Duration exitTimeout;

  /// Предел ожидания сброса журнала; истечение — не ошибка.
  final Duration flushTimeout;

  /// Проход выхода: мемоизирован, повторный запрос ждёт его же (D5).
  Future<AppExitResponse>? _exit;

  /// Колбэк `AppLifecycleListener.onExitRequested`: ждёт [closeRoot] не дольше
  /// [exitTimeout] и сброс журнала, разрешает выход. Сбой или зависание
  /// закрытия не должны держать app: они пишутся в журнал, а ответ остаётся
  /// `exit`.
  Future<AppExitResponse> onExitRequested() => _exit ??= _handle();

  Future<AppExitResponse> _handle() async {
    _log(() => _logger.info('app.exit_requested'));
    final watch = Stopwatch()..start();
    var timedOut = false;
    try {
      await _closeRoot().timeout(
        exitTimeout,
        onTimeout: () {
          timedOut = true;
        },
      );
      if (timedOut) {
        _log(
          () => _logger.warning(
            'app.exit_timeout',
            context: {
              'timeout_ms': exitTimeout.inMilliseconds,
              'pending': _pendingSteps(),
            },
          ),
        );
      } else {
        _log(
          () => _logger.info(
            'app.exit_closed',
            context: {'duration_ms': watch.elapsedMilliseconds},
          ),
        );
      }
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
