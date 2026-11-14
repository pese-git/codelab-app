import '../config/core_config.dart';
import '../env/execution_env.dart';
import '../env/memory_env.dart';
import '../llm/stream_function.dart';
import '../prompts/compose.dart';
import '../runtime/agent_runtime.dart';
import '../session/memory_session_store.dart';
import '../tools/builtin/edit.dart';
import '../tools/builtin/exec.dart';
import '../tools/builtin/ls.dart';
import '../tools/builtin/read.dart';
import '../tools/builtin/search.dart';
import '../tools/builtin/write.dart';
import '../tools/registry.dart';
import '../tools/tasks/task_tools.dart';
import '../util/logger.dart';
import 'host_profile.dart';
import 'services.dart';

/// What is on and why (`agent-core-architecture` §10.3).
final class CorePlan {
  CorePlan({
    required this.profile,
    required List<String> toolNames,
    required List<String> promptSections,
    required Map<HostCapability, String> offReasons,
  }) : toolNames = List.unmodifiable(toolNames),
       promptSections = List.unmodifiable(promptSections),
       offReasons = Map.unmodifiable(offReasons);

  /// Already narrowed.
  final HostProfile profile;

  /// In registration order.
  final List<String> toolNames;

  /// Id секций системного промпта в порядке сборки для режима по умолчанию
  /// (§11.5); сессия в другом режиме собирает свой набор.
  final List<String> promptSections;
  final Map<HostCapability, String> offReasons;
}

final class BuiltAgentCore {
  const BuiltAgentCore({required this.plan, required this.runtime});

  final CorePlan plan;
  final AgentRuntime runtime;
}

