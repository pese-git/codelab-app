import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import '../acp_transport.dart';
import '../transport_configs.dart';

final class StdioAcpTransport implements AcpTransport {
  StdioAcpTransport(this.config);

  final StdioAcpTransportConfig config;

  final _inboundController = StreamController<JsonRpcMessage>.broadcast(
    sync: true,
  );
  final _eventController = StreamController<AcpTransportEvent>.broadcast(
    sync: true,
  );
  final _subscriptions = <StreamSubscription<void>>[];

  Process? _process;
  Future<int>? _exitCode;
  AcpTransportState _state = AcpTransportState.idle;
  var _isClosed = false;

  /// Запуск процесса в полёте: `close` дожидается его, чтобы не оставить
  /// процесс без владельца (D13).
  Future<void>? _startFuture;

  /// Мемоизированное закрытие: повторный `close` возвращает его же (D13).
  Future<void>? _closing;

  /// Монотонные часы транспорта: дедлайны не зависят от сдвигов системных
  /// часов (NTP, смена времени), в отличие от `DateTime.now()` (D13).
  final Stopwatch _clock = Stopwatch()..start();

  /// Дедлайн ожидания выхода по EOF как отсчёт `Duration` на `_clock`;
  /// только сокращается (D13).
  late Duration _eofDeadline;

  /// `SIGTERM` уже послан: дедлайн EOF больше не сокращается (D13).
  var _termSent = false;

  /// Будится при сокращении `_eofDeadline`, чтобы ожидание пересчитало срок.
  Completer<void>? _deadlineChanged;

  @override
  Stream<JsonRpcMessage> get inbound => _inboundController.stream;

  @override
  Stream<AcpTransportEvent> get events => _eventController.stream;

  @override
  AcpTransportState get state => _state;

  /// Запускает процесс агента и подключает его stdio.
  ///
  /// Почему аргументы убираются из ошибки: `ProcessException.toString()`
  /// включает аргументы команды, а они попадают в журналы, баннеры и вывод
  /// клиентов (design.md change `redact-cli-stdio-profile-args`, D8).
  ///
  /// Для чего: единственное место, закрывающее утечку для всех потребителей.
  ///
  /// Как использовать: вызывать один раз; при ошибке запуска бросается
  /// `ProcessException` без `arguments` (тип, `message`, `errorCode`,
  /// `executable` сохранены), та же копия лежит в `cause` события
  /// `AcpTransportFailure` с кодом `startFailed`. Прочие ошибки — как раньше.
  ///
  /// `close()` во время запуска: `Future` запуска сохраняется, `close`
  /// дожидается `Process.start` и закрывает запущенный процесс обычной
  /// эскалацией; `start` при этом бросает `AcpTransportException` с кодом
  /// `closed`, подписок и событий `connected` не создаётся (design.md change
  /// `add-client-process-shutdown-on-exit`, D13).
  @override
  Future<void> start() {
    _ensureNotClosed();

    if (_state == AcpTransportState.connected ||
        _state == AcpTransportState.connecting) {
      return Future.value();
    }

    return _startFuture = _start();
  }

