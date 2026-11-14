import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

/// Источник `skills.disabled` недоверенного проекта и сохранность файла при
/// записи (ревью итерации 2: MAJOR «источник skills.disabled недоверенного
/// проекта», LOW «запись сохраняет соседние ключи»; design.md change
/// `add-app-skills-page`, D5, Q43).
///
/// Почему отдельный файл: список недоверенного проекта объединяется с нижними
/// слоями, и итог часто совпадает со списком слоя `project` (user без ключа:
/// итог `[p]`; user `[p]` и project `[p]`). Снимок тогда называл источником
/// проект или файл `--config`, и любое действие давало ложный `NotEditable`.
/// Источник такого ключа должен определяться по значениям БЕЗ проектных слоёв
/// (`CoreConfig.withoutProjectValues`); `--config` — источник только если сам
/// задаёт ключ. Снимки строит настоящее хранилище на временных каталогах.
void main() {
  const key = 'skills.disabled';

  late Directory root;
  late String home;
  late String project;
  late String canonicalProject;

  void write(String path, String text) => File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  String userFile() => '$home/config.yaml';
  String projectFile() => '$canonicalProject/.codelab/config.yaml';
  String localFile() => '$canonicalProject/.codelab/config.local.yaml';

  const provider = '''
agent:
  default_model: p/m
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_env: LLM_TEST_KEY
    models:
      m:
        context_window: 32000
''';

  /// Недоверенный проект: `trusted_projects` не называет папку.
  void user({String extra = ''}) => write(userFile(), '$provider$extra');

  Future<FileAgentConfigStore> open({String? extraConfig}) async {
    final environment = {'HOME': root.path, 'CODELAB_HOME': home};
    return FileAgentConfigStore(
      paths: ConfigPaths(
        codelabHome: home,
        projectDir: project,
        extraConfig: extraConfig,
      ),
      environment: environment,
      secrets: await ClientSecretAccess.open(
        codelabHome: home,
        environment: environment,
        logger: RecordingLogger(),
      ),
      logger: RecordingLogger(),
    );
  }

  Future<AgentConfigSnapshot> load({String? extraConfig}) async =>
      (await open(extraConfig: extraConfig)).snapshot(cwd: project);

  SkillsListPlan plan(SkillsListEditResult result) {
    expect(result, isA<SkillsListPlan>(), reason: '$result');
    return result as SkillsListPlan;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('skills_list_untrusted_');
    home = '${root.path}/home';
    project = '${root.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    canonicalProject = Directory(project).resolveSymbolicLinksSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('(а) user без skills.disabled, проект выключает [p]', () {
    test('выключение x — SetValue([x]) в user, не NotEditable', () async {
      user();
      write(projectFile(), 'skills:\n  disabled: [p]\n');
      final snapshot = await load();

      final result = plan(skillsListEdit(snapshot, key, 'x', present: true));

      expect(result.layer, ConfigLayer.user);
      expect(result.edits, [
        const SetValue(key, ['x']),
      ]);
    });

    test('включение p — отказ disabledByProject с файлом проекта', () async {
      user();
      write(projectFile(), 'skills:\n  disabled: [p]\n');
      final snapshot = await load();

      final result = skillsListEdit(snapshot, key, 'p', present: false);

      expect(result, isA<SkillsListRefused>());
      final refusal = (result as SkillsListRefused).refusal;
      expect(refusal, isA<SkillsListDisabledByProject>());
      expect((refusal as SkillsListDisabledByProject).source, projectFile());
    });
  });

  group('(б) user [p] и project [p]: итог совпадает со слоем project', () {
    test('выключение x — [p, x] в user', () async {
      user(extra: 'skills:\n  disabled: [p]\n');
      write(projectFile(), 'skills:\n  disabled: [p]\n');
      final snapshot = await load();

      final result = plan(skillsListEdit(snapshot, key, 'x', present: true));

      expect(result.layer, ConfigLayer.user);
      expect(result.edits, [
        const SetValue(key, ['p', 'x']),
      ]);
    });

    test('включение p — всё равно disabledByProject: проект выключает его '
        'и без user', () async {
      user(extra: 'skills:\n  disabled: [p]\n');
      write(projectFile(), 'skills:\n  disabled: [p]\n');
      final snapshot = await load();

      final result = skillsListEdit(snapshot, key, 'p', present: false);

      expect(
        (result as SkillsListRefused).refusal,
        isA<SkillsListDisabledByProject>(),
      );
    });
  });

  group('(в) --config без skills.disabled не источник объединения', () {
    test('user без ключа, project [p], --config без skills: выключение x '
        '— план в user, не NotEditable(--config)', () async {
      user();
      write(projectFile(), 'skills:\n  disabled: [p]\n');
      final extra = '${root.path}/team.yaml';
      write(extra, 'logging:\n  level: info\n');
      final snapshot = await load(extraConfig: extra);

      final result = plan(skillsListEdit(snapshot, key, 'x', present: true));

      expect(result.layer, ConfigLayer.user);
      expect(result.edits, [
        const SetValue(key, ['x']),
      ]);
    });

    test('--config сам задаёт skills.disabled: он действующий источник — '
        'NotEditable с его путём', () async {
      user();
      write(projectFile(), 'skills:\n  disabled: [p]\n');
      final extra = '${root.path}/team.yaml';
      write(extra, 'skills:\n  disabled: [t]\n');
      final snapshot = await load(extraConfig: extra);

      final result = skillsListEdit(snapshot, key, 'x', present: true);

      expect(
        ((result as SkillsListRefused).refusal as SkillsListNotEditable).source,
        extra,
      );
    });
  });

  group('слой projectLocal недоверенного проекта тоже объединяется', () {
    test('config.local.yaml выключает q: включить нельзя (отказ с файлом '
        'слоя), выключить x — user', () async {
      user();
      write(localFile(), 'skills:\n  disabled: [q]\n');
      final snapshot = await load();

      final off = plan(skillsListEdit(snapshot, key, 'x', present: true));
      final on = skillsListEdit(snapshot, key, 'q', present: false);

      expect(off.layer, ConfigLayer.user);
      expect(
        ((on as SkillsListRefused).refusal as SkillsListDisabledByProject)
            .source,
        localFile(),
      );
    });
  });

  test('запись skills.disabled в user сохраняет соседние ключи файла: '
      'провайдера, api_key_env, trusted_projects и комментарий', () async {
    write(
      userFile(),
      '# keep this comment\n$provider'
      'trusted_projects: [${root.path}/elsewhere]\n',
    );
    final store = await open();
    final snapshot = await store.snapshot(cwd: project);
    final result = plan(skillsListEdit(snapshot, key, 'x', present: true));

    final outcome = await store.apply(result.base, result.edits);

    expect(outcome, isA<ConfigSaved>());
    final text = File(userFile()).readAsStringSync();
    expect(text, contains('# keep this comment'));
    expect(text, contains('api_key_env: LLM_TEST_KEY'));
    expect(text, contains('base_url: https://llm.test/v1'));
    expect(text, contains('trusted_projects'));
    expect(text, contains('elsewhere'));
    expect(text, contains('disabled'));
  });
}
