import 'package:codelab_client_core/codelab_client_core.dart';

/// [ProfileStore] в памяти для widget-тестов: реальный файл внутри
/// `testWidgets` зависал бы в fake-async зоне (design.md change
/// `add-app-settings-shell`, D7; задача 2.6 проверяет настоящий файл в
/// обычном `test`).
///
/// Как использовать: `InMemoryProfileStore([profile, …])`; [failLoad] делает
/// файл «битым» — `load` бросает `FormatException`, как `JsonFileProfileStore`
/// для неизвестной версии. Правила хранилища kit (отказ для `embedded` и
/// зарезервированных id) повторены, чтобы тест видел те же `ArgumentError`.
final class InMemoryProfileStore implements ProfileStore {
  InMemoryProfileStore([Iterable<ConnectionProfile> profiles = const []])
    : profiles = [...profiles];

  final List<ConnectionProfile> profiles;
  bool failLoad = false;

  @override
  Future<List<ConnectionProfile>> load() async {
    if (failLoad) {
      throw const FormatException('Unsupported profiles version.');
    }
    return List.unmodifiable(profiles);
  }

  @override
  Future<void> save(ConnectionProfile profile) async {
    if (profile is EmbeddedProfile || isReservedProfileId(profile.id)) {
      throw ArgumentError.value(profile.id, 'profile');
    }
    final index = profiles.indexWhere((stored) => stored.id == profile.id);
    if (index == -1) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
  }

  @override
  Future<bool> remove(String id) async {
    final before = profiles.length;
    profiles.removeWhere((profile) => profile.id == id);
    return profiles.length != before;
  }
}
