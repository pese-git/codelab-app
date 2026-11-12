import 'package:meta/meta.dart';

import '../host/host_profile.dart';
import '../llm/decorators/retry.dart';
import '../llm/model_catalog.dart';
import '../llm/model_ref.dart';
import '../llm/provider_config.dart';
import '../mcp/mcp_server_config.dart';
import '../loop/turn_budget.dart';
import '../permissions/modes.dart';
import '../permissions/pattern.dart';
import '../permissions/policy.dart';
import '../skills/skills_config.dart';
import '../secrets/secret_names.dart';
import '../secrets/secret_template.dart';
import '../tools/agent_tool.dart' show ToolTier;
import '../util/logger.dart';
import 'config_issue.dart';
import 'config_values.dart';
import 'config_tree.dart';
import 'core_config.dart';
import 'host_settings.dart';
import 'inline_secrets.dart';
import 'interpolate.dart';
import 'key_path.dart';
import 'merge.dart';
import 'provider_binding.dart';
import 'redact_settings.dart';
import 'schema.dart';
import 'secret_name_rule.dart' show isSecretLikeName;
import 'trust.dart';
import 'validate.dart';

/// Проверка слоёв и сборка `CoreConfig` (`agent-core-architecture` §15.5,
/// шаги 3–9; design.md change `add-agent-configuration`, D3).
///
/// Почему чистая функция: файлов, разборщиков и логгера здесь нет (CFG-5,
/// PKG-1), хост передаёт готовые деревья и окружение. Исключений не бросает:
/// проблемы возвращаются списком, чтобы `config check` показал их все.
///
/// Как использовать: через `CoreConfig.fromLayers`.
ConfigLoadResult resolveConfig(
  List<ConfigTree> layers, {
  required Map<String, String> environment,
  String? projectRoot,
  bool collectAll = false,
  List<String>? pinnedTrustedProjects,
}) => _resolve(
  layers,
  environment: environment,
  projectRoot: projectRoot,
  fallbackModel: null,
  fallbackSource: DefaultModelSource.config,
  collectAll: collectAll,
  pinnedTrustedProjects: pinnedTrustedProjects,
);

/// Неявная модель уровня конфига: первая модель первого доступного провайдера
/// (design.md change `optional-default-model`, D2, D3).
///
/// Почему здесь: правило нужно и загрузке ([_Builder]), и пересчёту после
/// подстановки отложенных частей (`CoreConfig.withDeferred`, D10); одна
/// функция исключает расхождение.
///
/// «Доступный» провайдер определяется только данными загрузки, хранилище
/// секретов не читается (приоритет 1, CFG-10): у провайдера есть модель, нет
/// записи в [problems] (переменная `api_key_env` задана) и ключ не
/// [UnusableKeyRef]; ссылка на секрет считается доступной. Если доступных нет
/// (D3), берётся первый провайдер с моделями: неявная модель не строже
/// явной. Порядок — как в [providers] (порядок слияния слоёв), модели —
/// как в `providers.<id>.models`. `null` — моделей нет ни у кого (D4).
ModelRef? implicitDefaultModel(
  List<CatalogProvider> providers,
  Map<String, String> problems,
  ReasoningEffort effort,
) {
  final withModels = [
    for (final p in providers)
      if (p.models.isNotEmpty) p,
  ];
  final picked =
      withModels
          .where(
            (p) =>
                !problems.containsKey(p.config.name) &&
                p.key is! UnusableKeyRef,
          )
          .firstOrNull ??
      withModels.firstOrNull;
  if (picked == null) {
    return null;
  }
  return StaticModelCatalog(providers, logger: const _SilentLogger()).resolve(
    ModelId('${picked.config.name}/${picked.models.keys.first}'),
    effort: effort,
  );
}

/// Предупреждения без повторов (событие, ключ, источник): доверие считается и
/// по исходным слоям, и по вырезанным.
List<ConfigIssue> _mergeWarnings(
  List<ConfigIssue> first,
  List<ConfigIssue> second,
) {
  final seen = <String>{};
  return [
    for (final w in [...first, ...second])
      if (seen.add('${w.event}|${w.key}|${w.source}')) w,
  ];
}

/// Шаг 4: правила доверия к проектным слоям (D7). Вынесен, чтобы режим
/// `collectAll` мог выполнить его по ИСХОДНЫМ слоям до любого вырезания
/// (R3-3, третье ревью): отброшенные доверием ключи «блокируют всегда», и
/// никакая порча слоя не должна их скрывать.
({List<ConfigTree> effective, List<ConfigIssue> warnings}) _applyTrust(
  List<ConfigTree> layers,
  Map<String, String> environment,
  String? projectRoot,
  List<String>? pinnedTrustedProjects,
) {
  final trusted =
      projectRoot != null &&
      (pinnedTrustedProjects ?? _trustedRoots(layers, environment)).any(
        (r) => samePath(r, projectRoot),
      );
  final effective = <ConfigTree>[];
  final trustWarnings = <ConfigIssue>[];
  for (var i = 0; i < layers.length; i++) {
    final layer = layers[i];
    if (layer.kind != ConfigLayerKind.project &&
        layer.kind != ConfigLayerKind.projectLocal) {
      effective.add(layer);
      continue;
    }
    // «Нижние» слои — всё, что стоит под этим слоем и подчиняется доверию
    // раньше него: умолчания, глобальный и (для `projectLocal`) проектный.
    final outcome = applyProjectTrust(
      layer,
      lower: mergeLayers(
        effective.where(
          (l) =>
              l.kind == ConfigLayerKind.defaults ||
              l.kind == ConfigLayerKind.user ||
              l.kind == ConfigLayerKind.appStorage ||
              l.kind == ConfigLayerKind.project,
        ),
      ),
      trusted: trusted,
    );
    effective.add(outcome.layer);
    trustWarnings.addAll(outcome.warnings);
  }
  return (effective: effective, warnings: trustWarnings);
}

/// Вход для тестов: тот же `resolveConfig` в режиме `collectAll` с заданным
/// числом кругов [rounds] (ветка «проверка неполна», R3-3). Не экспортируется
/// из `codelab_agent_core.dart`; публичный API ядра не меняется.
@visibleForTesting
ConfigLoadResult resolveCollectAllForTesting(
  List<ConfigTree> layers, {
  required Map<String, String> environment,
  String? projectRoot,
  required int rounds,
}) => _resolve(
  layers,
  environment: environment,
  projectRoot: projectRoot,
  fallbackModel: null,
  fallbackSource: DefaultModelSource.config,
  collectAll: true,
  rounds: rounds,
);

/// Вход для тестов: вырезание ключей проблем [issues] из [layer]; `degraded`
/// — сработал фолбэк «весь слой».
@visibleForTesting
({ConfigTree layer, bool removed, bool degraded}) withoutKeysForTesting(
  ConfigTree layer,
  List<ConfigIssue> issues,
) => _withoutKeys(layer, issues);

