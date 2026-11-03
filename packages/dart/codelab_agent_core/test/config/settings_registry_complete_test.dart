import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart' show RecordingLogger;
// Схема валидатора — внутренняя (PKG-5 и `public_api_test`), но тест полноты
// обязан сверять реестр именно с ней, а не с копией.
import 'package:codelab_agent_core/src/config/schema.dart';
// `coveringDescriptors` — внутренняя функция реестра, не часть публичного API.
import 'package:codelab_agent_core/src/config/settings_registry.dart'
    show coveringDescriptors;
import 'package:collection/collection.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Ключи «только после перезапуска» (design.md change
/// `add-config-writer-and-reload`, D8, таблица перезапуска; R0-1, OQ5):
/// ключи хоста `sessions.*`, `logging.*` (в том числе `logging.level`),
/// `profile.*`, `config.*`, затем `secrets.backend` и ключи, ослабляющие
/// права, — `permissions.*`, `trusted_projects`.
///
/// Почему константа теста, а не вывод из реестра: пункт 6 сверяет признак
/// `restartRequired` реестра с внешним списком; список, построенный из самого
/// реестра, проверял бы реестр сам собой.
///
/// Ключи `config.*` (`config.watch`, `config.poll_interval`) добавила задача
/// 5.4 вместе со схемой: наблюдатель создаётся один раз (D7, D4,
/// «Порядок итераций»).
const restartKeyPatterns = [
  'sessions.*',
  'logging.*',
  'profile.*',
  'config.*',
  'secrets.backend',
  'permissions.*',
  'trusted_projects',
];

bool isRestartKey(String key) {
  for (final pattern in restartKeyPatterns) {
    if (pattern.endsWith('.*')) {
      final prefix = pattern.substring(0, pattern.length - 2);
      if (key == prefix || key.startsWith('$prefix.')) {
        return true;
      }
    } else if (key == pattern) {
      return true;
    }
  }
  return false;
}

/// Слои, в которые правила доверия §15.3 не пускают верхний раздел вовсе
/// (`trust.dart`: `trusted_projects` и `secrets` не читаются из проектных
/// слоёв, `sessions`, `logging`, `exec` — из слоя 3; `config.*` — из слоя 3,
/// D7 change `add-config-writer-and-reload`). Условные ограничения
/// («проект в `trusted_projects`») проверяет писатель, а не реестр.
const forbiddenLayers = <String, Set<ConfigLayer>>{
  'trusted_projects': {ConfigLayer.project, ConfigLayer.projectLocal},
  'secrets': {ConfigLayer.project, ConfigLayer.projectLocal},
  'sessions': {ConfigLayer.project},
  'logging': {ConfigLayer.project},
  'exec': {ConfigLayer.project},
  'config': {ConfigLayer.project},
};

/// Значения перечисления, которые схема хранит не в `allowed`, а проверяет
/// в `resolve.dart` (`secrets.backend`: текст `expected one of: auto,
/// keychain, env, file`) и в `configModeId` (`permissions.mode`).
const externalEnums = <String, List<String>>{
  'secrets.backend': ['auto', 'keychain', 'env', 'file'],
  'permissions.mode': ['plan', 'ask', 'standard', 'accept-edits', 'bypass'],
};

/// Листовые пути схемы; имена записей отображений — `*`.
///
/// `ObjectListNode` (`mcp.servers`) — лист: его поддерево покрывает
/// дескриптор `mapList`.
List<String> schemaLeaves(SectionNode section, [String prefix = '']) {
  String join(String name) => prefix.isEmpty ? name : '$prefix.$name';
  final out = <String>[];
  void visit(String path, SchemaNode node) {
    if (node is SectionNode) {
      out.addAll(schemaLeaves(node, path));
    } else {
      out.add(path);
    }
  }

  for (final MapEntry(:key, :value) in section.fields.entries) {
    visit(join(key), value);
  }
  if (section.named case final named?) {
    visit(join('*'), named);
  }
  return out;
}

/// Узел схемы по пути дескриптора (`*` — именованная запись).
SchemaNode? nodeAt(SectionNode root, String key) {
  SchemaNode? node = root;
  for (final segment in key.split('.')) {
    switch (node) {
      case SectionNode():
        node = node.fields[segment] ?? node.named;
      case ObjectListNode():
        node = node.item.fields[segment];
      case _:
        return null;
    }
    if (node == null) {
      return null;
    }
  }
  return node;
}

