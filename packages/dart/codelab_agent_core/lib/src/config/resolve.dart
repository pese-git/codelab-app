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
import '../secrets/secret_names.dart';
import '../secrets/secret_template.dart';
import '../tools/agent_tool.dart' show ToolTier;
import '../util/logger.dart';
import 'config_issue.dart';
import 'config_tree.dart';
import 'core_config.dart';
import 'host_settings.dart';
import 'interpolate.dart';
import 'key_path.dart';
import 'merge.dart';
import 'redact_settings.dart';
import 'schema.dart';
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
}) => _resolve(
  layers,
  environment: environment,
  projectRoot: projectRoot,
  fallbackModel: null,
);

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
    return ConfigLoadResult(issues: issues, sources: sources);
  }

  // Шаг 4: правила доверия применяются к слоям `project` и `projectLocal` до
  // слияния и сравнивают их с итогом слоёв ниже (D7).
  final trusted =
      projectRoot != null &&
      _trustedRoots(layers, environment).any((r) => samePath(r, projectRoot));
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

  final builder = _Builder(
    effective,
    environment: environment,
    fallbackModel: fallbackModel,
    warnings: trustWarnings,
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
    );
    if (second.issues.isNotEmpty) {
      return ConfigLoadResult(
        issues: second.issues,
        warnings: builder.warnings,
        sources: sources,
      );
    }
    bare = second.config;
  }

  return ConfigLoadResult(
    config: projectRoot == null
        ? full
        : CoreConfig(
            defaultModel: full.defaultModel,
            permissions: full.permissions,
            budget: full.budget,
            compaction: full.compaction,
            effort: full.effort,
            mcpServers: full.mcpServers,
            providers: full.providers,
            providerProblems: full.providerProblems,
            redact: full.redact,
            projectContextMaxBytes: full.projectContextMaxBytes,
            trustedProjects: full.trustedProjects,
            projectRoot: projectRoot,
            withoutProject: bare,
          ),
    host: builder.host,
    warnings: builder.warnings,
    sources: sources,
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
    this.layers, {
    required this.environment,
    required this.fallbackModel,
    List<ConfigIssue> warnings = const [],
  }) : warnings = [...warnings];

  final List<ConfigTree> layers;
  final Map<String, String> environment;
  final ModelRef? fallbackModel;

  final issues = <ConfigIssue>[];
  final List<ConfigIssue> warnings;

  late Map<String, Object?> merged;
  CoreConfig? config;
  HostSettings? host;

  void build() {
    for (final layer in layers) {
      for (final path in collectNotApplied(layer)) {
        _notApplied(path, layer);
      }
    }
    merged = mergeLayers(layers);

    final problems = <String, String>{};
    final providers = _providers(problems);
    final effort = _effort();
    final model = _defaultModel(providers, effort);
    final permissions = _permissions();
    final budget = _budget();
    final compaction = _compaction();
    final mcpServers = _mcpServers();
    final redact = _redact();
    final profiles = _profiles();
    final projectContextMaxBytes = _projectContextMaxBytes();
    final secretsBackend = _secretsBackend();

    if (issues.isNotEmpty || model == null) {
      return;
    }
    config = CoreConfig(
      defaultModel: model,
      permissions: permissions,
      budget: budget,
      compaction: compaction,
      effort: effort,
      mcpServers: mcpServers,
      providers: providers,
      providerProblems: problems,
      redact: redact,
      projectContextMaxBytes: projectContextMaxBytes,
      trustedProjects: _trustedRoots(layers, environment),
    );
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
      ),
    );
  }

  /// Проблема по сегментам ключа слитого дерева.
  void _bad(
    List<String> segments,
    String message, {
    ConfigIssueKind kind = ConfigIssueKind.semantic,
  }) => _issue(kind, _kp(segments), message, segments: segments);

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
    final rawBase = _str([...at, 'base_url']);
    final String? base;
    if (rawBase != null) {
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
    final baseUrl = Uri.tryParse(base);
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
      final path = _kp([...at, 'headers', name]);
      final expanded = _interpolate(
        value! as String,
        path,
        _origin([...at, 'headers', name]),
      );
      if (expanded == null) {
        continue;
      }
      if (expanded.secrets.isNotEmpty) {
        headerTemplates[name] = expanded.template;
      } else {
        headers[name] = expanded.text;
      }
    }

    final keyEnv = _str([...at, 'api_key_env']);
    final keySecret = _str([...at, 'api_key_secret']);
    // Имя не должно оказаться ключом, вписанным вместо имени (CFG-9,
    // §17.5.4): значение не попадает ни в проблему, ни в `providerProblems`,
    // ни в поле `variable` предупреждения.
    if (keyEnv != null && !_envName.hasMatch(keyEnv)) {
      _bad(
        [...at, 'api_key_env'],
        'expected an environment variable name',
        kind: ConfigIssueKind.value,
      );
      return null;
    }
    if (keySecret != null && SecretNames.problem(keySecret) != null) {
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

    final provider = ProviderConfig(
      name: id,
      api: api,
      baseUrl: baseUrl,
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
    for (final name in expansion.secretRefs) {
      if (SecretNames.problem(name) case final problem?) {
        _issue(ConfigIssueKind.value, path, problem, origin: origin);
        return null;
      }
    }
    return (
      text: expansion.text,
      secrets: expansion.secretRefs,
      template: expansion.template,
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
    void bad(String field, String message) =>
        _issue(ConfigIssueKind.value, at.child(field), message, origin: origin);

    if (raw['enabled'] == false) {
      _warn(
        'mcp.server.skipped',
        at.value,
        origin,
        'the server is disabled in the config',
        fields: {'server': name, 'reason': 'disabled in config'},
        level: LogLevel.info,
      );
      return null;
    }
    final type = raw['type'];
    if (type == null) {
      bad('type', 'required (stdio or http)');
      return null;
    }
    if (type != 'stdio' && type != 'http') {
      bad('type', 'only stdio and http are supported');
      return null;
    }

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
      );
    } else {
      final rawUrl = raw['url'];
      if (rawUrl is! String || rawUrl.isEmpty) {
        bad('url', 'required for http servers');
        return null;
      }
      final text = expand(rawUrl, at.child('url'));
      final headers = <(String, String)>[];
      // Индекс заголовка-шаблона среди всех заголовков файла: раскрытие
      // вернёт его на место, а не в конец (D4).
      final positions = <String, int>{};
      var index = 0;
      for (final MapEntry(:key, :value)
          in (raw['headers'] as Map<String, Object?>? ?? const {}).entries) {
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
      final url = text == null ? null : Uri.tryParse(text);
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
            );
    }
    return failed ? null : server;
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

  ModelRef? _defaultModel(
    List<CatalogProvider> providers,
    ReasoningEffort effort,
  ) {
    final name = _str(['agent', 'default_model']);
    final key = ['agent', 'default_model'];
    if (name == null) {
      if (fallbackModel != null) {
        return fallbackModel;
      }
      _bad(key, 'required', kind: ConfigIssueKind.value);
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
      return model;
    }
    if (fallbackModel != null) {
      return fallbackModel;
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
    'skills',
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