/// Внутренний проход. [fallbackModel] задаётся только при сборке снимка без
/// проектных слоёв (D9): если `agent.default_model` в нём не задан или не
/// разрешается, берётся модель полного снимка, а не ошибка. Остальные
/// проблемы снимка без проекта возвращаются как проблемы загрузки (отказ):
/// иначе сессия вне корня запуска получила бы неполную конфигурацию.
ConfigLoadResult _resolve(
  List<ConfigTree> layers, {
  required Map<String, String> environment,
  required String? projectRoot,
  required ModelRef? fallbackModel,
  required DefaultModelSource fallbackSource,
  bool collectAll = false,
  int rounds = 8,
  List<String>? pinnedTrustedProjects,
}) {
  final sources = [for (final layer in layers) layer.source];

  // Проектные слои без корня проекта: доверие проверить не к чему. Это
  // ошибка программиста хоста, а не пользователя, поэтому исключение (D7).
  if (projectRoot == null &&
      layers.any(
        (l) =>
            l.kind == ConfigLayerKind.project ||
            l.kind == ConfigLayerKind.projectLocal,
      )) {
    throw ArgumentError.value(
      projectRoot,
      'projectRoot',
      'is required when project layers are passed',
    );
  }

  // Шаги 1–2: проверка каждого слоя по схеме до слияния, чтобы проблема
  // называла файл и строку слоя, который её содержит.
  final issues = <ConfigIssue>[
    for (final layer in layers) ...validateLayer(layer),
    for (final layer in layers) ..._trustedProjectsPlacement(layer),
    ..._trustedProjectsPaths(layers, environment),
  ];
  if (issues.isNotEmpty) {
    if (!collectAll) {
      return ConfigLoadResult(issues: issues, sources: sources);
    }
    // R3-1 / R3-3 (решение пользователя 2026-11-03): полный набор проблем
    // без обрыва ступеней. Ключи с ошибкой слоя исключаются (так же, как
    // сборка исключает недопустимый элемент), остальные ступени
    // выполняются, и каскад (`default_model` не в каталоге) виден. Ошибки
    // слоя идут первыми; повтор той же проблемы из следующего круга
    // отбрасывается.
    //
    // Fail-closed: если круг ничего не вырезал или число кругов исчерпано,
    // поздние ступени (правила доверия) не выполнены, и это нельзя
    // выдавать за полный набор: добавляется служебная проблема
    // [validationIncompleteEvent].
    final incompleteIssue = ConfigIssue(
      kind: ConfigIssueKind.semantic,
      key: '',
      source: issues.first.source,
      message: 'the config could not be fully checked; fix the file by hand',
      event: validationIncompleteEvent,
    );
    ConfigLoadResult incomplete() => ConfigLoadResult(
      issues: [...issues, incompleteIssue],
      sources: sources,
    );
    if (rounds <= 0) {
      return incomplete();
    }
    // Доверие по исходным слоям (до вырезания). Сбой на испорченном слое —
    // тоже неполнота (fail-closed).
    var degraded = false;
    var originalTrust = const <ConfigIssue>[];
    try {
      originalTrust = _applyTrust(
        layers,
        environment,
        projectRoot,
        pinnedTrustedProjects,
      ).warnings;
    } on Object {
      degraded = true;
    }
    var progress = false;
    final pruned = [
      for (final layer in layers)
        () {
          final cut = _withoutKeys(layer, issues);
          progress = progress || cut.removed;
          degraded = degraded || cut.degraded;
          return cut.layer;
        }(),
    ];
    if (!progress) {
      return incomplete();
    }
    final rest = _resolve(
      pruned,
      environment: environment,
      projectRoot: projectRoot,
      fallbackModel: fallbackModel,
      fallbackSource: fallbackSource,
      collectAll: true,
      rounds: rounds - 1,
      pinnedTrustedProjects: pinnedTrustedProjects,
    );
    String sig(ConfigIssue i) => '${i.kind.name}|${i.key}|${i.source}';
    final seen = {for (final i in issues) sig(i)};
    return ConfigLoadResult(
      issues: [
        ...issues,
        for (final i in rest.issues)
          if (!seen.contains(sig(i))) i,
        // Фолбэк «весь слой» отбросил больше пути проблемы, в том числе
        // ключи под правилом доверия: результат нельзя выдавать за полный.
        if (degraded &&
            !rest.issues.any((i) => i.event == validationIncompleteEvent))
          incompleteIssue,
      ],
      warnings: _mergeWarnings(originalTrust, rest.warnings),
      sources: sources,
    );
  }

  // Шаг 4: правила доверия применяются к слоям `project` и `projectLocal` до
  // слияния и сравнивают их с итогом слоёв ниже (D7).
  final applied = _applyTrust(
    layers,
    environment,
    projectRoot,
    pinnedTrustedProjects,
  );
  final effective = applied.effective;
  final trustWarnings = applied.warnings;

  final builder = _Builder(
    effective,
    environment: environment,
    fallbackModel: fallbackModel,
    fallbackSource: fallbackSource,
    warnings: trustWarnings,
    pinnedTrustedProjects: pinnedTrustedProjects,
  )..build();
  if (builder.issues.isNotEmpty) {
    return ConfigLoadResult(
      issues: builder.issues,
      warnings: builder.warnings,
      sources: sources,
    );
  }
  final full = builder.config!;

  // D9: снимок без проектных слоёв для сессий вне корня запуска. Ключи
  // сборки (провайдеры, каталог, профиль) берутся из полного снимка, а
  // `defaultModel` второго снимка при отсутствии ключа — модель полного.
  CoreConfig? bare;
  var bareValues = const <String, Object?>{};
  final hasProjectLayers = layers.any(
    (l) =>
        l.kind == ConfigLayerKind.project ||
        l.kind == ConfigLayerKind.projectLocal,
  );
  if (projectRoot != null && hasProjectLayers) {
    final second = _resolve(
      [
        for (final l in layers)
          if (l.kind != ConfigLayerKind.project &&
              l.kind != ConfigLayerKind.projectLocal)
            l,
      ],
      environment: environment,
      projectRoot: null,
      fallbackModel: full.defaultModel,
      fallbackSource: full.defaultModelSource,
      pinnedTrustedProjects: pinnedTrustedProjects,
    );
    if (second.issues.isNotEmpty) {
      return ConfigLoadResult(
        issues: second.issues,
        warnings: builder.warnings,
        sources: sources,
      );
    }
    bare = second.config;
    bareValues = second.values;
  }

  return ConfigLoadResult(
    config: projectRoot == null
        ? full
        : CoreConfig(
            defaultModel: full.defaultModel,
            defaultModelSource: full.defaultModelSource,
            permissions: full.permissions,
            budget: full.budget,
            compaction: full.compaction,
            effort: full.effort,
            mcpServers: full.mcpServers,
            providers: full.providers,
            providerProblems: full.providerProblems,
            redact: full.redact,
            projectContextMaxBytes: full.projectContextMaxBytes,
            skills: full.skills,
            trustedProjects: full.trustedProjects,
            projectRoot: projectRoot,
            withoutProject: bare,
            // R0-1: значения второго снимка для сравнения при перезагрузке.
            withoutProjectValues: bare == null ? null : bareValues,
          ),
    host: builder.host,
    warnings: builder.warnings,
    sources: sources,
    values: builder.values,
  );
}

/// Корни из `trusted_projects` глобального слоя (§15.3), `~` раскрыт.
List<String> _trustedRoots(
  List<ConfigTree> layers,
  Map<String, String> environment,
) {
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  return [
    for (final layer in layers)
      if (layer.kind == ConfigLayerKind.user ||
          layer.kind == ConfigLayerKind.appStorage)
        if (layer.values['trusted_projects'] case final List<Object?> roots)
          for (final root in roots.cast<String>())
            if (home != null && (root == '~' || root.startsWith('~/')))
              '$home${root.substring(1)}'
            else
              root,
  ];
}

/// `trusted_projects` читается только из глобального слоя (§15.3).
List<ConfigIssue> _trustedProjectsPlacement(ConfigTree layer) {
  // В проектных слоях ключ отбрасывается с предупреждением, а не ошибкой
  // загрузки: репозиторий не должен ломать запуск (CFG-3).
  if (layer.kind == ConfigLayerKind.user ||
      layer.kind == ConfigLayerKind.appStorage ||
      layer.kind == ConfigLayerKind.project ||
      layer.kind == ConfigLayerKind.projectLocal ||
      !layer.values.containsKey('trusted_projects')) {
    return const [];
  }
  final position = layer.positions['trusted_projects'];
  return [
    ConfigIssue(
      kind: ConfigIssueKind.value,
      key: 'trusted_projects',
      source: layer.source,
      line: position?.line,
      column: position?.column,
      message: 'trusted_projects is read only from the global config',
    ),
  ];
}

/// Корни `trusted_projects` — только абсолютные пути (после раскрытия `~`):
/// относительный путь зависел бы от `cwd` процесса и мог бы «довериться»
/// чужому каталогу.
List<ConfigIssue> _trustedProjectsPaths(
  List<ConfigTree> layers,
  Map<String, String> environment,
) {
  final home = environment['HOME'] ?? environment['USERPROFILE'];
  final out = <ConfigIssue>[];
  for (final layer in layers) {
    if (layer.kind != ConfigLayerKind.user &&
        layer.kind != ConfigLayerKind.appStorage) {
      continue;
    }
    final roots = layer.values['trusted_projects'];
    if (roots is! List<Object?>) {
      continue;
    }
    for (var i = 0; i < roots.length; i++) {
      final root = roots[i];
      if (root is! String) {
        continue;
      }
      final expanded = home != null && (root == '~' || root.startsWith('~/'))
          ? '$home${root.substring(1)}'
          : root;
      if (!isAbsolutePath(expanded)) {
        final key = KeyPath('trusted_projects').at(i).value;
        final position = layer.positions[key];
        out.add(
          ConfigIssue(
            kind: ConfigIssueKind.value,
            key: key,
            source: layer.source,
            line: position?.line,
            column: position?.column,
            message: 'expected an absolute path',
          ),
        );
      }
    }
  }
  return out;
}

final _envName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Печатаемый ASCII (`0x20..0x7e`): значение ключа уходит в заголовок HTTP.
bool _printableAscii(String text) =>
    text.codeUnits.every((c) => c >= 0x20 && c <= 0x7e);

final class _SilentLogger implements Logger {
  const _SilentLogger();

  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}

/// Сборка значений из слитого дерева; копит проблемы и предупреждения.
final class _Builder {
  _Builder(
    this.sourceLayers, {
    required this.environment,
    required this.fallbackModel,
    required this.fallbackSource,
    List<ConfigIssue> warnings = const [],
    this.pinnedTrustedProjects,
  }) : layers = applyProviderGroupRule(sourceLayers),
       warnings = [...warnings];

  /// Слои после доверия, как их разобрал хост: по ним идут предупреждения о
  /// ключах без потребителя и о секретах в файлах, чтобы вытесненные правилом
  /// группы поля не скрыли находку.
  final List<ConfigTree> sourceLayers;

  /// Слои после правила группы провайдера (D23, правило 2): по ним строятся
  /// слияние и происхождение полей.
  final List<ConfigTree> layers;

  /// Привязки ссылок глобальных слоёв к origin (условие (b) D23). Строится по
  /// [sourceLayers]: после правила группы группа пользователя с тем же id уже
  /// вытеснена, и связка «ссылка — адрес» потерялась бы (C5.1).
  late final ProviderKeyBinding _keyBinding = ProviderKeyBinding.fromLayers(
    sourceLayers,
    environment,
  );
  final Map<String, String> environment;
  final ModelRef? fallbackModel;

  /// Источник [fallbackModel] в полном снимке (D1 `optional-default-model`).
  final DefaultModelSource fallbackSource;

  /// Закреплённый список доверия (`CoreConfig.fromLayers`); `null` — доверие
  /// по пользовательскому слою.
  final List<String>? pinnedTrustedProjects;

  final issues = <ConfigIssue>[];
  final List<ConfigIssue> warnings;

  late Map<String, Object?> merged;
  CoreConfig? config;
  HostSettings? host;

  /// Плоская карта листьев итогового дерева (`ConfigLoadResult.values`).
  Map<String, Object?> values = const {};

