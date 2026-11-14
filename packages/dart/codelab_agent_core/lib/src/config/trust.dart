import '../loop/turn_budget.dart';
import '../skills/skills_config.dart';
import '../subagents/subagents_config.dart';
import 'config_issue.dart';
import 'config_tree.dart';
import 'key_path.dart';
import 'schema.dart';
import 'validate.dart' show configModeId;

/// Правила доверия к проектным слоям (`agent-core-architecture` §15.3;
/// design.md change `add-agent-configuration`, D7; CFG-3).
///
/// Почему: проектный конфиг приходит из репозитория, который пользователь мог
/// только что склонировать. Репозиторий не должен запускать процессы на его
/// машине, направлять запросы на свой адрес и расширять права агента, но и
/// не должен ломать запуск — поэтому недопустимый ключ отбрасывается с
/// предупреждением `config.project.untrusted_key`, а не ошибкой. Недоверенный
/// проект также не снимает запреты, поставленные пользователем: его
/// `permissions.deny` объединяется со списком нижних слоёв, а правило
/// инструмента применяется, только если строже нижнего.
///
/// Для чего: функция возвращает копию слоя `project` или `projectLocal` без
/// отброшенных ключей и предупреждения. По решению пользователя 2026-10-30
/// `config.local.yaml` подчиняется тем же правилам, пока проект не в
/// `trusted_projects`; у доверенного проекта он не ограничен. Слои `extra`,
/// окружение и флаги правилам не подчиняются (задаёт тот, кто запускает).
///
/// Как использовать: [lower] — итог слияния слоёв ниже (умолчания, глобальный
/// и, для `projectLocal`, проектный): «только ужесточение» сравнивается с
/// ним, а не с самим слоем; [trusted] — корень проекта есть в
/// `trusted_projects`.
({ConfigTree layer, List<ConfigIssue> warnings}) applyProjectTrust(
  ConfigTree project, {
  required Map<String, Object?> lower,
  required bool trusted,
}) {
  final values = _deepCopy(project.values);
  final warnings = <ConfigIssue>[];
  final isProject = project.kind == ConfigLayerKind.project;

  void warn(String key, String reason) {
    final position = project.positions[key];
    warnings.add(
      ConfigIssue(
        kind: ConfigIssueKind.semantic,
        key: key,
        source: project.source,
        line: position?.line,
        column: position?.column,
        message: 'ignored: $reason',
        event: 'config.project.untrusted_key',
        fields: {'key': key, 'source': project.source},
      ),
    );
  }

  // Не читаются из проектных слоёв ни с доверием, ни без: список доверия
  // ведёт только пользователь (CFG-3), секреты — только глобальный конфиг
  // (§15.3, `secrets.*`).
  if (values.remove('trusted_projects') != null) {
    warn(
      'trusted_projects',
      'trusted_projects is read only from the global config',
    );
  }
  if (values.remove('secrets') != null) {
    warn('secrets', 'secrets is read only from the global config');
  }
  // Эти разделы не читаются из проекта (слой 3) даже с доверием (§15.3:
  // «нет» в его столбце). `sessions` и `logging` определяют, куда агент
  // пишет, `config` — как хост следит за файлами конфига (D7, change
  // `add-config-writer-and-reload`). У `config.local.yaml` столбец «да», но
  // только для доверенного проекта: недоверенный подчиняется правилам
  // слоя 3.
  if (isProject || !trusted) {
    for (final section in const ['sessions', 'logging', 'exec', 'config']) {
      if (values.remove(section) != null) {
        warn(section, '$section is not read from a project config');
      }
    }
  }

  if (!trusted) {
    const reason =
        'the project is not trusted; add it to trusted_projects in the '
        'global config';
    if ((values['mcp'] as Map<String, Object?>?)?.remove('servers') != null) {
      warn('mcp.servers', reason);
    }
    // Разделы, которым нужно доверие (§15.3). `prompts` и разделы после MVP
    // читаются позже, но правило действует уже сейчас: потребитель не должен
    // получить непроверенный ключ из чужого репозитория.
    for (final section in const [
      'providers',
      'model_catalog',
      'prompts',
      'hooks',
      'plugins',
      'a2a',
      'lsp',
    ]) {
      if (values.remove(section) != null) {
        warn(section, reason);
      }
    }
    _restrictPermissions(values, lower, warn, reason);
    _restrictRedact(values, lower, warn);
    _lowerBudget(values, lower, warn);
    _lowerProjectContext(values, lower, warn);
    _lowerSkills(values, lower, warn);
    _lowerSubagents(values, lower, warn);
  }
  if (isProject || !trusted) {
    _dropSkillRoots(values, warn);
  }
  if (!trusted || isProject) {
    _narrowMode(values, lower, warn);
  }

  return (
    layer: ConfigTree(
      kind: project.kind,
      source: project.source,
      values: values,
      positions: project.positions,
    ),
    warnings: warnings,
  );
}

