/// Проблема значения `secrets.backend` для платформы (design.md change
/// `add-agent-secret-store`, D7, D14; agent-secrets «Выбор бэкенда
/// secrets.backend»).
///
/// Почему тип: одну и ту же проблему показывают разные места — `ConfigLoader`
/// (строкой конфигурации с ключом `secrets.backend`), `openSecretStore` и
/// подкоманды `secret` (исключение `SecretStoreUnavailableException`);
/// тексты не должны разойтись. [message] — английский текст без ключа и без
/// эха самого значения (в нём мог оказаться секрет).
final class SecretsBackendProblem {
  const SecretsBackendProblem(this.message);

  /// Английский текст проблемы: уходит в `ConfigIssue`, в исключение
  /// `SecretStoreUnavailableException.reason` и в stderr подкоманд как есть.
  /// Не содержит ни ключа конфига, ни введённого значения (в нём мог быть
  /// секрет), поэтому префикс `secrets.backend:` добавляет вызывающий.
  final String message;

  @override
  String toString() => message;
}

/// Единая проверка `secrets.backend` для [platform] (`Platform.operatingSystem`);
/// `null` — значение допустимо.
///
/// Для чего: `keychain` (хранилища ОС после 1.0), незнакомое значение и
/// `file` на Windows (ACL NTFS `dart:io` не проверяет). Ядро платформу не
/// знает (PKG-1), поэтому проверка живёт здесь. `null` и `auto`/`env` —
/// допустимы везде; `file` — везде, кроме Windows.
SecretsBackendProblem? secretsBackendProblem(String? choice, String platform) {
  switch (choice) {
    case null || 'auto' || 'env':
      return null;
    case 'file':
      return platform == 'windows'
          ? const SecretsBackendProblem(
              'file backend is not supported on Windows; use env with '
              'CODELAB_SECRET_* variables',
            )
          : null;
    case 'keychain':
      return const SecretsBackendProblem(
        'keychain is not supported yet (supported: auto, env, file)',
      );
    default:
      // Значение в текст не попадает: в нём мог оказаться секрет.
      return const SecretsBackendProblem(
        'expected one of: auto, keychain, env, file',
      );
  }
}