  void build() {
    for (final layer in sourceLayers) {
      for (final path in collectNotApplied(layer)) {
        _notApplied(path, layer);
      }
    }
    _warnSecretsInFiles();
    merged = mergeLayers(layers);

    final problems = <String, String>{};
    final providers = _providers(problems);
    final effort = _effort();
    final picked = _defaultModel(providers, problems, effort);
    final model = picked?.$1;
    final permissions = _permissions();
    final budget = _budget();
    final compaction = _compaction();
    final mcpServers = _mcpServers();
    final redact = _redact();
    final profiles = _profiles();
    final projectContextMaxBytes = _projectContextMaxBytes();
    final skills = _skills();
    final secretsBackend = _secretsBackend();
    final configWatch = _bool(['config', 'watch']);
    final configPollInterval = _configPollInterval();

    if (issues.isNotEmpty || model == null) {
      return;
    }
    config = CoreConfig(
      defaultModel: model,
      defaultModelSource: picked!.$2,
      permissions: permissions,
      budget: budget,
      compaction: compaction,
      effort: effort,
      mcpServers: mcpServers,
      providers: providers,
      providerProblems: problems,
      redact: redact,
      projectContextMaxBytes: projectContextMaxBytes,
      skills: skills,
      trustedProjects:
          pinnedTrustedProjects ?? _trustedRoots(layers, environment),
    );
    values = flattenConfigValues(merged, {
      for (final server in mcpServers) server.name,
    });
    host = HostSettings(
      sessionsDir: _path(['sessions', 'dir']),
      fsync: _str(['sessions', 'fsync']),
      logLevel: switch (_str(['logging', 'level'])) {
        final String name => LogLevel.values.byName(name),
        null => null,
      },
      logFile: _path(['logging', 'file']),
      secretsBackend: secretsBackend,
      profileNarrowing: profiles,
      configWatch: configWatch,
      configPollInterval: configPollInterval,
    );
  }

  // ---- чтение слитого дерева ----------------------------------------------

