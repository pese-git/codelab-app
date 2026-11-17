// Тестовые двойники хранилищ профилей и секретов (change
// `add-provider-setup-ui`, D13). Журнал вызовов `calls` общий для обоих
// двойников, чтобы тесты проверяли порядок «секрет → профиль» без таймеров.

import 'package:codelab_client_core/codelab_client_core.dart';

/// Общий журнал вызовов: записи вида `secret.store:<имя>`, `profile.save:<id>`.
final class CallLog {
  final entries = <String>[];
}

/// [ProfileSecrets] в памяти. Результаты записи и удаления можно подменить.
class FakeProfileSecrets implements ProfileSecrets {
  FakeProfileSecrets({
    CallLog? log,
    Map<String, String>? values,
    this.backend = const ProfileSecretBackend(id: 'file', writable: true),
  }) : log = log ?? CallLog(),
       values = {...?values};

  final CallLog log;
  final Map<String, String> values;

  @override
  ProfileSecretBackend backend;

  /// Подменяет исход `store`; `null` — обычное поведение.
  ProfileSecretWrite? nextWrite;

  /// Подменяет исход `delete`; `null` — обычное поведение.
  ProfileSecretDelete? nextDelete;

  @override
  Future<List<String>> names() async => values.keys.toList()..sort();

  /// Сколько раз вызваны `isSet` и `read`: проверка «значение не читается».
  var isSetCalls = 0;
  var readCalls = 0;

  @override
  Future<bool> isSet(String name) async {
    isSetCalls++;
    return values.containsKey(name);
  }

  @override
  Future<String?> read(String name) async {
    readCalls++;
    return values[name];
  }

  @override
  Future<ProfileSecretWrite> store(String name, SecretText value) async {
    log.entries.add('secret.store:$name');
    if (nextWrite case final forced?) {
      return forced;
    }
    if (values.containsKey(name)) {
      return const Exists();
    }
    values[name] = value.reveal();
    return const Stored();
  }

  @override
  Future<ProfileSecretDelete> delete(String name) async {
    log.entries.add('secret.delete:$name');
    if (nextDelete case final forced?) {
      return forced;
    }
    return values.remove(name) == null ? const NotSet() : const Deleted();
  }
}

/// [ProfileStore] в памяти; `failSave` / `failRemove` имитируют отказ записи.
final class FakeProfileStore implements ProfileStore {
  FakeProfileStore({CallLog? log, List<ConnectionProfile>? profiles})
    : log = log ?? CallLog(),
      profiles = [...?profiles];

  final CallLog log;
  final List<ConnectionProfile> profiles;
  Object? failSave;
  Object? failRemove;

  /// Профили, которые появятся в файле при ближайшем `load` (гонка с
  /// другим процессом: id занят между проверкой формы и записью).
  List<ConnectionProfile>? appearOnNextLoad;

  /// Профили, которые появятся при втором `load`: гонка между перечитыванием
  /// id в начале записи и непосредственно перед записью профиля.
  List<ConnectionProfile>? appearOnSecondLoad;
  var _loads = 0;

  @override
  Future<List<ConnectionProfile>> load() async {
    log.entries.add('profile.load');
    _loads++;
    if (_loads == 2 && appearOnSecondLoad != null) {
      profiles.addAll(appearOnSecondLoad!);
      appearOnSecondLoad = null;
    }
    if (appearOnNextLoad case final late?) {
      profiles.addAll(late);
      appearOnNextLoad = null;
    }
    return List.unmodifiable(profiles);
  }

  @override
  Future<void> save(ConnectionProfile profile) async {
    log.entries.add('profile.save:${profile.id}');
    if (failSave case final error?) {
      throw error;
    }
    profiles
      ..removeWhere((p) => p.id == profile.id)
      ..add(profile);
  }

  @override
  Future<bool> remove(String id) async {
    log.entries.add('profile.remove:$id');
    if (failRemove case final error?) {
      throw error;
    }
    final before = profiles.length;
    profiles.removeWhere((p) => p.id == id);
    return profiles.length < before;
  }
}
