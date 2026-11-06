/// Адаптер порта `ProviderKeys` поверх `ClientSecretAccess` (design.md change
/// `add-provider-setup-ui`, D3, D7).
library;

import 'dart:io' show Platform;

import 'package:codelab_agent_io/codelab_agent_io.dart'
    show
        ClientSecretAccess,
        SecretCollision,
        SecretDeleted,
        SecretFailed,
        SecretInvalidName,
        SecretInvalidValue,
        SecretListFailed,
        SecretListing,
        SecretNotSet,
        SecretReadOnly,
        SecretStored,
        SecretUpdated,
        SecretDeleteOutcome,
        SecretWriteOutcome,
        secretReadOnlyHint;
import 'package:codelab_agent_core/codelab_agent_core.dart'
    show SecretBackendInfo, SecretStoreUnavailableException;

import '../provider/provider_keys.dart';
import '../provider/provider_remover.dart' show SecretDeletion;
import '../secret/secret_value.dart';

/// Строит [ProviderKeys] для мастера, готовности и страниц настроек.
///
/// Почему адаптер здесь: типы `SecretAdmin` и исходы записи живут в
/// `codelab_agent_io` и основному бареле недоступны. Значение секрета
/// раскрывается только внутри [ProviderKeys.write] (SETUP-1). Имена веток
/// порта не совпадают с `SecretStored`/`SecretUpdated`, чтобы composition root
/// мог импортировать оба барелей.
///
/// Как использовать: `providerKeysOf(await ClientSecretAccess.open(...),
/// home: codelabHome)`; [home] — настоящий `$CODELAB_HOME` для подсказки про
/// бэкенд только для чтения (`secretReadOnlyHint`, D3). Доступ переоткрывается
/// вместе со страницей, адаптер строится заново.
ProviderKeys providerKeysOf(
  ClientSecretAccess access, {
  required String home,
}) => _ClientProviderKeys(access, home);

final class _ClientProviderKeys implements ProviderKeys {
  _ClientProviderKeys(this._access, this._home);

  final ClientSecretAccess _access;
  final String _home;

  @override
  SecretBackendInfo get backend => _access.backend;

  @override
  String? get readOnlyHint {
    if (backend.writable) {
      return null;
    }
    final problem = _access.configProblem;
    final hint = secretReadOnlyHint(
      // Имя секрета на этом шаге ещё неизвестно: общая подсказка называет
      // переменную шаблоном, точную называет отказ записи.
      SecretReadOnly(
        backend: backend.id,
        variable: 'CODELAB_SECRET_<NAME>',
        fileBackendOffered: !Platform.isWindows,
      ),
      _home,
    );
    return problem == null
        ? hint
        : 'Cannot read $_home/config.yaml ($problem). $hint';
  }

  @override
  Future<bool> stored(String name) async {
    final listing = await _access.admin.list();
    return switch (listing) {
      // Переменные `CODELAB_SECRET_*` в `names` не входят (они в `overrides`).
      SecretListing(:final names) => names.contains(name),
      SecretListFailed(:final reason) => throw SecretStoreUnavailableException(
        backend: backend.id,
        reason: reason,
      ),
    };
  }

  @override
  Future<SecretValue?> read(String name) async {
    final value = await _access.read(name);
    return value == null ? null : SecretValue(value);
  }

  @override
  Future<ProviderKeyWrite> write(String name, SecretValue value) async {
    final SecretWriteOutcome outcome = await _access.admin.store(
      name,
      value.reveal(),
    );
    return switch (outcome) {
      SecretStored() => const ProviderKeyCreated(),
      SecretUpdated() => const ProviderKeyReplaced(),
      final SecretReadOnly readOnly => ProviderKeyRefused(
        secretReadOnlyHint(readOnly, _home),
      ),
      SecretFailed(:final reason) => ProviderKeyRefused(reason),
      SecretInvalidName(:final reason) => ProviderKeyRefused(
        'Invalid secret name: $reason',
      ),
      SecretInvalidValue(:final reason) => ProviderKeyRefused(
        'Invalid secret value: $reason',
      ),
      SecretCollision(:final other, :final variable) => ProviderKeyRefused(
        'The name collides with $other ($variable).',
      ),
    };
  }

  @override
  Future<SecretDeletion> delete(String name) async {
    final SecretDeleteOutcome outcome = await _access.admin.delete(name);
    return switch (outcome) {
      SecretDeleted() => SecretDeletion.deleted,
      SecretNotSet() => SecretDeletion.notSet,
      SecretReadOnly() ||
      SecretFailed() ||
      SecretInvalidName() => SecretDeletion.failed,
    };
  }
}
