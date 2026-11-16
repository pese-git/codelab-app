import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        CoreConfig,
        ModeId,
        ModelRef,
        PermissionsConfig,
        ProviderApi,
        ReasoningEffort,
        ToolTier;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

/// Умолчания новой сессии в мосте (client-agent-setup «Умолчания новой сессии
/// в мосте»; design.md change `add-settings-agents-modes`, D4, D6; SETUP-8):
/// итог берётся из разобранного `loaded.config`, а не из сырых листьев;
/// источник — `originOf`; сужение — предупреждение
/// `config.project.untrusted_key`; цель записи — слой источника режима.
void main() {
  const cwd = '/work/project';
  const home = '/h';
  const backend = SecretBackendInfo(id: 'file', writable: true);
  const withFolder = EditableSettings(
    ConfigPaths(codelabHome: home, projectDir: cwd),
  );
  const withoutFolder = EditableSettings(ConfigPaths(codelabHome: home));

  /// Итог загрузки: `defaultModel` обязателен у ядра, но к режиму и effort
  /// отношения не имеет.
  CoreConfig coreConfig({
    PermissionsConfig permissions = const PermissionsConfig(),
    ReasoningEffort effort = ReasoningEffort.medium,
  }) => CoreConfig(
    defaultModel: ModelRef(
      provider: 'test',
      id: 'model-1',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://localhost:8080/v1'),
      contextWindow: 32000,
      maxOutputTokens: 4096,
    ),
    permissions: permissions,
    effort: effort,
  );

  /// Снимок: [user] и [local] — листья слоёв; [config] — итог загрузки
  /// (разбор ядра), [values] — плоские итоговые листья, как у загрузчика.
  AgentConfigSnapshot snapshotOf({
    Map<String, Object?> user = const {},
    Map<String, Object?>? local,
    Map<String, Object?>? project,
    required CoreConfig config,
    Map<String, Object?> values = const {},
    bool narrowedKey = false,
  }) => AgentConfigSnapshot.fromLayers(
    cwd: cwd,
    layers: {
      ConfigLayer.user: ConfigSnapshot(
        target: const ConfigTarget.user(),
        path: '$home/config.yaml',
        fingerprint: 'fp-user',
        values: user,
      ),
      if (project != null)
        ConfigLayer.project: ConfigSnapshot(
          target: const ConfigTarget.project(cwd),
          path: '$cwd/.codelab/config.yaml',
          fingerprint: 'fp-project',
          values: project,
        ),
      if (local != null)
        ConfigLayer.projectLocal: ConfigSnapshot(
          target: const ConfigTarget.projectLocal(cwd),
          path: '$cwd/.codelab/config.local.yaml',
          fingerprint: 'fp-local',
          values: local,
        ),
    },
    loaded: ConfigLoadResult(
      config: config,
      values: values,
      warnings: [
        if (narrowedKey)
          const ConfigIssue(
            kind: ConfigIssueKind.semantic,
            key: 'permissions.mode',
            source: '$cwd/.codelab/config.local.yaml',
            message: 'ignored: the project is not in trusted_projects',
            event: 'config.project.untrusted_key',
          ),
      ],
    ),
    secrets: backend,
  );

  const userSource = ConfigSourceView(
    kind: ConfigSourceKind.user,
    label: '$home/config.yaml',
  );
  const localSource = ConfigSourceView(
    kind: ConfigSourceKind.projectLocal,
    label: '$cwd/.codelab/config.local.yaml',
  );

  group('Псевдоним и источник', () {
    test('acceptEdits в слое user даёт accept-edits, effort — default', () {
      final snapshot = snapshotOf(
        user: {
          'permissions': {'mode': 'acceptEdits'},
        },
        config: coreConfig(
          permissions: PermissionsConfig(mode: ModeId.acceptEdits),
        ),
        values: {'permissions.mode': 'acceptEdits'},
      );

      final view = sessionDefaultsOf(snapshot, withFolder);

      expect(view.mode.id, 'accept-edits');
      expect(view.mode.source, userSource);
      expect(view.mode.narrowedByProject, isFalse);
      expect(view.mode.blocksWriteAndExec, isFalse);
      expect(view.effort.id, 'medium');
      expect(view.effort.source, isNull, reason: 'листа нет — default');
    });

    test('без листов режим standard, источник default', () {
      final snapshot = snapshotOf(config: coreConfig());

      final view = sessionDefaultsOf(snapshot, withFolder);

      expect(view.mode.id, 'standard');
      expect(view.mode.source, isNull);
      expect(view.effort.id, 'medium');
    });

    test('effort high из слоя user берёт значение и источник', () {
      final snapshot = snapshotOf(
        user: {
          'agent': {'effort': 'high'},
        },
        config: coreConfig(effort: ReasoningEffort.high),
        values: {'agent.effort': 'high'},
      );

      final view = sessionDefaultsOf(snapshot, withFolder);

      expect(view.effort.id, 'high');
      expect(view.effort.source, userSource);
    });
  });

  group('Сужение проектом', () {
    test('недоверенный проект с bypass: итог standard, признак сужения', () {
      final snapshot = snapshotOf(
        user: {
          'permissions': {'mode': 'standard'},
        },
        local: {
          'permissions': {'mode': 'bypass'},
        },
        config: coreConfig(
          permissions: PermissionsConfig(mode: ModeId.standard),
        ),
        values: {'permissions.mode': 'standard'},
        narrowedKey: true,
      );

      final view = sessionDefaultsOf(snapshot, withFolder);

      expect(view.mode.id, 'standard');
      expect(view.mode.narrowedByProject, isTrue);
      expect(
        view.mode.source,
        userSource,
        reason: 'проектный bypass проигнорирован — он не источник',
      );
    });

    test('предупреждение про другой ключ не считается сужением режима', () {
      final snapshot = snapshotOf(config: coreConfig(), narrowedKey: false);

      expect(
        sessionDefaultsOf(snapshot, withFolder).mode.narrowedByProject,
        isFalse,
      );
    });
  });

  group('Сочетание ask и plan', () {
    test('итог ask с запретом write и exec', () {
      final snapshot = snapshotOf(
        user: {
          'permissions': {'mode': 'ask'},
        },
        local: {
          'permissions': {'mode': 'plan'},
        },
        config: coreConfig(
          permissions: PermissionsConfig(
            mode: ModeId.ask,
            extraDeniedTiers: {ToolTier.write, ToolTier.exec},
          ),
        ),
        values: {'permissions.mode': 'ask+plan'},
        narrowedKey: true,
      );

      final view = sessionDefaultsOf(snapshot, withFolder);

      expect(view.mode.id, 'ask');
      expect(view.mode.blocksWriteAndExec, isTrue);
    });

    test('чистый ask без запретов уровней', () {
      final snapshot = snapshotOf(
        user: {
          'permissions': {'mode': 'ask'},
        },
        config: coreConfig(permissions: PermissionsConfig(mode: ModeId.ask)),
        values: {'permissions.mode': 'ask'},
      );

      expect(
        sessionDefaultsOf(snapshot, withFolder).mode.blocksWriteAndExec,
        isFalse,
      );
    });
  });

  group('Цель записи', () {
    test('источник user — цель user', () {
      final snapshot = snapshotOf(
        user: {
          'permissions': {'mode': 'ask'},
        },
        config: coreConfig(permissions: PermissionsConfig(mode: ModeId.ask)),
        values: {'permissions.mode': 'ask'},
      );

      expect(
        sessionDefaultsOf(snapshot, withFolder).suggestedTarget,
        ConfigLayer.user,
      );
    });

    test('источник projectLocal с папкой — цель projectLocal', () {
      final snapshot = snapshotOf(
        local: {
          'permissions': {'mode': 'accept-edits'},
        },
        config: coreConfig(
          permissions: PermissionsConfig(mode: ModeId.acceptEdits),
        ),
        values: {'permissions.mode': 'accept-edits'},
      );

      final view = sessionDefaultsOf(snapshot, withFolder);

      expect(view.mode.source, localSource);
      expect(view.suggestedTarget, ConfigLayer.projectLocal);
    });

    test('источник projectLocal без папки — цель user', () {
      final snapshot = snapshotOf(
        local: {
          'permissions': {'mode': 'accept-edits'},
        },
        config: coreConfig(
          permissions: PermissionsConfig(mode: ModeId.acceptEdits),
        ),
        values: {'permissions.mode': 'accept-edits'},
      );

      expect(
        sessionDefaultsOf(snapshot, withoutFolder).suggestedTarget,
        ConfigLayer.user,
      );
    });

    test('источник project (только чтение) — цель user', () {
      final snapshot = snapshotOf(
        project: {
          'permissions': {'mode': 'ask'},
        },
        config: coreConfig(permissions: PermissionsConfig(mode: ModeId.ask)),
        values: {'permissions.mode': 'ask'},
      );

      expect(
        sessionDefaultsOf(snapshot, withFolder).suggestedTarget,
        ConfigLayer.user,
      );
    });

    test('листа нет — цель user', () {
      final snapshot = snapshotOf(config: coreConfig());

      expect(
        sessionDefaultsOf(snapshot, withFolder).suggestedTarget,
        ConfigLayer.user,
      );
    });
  });
}