/// Какие типы реестра допустимы для узла схемы (пункт 3).
Set<SettingType> compatibleTypes(SchemaNode node) => switch (node) {
  ScalarNode(type: ScalarType.string) => {
    SettingType.string,
    SettingType.enumeration,
    SettingType.modelRef,
    SettingType.secretName,
    SettingType.envVarName,
  },
  ScalarNode(type: ScalarType.integer) => {SettingType.int},
  ScalarNode(type: ScalarType.float) => {SettingType.float},
  ScalarNode(type: ScalarType.boolean) => {SettingType.bool},
  ScalarNode(type: ScalarType.duration) => {SettingType.duration},
  ScalarNode(type: ScalarType.path) => {SettingType.path},
  ListNode(item: ScalarType.path) => {SettingType.pathList},
  ListNode() => {SettingType.stringList, SettingType.modelRefList},
  StringMapNode() => {SettingType.map},
  SectionNode() => {SettingType.map},
  OpaqueNode() => {SettingType.map},
  AgentsNode() => {SettingType.map},
  ProfileValueNode() => {SettingType.map},
  ObjectListNode() => {SettingType.mapList},
  ModeNode() => {SettingType.enumeration},
};

String _seconds(Duration d) => '${d.inSeconds}s';

/// Умолчания, которые можно узнать у настоящего разрешения конфигурации:
/// схема §15.4 этой сборки не хранит значений по умолчанию, их применяет
/// `resolve.dart`/`CoreConfig`/каталог моделей (D4; §17.5.8, п. 3). Ключ —
/// путь дескриптора (с `*`).
Map<String, Object?> resolvedDefaults() {
  final config = CoreConfig.fromLayers([
    layer(baseValues()),
  ], environment: const {}).config!;
  final provider = config.providers.single.config;
  // Каталог без встроенной таблицы: модель `p/m` без явных значений
  // получает безопасные умолчания.
  final model = StaticModelCatalog(
    config.providers,
    builtIn: const {},
    logger: RecordingLogger(),
  ).resolve(const ModelId('p/m'))!;
  return {
    'budget.max_steps': config.budget.maxSteps,
    'compaction.enabled': config.compaction.enabled,
    'agent.effort': config.effort.name,
    'tools.project_context.max_bytes': config.projectContextMaxBytes,
    'trusted_projects': config.trustedProjects,
    'permissions.deny': [
      for (final key in config.permissions.rules.denyPatterns) '$key',
    ],
    'providers.*.connect_timeout': _seconds(provider.timeouts.connect),
    'providers.*.idle_timeout': _seconds(provider.timeouts.idle),
    'providers.*.idle_timeout_reasoning': _seconds(
      provider.timeouts.idleReasoning,
    ),
    'providers.*.rate_limit_retries': provider.retry.rateLimitRetries,
    'providers.*.transient_retries': provider.retry.maxAttempts - 1,
    'providers.*.list_models': provider.listModels,
    'providers.*.models.*.image': model.supportsImages,
    'providers.*.models.*.reasoning': model.supportsReasoning,
  };
}

/// Ключи, чьё умолчание дескриптора взято только из §15.4 и которое ядро
/// само не применяет: ключ без потребителя в этой сборке (`_*U` в схеме),
/// список пустой в `resolve.dart` по отсутствию значения, умолчание хоста
/// (`HostSettings`: `logging.level` — `info`, `secrets.backend` — `auto`).
/// Дескриптор с умолчанием, которого нет ни в [resolvedDefaults], ни здесь,
/// роняет тест: новое умолчание обязано иметь источник проверки (§17.5.8,
/// п. 3).
const specOnlyDefaults = {
  'agent.fallback',
  'providers.*.list_models_include',
  'tools.disabled',
  'tools.untrusted_paths',
  'loop.empty_response_retries',
  'logging.level',
  'secrets.backend',
  // Умолчания применяет хост (`FileConfigSource`): `HostSettings` хранит
  // `null` для незаданного ключа (D7, §15.4).
  'config.watch',
  'config.poll_interval',
};

