import 'dart:convert';

import 'package:codelab_client_core/codelab_client_core.dart';

import '../cli_args.dart';
import '../exit_codes.dart';
import 'profile_arg.dart';

final _profileId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$');

/// Команда `codelab profiles list|show <id>|add <id> <agent>|remove <id>`.
///
/// Почему: без профиля `default` CLI не знает, какого агента запускать, а
/// писать `profiles.json` руками — ошибкоопасно (U-06, DoD §9.11). Команда
/// работает без запуска агента.
///
/// Как использовать: вызывает `runCodelab` для подкоманды `profiles`;
/// результат — код выхода. Неверные аргументы — [UsageError] (код `64`
/// у вызывающего); неизвестный профиль у `show` и `remove` — текст в
/// [stderr] и [failureExit].
Future<int> runProfilesCommand(
  List<String> args, {
  required ProfileStore store,
  required StringSink stdout,
  required StringSink stderr,
}) async {
  switch (args) {
    case ['list']:
      final profiles = await _load(store);
      if (profiles.isEmpty) {
        stdout.writeln(
          'No agent profiles. Add one with '
          '"codelab profiles add default stdio:<command>".',
        );
        return okExit;
      }
      final width = profiles
          .map((profile) => profile.id.length)
          .reduce((a, b) => a > b ? a : b);
      for (final profile in profiles) {
        stdout.writeln('${profile.id.padRight(width)}  ${_summary(profile)}');
      }
      return okExit;
    case ['show', final id]:
      final profile = (await _load(store)).where((p) => p.id == id).firstOrNull;
      if (profile == null) {
        stderr.writeln('codelab: Unknown agent profile "$id".');
        return failureExit;
      }
      _show(profile, stdout);
      return okExit;
    case ['add', final id, final value]:
      if (!_profileId.hasMatch(id) || id == 'embedded') {
        throw UsageError(
          'Invalid profile id "$id": use letters, digits, ".", "_" and "-".',
        );
      }
      final profile = inlineAgentProfile(value, id: id);
      if (profile == null) {
        throw UsageError(
          'Invalid agent "$value": use "stdio:<command> [args]", ws:// or '
          'wss://.',
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
  StdioProfile(:final command, :final args) =>
    'stdio: ${[command, ...args].join(' ')}',
  WebSocketProfile(:final uri) => 'ws: $uri',
};

/// Аргументы печатаются JSON-массивом: так видно границы слов с пробелами.
/// Значение токена не печатается никогда — только откуда оно берётся.
void _show(ConnectionProfile profile, StringSink out) {
  out.writeln('id: ${profile.id}');
  switch (profile) {
    case StdioProfile():
      out
        ..writeln('type: stdio')
        ..writeln('command: ${profile.command}')
        ..writeln('args: ${jsonEncode(profile.args)}');
      if (profile.env.isNotEmpty) {
        out.writeln('env: ${profile.env.keys.join(', ')}');
      }
    case WebSocketProfile():
      out
        ..writeln('type: webSocket')
        ..writeln('uri: ${profile.uri}');
      if (profile.tokenRef case final ref?) {
        out.writeln(
          'token: ${ref.startsWith('env:') ? '\$${ref.substring(4)}' : ref}',
        );
      }
  }
}
