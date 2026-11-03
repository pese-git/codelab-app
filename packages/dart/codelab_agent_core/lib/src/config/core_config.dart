import '../llm/model_catalog.dart';
import '../llm/model_ref.dart';
import '../loop/turn_budget.dart';
import '../mcp/mcp_server_config.dart';
import '../permissions/modes.dart';
import '../permissions/policy.dart';
import '../tools/agent_tool.dart' show ToolTier;
import 'config_issue.dart';
import 'config_tree.dart';
import 'key_path.dart' show samePath;
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

/// Отложенные до перезапуска части `CoreConfig` в структурированном виде
/// (design.md change `add-config-writer-and-reload`, D8, «Пересборка снимка
/// с отложенными ключами»; R0-1).
///
/// Почему не строки ключей: `CoreConfig.withDeferred` раньше разбирал ключи
/// показа обратно в имена, а имя сервера с `[`, `]`, `"` не разбирается:
/// разбор давал `null`, и новый stdio-сервер оставался в снимке (fail-open).
/// Имена и идентификаторы берёт `planConfigReload` из самих снимков.
///
/// Как использовать: `planConfigReload` возвращает значение в
/// `ConfigReloadPlan.deferred` (объединение по полному снимку и снимку без
/// проекта); рантайм передаёт его в [CoreConfig.withDeferred]. Тесты строят
/// значение напрямую.
final class DeferredConfigParts {
  const DeferredConfigParts({
    this.providers = const {},
    this.servers = const {},
    this.disabledServers = const {},
    this.disabledServersWithoutProject = const {},
    this.permissions = false,
    this.defaultModel = false,
  });

  /// Идентификаторы провайдеров, чья группа адреса и аутентификации (и
  /// ссылки на модели нового провайдера) остаётся прежней.
  final Set<String> providers;

  /// Имена серверов `mcp.servers`: прежний элемент того же имени, а нового
  /// нет — он исключается.
  final Set<String> servers;

  /// Подмножество [servers]: сервер выключен этой же правкой, а правка его
  /// соединения отложена (R6-1). В снимке остаётся прежний элемент с
  /// `enabled: false`: выключение действует сразу, `/mcp enable` подключит
  /// прежние параметры.
  final Set<String> disabledServers;

  /// То же для снимка без проекта: выключение применяется только в том
  /// снимке, чей план его дал (проектный слой может выключить сервер только в
  /// полном снимке).
  final Set<String> disabledServersWithoutProject;

  /// Отложенные части для снимка без проекта: его собственный набор
  /// выключаемых серверов.
  DeferredConfigParts get forWithoutProject => DeferredConfigParts(
    providers: providers,
    servers: servers,
    disabledServers: disabledServersWithoutProject,
    disabledServersWithoutProject: disabledServersWithoutProject,
    permissions: permissions,
    defaultModel: defaultModel,
  );

  /// Весь раздел `permissions` берётся прежним.
  final bool permissions;

  /// `agent.default_model` остаётся прежней.
  final bool defaultModel;

  bool get isEmpty =>
      providers.isEmpty && servers.isEmpty && !permissions && !defaultModel;

