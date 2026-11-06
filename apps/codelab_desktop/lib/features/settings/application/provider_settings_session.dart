import 'package:codelab_setup/codelab_setup.dart';

/// Открытый доступ к настройкам одного агента на время одной загрузки
/// страницы «Providers».
///
/// Почему порт: конфиг агента, хранилище секретов и проверка `/models` — это
/// файлы, процессы и сеть; `ClientSecretAccess`, `FileAgentConfigStore` и
/// `ioProviderCheck` лежат в `codelab_setup/io.dart`, который сторож пускает
/// только в `lib/app/` (design.md change `add-provider-setup-ui`, D20,
/// SETUP-9). Cubit работает с этим портом и не знает, откуда он.
///
/// Для чего: всё, что странице нужно от IO, одним объектом — снимок и запись
/// конфига, «задан ли секрет» без чтения значения, удаление секрета и
/// проверка ключа. Значение ключа через порт НЕ проходит: проверку
/// выполняет адаптер, который читает ключ и сразу отдаёт его `ProviderCheck`
/// (D4, SETUP-1).
///
/// Как использовать: фабрика [ProviderSettingsOpener] из composition root
/// открывает сессию заново при каждой загрузке страницы, поэтому правка
/// `secrets.backend` в `config.yaml` применяется без перезапуска (D3).
abstract interface class ProviderSettingsSession {
  /// Снимок и запись конфига агента (`ConfigWriter` под капотом).
  AgentConfigStore get config;

  /// Бэкенд секретов: `id`, `writable`, причина недоступности (D3).
  SecretBackendInfo get backend;

  /// Задан ли секрет [name]; значение не читается (SETUP-1).
  Future<bool> isSecretSet(String name);

  /// Удаляет секрет [name]; вызывается только после `ConfigSaved` (SETUP-24).
  Future<SecretDeletion> deleteSecret(String name);

  /// Строит автомат мастера провайдера (`ProviderSetupFlow`) на этой сессии:
  /// проверка `/models`, порт ключей, запись конфига и `isLocalHost` kit
  /// собирает composition root, а Cubit мастера получает готовый автомат.
  ///
  /// Почему в сессии, а не в Cubit: порт `ProviderKeys` (значения ключей) и
  /// IO-барель моста нельзя пускать в `features/` (SETUP-1, SETUP-9, D7).
  /// [editing] — строка правки («Edit»), [forceDefault] — «Make default»
  /// нельзя снять (баннер D26). [entry] — откуда открыт мастер для события
  /// `provider_wizard.started` (D18). Снимок конфига читается заново на каждый
  /// вызов, чтобы мастер видел свежие слои.
  Future<ProviderSetupFlow> openWizard({
    ProviderEntryView? editing,
    bool forceDefault = false,
    ProviderWizardEntry entry = ProviderWizardEntry.app,
  });

  /// Запрашивает список моделей провайдера. Ключ по ссылке [key] читает сам
  /// адаптер и сразу передаёт проверке; в Cubit значение не попадает.
  ///
  /// [cancel] — отмена владельцем (повторный Check строки, закрытие
  /// страницы): сработавший токен обрывает запрос, итог — `CheckCancelled`.
  Future<ProviderCheckResult> checkProvider({
    required String kind,
    required Uri baseUrl,
    required KeyStatusView key,
    CancelToken? cancel,
  });
}

/// Фабрика сессии настроек для доступа [access] (design.md, D5).
///
/// [environment] — окружение агента: переменные app, дополненные `env`
/// stdio-профиля; по нему считаются `api_key_env` и `CODELAB_SECRET_*`.
typedef ProviderSettingsOpener =
    Future<ProviderSettingsSession> Function(
      EditableSettings access,
      Map<String, String> environment,
    );
