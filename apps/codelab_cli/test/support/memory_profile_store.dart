import 'package:codelab_client_core/codelab_client_core.dart';

/// [ProfileStore] в памяти для модульных тестов профилей CLI.
///
/// Как использовать: `MemoryProfileStore([profile])`; [broken] — хранилище,
/// которое читает битый файл (`FormatException`).
final class MemoryProfileStore implements ProfileStore {
  MemoryProfileStore([List<ConnectionProfile> profiles = const []])
    : _profiles = [...profiles],
      _broken = false;

  MemoryProfileStore.broken() : _profiles = [], _broken = true;

  final List<ConnectionProfile> _profiles;
  final bool _broken;

  @override
  Future<List<ConnectionProfile>> load() async {
    if (_broken) {
      throw const FormatException('Expected a JSON object in profiles.json.');
    }
    return List.unmodifiable(_profiles);
  }

  @override
  Future<void> save(ConnectionProfile profile) async {
    final index = _profiles.indexWhere((stored) => stored.id == profile.id);
    if (index == -1) {
      _profiles.add(profile);
    } else {
      _profiles[index] = profile;
    }
  }

  @override
  Future<bool> remove(String id) async {
    final before = _profiles.length;
    _profiles.removeWhere((profile) => profile.id == id);
    return _profiles.length != before;
  }
}
