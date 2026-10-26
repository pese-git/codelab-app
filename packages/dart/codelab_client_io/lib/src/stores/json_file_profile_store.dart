import 'package:codelab_client_core/codelab_client_core.dart';

import 'json_file.dart';

/// [ProfileStore] в JSON-файле.
///
/// Почему: CLI хранит профили подключения в `~/.codelab/profiles.json`
/// (`09-10`, задача 5.8); секреты в файл не попадают — у `WebSocketProfile`
/// только ссылка `tokenRef` (design D8 change `extract-acp-client-kit`).
///
/// Как использовать: `JsonFileProfileStore('<home>/.codelab/profiles.json')`;
/// формат — `{"version": 1, "profiles": [...]}`. Нет файла — пустой список;
/// битый файл или неизвестный вид профиля — `FormatException`.
final class JsonFileProfileStore implements ProfileStore {
  JsonFileProfileStore(this.path);

  final String path;

  static const _version = 1;

  @override
  Future<List<ConnectionProfile>> load() async {
    final json = await readJsonObject(path);
    if (json == null) {
      return const [];
    }
    if (json['version'] != _version) {
      throw FormatException('Unsupported profiles version in $path.');
    }
    final profiles = json['profiles'];
    if (profiles is! List<Object?>) {
      throw FormatException('Expected a "profiles" list in $path.');
    }
    return [
      for (final profile in profiles) _decode(profile as Map<String, Object?>),
    ];
  }

  @override
  Future<void> save(ConnectionProfile profile) async {
    final profiles = [...await load()];
    final index = profiles.indexWhere((stored) => stored.id == profile.id);
    if (index == -1) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
    await writeJsonObject(path, {
      'version': _version,
      'profiles': [for (final stored in profiles) _encode(stored)],
    });
  }

  Map<String, Object?> _encode(ConnectionProfile profile) => switch (profile) {
    StdioProfile() => {
      'type': 'stdio',
      'id': profile.id,
      'label': profile.label,
      'command': profile.command,
      'args': profile.args,
      'env': profile.env,
      'runInProjectDirectory': profile.runInProjectDirectory,
    },
    WebSocketProfile() => {
      'type': 'webSocket',
      'id': profile.id,
      'label': profile.label,
      'uri': profile.uri.toString(),
      'tokenRef': ?profile.tokenRef,
    },
  };

  ConnectionProfile _decode(Map<String, Object?> json) =>
      switch (json['type']) {
        'stdio' => StdioProfile(
          id: json['id']! as String,
          label: json['label']! as String,
          command: json['command']! as String,
          args: [for (final arg in json['args']! as List<Object?>) '$arg'],
          env: {
            for (final MapEntry(:key, :value)
                in (json['env']! as Map<String, Object?>).entries)
              key: '$value',
          },
          runInProjectDirectory: json['runInProjectDirectory'] == true,
        ),
        'webSocket' => WebSocketProfile(
          id: json['id']! as String,
          label: json['label']! as String,
          uri: Uri.parse(json['uri']! as String),
          tokenRef: json['tokenRef'] as String?,
        ),
        final type => throw FormatException(
          'Unknown profile type "$type" in $path.',
        ),
      };
}