  /// Объединение: отложенное в любом из снимков откладывается в обоих.
  /// Исключение — `disabledServers` и `disabledServersWithoutProject`: они
  /// описывают снимок, чей план их дал, и здесь суммируются только как набор
  /// имён; `planConfigReload` задаёт их по снимкам отдельно (R6-1).
  DeferredConfigParts union(DeferredConfigParts other) => DeferredConfigParts(
    providers: {...providers, ...other.providers},
    servers: {...servers, ...other.servers},
    disabledServers: {...disabledServers, ...other.disabledServers},
    disabledServersWithoutProject: {
      ...disabledServersWithoutProject,
      ...other.disabledServersWithoutProject,
    },
    permissions: permissions || other.permissions,
    defaultModel: defaultModel || other.defaultModel,
  );
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
    this.withoutProjectValues,
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
  ///
  /// [collectAll] (R3-1, решение 2026-11-03; design.md change
  /// `add-config-writer-and-reload`, D5) — режим писателя: ошибка проверки
  /// слоя не обрывает следующие ступени, ключи с ошибкой исключаются, а в
  /// `issues` попадают проблемы всех ступеней, включая каскадные. Обычная
  /// загрузка (`false`) не меняется.
  ///
  /// [pinnedTrustedProjects] (design.md change `add-config-writer-and-reload`,
  /// D8, «Пересборка снимка с отложенными ключами») — закреплённый список
  /// доверия: по нему, а не по `trusted_projects` слоёв, оцениваются проектные
  /// слои 3–4 и заполняется `trustedProjects` полного снимка и
  /// `withoutProject`. Почему в ядре: доверие решает, какие ключи проектных
  /// слоёв войдут в дерево, и после слияния этого не восстановить. Хост
  /// передаёт `initial.config.trustedProjects` на каждой перезагрузке; новое
  /// значение ключа попадает только в `ConfigLoadResult.values`. `null` —
  /// доверие по слоям, как при старте. Элементы уже канонические (список
  /// стартового снимка), повторно не раскрываются.
  static ConfigLoadResult fromLayers(
    List<ConfigTree> layers, {
    required Map<String, String> environment,
    String? projectRoot,
    bool collectAll = false,
    List<String>? pinnedTrustedProjects,
  }) => resolveConfig(
    layers,
    environment: environment,
    projectRoot: projectRoot,
    collectAll: collectAll,
    pinnedTrustedProjects: pinnedTrustedProjects,
  );

  /// Подставляет в [next] отложенные до перезапуска части из [previous]
  /// (design.md change `add-config-writer-and-reload`, D8, «Пересборка
  /// снимка с отложенными ключами», звено 2).
  ///
  /// Почему в ядре и чистой функцией: какие части отложить, видно только
  /// после сравнения с применённым снимком (R0-1, R0-4), а подстановка
  /// работает над `CoreConfig` и его [withoutProject]; `HostSettings` и
  /// `values` лежат в `ConfigLoadResult`, их подставляет рантайм.
  ///
  /// [deferred] — структурированные части (имена серверов и идентификаторы
  /// провайдеров из снимков, а не разбор ключей показа): `permissions`
  /// целиком прежние, `defaultModel` прежняя, сервер из `servers` — прежний
  /// элемент того же имени (нового нет — он исключается), провайдер из
  /// `providers` — группа адреса и аутентификации прежняя (`CatalogProvider`
  /// собирается из прежних `config`, `key` и `headerTemplates` и новых
  /// `models`, запись `providerProblems` прежняя; нового провайдера
  /// [previous] не знает — он исключается). Остальное ([trustedProjects],
  /// бюджет, сжатие, `effort`) берётся из [next]: доверие уже закреплено
  /// `fromLayers(pinnedTrustedProjects:)`.
  ///
  /// [withoutProjectValues] — `values` снимка без проекта после подстановки
  /// (`ConfigReloadPlan.appliedWithoutProjectValues`); по умолчанию — из
  /// [next]. Следующая перезагрузка сравнивает с ними (R0-1).
  ///
  /// Как использовать: рантайм вызывает после `planConfigReload` и затем
  /// проверяет итог [validateSnapshot]. Снимок без проекта подставляется
  /// тем же способом относительно `previous.withoutProject` (или `previous`,
  /// если у прежнего снимка проектных слоёв не было).
  static CoreConfig withDeferred(
    CoreConfig previous,
    CoreConfig next,
    DeferredConfigParts deferred, {
    Map<String, Object?>? withoutProjectValues,
  }) {
    if (deferred.isEmpty) {
      return withoutProjectValues == null
          ? next
          : next._copyWith(
              withoutProject: next.withoutProject,
              withoutProjectValues: withoutProjectValues,
            );
    }
    final providers = deferred.providers;
    final servers = deferred.servers;
    final oldProviders = {for (final p in previous.providers) p.config.name: p};
    final oldServers = {for (final s in previous.mcpServers) s.name: s};
    final problems = {...next.providerProblems};
    for (final id in providers) {
      problems.remove(id);
      if (previous.providerProblems[id] case final problem?) {
        problems[id] = problem;
      }
    }
    final bare = next.withoutProject;
    return next._copyWith(
      defaultModel: deferred.defaultModel ? previous.defaultModel : null,
      permissions: deferred.permissions ? previous.permissions : null,
      mcpServers: [
        for (final server in next.mcpServers)
          if (!servers.contains(server.name))
            server
          else if (deferred.disabledServers.contains(server.name))
            ?oldServers[server.name]?.withEnabled(false)
          else
            ?oldServers[server.name],
      ],
      providers: [
        for (final provider in next.providers)
          if (!providers.contains(provider.config.name))
            provider
          else if (oldProviders[provider.config.name] case final old?)
            CatalogProvider(
              old.config,
              models: provider.models,
              key: old.key,
              headerTemplates: old.headerTemplates,
            ),
      ],
      providerProblems: problems,
      withoutProject: bare == null
          ? null
          : withDeferred(
              previous.withoutProject ?? previous,
              bare,
              deferred.forWithoutProject,
            ),
      withoutProjectValues: withoutProjectValues,
    );
  }

