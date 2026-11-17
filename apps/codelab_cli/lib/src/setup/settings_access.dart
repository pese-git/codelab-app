import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_setup/codelab_setup.dart';

import 'setup_commands.dart';

/// Строка для удалённого агента (§12.4.8, шаг 3).
const remoteReadOnlyLine =
    'Provider settings are read-only for a remote agent. Run "codelab '
    'provider add" on the agent host.';

/// Чьи настройки у профиля подключения (SETUP-2, design.md D5, D17).
///
/// Почему здесь, а не в команде: `/provider` и `/settings` (и в 4b оверлеи
/// TUI) спрашивают одно и то же, а ответ даёт общая `resolveSettingsAccess`
/// моста: `EmbeddedProfile` — встроенный агент, `StdioProfile` — по команде,
/// `WebSocketProfile` — только чтение.
SettingsAccess settingsAccessOf(
  ConnectionProfile profile, {
  required String cwd,
  required String codelabHome,
}) => profile.map(
  stdio: (p) => resolveSettingsAccess(
    kind: AgentLaunchKind.stdio,
    command: p.command,
    args: p.args,
    env: p.env,
    // Без `runInProjectDirectory` агент не работает в папке проекта: слой
    // `projectLocal` недоступен (D5).
    cwd: p.runInProjectDirectory ? cwd : null,
    defaultCodelabHome: codelabHome,
  ),
  webSocket: (p) => resolveSettingsAccess(
    kind: AgentLaunchKind.webSocket,
    endpoint: p.uri,
    cwd: cwd,
    defaultCodelabHome: codelabHome,
  ),
  embedded: (_) => resolveSettingsAccess(
    kind: AgentLaunchKind.embedded,
    cwd: cwd,
    defaultCodelabHome: codelabHome,
  ),
);

/// Строка отказа для [access], если настройки нельзя менять отсюда; для
/// `EditableSettings` — `null`.
String? readOnlyLineOf(SettingsAccess access) => switch (access) {
  EditableSettings() => null,
  RemoteReadOnly() => remoteReadOnlyLine,
  NotManaged(:final agentName) =>
    'Provider settings are managed by $agentName.',
};

/// Строка для `--local`, когда у агента нет проектного слоя.
const noProjectLocalLine =
    'This agent has no project-local config; run without --local.';

/// Цель `projectLocal` из доступа или `null`, если её нет.
ConfigTarget? projectLocalTargetOf(EditableSettings access) {
  for (final target in access.targets) {
    if (target.layer == ConfigLayer.projectLocal) {
      return target;
    }
  }
  return null;
}

/// Область порта для [access] профиля [profile]: окружение stdio-профиля
/// (как при запуске агента) и папка снимка `access.cwd ?? cwd`.
SetupScope settingsScopeOf(
  ConnectionProfile profile,
  EditableSettings access, {
  required String cwd,
}) => SetupScope(
  access: access,
  cwd: access.cwd ?? cwd,
  env: profile.map(
    stdio: (p) => p.env,
    webSocket: (_) => const {},
    embedded: (_) => const {},
  ),
);
