import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'env_secret_store.dart';
import 'file_secret_store.dart';
import 'secret_process_runner.dart';
import 'secrets_backend_problem.dart';

/// Причина, по которой `auto` дал `env` (`SecretBackendInfo.unavailableReason`
/// и поле `reason` события `secrets.backend.selected`).
///
/// Почему текст такой: пользователь, которому секрет действительно нужен,
/// получит подсказку в ошибке хода и в `config check` (D7, D8, D9); при старте
/// предупреждения нет. На Windows `secrets.backend: file` недоступен (D14), и
/// подсказывать его нельзя: остаётся только переменная окружения.
///
/// Не экспортируется: это деталь `openSecretStore`.
String _autoBackendReason(String platform) => platform == 'windows'
    ? 'OS keychain backends are not available in this version; set '
          'CODELAB_SECRET_* variables'
    : 'OS keychain backends are not available in this version; set '
          'secrets.backend: file or CODELAB_SECRET_* variables';

/// Выбирает хранилище секретов по `secrets.backend` (design.md change
/// `add-agent-secret-store`, D7; agent-secrets «Выбор бэкенда
/// secrets.backend»).
///
/// Почему одна функция: при появлении хранилищ ОС после 1.0 меняется только
/// она (D13); вызывающие (`openHostSecrets`, `SecretCommands`, `config check`)
/// получают [DescribedSecretStore] и не знают бэкендов.
///
/// Для чего и как использовать: [choice] — `HostSettings.secretsBackend`
/// (`null` и `auto` — `env` на всех ОС, без проб и процессов; `auto` НЕ
/// выбирает `file` никогда, ни сразу, ни запасным вариантом, CFG-11),
/// [environment] — окружение процесса, [home] — `$CODELAB_HOME`, [platform]
/// подменяет `Platform.operatingSystem` в тестах, [selectionReason] заменяет
/// `reason` в событии, когда бэкенд задан не настройкой (`--llm-script`). Выбор логируется один раз:
/// `secrets.backend.selected {backend, path, reason}`; для `file` ещё
/// предупреждение `secrets.backend.plaintext {path}`. Недопустимый [choice]
/// (`keychain`, незнакомое значение, `file` на Windows — [secretsBackendProblem])
/// даёт `SecretStoreUnavailableException` с тем же текстом, что и
/// `ConfigLoader`, а не `UnsupportedError`: сюда значение приходит и из
/// подкоманд `secret`, и из встроенного хоста. `FileSecretStore` на Windows
/// отказывает и сам (защита в глубину).
DescribedSecretStore openSecretStore({
  required String? choice,
  required Map<String, String> environment,
  required String home,
  required Logger logger,
  SecretProcessRunner? runner,
  String? platform,
  String? selectionReason,
}) {
  if (secretsBackendProblem(choice, platform ?? Platform.operatingSystem)
      case final problem?) {
    throw SecretStoreUnavailableException(
      backend: choice == 'file' ? 'file' : 'config',
      reason: problem.message,
    );
  }
  final autoReason = _autoBackendReason(platform ?? Platform.operatingSystem);
  final DescribedSecretStore store;
  final String? path;
  final String reason;
  switch (choice) {
    case null || 'auto':
      store = EnvSecretStore(
        environment: environment,
        unavailableReason: autoReason,
      );
      path = null;
      reason = autoReason;
    case 'env':
      store = EnvSecretStore(environment: environment);
      path = null;
      reason = 'configured: secrets.backend: env';
    case 'file':
      path = '$home/secrets.yaml';
      store = FileSecretStore(
        path: path,
        runner: runner,
        logger: logger,
        platform: platform ?? Platform.operatingSystem,
      );
      reason = 'configured: secrets.backend: file';
    default:
      // Недостижимо: [secretsBackendProblem] выше отсёк всё остальное.
      throw StateError('unreachable secrets.backend');
  }
  logger.log(
    LogLevel.info,
    'secrets.backend.selected',
    fields: {
      'backend': store.backend.id,
      'path': path,
      'reason': selectionReason ?? reason,
    },
  );
  if (path != null) {
    logger.log(
      LogLevel.warning,
      'secrets.backend.plaintext',
      fields: {'path': path},
    );
  }
  return store;
}
