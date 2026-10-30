import 'config_issue.dart';
import 'config_tree.dart';
import 'key_path.dart';
import 'schema.dart';

/// Строгая проверка одного слоя по схеме (`agent-core-architecture` §15.5,
/// «Строгая валидация»; CFG-1, CFG-2, CFG-4).
///
/// Почему отдельный обход: слой проверяется целиком и до слияния, чтобы
/// проблема называла файл и строку слоя, который её содержит. Тот же обход
/// собирает ключи без потребителя ([LayerWalk.notApplied]) — после правил
/// доверия, когда отброшенные ключи уже не должны давать лишних предупреждений.
///
/// Как использовать: `validateLayer(layer)` возвращает проблемы слоя;
/// `collectNotApplied(layer)` — пути явно заданных ключей без потребителя.
List<ConfigIssue> validateLayer(ConfigTree layer) {
  final walk = LayerWalk(layer, report: true)..run();
  return walk.issues;
}

/// Пути явно заданных ключей слоя, у которых ещё нет потребителя (D6).
List<String> collectNotApplied(ConfigTree layer) {
  if (layer.kind == ConfigLayerKind.defaults) {
    // Умолчание ключа без потребителя предупреждения не даёт (D6).
    return const [];
  }
  final walk = LayerWalk(layer, report: false)..run();
  return walk.notApplied;
}

/// Обход слоя по схеме; один класс на проверку и сбор `not_applied`.
final class LayerWalk {
  LayerWalk(this.layer, {required this.report});

  final ConfigTree layer;

  /// `false` — только собирает [notApplied], проблемы не копит.
  final bool report;

  final issues = <ConfigIssue>[];
  final notApplied = <String>[];

  void run() => _section(layer.values, rootSchema, KeyPath.root);

