import '../host/host_profile.dart';
import '../util/logger.dart';

/// Ключи конфигурации, которые читает хост, а не ядро (`agent-core-
/// architecture` §15.1; design.md change `add-agent-configuration`, D3).
///
/// Почему отдельно от `CoreConfig`: журналы сессий, файл лога и сужение
/// профиля настраивает composition root; ядро не должно получать поля,
/// которых не читает.
///
/// Как использовать: хост берёт значения из `ConfigLoadResult.host`;
/// `null` в поле — ключ не задан, действует умолчание хоста
/// (`$CODELAB_HOME/sessions`, `fsync: checkpoints`, уровень `info`; файл лога
/// по умолчанию не создаётся — OQ5 (а)).
final class HostSettings {
  const HostSettings({
    this.sessionsDir,
    this.fsync,
    this.logLevel,
    this.logFile,
    this.secretsBackend,
    this.profileNarrowing = const {},
  });

  /// `sessions.dir` (путь, `~` раскрыт).
  final String? sessionsDir;

  /// `sessions.fsync`: `checkpoints` | `always` | `never` (§8.5). Строкой:
  /// перечисление живёт в `codelab_agent_io` (`FsyncPolicy`).
  final String? fsync;

  /// `logging.level`.
  final LogLevel? logLevel;

  /// `logging.file`, только явно заданный (OQ5 (а)).
  final String? logFile;

  /// `secrets.backend`: `auto` | `env` | `file` (`keychain` — проблема
  /// конфигурации, хранилища ОС появятся после 1.0; design.md change
  /// `add-agent-secret-store`, D7). Читается из пользовательского слоя и
  /// `--config`: проект переключить хранилище на открытый файл не может.
  /// `null` — ключ не задан, действует `auto`. Строкой: перечисление живёт в
  /// `codelab_agent_io`. Потребитель — хост (`openHostSecrets`).
  final String? secretsBackend;

  /// `profile.<name>.<capability>`: уже проверенное сужение (расширение
  /// профиля — проблема конфигурации, а не исключение сборки).
  final Map<String, Map<HostCapability, CapabilityState>> profileNarrowing;
}