/// Единственный способ собрать ядро (HOST-6, `agent-core-architecture`
/// §10.7).
///
/// Почему одна точка: сужение профиля по сервисам и конфигурации, реестр
/// инструментов по capability, политика разрешений первым хуком каждой
/// сессии и план включённого должны получаться одинаково у всех хостов.
///
/// Как использовать: хост передаёт профиль, сервисы, конфигурацию и
/// [streamFunction] — фабрику провайдеров этапа 1 или scripted-модель в
/// тестах. Несовместимые сервисы (журнал в памяти при `sessionPersistence`,
/// env без shell при `shellExec`) — `HostWiringException`;
/// `CoreConfig.compaction.enabled: false` выключает capability `compaction`.
///
/// Живая перезагрузка (design.md change `add-config-writer-and-reload`, D8):
/// [streamFunction] остаётся функцией модели начального снимка, начальный
/// каталог — `AgentCoreServices.models`. [modelsFor] нужен, если передан
/// `AgentCoreServices.config` (иначе `HostWiringException`), и вызывается
/// только на снимках, применённых перезагрузкой, — при сборке нет; хост с
/// источником строит начальную пару одним вызовом того же замыкания. Без
/// источника [modelsFor] не требуется и не вызывается. [configCommand] `false`
/// не объявляет и не исполняет встроенную `/config` (`serve --ws`, R0-3).
BuiltAgentCore buildAgentCore({
  required HostProfile profile,
  required AgentCoreServices services,
  required CoreConfig config,
  required StreamFunction streamFunction,
  ConfiguredModels Function(CoreConfig config)? modelsFor,
  bool configCommand = true,
}) {
  if (services.config != null && modelsFor == null) {
    throw const HostWiringException(
      'AgentCoreServices.config требует modelsFor: перезагрузка строит '
      'функцию модели и каталог по новому снимку',
    );
  }
  // D21: без `modelsFor` функцию модели и каталог сессии папки не построить.
  if (services.projectConfig != null && modelsFor == null) {
    throw const HostWiringException(
      'AgentCoreServices.projectConfig требует modelsFor: сессия другой '
      'папки получает функцию модели и каталог по своей конфигурации',
    );
  }
  final narrowed = profile.narrowed({
    if (services.gate == null)
      HostCapability.interactiveApproval: const CapabilityOff(
        'PermissionGate не передан',
      ),
    if (services.baseEnv is! DirectoryListing)
      HostCapability.fileListing: const CapabilityOff(
        'env без листинга каталога',
      ),
    if (!config.compaction.enabled)
      HostCapability.compaction: const CapabilityOff('выключено конфигом'),
    if (services.mcp == null)
      HostCapability.mcp: const CapabilityOff('сервис MCP не передан'),
    // Навыки (design.md change `add-agent-skills`, D11, D16, Q44, Q45):
    // `skills.enabled` capability НЕ сужает. Настройка принадлежит папке
    // сессии: рантайм читает её из конфигурации сессии и для сессий с
    // `enabled: false` отдаёт `SkillCatalog.empty`, не вызывая порт. Если
    // сузить capability по конфигу корня запуска, сессии доверенной папки
    // `/B` с `enabled: true` навыков не получили бы. Сужает только профиль
    // (`profile.<name>.skills: off`); без порта (`skillFiles == null`)
    // capability остаётся `on`, сессия без навыков.
  });
  // §10.8: журнал на постоянном носителе требует хранилища, которое не
  // теряет записи при выходе процесса.
  if (narrowed.isOn(HostCapability.sessionPersistence) &&
      services.sessions is MemorySessionStore) {
    throw const HostWiringException(
      'capability sessionPersistence требует постоянного SessionStore: '
      'MemorySessionStore теряет журнал при выходе процесса',
    );
  }
  // HOST-3: коннектор обязан уметь каждый транспорт включённой capability.
  if (narrowed.states[HostCapability.mcp]
      case CapabilityTransport(:final transports) when services.mcp != null) {
    final missing = transports.difference(services.mcp!.transports);
    if (missing.isNotEmpty) {
      throw HostWiringException(
        'capability mcp требует транспорты ${(transports.toList()..sort()).join(', ')}: '
        'McpConnector не умеет ${(missing.toList()..sort()).join(', ')}',
      );
    }
  }
  if (narrowed.isOn(HostCapability.shellExec) &&
      services.baseEnv is MemoryExecutionEnv) {
    throw const HostWiringException(
      'capability shellExec требует сервис baseEnv с настоящим Shell.exec: '
      'у MemoryExecutionEnv его нет',
    );
  }
  final registry = ToolRegistry();
  void register(String name, void Function() add) {
    if (registry.lookup(name) != null) {
      throw HostWiringException('два встроенных инструмента с именем $name');
    }
    add();
  }

  // Порядок §10.7, шаг 5: базовые инструменты, затем по capability.
  register('read', () => registry.register(ReadTool()));
  register('write', () => registry.register(WriteTool()));
  register('edit', () => registry.register(EditTool()));
  // Список задач вместо update_plan (change `add-subagents-and-tasks`, D13):
  // четыре инструмента всегда; секцию промпта включает якорь task_create.
  register('task_create', () => registry.register(TaskCreateTool()));
  register('task_update', () => registry.register(TaskUpdateTool()));
  register('task_list', () => registry.register(TaskListTool()));
  register('task_get', () => registry.register(TaskGetTool()));
  if (narrowed.isOn(HostCapability.shellExec)) {
    register('exec', () => registry.register(ExecTool()));
  }
  if (narrowed.isOn(HostCapability.fileListing)) {
    register('ls', () => registry.register(LsTool()));
    register('search', () => registry.register(SearchTool()));
  }
  final plan = CorePlan(
    profile: narrowed,
    toolNames: [for (final t in registry.tools) t.name],
    // Секции промпта новой сессии в режиме по умолчанию (§10.7, шаг 7).
    promptSections: systemPromptSections(
      PromptInputs(
        cwd: '/',
        platform: services.platform,
        today: services.clock.now(),
        mode: config.permissions.mode ?? narrowed.defaultMode,
        profile: narrowed,
        toolNames: {for (final t in registry.tools) t.name},
      ),
    ),
    offReasons: {
      for (final MapEntry(key: capability, value: state)
          in narrowed.states.entries)
        if (state case CapabilityOff(:final reason)) capability: reason,
    },
  );
  services.logger.log(
    LogLevel.info,
    'host.plan',
    fields: {
      'profile': narrowed.name,
      'tools': plan.toolNames,
      'off': {for (final e in plan.offReasons.entries) e.key.name: e.value},
    },
  );
  return BuiltAgentCore(
    plan: plan,
    runtime: AgentRuntimeImpl(
      profile: narrowed,
      services: services,
      config: config,
      registry: registry,
      stream: streamFunction,
      // Нужен и перезагрузке корня (`config`), и сессиям других папок
      // (`projectConfig`, D21): порт может быть без источника.
      modelsFor: services.config == null && services.projectConfig == null
          ? null
          : modelsFor,
      configCommand: configCommand,
    ),
  );
}
