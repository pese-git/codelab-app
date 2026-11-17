import 'package:codelab_client_core/codelab_client_core.dart';

import '../../cli_args.dart';
import '../../profiles/profile_arg.dart';
import '../../session_setup.dart';
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
      // `label` профиля из `--agent` — исходная командная строка; в скобках
      // его нет (D3), а описание stdio — команда и число аргументов (D1, D2).
      final label = isLabelFromAgentValue(profile.label)
          ? ''
          : ' (${profile.label})';
      final description = switch (profile) {
        StdioProfile() => 'stdio ${describeProfile(profile)}',
        // Только origin: query и userinfo несут секреты (требование «Адрес
        // WebSocket-профиля в выводе CLI» change `add-provider-setup-ui`).
        WebSocketProfile() => describeProfile(profile),
        EmbeddedProfile(:final hostProfile) => 'embedded $hostProfile',
      };
      context.say('Profile ${profile.id}$label: $description');
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
