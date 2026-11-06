import 'package:codelab_agent_core/codelab_agent_core.dart';

/// ЗАГЛУШКА красных тестов change `optional-default-model` (D7): сигнатуры
/// без поведения; doc-комментарий и реализация — задача 3.2.
///
/// Файловая память последней модели `$CODELAB_HOME/state/last-model.json`.
/// Конструктор и [path] — предположение исполнителя тестов (design.md не
/// фиксирует сигнатуру): по образцу `openHostSessions(codelabHome:)`.
final class FileLastModelStore implements LastModelStore {
  FileLastModelStore({required this.codelabHome, Logger? logger})
    : _logger = logger;

  final String codelabHome;
  final Logger? _logger;

  /// `<codelabHome>/state/last-model.json`.
  String get path => '$codelabHome/state/last-model.json';

  @override
  Future<ModelId?> read() =>
      throw UnimplementedError('FileLastModelStore.read: задача 3.2 $_logger');

  @override
  Future<void> write(ModelId model) =>
      throw UnimplementedError('FileLastModelStore.write: задача 3.2');
}