  Object? _raw(List<String> segments) {
    Object? current = merged;
    for (final segment in segments) {
      if (current is Map<String, Object?>) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  String? _str(List<String> s) => _raw(s) as String?;
  int? _int(List<String> s) => _raw(s) as int?;
  double? _num(List<String> s) => (_raw(s) as num?)?.toDouble();
  bool? _bool(List<String> s) => _raw(s) as bool?;
  Duration? _dur(List<String> s) => switch (_raw(s)) {
    final String text => parseConfigDuration(text),
    _ => null,
  };
  Map<String, Object?>? _map(List<String> s) =>
      _raw(s) as Map<String, Object?>?;

  String? _path(List<String> s) {
    final value = _str(s);
    return value == null ? null : _expandHome(value);
  }

  String _expandHome(String path) {
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    if (home != null && (path == '~' || path.startsWith('~/'))) {
      return '$home${path.substring(1)}';
    }
    return path;
  }

  // ---- проблемы -----------------------------------------------------------

  KeyPath _kp(List<String> segments) {
    var path = KeyPath.root;
    for (final segment in segments) {
      path = path.child(segment);
    }
    return path;
  }

  /// Слой, который задал итоговое значение ключа: проблема называет его файл
  /// и строку.
  ConfigTree _origin(List<String> segments) {
    for (final layer in layers.reversed) {
      Object? current = layer.values;
      var found = true;
      for (final segment in segments) {
        if (current is Map<String, Object?> && current.containsKey(segment)) {
          current = current[segment];
        } else {
          found = false;
          break;
        }
      }
      if (found) {
        return layer;
      }
    }
    return layers.isEmpty ? const ConfigTree.defaults() : layers.last;
  }

  void _issue(
    ConfigIssueKind kind,
    KeyPath path,
    String message, {
    ConfigTree? origin,
    List<String>? segments,
    String? event,
    Map<String, Object?> fields = const {},
  }) {
    final layer = origin ?? _origin(segments ?? const []);
    final position = layer.positions[path.value];
    issues.add(
      ConfigIssue(
        kind: kind,
        key: path.value,
        source: layer.source,
        line: position?.line,
        column: position?.column,
        message: message,
        event: event,
        fields: fields,
      ),
    );
  }

  /// Проблема по сегментам ключа слитого дерева.
  void _bad(
    List<String> segments,
    String message, {
    ConfigIssueKind kind = ConfigIssueKind.semantic,
    String? event,
  }) => _issue(kind, _kp(segments), message, segments: segments, event: event);

  void _warn(
    String event,
    String key,
    ConfigTree layer,
    String message, {
    Map<String, Object?> fields = const {},
    LogLevel level = LogLevel.warning,
  }) {
    final position = layer.positions[key];
    warnings.add(
      ConfigIssue(
        kind: ConfigIssueKind.semantic,
        key: key,
        source: layer.source,
        line: position?.line,
        column: position?.column,
        message: message,
        event: event,
        fields: fields,
        level: level,
      ),
    );
  }

  /// Предупреждение `config.secret.in_file` на каждую находку CFG-9 (пп. 1–3)
  /// в файловых слоях (design.md change `add-config-literal-secrets-and-migrate`,
  /// D4, R8-4).
  ///
  /// Почему по слоям `effective`, а не по исходным: правило доверия §15.3 уже
  /// убрало из недоверенного проекта `providers` и `mcp.servers`, поэтому
  /// предупреждения для чужих секретов нет — достаточно `untrusted_key`.
  /// Находки считаются по слою независимо от `enabled` сервера: откат
  /// предупреждений выключенных серверов (`_mcpServer`) их не снимает, потому
  /// что они рождаются здесь, до построения серверов.
  ///
  /// Команда в тексте зависит от слоя: `secret migrate` переносит только
  /// `user`, `project` и `projectLocal`; файл `CODELAB_CONFIG`/`--config` он
  /// не пишет (D7), и совет «migrate» там был бы тупиком. Окружение, флаги и
  /// хранилище приложения — не файлы, для них предупреждения нет. Литеральный
  /// `api_key` в `appStorage` возможен только если хост приложения положил его
  /// туда сам: писатель и клиенты секрет значением не пишут (CFG-2, D5), а
  /// переносить в хранилище секретов там нечего.
  void _warnSecretsInFiles() {
    for (final layer in sourceLayers) {
      final String Function(InlineSecretFinding) command;
      switch (layer.kind) {
        case ConfigLayerKind.user:
          command = (_) => 'codelab secret migrate';
        case ConfigLayerKind.project:
          command = (_) => 'codelab secret migrate --project';
        case ConfigLayerKind.projectLocal:
          command = (_) => 'codelab secret migrate --local';
        case ConfigLayerKind.extra:
          command = (f) => 'codelab secret set ${f.suggestedSecretName}';
        case ConfigLayerKind.defaults ||
            ConfigLayerKind.environment ||
            ConfigLayerKind.flags ||
            ConfigLayerKind.appStorage:
          continue;
      }
      for (final finding in findInlineSecrets(layer)) {
        _warn(
          secretInFileEvent,
          finding.keyPath,
          layer,
          'a secret is stored in the config file; move it to the secret '
          'store: ${command(finding)}',
          fields: {'key': finding.keyPath, 'source': layer.source},
        );
      }
    }
  }

  void _notApplied(String key, ConfigTree layer) {
    // Одно предупреждение на ключ за загрузку; источник — слой с последним
    // словом (D6).
    final existing = warnings.indexWhere(
      (w) => w.event == 'config.key.not_applied' && w.key == key,
    );
    if (existing >= 0) {
      warnings.removeAt(existing);
    }
    _warn(
      'config.key.not_applied',
      key,
      layer,
      'this key is read but not applied by this version of the agent',
      fields: {'key': key, 'source': layer.source},
    );
  }

  /// `config.poll_interval`: `1s..60s` (D7, agent-configuration «Ключи
  /// config.watch и config.poll_interval»).
  Duration? _configPollInterval() {
    final value = _dur(['config', 'poll_interval']);
    if (value == null) {
      return null;
    }
    if (value < const Duration(seconds: 1) ||
        value > const Duration(seconds: 60)) {
      _bad(
        ['config', 'poll_interval'],
        'must be between 1s and 60s',
        kind: ConfigIssueKind.value,
      );
      return null;
    }
    return value;
  }

  /// `secrets.backend` (D7): `auto` | `env` | `file`. `keychain` в схеме
  /// остаётся, чтобы будущий change хранилищ ОС не менял её, но пока даёт
  /// проблему конфигурации; текст `expected one of: …` задан спецификацией
  /// agent-secrets «Выбор бэкенда secrets.backend».
  String? _secretsBackend() {
    final value = _str(['secrets', 'backend']);
    if (value == null) {
      return null;
    }
    switch (value) {
      case 'auto' || 'env' || 'file':
        return value;
      case 'keychain':
        _bad(
          ['secrets', 'backend'],
          'keychain is not supported yet (supported: auto, env, file)',
          kind: ConfigIssueKind.value,
        );
      default:
        _bad(
          ['secrets', 'backend'],
          'expected one of: auto, keychain, env, file',
          kind: ConfigIssueKind.value,
        );
    }
    return null;
  }

  // ---- провайдеры ---------------------------------------------------------

  List<CatalogProvider> _providers(Map<String, String> problems) {
    final out = <CatalogProvider>[];
    final map = _map(['providers']);
    if (map == null) {
      return out;
    }
    for (final id in map.keys) {
      final provider = _provider(id, problems);
      if (provider != null) {
        out.add(provider);
      }
    }
    return out;
  }

  CatalogProvider? _provider(String id, Map<String, String> problems) {
    final at = ['providers', id];
    final kind = _str([...at, 'kind']);
    if (kind == null) {
      _bad(
        [...at, 'kind'],
        'required (known: ${providerKinds.join(', ')})',
        kind: ConfigIssueKind.value,
      );
      return null;
    }
    final api = switch (kind) {
      'anthropic' => ProviderApi.anthropicMessages,
      'gemini' => ProviderApi.gemini,
      _ => ProviderApi.openaiChat,
    };
    // D23: ссылки проектного слоя, не привязанные к адресу, не раскрываются и
    // не читаются; провайдер остаётся в каталоге, ход с ним отвечает ошибкой.
    final unbound = _unboundReferences(id, at, kind);
    final unboundFields = {for (final ref in unbound.references) ref.field};
    final rawBase = _str([...at, 'base_url']);
    final String? base;
    if (rawBase != null && unboundFields.contains('base_url')) {
      // Адрес с непривязанной `${ENV}` нигде не используется (запрос не
      // уходит), но `ProviderConfig` требует разобранный `Uri`: ссылки
      // убираются, значение переменной в строку не попадает.
      base = rawBase.replaceAll(RegExp(r'\$\{[^}]*\}'), '');
    } else if (rawBase != null) {
      base = _interpolate(
        rawBase,
        _kp([...at, 'base_url']),
        _origin([...at, 'base_url']),
        allowSecrets: false,
      )?.text;
      if (base == null) {
        return null;
      }
    } else {
      base = switch (kind) {
        'anthropic' => 'https://api.anthropic.com',
        'gemini' => 'https://generativelanguage.googleapis.com',
        _ => null,
      };
    }
    if (base == null) {
      _bad([...at, 'base_url'], 'required for openai-compatible providers');
      return null;
    }
    var baseUrl = Uri.tryParse(base);
    if (unboundFields.contains('base_url') &&
        (baseUrl == null ||
            !(baseUrl.isScheme('http') || baseUrl.isScheme('https')) ||
            baseUrl.host.isEmpty)) {
      baseUrl = Uri.parse('https://unbound.invalid');
    }
    if (baseUrl == null ||
        !(baseUrl.isScheme('http') || baseUrl.isScheme('https')) ||
        baseUrl.host.isEmpty) {
      _bad(
        [...at, 'base_url'],
        'expected an http or https URL',
        kind: ConfigIssueKind.value,
      );
      return null;
    }

    final idle = _dur([...at, 'idle_timeout']);
    final idleReasoning = _dur([...at, 'idle_timeout_reasoning']);
    final effectiveIdle = idle ?? LlmTimeouts.defaults.idle;
    final effectiveReasoning =
        idleReasoning ?? LlmTimeouts.defaults.idleReasoning;
    if (effectiveReasoning < effectiveIdle) {
      _bad([
        ...at,
        if (idleReasoning != null) 'idle_timeout_reasoning' else 'idle_timeout',
      ], 'idle_timeout_reasoning must not be shorter than idle_timeout');
      return null;
    }

    final transient = _int([...at, 'transient_retries']);
    final rateLimit = _int([...at, 'rate_limit_retries']);
    for (final (key, value) in [
      ('transient_retries', transient),
      ('rate_limit_retries', rateLimit),
    ]) {
      if (value != null && value < 0) {
        _bad([...at, key], 'must be 0 or greater');
      }
    }
    const defaultRetry = RetryPolicy();

    // Заголовки: `${ENV}` раскрывается сразу, значение со ссылкой
    // `${secret:…}` остаётся шаблоном до первого запроса к провайдеру (D4).
    final headers = <String, String>{};
    final headerTemplates = <String, SecretTemplate>{};
    final rawHeaders = _map([...at, 'headers']) ?? const {};
    for (final MapEntry(key: name, value: value) in rawHeaders.entries) {
      if (unboundFields.contains('headers.$name')) {
        continue;
      }
      final path = _kp([...at, 'headers', name]);
      final expanded = _interpolate(
        value! as String,
        path,
        _origin([...at, 'headers', name]),
      );
      if (expanded == null) {
        continue;
      }
      // Литерал секретного заголовка с управляющим или не-ASCII символом
      // `package:http` отвергает с текстом, цитирующим значение; поэтому
      // отказ при загрузке, без значения.
      if (expanded.secrets.isEmpty &&
          isSecretLikeName(name) &&
          !_printableAscii(expanded.text)) {
        _issue(
          ConfigIssueKind.value,
          path,
          '$name must be printable ASCII',
          origin: _origin([...at, 'headers', name]),
        );
        continue;
      }
      if (expanded.secrets.isNotEmpty) {
        headerTemplates[name] = expanded.template;
      } else {
        headers[name] = expanded.text;
      }
    }

    final keyEnv = unboundFields.contains('api_key_env')
        ? null
        : _str([...at, 'api_key_env']);
    final keySecret = unboundFields.contains('api_key_secret')
        ? null
        : _str([...at, 'api_key_secret']);
    final rawApiKey = switch (_str([...at, 'api_key'])) {
      _ when unboundFields.contains('api_key') => null,
      final String text when text.isNotEmpty => text,
      _ => null,
    };
    // R8-6: `api_key` — ещё один источник ключа. Проверка идёт по слитому
    // дереву, поэтому `api_key` пользователя и `api_key_secret` доверенного
    // проекта тоже дают конфликт. Это не «секрет в файле», а неоднозначность:
    // агент не стартует, пока источник не один. Ссылка `${VAR}`/`${secret:x}`
    // (R8-8) — тоже источник.
    if (rawApiKey != null && (keyEnv != null || keySecret != null)) {
      _bad(
        [...at, 'api_key'],
        providerKeySourcesConflictMessage,
        kind: ConfigIssueKind.value,
      );
      return null;
    }
    // Значение, совпавшее с шаблоном секрета, вписано вместо имени (CFG-9,
    // пункт 3): формат имени не проверяется, чтобы значение не попало в
    // проблему, `providerProblems` или `variable` предупреждения. Загрузка
    // кладёт маркер [UnusableKeyRef], а не ссылку (D4).
    final envIsSecret =
        keyEnv != null && literalSecretTag(keyEnv, asName: true) != null;
    final secretIsSecret =
        keySecret != null && literalSecretTag(keySecret, asName: true) != null;
    if (keyEnv != null && !envIsSecret && !_envName.hasMatch(keyEnv)) {
      _bad(
        [...at, 'api_key_env'],
        'expected an environment variable name',
        kind: ConfigIssueKind.value,
      );
      return null;
    }
    if (keySecret != null &&
        !secretIsSecret &&
        SecretNames.problem(keySecret) != null) {
      _bad(
        [...at, 'api_key_secret'],
        SecretNames.problem(keySecret)!,
        kind: ConfigIssueKind.value,
      );
      return null;
    }
    // Значение ключа загрузка не читает (D4): провайдер хранит ссылку, а
    // `createRoutedStreamFunction` разрешает её при первом запросе через
    // `SecretResolver`. Незаданная переменная остаётся быстрым отказом
    // (сценарий «Переменная ключа не задана»): окружение процесса не
    // меняется, поэтому ответ при запросе был бы тем же.
    ProviderKeyRef? key;
    if (keyEnv != null && keySecret != null) {
      _bad(
        [...at, 'api_key_secret'],
        'api_key_env and api_key_secret are mutually exclusive',
        kind: ConfigIssueKind.value,
      );
      return null;
    } else if (envIsSecret) {
      key = UnusableKeyRef(_kp([...at, 'api_key_env']).value);
    } else if (secretIsSecret) {
      key = UnusableKeyRef(_kp([...at, 'api_key_secret']).value);
    } else if (keyEnv != null) {
      key = EnvKeyRef(keyEnv);
      final value = environment[keyEnv];
      if (value == null || value.isEmpty) {
        problems[id] = 'API key variable $keyEnv is not set';
        _warn(
          'config.provider.key_missing',
          _kp([...at, 'api_key_env']).value,
          _origin([...at, 'api_key_env']),
          'the environment variable with the API key is not set',
          fields: {'provider': id, 'variable': keyEnv},
        );
      }
    } else if (keySecret != null) {
      key = SecretKeyRef(keySecret);
    }

    // `api_key`: литерал работает как есть (R8-4), ссылка раскрывается как в
    // заголовках (R8-8, решение пользователя 2026-11-04): `${VAR}` — значение
    // переменной, `${secret:x}` целиком — ссылка на секрет.
    String? keyLiteral;
    var keyIsLiteral = false;
    if (rawApiKey != null) {
      final keyPath = _kp([...at, 'api_key']);
      final expanded = _interpolate(
        rawApiKey,
        keyPath,
        _origin([...at, 'api_key']),
      );
      if (expanded == null) {
        return null;
      }
      if (expanded.secrets.isEmpty) {
        if (!_printableAscii(expanded.text)) {
          _bad(
            [...at, 'api_key'],
            'api_key must be printable ASCII',
            kind: ConfigIssueKind.value,
          );
          return null;
        }
        keyLiteral = expanded.text;
        keyIsLiteral = !rawApiKey.contains(r'${');
      } else {
        switch (expanded.template.parts) {
          case [SecretReference(:final name)]:
            key = SecretKeyRef(name);
          case [UnusableSecretReference()]:
            key = UnusableKeyRef(keyPath.value);
          default:
            _bad(
              [...at, 'api_key'],
              r'api_key may use ${secret:…} only as the whole value',
              kind: ConfigIssueKind.value,
            );
            return null;
        }
      }
    }

    final provider = ProviderConfig(
      name: id,
      api: api,
      baseUrl: baseUrl,
      // Литеральный ключ файла работает как есть, без резолвера (D4, R8-4).
      apiKey: keyLiteral,
      literalApiKey: keyIsLiteral,
      headers: headers,
      authHeader: _str([...at, 'auth_header']),
      reasoningFormat: switch (_str([...at, 'reasoning_format'])) {
        'openrouter' => ReasoningFormat.openrouter,
        'none' => ReasoningFormat.none,
        'openai' => ReasoningFormat.openai,
        _ => null,
      },
      promptCacheKey: _bool([...at, 'prompt_cache_key']),
      timeouts: LlmTimeouts(
        connect:
            _dur([...at, 'connect_timeout']) ?? LlmTimeouts.defaults.connect,
        idle: effectiveIdle,
        idleReasoning: effectiveReasoning,
      ),
      retry: RetryPolicy(
        maxAttempts: transient == null
            ? defaultRetry.maxAttempts
            : transient + 1,
        rateLimitRetries: rateLimit ?? defaultRetry.rateLimitRetries,
      ),
    );

    if (unbound.references.isNotEmpty) {
      _reportUnbound(id, at, unbound, problems);
    }

    final models = <String, ModelInfo>{};
    final declared = _map([...at, 'models']) ?? const {};
    for (final model in declared.keys) {
      final info = _modelInfo([...at, 'models', model]);
      if (info != null) {
        models[model] = info;
      }
    }
    return CatalogProvider(
      provider,
      models: models,
      key: key,
      headerTemplates: headerTemplates,
    );
  }

  /// Ссылки группы провайдера [id] из проектного слоя `config.yaml`, которые
  /// нельзя раскрывать (D23, правило 3).
  ///
  /// Группа к этому моменту целиком из одного слоя (правило 2). Слой
  /// `projectLocal` доверенного проекта — условие (a): ссылки разрешены.
  /// Слой `project` — только условие (b): глобальные слои связывают ту же
  /// ссылку с тем же origin. Глобальный слой не проверяется.
  ({ConfigTree? layer, List<ProviderReference> references}) _unboundReferences(
    String id,
    List<String> at,
    String kind,
  ) {
    for (final layer in layers.reversed) {
      final entry = providerEntry(layer, id);
      if (entry == null || !providerGroupKeys.any(entry.containsKey)) {
        continue;
      }
      if (layer.kind != ConfigLayerKind.project) {
        break;
      }
      // Адрес — итоговый: поля адреса, которых слой не задал, пришли из
      // непроектных слоёв ниже (Q21 (a)), поэтому берутся из слитого дерева.
      final origin = providerOrigin(
        {
          'base_url': _str([...at, 'base_url']),
        },
        kind,
        environment,
      );
      return (
        layer: layer,
        references: [
          for (final ref in providerReferences(entry))
            if (!_keyBinding.isBound(ref, origin)) ref,
        ],
      );
    }
    return (layer: null, references: const []);
  }

  /// Запись в `providerProblems` и предупреждения `config.provider.key_unbound`
  /// для непривязанных ссылок. Ни имя значения, ни само значение, ни адрес
  /// проекта в текст не входят: только слой, id провайдера и имя ссылки
  /// (design.md `require-project-folder`, D23, правило 4).
  void _reportUnbound(
    String id,
    List<String> at,
    ({ConfigTree? layer, List<ProviderReference> references}) unbound,
    Map<String, String> problems,
  ) {
    final layer = unbound.layer!;
    final first = unbound.references.first;
    final shown = literalSecretTag(first.name, asName: true) != null
        ? 'a reference'
        : switch (first.kind) {
            ProviderReferenceKind.secret => 'secret ${first.name}',
            ProviderReferenceKind.env => 'variable ${first.name}',
          };
    problems[id] =
        'Provider $id from ${layer.source} cannot use $shown: the key is '
        'bound to another address. Move the provider to config.local.yaml or '
        'to the user config.';
    for (final ref in unbound.references) {
      final segments = ref.field.startsWith('headers.')
          ? [...at, 'headers', ref.field.substring('headers.'.length)]
          : [...at, ref.field];
      _warn(
        'config.provider.key_unbound',
        _kp(segments).value,
        layer,
        'the key reference is bound to another address and is not used',
        fields: {
          'provider': id,
          'source': layer.source,
          'reference_kind': ref.kind.name,
        },
      );
    }
  }

  ModelInfo? _modelInfo(List<String> at) {
    for (final key in const ['context_window', 'max_output_tokens']) {
      final value = _int([...at, key]);
      if (value != null && value < 1) {
        _bad([...at, key], 'must be greater than 0');
        return null;
      }
    }
    final input = _num([...at, 'cost_input']);
    final output = _num([...at, 'cost_output']);
    final read = _num([...at, 'cost_cache_read']);
    final write = _num([...at, 'cost_cache_write']);
    ModelCost? cost;
    if ((input == null) != (output == null) ||
        (input == null && (read != null || write != null))) {
      _bad([
        ...at,
        input == null ? 'cost_input' : 'cost_output',
      ], 'cost_input and cost_output must be set together');
      return null;
    }
    if (input != null && output != null) {
      cost = ModelCost(
        input: input,
        output: output,
        cacheRead: read ?? 0,
        cacheWrite: write ?? 0,
      );
    }
    return ModelInfo(
      displayName: _str([...at, 'name']),
      contextWindow: _int([...at, 'context_window']),
      maxOutputTokens: _int([...at, 'max_output_tokens']),
      cost: cost,
      supportsImages: _bool([...at, 'image']),
      supportsReasoning: _bool([...at, 'reasoning']),
      hiddenReasoning: _bool([...at, 'hidden_reasoning']),
      thinkingMode: switch (_str([...at, 'thinking_mode'])) {
        'adaptive' => ThinkingMode.adaptive,
        'budget' => ThinkingMode.budget,
        _ => null,
      },
    );
  }

  // ---- подстановка ${ENV} -------------------------------------------------

  /// Раскрывает `${NAME}` в значении разрешённого ключа (§15.5). Незаданная
  /// переменная — проблема с путём ключа и именем переменной (значение не
  /// попадает в текст), результат — `null`.
  ///
  /// Ссылки `${secret:<name>}` не читаются: имя проверяет `SecretNames`
  /// (текст проблемы называет правило, а не имя), а значение остаётся
  /// шаблоном `template` (D4). [allowSecrets] `false` — ключ, где ссылка на
  /// секрет недопустима (argv, URL): это проблема, а не молчаливый литерал.
  ({String text, List<String> secrets, SecretTemplate template})? _interpolate(
    String raw,
    KeyPath path,
    ConfigTree origin, {
    bool allowSecrets = true,
  }) {
    final expansion = expandEnvironment(raw, environment);
    if (expansion.missing.isNotEmpty) {
      for (final name in expansion.missing.toSet()) {
        _issue(
          ConfigIssueKind.value,
          path,
          'variable $name is not set',
          origin: origin,
          // Писатель конфига превращает такую проблему в предупреждение
          // (§17.5.5, шаг 6) по признаку, а не по тексту (R3, D5).
          event: unsetVariableEvent,
          fields: {'variable': name},
        );
      }
      return null;
    }
    if (expansion.secretRefs.isNotEmpty && !allowSecrets) {
      _issue(
        ConfigIssueKind.value,
        path,
        r'secret references ${secret:…} are allowed only in env and headers '
        'values',
        origin: origin,
      );
      return null;
    }
    // В скобки вписан сам секрет вместо имени (CFG-9, пункт 3): формат имени
    // не проверяется (значение не должно попасть в проблему), а в шаблон
    // вместо ссылки кладётся маркер, который никто не разрешает (D4).
    // Список `secrets` остаётся прежним: непустой список — признак шаблона,
    // иначе значение `${secret:<токен>}` ушло бы строкой как литерал.
    final unusable = {
      for (final name in expansion.secretRefs)
        if (literalSecretTag(name, asName: true) != null) name,
    };
    for (final name in expansion.secretRefs) {
      if (unusable.contains(name)) {
        continue;
      }
      if (SecretNames.problem(name) case final problem?) {
        _issue(ConfigIssueKind.value, path, problem, origin: origin);
        return null;
      }
    }
    return (
      text: expansion.text,
      secrets: expansion.secretRefs,
      template: unusable.isEmpty
          ? expansion.template
          : SecretTemplate([
              for (final part in expansion.template.parts)
                if (part case SecretReference(
                  :final name,
                ) when unusable.contains(name))
                  const UnusableSecretReference()
                else
                  part,
            ]),
    );
  }

  // ---- MCP-серверы конфигурации (D10) -------------------------------------

  List<McpServerConfig> _mcpServers() {
    final out = <McpServerConfig>[];
    final list = _raw(['mcp', 'servers']);
    if (list is! List) {
      return out;
    }
    for (final item in list) {
      final server = _mcpServer(item! as Map<String, Object?>);
      if (server != null) {
        out.add(server);
      }
    }
    return out;
  }

  /// Слой, объявивший сервер последним: слои заменяют сервер целиком.
  ConfigTree _serverOrigin(String name) {
    for (final layer in layers.reversed) {
      final servers =
          (layer.values['mcp'] as Map<String, Object?>?)?['servers'];
      if (servers is List &&
          servers.any((s) => s is Map<String, Object?> && s['name'] == name)) {
        return layer;
      }
    }
    return layers.isEmpty ? const ConfigTree.defaults() : layers.last;
  }

  McpServerConfig? _mcpServer(Map<String, Object?> raw) {
    final name = raw['name']! as String;
    final at = KeyPath('mcp.servers').at(name);
    final origin = _serverOrigin(name);
    if (raw['enabled'] != false) {
      return _buildMcpServer(raw, name, at, origin, enabled: true);
    }
    _warn(
      'mcp.server.skipped',
      at.value,
      origin,
      'the server is disabled in the config',
      fields: {'server': name, 'reason': 'disabled in config'},
      level: LogLevel.info,
    );
    // Выключенный сервер доходит до коннектора с `enabled == false`, чтобы
    // `/mcp list` его показывал, а `/mcp enable` мог подключить (D10, D11).
    // Но проверять его строже, чем раньше, нельзя: конфиг с неполным или
    // «сломанным» выключенным сервером был валиден и остаётся валидным. Поэтому
    // сервер строится «тихо»: проблемы и предупреждения построения
    // откатываются, а элемент, который не из чего собрать (`{name,
    // enabled: false}` в проектном слое поверх сервера пользователя), как и
    // прежде, выпадает из списка.
    final issuesMark = issues.length;
    final warningsMark = warnings.length;
    final server = _buildMcpServer(raw, name, at, origin, enabled: false);
    issues.removeRange(issuesMark, issues.length);
    warnings.removeRange(warningsMark, warnings.length);
    return server;
  }

  McpServerConfig? _buildMcpServer(
    Map<String, Object?> raw,
    String name,
    KeyPath at,
    ConfigTree origin, {
    required bool enabled,
  }) {
    void bad(String field, String message) =>
        _issue(ConfigIssueKind.value, at.child(field), message, origin: origin);

    final type = raw['type'];
    if (type == null) {
      bad('type', 'required (stdio or http)');
      return null;
    }
    if (type != 'stdio' && type != 'http') {
      bad('type', 'only stdio and http are supported');
      return null;
    }

    // Привязка ссылок HTTP-сервера проектного слоя к адресу (change
    // `bind-mcp-secrets-to-origin`, D1, D4, D8): вердикт выносится до
    // `_interpolate` и `expand`, поэтому значение непривязанной ссылки не
    // читается ни из окружения, ни из хранилища и в объект не попадает.
    final unbound = type == 'http'
        ? _unboundMcpReferences(raw, origin)
        : const <ProviderReference>[];
    final unboundFields = {for (final ref in unbound) ref.field};
    final blockedReason = unbound.isEmpty ? null : _mcpBlockedReason(unbound);

    final connect = raw['connect_timeout'] is String
        ? parseConfigDuration(raw['connect_timeout']! as String)
        : null;
    final call = raw['call_timeout'] is String
        ? parseConfigDuration(raw['call_timeout']! as String)
        : null;
    if (connect != null && connect <= Duration.zero) {
      bad('connect_timeout', 'must be greater than 0');
      return null;
    }
    if (call != null &&
        (call < const Duration(seconds: 1) ||
            call > const Duration(hours: 24))) {
      bad('call_timeout', 'must be between 1s and 24h');
      return null;
    }

    // Значение после подстановки — возможный секрет. Ссылки `${secret:…}`
    // допустимы только в `env` и `headers`: они остаются шаблонами в
    // `secretValues` и раскрываются рантаймом перед `connect` (D4). В `args`
    // и `url` ссылка недопустима: argv и URL видны в списке процессов и
    // логах.
    var failed = false;
    String? expand(String value, KeyPath path) {
      final result = _interpolate(value, path, origin, allowSecrets: false);
      if (result == null) {
        failed = true;
        return null;
      }
      return result.text;
    }

    final secretValues = <String, SecretTemplate>{};
    // Значение `env`/`headers`: строка или шаблон (тогда в [secretValues]).
    String? expandValue(String value, KeyPath path, String templateKey) {
      final result = _interpolate(value, path, origin);
      if (result == null) {
        failed = true;
        return null;
      }
      if (result.secrets.isEmpty) {
        return result.text;
      }
      secretValues[templateKey] = result.template;
      return null;
    }

    McpServerConfig? server;
    if (type == 'stdio') {
      final command = raw['command'];
      if (command is! String || command.isEmpty) {
        bad('command', 'required for stdio servers');
        return null;
      }
      final args = <String>[];
      final rawArgs = raw['args'] as List<Object?>? ?? const [];
      for (var i = 0; i < rawArgs.length; i++) {
        args.add(expand(rawArgs[i]! as String, at.child('args').at(i)) ?? '');
      }
      final env = <String, String>{};
      for (final MapEntry(:key, :value)
          in (raw['env'] as Map<String, Object?>? ?? const {}).entries) {
        final text = expandValue(
          value! as String,
          at.child('env').child(key),
          'env.$key',
        );
        if (text != null) {
          env[key] = text;
        }
      }
      server = McpStdioServerConfig(
        name: name,
        command: command,
        args: args,
        env: env,
        origin: McpServerOrigin.config,
        connectTimeout: connect ?? defaultMcpConnectTimeout,
        callTimeout: call,
        secretValues: secretValues,
        enabled: enabled,
      );
      // D12: stdio-сервер закоммиченного `config.yaml` получает ссылку на
      // секрет. Поведение не меняется (stdio правило привязки не судит, D1),
      // но процесс работает от имени пользователя и видит его файлы, поэтому
      // пользователь должен знать, что его хранилище доступно чужой команде.
      // `${NAME}` не предупреждает (шум для `npx … ${TOKEN}`), `${secret:}` в
      // `args` — проблема загрузки до этого места. Одно событие на сервер.
      if (!failed &&
          origin.kind == ConfigLayerKind.project &&
          secretValues.entries.any(
            (e) =>
                e.key.startsWith('env.') &&
                e.value.parts.any((p) => p is SecretReference),
          )) {
        _warn(
          'config.mcp.stdio_secret_reference',
          at.value,
          origin,
          'a stdio server from the committed project config receives a '
              'secret reference; it runs as you, so move it to config.local.yaml '
              'if you did not write it',
          fields: {'server': name, 'source': origin.source},
        );
      }
    } else {
      final rawUrl = raw['url'];
      if (rawUrl is! String || rawUrl.isEmpty) {
        bad('url', 'required for http servers');
        return null;
      }
      // Адрес с непривязанной `${ENV}` нигде не используется (транспорт не
      // открывается), но `McpHttpServerConfig` требует разобранный `Uri`:
      // ссылки вырезаются, значение переменной в строку не попадает.
      // `${secret:}` в `url` — проблема загрузки при любых других ссылках:
      // проверка раньше ветки вырезания, иначе сервер лишь блокировался бы.
      final secretInUrl = referencesIn(
        rawUrl,
      ).any((r) => r.$1 == ProviderReferenceKind.secret);
      if (secretInUrl) {
        bad(
          'url',
          r'secret references ${secret:…} are allowed only in env and '
              'headers values',
        );
        failed = true;
      }
      final text = secretInUrl
          ? null
          : unboundFields.contains('url')
          ? rawUrl.replaceAll(RegExp(r'\$\{[^}]*\}'), '')
          : expand(rawUrl, at.child('url'));
      final headers = <(String, String)>[];
      // Индекс заголовка-шаблона среди всех заголовков файла: раскрытие
      // вернёт его на место, а не в конец (D4).
      final positions = <String, int>{};
      var index = 0;
      for (final MapEntry(:key, :value)
          in (raw['headers'] as Map<String, Object?>? ?? const {}).entries) {
        if (unboundFields.contains('headers.$key')) {
          // Ни в `headers`, ни шаблоном в `secretValues` (D4).
          continue;
        }
        final expanded = expandValue(
          value! as String,
          at.child('headers').child(key),
          'headers.$key',
        );
        if (expanded != null) {
          headers.add((key, expanded));
        } else if (secretValues.containsKey('headers.$key')) {
          positions[key] = index;
        }
        index++;
      }
      var url = text == null ? null : Uri.tryParse(text);
      if (unboundFields.contains('url') &&
          (url == null ||
              !(url.isScheme('http') || url.isScheme('https')) ||
              url.host.isEmpty)) {
        url = Uri.parse('https://unbound.invalid');
      }
      if (!failed &&
          (url == null ||
              !(url.isScheme('http') || url.isScheme('https')) ||
              url.host.isEmpty)) {
        bad('url', 'expected an http or https URL');
        return null;
      }
      server = failed
          ? null
          : McpHttpServerConfig(
              name: name,
              url: url!,
              headers: headers,
              origin: McpServerOrigin.config,
              connectTimeout: connect ?? defaultMcpConnectTimeout,
              callTimeout: call,
              secretValues: secretValues,
              secretHeaderPositions: positions,
              enabled: enabled,
              blockedReason: blockedReason,
            );
      if (unbound.isNotEmpty && !failed) {
        _reportMcpUnbound(name, at, origin, unbound);
      }
    }
    return failed ? null : server;
  }

  /// Ссылки HTTP-сервера [raw] слоя `project`, не привязанные к его адресу
  /// (D1, D3). Слой `projectLocal` доверенного проекта — условие (a), глобальные
  /// слои не судятся, поэтому пусто. Условие (b): глобальные слои связывают ту
  /// же ссылку с тем же origin ([ProviderKeyBinding]); origin — по `url`
  /// сервера, `null` (переменная не задана, не http) не привязывает ничего.
  List<ProviderReference> _unboundMcpReferences(
    Map<String, Object?> raw,
    ConfigTree origin,
  ) {
    if (origin.kind != ConfigLayerKind.project) {
      return const [];
    }
    final serverOrigin = mcpServerOrigin(raw, environment);
    return [
      for (final ref in mcpServerReferences(raw))
        // `${secret:}` в `url` правило не судит: она остаётся проблемой
        // загрузки (`expand` с `allowSecrets: false`), как до change.
        if (!(ref.field == 'url' && ref.kind == ProviderReferenceKind.secret) &&
            !_keyBinding.isBound(ref, serverOrigin))
          ref,
    ];
  }

  /// Текст `blockedReason` (D5): совет стоит до имени ссылки, потому что
  /// `lastError` обрезается до 200 символов, а имя секрета бывает до 128. Имя,
  /// похожее на значение секрета, не печатается (как в `_reportUnbound`).
  String _mcpBlockedReason(List<ProviderReference> unbound) {
    final first = unbound.first;
    // Имя пришло из репозитория: в `lastError` и лог оно попадает, только если
    // это допустимое имя секрета (не значение, без управляющих символов и не
    // длиннее предела); имя переменной уже ограничено разбором `${NAME}`.
    final printable = switch (first.kind) {
      ProviderReferenceKind.secret =>
        literalSecretTag(first.name, asName: true) == null &&
            SecretNames.problem(first.name) == null,
      ProviderReferenceKind.env =>
        literalSecretTag(first.name, asName: true) == null,
    };
    final shown = !printable
        ? 'a reference'
        : switch (first.kind) {
            ProviderReferenceKind.secret => 'secret ${first.name}',
            ProviderReferenceKind.env => 'variable ${first.name}',
          };
    return 'key bound to another address: move the server to '
        'config.local.yaml or the user config ($shown)';
  }

  /// Предупреждение `config.mcp.key_unbound` на каждую непривязанную ссылку
  /// (D5, по образцу `_reportUnbound`). Ни имя, ни значение ссылки, ни адрес в
  /// поля не входят: имя — в `lastError`, у выключенного сервера запись
  /// откатывается вместе с остальными («тихая» сборка в `_mcpServer`).
  void _reportMcpUnbound(
    String name,
    KeyPath at,
    ConfigTree origin,
    List<ProviderReference> unbound,
  ) {
    for (final ref in unbound) {
      final path = ref.field.startsWith('headers.')
          ? at.child('headers').child(ref.field.substring('headers.'.length))
          : at.child(ref.field);
      _warn(
        'config.mcp.key_unbound',
        path.value,
        origin,
        'the reference is bound to another address and is not used',
        fields: {
          'server': name,
          'source': origin.source,
          'reference_kind': ref.kind.name,
        },
      );
    }
  }

  // ---- редакция секретов (§12.4.3) ----------------------------------------

  RedactSettings _redact() {
    const defaults = RedactSettings();
    List<String> checked(
      List<String> segments,
      List<String> fallback, {
      List<String>? known,
      String what = 'entry',
    }) {
      final raw = _raw(segments);
      if (raw is! List) {
        return fallback;
      }
      final path = _kp(segments);
      final origin = _origin(segments);
      final out = <String>[];
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i]! as String;
        if (known != null && !known.contains(item)) {
          _issue(
            ConfigIssueKind.value,
            path.at(i),
            'unknown $what (known: ${known.join(', ')})',
            origin: origin,
          );
        }
        out.add(item);
      }
      return out;
    }

    final patterns = checked(['redact', 'allowlist', 'patterns'], const []);
    final patternsPath = _kp(['redact', 'allowlist', 'patterns']);
    for (var i = 0; i < patterns.length; i++) {
      try {
        RegExp(patterns[i]);
      } on FormatException {
        _issue(
          ConfigIssueKind.value,
          patternsPath.at(i),
          'invalid regular expression',
          origin: _origin(['redact', 'allowlist', 'patterns']),
        );
      }
    }
    return RedactSettings(
      enabled: _bool(['redact', 'enabled']) ?? defaults.enabled,
      layers: checked(
        ['redact', 'layers'],
        defaults.layers,
        known: redactLayerNames,
        what: 'redaction layer',
      ),
      allowlistBuiltin: checked(
        ['redact', 'allowlist', 'builtin'],
        defaults.allowlistBuiltin,
        known: redactBuiltinAllowlist,
        what: 'built-in allowlist entry',
      ),
      allowlistPatterns: patterns,
      exemptTools: checked(['redact', 'exempt_tools'], const []),
    );
  }

