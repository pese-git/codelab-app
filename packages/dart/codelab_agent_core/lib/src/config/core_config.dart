import '../llm/model_catalog.dart';
import '../llm/model_ref.dart';
import '../loop/turn_budget.dart';
import '../mcp/mcp_server_config.dart';
import '../permissions/modes.dart';
import '../permissions/policy.dart';
import '../tools/agent_tool.dart' show ToolTier;
import 'config_issue.dart';
import 'config_tree.dart';
import 'key_path.dart';
import 'redact_settings.dart';
import 'resolve.dart';
import 'schema.dart' show defaultProjectContextMaxBytes;

// Константы бюджета живут в `schema.dart`: правило доверия `trust.dart`
// читает их оттуда, и цикл `core_config → resolve → trust → core_config`
// не возникает. Публичный API прежний.
export 'schema.dart'
    show defaultProjectContextMaxBytes, maxProjectContextMaxBytes;

/// Часть конфигурации, относящаяся к разрешениям (`agent-core-architecture`
/// §7, §15.3, §15.4).
///
/// Почему отдельный объект: режим, правила и запреты уровней приходят из
/// слоёв конфига вместе и применяются политикой `PermissionPolicy` одним
/// набором. [extraDeniedTiers] нужен потому, что слои могут дать сочетание
/// «`ask` + `plan`» (§15.3): `ask` спрашивает про всё, а `plan` запрещает
/// write/exec; один идентификатор режима этого не выразит.
///
/// Как использовать: `CoreConfig.fromLayers` заполняет поля, тесты и
/// встроенные хосты создают значение сами. [mode] `null` — режим профиля
/// (§10.5); [modeOverride] — режимы флага запуска (`autopilot`, CFG-4);
/// [extraDeniedTiers] политика объединяет с запретами самого режима.
final class PermissionsConfig {
  const PermissionsConfig({
    this.mode,
    this.modeOverride,
    this.rules = const PolicyRules(),
    this.extraDeniedTiers = const {},
  });

  /// Replaces the default mode of the profile (§10.5).
  final ModeId? mode;

  /// `autopilot` and other launch-flag modes (design.md of
  /// `add-agent-core-permission-policy`, D3).
  final PermissionMode? modeOverride;
  final PolicyRules rules;

  /// Уровни инструментов, запрещённые без вопроса сверх запретов режима.
  final Set<ToolTier> extraDeniedTiers;
}

/// Проверенная конфигурация ядра.
///
/// Почему одно значение: сборка ядра (`buildAgentCore`) и все сессии
/// читают настройки из одного места, а хост собирает его из своих
/// источников. Чтение файлов — задача хоста (`ConfigLoader` в
/// `codelab_agent_io`); сама проверка слоёв — [fromLayers] (design.md change
/// `add-agent-configuration`, D3).
///
/// Как использовать: хост создаёт значение напрямую (тесты, встроенные
/// хосты) или получает его из [fromLayers] и передаёт в `buildAgentCore`;
/// поля по умолчанию дают поведение без переопределений.
final class CoreConfig {
  const CoreConfig({
    required this.defaultModel,
    this.permissions = const PermissionsConfig(),
    this.budget = const TurnBudget(),
    this.compaction = const CompactionOverrides(),
    this.effort = ReasoningEffort.medium,
    this.mcpServers = const [],
    this.providers = const [],
    this.providerProblems = const {},
    this.redact = const RedactSettings(),
    this.projectContextMaxBytes = defaultProjectContextMaxBytes,
    this.trustedProjects = const [],
    this.projectRoot,
    this.withoutProject,
  });

  /// Проверяет слои от низшего приоритета к высшему и собирает конфигурацию
  /// (`agent-core-architecture` §15.5, шаги 3–9).
  ///
  /// Почему функция ядра, а не загрузчик: проверка — чистая и работает над
  /// уже разобранным деревом (CFG-5); мобильный и web-хосты передают слои
  /// без позиций и получают ту же проверку.
  ///
  /// Как использовать: [environment] — переменные для `${ENV}` и проверки
  /// `api_key_env` (само значение ключа загрузка не читает, D4);
  /// [projectRoot] — канонический корень проектных слоёв (доверие §15.3 и
  /// [withoutProject], D9). Исключений не бросает: либо `config` без проблем,
  /// либо непустой `issues`.
  static ConfigLoadResult fromLayers(
    List<ConfigTree> layers, {
    required Map<String, String> environment,
    String? projectRoot,
  }) =>
      resolveConfig(layers, environment: environment, projectRoot: projectRoot);

