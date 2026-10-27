import 'package:codelab_client_core/codelab_client_core.dart';

import '../../cli_args.dart';
import '../repl_command.dart';

/// `/profile [id]` — текущий профиль или подключение к другому: id из
/// `profiles.json` или форма значения `--agent` (design.md, D7).
final class ProfileCommand implements ReplCommand {
  const ProfileCommand();

  @override
  String get name => 'profile';

  @override
  String get usage => '/profile [id]';

  @override
  String get description => 'show the agent profile or connect to another';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    if (args.isEmpty) {
      final profile = context.profile;
      context.say(
        'Profile ${profile.id} (${profile.label}): ${switch (profile) {
          StdioProfile(:final command, :final args) => 'stdio ${[command, ...args].join(' ')}',
          WebSocketProfile(:final uri) => '$uri',
        }}',
      );
      return;
    }
    final ConnectionProfile profile;
    try {
      profile = await context.resolveProfile(args.first);
    } on UsageError catch (error) {
      context.say(error.message);
      return;
    }
    await context.switchProfile(profile);
  }
}
