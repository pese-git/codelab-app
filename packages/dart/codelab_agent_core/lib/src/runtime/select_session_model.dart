import '../config/core_config.dart';
import '../llm/model_catalog.dart';
import '../llm/model_ref.dart';

/// ЗАГЛУШКА красных тестов change `optional-default-model` (D5): сигнатура
/// без поведения; реализация и doc-комментарий — задача 2.2.
///
/// Чистое правило выбора модели новой сессии: явная модель конфига, затем
/// [lastUsed] из каталога, затем первый провайдер.
(ModelRef, DefaultModelSource) selectSessionModel(
  CoreConfig config,
  ModelId? lastUsed,
  ModelCatalog catalog,
) => throw UnimplementedError('selectSessionModel: задача 2.2');
