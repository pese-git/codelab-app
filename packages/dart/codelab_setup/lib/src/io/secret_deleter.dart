/// Адаптер удаления секрета для основного бареля (design.md change
/// `add-provider-setup-ui`, D10; SETUP-24).
library;

import 'package:codelab_agent_io/codelab_agent_io.dart'
    show
        ClientSecretAccess,
        SecretDeleted,
        SecretFailed,
        SecretInvalidName,
        SecretNotSet,
        SecretReadOnly;

import '../provider/provider_remover.dart';

/// Превращает `ClientSecretAccess.admin.delete` в [SecretDeleter].
///
/// Почему: типы `SecretAdmin` живут в `codelab_agent_io`, а `ProviderRemover`
/// основного бареля (web-безопасного) их не видит. Результат несёт только вид
/// исхода: имя секрета уже известно вызывающему, значения нет.
///
/// Как использовать: composition root — `ProviderRemover(config: store,
/// deleteSecret: secretDeleterOf(access))`. Доступ нужно переоткрывать вместе
/// со страницей (D3), поэтому адаптер строится заново при каждом открытии.
SecretDeleter secretDeleterOf(ClientSecretAccess access) => (name) async {
  return switch (await access.admin.delete(name)) {
    SecretDeleted() => SecretDeletion.deleted,
    SecretNotSet() => SecretDeletion.notSet,
    SecretReadOnly() ||
    SecretFailed() ||
    SecretInvalidName() => SecretDeletion.failed,
  };
};
