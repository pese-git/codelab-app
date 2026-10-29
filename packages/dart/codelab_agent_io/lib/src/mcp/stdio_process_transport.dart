import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../env/host_path.dart';
import '../env/host_variables.dart';
import '../env/process_tree.dart';

/// Входящая строка длиннее этого предела закрывает транспорт (D9).
const _maxLineBytes = 16 * 1024 * 1024;

/// Строка stderr в логе не длиннее 4 КиБ: в ней могут быть секреты (D9).
const _stderrLineBytes = 4096;

/// Сколько ждать выхода процесса после закрытия stdin, прежде чем слать
/// `SIGTERM` дереву (D9, шаг 2).
const _exitAfterEof = Duration(seconds: 2);

/// Сколько ждать выхода после `SIGTERM`, прежде чем слать `SIGKILL` (D9,
/// шаг 4).
const _exitAfterTerm = Duration(seconds: 5);

/// Потомок мог унаследовать канал и держать его открытым после выхода
/// процесса: дочитываем не дольше этого (`agent-core-architecture` §4.6,
/// шаг 7).
const _pipeGrace = Duration(seconds: 1);

/// Фабрика stdio-транспортов MCP: порт ядра `McpTransportFactory` для ключа
/// `stdio` (design.md change `add-agent-mcp-client`, D3, D9).
///
/// Почему в `codelab_agent_io`: запуск процесса — `dart:io`, а ядро и пакет
/// `codelab_agent_mcp` его не импортируют (PKG-1, PKG-3). Транспорт знает
/// только «строки туда и обратно»; протокол MCP — над ним.
///
/// Как использовать: хост создаёт одну фабрику и кладёт в
/// `McpTransports(stdio: …)` коннектора MCP (задача 8.2). [hostEnvironment]
/// — окружение хоста, из которого берутся только имена allowlist (по
/// умолчанию настоящее; тесты передают своё). Логгер приходит в `open`
/// вместе с `session_id` (`BoundLogger`): транспорт пишет через него
/// `mcp.server.stderr` (debug) и `mcp.server.closed` (info) с полем `server`.
final class StdioMcpTransportFactory implements McpTransportFactory {
  StdioMcpTransportFactory({Map<String, String>? hostEnvironment})
    : _hostEnvironment = hostEnvironment ?? io.Platform.environment;

  final Map<String, String> _hostEnvironment;

  @override
  Set<String> get transports => const {'stdio'};

  /// Запускает процесс сервера в [cwd]. Ошибка запуска — только
  /// [McpTransportException] (`spawn failed: …`): остальное исключение
  /// ломало бы остальные серверы сессии (D6).
  @override
  Future<McpTransport> open(
    McpServerConfig server, {
    required String cwd,
    required CancelToken cancel,
    required Logger logger,
  }) async {
    if (server is! McpStdioServerConfig) {
      throw const McpTransportException('not a stdio server');
    }
    if (cancel.isCancelled) {
      throw const McpTransportException('cancelled');
    }
    return StdioProcessTransport.start(
      server,
      cwd: cwd,
      hostEnvironment: _hostEnvironment,
      logger: logger,
    );
  }
}

