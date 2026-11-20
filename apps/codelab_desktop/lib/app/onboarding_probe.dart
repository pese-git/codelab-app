// IO-барель моста настроек разрешён сторожем только в `lib/app/`
// (design.md change `add-app-onboarding`, D15; `add-provider-setup-ui`, D20).
import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile, EmbeddedProfile, StdioProfile, WebSocketProfile;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart' as setup;

import '../core/platform/home_path_label.dart';
import '../features/onboarding/application/onboarding_probe.dart';

/// Адаптер порта `OnboardingProbe` поверх моста `codelab_setup` (design.md
/// change `add-app-onboarding`, D6).
///
/// Почему в `lib/app/`: снимок читает `FileAgentConfigStore`, а IO-барель
/// моста сторож пускает только в composition root (SETUP-9). Правила
/// готовности и режима — функции моста (`checkProviderReadiness`,
/// `sessionDefaultsOf`), второй копии нет (SETUP-8).
///
/// Для чего: собирает [OnboardingFacts] за одно открытие хранилища. Значения
/// ключей не читаются (SETUP-1). Профиль по умолчанию не настраиваемый
/// (внешний агент) даёт `OnboardingFacts.external` без чтения конфига.
///
/// Как использовать: composition root передаёт `DefaultProfileResolver.resolve`
/// в [resolveProfile], каталог логов app в [logDirectory] и окружение app.
/// [keysOf] — шов тестов над `providerKeysOf`.
final class SetupOnboardingProbe implements OnboardingProbe {
  SetupOnboardingProbe({
    required Future<ConnectionProfile> Function() resolveProfile,
    required String codelabHome,
    required String logDirectory,
    required Map<String, String> environment,
    required setup.Logger logger,
    ProviderKeys Function(
          setup.ClientSecretAccess access, {
          required String home,
        })
        keysOf =
        setup.providerKeysOf,
  }) : _resolveProfile = resolveProfile,
       _codelabHome = codelabHome,
       _logDirectory = logDirectory,
       _environment = environment,
       _logger = logger,
       _keysOf = keysOf;

  final Future<ConnectionProfile> Function() _resolveProfile;
  final String _codelabHome;
  final String _logDirectory;
  final Map<String, String> _environment;
  final setup.Logger _logger;
  final ProviderKeys Function(
    setup.ClientSecretAccess access, {
    required String home,
  })
  _keysOf;

  @override
  Future<OnboardingFacts> read() async {
    final logsLabel = homePathLabel(_logDirectory, _environment);
    final profile = await _resolveProfile();
    // Без папки проекта (`cwd: null`): при первом запуске проекта нет, а
    // проектные слои применяются только к доверенному проекту (D6, п. 1).
    final access = switch (profile) {
      EmbeddedProfile() => resolveSettingsAccess(
        kind: AgentLaunchKind.embedded,
        defaultCodelabHome: _codelabHome,
      ),
      StdioProfile(:final command, :final args, :final env) =>
        resolveSettingsAccess(
          kind: AgentLaunchKind.stdio,
          command: command,
          args: args,
          env: env,
          defaultCodelabHome: _codelabHome,
        ),
      WebSocketProfile(:final uri) => resolveSettingsAccess(
        kind: AgentLaunchKind.webSocket,
        endpoint: uri,
        defaultCodelabHome: _codelabHome,
      ),
    };
    if (access is! EditableSettings) {
      return OnboardingFacts.external(logsLabel: logsLabel);
    }
    final home = access.paths.codelabHome;
    final secrets = await setup.ClientSecretAccess.open(
      codelabHome: home,
      environment: _environment,
      logger: _logger,
    );
    final keys = _keysOf(secrets, home: home);
    final store = setup.FileAgentConfigStore(
      paths: access.paths,
      environment: _environment,
      secrets: secrets,
      logger: _logger,
    );
    final snapshot = await store.snapshot(cwd: '');
    return OnboardingFacts(
      readiness: await checkProviderReadiness(snapshot, keys, _environment),
      backendId: keys.backend.id,
      backendWritable: keys.backend.writable,
      mode: sessionDefaultsOf(snapshot, access).mode.id,
      homeLabel: homePathLabel(home, _environment),
      logsLabel: logsLabel,
    );
  }
}
