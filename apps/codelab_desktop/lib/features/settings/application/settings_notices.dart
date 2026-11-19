/// Типизированные причины InfoBar «только чтение» и проблемы нечитаемого
/// конфига для страниц «MCP servers», «Agents & modes» и «Skills & extensions»
/// (change `add-desktop-localization`, итерация 5, D5 «Уточнение итерации 5»).
///
/// Почему: Cubit-ы этих страниц не подписаны на `AppStrings` и не хранят
/// готовый английский текст. Состояние несёт данные (чей агент, какая
/// проблема), а текст строит presentation по `context.l10n`; тогда уже
/// показанный InfoBar переводится вместе с деревом при смене языка.
library;

/// Причина «только чтение»: чей это агент.
///
/// Закрытый тип, как `SettingsAccess` моста: удалённый агент с адресом или
/// сторонний агент с именем.
sealed class ReadOnlyReason {
  const ReadOnlyReason();
}

/// Агент по WebSocket: его конфиг на чужой машине; [origin] — `wss://host:port`.
final class RemoteAgentReadOnly extends ReadOnlyReason {
  const RemoteAgentReadOnly(this.origin);

  final String origin;

  @override
  bool operator ==(Object other) =>
      other is RemoteAgentReadOnly && other.origin == origin;

  @override
  int get hashCode => Object.hash(RemoteAgentReadOnly, origin);

  @override
  String toString() => 'RemoteAgentReadOnly($origin)';
}

/// Сторонний stdio-агент: [agentName] — его имя из профиля.
final class ForeignAgentReadOnly extends ReadOnlyReason {
  const ForeignAgentReadOnly(this.agentName);

  final String agentName;

  @override
  bool operator ==(Object other) =>
      other is ForeignAgentReadOnly && other.agentName == agentName;

  @override
  int get hashCode => Object.hash(ForeignAgentReadOnly, agentName);

  @override
  String toString() => 'ForeignAgentReadOnly($agentName)';
}

/// Фраза самого app в списке проблем нечитаемого конфига.
enum AppSettingsProblemKind {
  /// `Cannot read the agent settings.`
  cannotReadSettings,

  /// `The CodeLab home folder is not available.`
  homeUnavailable,

  /// `The user config.yaml cannot be read.`
  userConfigUnreadable,

  /// `Cannot read the skills and extensions of this folder.`
  cannotReadExtensions,
}

/// Одна проблема списка нечитаемого конфига: фраза app (переводится) или
/// текст загрузчика ядра агента (показывается как есть, D6).
sealed class SettingsProblem {
  const SettingsProblem();
}

/// Фраза app по [kind].
final class AppSettingsProblem extends SettingsProblem {
  const AppSettingsProblem(this.kind);

  final AppSettingsProblemKind kind;

  @override
  bool operator ==(Object other) =>
      other is AppSettingsProblem && other.kind == kind;

  @override
  int get hashCode => Object.hash(AppSettingsProblem, kind);

  @override
  String toString() => 'AppSettingsProblem(${kind.name})';
}

/// Текст загрузчика ядра агента: `<путь ключа>: <проблема>`, как есть.
final class LoaderSettingsProblem extends SettingsProblem {
  const LoaderSettingsProblem(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      other is LoaderSettingsProblem && other.text == text;

  @override
  int get hashCode => Object.hash(LoaderSettingsProblem, text);

  @override
  String toString() => 'LoaderSettingsProblem';
}
