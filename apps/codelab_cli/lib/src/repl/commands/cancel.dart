import 'package:codelab_client_core/codelab_client_core.dart';

import '../repl_command.dart';

/// `/cancel` — отменить идущий ход (`session/cancel`).
final class CancelCommand implements ReplCommand {
  const CancelCommand();

  @override
  String get name => 'cancel';

  @override
  String get usage => '/cancel';

  @override
  String get description => 'cancel the running turn';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    if (context.session.current.status != SessionStatusView.running) {
      context.say('Nothing to cancel.');
      return;
    }
    await context.cancelTurn();
  }
}