  // ---- агент, права, бюджет, сжатие --------------------------------------

  ReasoningEffort _effort() => switch (_str(['agent', 'effort'])) {
    final String name => ReasoningEffort.values.byName(name),
    null => ReasoningEffort.medium,
  };

  /// Модель уровня конфига и её источник (design.md change
  /// `optional-default-model`, D1–D4).
  ///
  /// Ключ задан — прежняя строгая проверка, источник `config`, без отката на
  /// другую модель. Ключа нет — первая модель первого доступного провайдера
  /// ([implicitDefaultModel]), источник `firstProvider`; моделей нет совсем —
  /// проблема `agent.default_model` вида `value` с событием
  /// [modelNoneEvent]. Снимок без проекта (D9) при отсутствии ключа берёт
  /// модель полного снимка, если тот выбрал её явно; неявную пересчитывает по
  /// своим провайдерам и лишь потом берёт модель полного.
  (ModelRef, DefaultModelSource)? _defaultModel(
    List<CatalogProvider> providers,
    Map<String, String> problems,
    ReasoningEffort effort,
  ) {
    final name = _str(['agent', 'default_model']);
    final key = ['agent', 'default_model'];
    if (name == null) {
      final fallback = fallbackModel;
      if (fallback != null && fallbackSource == DefaultModelSource.config) {
        return (fallback, DefaultModelSource.config);
      }
      if (implicitDefaultModel(providers, problems, effort) case final m?) {
        return (m, DefaultModelSource.firstProvider);
      }
      if (fallback != null) {
        return (fallback, fallbackSource);
      }
      _bad(
        key,
        modelNoneMessage,
        kind: ConfigIssueKind.value,
        event: modelNoneEvent,
      );
      return null;
    }
    final slash = name.indexOf('/');
    final catalog = StaticModelCatalog(
      providers,
      logger: const _SilentLogger(),
    );
    final model = slash <= 0 || slash == name.length - 1
        ? null
        : catalog.resolve(ModelId(name), effort: effort);
    if (model != null) {
      return (model, DefaultModelSource.config);
    }
    if (fallbackModel != null) {
      return (fallbackModel!, fallbackSource);
    }
    _bad(
      key,
      slash <= 0
          ? 'expected <provider>/<model>'
          : '$name is not in the model catalog; declare it in '
                'providers.${name.substring(0, slash)}.models',
      kind: ConfigIssueKind.value,
    );
    return null;
  }

