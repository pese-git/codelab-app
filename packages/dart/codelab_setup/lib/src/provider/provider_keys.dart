/// Порт ключей провайдера для мастера и готовности (design.md change
/// `add-provider-setup-ui`, D7, D9).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show SecretBackendInfo;

import '../secret/secret_value.dart';
import 'provider_remover.dart' show SecretDeletion;

/// Всё, что мастеру нужно от хранилища секретов.
///
/// Почему порт основного бареля: `ClientSecretAccess` и `SecretAdmin` живут в
/// `codelab_agent_io` и основному бареле (web-безопасному) недоступны. Адаптер
/// `providerKeysOf(access, home:)` в `io.dart` строит порт поверх них; тесты
/// мастера работают на фейке.
///
/// Как использовать: composition root создаёт порт при открытии мастера и
/// отдаёт его `ProviderSetupFlow`, `ProviderSetupCommitter` и
/// `checkProviderReadiness`. Значение секрета раскрывается только внутри
/// адаптера (SETUP-1). Отрывок [delete] подходит `ProviderRemover` как
/// `SecretDeleter`.
abstract interface class ProviderKeys {
  /// Бэкенд: `id`, `writable`, `unavailableReason`.
  SecretBackendInfo get backend;

  /// Готовая подсказка про бэкенд только для чтения (D3) или `null`, если
  /// запись возможна.
  String? get readOnlyHint;

  /// Есть ли имя в бэкенде (`names()`); переменные `CODELAB_SECRET_*` не
  /// учитываются: текст мастера «already exists in [backend]» говорит о нём.
  Future<bool> stored(String name);

  /// Значение: переменная `CODELAB_SECRET_*`, затем бэкенд; без кэша.
  Future<SecretValue?> read(String name);

  /// Записывает значение; исход различает «создан» и «заменён» (правило отката
  /// D9).
  Future<ProviderKeyWrite> write(String name, SecretValue value);

  /// Удаляет секрет (откат созданного ключа).
  Future<SecretDeletion> delete(String name);
}

/// Итог [ProviderKeys.write].
sealed class ProviderKeyWrite {
  const ProviderKeyWrite();
}

/// Секрет создан (`SecretStored`): при неудаче записи конфига его удаляют.
final class ProviderKeyCreated extends ProviderKeyWrite {
  const ProviderKeyCreated();

  @override
  String toString() => 'ProviderKeyCreated';
}

/// Существовавший секрет заменён (`SecretUpdated`): прежнего значения клиент не
/// знает, откатить его нельзя.
final class ProviderKeyReplaced extends ProviderKeyWrite {
  const ProviderKeyReplaced();

  @override
  String toString() => 'ProviderKeyReplaced';
}

/// Запись отклонена (только чтение, сбой, неверное имя или значение,
/// коллизия): [reason] — готовый текст без значения.
final class ProviderKeyRefused extends ProviderKeyWrite {
  const ProviderKeyRefused(this.reason);

  final String reason;

  @override
  String toString() => 'ProviderKeyRefused';
}
