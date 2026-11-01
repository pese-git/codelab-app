import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

/// Компиляция реэкспортов подкоманды `secret` и `SecretAdmin`
/// (change `add-agent-secret-store`, задача 9.1, D15): клиенту, которому
/// запрещён `package:codelab_agent_*`, эти символы доступны через мост.
void main() {
  test('io.dart exposes the secret command symbols', () {
    // Ссылки на типы: тест падает на компиляции, если реэкспорта нет.
    final types = <Type>[
      SecretCommands,
      SecretCommandResult,
      SecretSetOptions,
      SecretDeleteOptions,
      SecretListOptions,
      SecretInput,
      StdinSecretInput,
      MultilineSecretException,
      SecretAdmin,
      SecretWriteOutcome,
      SecretDeleteOutcome,
      SecretListOutcome,
      SecretStored,
      SecretUpdated,
      SecretInvalidName,
      SecretInvalidValue,
      SecretCollision,
      SecretReadOnly,
      SecretFailed,
      SecretDeleted,
      SecretNotSet,
      SecretListing,
      SecretListFailed,
    ];
    expect(types, hasLength(23));
    // Функция-фабрика бэкенда (D15) — тоже часть моста.
    expect(openSecretStore, isA<Function>());
  });

  test('SecretAdmin is constructible through io.dart alone', () {
    // Ревью итерации 4: `openSecretStore` возвращает `DescribedSecretStore` и
    // требует `Logger`; без их реэкспорта клиент (ему запрещён
    // `package:codelab_agent_*`) не может ни собрать, ни типизировать админку.
    final DescribedSecretStore store = openSecretStore(
      choice: 'auto',
      environment: const {},
      home: '/nonexistent-codelab-home',
      logger: const _QuietLogger(),
    );
    final admin = SecretAdmin(store: store, environment: const {});
    expect(admin, isA<SecretAdmin>());
    expect(SecretStoreUnavailableException, isNotNull);
  });
}

final class _QuietLogger implements Logger {
  const _QuietLogger();

  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}