  PermissionsConfig _permissions() {
    final raw = _str(['permissions', 'mode']);
    ModeId? mode;
    PermissionMode? override;
    var extraDenied = const <ToolTier>{};
    if (raw == 'autopilot') {
      override = PermissionMode.autopilot;
    } else if (raw == askWithPlanBan) {
      // Сочетание `ask` и `plan` слоёв (§15.3): спрашивать про всё и
      // запретить write/exec.
      mode = ModeId.ask;
      extraDenied = {ToolTier.write, ToolTier.exec};
    } else if (raw != null) {
      mode = ModeId.parse(configModeId(raw)!);
    }

    final deny = <PermissionKey>{};
    final denyList = _raw(['permissions', 'deny']);
    if (denyList is List) {
      for (var i = 0; i < denyList.length; i++) {
        final entry = denyList[i]! as String;
        final colon = entry.indexOf(':');
        if (colon <= 0 || colon == entry.length - 1) {
          _issue(
            ConfigIssueKind.value,
            _kp(['permissions', 'deny']).at(i),
            'expected "<tool>:<pattern>"',
            segments: ['permissions', 'deny'],
          );
          continue;
        }
        deny.add(
          PermissionKey(entry.substring(0, colon), entry.substring(colon + 1)),
        );
      }
    }
    final tools = <String, ToolPolicy>{};
    for (final MapEntry(:key, :value)
        in (_map(['permissions', 'tools']) ?? const {}).entries) {
      tools[key] = ToolPolicy.values.byName(value! as String);
    }
    return PermissionsConfig(
      mode: mode,
      modeOverride: override,
      rules: PolicyRules(toolPolicies: tools, denyPatterns: deny),
      extraDeniedTiers: extraDenied,
    );
  }

