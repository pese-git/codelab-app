import '../repl_command.dart';

/// `/queue`, `/queue drop <n>`, `/queue clear` — очередь промптов kit; своей
/// очереди у CLI нет (spec codelab-cli «Очередь промптов в REPL»; U-15).
final class QueueCommand implements ReplCommand {
  const QueueCommand();

  @override
  String get name => 'queue';

  @override
  String get usage => '/queue [drop <n>|clear]';

  @override
  String get description => 'show, drop or clear queued prompts';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    final queue = context.session.queue;
    final items = queue.items;
    switch (args) {
      case []:
        if (items.isEmpty) {
          context.say('The queue is empty.');
        }
        for (final (i, item) in items.indexed) {
          context.say('  ${i + 1}. ${_firstLine(item.text)}');
        }
      case ['drop', final value]:
        final n = int.tryParse(value);
        if (n == null || n < 1 || n > items.length) {
          context.say('No queued prompt $value.');
          return;
        }
        final item = items[n - 1];
        if (queue.remove(item.id) != null) {
          context
            ..forgetQueued(1)
            ..say('Dropped $n. ${_firstLine(item.text)}');
        }
      case ['clear']:
        queue.clear();
        context
          ..forgetQueued(items.length)
          ..say('Cleared the queue.');
      case _:
        context.say('Usage: $usage');
    }
  }

  static String _firstLine(String text) {
    final end = text.indexOf('\n');
    return end < 0 ? text : '${text.substring(0, end)} …';
  }
}
