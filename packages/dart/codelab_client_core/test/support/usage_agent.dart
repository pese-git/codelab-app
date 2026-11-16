// Обвязка тестов usage kit (задачи 2.5, 2.7b change `add-usage-extension`;
// design.md, D14, D21 Т4, Т5): рабочее пространство на `FakeAcpTransport`,
// в котором тест играет агента, плюс журнал, который копит записи kit.
//
// Почему не `KitAgent`: ему нужен необязательный `Logger` у `ClientWorkspace`
// (`usage.stale`, `usage.decode_failed`, D21 Т5), а добавление параметра
// туда зависело бы от кода итерации 2.9. Собственная обвязка держит красными
// только тесты usage, а не весь набор kit.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

/// Запись журнала: уровень, событие и контекст вместе с привязанным.
typedef LogEntry = ({
  String level,
  String? event,
  Map<String, Object?> context,
});

/// Журнал, копящий записи всех дочерних логгеров (`bind`, `withCorrelation`)
/// в один список: тесту нужен состав записей, а не их вывод.
final class RecordingLogger implements Logger {
  RecordingLogger([List<LogEntry>? entries, Map<String, Object?>? context])
    : entries = entries ?? <LogEntry>[],
      _context = context ?? const {};

  final List<LogEntry> entries;
  final Map<String, Object?> _context;

  /// Записи события [event].
  Iterable<LogEntry> where(String event) =>
      entries.where((entry) => entry.event == event);

  @override
  Logger bind(Map<String, Object?> context) =>
      RecordingLogger(entries, {..._context, ...context});

  @override
  Logger withCorrelation({
    String? sessionId,
    String? requestId,
    int? connectionGeneration,
    String? toolCallId,
    String? messageId,
    String? operationId,
  }) => RecordingLogger(entries, {
    ..._context,
    'session_id': ?sessionId,
    'request_id': ?requestId,
    'connection_generation': ?connectionGeneration,
    'tool_call_id': ?toolCallId,
    'message_id': ?messageId,
    'operation_id': ?operationId,
  });

  void _add(String level, String? event, Map<String, Object?>? context) =>
      entries.add((
        level: level,
        event: event,
        context: {..._context, ...?context},
      ));

  @override
  void trace(String? event, {Map<String, Object?>? context}) =>
      _add('trace', event, context);

  @override
  void debug(String? event, {Map<String, Object?>? context}) =>
      _add('debug', event, context);

  @override
  void info(String? event, {Map<String, Object?>? context}) =>
      _add('info', event, context);

  @override
  void warning(String? event, {Map<String, Object?>? context}) =>
      _add('warning', event, context);

  @override
  void error(String? event, {Map<String, Object?>? context}) =>
      _add('error', event, context);

  @override
  void critical(String? event, {Map<String, Object?>? context}) =>
      _add('critical', event, context);
}

/// Агент для тестов usage: рабочее пространство с журналом [logger].
final class UsageAgent {
  UsageAgent({AgentCapabilities capabilities = const AgentCapabilities()}) {
    transport.initializeAgentCapabilities = capabilities;
  }

  /// Транспорт текущего «процесса» агента; резолвер читает его при каждом
  /// открытии, поэтому [restartAgent] подменяет агента для `reconnect`.
  var transport = FakeAcpTransport();

  /// Что выполнить при открытии нового транспорта — после `suspend`
  /// сессий и до замены транспорта в ядре клиента. Через неё тест вставляет
  /// кадр старого агента в окно, где поколение ещё прежнее (D21 Т2).
  void Function(FakeAcpTransport previous)? beforeOpen;

  final logger = RecordingLogger();
  final application = AcpClientApplication(transport: FakeAcpTransport());
  late final ClientWorkspace workspace = ClientWorkspace(
    backend: AcpClientBackend(application),
    resolvers: [
      ConfigTransportResolver(
        stdio: (_) {
          final next = transport;
          final hook = beforeOpen;
          if (hook != null) {
            hook(_opened ?? next);
          }
          _opened = next;
          return next;
        },
      ),
    ],
    logger: logger,
  );
  FakeAcpTransport? _opened;

  /// Новый «процесс» агента для следующего `reconnect()`.
  void restartAgent({
    AgentCapabilities capabilities = const AgentCapabilities(),
  }) =>
      transport = FakeAcpTransport()
        ..initializeAgentCapabilities = capabilities;

  Future<void> start() => workspace.connect(
    const StdioProfile(id: 'agent', label: 'Agent', command: 'agent'),
    projectDirectory: '/work',
  );

  Future<SessionHandle> newSession(String id) async {
    final request = next(sessionNewMethod);
    final handle = workspace.newSession();
    respond(await request, {'sessionId': id});
    return handle;
  }

  Future<JsonRpcRequest> next(String method) async =>
      await transport.sent.firstWhere(
            (message) => message is JsonRpcRequest && message.method == method,
          )
          as JsonRpcRequest;

  void respond(JsonRpcRequest request, Object? result) => transport.emitInbound(
    JsonRpcMessage.response(id: request.id, result: result),
  );

  /// Присылает уведомление `_codelab/session/usage` с [params] по
  /// транспорту [on] (по умолчанию — текущему).
  void usage(Map<String, Object?> params, {FakeAcpTransport? on}) =>
      (on ?? transport).emitInbound(
        JsonRpcMessage.notification(
          method: '_codelab/session/usage',
          params: params,
        ),
      );

  Future<void> dispose() async {
    await workspace.dispose();
    await application.dispose();
  }
}

/// Объявление агента `usage: {"version": 1}` (D3).
const usageCapabilities = AgentCapabilities(
  meta: {
    'codelab': {
      'usage': {'version': 1},
    },
  },
);

/// То же, что [usageCapabilities], плюс `loadSession`.
const usageLoadCapabilities = AgentCapabilities(
  loadSession: true,
  meta: {
    'codelab': {
      'usage': {'version': 1},
    },
  },
);

/// Десятичная строка денег D9 из целых микроединиц: до 6 знаков без
/// хвостовых нулей.
String moneyString(int micros) {
  final whole = micros ~/ 1000000;
  final fraction = (micros % 1000000)
      .toString()
      .padLeft(6, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}

Map<String, Object?> _tokens(int input, int output) => {
  'input': input,
  'output': output,
  'cacheRead': 0,
  'cacheWrite': 0,
};

/// Параметры `_codelab/session/usage` (D2) для тестов: агрегаты хода и
/// сессии с токенами и деньгами [turnMicros] и [sessionMicros]; [turnId]
/// `null` — снимок `compaction` без хода.
Map<String, Object?> usageParams({
  required String sessionId,
  required int seq,
  String trigger = 'turn',
  String? turnId = 'turn-1',
  int turnTokens = 100,
  int sessionTokens = 100,
  int turnMicros = 1000,
  int sessionMicros = 1000,
  List<String>? partial,
  Map<String, Object?>? context,
}) => {
  'sessionId': sessionId,
  'seq': seq,
  'trigger': trigger,
  'turnId': ?turnId,
  if (turnId != null)
    'turn': {
      'steps': 1,
      'tokens': _tokens(turnTokens, 0),
      'cost': moneyString(turnMicros),
    },
  'session': {
    'turns': 1,
    'steps': 1,
    'tokens': _tokens(sessionTokens, 0),
    'cost': moneyString(sessionMicros),
    'partial': ?partial,
  },
  'currency': 'USD',
  'context': ?context,
};
