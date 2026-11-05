import 'package:codelab_client_core/codelab_client_core.dart';

import '../cli_args.dart';
import '../exit_codes.dart';
import '../session_setup.dart';
import 'profile_arg.dart';

/// Команда `codelab profiles list|show <id>|add <id> <agent>|remove <id>`.
///
/// Почему: внешнего агента CLI запускает только по явному `-a <id>`, а
/// писать `profiles.json` руками — ошибкоопасно (U-06, DoD §9.11). Команда
/// работает без запуска агента.
///
/// Как использовать: вызывает `runCodelab` для подкоманды `profiles`;
/// результат — код выхода. Неверные аргументы — [UsageError] (код `64`
/// у вызывающего); неизвестный профиль у `show` и `remove` — текст в
/// [stderr] и [failureExit].
///
/// Прежняя запись `default` (D21): `list` её не показывает, `show default`
/// печатает встроенный профиль, обе команды пишут в [stderr] одно
/// предупреждение [ignoredDefaultProfileWarning]; удаление `default`
/// работает как у любого профиля. Файл автоматически не меняется.
///
/// [openSecrets] открывает хранилище секретов лениво и только для `show`
/// профиля со ссылкой `secret:<имя>`: остальные подкоманды хранилища не
/// касаются. `show` печатает `token: secret <имя> (set|missing)` по
/// `ProfileSecrets.isSet` — значение не читается (design.md change
/// `add-provider-setup-ui`, D13). Без [openSecrets] или при сбое хранилища
/// секрет считается отсутствующим.
Future<int> runProfilesCommand(
  List<String> args, {
  required ProfileStore store,
  required StringSink stdout,
  required StringSink stderr,
  Future<ProfileSecrets> Function()? openSecrets,
}) async {
  switch (args) {
    case ['list']:
      final (:usable, :ignoredDefault) = usableStoredProfiles(
        await _load(store),
      );
      if (ignoredDefault) {
        stderr.writeln(ignoredDefaultProfileWarning);
      }
      if (usable.isEmpty) {
        stdout.writeln(
          'No agent profiles. Add one with '
          '"codelab profiles add <id> stdio:<command>".',
        );
        return okExit;
      }
      final width = usable
          .map((profile) => profile.id.length)
          .reduce((a, b) => a > b ? a : b);
      for (final profile in usable) {
        stdout.writeln('${profile.id.padRight(width)}  ${_summary(profile)}');
      }
      return okExit;
    case ['show', final id]:
      final (:usable, :ignoredDefault) = usableStoredProfiles(
        await _load(store),
      );
      if (id == defaultAgentWord) {
        // `default` — алиас встроенного агента (D21): запись файла не
        // показывается, о ней предупреждение.
        if (ignoredDefault) {
          stderr.writeln(ignoredDefaultProfileWarning);
        }
        await _show(embeddedCliProfile, stdout, openSecrets);
        return okExit;
      }
      final profile = usable.where((p) => p.id == id).firstOrNull;
      if (profile == null) {
        stderr.writeln('codelab: Unknown agent profile "$id".');
        return failureExit;
      }
      await _show(profile, stdout, openSecrets);
      return okExit;
    case ['add', final id, final value]:
      // `embedded` и `default` встроены и в `profiles.json` не пишутся (D7,
      // D21): ни как id, ни как значение. Резерв проверяется раньше
      // синтаксиса id, чтобы сообщение называло причину.
      if (id == embeddedAgentWord || value == embeddedAgentWord) {
        throw const UsageError(embeddedIsBuiltInMessage);
      }
      if (isReservedProfileId(id) || value == defaultAgentWord) {
        throw const UsageError(defaultIsBuiltInMessage);
      }
      // Правило id нового профиля — общее с app (D11, D15). Прежние профили с
      // другими id читаются и выбираются как раньше: проверка только здесь.
      if (!isValidProfileId(id)) {
        throw UsageError(
          'Invalid profile id "$id": use lowercase letters, digits, ".", '
          '"_" and "-", starting with a letter or digit, up to 64 characters.',
        );
      }
      final profile = inlineAgentProfile(value, id: id);
      if (profile == null) {
        // Значение не повторяется: без префикса оно может быть командной
        // строкой с токеном (design.md change `redact-cli-stdio-profile-args`,
        // D6).
        throw const UsageError(
          'Invalid agent: use "stdio:<command> [args]", ws:// or wss://.',
        );
      }
      await store.save(profile);
      stdout.writeln('Saved profile $id.');
      return okExit;
    case ['remove', final id]:
      if (!await store.remove(id)) {
        stderr.writeln('codelab: Unknown agent profile "$id".');
        return failureExit;
      }
      stdout.writeln('Removed profile $id.');
      return okExit;
    default:
      throw const UsageError(
        'Usage: codelab profiles list|show <id>|add <id> <agent>|remove <id>',
      );
  }
}