  TurnBudget _budget() {
    const defaults = TurnBudget();
    final steps = _int(['budget', 'max_steps']);
    final tokens = _int(['budget', 'max_tokens']);
    final cost = _num(['budget', 'max_cost']);
    final duration = _dur(['budget', 'max_duration']);
    if (steps != null && steps < 1) {
      _bad(['budget', 'max_steps'], 'must be 1 or greater');
    }
    if (tokens != null && tokens < 1) {
      _bad(['budget', 'max_tokens'], 'must be greater than 0');
    }
    if (cost != null && cost <= 0) {
      _bad(['budget', 'max_cost'], 'must be greater than 0');
    }
    if (duration != null && duration <= Duration.zero) {
      _bad(['budget', 'max_duration'], 'must be greater than 0');
    }
    return TurnBudget(
      maxSteps: steps ?? defaults.maxSteps,
      maxTokens: tokens,
      maxCost: cost,
      maxDuration: duration,
    );
  }

  /// `tools.project_context.max_bytes`: `0..262144`, `0` выключает чтение
  /// инструкций проекта (D5).
  int _projectContextMaxBytes() {
    const path = ['tools', 'project_context', 'max_bytes'];
    final value = _int(path);
    if (value == null) {
      return defaultProjectContextMaxBytes;
    }
    if (value < 0 || value > maxProjectContextMaxBytes) {
      _bad(path, 'must be between 0 and $maxProjectContextMaxBytes');
      return defaultProjectContextMaxBytes;
    }
    return value;
  }

