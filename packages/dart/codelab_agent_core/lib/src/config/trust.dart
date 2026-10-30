import '../loop/turn_budget.dart';
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
  // пишет. У `config.local.yaml` столбец «да», но только для доверенного
  // проекта: недоверенный подчиняется правилам слоя 3.
  if (isProject || !trusted) {
    for (final section in const ['sessions', 'logging', 'exec']) {
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