  Future<void> _start() async {
    _setState(AcpTransportState.connecting);

    try {
      final process = await Process.start(
        config.command,
        config.args,
        workingDirectory: config.cwd,
        environment: config.env.isEmpty ? null : config.env,
      );
      _process = process;
      _exitCode = process.exitCode;
      if (_isClosed) {
        // D13: `close` начался во время `Process.start`. Процесс сохранён
        // для эскалации `close` (EOF -> SIGTERM -> SIGKILL); подписок и
        // событий нет, контроллеры уже закрываются.
        throw AcpTransportException(
          code: AcpTransportErrorCode.closed,
          message: 'Stdio ACP transport was closed while starting.',
        );
      }
      _listenToProcess(process);
      _setState(AcpTransportState.connected);
    } on Object catch (error, stackTrace) {
      // D8 (change `redact-cli-stdio-profile-args`): `ProcessException`
      // печатает `Command: <exe> <args>`, а аргументы агента могут быть
      // ключами. Копия без аргументов сохраняет тип, `message`, `errorCode` и
      // `executable`, поэтому `on ProcessException` и классификация ENOENT у
      // потребителей работают как раньше. Исходный стек сохраняем.
      final sanitized = error is ProcessException
          ? ProcessException(
              error.executable,
              const [],
              error.message,
              error.errorCode,
            )
          : error;
      _fail(
        AcpTransportException(
          code: AcpTransportErrorCode.startFailed,
          message: 'Failed to start stdio ACP agent.',
          cause: sanitized,
          stackTrace: stackTrace,
        ),
      );
      Error.throwWithStackTrace(sanitized, stackTrace);
    }
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    _ensureConnected();

    try {
      _process!.stdin.writeln(encodeJsonRpcMessage(message));
      await _process!.stdin.flush();
    } on Object catch (error, stackTrace) {
      throw AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'Failed to send ACP message over stdio.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Закрывает транспорт: EOF на stdin, затем ограниченная эскалация сигналов.
  ///
  /// Почему ограничено: раньше после `SIGTERM` шло `await exitCode` без
  /// предела, и агент, игнорирующий `SIGTERM`, держал `close()` вечно, а вместе
  /// с ним выход клиента и Reconnect (design.md change
  /// `add-client-process-shutdown-on-exit`, D3).
  ///
  /// Почему мемоизирован и срок только сокращается: Reconnect закрывает
  /// транспорт с пределом по умолчанию, и в этот момент выход приложения
  /// вызывает `close` с коротким пределом. Если бы повторный вызов возвращался
  /// сразу, выход считал бы транспорт закрытым, а `SIGTERM` ушёл бы позже
  /// остановки VM. Поэтому повторный вызов ждёт идущее закрытие, а более
  /// ранний дедлайн сокращает ожидание EOF. Более поздний не продлевает его, а
  /// фазу после `SIGTERM` не сокращает ничто, иначе агент лишился бы обработчика
  /// `SIGTERM` (D13).
  ///
  /// Для чего: ACP описывает завершение stdio-агента как «Close stdin,
  /// terminate subprocess» (`16-Transports.md`) и не задаёт сроков; сроки
  /// выбраны здесь.
  ///
  /// Как использовать: порядок — дождаться идущего `start`, закрыть stdin,
  /// ждать выхода `timeout` (по умолчанию 5 с), `SIGTERM`, ждать до 2 с,
  /// `SIGKILL` без ожидания кода выхода. Итого не позже `timeout` + 2 с плюс
  /// отписка потоков. Повторный вызов возвращает тот же `Future`, сигналов
  /// не шлёт.
  @override
  Future<void> close({Duration? timeout}) {
    final deadline = _clock.elapsed + (timeout ?? const Duration(seconds: 5));
    final closing = _closing;
    if (closing != null) {
      if (!_termSent && deadline < _eofDeadline) {
        _eofDeadline = deadline;
        final changed = _deadlineChanged;
        _deadlineChanged = null;
        if (changed != null && !changed.isCompleted) {
          changed.complete();
        }
      }
      return closing;
    }

    _eofDeadline = deadline;
    return _closing = _close();
  }

  Future<void> _close() async {
    // Флаг ставится синхронно: `start` в полёте увидит закрытие.
    _isClosed = true;

    try {
      await _startFuture;
    } on Object {
      // Ошибку запуска получает вызвавший `start`.
    }

    // Состояние `closing` публикуется после запуска в полёте: до этого
    // момента контроллеры должны оставаться открытыми для `start` (D13).
    _setState(AcpTransportState.closing);

    final process = _process;
    final exitCode = _exitCode;

    try {
      await process?.stdin.close();
    } on Object {
      // Процесс мог уже завершиться: закрытие stdin тогда не нужно.
    }

    if (process != null && exitCode != null) {
      await _waitForProcessExit(process, exitCode);
    }

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    _process = null;
    _exitCode = null;

    _setState(AcpTransportState.closed);
    await _inboundController.close();
    await _eventController.close();
  }

  void _listenToProcess(Process process) {
    unawaited(
      process.exitCode.then((exitCode) {
        _handleProcessExit(exitCode);
      }),
    );

    _subscriptions
      ..add(
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              _handleStdoutLine,
              onError: (Object error, StackTrace stackTrace) {
                _fail(
                  AcpTransportException(
                    code: AcpTransportErrorCode.receiveFailed,
                    message: 'Failed to read ACP stdout stream.',
                    cause: error,
                    stackTrace: stackTrace,
                  ),
                );
              },
            ),
      )
      ..add(
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              _handleStderrLine,
              onError: (Object error, StackTrace stackTrace) {
                _fail(
                  AcpTransportException(
                    code: AcpTransportErrorCode.receiveFailed,
                    message: 'Failed to read ACP stderr stream.',
                    cause: error,
                    stackTrace: stackTrace,
                  ),
                );
              },
            ),
      );
  }

