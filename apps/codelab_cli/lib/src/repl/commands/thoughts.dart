import '../../render/terminal_renderer.dart';
import '../repl_command.dart';

/// `/thoughts dim|collapsed|hidden` — показ мыслей до конца процесса (U-08,
/// §12.2.3).
final class ThoughtsCommand implements ReplCommand {
  const ThoughtsCommand();

  @override
  String get name => 'thoughts';

  @override
  String get usage => '/thoughts dim|collapsed|hidden';

  @override
  String get description => 'show thoughts dimmed, collapsed or not at all';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    final mode = args.length == 1
        ? ThoughtsMode.values.where((m) => m.name == args.single).firstOrNull
        : null;
    if (mode == null) {
      context.say('Usage: $usage');
      return;
    }
    context.renderer.thoughts = mode;
    context.say('thoughts: ${mode.name}');
  }
}