  /// Раздел `skills` (design.md change `add-agent-skills`, D11, D16, Q41):
  /// границы значений и проверка элементов `extra_roots`.
  ///
  /// Элемент со схемой `<scheme>://` зарезервирован под встроенные навыки
  /// (E-18) и сейчас — проблема `value`; `~user/…` не поддерживается, потому
  /// что домашний каталог другого пользователя ядро не знает. Значения
  /// `extra_roots` хранятся как записаны: `~` раскрывает загрузчик.
  SkillsConfig _skills() {
    const defaults = SkillsConfig();
    int bounded(List<String> path, int lower, int upper, int fallback) {
      final value = _int(['skills', ...path]);
      if (value == null) {
        return fallback;
      }
      if (value < lower || value > upper) {
        _bad(
          ['skills', ...path],
          'must be between $lower and $upper',
          kind: ConfigIssueKind.value,
        );
        return fallback;
      }
      return value;
    }

    final roots = <String>[];
    final raw = _raw(['skills', 'extra_roots']);
    if (raw is List<Object?>) {
      final scheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*://');
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is! String) {
          continue;
        }
        final path = _kp(['skills', 'extra_roots']).at(i);
        if (scheme.hasMatch(item)) {
          _issue(
            ConfigIssueKind.value,
            path,
            'URI schemes are not supported in skills.extra_roots',
            segments: const ['skills', 'extra_roots'],
          );
        } else if (item.startsWith('~') &&
            item != '~' &&
            !item.startsWith('~/')) {
          _issue(
            ConfigIssueKind.value,
            path,
            '~user is not supported in skills.extra_roots; use an absolute '
            'path or ~/',
            segments: const ['skills', 'extra_roots'],
          );
        } else {
          roots.add(item);
        }
      }
    }
    final disabled = _raw(['skills', 'disabled']);
    return SkillsConfig(
      enabled: _bool(['skills', 'enabled']) ?? defaults.enabled,
      extraRoots: roots,
      disabled: disabled is List<Object?>
          ? [for (final name in disabled) name! as String]
          : const [],
      maxSkills: bounded(['max_skills'], 1, 1000, defaults.maxSkills),
      catalogMaxChars: bounded(
        ['catalog_max_chars'],
        1000,
        64000,
        defaults.catalogMaxChars,
      ),
      reattachPerSkillTokens: bounded(
        ['reattach', 'per_skill_tokens'],
        0,
        16384,
        defaults.reattachPerSkillTokens,
      ),
      reattachTotalTokens: bounded(
        ['reattach', 'total_tokens'],
        0,
        200000,
        defaults.reattachTotalTokens,
      ),
    );
  }

  CompactionOverrides _compaction() {
    final reserve = _int(['compaction', 'reserve_tokens']);
    final keep = _int(['compaction', 'keep_recent_tokens']);
    final cap = _int(['compaction', 'context_window_cap']);
    for (final (key, value) in [
      ('reserve_tokens', reserve),
      ('keep_recent_tokens', keep),
      ('context_window_cap', cap),
    ]) {
      if (value != null && value <= 0) {
        _bad(['compaction', key], 'must be greater than 0');
      }
    }
    return CompactionOverrides(
      reserveTokens: reserve,
      keepRecentTokens: keep,
      keepRecentUserTurns: _int(['compaction', 'keep_recent_user_turns']),
      contextWindowCap: cap,
      enabled: _bool(['compaction', 'enabled']) ?? true,
    );
  }

  // ---- профиль хоста ------------------------------------------------------

  static final _capabilityByKey = {
    for (final capability in HostCapability.values)
      _snake(capability.name): capability,
  };

  static String _snake(String camel) => camel.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '_${m.group(0)!.toLowerCase()}',
  );

  /// Возможности «после MVP» (§15.4): имена известны, потребителя нет.
  static const _afterMvpCapabilities = {
    'network',
    'language_servers',
    'background_jobs',
    'memory',
    'user_questions',
    'user_hooks',
  };

  Map<String, Map<HostCapability, CapabilityState>> _profiles() {
    final out = <String, Map<HostCapability, CapabilityState>>{};
    for (final MapEntry(key: name, value: raw)
        in (_map(['profile']) ?? const {}).entries) {
      final profileKey = ['profile', name];
      final HostProfile profile;
      try {
        profile = HostProfile.of(name);
      } on ArgumentError {
        _bad(profileKey, 'unknown host profile', kind: ConfigIssueKind.value);
        continue;
      }
      final narrowing = <HostCapability, CapabilityState>{};
      for (final MapEntry(key: key, value: value)
          in (raw as Map<String, Object?>? ?? const {}).entries) {
        final capability = _capabilityByKey[key];
        if (capability == null) {
          if (_afterMvpCapabilities.contains(key)) {
            _notApplied(
              _kp([...profileKey, key]).value,
              _origin([...profileKey, key]),
            );
          } else {
            final hint = nearestKey(key, _capabilityByKey.keys);
            _bad(
              [...profileKey, key],
              hint == null
                  ? 'unknown key'
                  : 'unknown key (did you mean $hint?)',
              kind: ConfigIssueKind.unknownKey,
            );
          }
          continue;
        }
        final state = value == 'off'
            ? const CapabilityOff('disabled in config')
            : CapabilityTransport({
                for (final item in value! as List<Object?>) item! as String,
              }, 'narrowed in config');
        try {
          profile.narrowed({capability: state});
        } on HostWiringException {
          _bad(
            [...profileKey, key],
            'a profile can only be narrowed, not widened',
            kind: ConfigIssueKind.value,
          );
          continue;
        }
        narrowing[capability] = state;
      }
      out[name] = narrowing;
    }
    return out;
  }
}

/// Копия [layer] без ключей, названных проблемами [issues] этого слоя
/// (режим `collectAll`; R3-1, решение 2026-11-03), и признак, что что-то
/// вырезано.
///
/// Почему: проверка слоя нашла ошибочный ключ, и сборка не должна ни читать
/// его значение неверного типа, ни повторять ту же проблему.
///
/// Как работает: сначала все пути разрешаются в цели по исходному дереву, и
/// только потом цели удаляются; элементы одного списка — по убыванию индекса,
/// иначе номера следующих проблем указывали бы на сдвинутые элементы. Путь не
/// разбирается `splitKeyPath`, а сопоставляется строкой с ключами дерева
/// (`KeyPath.child` не квотирует `"` внутри имени, и разбор такого пути
/// невозможен). Не найденный до конца путь вырезает ближайшего найденного
/// предка; не найденный вовсе (ключ верхнего уровня не опознан) — весь слой,
/// чтобы круг всегда давал прогресс; такой фолбэк даёт `degraded`, и результат
/// помечается проблемой «проверка неполна» (ревью R3-3).
({ConfigTree layer, bool removed, bool degraded}) _withoutKeys(
  ConfigTree layer,
  List<ConfigIssue> issues,
) {
  var values = _deepCopy(layer.values) as Map<String, Object?>;
  final cut = _Cut();
  var wholeLayer = false;
  var fallback = false;
  for (final issue in issues) {
    if (issue.source != layer.source || _exact(values, issue.key, cut)) {
      continue;
    }
    fallback = true;
    final ancestor = _nearestAncestor(values, issue.key, cut);
    if (ancestor == null) {
      wholeLayer = true;
    } else {
      ancestor();
    }
  }
  var removed = false;
  if (wholeLayer && values.isNotEmpty) {
    values = <String, Object?>{};
    removed = true;
  } else {
    for (final (map, key) in cut.mapKeys) {
      map.remove(key);
      removed = true;
    }
    for (final MapEntry(key: list, value: indexes) in cut.listIndexes.entries) {
      for (final index in (indexes.toList()..sort()).reversed) {
        list.removeAt(index);
        removed = true;
      }
    }
  }
  return (
    layer: ConfigTree(
      kind: layer.kind,
      source: layer.source,
      values: values,
      positions: layer.positions,
    ),
    removed: removed,
    degraded: fallback && removed,
  );
}

Object? _deepCopy(Object? v) => switch (v) {
  Map<String, Object?>() => {
    for (final e in v.entries) e.key: _deepCopy(e.value),
  },
  List<Object?>() => [for (final e in v) _deepCopy(e)],
  _ => v,
};

/// Результат вырезания: цели и признак запасного вырезания.
final class _Cut {
  final mapKeys = <(Map<String, Object?>, String)>[];
  final listIndexes = <List<Object?>, Set<int>>{};
}

/// Точный поиск узла по остатку пути [rest] с возвратом: сначала ключ,
/// равный всему остатку, затем префиксы от длинного к короткому, при неудаче
/// — следующий кандидат (результат не зависит от порядка ключей). В [cut]
/// записывается только найденный узел; неудачные ветки ничего не пишут.
///
/// Элемент списка: токен до подходящей `]` (имя может содержать `]`) ищется
/// по `name`-строке; номер — только для элемента без строкового `name` или
/// для списка строк, так сервер с именем `"0"` не путается с номером 0.
/// Дубликаты имени: остаются первый, остальные вырезаются за один круг.
bool _exact(Object? node, String rest, _Cut cut) {
  if (node is Map<String, Object?>) {
    final candidates = [
      for (final key in node.keys) (key, KeyPath.root.child(key).value),
    ]..sort((a, b) => b.$2.length.compareTo(a.$2.length));
    for (final (key, segment) in candidates) {
      if (rest == segment) {
        cut.mapKeys.add((node, key));
        return true;
      }
    }
    for (final (key, segment) in candidates) {
      if (rest.length > segment.length && rest.startsWith(segment)) {
        final tail = rest.substring(segment.length);
        if ((tail.startsWith('.') || tail.startsWith('[')) &&
            _exact(
              node[key],
              tail.startsWith('.') ? tail.substring(1) : tail,
              cut,
            )) {
          return true;
        }
      }
    }
    return false;
  }
  if (node is List<Object?> && rest.startsWith('[')) {
    for (
      var end = rest.indexOf(']');
      end > 0;
      end = rest.indexOf(']', end + 1)
    ) {
      final tail = rest.substring(end + 1);
      if (tail.isNotEmpty && !tail.startsWith('.')) {
        continue;
      }
      final token = rest.substring(1, end);
      var indexes = [
        for (var i = 0; i < node.length; i++)
          if (node[i] is Map && (node[i] as Map)['name'] == token) i,
      ];
      if (indexes.isEmpty) {
        final n = int.tryParse(token);
        if (n != null && n >= 0 && n < node.length) {
          final item = node[n];
          if (!(item is Map && item['name'] is String)) {
            indexes = [n];
          }
        }
      }
      if (indexes.isEmpty) {
        continue;
      }
      if (tail.isEmpty) {
        (cut.listIndexes[node] ??= {}).addAll(
          indexes.length > 1 ? indexes.skip(1) : indexes,
        );
        return true;
      }
      if (_exact(node[indexes.first], tail.substring(1), cut)) {
        return true;
      }
    }
  }
  return false;
}

/// Запасной поиск: самый глубокий узел, на который указывает начало пути
/// (жадно, по самому длинному ключу). Вырезание такого предка всегда
/// помечается `degraded` — это отбрасывает больше, чем путь проблемы.
void Function()? _nearestAncestor(Object? node, String rest, _Cut cut) {
  if (node is! Map<String, Object?>) {
    return null;
  }
  final candidates = [
    for (final key in node.keys) (key, KeyPath.root.child(key).value),
  ]..sort((a, b) => b.$2.length.compareTo(a.$2.length));
  for (final (key, segment) in candidates) {
    if (!rest.startsWith(segment)) {
      continue;
    }
    final tail = rest.substring(segment.length);
    if (tail.startsWith('.')) {
      final deeper = _nearestAncestor(node[key], tail.substring(1), cut);
      if (deeper != null) {
        return deeper;
      }
    }
    return () => cut.mapKeys.add((node, key));
  }
  return null;
}
