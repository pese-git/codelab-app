import '../repl_command.dart';
import 'config_option_support.dart';

/// `/config [id] [значение]` — любая опция конфигурации сессии.
final class ConfigCommand implements ReplCommand {
  const ConfigCommand();

  @override
  String get name => 'config';

  @override
  String get usage => '/config [id] [value]';

  @override
  String get description => 'show or set a config option';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    if (args.isEmpty) {
      final options = context.session.current.configOptions;
      if (options.isEmpty) {
        context.say('The agent has no config options.');
      }
      for (final option in options) {
        context.say(
          '${option.id} = ${option.currentValue}  '
          '(${option.values.map((v) => v.value).join(', ')})',
        );
      }
      return;
    }
    final option = findConfigOption(context, args.first);
    if (option == null) {
      context.say('The agent has no "${args.first}" option.');
      return;
    }
    if (args.length == 1) {
      showConfigOption(context, option);
      return;
    }
    await setConfigOption(context, option, args[1], option.id);
  }
}