  void _issue(ConfigIssueKind kind, KeyPath path, String message) {
    if (!report) {
      return;
    }
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

  void _section(Map<String, Object?> map, SectionNode node, KeyPath path) {
    for (final MapEntry(key: name, value: value) in map.entries) {
      final child = path.child(name);
      if (node.rejectsInlineSecrets && inlineSecretKeys.contains(name)) {
        _issue(ConfigIssueKind.inlineSecret, child, _inlineSecretMessage(path));
        continue;
      }
      final field = node.fields[name];
      if (field != null) {
        _node(value, field, child);
        continue;
      }
      final named = node.named;
      if (named != null) {
        final format = node.nameFormat;
        if (name.isEmpty || (format != null && !format.hasMatch(name))) {
          _issue(
            ConfigIssueKind.value,
            child,
            'invalid ${node.nameLabel} (use a-z, 0-9, _ and -)',
          );
          continue;
        }
        _node(value, named, child);
        continue;
      }
      _unknownKey(name, node, child);
    }
  }

  void _unknownKey(String name, SectionNode node, KeyPath path) {
    if (name.contains('.')) {
      final nested = name.split('.').map((part) => '$part:').join(' -> ');
      _issue(
        ConfigIssueKind.unknownKey,
        path,
        'unknown key; a dot is part of the name, use the nested form '
        '($nested)',
      );
      return;
    }
    final hint = nearestKey(name, node.fields.keys);
    _issue(
      ConfigIssueKind.unknownKey,
      path,
      hint == null ? 'unknown key' : 'unknown key (did you mean $hint?)',
    );
  }

  /// Текст не содержит значения: оно может быть секретом (CFG-2).
  String _inlineSecretMessage(KeyPath owner) =>
      owner.value.startsWith('mcp.servers')
      ? 'secrets are not stored in the config; reference an environment '
            'variable with \${NAME} in env or headers'
      : 'secrets are not stored in the config; use api_key_env '
            '(or api_key_secret with the secret store)';

  void _node(Object? value, SchemaNode node, KeyPath path) {
    switch (node) {
      case SectionNode():
        switch (value) {
          case null:
            return; // Контейнер без листьев читается как пустой (§15.5, п. 5).
          case final Map<String, Object?> map:
            _section(map, node, path);
          case _:
            _issue(ConfigIssueKind.type, path, 'expected a mapping');
        }
      case ScalarNode():
        _scalar(value, node, path);
      case ListNode():
        _list(value, node, path);
      case StringMapNode():
        _stringMap(value, node, path);
      case ObjectListNode():
        _objectList(value, node, path);
      case OpaqueNode():
        _opaqueLeaves(value, path);
      case ProfileValueNode():
        _profileValue(value, path);
      case ModeNode():
        _mode(value, path);
      case AgentsNode():
        _agents(value, path);
    }
  }

  void _mark(SchemaNode node, KeyPath path) {
    if (!node.applied) {
      notApplied.add(path.value);
    }
  }

  void _scalar(Object? value, ScalarNode node, KeyPath path) {
    if (value == null) {
      _issue(
        ConfigIssueKind.type,
        path,
        'null is not allowed; remove the key to use the default',
      );
      return;
    }
    switch (node.type) {
      case ScalarType.boolean:
        if (value is! bool) {
          _issue(
            ConfigIssueKind.type,
            path,
            value is String && _yamlOneBooleans.contains(value.toLowerCase())
                ? 'expected bool (use true or false)'
                : 'expected bool',
          );
          return;
        }
      case ScalarType.integer:
        // Хост-разборщик отдаёт `2.0` как double. На web (JS) `2.0 is int`
        // истинно, поэтому там разборщик обязан различать запись числа сам
        // (профиль §15.5, п. 6); здесь проверяется только тип значения.
        if (value is! int) {
          _issue(ConfigIssueKind.type, path, 'expected int');
          return;
        }
      case ScalarType.float:
        if (value is! num) {
          _issue(ConfigIssueKind.type, path, 'expected float');
          return;
        }
      case ScalarType.duration:
        if (value is! String || parseConfigDuration(value) == null) {
          _issue(
            ConfigIssueKind.type,
            path,
            'expected duration (a string like 30s, 2m or 1h)',
          );
          return;
        }
      case ScalarType.string || ScalarType.path:
        if (value is! String) {
          _issue(ConfigIssueKind.type, path, 'expected string');
          return;
        }
        if (node.allowed case final allowed? when !allowed.contains(value)) {
          _issue(
            ConfigIssueKind.value,
            path,
            'unknown ${node.allowedLabel} (known: ${allowed.join(', ')})',
          );
          return;
        }
    }
    _mark(node, path);
  }

  void _list(Object? value, ListNode node, KeyPath path) {
    if (value == null) {
      _issue(
        ConfigIssueKind.type,
        path,
        'null is not allowed; remove the key to use the default',
      );
      return;
    }
    if (value is! List) {
      _issue(ConfigIssueKind.type, path, 'expected a list of strings');
      return;
    }
    for (var i = 0; i < value.length; i++) {
      if (value[i] is! String) {
        _issue(ConfigIssueKind.type, path.at(i), 'expected string');
      }
    }
    _mark(node, path);
  }

  void _stringMap(Object? value, StringMapNode node, KeyPath path) {
    switch (value) {
      case null:
        return;
      case final Map<String, Object?> map:
        for (final MapEntry(:key, value: item) in map.entries) {
          if (item is! String) {
            _issue(ConfigIssueKind.type, path.child(key), 'expected string');
          }
        }
        _mark(node, path);
      case _:
        _issue(ConfigIssueKind.type, path, 'expected a map of strings');
    }
  }

  void _objectList(Object? value, ObjectListNode node, KeyPath path) {
    if (value == null) {
      _issue(
        ConfigIssueKind.type,
        path,
        'null is not allowed; remove the key to use the default',
      );
      return;
    }
    if (value is! List) {
      _issue(ConfigIssueKind.type, path, 'expected a list of mappings');
      return;
    }
    final seen = <String>{};
    for (var i = 0; i < value.length; i++) {
      final item = value[i];
      final keyField = node.keyField;
      var itemPath = path.at(i);
      if (item is! Map<String, Object?>) {
        _issue(ConfigIssueKind.type, itemPath, 'expected a mapping');
        continue;
      }
      if (keyField != null) {
        final name = item[keyField];
        if (name is! String || name.isEmpty) {
          _issue(
            ConfigIssueKind.value,
            itemPath,
            '$keyField is required and must be a non-empty string',
          );
        } else {
          itemPath = path.at(name);
          if (!seen.add(name)) {
            _issue(
              ConfigIssueKind.semantic,
              itemPath,
              'duplicate $keyField in the same file',
            );
          }
        }
      }
      _section(item, node.item, itemPath);
    }
    _mark(node, path);
  }

  /// Раздел «после MVP»: типы не проверяются, листья называются по пути.
  void _opaqueLeaves(Object? value, KeyPath path) {
    switch (value) {
      case final Map<String, Object?> map when map.isNotEmpty:
        for (final MapEntry(:key, value: item) in map.entries) {
          _opaqueLeaves(item, path.child(key));
        }
      case final List<Object?> list when list.isNotEmpty:
        notApplied.add(path.value);
      case Map<String, Object?>() || List<Object?>() || null:
        return;
      case _:
        notApplied.add(path.value);
    }
  }

  void _profileValue(Object? value, KeyPath path) {
    final ok =
        value == 'off' || (value is List && value.every((e) => e is String));
    if (!ok) {
      _issue(
        ConfigIssueKind.type,
        path,
        'expected "off" or a list of transport names',
      );
    }
  }

  void _mode(Object? value, KeyPath path) {
    if (value is! String) {
      _issue(ConfigIssueKind.type, path, 'expected string');
      return;
    }
    if (value == 'autopilot') {
      // Только флаг запуска включает autopilot (CFG-4).
      if (layer.kind != ConfigLayerKind.flags) {
        _issue(
          ConfigIssueKind.value,
          path,
          'autopilot is allowed only as a launch flag '
          '(--permission-mode autopilot)',
        );
      }
      return;
    }
    if (configModeId(value) == null) {
      _issue(
        ConfigIssueKind.value,
        path,
        'unknown permission mode (known: plan, ask, standard, accept-edits, '
        'bypass)',
      );
    }
  }

  void _agents(Object? value, KeyPath path) {
    if (value == null) {
      return;
    }
    if (value is! Map<String, Object?>) {
      _issue(ConfigIssueKind.type, path, 'expected a mapping');
      return;
    }
    for (final MapEntry(key: name, value: item) in value.entries) {
      if (name != 'definitions') {
        _unknownKey(
          name,
          const SectionNode({'definitions': OpaqueNode()}),
          path.child(name),
        );
        continue;
      }
      final definitions = path.child(name);
      if (item is Map<String, Object?> && item.isNotEmpty) {
        for (final definition in item.keys) {
          _issue(
            ConfigIssueKind.value,
            definitions.child(definition),
            'agent definitions are not configured in YAML; put the '
            'definition in .codelab/agents/$definition.md',
          );
        }
      } else {
        _issue(
          ConfigIssueKind.value,
          definitions,
          'agent definitions are not configured in YAML; put each '
          'definition in .codelab/agents/<name>.md',
        );
      }
    }
  }
}

/// Литералы логических значений YAML 1.1: для `bool` это ошибка с подсказкой
/// (профиль §15.5, п. 4).
const _yamlOneBooleans = {'yes', 'no', 'on', 'off', 'y', 'n'};

/// Идентификатор режима по имени из конфигурации или `null` (с синонимами
/// §15.4; ACP-синонимы `architect`, `debug`, `code` не принимаются).
String? configModeId(String name) => switch (name) {
  'plan' => 'plan',
  'ask' || 'alwaysAsk' => 'ask',
  'standard' || 'write' => 'standard',
  'accept-edits' || 'acceptEdits' => 'accept-edits',
  'bypass' || 'yolo' => 'bypass',
  _ => null,
};