/// Допустим ли [value] в [key] для настоящего валидатора: `true` — проблем
/// на этом ключе нет.
bool validatorAccepts(String key, int value) {
  final concrete = key
      .replaceAll('*', 'p')
      .replaceFirst('p.models.p', 'p.models.m');
  Object? nested = value;
  for (final segment in concrete.split('.').reversed) {
    nested = {segment: nested};
  }
  final result = load([
    layer(withValues(baseValues(), nested! as Map<String, Object?>)),
  ]);
  return issuesAt(result, concrete).isEmpty;
}

/// Алгоритм §17.5.8, п. 1–7. Возвращает нарушения; пустой список — реестр
/// согласован со схемой. Параметры [descriptors] и [schema] позволяют
/// проверить сам тест на испорченных копиях (сценарии «Ключ схемы без
/// дескриптора» и «Расхождение умолчаний»).
List<String> verifyRegistry(
  List<SettingDescriptor> descriptors,
  SectionNode schema,
) {
  final problems = <String>[];
  final defaults = resolvedDefaults();

  // 1. Каждый лист схемы покрыт ровно одним дескриптором (после правила
  // «более конкретный побеждает»: дубликаты ключа — неоднозначность).
  final seen = <String>{};
  for (final d in descriptors) {
    if (!seen.add(d.key)) {
      problems.add('duplicate SettingDescriptor for ${d.key}');
    }
  }
  for (final leaf in schemaLeaves(schema)) {
    if (coveringDescriptors(descriptors, leaf, schemaPath: true).isEmpty) {
      problems.add(
        'config key $leaf has no SettingDescriptor: declare it shared or '
        'fileOnly with a reason',
      );
    }
  }

  for (final d in descriptors) {
    // 2–3. Путь есть в схеме; тип, перечисление, умолчание, границы.
    final node = nodeAt(schema, d.key);
    if (node == null) {
      problems.add('descriptor ${d.key} is not in the schema');
      continue;
    }
    if (!compatibleTypes(node).contains(d.type)) {
      problems.add(
        'descriptor ${d.key} has type ${d.type.name}, '
        'the schema node ${node.runtimeType} allows '
        '${compatibleTypes(node).map((t) => t.name).join(', ')}',
      );
    }
    final expectedEnum =
        externalEnums[d.key] ?? (node is ScalarNode ? node.allowed : null);
    if (expectedEnum != null &&
        !const ListEquality<String>().equals(d.enumValues, expectedEnum)) {
      problems.add(
        'descriptor ${d.key} enumValues ${d.enumValues} differ from '
        '$expectedEnum',
      );
    }
    if (d.type == SettingType.enumeration && (d.enumValues ?? []).isEmpty) {
      problems.add('descriptor ${d.key} is an enumeration without enumValues');
    }
    if (defaults.containsKey(d.key)) {
      if (!const DeepCollectionEquality().equals(
        d.defaultValue,
        defaults[d.key],
      )) {
        problems.add(
          'descriptor ${d.key} default ${d.defaultValue} differs from '
          'the validator default ${defaults[d.key]}',
        );
      }
    } else if (d.defaultValue != null && !specOnlyDefaults.contains(d.key)) {
      problems.add(
        'descriptor ${d.key} default ${d.defaultValue} has no source: add it '
        'to resolvedDefaults or to specOnlyDefaults with a reference to '
        '§15.4',
      );
    }
    if (d.type == SettingType.int) {
      // Граница, которой нет в дескрипторе, не должна быть в валидаторе:
      // без `min` принимается -1000000, без `max` — 1 << 40.
      final min = d.min;
      final max = d.max;
      if (min == null
          ? !validatorAccepts(d.key, -1000000)
          : !validatorAccepts(d.key, min.toInt()) ||
                validatorAccepts(d.key, min.toInt() - 1)) {
        problems.add('descriptor ${d.key} min $min differs from the validator');
      }
      if (max == null
          ? !validatorAccepts(d.key, 1 << 40)
          : !validatorAccepts(d.key, max.toInt()) ||
                validatorAccepts(d.key, max.toInt() + 1)) {
        problems.add('descriptor ${d.key} max $max differs from the validator');
      }
    }

    // Правило D4: `shared` — только ключ, у которого есть потребитель;
    // ключ без потребителя (`applied: false`) клиенты не редактируют.
    if (d.scope == SettingScope.shared && !node.applied) {
      problems.add(
        'descriptor ${d.key} is shared but the schema key is not applied: '
        'declare it fileOnly with the reason "not applied in this version"',
      );
    }

    // 4. fileOnly ⇔ причина; подписи не пусты.
    final hasReason = (d.fileOnlyReason ?? '').isNotEmpty;
    if ((d.scope == SettingScope.fileOnly) != hasReason) {
      problems.add('descriptor ${d.key}: fileOnly iff fileOnlyReason is set');
    }
    if (d.label.isEmpty || d.description.isEmpty) {
      problems.add('descriptor ${d.key} has an empty label or description');
    }

    // 6. Признак перезапуска.
    if (d.restartRequired != isRestartKey(d.key)) {
      problems.add(
        'descriptor ${d.key} restartRequired is '
        '${d.restartRequired}, the restart list says ${isRestartKey(d.key)}',
      );
    }

    // 7. Слои.
    final forbidden = forbiddenLayers[d.key.split('.').first] ?? const {};
    final bad = d.layers.intersection(forbidden);
    if (d.layers.isEmpty || bad.isNotEmpty) {
      problems.add(
        'descriptor ${d.key} layers ${d.layers.map((l) => l.name)} '
        'are not allowed by the trust rules',
      );
    }
  }

  // 5. Каждый ключ верхнего уровня покрыт.
  for (final top in schema.fields.keys) {
    final covered = descriptors.any(
      (d) =>
          d.key == top ||
          d.key.startsWith('$top.') ||
          coveringDescriptors([d], top).isNotEmpty,
    );
    if (!covered) {
      problems.add('top-level key $top is not covered by a descriptor');
    }
  }
  return problems;
}

