import 'package:codelab_client_core/codelab_client_core.dart';

import '../repl_command.dart';

/// Общее для `/mode`, `/model` и `/config`: поиск опции, показ значений и
/// установка через `session/set_config_option` (U-05; design.md change
/// `add-codelab-cli`, D7).
///
/// Опция ищется по id, затем по категории ACP; неизвестное значение —
/// сообщение без запроса.
ConfigOptionView? findConfigOption(ReplContext context, String name) {
  final options = context.session.current.configOptions;
  return options.where((o) => o.id == name).firstOrNull ??
      options.where((o) => o.category == name).firstOrNull;
}

/// Значения [option] с отметкой текущего.
void showConfigOption(ReplContext context, ConfigOptionView option) {
  context.say('${option.name} (${option.id}):');
  for (final value in option.values) {
    final mark = value.value == option.currentValue ? '*' : ' ';
    context.say('  $mark ${value.value}  ${value.name}');
  }
}

/// Устанавливает [option] значением [value] и печатает итог из ответа
/// агента.
Future<void> setConfigOption(
  ReplContext context,
  ConfigOptionView option,
  String value,
  String label,
) async {
  if (!option.values.any((v) => v.value == value)) {
    context.say(
      'Unknown $label "$value". Available: '
      '${option.values.map((v) => v.value).join(', ')}.',
    );
    return;
  }
  try {
    await context.session.setConfigOption(option.id, value);
  } on Object catch (error) {
    context.say('codelab: cannot set $label: ${describeFailure(error)}');
    return;
  }
  final current = findConfigOption(context, option.id)?.currentValue;
  context.say('${option.id} = ${current ?? value}');
}

/// `/mode` и `/model`: без аргумента — значения, с аргументом — установка.
final class ConfigOptionCommand implements ReplCommand {
  const ConfigOptionCommand(this.name, this.missing);

  @override
  final String name;

  /// Сообщение, если у агента нет такой опции.
  final String missing;

  @override
  String get usage => '/$name [value]';

  @override
  String get description => 'show or set the $name';

  @override
  Future<void> run(ReplContext context, List<String> args) async {
    final option = findConfigOption(context, name);
    if (option == null) {
      context.say(missing);
      return;
    }
    if (args.isEmpty) {
      showConfigOption(context, option);
      return;
    }
    await setConfigOption(context, option, args.first, name);
  }
}
