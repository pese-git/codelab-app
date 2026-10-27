import 'config_option_support.dart';

/// `/mode [id]` — режим агента через опцию конфигурации `mode`: kit не
/// поддерживает устаревший `session/set_mode` (design.md, D7).
const modeCommand = ConfigOptionCommand(
  'mode',
  'The agent does not expose a "mode" config option.',
);