SettingDescriptor copyOf(
  SettingDescriptor d, {
  Object? defaultValue,
  bool? restartRequired,
  Set<ConfigLayer>? layers,
  String? fileOnlyReason,
  SettingScope? scope,
  bool dropMin = false,
  bool dropMax = false,
}) => SettingDescriptor(
  key: d.key,
  type: d.type,
  defaultValue: defaultValue ?? d.defaultValue,
  scope: scope ?? d.scope,
  fileOnlyReason: fileOnlyReason ?? d.fileOnlyReason,
  section: d.section,
  label: d.label,
  description: d.description,
  secret: d.secret,
  restartRequired: restartRequired ?? d.restartRequired,
  enumValues: d.enumValues,
  min: dropMin ? null : d.min,
  max: dropMax ? null : d.max,
  layers: layers ?? d.layers,
);

SettingDescriptor byKey(String key) =>
    SettingsRegistry.all.singleWhere((d) => d.key == key);

SettingDescriptor synthetic(String key, {SettingType type = SettingType.map}) =>
    SettingDescriptor(
      key: key,
      type: type,
      scope: SettingScope.shared,
      section: 'Advanced',
      label: key,
      description: key,
      layers: const {ConfigLayer.user},
    );

/// E-15, CFG-19: реестр настроек согласован со схемой валидатора
/// (`core/settings-registry-complete`; agent-configuration «Реестр
/// настроек»; `agent-core-architecture` §17.5.8; design.md change
/// `add-config-writer-and-reload`, D4).
void main() {
  group('completeness against the validator schema', () {
    test('the registry of this build is consistent with rootSchema', () {
      expect(verifyRegistry(SettingsRegistry.all, rootSchema), isEmpty);
    });

    test('a schema key without a descriptor fails the check with the '
        'documented message', () {
      final budget = rootSchema.fields['budget']! as SectionNode;
      final extended = SectionNode({
        ...rootSchema.fields,
        'budget': SectionNode({
          ...budget.fields,
          'max_widgets': const ScalarNode(ScalarType.integer),
        }),
      });

      expect(verifyRegistry(SettingsRegistry.all, extended), [
        'config key budget.max_widgets has no SettingDescriptor: declare it '
            'shared or fileOnly with a reason',
      ]);
    });

    test('a new top-level section without a descriptor fails too', () {
      final extended = SectionNode({
        ...rootSchema.fields,
        'widgets': const SectionNode({'size': ScalarNode(ScalarType.integer)}),
      });

      final problems = verifyRegistry(SettingsRegistry.all, extended);

      expect(
        problems,
        contains(
          'config key widgets.size has no SettingDescriptor: declare it '
          'shared or fileOnly with a reason',
        ),
      );
      expect(
        problems,
        contains('top-level key widgets is not covered by a descriptor'),
      );
    });

    test('a descriptor whose default differs from the validator is named', () {
      final broken = [
        for (final d in SettingsRegistry.all)
          d.key == 'budget.max_steps' ? copyOf(d, defaultValue: 51) : d,
      ];

      final problems = verifyRegistry(broken, rootSchema);

      expect(problems, hasLength(1));
      expect(problems.single, contains('budget.max_steps'));
      expect(problems.single, contains('default'));
    });

    test('a descriptor outside the schema is reported', () {
      final extra = [...SettingsRegistry.all, synthetic('budget.ghost')];

      expect(
        verifyRegistry(extra, rootSchema),
        contains('descriptor budget.ghost is not in the schema'),
      );
    });

    test('two descriptors with one key are ambiguous', () {
      final twice = [...SettingsRegistry.all, byKey('budget.max_steps')];

      expect(
        verifyRegistry(twice, rootSchema),
        contains('duplicate SettingDescriptor for budget.max_steps'),
      );
    });

    test('fileOnly without a reason, and a reason without fileOnly, fail', () {
      final mutated = [
        for (final d in SettingsRegistry.all)
          if (d.key == 'exec')
            copyOf(d, fileOnlyReason: '')
          else if (d.key == 'budget.max_steps')
            copyOf(d, fileOnlyReason: 'because')
          else
            d,
      ];

      final problems = verifyRegistry(mutated, rootSchema);

      expect(problems.where((p) => p.contains('descriptor exec')), isNotEmpty);
      expect(
        problems.where((p) => p.contains('descriptor budget.max_steps')),
        isNotEmpty,
      );
    });

    test('restartRequired off for a restart key, and on for another, fail', () {
      final mutated = [
        for (final d in SettingsRegistry.all)
          if (d.key == 'permissions.mode')
            copyOf(d, restartRequired: false)
          else if (d.key == 'budget.max_steps')
            copyOf(d, restartRequired: true)
          else
            d,
      ];

      final problems = verifyRegistry(mutated, rootSchema);

      expect(problems, hasLength(2));
      expect(problems.join('\n'), contains('permissions.mode'));
      expect(problems.join('\n'), contains('budget.max_steps'));
    });

    test('dropping min of budget.max_steps fails: the validator rejects '
        'values below it', () {
      final mutated = [
        for (final d in SettingsRegistry.all)
          d.key == 'budget.max_steps' ? copyOf(d, dropMin: true) : d,
      ];

      expect(verifyRegistry(mutated, rootSchema), [
        'descriptor budget.max_steps min null differs from the validator',
      ]);
    });

    test('a max the validator does not enforce fails', () {
      final mutated = [
        for (final d in SettingsRegistry.all)
          d.key == 'tools.project_context.max_bytes'
              ? copyOf(d, dropMax: true)
              : d,
      ];

      expect(
        verifyRegistry(mutated, rootSchema).single,
        contains('tools.project_context.max_bytes max null'),
      );
    });

    test('a default without a source fails until it is declared', () {
      final mutated = [
        for (final d in SettingsRegistry.all)
          d.key == 'budget.max_tokens' ? copyOf(d, defaultValue: 5) : d,
      ];

      expect(
        verifyRegistry(mutated, rootSchema).single,
        contains('descriptor budget.max_tokens default 5 has no source'),
      );
    });

    test('the provider defaults are taken from the real resolution', () {
      final mutated = [
        for (final d in SettingsRegistry.all)
          d.key == 'providers.*.connect_timeout'
              ? copyOf(d, defaultValue: '31s')
              : d.key == 'providers.*.models.*.image'
              ? copyOf(d, defaultValue: true)
              : d,
      ];

      final problems = verifyRegistry(mutated, rootSchema);

      expect(problems, hasLength(2));
      expect(problems.join('\n'), contains('providers.*.connect_timeout'));
      expect(problems.join('\n'), contains('providers.*.models.*.image'));
    });

    test('a shared descriptor for a key nobody reads fails', () {
      final mutated = [
        for (final d in SettingsRegistry.all)
          d.key == 'agent.fallback'
              ? copyOf(d, scope: SettingScope.shared, fileOnlyReason: '')
              : d,
      ];

      expect(
        verifyRegistry(mutated, rootSchema).single,
        contains(
          'descriptor agent.fallback is shared but the schema key is '
          'not applied',
        ),
      );
    });

    test('keys without a consumer are fileOnly with the standard reason', () {
      for (final key in [
        'agent.fallback',
        'agent.summary_model',
        'permissions.timeout',
        'tools.disabled',
        'providers.*.list_models',
        'providers.*.list_models_include',
      ]) {
        final d = byKey(key);
        expect(d.scope, SettingScope.fileOnly, reason: key);
        expect(d.fileOnlyReason, 'not applied in this version', reason: key);
      }
    });

    test('a layer the trust rules forbid fails', () {
      final mutated = [
        for (final d in SettingsRegistry.all)
          d.key == 'trusted_projects'
              ? copyOf(d, layers: {ConfigLayer.user, ConfigLayer.project})
              : d,
      ];

      expect(
        verifyRegistry(mutated, rootSchema).single,
        contains('trusted_projects'),
      );
    });
  });

  group('restart keys (R0-1, D8)', () {
    test('permissions.*, trusted_projects, sessions, logging, profile and '
        'secrets.backend require a restart', () {
      for (final key in [
        'trusted_projects',
        'permissions.mode',
        'permissions.timeout',
        'permissions.deny',
        'permissions.tools',
        'sessions',
        'logging.level',
        'logging.file',
        'logging.trace',
        'profile',
        'secrets.backend',
      ]) {
        expect(byKey(key).restartRequired, isTrue, reason: key);
      }
    });

    test('mcp.servers, providers.* and budget.* apply live', () {
      for (final key in [
        'mcp.servers',
        'providers.*.kind',
        'providers.*.api_key_secret',
        'budget.max_steps',
        'agent.default_model',
        'compaction.enabled',
      ]) {
        expect(byKey(key).restartRequired, isFalse, reason: key);
      }
    });

    test('config.watch and config.poll_interval are fileOnly leaves that '
        'require a restart; the opaque config map is gone (D7, D4)', () {
      final watch = byKey('config.watch');
      final poll = byKey('config.poll_interval');

      expect(watch.type, SettingType.bool);
      expect(watch.defaultValue, true);
      expect(poll.type, SettingType.duration);
      expect(poll.defaultValue, '2s');
      for (final d in [watch, poll]) {
        expect(d.scope, SettingScope.fileOnly, reason: d.key);
        expect(d.restartRequired, isTrue, reason: d.key);
        expect(d.layers, {ConfigLayer.user, ConfigLayer.projectLocal});
      }
      expect(
        SettingsRegistry.all.where((d) => d.key == 'config'),
        isEmpty,
        reason: 'the section is covered by its leaves',
      );
    });
  });

  group('opaque after-MVP sections', () {
    test('every after-MVP section is one fileOnly map with the standard '
        'reason', () {
      for (final section in afterMvpSections) {
        final d = byKey(section);
        expect(d.type, SettingType.map, reason: section);
        expect(d.scope, SettingScope.fileOnly, reason: section);
        expect(
          d.fileOnlyReason,
          'not supported in this version; edit the file manually',
          reason: section,
        );
        expect(d.restartRequired, isFalse, reason: section);
      }
    });
  });

  group('lookup', () {
    test('a specific descriptor beats the wildcard and the section', () {
      final d = SettingsRegistry.lookup('providers.openai.api_key_secret');

      expect(d, isNotNull);
      expect(d!.key, 'providers.*.api_key_secret');
      expect(d.secret, isTrue);
      expect(d.type, SettingType.secretName);
    });

    test('a quoted model id is one segment', () {
      expect(
        SettingsRegistry.lookup(
          'providers.local.models."qwen2.5-coder-32b".context_window',
        )!.key,
        'providers.*.models.*.context_window',
      );
    });

    test('a mapList descriptor covers the elements of mcp.servers', () {
      expect(SettingsRegistry.lookup('mcp.servers')!.type, SettingType.mapList);
      expect(
        SettingsRegistry.lookup('mcp.servers[github]')!.key,
        'mcp.servers',
      );
      expect(
        SettingsRegistry.lookup(
          'mcp.servers[github].headers.Authorization',
        )!.key,
        'mcp.servers',
      );
    });

    test('a map descriptor covers its subtree', () {
      expect(SettingsRegistry.lookup('exec.env.PATH')!.key, 'exec');
      expect(
        SettingsRegistry.lookup('tools.web.search.backend')!.key,
        'tools.web',
      );
      expect(
        SettingsRegistry.lookup('permissions.tools.exec')!.key,
        'permissions.tools',
      );
    });

    test('a scalar descriptor does not cover a child key', () {
      expect(SettingsRegistry.lookup('budget.max_steps.extra'), isNull);
    });

    test('an unknown key has no descriptor', () {
      expect(SettingsRegistry.lookup('budget.max_widgets'), isNull);
      expect(SettingsRegistry.lookup('nonsense'), isNull);
    });

    test('covering orders candidates: exact literal, exact wildcard, then '
        'the deeper section', () {
      final set = [
        synthetic('plugins'),
        synthetic('plugins.*', type: SettingType.string),
        synthetic('plugins.enabled', type: SettingType.stringList),
      ];

      expect(coveringDescriptors(set, 'plugins.enabled').map((d) => d.key), [
        'plugins.enabled',
        'plugins.*',
        'plugins',
      ]);
      expect(coveringDescriptors(set, 'plugins.other').map((d) => d.key), [
        'plugins.*',
        'plugins',
      ]);
      expect(
        coveringDescriptors(set, 'plugins.enabled.deep').map((d) => d.key),
        ['plugins'],
      );
    });

    test('equal scores are ordered by key, whatever the input order', () {
      final a = synthetic('x.*.a', type: SettingType.string);
      final b = synthetic('x.b.*', type: SettingType.string);

      expect(coveringDescriptors([a, b], 'x.b.a').map((d) => d.key), [
        'x.*.a',
        'x.b.*',
      ]);
      expect(coveringDescriptors([b, a], 'x.b.a').map((d) => d.key), [
        'x.*.a',
        'x.b.*',
      ]);
    });

    test('malformed or hostile keys find nothing', () {
      for (final key in [
        'budget..max_steps',
        '.budget.max_steps',
        'budget.max_steps.',
        'budget."max_steps',
        'mcp.servers[github',
        'providers.*.kind',
        'providers.*.models.*.context_window',
        '*',
        'providers."*".kind',
        '',
      ]) {
        expect(SettingsRegistry.lookup(key), isNull, reason: key);
      }
    });

    test('the registry lists a descriptor once per key, in display order', () {
      final keys = [for (final d in SettingsRegistry.all) d.key];

      expect(keys.toSet(), hasLength(keys.length));
      expect(
        keys.indexOf('agent.default_model'),
        lessThan(keys.indexOf('budget.max_steps')),
      );
    });
  });

  group('parseCliValue', () {
    test('yes for a bool is a ConfigValueException that suggests true or '
        'false', () {
      final d = SettingsRegistry.lookup('compaction.enabled')!;

      expect(
        () => SettingsRegistry.parseCliValue(d, 'yes'),
        throwsA(
          isA<ConfigValueException>()
              .having((e) => e.key, 'key', 'compaction.enabled')
              .having((e) => e.expected, 'expected', contains('true or false')),
        ),
      );
    });

    test('a JSON array of strings parses for permissions.deny', () {
      final d = SettingsRegistry.lookup('permissions.deny')!;

      expect(SettingsRegistry.parseCliValue(d, '["exec:rm -rf *"]'), [
        'exec:rm -rf *',
      ]);
    });

    test('the error text never quotes the value', () {
      final d = SettingsRegistry.lookup('budget.max_steps')!;

      try {
        SettingsRegistry.parseCliValue(d, 'sk-live-0123456789');
        fail('expected ConfigValueException');
      } on ConfigValueException catch (e) {
        expect(e.toString(), isNot(contains('sk-live')));
        expect(e.expected, isNot(contains('sk-live')));
      }
    });
  });
}
