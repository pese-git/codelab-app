import 'package:codelab_client_core/codelab_client_core.dart';

import '../cli_args.dart';

/// Переменная окружения с токеном WebSocket-агента (`09-11`, значение
/// `--agent`).
const agentTokenVariable = 'CODELAB_AGENT_TOKEN';

/// Ссылка на токен в `WebSocketProfile.tokenRef`: значение читает
/// `ProfileSecretSource` kit, в профиль и `profiles.json` оно не попадает.
const agentTokenRef = 'env:$agentTokenVariable';

/// Слово `--agent`, которое выбирает встроенный агент.
const embeddedAgentWord = 'embedded';

/// Слово `--agent` — алиас [embeddedAgentWord] (design.md change
/// `add-app-settings-shell`, D21): «профиль по умолчанию» у CLI и app —
/// встроенный агент, а не запись файла.
const defaultAgentWord = 'default';

/// Профиль хоста встроенного агента CLI (design.md change
/// `add-embedded-agent-mode`, D2).
const embeddedHostProfile = 'embedded-cli';

/// Встроенный агент CLI: выбирается словом `embedded`, алиасом `default` или
/// умолчанием без `--agent`; в файл не записывается (D7, D21).
const embeddedCliProfile = ConnectionProfile.embedded(
  id: embeddedAgentWord,
  label: 'Embedded agent',
  hostProfile: embeddedHostProfile,
);

/// Текст отказа сохранить `embedded` профилем (spec codelab-cli «embedded
/// нельзя сохранить профилем»).
const embeddedIsBuiltInMessage =
    'embedded is built in; use --agent $embeddedAgentWord';

/// Текст отказа сохранить `default` профилем (spec codelab-cli «default
/// зарезервирован в profiles add»; D21).
const defaultIsBuiltInMessage =
    'default is the built-in agent; use --agent $embeddedAgentWord';

/// Строка stderr CLI о пустом секрете токена профиля [profileId] (spec
/// codelab-cli «Профили подключения CLI»): префикс `codelab:` и строчная
/// буква, как у остальных сообщений CLI.
String secretMissingMessage(String profileId) =>
    'codelab: profile $profileId has no stored secret value; connecting '
    'without a token.';

/// Предупреждение о прежней записи `default` в `profiles.json`: запись
/// игнорируется. Команды, аргументов, URL и `env` записи в тексте нет
/// (`observability.md`, D21).
const ignoredDefaultProfileWarning =
    'profile "default" in profiles.json is ignored: default is the built-in '
    'agent; remove it with codelab profiles remove default';

/// Превращает значение `--agent` в профиль подключения.
///
/// Почему: у `--agent` пять форм (`09-11`, таблица «Значение `--agent`»), и
/// REPL, headless и `profiles add` должны понимать их одинаково (design.md
/// change `add-codelab-cli`, D4).
///
/// Как использовать: `await resolveAgentProfile(options.agent, store: store,
/// onWarning: stderr.writeln)`. Правило выбора (design.md change
/// `add-app-settings-shell`, D21):
/// * [value] `null`, `embedded` и `default` — встроенный агент, и хранилище
///   не читается: битый `profiles.json` ему не мешает;
/// * `stdio:…`, `ws://…`, `wss://…` — разовый профиль;
/// * иначе — id из `profiles.json`; запись `default` из файла не выбирается
///   никогда ([usableStoredProfiles]).
///
/// Для `default` хранилище читается только ради предупреждения: если в нём
/// осталась прежняя запись `default`, [onWarning] получает
/// [ignoredDefaultProfileWarning]. Любая ошибка чтения тут молчит: без неё
/// встроенный агент выбран верно. Любая другая ошибка — [UsageError] (код
/// `64`): неверная форма, неизвестный id, битый `profiles.json` при `-a <id>`.
Future<ConnectionProfile> resolveAgentProfile(
  String? value, {
  required ProfileStore store,
  void Function(String warning)? onWarning,
}) async {
  if (value == null || value == embeddedAgentWord) {
    return embeddedCliProfile;
  }
  if (value == defaultAgentWord) {
    if (onWarning != null && await _hasIgnoredDefault(store)) {
      onWarning(ignoredDefaultProfileWarning);
    }
    return embeddedCliProfile;
  }
  if (inlineAgentProfile(value, id: 'inline') case final profile?) {
    return profile;
  }
  final List<ConnectionProfile> profiles;
  try {
    profiles = await store.load();
  } on FormatException catch (error) {
    throw UsageError('Cannot read agent profiles: ${error.message}');
  }
  for (final profile in usableStoredProfiles(profiles).usable) {
    if (profile.id == value) {
      return profile;
    }
  }
  // Значение не цитируется: без префикса `stdio:` оно может оказаться
  // командной строкой с токеном (`-a 'my-agent --token sk-…'`), а голый токен
  // проходит и проверку id (design.md change `redact-cli-stdio-profile-args`,
  // D6). Список id — `codelab profiles list`.
  throw const UsageError('Unknown agent profile. Run "codelab profiles list".');
}