  final ModelRef defaultModel;

  /// Уровень рассуждения новой сессии (`agent.effort`, §2.12.3, §15.4);
  /// доходит до запроса только у модели с рассуждением.
  final ReasoningEffort effort;
  final PermissionsConfig permissions;
  final TurnBudget budget;

  /// Настройки сжатия контекста (§9.4, §15).
  final CompactionOverrides compaction;

  /// MCP-серверы конфигурации (`origin: config`). Сервер клиента с тем же
  /// `name` заменяет сервер конфига (§13.4, шаг 2; D6).
  final List<McpServerConfig> mcpServers;

  /// Провайдеры конфигурации с объявленными моделями, в порядке файла.
  /// Хост строит из них каталог и функцию модели
  /// (`createRoutedStreamFunction`, D11).
  final List<CatalogProvider> providers;

  /// Провайдер → причина, по которой его ключ недоступен заранее:
  /// переменная `api_key_env` не задана (быстрый отказ, D4). Выбор такой
  /// модели даёт ошибку хода без HTTP-запроса. Записей о секретах здесь нет:
  /// `api_key_secret` и `${secret:…}` разрешаются при первом запросе
  /// (design.md change `add-agent-secret-store`, D4).
  final Map<String, String> providerProblems;

  /// Проверенные ключи `redact.*`.
  final RedactSettings redact;

  /// Бюджет инструкций проекта в системном промпте, байты
  /// (`tools.project_context.max_bytes`, `0` — выключено; design.md change
  /// `add-agent-project-files`, D5). Runtime передаёт его порту файлов
  /// проекта и `assembleProjectContext`.
  final int projectContextMaxBytes;

  /// Канонические корни `trusted_projects` глобального слоя (~ раскрыт,
  /// symlink раскрыт `ConfigLoader`). Runtime сравнивает с ними канонический
  /// `cwd` каждой сессии (D4): доверие сессии определяется её собственным
  /// каталогом, а не корнем запуска хоста. Проектные слои список не меняют
  /// (CFG-3).
  final List<String> trustedProjects;

  /// Корень, для которого прочитаны проектные слои 3–4; `null` — проектных
  /// слоёв нет (design.md, D9).
  final String? projectRoot;

  /// Снимок без проектных слоёв для сессий вне [projectRoot] (D9, OQ1 (а)).
  final CoreConfig? withoutProject;

  /// Конфигурация сессии с данным [cwd]: полная для сессии в [projectRoot] и
  /// [withoutProject] для любой другой. Сравнивается равенство путей, а не
  /// вложенность: у подкаталога может быть свой `.codelab/`, и чужой
  /// проектный конфиг к нему неприменим (D9). Без [projectRoot] или
  /// [withoutProject] поведение прежнее — все сессии получают этот объект.
  CoreConfig forSessionCwd(String cwd) {
    final root = projectRoot;
    final bare = withoutProject;
    if (root == null || bare == null || samePath(cwd, root)) {
      return this;
    }
    return bare;
  }
}

/// Переопределения порогов сжатия из конфигурации (`agent-core-architecture`
/// §9.4, ключи `compaction.*` §15; design.md change
/// `add-agent-core-sessions-and-compaction`, D8).
///
/// Почему переопределения, а не готовые числа: пороги зависят от окна
/// модели (`CompactionSettings.forWindow`), а модель сессии может меняться.
/// Заданное значение заменяет вычисленное и проходит те же ограничения
/// сверху `w/4` и `w/2`, поэтому настройка не делает порог отрицательным.
///
/// Как использовать: `null` в поле — значение из таблицы §9.4.
/// [contextWindowCap] ограничивает окно для порога, проверки перед запросом
/// и оценки в `ModelRequested` (CMP-6). `enabled: false` выключает
/// capability `compaction` при сборке ядра.
final class CompactionOverrides {
  const CompactionOverrides({
    this.reserveTokens,
    this.keepRecentTokens,
    this.keepRecentUserTurns,
    this.contextWindowCap,
    this.enabled = true,
  });

  final int? reserveTokens;
  final int? keepRecentTokens;
  final int? keepRecentUserTurns;
  final int? contextWindowCap;
  final bool enabled;
}
