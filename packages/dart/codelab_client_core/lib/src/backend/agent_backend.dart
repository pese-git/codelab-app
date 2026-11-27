import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';

/// Источник данных kit: соединение и сессии одного агента.
///
/// Почему: kit не должен зависеть от того, как именно клиент говорит с
/// агентом; сейчас это ACP через `AcpClientApplication`, позже может
/// появиться прямой вызов ядра агента без смены UI (`09-10`, §4.5;
/// design D3).
///
/// Для чего: внутренний порт `ClientWorkspace`. Поздние события старого
/// соединения реализация отбрасывает сама (`AGENTS.md` §9): после
/// `reconnect` потоки несут только события нового поколения.
///
/// Как использовать: передать в `ClientWorkspace(backend: ...)`. Члены
/// появляются вместе с итерацией, которая переносит их потребителя в kit
/// (design D12); ошибки — исключения `codelab_client_acp`, как у
/// `AcpClientApplication`.
abstract interface class AgentBackend {
  Stream<ClientConnectionState> get connectionStates;

  Stream<AcpSession> get sessionChanges;

  /// Уведомления `_codelab/session/usage` текущих соединений: сырые `params`
  /// и поколение (change `add-usage-extension`, D8, D21 Т2). Кадры прежнего
  /// транспорта реализация отбрасывает сама, как и для остальных потоков.
  Stream<UsageNotification> get usageNotifications;

  /// Кадры ACP текущих соединений (change `redesign-protocol-pane`, D2, D5);
  /// кадры прежнего транспорта реализация отбрасывает сама. Поток закрывается
  /// владельцем ядра.
  Stream<ProtocolFrame> get protocolFrames;

  /// Базовая политика payload ядра клиента (D3 change
  /// `redesign-protocol-pane`, «Текст ошибки агента»).
  ///
  /// Почему в порту: kit решает по ней, что писать в `WorkspaceDiagnostic` о
  /// сбое — текст агента (`full`) или только метаданные (`metadataOnly`).
  /// Единственный источник — параметр конструктора ядра; второго параметра у
  /// kit нет, рассинхронизация невозможна. Это не действующая политика
  /// кадров: режим Trace её не меняет.
  ProtocolPayloadPolicy get protocolPayloads;

  /// Режим Trace кадров возможен: базовая политика ядра — `metadataOnly`
  /// (D17).
  bool get traceAvailable;

  /// Включает или выключает режим Trace кадров (D17); при
  /// `traceAvailable == false` — без эффекта.
  void setFrameTrace(bool enabled);

  /// Поколение текущего соединения (растёт при замене транспорта): по нему
  /// kit отличает ответ запроса старого соединения (`AGENTS.md` §9).
  int get generation;

  Future<ClientConnectionState> connect(AcpTransport transport);

  Future<ClientConnectionState> reconnect(ReconnectCommand command);

  Future<AcpSession> createSession(CreateSessionCommand command);

  /// Страница `session/list`; только при `sessionCapabilities.list`.
  Future<SessionListPage> listSessions({String? cwd, String? cursor});

  /// `session/load`: сессия с ходами из реплея агента.
  Future<AcpSession> loadSession(LoadSessionCommand command);

  Future<PromptTurn> sendPrompt(SendPromptCommand command);

  Future<PromptTurn> cancelTurn(CancelTurnCommand command);

  Future<ApprovalRequest> respondToPermission(
    RespondToPermissionCommand command,
  );

  Future<AcpSession> setSessionConfigOption(
    SetSessionConfigOptionCommand command,
  );

  /// Журнал usage сессии `_codelab/session/usage/ledger` (change
  /// `add-usage-ledger`, D9): сырой результат и поколение отправки; только
  /// при объявленном агентом `usageLedger`, иначе — исключение без кадра.
  Future<UsageLedgerReply> requestUsageLedger({
    required SessionId sessionId,
    bool rebuild = false,
  });
}

/// [AgentBackend] поверх `AcpClientApplication`.
///
/// Почему: ядро клиента уже реализует ACP, поколения соединения и
/// отбрасывание поздних кадров; kit не дублирует это.
///
/// Для чего: единственная реализация порта на этом change.
///
/// Как использовать: `AcpClientBackend(application)`. Владелец
/// `application` — тот, кто его создал: бэкенд и `ClientWorkspace.dispose`
/// его не закрывают.
final class AcpClientBackend implements AgentBackend {
  const AcpClientBackend(this._application);

  final AcpClientApplication _application;

  @override
  Stream<ClientConnectionState> get connectionStates =>
      _application.connectionStateChanges;

  @override
  Stream<AcpSession> get sessionChanges => _application.sessionChanges;

  @override
  Stream<UsageNotification> get usageNotifications =>
      _application.usageNotifications;

  @override
  Stream<ProtocolFrame> get protocolFrames => _application.protocolFrames;

  @override
  ProtocolPayloadPolicy get protocolPayloads => _application.protocolPayloads;

  @override
  bool get traceAvailable => _application.traceAvailable;

  @override
  void setFrameTrace(bool enabled) => _application.setFrameTrace(enabled);

  @override
  int get generation => _application.generation;

  @override
  Future<ClientConnectionState> connect(AcpTransport transport) =>
      _application.connect(transport);

  @override
  Future<ClientConnectionState> reconnect(ReconnectCommand command) =>
      _application.reconnect(command);

  @override
  Future<AcpSession> createSession(CreateSessionCommand command) =>
      _application.createSession(command);

  @override
  Future<SessionListPage> listSessions({String? cwd, String? cursor}) =>
      _application.listSessions(cwd: cwd, cursor: cursor);

  @override
  Future<AcpSession> loadSession(LoadSessionCommand command) =>
      _application.loadSession(command);

  @override
  Future<PromptTurn> sendPrompt(SendPromptCommand command) =>
      _application.sendPrompt(command);

  @override
  Future<PromptTurn> cancelTurn(CancelTurnCommand command) =>
      _application.cancelTurn(command);

  @override
  Future<ApprovalRequest> respondToPermission(
    RespondToPermissionCommand command,
  ) => _application.respondToPermission(command);

  @override
  Future<AcpSession> setSessionConfigOption(
    SetSessionConfigOptionCommand command,
  ) => _application.setSessionConfigOption(command);

  @override
  Future<UsageLedgerReply> requestUsageLedger({
    required SessionId sessionId,
    bool rebuild = false,
  }) => _application.requestUsageLedger(sessionId: sessionId, rebuild: rebuild);
}
