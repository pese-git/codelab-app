import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'agent_server.dart' show AcpTimeouts;
import 'connection/client_requests.dart';

/// Env сессии, в котором файлы и команды исполняет ACP-клиент
/// (`agent-core-architecture` §4.7, §13.9).
///
/// Почему: клиент показывает пользователю правки и терминалы и держит
/// containment рабочей папки (`AGENTS.md` §10), а агент по WebSocket может
/// вообще не видеть файлов. Поэтому встроенные инструменты пишутся один раз
/// над `ExecutionEnv`, а этот env переводит его в `fs/*` и `terminal/*`.
///
/// Для чего: `readText` → `fs/read_text_file`, `writeText` →
/// `fs/write_text_file`, `stat` → чтение одной строки (в ACP нет stat),
/// `exec` → `terminal/create` → `wait_for_exit` → `output` → `release`.
/// Метод без объявленной клиентом возможности отвечает отказом без кадра.
/// `listDir`, `readBytes`, `realpath` не реализуются: таких методов в ACP нет.
///
/// Как использовать: соединение создаёт env в `session/new` и отдаёт его в
/// порты сессии (сессия сама ставит `BoundedEnv` поверх). При отмене хода
/// мост сессии зовёт [abortPending]: у `fs/*` нет токена отмены в порте, а
/// ожидание ответа клиента должно прекратиться (§13.7, `session/cancel`).
final class AcpClientExecutionEnv implements ExecutionEnv {
  AcpClientExecutionEnv({
    required ClientLink link,
    required String cwd,
    required AcpTimeouts timeouts,
    required Clock clock,
    required Logger logger,
  }) : _link = link,
       _cwd = cwd,
       _timeouts = timeouts,
       _clock = clock,
       _logger = logger;

  final ClientLink _link;
  final String _cwd;
  final AcpTimeouts _timeouts;
  final Clock _clock;
  final Logger _logger;

  /// Завершается, когда терминал уже встроен в вызов на стороне клиента
  /// (`tool_call_update` с `{"type":"terminal"}` в очереди): `wait_for_exit`
  /// не должен его опередить. Ставит мост сессии; `null` — не ждать.
  Future<void> Function(String terminalId)? terminalShown;

  /// Отмена ожидающих `fs/*`: по одному источнику на запрос.
  final _fsInFlight = <CancelTokenSource>{};

  @override
  String get cwd => _cwd;

  acp.FileSystemCapabilities get _fs => _link.capabilities.fs;

