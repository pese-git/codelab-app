import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:http/http.dart' as web;

/// Конфигурация встроенного агента: результат загрузчика конфигурации и
/// профиль хоста (design.md change `add-embedded-agent-mode`, D2).
///
/// Почему не `ProviderConfig`: конфиг 8.5 — это `CoreConfig` с несколькими
/// провайдерами и маршрутизацией; свой тип продублировал бы схему.
///
/// Как использовать: открыватель хоста берёт [core] и [host] из
/// `ConfigLoadResult` и передаёт вместе с [hostProfile] в
/// `createEmbeddedAgent`.
final class EmbeddedAgentConfig {
  const EmbeddedAgentConfig({
    required this.hostProfile,
    required this.core,
    required this.host,
  });

  /// `embedded-app-desktop` или `embedded-cli` (`mobile` и `web` — этап 10).
  final String hostProfile;

  /// Провайдеры, модель по умолчанию, MCP, `permissions.mode` и прочее.
  final CoreConfig core;

  /// `secretsBackend`, `sessionsDir`, `fsync` и сужение профилей.
  final HostSettings host;
}

/// Ресурсы хоста встроенного агента; создаёт `io.dart` (настольные хосты) или
/// тест (design.md change `add-embedded-agent-mode`, D2).
///
/// Почему отдельный объект: пакет не создаёт `http.Client`, `Clock`, `Random`
/// и `IdGenerator` сам (PKG-6) и не знает, где лежат файлы и журнал.
///
/// Как использовать: поля передаются в `AgentCoreServices` как есть.
/// [localEnv] — фабрика env сессии по её `cwd`; сервер вызывает её с `/` при
/// создании, поэтому она должна быть чистой и дешёвой (без обращения к ФС).
/// Containment по `cwd` даёт `BoundedEnv` ядра (ENV-2), фабрика его не строит.
final class EmbeddedHostServices {
  const EmbeddedHostServices({
    required this.baseEnv,
    required this.localEnv,
    required this.sessions,
    required this.secrets,
    required this.http,
    required this.logger,
    required this.clock,
    required this.ids,
    required this.random,
    required this.platform,
    this.closeHttpOnDispose = false,
    this.mcp,
    this.projectFiles,
  });

  /// Локальный env хоста: базовое окружение инструментов ядра.
  final ExecutionEnv baseEnv;

  /// Env сессии для `AcpServerConfig.localEnv` (профили `embedded-*`, D4).
  /// Для других профилей (только `testing.dart`) используется как локальный
  /// листинг, а файлы и команды идут через клиента, как у бинаря по stdio.
  final ExecutionEnv Function(String cwd) localEnv;

  final SessionStore sessions;
  final SecretResolver secrets;

  /// HTTP-клиент провайдеров и MCP.
  final web.Client http;

  /// Закрывать [http] в `dispose`: `true`, если клиент создан хостом.
  final bool closeHttpOnDispose;

  final Logger logger;
  final Clock clock;
  final IdGenerator ids;

  /// Случайность для джиттера повторов провайдеров (PKG-6).
  final Random random;

  /// Платформа для системного промпта (`Platform.operatingSystem`).
  final String platform;

  final McpConnector? mcp;
  final ProjectFilesSource? projectFiles;
}

/// Невалидная конфигурация встроенного агента: проблемы загрузчика без
/// значений секретов (CFG-2; design.md change `add-embedded-agent-mode`, D5).
///
/// Как использовать: открыватель хоста бросает её до создания ресурсов
/// (`io.dart`) и передаёт [issues] загрузчика и каталог состояния
/// [home] (`codelabHomeOf`). CLI печатает [message] в stderr с кодом `64`, app
/// показывает его в баннере соединения. Текст — строки
/// `<location>: [<key>: ]<message>` формы `config check` и последней строкой
/// подсказка; значений ключей в нём нет, потому что [ConfigIssue] их не хранит.
final class EmbeddedAgentConfigException implements Exception {
  EmbeddedAgentConfigException(this.issues, {required String home})
    : message = [
        for (final issue in issues) '$issue',
        'Configure the embedded agent in $home/config.yaml; '
            'check it with: codelab config check',
      ].join('\n');

  final List<ConfigIssue> issues;

  /// Готовый текст для stderr и баннера.
  final String message;

  @override
  String toString() => 'EmbeddedAgentConfigException: $message';
}
