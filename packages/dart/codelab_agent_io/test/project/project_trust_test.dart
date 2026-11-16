import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Правило доверия к папке проекта: одно для `config check` и моста
/// `codelab_setup` (design.md change `add-settings-agents-modes`, D7; SETUP-8;
/// CFG-3, D4 change `add-agent-project-files`). Fail-closed: путь, который не
/// разрешился, недоверенный.
void main() {
  late String base;
  late String repo;

  setUp(() {
    final tmp = Directory.systemTemp.createTempSync('project_trust_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    base = tmp.resolveSymbolicLinksSync();
    repo = '$base/repo';
    Directory(repo).createSync(recursive: true);
  });

  CoreConfig config(List<String> trusted) => CoreConfig(
    defaultModel: ModelRef(
      provider: 'test',
      id: 'model-1',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://localhost:8080/v1'),
      contextWindow: 32000,
      maxOutputTokens: 4096,
    ),
    trustedProjects: trusted,
  );

  test('папка из trusted_projects доверенная, cwd канонический', () async {
    final trust = await projectTrustAt(
      config: config([repo]),
      folder: repo,
      environment: const {},
    );

    expect(trust.cwd, repo);
    expect(trust.trusted, isTrue);
  });

  test('папка вне trusted_projects недоверенная', () async {
    final trust = await projectTrustAt(
      config: config(const []),
      folder: repo,
      environment: const {},
    );

    expect(trust.trusted, isFalse);
  });

  test(
    'symlink на доверенную папку даёт канонический путь и доверие',
    () async {
      Link('$base/link').createSync(repo);

      final trust = await projectTrustAt(
        config: config([repo]),
        folder: '$base/link',
        environment: const {},
      );

      expect(trust.cwd, repo);
      expect(trust.trusted, isTrue);
    },
  );

  test('несуществующая папка недоверенная (fail-closed)', () async {
    final trust = await projectTrustAt(
      config: config([repo]),
      folder: '$base/missing',
      environment: const {},
    );

    expect(trust.trusted, isFalse);
  });
}
