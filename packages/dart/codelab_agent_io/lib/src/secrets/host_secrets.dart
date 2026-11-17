import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'open_secret_store.dart';
import 'secret_process_runner.dart';

/// Строит резолвер секретов настольного хоста (design.md change
/// `add-agent-secret-store`, D15; agent-secrets «Секреты настольных хостов и
/// встроенных профилей»).
///
/// Почему одна фабрика: `codelab-agent`, встроенный агент desktop-приложения и
/// CLI обязаны использовать одни и те же бэкенды, иначе ключ, сохранённый
/// `codelab secret set`, был бы невиден встроенному агенту. Своего хранилища у
/// `codelab_embedded` нет.
///
/// Для чего: собрать [SecretResolver] из сериализуемых данных — [codelabHome]
/// (`codelabHomeOf(environment)`), [environment] процесса, [backend]
/// (`HostSettings.secretsBackend`, `null` — `auto`) и признака [debug]
/// (`--debug-secrets`, `CODELAB_DEBUG_SECRETS=1` или опция хоста).
///
/// Как использовать: функция синхронна и не держит глобального состояния,
/// поэтому хост с ядром в отдельном isolate (`IsolateAcpLink`) вызывает её
/// внутри isolate из полей `codelabHome`, `secretsBackend`, `debugSecrets`.
/// Резолвер, его кэш, [runner] и значения секретов через границу isolate не
/// передаются. [platform] и [runner] — швы для тестов. [selectionReason] — текст
/// `reason` события `secrets.backend.selected`, когда бэкенд выбран не
/// настройкой (`forced by --llm-script`, D11). [testStorePath] — путь к
/// `secrets.yaml` тестового хранилища: бэкенд становится `file` по этому пути
/// независимо от [backend] (change `add-embedded-agent-mode`, D5). Параметр
/// передаёт только открыватель встроенного агента в сборке с
/// `-DCODELAB_ALLOW_TEST_SECRETS=true`; обычный хост его не задаёт.
SecretResolver openHostSecrets({
  required String codelabHome,
  required Map<String, String> environment,
  required String? backend,
  required bool debug,
  required Logger logger,
  String? platform,
  SecretProcessRunner? runner,
  String? selectionReason,
  String? testStorePath,
}) => SecretResolver(
  store: openSecretStore(
    choice: backend,
    environment: environment,
    home: codelabHome,
    logger: logger,
    runner: runner,
    platform: platform,
    selectionReason: selectionReason,
    testStorePath: testStorePath,
  ),
  environment: environment,
  logger: logger,
  debug: debug,
);
