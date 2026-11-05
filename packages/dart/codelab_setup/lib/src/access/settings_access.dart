/// Чьи настройки агента клиент вправе читать и писать (client-agent-setup
/// «Доступ к настройкам агента»; `dart-agent-and-clients` §12.4.2; design.md
/// change `add-provider-setup-ui`, D5).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart' show ConfigTarget;

/// Как запущен агент профиля: от этого зависит, лежит ли его конфиг у нас.
enum AgentLaunchKind {
  /// Встроенный агент в процессе app или CLI.
  embedded,

  /// Локальный процесс по stdio.
  stdio,

  /// Удалённый агент по WebSocket.
  webSocket,
}

/// Где лежат файлы конфигурации агента, которым клиент вправе управлять.
///
/// Почему данные без путей к файлам: сами файлы (`config.yaml`,
/// `config.local.yaml`) вычисляет писатель из `codelabHome` и [projectDir]
/// (`dart:io`, канонизация ссылок), а этот тип остаётся чистым и web-безопасным.
///
/// Как использовать: создаёт [resolveSettingsAccess]; `FileAgentConfigStore`
/// принимает его целиком.
final class ConfigPaths {
  const ConfigPaths({
    required this.codelabHome,
    this.projectDir,
    this.extraConfig,
  });

  /// `CODELAB_HOME` агента (возможно с `~`: раскрывает хост с `HOME` агента).
  final String codelabHome;

  /// Папка проекта; `null` — проектных слоёв для записи нет.
  final String? projectDir;

  /// Файл `--config` или `CODELAB_CONFIG`: читается агентом, но клиентом не
  /// пишется (SETUP-3).
  final String? extraConfig;
}

/// Можно ли этому клиенту писать конфиг агента, к которому он подключён (или
/// подключится).
///
/// Почему запечатанная иерархия: страницы настроек разбирают её `switch`-ом без
/// `default`, и новый вид доступа не пройдёт мимо компилятора.
sealed class SettingsAccess {
  const SettingsAccess();
}

/// Конфиг агента наш и доступен для правки в слоях `user` и `projectLocal`.
final class EditableSettings extends SettingsAccess {
  const EditableSettings(this.paths);

  final ConfigPaths paths;

  /// Папка проекта для слоя `projectLocal`.
  String? get cwd => paths.projectDir;

  /// Цели записи (SETUP-3): `user` и, если известна папка проекта,
  /// `projectLocal`. Слой 3 (`project`) и файл `--config` — только чтение.
  List<ConfigTarget> get targets => [
    const ConfigTarget.user(),
    if (paths.projectDir case final dir?) ConfigTarget.projectLocal(dir),
  ];
}

/// Агент по WebSocket: его конфиг на чужой машине и локально не читается
/// (SETUP-2).
final class RemoteReadOnly extends SettingsAccess {
  const RemoteReadOnly(this.endpoint);

  final Uri endpoint;
}

/// Сторонний stdio-агент: его конфигурация не наша (SETUP-2).
final class NotManaged extends SettingsAccess {
  const NotManaged(this.agentName);

  final String agentName;
}

/// Определяет доступ к настройкам по профилю подключения.
///
/// Почему простые данные, а не `ConnectionProfile` из kit: мост не зависит от
/// клиентских пакетов, поэтому вызывающий (app, CLI) сам раскладывает профиль.
///
/// Как использовать: для профиля ТЕКУЩЕГО подключения, а без подключения —
/// для профиля по умолчанию (D5); при смене подключения вызывается заново.
/// - [AgentLaunchKind.embedded] — [EditableSettings], `CODELAB_HOME` app
///   ([defaultCodelabHome]);
/// - [AgentLaunchKind.stdio] — [EditableSettings], если [command] — это
///   `codelab-agent` (по базовому имени, без `.exe`) и, когда клиент уже
///   подключён, [agentName] из `initialize` — тоже `codelab-agent`;
///   `CODELAB_HOME` берётся из [env] профиля, иначе [defaultCodelabHome]; файл
///   `--config` из [args] (или `CODELAB_CONFIG` из [env]) — только чтение.
///   Иначе [NotManaged] с именем агента (или команды);
/// - [AgentLaunchKind.webSocket] — [RemoteReadOnly]; [endpoint] обязателен.
///
/// [cwd] — папка проекта: передаётся, только если агент работает в ней (для
/// stdio — при `runInProjectDirectory`); `null` — слой `projectLocal` не
/// предлагается.
SettingsAccess resolveSettingsAccess({
  required AgentLaunchKind kind,
  String? command,
  String? agentName,
  List<String> args = const [],
  Map<String, String> env = const {},
  Uri? endpoint,
  String? cwd,
  required String defaultCodelabHome,
}) {
  switch (kind) {
    case AgentLaunchKind.embedded:
      return EditableSettings(
        ConfigPaths(codelabHome: defaultCodelabHome, projectDir: cwd),
      );
    case AgentLaunchKind.webSocket:
      if (endpoint == null) {
        throw ArgumentError.notNull('endpoint');
      }
      return RemoteReadOnly(endpoint);
    case AgentLaunchKind.stdio:
      final base = _baseName(command);
      // Команда решает, чей это конфиг; самоназвание из `initialize` только
      // опровергает (чужой агент под нашей командой), но не доказывает.
      final ours =
          base == _codelabAgent &&
          (agentName == null || agentName == _codelabAgent);
      if (!ours) {
        return NotManaged(agentName ?? base ?? 'unknown');
      }
      final home = env['CODELAB_HOME'];
      final envConfig = env['CODELAB_CONFIG'];
      return EditableSettings(
        ConfigPaths(
          codelabHome: home == null || home.isEmpty ? defaultCodelabHome : home,
          projectDir: cwd,
          extraConfig:
              _configFlag(args) ??
              (envConfig == null || envConfig.isEmpty ? null : envConfig),
        ),
      );
  }
}

const _codelabAgent = 'codelab-agent';

/// Базовое имя команды без каталога и суффикса `.exe`; `null` — команды нет.
String? _baseName(String? command) {
  if (command == null || command.isEmpty) {
    return null;
  }
  var name = command.split(RegExp(r'[/\\]')).last;
  if (name.toLowerCase().endsWith('.exe')) {
    name = name.substring(0, name.length - 4);
  }
  return name.isEmpty ? null : name;
}

/// Значение `--config <file>` или `--config=<file>` из аргументов агента.
String? _configFlag(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--config' && i + 1 < args.length) {
      return args[i + 1];
    }
    if (arg.startsWith('--config=')) {
      return arg.substring('--config='.length);
    }
  }
  return null;
}
