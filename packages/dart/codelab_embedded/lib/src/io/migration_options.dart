import 'package:codelab_agent_core/codelab_agent_core.dart' show ConfigLayer;
import 'package:codelab_agent_io/codelab_agent_io.dart'
    show SecretMigrationOptions, testSecretStorePath;

/// Опции переноса секретов для codelab-app из того же окружения, что у
/// `localEmbeddedAgentOpener` (change `add-config-literal-secrets-and-migrate`,
/// D8).
///
/// Почему: app не должна дублировать логику открывателя. Мигратор обязан
/// видеть то же хранилище, что и агент: тестовая сборка
/// (`CODELAB_ALLOW_TEST_SECRETS`) переключает его через `testSecretStorePath`.
///
/// Как использовать: `SecretMigrator().run(secretMigrationOptionsFor(cwd:,
/// environment:, dryRun: true))` — план, без `dryRun` — применение. Слои —
/// `--all` (пользователь, проект, локальный проект), `force` не задаётся:
/// перезапись чужого значения безвозвратна (L7). [environment] — то же, что
/// передано открывателю.
SecretMigrationOptions secretMigrationOptionsFor({
  required String cwd,
  required Map<String, String> environment,
  bool dryRun = false,
}) => SecretMigrationOptions(
  cwd: cwd,
  environment: environment,
  layers: const {
    ConfigLayer.user,
    ConfigLayer.project,
    ConfigLayer.projectLocal,
  },
  dryRun: dryRun,
  testStorePath: testSecretStorePath(environment),
);
