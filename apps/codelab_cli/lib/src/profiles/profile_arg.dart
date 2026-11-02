import 'package:codelab_client_core/codelab_client_core.dart';

import '../cli_args.dart';

/// Переменная окружения с токеном WebSocket-агента (`09-11`, значение
/// `--agent`).
const agentTokenVariable = 'CODELAB_AGENT_TOKEN';

/// Ссылка на токен в `WebSocketProfile.tokenRef`: значение читает
/// [EnvSecretSource], в профиль и `profiles.json` оно не попадает.
const agentTokenRef = 'env:$agentTokenVariable';

/// Id профиля, который используется без `--agent`.
const defaultProfileId = 'default';

/// Слово `--agent`, которое выбирает встроенный агент.
const embeddedAgentWord = 'embedded';

/// Профиль хоста встроенного агента CLI (design.md change
/// `add-embedded-agent-mode`, D2).
const embeddedHostProfile = 'embedded-cli';

/// Встроенный агент CLI: выбирается словом `embedded` или умолчанием без
/// `--agent` и `default` в `profiles.json`; в файл не записывается (D7).
const embeddedCliProfile = ConnectionProfile.embedded(
  id: embeddedAgentWord,
  label: 'Embedded agent',
  hostProfile: embeddedHostProfile,
);

/// Текст отказа сохранить `embedded` профилем (spec codelab-cli «embedded
/// нельзя сохранить профилем»).
const embeddedIsBuiltInMessage =
    'embedded is built in; use --agent $embeddedAgentWord';

/// Превращает значение `--agent` в профиль подключения.
///
/// Почему: у `--agent` четыре формы (`09-11`, таблица «Значение `--agent`»),
/// и REPL, headless и `profiles add` должны понимать их одинаково
/// (design.md change `add-codelab-cli`, D4).
///
/// Как использовать: `await resolveAgentProfile(options.agent, store:
/// store)`. [value] `null` — профиль `default` из `profiles.json`, если он
/// там есть, иначе встроенный агент (D13, п. 1): новая установка получает
/// встроенного агента, а явный выбор `profiles add default …` сохраняется.
/// `embedded` хранилище не читает. Любая ошибка — [UsageError] (код `64`):
/// неверная форма, неизвестный id, битый `profiles.json` (без `--agent` он не
/// превращается тихо во встроенного агента).
Future<ConnectionProfile> resolveAgentProfile(
  String? value, {
  required ProfileStore store,
}) async {
  if (value != null) {
    if (inlineAgentProfile(value, id: 'inline') case final profile?) {
      return profile;
    }
  }
  final id = value ?? defaultProfileId;
  final List<ConnectionProfile> profiles;
  try {
    profiles = await store.load();
  } on FormatException catch (error) {
    throw UsageError('Cannot read agent profiles: ${error.message}');
  }
  for (final profile in profiles) {
    if (profile.id == id) {
      return profile;
    }
  }
  if (value == null) {
    // Так же выбирает агента весь CLI, включая `test-scenario` (решение
    // пользователя 2026-11-02, U1; D13 п. 1).
    return embeddedCliProfile;
  }
  throw UsageError('Unknown agent profile "$id". Run "codelab profiles list".');
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
      throw UsageError('Invalid agent command "$value": ${error.message}.');
    }
    if (words.isEmpty || words.first.isEmpty) {
      throw UsageError('Invalid agent command "$value": no command.');
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

/// [SecretSource] из переменных окружения процесса CLI.
///
/// Почему: токен WebSocket-агента CLI получает только из окружения
/// (`CODELAB_AGENT_TOKEN`), а не из файла; хранилища секретов CLI до этапа 8
/// нет (design.md, D4).
///
/// Как использовать: `EnvSecretSource(Platform.environment)` передаётся в
/// `ioTransportResolver`. Ссылка `env:<VAR>` даёт значение переменной;
/// пустая переменная и другие ссылки — `null`.
final class EnvSecretSource implements SecretSource {
  const EnvSecretSource(this._environment);

  final Map<String, String> _environment;

  @override
  Future<String?> read(String ref) async {
    if (!ref.startsWith('env:')) {
      return null;
    }
    final value = _environment[ref.substring('env:'.length)];
    return value == null || value.isEmpty ? null : value;
  }
}