Future<List<ConnectionProfile>> _load(ProfileStore store) async {
  try {
    return await store.load();
  } on FormatException catch (error) {
    throw UsageError('Cannot read agent profiles: ${error.message}');
  }
}

String _summary(ConnectionProfile profile) => switch (profile) {
  StdioProfile(:final command, :final args) when args.isEmpty =>
    'stdio: $command',
  // Значения аргументов не печатаются (D1, D2): только команда и их число.
  StdioProfile(:final command, :final args) =>
    'stdio: $command (${argumentCount(args.length)})',
  WebSocketProfile(:final uri) => 'ws: $uri',
  // В `profiles.json` его не бывает (D7); ветка нужна исчерпывающему switch.
  EmbeddedProfile(:final hostProfile) => 'embedded: $hostProfile',
};

/// Значения аргументов stdio-профиля не печатаются — только их число
/// (`args: <N> (values hidden)`): среди них бывает токен, а по строке
/// секретный аргумент не отличить от обычного (design.md change
/// `redact-cli-stdio-profile-args`, D1). Значения видны только в
/// `$CODELAB_HOME/profiles.json`. Значение токена не печатается никогда —
/// только откуда оно берётся.
Future<void> _show(
  ConnectionProfile profile,
  StringSink out,
  Future<ProfileSecrets> Function()? openSecrets,
) async {
  out.writeln('id: ${profile.id}');
  switch (profile) {
    case StdioProfile():
      out
        ..writeln('type: stdio')
        ..writeln('command: ${profile.command}')
        ..writeln(
          profile.args.isEmpty
              ? 'args: 0'
              : 'args: ${profile.args.length} (values hidden)',
        );
      if (profile.env.isNotEmpty) {
        out.writeln('env: ${profile.env.keys.join(', ')}');
      }
    case WebSocketProfile():
      out
        ..writeln('type: webSocket')
        ..writeln('uri: ${profile.uri}');
      if (profile.tokenRef case final ref?) {
        // Только имя переменной или секрета; значение токена не читается.
        // Ссылка иного вида не печатается совсем: в поле, рассчитанное на
        // имя, мог быть вписан сам секрет (решение по безопасности итерации 2
        // change `add-app-settings-shell`, приоритет 1 AGENTS.md §2).
        out.writeln(switch (ProfileTokenRef.parse(ref)) {
          EnvTokenRef(:final name) => 'token: env $name',
          SecretTokenRef(:final name) =>
            'token: secret $name '
                '(${await _isSecretSet(name, openSecrets) ? 'set' : 'missing'})',
          UnsupportedTokenRef() =>
            'token: unrecognized token reference (not supported in this '
                'version)',
        });
      }
    case EmbeddedProfile():
      out
        ..writeln('type: embedded')
        ..writeln('hostProfile: ${profile.hostProfile}');
  }
}

/// Есть ли секрет [name]: без чтения значения; сбой хранилища — «нет».
///
/// Почему не ошибка: `show` — диагностическая команда, и недоступное
/// хранилище должно читаться как `missing`, а не ронять вывод остальных
/// полей профиля. Текст ошибки хранилища не печатается (мог бы цитировать
/// путь или значение).
Future<bool> _isSecretSet(
  String name,
  Future<ProfileSecrets> Function()? openSecrets,
) async {
  if (openSecrets == null) {
    return false;
  }
  try {
    return await (await openSecrets()).isSet(name);
  } on Object catch (_) {
    return false;
  }
}
