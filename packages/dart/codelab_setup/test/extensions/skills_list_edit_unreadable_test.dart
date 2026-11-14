import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

/// Слой без снимка в `skillsListEdit` (ревью итерации 2, NIT «слой без
/// снимка — отдельная причина»; design.md change `add-app-skills-page`, D5).
///
/// Почему: файл слоя с битым YAML остаётся вне `AgentConfigSnapshot.layers`
/// (`FileAgentConfigStore`). Писать в него небезопасно, но это не «слой
/// назначен не редактируемым», и подсказка у него другая: файл нужно
/// исправить. Поэтому причина отдельная: `SkillsListLayerUnreadable(layer)`.
void main() {
  AgentConfigSnapshot snapshotWithout(ConfigLayer missing) =>
      AgentConfigSnapshot.fromLayers(
        cwd: '/work',
        layers: {
          if (missing != ConfigLayer.user)
            ConfigLayer.user: ConfigSnapshot(
              target: const ConfigTarget.user(),
              path: '/h/config.yaml',
              fingerprint: 'fp',
              values: const {},
            ),
          if (missing != ConfigLayer.projectLocal)
            ConfigLayer.projectLocal: ConfigSnapshot(
              target: const ConfigTarget.projectLocal('/work'),
              path: '/work/.codelab/config.local.yaml',
              fingerprint: 'fp-l',
              values: const {
                'skills': {
                  'disabled': ['a'],
                },
              },
            ),
        },
        loaded: const ConfigLoadResult(),
        secrets: const SecretBackendInfo(id: 'file', writable: true),
      );

  test('слой user без снимка: отказ LayerUnreadable(user), не NotEditable', () {
    // Ключа нет нигде, слой user (цель по умолчанию) не прочитан.
    final result = skillsListEdit(
      AgentConfigSnapshot.fromLayers(
        cwd: '/work',
        layers: const {},
        loaded: const ConfigLoadResult(),
        secrets: const SecretBackendInfo(id: 'file', writable: true),
      ),
      'skills.disabled',
      'x',
      present: true,
    );

    final refusal = (result as SkillsListRefused).refusal;
    expect(refusal, isA<SkillsListLayerUnreadable>());
    expect((refusal as SkillsListLayerUnreadable).layer, ConfigLayer.user);
  });

  test('действующий слой projectLocal без снимка: отказ '
      'LayerUnreadable(projectLocal)', () {
    // Значение слоя действует (ключ в итоге есть), но файл не прочитан.
    final snapshot = AgentConfigSnapshot.fromLayers(
      cwd: '/work',
      layers: {
        ConfigLayer.user: ConfigSnapshot(
          target: const ConfigTarget.user(),
          path: '/h/config.yaml',
          fingerprint: 'fp',
          values: const {},
        ),
      },
      loaded: const ConfigLoadResult(
        values: {
          'skills.disabled': ['a'],
        },
      ),
      secrets: const SecretBackendInfo(id: 'file', writable: true),
      externalOrigin: (key) => const ConfigSourceView(
        kind: ConfigSourceKind.projectLocal,
        label: '/work/.codelab/config.local.yaml',
      ),
    );

    final result = skillsListEdit(
      snapshot,
      'skills.disabled',
      'x',
      present: true,
    );

    expect(
      ((result as SkillsListRefused).refusal as SkillsListLayerUnreadable)
          .layer,
      ConfigLayer.projectLocal,
    );
  });

  test('читаемые слои — как раньше: план, а не отказ', () {
    final result = skillsListEdit(
      snapshotWithout(ConfigLayer.project),
      'skills.disabled',
      'b',
      present: true,
    );

    expect(result, isA<SkillsListPlan>());
    expect((result as SkillsListPlan).layer, ConfigLayer.projectLocal);
    expect(result.edits, [
      const SetValue('skills.disabled', ['a', 'b']),
    ]);
  });
}
