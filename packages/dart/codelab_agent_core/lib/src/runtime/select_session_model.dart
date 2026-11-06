import '../config/core_config.dart';
import '../llm/model_catalog.dart';
import '../llm/model_ref.dart';

/// Чистое правило выбора модели новой сессии (design.md change
/// `optional-default-model`, D5).
///
/// Почему отдельная публичная функция: правило одно для рантайма
/// (`createSession`) и для `config check` в `codelab_agent_io`; две копии
/// разошлись бы. Источник идеи порядка — поведение OpenCode в описании
/// пользователя (код не изучался и не воспроизводится, `07-decision-sources`
/// §7а, п. 3).
///
/// Порядок: (1) явная модель конфига ([DefaultModelSource.config]) — всегда
/// побеждает, [lastUsed] даже не нужен; (2) [lastUsed], если [catalog]
/// разрешает её (источник [DefaultModelSource.lastUsed]); (3) модель
/// [CoreConfig.defaultModel] — первая модель первого доступного провайдера
/// (источник [DefaultModelSource.firstProvider]).
///
/// Как использовать: вызывающий сам читает порт `LastModelStore` (и
/// перехватывает его сбои) и передаёт результат в [lastUsed]; `null` — шаг 2
/// пропускается. Ошибок функция не бросает.
(ModelRef, DefaultModelSource) selectSessionModel(
  CoreConfig config,
  ModelId? lastUsed,
  ModelCatalog catalog, {
  ReasoningEffort? effort,
}) {
  if (config.defaultModelSource == DefaultModelSource.config) {
    return (config.defaultModel, DefaultModelSource.config);
  }
  if (lastUsed != null) {
    final model = catalog.resolve(lastUsed, effort: effort);
    if (model != null) {
      return (model, DefaultModelSource.lastUsed);
    }
  }
  return (config.defaultModel, DefaultModelSource.firstProvider);
}
