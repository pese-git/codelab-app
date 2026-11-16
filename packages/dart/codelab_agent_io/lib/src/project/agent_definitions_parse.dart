/// Разбор определений агентов с каталогом моделей из конфига — одна функция
/// для `config check` и [loadAgentDefinitions] (design.md change
/// `add-settings-agents-modes`, D20.2; SETUP-8).
///
/// Почему отдельная внутренняя функция: «тот же разбор, что у `config check`»
/// (client-agent-setup) должен держаться кодом, а не двумя копиями сборки
/// каталога моделей. Не экспортируется из бареля пакета.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../util/silent_logger.dart';

/// Разбирает [files] ядром (`parseAgentDefinitions`); `model` определения
/// проверяется по провайдерам [config].
AgentParseResult parseAgentDefinitionsOf(
  CoreConfig config,
  List<MarkdownFile> files,
) => parseAgentDefinitions(
  files,
  models: StaticModelCatalog(config.providers, logger: const SilentLogger()),
);
