import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart' show McpStatusPort;

/// Встроенный агент, соединённый с клиентом парой `InProcessAcpLink`.
///
/// Почему интерфейс: клиентам нужны только транспорт и жизненный цикл, а
/// сборка ядра, сервера и ресурсов — забота `createEmbeddedAgent` (design.md
/// change `add-embedded-agent-mode`, D2, D6).
///
/// Как использовать: [clientTransport] отдаётся ACP-клиенту (`start()` вызывает
/// клиент); [dispose] — при закрытии хоста. Один агент обслуживает одно
/// соединение: клиент закрыл свой конец — агент завершается.
abstract interface class EmbeddedAgent {
  /// Клиентский конец пары.
  AcpTransport get clientTransport;

  /// В файлах конфига при открытии нашлись секреты-литералы (предупреждение
  /// `config.secret.in_file`).
  ///
  /// Почему здесь: app не называет типы ядра (PKG-4) и не разбирает лог, а
  /// кнопка «Перенести секреты» должна знать, показывать ли предложение
  /// (design.md change `add-config-literal-secrets-and-migrate`, D8, R8-3).
  /// Признак несёт только «да/нет»: ни значений, ни путей ключей, ни текстов.
  ///
  /// Как использовать: читается после открытия; вычисляется один раз при
  /// открытии и перезагрузкой конфига или переносом секретов не пересчитывается
  /// — актуальным станет после переподключения (D8, п. 1). Мигратор для app
  /// живёт в `io.dart`, этот барель web-безопасен.
  bool get secretsInConfig;

  /// Состояние MCP-серверов сессии [sessionId] для хоста (design.md change
  /// `add-provider-setup-ui`, D12, решение Q18; SETUP-11).
  ///
  /// Почему здесь: хосту (desktop) нужна живая таблица «Agent status» без
  /// промпта и без разбора текста `/mcp list`, а `package:codelab_agent_*` ему
  /// импортировать нельзя (PKG-4). Идентификатор сессии ACP у встроенного
  /// агента совпадает с `SessionId` рантайма.
  ///
  /// Как использовать: порт есть у любой открытой сессии (без серверов
  /// `servers` пуст, `changes` пришлёт появившиеся позже); `null` — сессия
  /// неизвестна или закрыта. Потоки порта закрываются с сессией и с
  /// [dispose].
  McpStatusPort? mcpStatus(String sessionId);

  /// Завершается после [dispose], явного или вызванного закрытием соединения.
  Future<void> get closed;

  /// Останавливает агента: ходы отменяются, журнал дописывается, ресурсы
  /// освобождаются. Идемпотентен — повторный вызов возвращает тот же `Future`.
  Future<void> dispose();
}

/// Открыватель агента для резолвера клиента: прод — из `io.dart`, тест — из
/// `testing.dart` (design.md change `add-embedded-agent-mode`, D2).
///
/// [cwd] — папка проекта (слои конфигурации, корень файлов), [hostProfile] —
/// `embedded-app-desktop` или `embedded-cli`.
typedef EmbeddedAgentOpener =
    Future<EmbeddedAgent> Function({
      required String cwd,
      required String hostProfile,
    });