/// Транспорт MCP поверх stdin/stdout дочернего процесса (D9;
/// `basic/transports/stdio.md`).
///
/// Почему отдельный класс, а не `Process` в клиенте: процесс — ресурс ОС с
/// жизненным циклом (EOF, `SIGTERM`, `SIGKILL`, дерево потомков), а клиент
/// MCP знает только порт [McpTransport] и не должен зависеть от `dart:io`.
///
/// Что делает:
/// * окружение — только allowlist хоста (§4.5, ENV-6) и `env` сервера поверх;
///   родительское окружение не наследуется;
/// * кадры — одна строка UTF-8 на сообщение; строка длиннее 16 МиБ закрывает
///   транспорт с причиной `message too large`;
/// * stderr читается всегда, чтобы процесс не завис на полном буфере; в лог
///   строки идут только уровнем debug и не длиннее 4 КиБ;
/// * [close] — EOF, 2 с, `SIGTERM` дереву, 5 с, `SIGKILL`.
///
/// Как использовать: создаётся через [StdioMcpTransportFactory.open]; [done]
/// завершается нормально при любом конце — выход процесса, [close], слишком
/// длинная строка.
final class StdioProcessTransport implements McpTransport {
  StdioProcessTransport._(this._process, this._server, this._logger) {
    _incoming = StreamController<String>(
      onPause: () => _stdoutSubscription.pause(),
      onResume: () => _stdoutSubscription.resume(),
    );
    final stdoutLines = _LineReader(
      limit: _maxLineBytes,
      onLine: _incoming.add,
      onOverflow: _onTooLong,
    );
    _stdoutSubscription = _process.stdout.listen(
      stdoutLines.add,
      onDone: _stdoutDone.complete,
      onError: (Object _) => _completeOnce(_stdoutDone),
    );
    // stderr читается всегда (D9): без этого процесс блокируется на записи
    // в полный буфер канала. Обрезка по длине — на стороне читателя, чтобы
    // строка без перевода строки не росла в памяти.
    final stderrLines = _LineReader(
      limit: _stderrLineBytes,
      truncate: true,
      onLine: _logStderr,
    );
    _stderrSubscription = _process.stderr.listen(
      stderrLines.add,
      onDone: _stderrDone.complete,
      onError: (Object _) => _completeOnce(_stderrDone),
    );
    // Запись в закрывшийся канал приходит ошибкой `done`; её отдаёт `send`,
    // здесь только не даём ей стать необработанной.
    _process.stdin.done.then<void>((_) {}, onError: (Object _) {});
    _process.exitCode.then(_complete);
  }

  /// Запускает [server] в [cwd] (путь ядра; на Windows переводится в путь
  /// хоста). [hostEnvironment] — источник значений allowlist.
  static Future<StdioProcessTransport> start(
    McpStdioServerConfig server, {
    required String cwd,
    required Map<String, String> hostEnvironment,
    required Logger logger,
  }) async {
    final io.Process process;
    try {
      process = await io.Process.start(
        server.command,
        server.args,
        workingDirectory: toHostPath(cwd, windows: io.Platform.isWindows),
        environment: {
          for (final name in hostEnvironmentAllowlist)
            name: ?hostEnvironment[name],
          ...server.env,
        },
        includeParentEnvironment: false,
        runInShell: false,
      );
    } on io.ProcessException catch (error) {
      throw McpTransportException('spawn failed: ${error.message}');
    } on ArgumentError {
      // NUL в команде, аргументе или `env`: текст исключения содержал бы
      // значения, а их в логах быть не должно (D13).
      throw const McpTransportException('spawn failed: invalid arguments');
    }
    return StdioProcessTransport._(process, server.name, logger);
  }

  final io.Process _process;
  final String _server;
  final Logger _logger;

  late final StreamController<String> _incoming;
  late final StreamSubscription<List<int>> _stdoutSubscription;
  late final StreamSubscription<List<int>> _stderrSubscription;
  final _stdoutDone = Completer<void>();
  final _stderrDone = Completer<void>();
  final _done = Completer<McpTransportClosed>();

  /// Хвост очереди записей: `IOSink` не допускает `add` во время `flush`,
  /// поэтому параллельные [send] выстраиваются в цепочку и сохраняют порядок.
  Future<void> _writes = Future.value();
  Future<void>? _closing;
  var _completing = false;
  var _closeRequested = false;
  String? _reason;

  @override
  String get kind => 'stdio';

  @override
  Stream<String> get incoming => _incoming.stream;

  /// У stdio обрыва потока ответа отдельного запроса нет (D8).
  @override
  Stream<Object> get abortedRequests => const Stream.empty();

  /// Отмена запроса stdio — уведомление клиента, а не действие транспорта.
  @override
  Future<void> abandon(Object requestId) async {}

  @override
  Future<McpTransportClosed> get done => _done.future;

  @override
  Future<void> send(
    String message, {
    Map<String, String> headers = const {},
  }) async {
    // Кадр — одна строка; `jsonEncode` перевода строки не даёт, но порт
    // принимает любой текст (stdio.md, «MUST NOT contain embedded newlines»).
    if (message.contains('\n') || message.contains('\r')) {
      throw const McpTransportException('message contains a newline');
    }
    final write = _writes.then((_) => _write(message));
    _writes = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }

  Future<void> _write(String message) async {
    if (_closeRequested || _done.isCompleted) {
      throw const McpTransportException('transport is closed');
    }
    try {
      _process.stdin.add(utf8.encode('$message\n'));
      await _process.stdin.flush();
    } on Object {
      // Текст исключения ОС в сообщение не берём: он идёт в лог (D13).
      throw const McpTransportException('write failed');
    }
  }

