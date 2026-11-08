import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

/// `AgentConfigSnapshot.rejections` (решение Q30 (в), design.md change
/// `add-provider-setup-ui`, D11, Q26): проблемы, из-за которых агент отклонит
/// конфиг, — виды `value`, `semantic`, `inlineSecret`, включая незаданную
/// переменную `${VAR}` в `env` MCP-сервера. Не входят: `config.model.none`
/// (`agent.default_model`, D26) и прочие стартовые проблемы, а также
/// синтаксис, `profile`, `unknownKey` и `type` (они остаются в `issues` и
/// блокируют запись). `issues` и `startProblems` не меняются — страница
/// Providers ведёт себя как раньше.
///
/// Ожидаемый API (задача 5.8b): геттер `List<ConfigIssue> get rejections`.
void main() {
  const file = '/h/config.yaml';

  const unsetVariable = ConfigIssue(
    kind: ConfigIssueKind.value,
    key: 'mcp.servers[postgres].env.DATABASE_URL',
    source: file,
    message: 'variable is not set',
    event: 'config.variable.unset',
  );
  const modelNone = ConfigIssue(
    kind: ConfigIssueKind.value,
    key: 'agent.default_model',
    source: file,
    message: 'required',
    event: 'config.model.none',
  );
  const badValue = ConfigIssue(
    kind: ConfigIssueKind.value,
    key: 'budget.max_steps',
    source: file,
    message: 'must be positive',
  );
  const semantic = ConfigIssue(
    kind: ConfigIssueKind.semantic,
    key: 'agent.default_model',
    source: file,
    message: 'unknown provider',
  );
  const inlineSecret = ConfigIssue(
    kind: ConfigIssueKind.inlineSecret,
    key: 'providers.p.api_key',
    source: 'env',
    message: 'secret as a value',
  );
  const syntax = ConfigIssue(
    kind: ConfigIssueKind.syntax,
    key: '',
    source: file,
    message: 'bad yaml',
  );
  const unknownKey = ConfigIssue(
    kind: ConfigIssueKind.unknownKey,
    key: 'nope',
    source: file,
    message: 'unknown key',
  );
  const typeIssue = ConfigIssue(
    kind: ConfigIssueKind.type,
    key: 'budget.max_steps',
    source: file,
    message: 'expected int',
  );

  AgentConfigSnapshot snapshotWith(List<ConfigIssue> issues) =>
      AgentConfigSnapshot.fromLayers(
        cwd: '/work/project',
        layers: {
          ConfigLayer.user: ConfigSnapshot(
            target: const ConfigTarget.user(),
            path: file,
            fingerprint: 'fp',
            values: const {
              'budget': {'max_steps': 0},
            },
          ),
        },
        loaded: ConfigLoadResult(issues: issues),
        secrets: const SecretBackendInfo(id: 'file', writable: true),
      );

  test('незаданная \${PG_URL} в env MCP-сервера: в rejections, не в issues '
      '(остаётся в startProblems, как сейчас)', () {
    final snapshot = snapshotWith([unsetVariable]);

    expect(snapshot.rejections, [unsetVariable]);
    expect(snapshot.issues, isEmpty);
    expect(snapshot.startProblems, [unsetVariable]);
  });

  test('config.model.none (agent.default_model, D26) не в rejections, '
      'остаётся в startProblems', () {
    final snapshot = snapshotWith([modelNone]);

    expect(snapshot.rejections, isEmpty);
    expect(snapshot.startProblems, [modelNone]);
    expect(snapshot.issues, isEmpty);
  });

  test('value существующего ключа, semantic и inlineSecret — в rejections '
      'и в issues', () {
    final snapshot = snapshotWith([badValue, semantic, inlineSecret]);

    expect(snapshot.rejections, [badValue, semantic, inlineSecret]);
    expect(snapshot.issues, [badValue, semantic, inlineSecret]);
    expect(snapshot.startProblems, isEmpty);
  });

  test('синтаксис, unknownKey и type — в issues и не в rejections', () {
    final snapshot = snapshotWith([syntax, unknownKey, typeIssue]);

    expect(snapshot.rejections, isEmpty);
    expect(snapshot.issues, [syntax, unknownKey, typeIssue]);
  });

  test('смесь: rejections сохраняет порядок загрузчика и отбрасывает '
      'model.none и блокирующие виды', () {
    final snapshot = snapshotWith([
      syntax,
      modelNone,
      unsetVariable,
      typeIssue,
      semantic,
    ]);

    expect(snapshot.rejections, [unsetVariable, semantic]);
  });

  test('регрессия Providers: issues и startProblems прежние для любого '
      'набора', () {
    final snapshot = snapshotWith([
      syntax,
      modelNone,
      unsetVariable,
      badValue,
      unknownKey,
    ]);

    expect(snapshot.issues, [syntax, badValue, unknownKey]);
    expect(snapshot.startProblems, [modelNone, unsetVariable]);
  });

  test('чистая загрузка: rejections пуст', () {
    expect(snapshotWith(const []).rejections, isEmpty);
  });
}