/// `permissions.deny` и `permissions.tools` недоверенного слоя: запрет
/// пользователя не снимается (D7).
void _restrictPermissions(
  Map<String, Object?> values,
  Map<String, Object?> lower,
  void Function(String key, String reason) warn,
  String reason,
) {
  final permissions = values['permissions'];
  if (permissions is! Map<String, Object?>) {
    return;
  }
  final lowerPermissions =
      lower['permissions'] as Map<String, Object?>? ?? const {};

  // Список заменяется при слиянии, поэтому слой получает объединение: иначе
  // `deny: []` в репозитории стёр бы запреты пользователя.
  if (permissions['deny'] case final List<Object?> deny) {
    final below = lowerPermissions['deny'];
    permissions['deny'] = [
      if (below is List<Object?>) ...below,
      for (final item in deny)
        if (below is! List<Object?> || !below.contains(item)) item,
    ];
  }

  if (permissions['tools'] case final Map<String, Object?> tools) {
    final belowTools =
        lowerPermissions['tools'] as Map<String, Object?>? ?? const {};
    for (final tool in [...tools.keys]) {
      final value = tools[tool];
      final below = belowTools[tool];
      // `allow` расширяет права — только с доверием; остальное допустимо,
      // если не мягче правила ниже (deny > ask > allow).
      if (value == 'allow' ||
          (below != null && _toolStrictness(value) < _toolStrictness(below))) {
        tools.remove(tool);
        warn(KeyPath('permissions.tools').child(tool).value, reason);
      }
    }
  }
}

int _toolStrictness(Object? policy) => switch (policy) {
  'deny' => 2,
  'ask' => 1,
  _ => 0,
};

/// Порядок мягкости базового режима: больше — строже (§15.3, `narrow`).
/// `plan` как базовое разрешение — `standard` (`ModeId.plan.permissionMode`).
const _strictness = {
  'bypass': 0,
  'accept-edits': 1,
  'standard': 2,
  'plan': 2,
  'ask': 3,
};

/// Режим профиля по умолчанию у встроенных профилей — `standard`
/// (`HostProfile.defaultMode`, §10.5): ядро не знает профиль хоста, а проект
/// не должен смягчить то, что хост выбрал бы без конфигов.
const _profileDefaultMode = 'standard';

/// Внутреннее значение `permissions.mode` для сочетания `ask` + `plan`: ни
/// один файловый слой записать его не может (проверка схемы идёт до правил
/// доверия), а `resolve.dart` превращает его в `ask` с
/// `PermissionsConfig.extraDeniedTiers = {write, exec}`.
const askWithPlanBan = 'ask+plan';

({int rank, bool ban}) _parseMode(String id) => (
  rank: id == askWithPlanBan ? _strictness['ask']! : _strictness[id]!,
  ban: id == 'plan' || id == askWithPlanBan,
);

