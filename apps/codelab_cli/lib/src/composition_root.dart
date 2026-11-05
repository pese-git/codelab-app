import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    as embedded
    show EmbeddedAgentOpener, LogLevel, Logger;
// Единственное место CLI, где разрешён IO-барель встроенного агента
// (правило сторожа, design.md change `add-embedded-agent-mode`, D3).
import 'package:codelab_embedded/io.dart';

import 'cli_args.dart';
import 'cli_logger.dart';
import 'embedded_logger.dart';
import 'embedded_transport_resolver.dart';

/// Собранный клиентский слой одного запуска `codelab`.
///
/// Почему: CLI использует kit так же, как app — `ClientWorkspace` поверх
/// `AcpClientApplication`, настоящие транспорты из `codelab_client_io`;
/// своего состояния сессий у CLI нет (design.md change `add-codelab-cli`,
/// D2, D3).
///
/// Как использовать: `buildCliRuntime(environment: …, stderr: …, verbose:
/// …)`; после работы — [dispose], который закрывает транспорт, завершает
/// процесс внешнего агента и **дожидается `dispose` встроенного агента**:
/// журнал сессии дописан до выхода процесса (spec codelab-cli «Встроенный
/// агент в CLI», «Выход»; design.md change `add-embedded-agent-mode`, D6).
final class CliRuntime {
  CliRuntime._(
    this.application,
    this.workspace,
    this._embedded,
    this._closeTimeout,
    this._logger,
    this._stderr,
  );

  final AcpClientApplication application;
  final ClientWorkspace workspace;
  final EmbeddedTransportResolver _embedded;
  final Duration _closeTimeout;
  final embedded.Logger _logger;
  final StringSink _stderr;

  Future<void> dispose() async {
    // Цепочка try/finally: сбой одного шага не оставляет агента без владельца
    // и транспорт клиента открытым.
    try {
      await workspace.dispose();
    } finally {
      try {
        // Резолвер встроенного агента закрывается до клиента, как в app (D9):
        // агент отменяет ход и дописывает журнал, пока клиентский конец жив.
        // Повисший `dispose` не держит выход вечно: по таймауту выход
        // продолжается (событие без текста), агента добьёт завершение
        // процесса.
        await _embedded.close().timeout(
          _closeTimeout,
          onTimeout: () {
            _logger.log(embedded.LogLevel.warning, 'embedded.close_timeout');
            // Пользователь должен узнать о зависшем выходе независимо от
            // `--verbose`: одна строка без текста ошибки (spec codelab-cli
            // «Выход»).
            _stderr.writeln(
              'codelab: the embedded agent did not stop in '
              '${_closeTimeout.inSeconds} s',
            );
          },
        );
      } finally {
        await application.dispose();
      }
    }
  }
}

/// Composition root CLI: ядро клиента, резолвер транспортов и рабочее
/// пространство.
///
/// [environment] даёт токен WebSocket (`CODELAB_AGENT_TOKEN`); [verbose] —
/// лог ядра клиента в [stderr], иначе лог выключен: stdout и stderr headless
/// не должны засоряться служебными строками.
///
/// Встроенный агент (`EmbeddedProfile`) открывает [embeddedOpener]; по
/// умолчанию — `localEmbeddedAgentOpener` с окружением процесса, логгером в
/// [stderr] при [verbose] и [debugSecrets] (`--debug-secrets`). Тестовая точка
/// входа подменяет открыватель сценарием модели (D8): `testing.dart` в рабочий
/// код не импортируется.
///
/// [profileSecrets] — хранилище секретов для токенов профилей `secret:<имя>`
/// (design.md change `add-provider-setup-ui`, D13): его собирает `run.dart`
/// поверх `ClientSecretAccess`, потому что IO-барель моста разрешён только
/// там. Без него `secret:` читается как «секрета нет» и подключение идёт без
/// токена.
CliRuntime buildCliRuntime({
  required Map<String, String> environment,
  required StringSink stderr,
  required bool verbose,
  bool debugSecrets = false,
  embedded.EmbeddedAgentOpener? embeddedOpener,
  ProfileSecrets? profileSecrets,
  Duration embeddedCloseTimeout = const Duration(seconds: 10),
}) {
  const textFileIo = IoTextFileIo();
  final application = AcpClientApplication(
    transport: _NotConnectedTransport(),
    clientInfo: const Implementation(name: 'codelab-cli', version: cliVersion),
    textFileReader: textFileIo,
    textFileWriter: textFileIo,
    terminalProcessRunner: const IoTerminalProcessRunner(),
    logger: verbose ? CliLogger(stderr) : CliLogger.silent(),
  );
  // Лог агента: полный с `--verbose`; `--debug-secrets` (или
  // `CODELAB_DEBUG_SECRETS=1`) без `--verbose` пишет только `secrets.lookup`
  // (имена и источник, без значений); иначе тишина — stdout и stderr
  // headless не засоряются.
  final debug = debugSecrets || environment['CODELAB_DEBUG_SECRETS'] == '1';
  final embedded.Logger agentLogger = verbose
      ? CliEmbeddedLogger(stderr)
      : debug
      ? CliEmbeddedLogger.secretLookupsOnly(stderr)
      : const CliEmbeddedLogger.silent();
  final resolver = EmbeddedTransportResolver(
    embeddedOpener ??
        localEmbeddedAgentOpener(
          environment: environment,
          logger: agentLogger,
          debugSecrets: debugSecrets,
        ),
  );
  final workspace = ClientWorkspace(
    backend: AcpClientBackend(application),
    resolvers: [
      ioTransportResolver(
        secrets: ProfileSecretSource(environment, stored: profileSecrets),
      ),
      resolver,
    ],
  );
  return CliRuntime._(
    application,
    workspace,
    resolver,
    embeddedCloseTimeout,
    agentLogger,
    stderr,
  );
}

/// Транспорт до первого `connect`.
///
/// Почему: `AcpClientApplication` требует транспорт при создании, а
/// настоящий транспорт CLI открывает резолвер `ClientWorkspace.connect` по
/// профилю. Этот никогда не стартует и не отправляет кадров: до
/// подключения отправлять нечего.
final class _NotConnectedTransport implements AcpTransport {
  @override
  Stream<JsonRpcMessage> get inbound => const Stream.empty();

  @override
  Stream<AcpTransportEvent> get events => const Stream.empty();

  @override
  AcpTransportState get state => AcpTransportState.idle;

  @override
  Future<void> start() => Future.error(_notConnected());

  @override
  Future<void> send(JsonRpcMessage message) => Future.error(_notConnected());

  @override
  Future<void> close({Duration? timeout}) async {}

  static AcpTransportException _notConnected() => const AcpTransportException(
    code: AcpTransportErrorCode.disconnected,
    message: 'Not connected to an agent.',
  );
}
