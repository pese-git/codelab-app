import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile, ProfileStore;

/// Хранилище профилей недоступно: `CODELAB_HOME` недопустим, и пути к
/// `profiles.json` нет (design.md change `add-app-settings-shell`, D7).
///
/// Почему отдельный тип: страница «Connection» показывает [message] как
/// причину и не путает её с битым файлом; в журнал идёт только имя типа.
final class ProfilesUnavailableException implements Exception {
  const ProfilesUnavailableException(this.message);

  /// Причина без путей и секретов (правило `resolveCodelabHome`).
  final String message;
}

/// [ProfileStore] без файла: любая операция — [ProfilesUnavailableException].
///
/// Почему: недопустимый `CODELAB_HOME` не должен ни ронять app, ни молча
/// писать профили в другое место, ни создавать каталоги. Composition root
/// подставляет это хранилище вместо `JsonFileProfileStore`; страница
/// получает `ConnectionSettingsUnreadable`, а остальные настройки работают.
final class UnavailableProfileStore implements ProfileStore {
  const UnavailableProfileStore(this.reason);

  final String reason;

  @override
  Future<List<ConnectionProfile>> load() =>
      Future.error(ProfilesUnavailableException(reason));

  @override
  Future<void> save(ConnectionProfile profile) =>
      Future.error(ProfilesUnavailableException(reason));

  @override
  Future<bool> remove(String id) =>
      Future.error(ProfilesUnavailableException(reason));
}