void _narrowMode(
  Map<String, Object?> values,
  Map<String, Object?> lower,
  void Function(String key, String reason) warn,
) {
  final permissions = values['permissions'];
  if (permissions is! Map<String, Object?>) {
    return;
  }
  final raw = permissions['mode'];
  final project = raw is String ? configModeId(raw) : null;
  if (project == null) {
    return;
  }
  final lowerRaw = (lower['permissions'] as Map<String, Object?>?)?['mode'];
  final lowerMode = lowerRaw is String
      ? (lowerRaw == askWithPlanBan ? lowerRaw : configModeId(lowerRaw))
      : null;

  // `plan` запрещает write/exec жёстко, `ask` спрашивает про всё. Результат
  // — более строгий базовый режим и объединение запретов: `ask` + `plan` в
  // любом порядке даёт `ask` с запретом write/exec (§15.3).
  final a = _parseMode(lowerMode ?? _profileDefaultMode);
  final b = _parseMode(project);
  final rank = a.rank > b.rank ? a.rank : b.rank;
  final ban = a.ban || b.ban;
  final String result;
  if (rank >= _strictness['ask']!) {
    result = ban ? askWithPlanBan : 'ask';
  } else if (ban) {
    result = 'plan';
  } else {
    result = _strictness.entries
        .firstWhere((e) => e.value == rank && e.key != 'plan')
        .key;
  }
  if (result == project) {
    permissions['mode'] = project;
    return;
  }
  warn(
    'permissions.mode',
    'a project config can only make the permission mode stricter',
  );
  if (lowerMode == null && result == _profileDefaultMode) {
    permissions.remove('mode');
  } else {
    permissions['mode'] = result;
  }
}

void _lowerBudget(
  Map<String, Object?> values,
  Map<String, Object?> lower,
  void Function(String key, String reason) warn,
) {
  final budget = values['budget'];
  if (budget is! Map<String, Object?>) {
    return;
  }
  final lowerBudget = lower['budget'] as Map<String, Object?>? ?? const {};
  for (final key in const [
    'max_steps',
    'max_tokens',
    'max_cost',
    'max_duration',
  ]) {
    final project = budget[key];
    if (project == null) {
      continue;
    }
    final below =
        lowerBudget[key] ??
        (key == 'max_steps' ? const TurnBudget().maxSteps : null);
    if (below != null && _greater(project, below)) {
      budget.remove(key);
      warn(
        'budget.$key',
        'a project config can only lower the budget; the limit of the '
            'global config is kept',
      );
    }
  }
}

/// `tools.project_context.max_bytes` недоверенного проекта — только
/// уменьшение (design.md change `add-agent-project-files`, D5): репозиторий
/// не должен раздувать каждый запрос мегабайтом своего текста. Сравнивается с
/// итогом слоёв ниже, а без значения там — с умолчанием.
void _lowerProjectContext(
  Map<String, Object?> values,
  Map<String, Object?> lower,
  void Function(String key, String reason) warn,
) {
  final tools = values['tools'];
  final section = tools is Map<String, Object?>
      ? tools['project_context']
      : null;
  if (section is! Map<String, Object?> || section['max_bytes'] is! int) {
    return;
  }
  final lowerTools = lower['tools'];
  final lowerSection = lowerTools is Map<String, Object?>
      ? lowerTools['project_context']
      : null;
  final below = lowerSection is Map<String, Object?>
      ? lowerSection['max_bytes']
      : null;
  final limit = below is int ? below : defaultProjectContextMaxBytes;
  if ((section['max_bytes'] as int) > limit) {
    section.remove('max_bytes');
    warn(
      'tools.project_context.max_bytes',
      'a project config can only lower the project context budget; the '
          'limit of the global config is kept',
    );
  }
}

