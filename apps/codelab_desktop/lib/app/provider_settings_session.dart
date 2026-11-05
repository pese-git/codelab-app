// IO-барель моста настроек разрешён сторожем только в `lib/app/`
// (design.md change `add-provider-setup-ui`, D20).
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart' as setup;

import '../features/settings/application/provider_settings_session.dart';

/// Открывает [ProviderSettingsSession] для доступа [access] (design.md
/// change `add-provider-setup-ui`, D4, D5, D6).
///
/// Почему в `lib/app/`: `ClientSecretAccess`, `FileAgentConfigStore` и
/// `ioProviderCheck` — это файлы и сеть, а IO-барель `codelab_setup/io.dart`
/// сторож пускает только в composition root (D20, SETUP-9). Cubit страницы
/// работает с портом и не знает, откуда он.
///
/// Для чего: собирает для одного агента (его `CODELAB_HOME`, `--config` и
/// окружение) хранилище секретов, писатель конфига и проверку `/models`.
/// Открывается заново при каждой загрузке страницы, поэтому правка
/// `secrets.backend` в `config.yaml` применяется без перезапуска (D3).
///
/// Как использовать: composition root передаёт эту функцию (с общей
/// [check] и логгером) в `ProviderSettingsCubit(open:)`. Значение ключа
/// проходит только через [ProviderSettingsSession.checkProvider]: ключ
/// читается и сразу отдаётся [ProviderCheck], в состояние, события и логи он
/// не попадает (SETUP-1).
Future<ProviderSettingsSession> openProviderSettingsSession(
  EditableSettings access,
  Map<String, String> environment, {
  required ProviderCheck check,
  required setup.Logger logger,
}) async {
  final secrets = await setup.ClientSecretAccess.open(
    codelabHome: access.paths.codelabHome,
    environment: environment,
    logger: logger,
  );
  return _IoProviderSettingsSession(
    secrets: secrets,
    config: setup.FileAgentConfigStore(
      paths: access.paths,
      environment: environment,
      secrets: secrets,
      logger: logger,
    ),
    check: check,
    environment: environment,
  );
}

final class _IoProviderSettingsSession implements ProviderSettingsSession {
  _IoProviderSettingsSession({
    required setup.ClientSecretAccess secrets,
    required this.config,
    required ProviderCheck check,
    required Map<String, String> environment,
  }) : _secrets = secrets,
       _check = check,
       _environment = environment,
       _delete = setup.secretDeleterOf(secrets);

  final setup.ClientSecretAccess _secrets;
  final ProviderCheck _check;
  final Map<String, String> _environment;
  final SecretDeleter _delete;

  @override
  final AgentConfigStore config;

  @override
  SecretBackendInfo get backend => _secrets.backend;

  @override
  Future<bool> isSecretSet(String name) => _secrets.isSet(name);

  @override
  Future<SecretDeletion> deleteSecret(String name) => _delete(name);

  @override
  Future<ProviderCheckResult> checkProvider({
    required String kind,
    required Uri baseUrl,
    required KeyStatusView key,
    CancelToken? cancel,
  }) async {
    // Значение читается здесь и сразу уходит проверке: оно не сохраняется в
    // поле и не возвращается наружу (D4, SETUP-1).
    final String? raw = switch (key) {
      KeyInSecretStore(:final name) => await _secrets.read(name),
      KeyFromEnv(:final name, :final isSet) =>
        isSet ? _environment[name] : null,
      _ => null,
    };
    return _check.listModels(
      kind,
      baseUrl,
      raw == null || raw.isEmpty ? null : SecretValue(raw),
      cancel: cancel,
    );
  }
}
