import '../repl_command.dart';

/// `/help` — команды клиента и агента; `/help keys` — таблица клавиш,
/// построенная из `KeyBindings` (§12.2.11, TUI-7).
final class HelpCommand implements ReplCommand {
  const HelpCommand();

  @override
  String get name => 'help';

  @override
  String get usage => '/help [keys]';

  @override
  String get description => 'show the commands, or the keys with "keys"';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    if (args.isNotEmpty && args.first == 'keys') {
      context.keys.helpLines().forEach(context.say);
      return;
    }
    final width = context.commands
        .map((c) => c.usage.length)
        .reduce((a, b) => a > b ? a : b);
    context.say('Commands:');
    for (final command in context.commands) {
      context.say('  ${command.usage.padRight(width)}  ${command.description}');
    }
    final agent = context.session.current.agentCommands;
    if (agent.isNotEmpty) {
      context.say('Agent commands:');
      final names = {for (final c in context.commands) c.name};
      for (final command in agent) {
        final label = names.contains(command.name)
            ? '/agent:${command.name}'
            : '/${command.name}';
        context.say('  $label  ${command.description}');
      }
    }
    context.say('Run /help keys for the keys.');
  }
}