/// Ключи `skills.*` недоверенного проекта (design.md change
/// `add-agent-skills`, D11, Q40, Q43).
///
/// Числовые ключи — только уменьшение: репозиторий не должен раздувать
/// каталог навыков в каждом запросе; сравнение — с итогом слоёв ниже, а без
/// значения там — с умолчанием `SkillsConfig`. Запреты пользователя проект не
/// снимает: `enabled: true` поверх `false` нижних слоёв отбрасывается, а
/// `disabled` объединяется с нижними слоями (как `permissions.deny`). Доверенный
/// проект ограничен лишь границами схемы, как с `budget.*`.
void _lowerSkills(
  Map<String, Object?> values,
  Map<String, Object?> lower,
  void Function(String key, String reason) warn,
) {
  final skills = values['skills'];
  if (skills is! Map<String, Object?>) {
    return;
  }
  Object? at(Map<String, Object?> root, List<String> path) {
    Object? node = root;
    for (final name in path) {
      node = node is Map<String, Object?> ? node[name] : null;
    }
    return node;
  }

  // Q43: запреты пользователя недоверенный проект не снимает. `enabled: true`
  // поверх `false` нижних слоёв отбрасывается; `disabled` объединяется с
  // нижними слоями (список при слиянии заменяется, как `permissions.deny`).
  if (skills['enabled'] == true && at(lower, ['skills', 'enabled']) == false) {
    skills.remove('enabled');
    warn(
      'skills.enabled',
      'a project config cannot switch skills back on; the setting of the '
          'global config is kept',
    );
  }
  final ownDisabled = skills['disabled'];
  if (ownDisabled is List<Object?>) {
    final lowerDisabled = at(lower, ['skills', 'disabled']);
    skills['disabled'] = [
      if (lowerDisabled is List<Object?>) ...lowerDisabled,
      for (final name in ownDisabled)
        if (lowerDisabled is! List<Object?> || !lowerDisabled.contains(name))
          name,
    ];
  }

  const defaults = SkillsConfig();
  final keys = <(List<String>, int)>[
    (const ['max_skills'], defaults.maxSkills),
    (const ['catalog_max_chars'], defaults.catalogMaxChars),
    (const ['reattach', 'per_skill_tokens'], defaults.reattachPerSkillTokens),
    (const ['reattach', 'total_tokens'], defaults.reattachTotalTokens),
  ];
  for (final (path, fallback) in keys) {
    final value = at(skills, path);
    if (value is! int) {
      continue;
    }
    final below = at(lower, ['skills', ...path]);
    if (value > (below is int ? below : fallback)) {
      final parent = path.length == 1
          ? skills
          : skills[path.first] as Map<String, Object?>;
      parent.remove(path.last);
      warn(
        'skills.${path.join('.')}',
        'a project config can only lower the skills limits; the limit of the '
            'global config is kept',
      );
    }
  }
}

/// Ключи `subagents.*` недоверенного проекта: проект только ужесточает
/// (design.md change `add-subagents-and-tasks`, D17; как `permissions`).
///
/// Меньшие числа и `enabled: false` применяются; бо́льшие числа и
/// `enabled: true` поверх `false` нижних слоёв отбрасываются с событием
/// `config.project.untrusted_key`. Сравнение — с итогом слоёв ниже, а без
/// значения там — с умолчанием `SubagentsConfig`.
void _lowerSubagents(
  Map<String, Object?> values,
  Map<String, Object?> lower,
  void Function(String key, String reason) warn,
) {
  final section = values['subagents'];
  if (section is! Map<String, Object?>) {
    return;
  }
  final below = lower['subagents'] is Map<String, Object?>
      ? lower['subagents'] as Map<String, Object?>
      : const <String, Object?>{};
  if (section['enabled'] == true && below['enabled'] == false) {
    section.remove('enabled');
    warn(
      'subagents.enabled',
      'a project config cannot switch subagents back on; the setting of the '
          'global config is kept',
    );
  }
  const defaults = SubagentsConfig();
  final fallbacks = <String, Object?>{
    'max_depth': defaults.maxDepth,
    'max_concurrent': defaults.maxConcurrent,
    'max_per_turn': defaults.maxPerTurn,
    'max_steps': defaults.maxSteps,
    'max_tokens': null,
    'max_cost': null,
    'max_duration': '10m',
    'report_max_bytes': defaults.reportMaxBytes,
    'progress_interval': '2s',
    'heartbeat_interval': '15s',
    'cancel_grace': '10s',
  };
  for (final MapEntry(:key, value: fallback) in fallbacks.entries) {
    final own = section[key];
    if (own == null) {
      continue;
    }
    final limit = below[key] ?? fallback;
    if (limit != null && _greater(own, limit)) {
      section.remove(key);
      warn(
        'subagents.$key',
        'a project config can only lower the subagent limits; the limit of '
            'the global config is kept',
      );
    }
  }
}

