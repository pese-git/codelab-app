import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../session/write_queue.dart';

/// Файловая память последней явно выбранной модели
/// `$CODELAB_HOME/state/last-model.json` (design.md change
/// `optional-default-model`, D7).
///
/// Почему отдельный файл: это производное состояние агента, а не настройка
/// пользователя (`config.yaml`) и не журнал (`sessions/`). Писать выбор в
/// `config.yaml` нельзя: молчаливая правка файла с комментариями, конфликт с
/// `ConfigWriter` и превращение неявного выбора в явный. Путь входит в
/// `agentConfigPathsFor` (PERM-11): инструмент записи не должен переводить
/// будущие сессии на другую модель.
///
/// Для чего: реализует порт ядра [LastModelStore] для `codelab-agent serve` и
/// настольного встроенного агента; общий `$CODELAB_HOME` делает память общей
/// у CLI, бинаря и app (D8).
///
/// Формат: `{"v": 1, "model": "<provider>/<model>"}`; неизвестные поля при
/// чтении игнорируются. Запись — очередь `writeQueue` по пути, уникальный
/// временный файл `<path>.tmp-<pid>-<random>` рядом и `rename`; без `fsync` и
/// lock: между процессами выигрывает последний `rename`, а потеря при
/// отключении питания безвредна — выбор модели даст рабочий результат и без
/// файла. Чтение: нет файла — `null` молча; большой (> 4 KiB), нечитаемый или
/// чужой версии файл — `null` и событие `model.last_used.ignored {path,
/// reason}` уровня `warning` (`reason` — категория, без содержимого файла);
/// файл не переписывается. Кэша нет: файл читается на каждый вызов.
///
/// Как использовать: хост создаёт один раз —
/// `FileLastModelStore(codelabHome: home, logger: logger)` — и кладёт в
/// `AgentCoreServices.lastModel`; `config check` вызывает только [read]. В
/// файле только идентификатор модели, секретов нет.
final class FileLastModelStore implements LastModelStore {
  FileLastModelStore({required this.codelabHome, Logger? logger})
    : _logger = logger;

  /// Корень `$CODELAB_HOME` (`codelabHomeOf`).
  final String codelabHome;
  final Logger? _logger;

  /// Предел размера файла: настоящий файл — десятки байт, больше — чужой.
  static const _maxBytes = 4096;

  static final _random = Random.secure();

  /// `<codelabHome>/state/last-model.json`.
  String get path => '$codelabHome/state/last-model.json';

  @override
  Future<ModelId?> read() async {
    final file = File(path);
    try {
      if (!await file.exists()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxBytes) {
        return _ignore('too large');
      }
      final Object? json;
      try {
        json = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        return _ignore('invalid json');
      }
      if (json is! Map<String, Object?>) {
        return _ignore('invalid json');
      }
      if (json['v'] != 1) {
        return _ignore('unknown version');
      }
      final model = json['model'];
      if (model is! String) {
        return _ignore('invalid model');
      }
      final slash = model.indexOf('/');
      if (slash <= 0 || slash == model.length - 1) {
        return _ignore('invalid model');
      }
      return ModelId(model);
    } on FileSystemException {
      return _ignore('unreadable');
    }
  }

  ModelId? _ignore(String reason) {
    _logger?.log(
      LogLevel.warning,
      'model.last_used.ignored',
      fields: {'path': path, 'reason': reason},
    );
    return null;
  }

  @override
  Future<void> write(ModelId model) => writeQueue.run(path, () async {
    await Directory('$codelabHome/state').create(recursive: true);
    final tmp = File('$path.tmp-$pid-${_random.nextInt(1 << 32)}');
    try {
      await tmp.writeAsString(jsonEncode({'v': 1, 'model': model.value}));
      await tmp.rename(path);
    } on Object {
      if (await tmp.exists()) {
        await tmp.delete();
      }
      rethrow;
    }
  });
}
