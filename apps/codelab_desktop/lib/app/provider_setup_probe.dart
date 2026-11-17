// IO-барель моста настроек разрешён сторожем только в `lib/app/`
// (design.md change `add-provider-setup-ui`, D20).
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart' as setup;

/// Нужен ли встроенному агенту провайдер: признак моста по снимку конфига
/// (design.md change `add-provider-setup-ui`, D26).
///
/// Почему в `lib/app/`: снимок читает `FileAgentConfigStore` (файлы и
/// хранилище секретов), а IO-барель моста сторож пускает только в composition
/// root (D20, SETUP-9). Сам признак — чистая функция моста
/// `providerSetupNeeded`, поэтому app и CLI не расходятся.
///
/// Для чего: `EmbeddedTransportResolver` зовёт её при
/// `EmbeddedAgentConfigException`, чтобы баннер соединения показал «Add
/// provider» вместо сырого текста проблем. [codelabHome], [cwd] и
/// [environment] — те же `CODELAB_HOME`, папка проекта и окружение, с которыми
/// открывался агент, иначе снимок описывал бы другой конфиг.
///
/// Как использовать: composition root оборачивает её в
/// `Future<bool> Function(String cwd)`. Сбой чтения снимка пробрасывается
/// вызывающему: резолвер превращает его в «не нужен» и показывает прежний
/// текст (D26).
Future<bool> providerSetupNeededAt(
  String cwd, {
  required String codelabHome,
  required Map<String, String> environment,
  required setup.Logger logger,
}) async {
  final secrets = await setup.ClientSecretAccess.open(
    codelabHome: codelabHome,
    environment: environment,
    logger: logger,
  );
  // Те же пути, что у мастера из баннера (`openEmbeddedWizard`): правило
  // «чьи настройки» одно, в `resolveSettingsAccess` моста.
  final access = resolveSettingsAccess(
    kind: AgentLaunchKind.embedded,
    cwd: cwd.isEmpty ? null : cwd,
    defaultCodelabHome: codelabHome,
  );
  if (access is! EditableSettings) {
    return false;
  }
  final store = setup.FileAgentConfigStore(
    paths: access.paths,
    environment: environment,
    secrets: secrets,
    logger: logger,
  );
  final snapshot = await store.snapshot(cwd: cwd);
  return providerSetupNeeded(snapshot);
}
