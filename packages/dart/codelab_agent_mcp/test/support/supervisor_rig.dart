// Барель пакета сужен до API хоста; тесты проверяют внутренние типы.
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:codelab_agent_mcp/testing.dart';

import 'harness.dart';

/// Фабрика транспортов для тестов супервизора: пишет описания серверов,
/// которые получил `open` (так видно, что раскрытые секреты разные на разных
/// попытках), и умеет задерживать `open` до сигнала теста.
///
/// Почему обёртка, а не наследник: `FakeMcpTransportFactory` — `final`.
final class SpyTransportFactory implements McpTransportFactory {
  SpyTransportFactory(this.inner);

  final FakeMcpTransportFactory inner;

  /// Описания в порядке открытия.
  final configs = <McpServerConfig>[];

  /// Если задан, следующий `open` ждёт его завершения.
  Completer<void>? gate;

  @override
  Set<String> get transports => inner.transports;

  List<String> get opened => inner.opened;

  @override
  Future<McpTransport> open(
    McpServerConfig server, {
    required String cwd,
    required CancelToken cancel,
    required Logger logger,
  }) async {
    configs.add(server);
    if (gate case final waiting?) {
      gate = null;
      await waiting.future;
    }
    return inner.open(server, cwd: cwd, cancel: cancel, logger: logger);
  }
}

/// Стенд тестов переподключения: `FakeClock`, `Random(0)`, серверы в
/// памяти и коннектор над ними (design.md change
/// `add-config-writer-and-reload`, D11; PKG-6).
///
/// Как использовать: `rig.connect([...])` подключает серверы, `rig.crash(name)`
/// роняет транспорт, `rig.settle()` отдаёт управление очереди событий, а
/// `h.clock.elapse` двигает время.
final class SupervisorRig {
  SupervisorRig(this.fakes, {Map<String, String>? failures, int seed = 0})
    : failures = failures ?? {},
      random = Random(seed) {
    spy = SpyTransportFactory(
      FakeMcpTransportFactory(fakes, failures: this.failures),
    );
    connector = McpClientConnector(
      transports: McpTransports(stdio: spy, http: spy),
      clock: h.clock,
      random: random,
    );
  }

  final h = McpHarness();
  final Map<String, FakeMcpServer> fakes;

  /// Ошибки запуска по имени сервера; тест может менять карту на лету.
  final Map<String, String> failures;
  final Random random;
  late final SpyTransportFactory spy;
  late final McpClientConnector connector;
  final _cancel = CancelTokenSource();

  /// Отмена токена запроса: `close()` сессии или `dispose()` рантайма.
  void cancelSession() => _cancel.cancel();

  Logger get logger => h.logger;
  RecordingLogger get log => h.logger;
  FakeClock get clock => h.clock;

  McpConnectRequest request(
    List<McpServerConfig> servers, {
    McpSecretExpander? expandSecrets,
    Set<String> reserved = const {'read', 'write'},
  }) => McpConnectRequest(
    sessionId: const SessionId('s1'),
    cwd: '/proj',
    servers: servers,
    reservedNames: reserved,
    logger: h.logger,
    cancel: _cancel.token,
    expandSecrets: expandSecrets,
  );

  Future<McpSessionTools> connect(
    List<McpServerConfig> servers, {
    McpSecretExpander? expandSecrets,
  }) => connector.connect(request(servers, expandSecrets: expandSecrets));

  /// Отдаёт управление очереди событий и таймерам с нулевой задержкой.
  Future<void> settle() => h.clock.elapse(Duration.zero);

  /// Сервер падает; клиент и коннектор узнают об этом после [settle].
  Future<void> crash(String name, {String? reason}) async {
    if (reason == null) {
      fakes[name]!.crash();
    } else {
      fakes[name]!.crash(reason: reason);
    }
    await settle();
  }
}

McpStdioServerConfig stdio(
  String name, {
  McpServerOrigin origin = McpServerOrigin.session,
  bool enabled = true,
}) => McpStdioServerConfig(
  name: name,
  command: '/usr/bin/$name',
  origin: origin,
  enabled: enabled,
);

FakeMcpServer fakeServer(List<String> tools) => FakeMcpServer(
  era: FakeMcpEra.modern,
  tools: [for (final t in tools) FakeMcpTool(t)],
);

McpServerSummary summaryOf(McpSessionTools session, String name) =>
    session.servers.firstWhere((s) => s.name == name);

/// Базовая задержка повтора для номера сбоя (с 0): `min(30, 2^n)` секунд.
Duration baseDelay(int attempt) =>
    Duration(seconds: min(30, pow(2, attempt).toInt()));

/// Задержка укладывается в `[base, base * 1.2]` и не больше 30 с.
bool delayWithinBounds(Duration delay, int attempt) {
  final base = baseDelay(attempt);
  final upper = Duration(
    microseconds: min(
      const Duration(seconds: 30).inMicroseconds,
      (base.inMicroseconds * 1.2).ceil(),
    ),
  );
  return delay >= base && delay <= upper;
}