/// `skills.extra_roots` — согласие на чтение каталога вне проекта: даёт его
/// пользователь, а не репозиторий (D11, Q27). Из `config.yaml` проекта
/// отбрасывается всегда, из `config.local.yaml` — у недоверенного проекта.
void _dropSkillRoots(
  Map<String, Object?> values,
  void Function(String key, String reason) warn,
) {
  final skills = values['skills'];
  if (skills is Map<String, Object?> && skills.remove('extra_roots') != null) {
    warn(
      'skills.extra_roots',
      'extra skill roots are set by the user, not by a project config',
    );
  }
}

bool _greater(Object? a, Object? b) {
  if (a is num && b is num) {
    return a > b;
  }
  if (a is String && b is String) {
    final left = parseConfigDuration(a);
    final right = parseConfigDuration(b);
    return left != null && right != null && left > right;
  }
  return false;
}

/// Правила §15.3 для `redact.*` недоверенного проекта: только включить
/// редакцию, добавить слои и убрать записи белого списка.
void _restrictRedact(
  Map<String, Object?> values,
  Map<String, Object?> lower,
  void Function(String key, String reason) warn,
) {
  final redact = values['redact'];
  if (redact is! Map<String, Object?>) {
    return;
  }
  final lowerRedact = lower['redact'] as Map<String, Object?>? ?? const {};
  const reason = 'an untrusted project config can only make redaction stricter';

  if (redact['enabled'] == false) {
    redact.remove('enabled');
    warn('redact.enabled', reason);
  }
  if (redact['layers'] case final List<Object?> layers) {
    final base = _strings(lowerRedact['layers']) ?? redactDefaultLayers;
    if (!layers.toSet().containsAll(base)) {
      redact.remove('layers');
      warn('redact.layers', reason);
    }
  }
  if (redact['exempt_tools'] case final List<Object?> tools) {
    if (!(_strings(lowerRedact['exempt_tools']) ?? const [])
        .toSet()
        .containsAll(tools)) {
      redact.remove('exempt_tools');
      warn('redact.exempt_tools', reason);
    }
  }
  if (redact['allowlist'] case final Map<String, Object?> allowlist) {
    final lowerAllow =
        lowerRedact['allowlist'] as Map<String, Object?>? ?? const {};
    for (final (key, fallback) in [
      ('builtin', redactBuiltinAllowlist),
      ('patterns', const <String>[]),
    ]) {
      if (allowlist[key] case final List<Object?> items) {
        final base = _strings(lowerAllow[key]) ?? fallback;
        if (!base.toSet().containsAll(items)) {
          allowlist.remove(key);
          warn('redact.allowlist.$key', reason);
        }
      }
    }
  }
}

List<String>? _strings(Object? value) =>
    value is List ? [for (final item in value) item as String] : null;

Map<String, Object?> _deepCopy(Map<String, Object?> map) => {
  for (final MapEntry(:key, value: value) in map.entries)
    key: switch (value) {
      final Map<String, Object?> inner => _deepCopy(inner),
      final List<Object?> list => [
        for (final item in list)
          if (item is Map<String, Object?>) _deepCopy(item) else item,
      ],
      _ => value,
    },
};
