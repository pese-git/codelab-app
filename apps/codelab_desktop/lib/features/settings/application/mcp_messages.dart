import 'package:codelab_setup/codelab_setup.dart'
    show McpServerRefusal, SecretCleanup;

/// Исход очистки секрета [name] для строки баннера (SETUP-24).
///
/// Хранит имя и исход [cleanup], а не фразу: фраза и команда
/// `codelab secret delete <имя>` строятся presentation (D5, D7).
final class McpSecretNote {
  const McpSecretNote(this.name, this.cleanup);

  final String name;
  final SecretCleanup cleanup;

  @override
  String toString() => 'McpSecretNote($name, ${cleanup.name})';
}

/// Причина отказа записи, у которой нет собственного сообщения.
enum McpWriteFailure {
  /// `The MCP server settings changed. Review the page and try again.`
  settingsChanged,

  /// `The secret store could not be read, so nothing was saved.`
  secretStoreUnreadable,

  /// `The change was not saved because of an error.`
  changeNotSaved,

  /// `The config changed on disk, so nothing was saved. …`
  conflict,

  /// `The config was not saved: <проблемы ядра>`; проблемы — в `issues`.
  rejected,

  /// `The config was not saved: <key> must not hold a literal secret.`
  inlineSecret,

  /// `The config was not saved because of an error.`
  configNotSaved,
}

/// Разовое сообщение баннера страницы «MCP servers» (`mcp-banner`).
///
/// Почему закрытая иерархия: баннер — исход действия, которое не повторится;
/// строку из входов не пересобрать. Состояние хранит тип с аргументами (имя
/// сервера, секреты с исходом `SecretCleanup`, отказ `McpServerRefusal`), а
/// текст строит presentation на текущем языке. Тексты ядра агента
/// (`ConfigSaved.warnings`, `ConfigIssue.message`) и хранилища
/// (`McpSecretNotStored.reason`) лежат строками-аргументами и показываются
/// как есть под переведённым заголовком (D6). Образец — `ProviderMessage`.
///
/// Заглушка задачи 5.1c: типы нужны тестам; Cubit их пока не создаёт.
sealed class McpMessage {
  const McpMessage();
}

/// `Server <name> saved.` (после записи; [restartHint] — «запустится после
/// перезапуска агента», [warnings] — предупреждения записи как есть,
/// [secrets] — оставленные и неудалённые секреты).
final class McpServerSavedMessage extends McpMessage {
  const McpServerSavedMessage(
    this.server, {
    this.restartHint = false,
    this.warnings = const [],
    this.secrets = const [],
  });

  final String server;
  final bool restartHint;
  final List<String> warnings;
  final List<McpSecretNote> secrets;
}

/// `Server <name> enabled.` с подсказкой перезапуска.
final class McpServerEnabledMessage extends McpMessage {
  const McpServerEnabledMessage(this.server);

  final String server;
}

/// `Server <name> removed.` и итог очистки секретов.
final class McpServerRemovedMessage extends McpMessage {
  const McpServerRemovedMessage(this.server, {this.secrets = const []});

  final String server;
  final List<McpSecretNote> secrets;
}

/// Секрет не записан ([reason] — текст хранилища как есть); [notRolledBack] —
/// секреты, которые откат не удалил (имя и команда для ручного удаления).
final class McpSecretNotStoredMessage extends McpMessage {
  const McpSecretNotStoredMessage(this.reason, {this.notRolledBack = const []});

  final String reason;
  final List<String> notRolledBack;
}

/// Мост отказал в действии над сервером.
final class McpRefusedMessage extends McpMessage {
  const McpRefusedMessage(this.reason);

  final McpServerRefusal reason;
}

/// Запись не выполнена по причине [failure]; [issues] — проблемы ядра как
/// есть (`rejected`), [key] — путь ключа (`inlineSecret`), [notRolledBack] и
/// [replacedSecrets] — секреты, о которых нужно сказать отдельной строкой.
final class McpWriteFailedMessage extends McpMessage {
  const McpWriteFailedMessage(
    this.failure, {
    this.issues,
    this.key,
    this.notRolledBack = const [],
    this.replacedSecrets = const [],
  });

  final McpWriteFailure failure;
  final String? issues;
  final String? key;
  final List<String> notRolledBack;
  final List<String> replacedSecrets;
}
