import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile, StdioProfile;

/// Профиль, с которым запускается «Test connection».
///
/// Почему: stdio-профиль с `runInProjectDirectory` стартует процесс в папке
/// проекта, а без проекта папки нет, и `chdir` в пустую строку дал бы ложный
/// `Unreachable` (require-project-folder/design.md, D7).
///
/// Для чего: проверка шлёт только `initialize`, `session/new` не отправляет,
/// поэтому папка ей не нужна — без проекта процесс стартует без явной
/// рабочей папки, как при выключенном `runInProjectDirectory`. Ядро kit для
/// этого не меняется.
///
/// Как использовать: `AddProfileCubit` и `ConnectionSettingsCubit` передают в
/// `ProfileProbe.probe` результат; [projectDirectory] — выбранный проект или
/// `null`. WebSocket-профиль возвращается как есть. Сам сохраняемый профиль
/// не меняется.
ConnectionProfile probeProfileFor(
  ConnectionProfile profile, {
  required String? projectDirectory,
}) {
  if (projectDirectory == null &&
      profile is StdioProfile &&
      profile.runInProjectDirectory) {
    return profile.copyWith(runInProjectDirectory: false);
  }
  return profile;
}