  @override
  Future<void> close() => _closing ??= _shutdown();

  /// EOF → 2 с → `SIGTERM` дереву → 5 с → `SIGKILL` (D9, «Закрытие»).
  Future<void> _shutdown() async {
    _closeRequested = true;
    // Не ждём закрытия: при полном канале и сервере, который не читает,
    // `close()` stdin зависло бы навсегда.
    _process.stdin.close().then<void>((_) {}, onError: (Object _) {});
    final exited = await _exitCode(_exitAfterEof);
    if (exited == null) {
      await terminateTree(_process, grace: _exitAfterTerm);
      // `terminateTree` шлёт `SIGKILL` и не ждёт выхода.
      final killed = await _exitCode(_exitAfterEof);
      if (killed == null) {
        // Процесс не отдаёт код (не должно случаться после SIGKILL): не
        // подвешиваем закрытие сессии.
        unawaited(_complete(null));
      }
    }
    await _done.future;
  }

  Future<int?> _exitCode(Duration limit) => _process.exitCode
      .then<int?>((code) => code)
      .timeout(limit, onTimeout: () => null);

  void _onTooLong() {
    _reason ??= 'message too large';
    unawaited(close());
  }

  /// Процесс вышел (сам, по [close] или после слишком длинной строки):
  /// дочитываем каналы, закрываем поток и завершаем [done].
  Future<void> _complete(int? exitCode) async {
    if (_completing) {
      return;
    }
    _completing = true;
    await Future.wait([
      _stdoutDone.future,
      _stderrDone.future,
    ]).timeout(_pipeGrace, onTimeout: () => const []);
    await _stdoutSubscription.cancel();
    await _stderrSubscription.cancel();
    // Future закрытия контроллера без слушателя не завершается никогда:
    // ждать его нельзя (транспорт без читателя тоже должен закрыться).
    unawaited(_incoming.close());
    _logger.log(
      LogLevel.info,
      'mcp.server.closed',
      fields: {'server': _server, 'transport': 'stdio', 'exit_code': exitCode},
    );
    _done.complete(
      McpTransportClosed(
        _reason ?? (_closeRequested ? 'closed' : 'process exited'),
        exitCode: exitCode,
      ),
    );
  }

  void _logStderr(String line) => _logger.log(
    LogLevel.debug,
    'mcp.server.stderr',
    fields: {'server': _server, 'line': line},
  );

  static void _completeOnce(Completer<void> completer) {
    if (!completer.isCompleted) {
      completer.complete();
    }
  }
}

/// Собирает строки из потока байтов с предельной длиной (D9).
///
/// Почему не `LineSplitter`: он копит строку целиком, а сервер недоверенный —
/// бесконечная строка без `\n` исчерпала бы память до проверки длины.
/// Предел считается в байтах, поэтому строка ровно в предел допустима.
///
/// Режимы: [truncate] `false` — строка длиннее [limit] вызывает [onOverflow]
/// и чтение прекращается (stdout); `true` — лишнее отбрасывается, строка
/// усечена до [limit] (stderr).
final class _LineReader {
  _LineReader({
    required this.limit,
    required this.onLine,
    this.truncate = false,
    this.onOverflow,
  });

  final int limit;
  final bool truncate;
  final void Function(String line) onLine;
  final void Function()? onOverflow;

  final _line = BytesBuilder(copy: true);
  var _length = 0;
  var _overflowed = false;

  void add(List<int> chunk) {
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    var start = 0;
    while (start < bytes.length && !_overflowed) {
      final newline = bytes.indexOf(0x0A, start);
      final end = newline == -1 ? bytes.length : newline;
      _append(bytes, start, end);
      if (_overflowed || newline == -1) {
        return;
      }
      _emit();
      start = newline + 1;
    }
  }

  void _append(Uint8List bytes, int start, int end) {
    final size = end - start;
    if (!truncate && _length + size > limit) {
      _overflowed = true;
      _line.clear();
      onOverflow?.call();
      return;
    }
    final room = limit - _length;
    final take = truncate && size > room ? room : size;
    if (take > 0) {
      _line.add(Uint8List.sublistView(bytes, start, start + take));
      _length += take;
    }
  }

  void _emit() {
    var text = utf8.decode(_line.takeBytes(), allowMalformed: true);
    _length = 0;
    if (text.endsWith('\r')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.isNotEmpty) {
      onLine(text);
    }
  }
}
