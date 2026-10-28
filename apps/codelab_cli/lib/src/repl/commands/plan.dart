import '../repl_command.dart';

/// `/plan` — текущий план сессии целиком.
final class PlanCommand implements ReplCommand {
  const PlanCommand();

  @override
  String get name => 'plan';

  @override
  String get usage => '/plan';

  @override
  String get description => 'show the current plan';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    final plan = context.session.current.plan;
    if (plan.isEmpty) {
      context.say('No plan yet.');
      return;
    }
    context.showPlan(plan);
  }
}