  /// Прекращает ожидание всех идущих `fs/*`: они завершаются `io`
  /// «aborted»; запрос клиенту не отзывается — в ACP нечем.
  void abortPending() {
    for (final source in [..._fsInFlight]) {
      source.cancel();
    }
  }

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) async {
    final abs = _absolute(path);
    if (!_fs.readTextFile) {
      return Err(FileError(FileErrorCode.unsupported, abs));
    }
    final result = await _fsRequest(
      abs,
      acp.acpFsReadTextFile,
      acp.ReadTextFileRequest(
        sessionId: acp.SessionId(_link.sessionId),
        path: abs,
        line: line,
        limit: limit,
      ),
    );
    return switch (result) {
      Ok(:final value) => Ok(acp.acpFsReadTextFile.decodeResult(value).content),
      Err(:final error) => Err(error),
    };
  }

  @override
  Future<Result<void, FileError>> writeText(String path, String content) async {
    final abs = _absolute(path);
    if (!_fs.writeTextFile) {
      return Err(FileError(FileErrorCode.unsupported, abs));
    }
    final result = await _fsRequest(
      abs,
      acp.acpFsWriteTextFile,
      acp.WriteTextFileRequest(
        sessionId: acp.SessionId(_link.sessionId),
        path: abs,
        content: content,
      ),
    );
    return switch (result) {
      Ok() => const Ok(null),
      // Таймаут записи не значит, что её не было: модель узнаёт об этом из
      // текста (§13.9).
      Err(error: FileError(code: FileErrorCode.io, :final message?))
          when message.contains('timed out') =>
        Err(
          FileError(
            FileErrorCode.io,
            abs,
            '$message; the write may have completed',
          ),
        ),
      Err(:final error) => Err(error),
    };
  }

  /// В ACP нет stat: успешное чтение одной строки — файл без размера
  /// (§4.7). Каталоги через клиента не видны.
  @override
  Future<Result<FileStat, FileError>> stat(String path) async {
    final abs = _absolute(path);
    return switch (await readText(abs, limit: 1)) {
      Ok() => Ok(FileStat(path: abs, type: FileType.file)),
      Err(:final error) => Err(error),
    };
  }

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) async {
    if (!_link.capabilities.terminal) {
      return const Err(
        ExecError(
          ExecErrorCode.shellUnavailable,
          message: 'the client does not support terminals',
        ),
      );
    }
    final started = _clock.now();
    final sessionId = acp.SessionId(_link.sessionId);
    final acp.TerminalId terminal;
    try {
      final created = await _link.requests.request(
        acp.acpTerminalCreate,
        acp.CreateTerminalRequest(
          sessionId: sessionId,
          command: '/bin/sh',
          args: ['-c', command],
          env: [
            for (final MapEntry(:key, :value) in options.env.entries)
              acp.EnvVariable(name: key, value: value),
          ],
          cwd: _absolute(options.cwd),
          outputByteLimit: options.outputByteLimit,
        ),
        prefix: 'term',
        timeout: _timeouts.terminalCreate,
        cancel: options.cancel,
      );
      terminal = acp.acpTerminalCreate.decodeResult(created).terminalId;
    } on ClientCallCancelled {
      return Err(
        ExecError(
          ExecErrorCode.aborted,
          duration: _clock.now().difference(started),
        ),
      );
    } on ClientCallFailure catch (failure) {
      return Err(
        ExecError(ExecErrorCode.spawnFailed, message: _describe(failure)),
      );
    }
    if (options.onTerminal case final onTerminal?) {
      onTerminal(terminal.value);
      await terminalShown?.call(terminal.value);
    }
    try {
      return await _awaitTerminal(sessionId, terminal, options, started);
    } finally {
      // ENV-7: терминал освобождается на любом пути, включая ошибки,
      // таймаут и отмену.
      await _release(sessionId, terminal);
    }
  }

  /// Шаги 2–4 §4.7: ожидание выхода против таймаута и отмены, `kill` при
  /// любом из них, затем `output`.
  Future<Result<ExecResult, ExecError>> _awaitTerminal(
    acp.SessionId sessionId,
    acp.TerminalId terminal,
    ExecOptions options,
    DateTime started,
  ) async {
    final stop = CancelTokenSource();
    var timedOut = false;
    final timer = options.timeout == null
        ? null
        : _clock.timer(options.timeout!, () {
            timedOut = true;
            stop.cancel();
          });
    unawaited(options.cancel.onCancel.then((_) => stop.cancel()));
    final params = acp.WaitForTerminalExitRequest(
      sessionId: sessionId,
      terminalId: terminal,
    );
    acp.WaitForTerminalExitResponse? exited;
    ClientCallFailure? waitFailure;
    try {
      exited = acp.acpTerminalWaitForExit.decodeResult(
        await _link.requests.request(
          acp.acpTerminalWaitForExit,
          params,
          prefix: 'term',
          cancel: stop.token,
        ),
      );
    } on ClientCallCancelled {
      await _kill(sessionId, terminal);
    } on ClientCallFailure catch (failure) {
      waitFailure = failure;
    } finally {
      timer?.cancel();
    }
    final output = await _output(sessionId, terminal);
    final duration = _clock.now().difference(started);
    if (waitFailure != null) {
      return Err(
        ExecError(
          ExecErrorCode.unknown,
          message: 'terminal/wait_for_exit failed: ${_describe(waitFailure)}',
          outputTail: output?.output ?? '',
          duration: duration,
        ),
      );
    }
    if (exited == null) {
      return Err(
        ExecError(
          timedOut ? ExecErrorCode.timeout : ExecErrorCode.aborted,
          outputTail: output?.output ?? '',
          duration: duration,
        ),
      );
    }
    final status = output?.exitStatus;
    return Ok(
      ExecResult(
        exitCode: exited.exitCode ?? status?.exitCode,
        signal: exited.signal ?? status?.signal,
        output: output?.output ?? '[output unavailable]',
        truncated: output?.truncated ?? false,
        duration: duration,
      ),
    );
  }

  Future<void> _kill(acp.SessionId sessionId, acp.TerminalId terminal) async {
    try {
      await _link.requests.request(
        acp.acpTerminalKill,
        acp.KillTerminalCommandRequest(
          sessionId: sessionId,
          terminalId: terminal,
        ),
        prefix: 'term',
        timeout: _timeouts.terminalKill,
      );
    } on ClientCallFailure catch (failure) {
      _log('acp.terminal.kill_failed', terminal, failure);
    }
  }

  /// Вывод терминала; `null` — клиент его не отдал (результат получает
  /// пометку вместо вывода, §13.9).
  Future<acp.TerminalOutputResponse?> _output(
    acp.SessionId sessionId,
    acp.TerminalId terminal,
  ) async {
    try {
      return acp.acpTerminalOutput.decodeResult(
        await _link.requests.request(
          acp.acpTerminalOutput,
          acp.TerminalOutputRequest(sessionId: sessionId, terminalId: terminal),
          prefix: 'term',
          timeout: _timeouts.terminalOutput,
        ),
      );
    } on ClientCallFailure catch (failure) {
      _log('acp.terminal.output_failed', terminal, failure);
      return null;
    }
  }

  Future<void> _release(
    acp.SessionId sessionId,
    acp.TerminalId terminal,
  ) async {
    try {
      await _link.requests.request(
        acp.acpTerminalRelease,
        acp.ReleaseTerminalRequest(sessionId: sessionId, terminalId: terminal),
        prefix: 'term',
        timeout: _timeouts.terminalRelease,
      );
    } on ClientCallFailure catch (failure) {
      _log('acp.terminal.release_failed', terminal, failure);
    }
  }

  /// Запрос `fs/*` с таймаутом §13.9 и отменой [abortPending]; отказ
  /// клиента — значение `FileError` (ENV-1).
  Future<Result<Object?, FileError>> _fsRequest<P extends Object>(
    String path,
    acp.AcpMethodDefinition<P, Object> method,
    P params,
  ) async {
    final abort = CancelTokenSource();
    _fsInFlight.add(abort);
    try {
      return Ok(
        await _link.requests.request(
          method,
          params,
          prefix: 'fs',
          timeout: _timeouts.fs,
          cancel: abort.token,
        ),
      );
    } on ClientRejected catch (rejected) {
      return Err(
        rejected.error.code == acp.acpResourceNotFoundCode
            ? FileError(FileErrorCode.notFound, path, rejected.error.message)
            : FileError(FileErrorCode.io, path, rejected.error.message),
      );
    } on ClientCallFailure catch (failure) {
      return Err(FileError(FileErrorCode.io, path, '$failure'));
    } finally {
      _fsInFlight.remove(abort);
    }
  }

  void _log(String event, acp.TerminalId terminal, ClientCallFailure failure) =>
      _logger.log(
        LogLevel.warning,
        event,
        fields: {
          'session_id': _link.sessionId,
          'terminal_id': terminal.value,
          'reason': _describe(failure),
        },
      );

  static String _describe(ClientCallFailure failure) => switch (failure) {
    ClientRejected(:final error) => error.message,
    _ => '$failure',
  };

  /// Абсолютный нормализованный путь: относительный — от корня сессии.
  String _absolute(String path) {
    final segments = <String>[];
    final joined = path.startsWith('/') ? path : '$_cwd/$path';
    for (final segment in joined.split('/')) {
      switch (segment) {
        case '' || '.':
          break;
        case '..':
          if (segments.isNotEmpty) {
            segments.removeLast();
          }
        default:
          segments.add(segment);
      }
    }
    return '/${segments.join('/')}';
  }
}
