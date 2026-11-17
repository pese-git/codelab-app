import 'package:codelab_setup/codelab_setup.dart';

/// Результат команды порта [SetupCommands]: код выхода и строки потоков.
///
/// Почему свой тип: `ConfigCommandResult` живёт в `codelab_setup/io.dart`, а
/// `repl/` и `tui/` импортировать этот барель не вправе (сторож: только
/// `run.dart`; design.md change `add-provider-setup-ui`, D17).
final class SetupCommandResult {
  const SetupCommandResult({
    required this.exitCode,
    this.stdout = const [],
    this.stderr = const [],
  });

  final int exitCode;
  final List<String> stdout;
  final List<String> stderr;
}

/// Чьи настройки и откуда читать/писать: доступ профиля, его окружение и
/// папка снимка.
///
/// Почему один тип: пути (`CODELAB_HOME`, `--config`), `env` stdio-профиля
/// (для `api_key_env`, источника `env`) и папка проекта должны идти в порт
/// вместе и одинаково для всех методов (design.md change
/// `add-provider-setup-ui`, D5, D17).
///
/// Как использовать: строит команда через `settingsScopeOf`; [env] — `env`
/// stdio-профиля поверх окружения CLI, [cwd] — `access.cwd ?? cwd сессии`.
final class SetupScope {
  const SetupScope({
    required this.access,
    required this.cwd,
    this.env = const {},
  });

  final EditableSettings access;
  final String cwd;
  final Map<String, String> env;
}

/// Порт настройки агента для команд `/provider` и `/settings`.
///
/// Почему порт: реализацию (`ProviderCommands`, `FileAgentConfigStore`,
/// `ioProviderCheck`, `ClientSecretAccess`) собирает единственное место с
/// `codelab_setup/io.dart` — `run.dart`; REPL и TUI получают её через
/// `ReplContext.setup` и знают только основной барель моста (D17).
///
/// Для чего: каждый метод получает [SetupScope] — результат
/// `resolveSettingsAccess` для профиля подключения. Пути и окружение берутся
/// из него, а не из окружения клиента (SETUP-2, D5): запись идёт в конфиг
/// того агента, к которому подключены.
///
/// Как использовать: команда сначала проверяет доступ (`settingsAccessOf`) и
/// только для `EditableSettings` вызывает порт.
abstract interface class SetupCommands {
  /// Домашний каталог клиента: умолчание для `resolveSettingsAccess`.
  String get codelabHome;

  /// Снимок и запись файлов конфига (SETUP-6: конфликт, без автоповтора).
  Future<AgentConfigStore> configStore(SetupScope scope);

  /// `/provider list` — вывод `ProviderCommands.list`.
  Future<SetupCommandResult> listProviders(SetupScope scope);

  /// `/provider remove <id>`: слой `user` или, с [local], `projectLocal`.
  Future<SetupCommandResult> removeProvider(
    String id,
    SetupScope scope, {
    required bool local,
  });

  /// Новый автомат мастера `/provider add`.
  Future<ProviderSetupFlow> newProviderFlow(SetupScope scope);
}
