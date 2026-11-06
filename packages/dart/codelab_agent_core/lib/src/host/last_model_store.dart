import '../llm/model_catalog.dart' show ModelId;

/// ЗАГЛУШКА красных тестов change `optional-default-model` (D6): сигнатура
/// порта без поведения; настоящий doc-комментарий и реализация — задача 2.2.
///
/// Порт памяти последней явно выбранной модели; `null` в
/// `AgentCoreServices.lastModel` — памяти нет.
abstract interface class LastModelStore {
  Future<ModelId?> read();
  Future<void> write(ModelId model);
}
