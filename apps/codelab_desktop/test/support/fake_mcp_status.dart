// Двойники панели «Agent status» страницы «MCP servers» (задача 5.4 change
// `add-provider-setup-ui`; design.md D12, D21): порт состояния MCP одной
// сессии и источник портов composition root.
//
// Почему двойники: настоящий порт даёт встроенный агент (`EmbeddedAgent.
// mcpStatus`), его поток проверяют тесты ядра и моста (5.1, 5.2); страница
// отвечает за то, как поток подписан, отменён и показан. Двойник считает
// подписки: «одна подписка» и «отмена при смене сессии» видны по [listeners]
// и [journal].
//
// Красный файл: порт `EmbeddedMcpStatusSource` появится в задаче 5.10
// (`features/settings/application/embedded_mcp_status_source.dart`).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_desktop/features/settings/application/embedded_mcp_status_source.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    show McpServerState, McpServerSummary, McpStatusPort;

/// Сводка сервера для таблицы.
McpServerSummary mcpSummary(
  String name, {
  int tools = 0,
  McpServerState state = McpServerState.connected,
  String? lastError,
  Duration? retryIn,
}) => McpServerSummary(
  name: name,
  toolCount: tools,
  state: state,
  lastError: lastError,
  retryIn: retryIn,
);

/// Порт сессии: снимок [servers], широковещательный поток [changes] и журнал
/// `reconnect`.
///
/// [journal] — события подписки: `listen <label>` и `cancel <label>`; по нему
/// тест проверяет порядок «прежняя подписка отменена до новой». Каждая
/// подписка считается отдельно ([listeners]): обычный broadcast-контроллер
/// вызывает `onListen` только для первого слушателя и вторую подписку бы
/// не показал.
final class FakeMcpStatusPort implements McpStatusPort {
  FakeMcpStatusPort(
    this.label, {
    List<McpServerSummary> servers = const [],
    List<String>? journal,
  }) : servers = [...servers],
       journal = journal ?? [];

  /// Имя порта в журнале (`p1`, `p2`).
  final String label;

  @override
  List<McpServerSummary> servers;

  /// Общий журнал подписок нескольких портов.
  final List<String> journal;

  /// Число живых подписок на [changes].
  var listeners = 0;

  final _subscribers = <MultiStreamController<List<McpServerSummary>>>[];
  var _closed = false;

  /// Имена, переданные в [reconnect], по порядку.
  final reconnected = <String>[];

  /// Если задан, `reconnect` ждёт его (проверка «по очереди»).
  Completer<void>? gate;

  @override
  Stream<List<McpServerSummary>> get changes => Stream.multi((controller) {
    if (_closed) {
      controller.closeSync();
      return;
    }
    listeners++;
    journal.add('listen $label');
    _subscribers.add(controller);
    controller.onCancel = () {
      if (_subscribers.remove(controller)) {
        listeners--;
        journal.add('cancel $label');
      }
    };
  }, isBroadcast: true);

  /// Присылает полный список сводок, как поток моста.
  void emit(List<McpServerSummary> next) {
    servers = [...next];
    for (final subscriber in [..._subscribers]) {
      subscriber.addSync(next);
    }
  }

  /// Закрывает поток: сессия или агент закрыты.
  void close() {
    _closed = true;
    for (final subscriber in [..._subscribers]) {
      _subscribers.remove(subscriber);
      listeners--;
      subscriber.closeSync();
    }
  }

  @override
  Future<void> reconnect(String name) async {
    reconnected.add(name);
    await gate?.future;
  }
}

/// Источник портов composition root: порт по id сессии.
final class FakeEmbeddedMcpStatusSource implements EmbeddedMcpStatusSource {
  /// Порты по id сессии; нет записи — `null`, как у закрытой сессии (Q18).
  final ports = <SessionId, FakeMcpStatusPort>{};

  /// Запросы `statusOf`, по порядку.
  final calls = <SessionId>[];

  @override
  McpStatusPort? statusOf(SessionId id) {
    calls.add(id);
    return ports[id];
  }
}