  /// Единственное место, где `CoreConfig` копируется поле за полем: новое
  /// поле нельзя забыть в одной из точек подстановки. `null` — поле берётся
  /// у этого снимка; [withoutProject] подставляется всегда (его `null` значит
  /// «снимка нет»).
  CoreConfig _copyWith({
    ModelRef? defaultModel,
    PermissionsConfig? permissions,
    List<McpServerConfig>? mcpServers,
    List<CatalogProvider>? providers,
    Map<String, String>? providerProblems,
    required CoreConfig? withoutProject,
    Map<String, Object?>? withoutProjectValues,
  }) => CoreConfig(
    defaultModel: defaultModel ?? this.defaultModel,
    permissions: permissions ?? this.permissions,
    budget: budget,
    compaction: compaction,
    effort: effort,
    mcpServers: mcpServers ?? this.mcpServers,
    providers: providers ?? this.providers,
    providerProblems: providerProblems ?? this.providerProblems,
    redact: redact,
    projectContextMaxBytes: projectContextMaxBytes,
    trustedProjects: trustedProjects,
    projectRoot: projectRoot,
    withoutProject: withoutProject,
    withoutProjectValues: withoutProjectValues ?? this.withoutProjectValues,
  );

  /// Семантическая проверка снимка после подстановки отложенных частей
  /// (D8, шаг 5): модель по умолчанию должна быть в каталоге провайдеров.
  ///
  /// Почему повторно: `fromLayers` проверил новый снимок целиком, но
  /// [withDeferred] мог вернуть прежнюю ссылку на модель, которой в новых
  /// моделях провайдера уже нет. Отложенная ссылка на модель нового
  /// провайдера эту проверку не роняет: она откладывается вместе с
  /// провайдером.
  ///
  /// Возвращает проблемы (пусто — снимок годится); значений в тексте нет.
  /// Проверяются и [withoutProject]. Рантайм при непустом результате
  /// возвращает итог `failed`.
  List<ConfigIssue> validateSnapshot() {
    final issues = <ConfigIssue>[];
    final ref = '${defaultModel.provider}/${defaultModel.id}';
    final known = providers.any(
      (p) =>
          p.config.name == defaultModel.provider &&
          p.models.containsKey(defaultModel.id),
    );
    if (!known) {
      issues.add(
        ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'agent.default_model',
          source: 'config reload',
          message: '$ref is not in the model catalog',
        ),
      );
    }
    if (withoutProject case final bare?) {
      issues.addAll(bare.validateSnapshot());
    }
    return issues;
  }

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

  /// Плоская карта листьев [withoutProject] (как `ConfigLoadResult.values`
  /// полного снимка); `null` — снимка без проекта нет.
  ///
  /// Почему здесь, а не в `ConfigLoadResult`: значения нужны перезагрузке
  /// конфигурации, чтобы сравнить второй снимок (R0-1: правка слоя, скрытая
  /// проектным слоем в полном снимке, видна только в нём), и должны ехать
  /// вместе с самим снимком через любой адаптер источника конфигурации.
  /// Заполняет `fromLayers`; потребитель — `planConfigReload`. Без значений
  /// сравнение считает карту пустой (fail closed: расхождение откладывается).
  final Map<String, Object?>? withoutProjectValues;

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