/// Взят ли [label] профиля из значения `--agent` (`stdio:…`, `ws://…`,
/// `wss://…`) или пуст.
///
/// Почему: [inlineAgentProfile] кладёт в `label` исходную строку `--agent`, а
/// у stdio-профиля это командная строка с аргументами; печатать её как
/// подпись значит повторить значения (design.md change
/// `redact-cli-stdio-profile-args`, D3). Правило то же, что `profileTitle`
/// codelab-app.
///
/// Как использовать: `/profile` не выводит `label` в скобках, если ответ
/// `true`.
bool isLabelFromAgentValue(String label) {
  final trimmed = label.trim();
  return trimmed.isEmpty ||
      trimmed.startsWith('stdio:') ||
      trimmed.startsWith('ws://') ||
      trimmed.startsWith('wss://');
}

/// Есть ли в хранилище прежняя запись `default`; нечитаемый файл — нет.
///
/// Ловится любая ошибка чтения, не только `FormatException`: `EACCES` или
/// `profiles.json`-каталог (`FileSystemException`) не должны ронять запуск
/// встроенного агента ради необязательного предупреждения (D21).
Future<bool> _hasIgnoredDefault(ProfileStore store) async {
  try {
    return usableStoredProfiles(await store.load()).ignoredDefault;
  } on Object {
    return false;
  }
}

/// Профиль из формы `stdio:…`, URL или слова `embedded`; `null` — [value] похоже
/// на id профиля и ищется в хранилище.
///
/// Как использовать: [id] — id нового профиля (`profiles add`) или
/// `inline` для разового `--agent`. Ошибка формы — [UsageError].
ConnectionProfile? inlineAgentProfile(String value, {required String id}) {
  if (value == embeddedAgentWord) {
    return embeddedCliProfile;
  }
  if (value.startsWith('stdio:')) {
    final List<String> words;
    try {
      words = parseShellWords(value.substring('stdio:'.length));
    } on FormatException catch (error) {
      // Значение `--agent` в тексте не повторяется: в нём может быть токен
      // (design.md change `redact-cli-stdio-profile-args`, D4); `source`
      // ошибки разбора тоже не печатается.
      throw UsageError('Invalid agent command: ${error.message}.');
    }
    if (words.isEmpty || words.first.isEmpty) {
      throw const UsageError('Invalid agent command: no command.');
    }
    return ConnectionProfile.stdio(
      id: id,
      label: value,
      command: words.first,
      args: words.skip(1).toList(growable: false),
      // Агент стартует в рабочей папке сессии (`--cwd`), как в app.
      runInProjectDirectory: true,
    );
  }
  if (value.startsWith('ws://') || value.startsWith('wss://')) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      throw UsageError('Invalid agent URL "$value".');
    }
    return ConnectionProfile.webSocket(
      id: id,
      label: value,
      uri: uri,
      tokenRef: agentTokenRef,
    );
  }
  return null;
}
