import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Пишет предупреждения загрузки конфигурации в лог хоста.
///
/// Почему одна функция в `codelab_agent_io`: `codelab-agent` и встроенный
/// агент (`codelab_embedded/io.dart`) обязаны писать одни и те же события —
/// валидный конфиг пишет их при сборке хоста, а невалидный — при отчёте об
/// ошибках (D16 change `add-agent-configuration`; задача 2.8 change
/// `add-embedded-agent-mode`). Неизвестные `CODELAB_*` распознаёт
/// `ConfigLoader` и кладёт в те же `warnings` событием `config.env.unknown`
/// (D13), поэтому каждое предупреждение пишется ровно один раз.
///
/// Как использовать: `logConfigWarnings(logger, loaded)` сразу после
/// `ConfigLoader.load`. Предупреждение — событие со своим именем (без имени —
/// `config.warning`) и уровнем из [ConfigIssue.level]; в `message` нет
/// значений ключей (CFG-2).
void logConfigWarnings(Logger logger, ConfigLoadResult loaded) {
  for (final warning in loaded.warnings) {
    logger.log(
      warning.level,
      warning.event ?? 'config.warning',
      fields: {...warning.fields, 'message': warning.message},
    );
  }
}
