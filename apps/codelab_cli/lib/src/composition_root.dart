import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart';

import 'cli_args.dart';
import 'cli_logger.dart';
import 'profiles/profile_arg.dart';

/// Собранный клиентский слой одного запуска `codelab`.
///
/// Почему: CLI использует kit так же, как app — `ClientWorkspace` поверх
/// `AcpClientApplication`, настоящие транспорты из `codelab_client_io`;
/// своего состояния сессий у CLI нет (design.md change `add-codelab-cli`,
/// D2, D3).
///
/// Как использовать: `buildCliRuntime(environment: …, stderr: …, verbose:
/// …)`; после работы — [dispose], который закрывает транспорт и завершает
/// процесс агента.
final class CliRuntime {
  CliRuntime._(this.application, this.workspace);

  final AcpClientApplication application;
  final ClientWorkspace workspace;

  Future<void> dispose() async {
    await workspace.dispose();
    await application.dispose();
  }
}

/// Composition root CLI: ядро клиента, резолвер транспортов и рабочее
/// пространство.
///
/// [environment] даёт токен WebSocket (`CODELAB_AGENT_TOKEN`); [verbose] —
/// лог ядра клиента в [stderr], иначе лог выключен: stdout и stderr headless
/// не должны засоряться служебными строками.
CliRuntime buildCliRuntime({
  required Map<String, String> environment,
  required StringSink stderr,
  required bool verbose,
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
  final workspace = ClientWorkspace(
    backend: AcpClientBackend(application),
    resolvers: [ioTransportResolver(secrets: EnvSecretSource(environment))],
  );
  return CliRuntime._(application, workspace);
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