  /// Срок ожидания выхода после `SIGTERM` до `SIGKILL`.
  ///
  /// Совпадает с `terminateTree` агента (`agent-core-architecture` §4.6);
  /// внутренняя константа, не параметр (D3).
  static const _termGracePeriod = Duration(seconds: 2);

  /// Ждёт выхода процесса с эскалацией `EOF` -> `SIGTERM` -> `SIGKILL` (D3).
  ///
  /// Ожидание EOF идёт до `_eofDeadline`, который повторный `close` может
  /// сократить (D13): цикл пересчитывает остаток при каждом пробуждении.
  /// `SIGKILL` не ждёт код выхода: ядро доставляет его безусловно, а
  /// неограниченное ожидание вернуло бы исходную проблему зависшего `close`.
  Future<void> _waitForProcessExit(
    Process process,
    Future<int> exitCode,
  ) async {
    var exited = false;
    unawaited(exitCode.then((_) => exited = true, onError: (Object _) {}));

    while (!exited) {
      final remaining = _eofDeadline - _clock.elapsed;
      if (remaining <= Duration.zero) {
        break;
      }
      final changed = _deadlineChanged = Completer<void>();
      final timer = Timer(remaining, () {
        if (!changed.isCompleted) changed.complete();
      });
      await Future.any<Object?>([exitCode, changed.future]);
      timer.cancel();
    }
    if (exited) {
      return;
    }

    // Агент не вышел по EOF: просим завершиться штатно.
    _termSent = true;
    _deadlineChanged = null;
    process.kill();
    try {
      await exitCode.timeout(_termGracePeriod);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
  }

  void _handleProcessExit(int exitCode) {
    if (_isClosed || _state == AcpTransportState.failed) {
      return;
    }

    _fail(
      AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'Stdio ACP agent exited unexpectedly with code $exitCode.',
      ),
    );
  }

  void _handleStdoutLine(String line) {
    if (_isClosed || line.isEmpty) {
      return;
    }

    try {
      _inboundController.add(decodeJsonRpcMessage(line));
    } on JsonRpcProtocolException catch (error, stackTrace) {
      _fail(
        AcpTransportException(
          code: AcpTransportErrorCode.protocolViolation,
          message: 'Agent wrote invalid ACP JSON-RPC to stdout.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  void _handleStderrLine(String line) {
    if (_isClosed || line.isEmpty) {
      return;
    }

    _eventController.add(
      AcpTransportEvent.diagnostic(
        message: line,
        severity: AcpTransportDiagnosticSeverity.info,
        source: 'stderr',
      ),
    );
  }

  void _ensureConnected() {
    _ensureNotClosed();

    if (_state != AcpTransportState.connected || _process == null) {
      throw AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'Stdio ACP transport is not connected.',
      );
    }
  }

  void _ensureNotClosed() {
    if (_isClosed || _state == AcpTransportState.closed) {
      throw AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'Stdio ACP transport is closed.',
      );
    }
  }

  void _fail(AcpTransportException error) {
    if (_isClosed) {
      return;
    }

    _setState(AcpTransportState.failed);
    _eventController.add(AcpTransportEvent.failure(error));
  }

  void _setState(AcpTransportState state) {
    _state = state;
    _eventController.add(AcpTransportEvent.stateChanged(state));
  }
}
