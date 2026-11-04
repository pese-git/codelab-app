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
/// битый файл или неизвестный вид профиля — `FormatException`. [save]
/// отклоняет `EmbeddedProfile` и зарезервированный id (`reservedProfileIds`)
/// `ArgumentError`, файл при этом не меняется; [load] возвращает прежнюю
/// запись `default` как есть, а [remove] её удаляет (D21).
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
      for (final profile in profiles)
        if (profile is Map<String, Object?>)
          _decodeChecked(profile)
        else
          throw FormatException('Expected a profile object in $path.'),
    ];
  }

  @override
  Future<void> save(ConnectionProfile profile) async {
    // Встроенный агент выбирается словом `embedded`, а не записью (D7).
    // Проверка до чтения файла: файл при отказе не меняется.
    if (profile is EmbeddedProfile) {
      throw ArgumentError.value(
        profile.id,
        'profile',
        'an embedded profile is built in and is not saved',
      );
    }
    // `embedded` и `default` — имена встроенного агента (design.md change
    // `add-app-settings-shell`, D21). Проверка тоже до чтения файла. Старая
    // запись `default` в файле остаётся и удаляется только `remove`.
    if (isReservedProfileId(profile.id)) {
      throw ArgumentError.value(
        profile.id,
        'profile',
        'the id is reserved for the built-in agent',
      );
    }
    final profiles = [...await load()];
    final index = profiles.indexWhere((stored) => stored.id == profile.id);
    if (index == -1) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
    await _write(profiles);
  }

  @override
  Future<bool> remove(String id) async {
    final profiles = await load();
    final kept = [
      for (final profile in profiles)
        if (profile.id != id) profile,
    ];
    if (kept.length == profiles.length) {
      return false;
    }
    await _write(kept);
    return true;
  }

  Future<void> _write(List<ConnectionProfile> profiles) =>
      writeJsonObject(path, {
        'version': _version,
        'profiles': [for (final stored in profiles) _encode(stored)],
      });

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
    // `save` отклоняет такой профиль раньше (D7): сюда он не доходит.
    EmbeddedProfile() => throw ArgumentError.value(
      profile.id,
      'profile',
      'an embedded profile is not stored',
    ),
  };

  /// Структурно битая запись (нет `id`, `args` не список, …) — тот же
  /// `FormatException`, что у неизвестного типа, а не `TypeError`: хост
  /// превращает его в понятную ошибку (CLI — код `64`).
  ConnectionProfile _decodeChecked(Map<String, Object?> json) {
    try {
      return _decode(json);
    } on TypeError {
      throw FormatException('Invalid profile record in $path.');
    }
  }

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
