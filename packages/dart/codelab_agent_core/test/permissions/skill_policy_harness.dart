import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:codelab_agent_core/src/tools/builtin/write.dart';
import 'package:test/test.dart';

import '../env/resolving_env.dart';
import '../tools/executor_harness.dart';
import 'fake_gate.dart';
import 'policy_harness.dart';

/// Общая оснастка тестов PERM-11 для навыков (задача 2.7 change
/// `add-agent-skills`; agent-permissions «Критические пути правок
/// конфигурации агента», D9, решения Q24–Q38).
///
/// Фиксируемый API ядра (красное состояние — ошибка компиляции):
/// `AgentConfigPaths(skillDirs: …)` — канонические каталоги загруженных
/// навыков сессии (для E1–E3) и `AgentConfigPaths.withSession({paths,
/// skillDirs})` — копия с добавленными путями сессии (Q27).
const workDir = '/work/demo';
const userHome = '/home/u';
const codelabHome = '/home/u/.codelab';
const agentsRoot = '/home/u/.agents/skills';
const codelabRoot = '/home/u/.codelab/skills';

/// Навык пользователя в `~/.agents/skills` — основной в сценариях E1–E3.
const pdf = '$agentsRoot/pdf';

/// Другой навык того же корня: ресурс «чужого» навыка.
const notes = '$agentsRoot/notes';

/// Навыки `$CODELAB_HOME/skills` (сценарии «Скрипт навыка по абсолютному
/// пути из рабочей папки», «Пишущие команды на существующий файл»).
const releaseNotes = '$codelabRoot/release-notes';
const codelabPdf = '$codelabRoot/pdf';

/// Навык проекта у `cwd` (сценарий «Скрипт навыка не критичен»).
const projectPdf = '$workDir/.codelab/skills/pdf';

/// Метка шаблона `write to agent configuration` (§7.6): у `find . -delete`
/// рядом стоит и метка удаления, поэтому причина проверяется по вхождению.
const criticalLabel = 'write to agent configuration';

/// Причина вопроса для критической команды `exec` (§7.6).
const criticalReason = 'critical command: write to agent configuration';

/// Файлы навыка, которые нужны сценариям: `SKILL.md`, скрипты (в том числе
/// под запретными сегментами), `assets/`, `references/`, исполняемые файлы
/// вне `scripts/`.
const skillFiles = [
  'SKILL.md',
  'scripts/fill.py',
  'scripts/extract.py',
  'scripts/x.py',
  'scripts/x.js',
  'scripts/x.sh',
  'scripts/x.rb',
  'scripts/x.pl',
  'scripts/x.ts',
  'scripts/fill.ps1',
  'scripts/bin/tsx',
  'scripts/bin/python3',
  'scripts/bin/deno',
  'scripts/bin/bun',
  'scripts/bin/uv',
  'scripts/bin/pipx',
  'scripts/run.sh',
  'scripts/lib/tool.py',
  'scripts/sub/inner.py',
  'scripts/SKILL.md',
  'scripts/.hidden/x.py',
  'scripts/vendor/x.py',
  'scripts/site-packages/x.py',
  'scripts/node_modules/x.js',
  'scripts/node_modules/.bin/prettier',
  'assets/schema.json',
  'assets/a.json',
  'assets/a.png',
  'assets/b.md',
  'assets/sub/c.json',
  'references/a.md',
  'references/FORMS.md',
  'node_modules/.bin/shx',
  '.venv/bin/pip',
];

/// Настройки хоста: корни навыков — пути от хоста, каталоги загруженных
/// навыков — для исключений E1–E3.
AgentConfigPaths skillConfig({
  bool caseInsensitive = false,
  List<String> extraPaths = const [],
}) => AgentConfigPaths(
  paths: [
    '$codelabHome/config.yaml',
    codelabRoot,
    agentsRoot,
    '/opt/team/skills',
    ...extraPaths,
  ],
  skillDirs: [pdf, notes, releaseNotes, codelabPdf, projectPdf],
  expansions: {'HOME': userHome, 'CODELAB_HOME': codelabHome},
  caseInsensitive: caseInsensitive,
);

/// Политика над памятью с навыками. [critical] отвечает: `exec` спросил
/// человека как критический шаблон (без `allow_always`).
final class SkillHarness {
  SkillHarness._(this.p, this.env, this.gate);

  static Future<SkillHarness> create({
    ModeId mode = ModeId.bypass,
    PermissionMode? modeOverride,
    AgentConfigPaths? config,
    Map<String, String> links = const {},
    bool withGate = true,
    String cwd = workDir,
  }) async {
    final memory = MemoryExecutionEnv(cwd: cwd);
    for (final dir in [pdf, notes, releaseNotes, codelabPdf, projectPdf]) {
      for (final file in skillFiles) {
        await memory.writeText('$dir/$file', 'old\n');
      }
    }
    await memory.writeText('$workDir/tool.py', 'print(1)\n');
    await memory.writeText('$workDir/a.pdf', 'pdf');
    await memory.writeText('/bin/cp', 'binary');
    final env = ResolvingEnv(memory, links: links);
    final h = await ExecutorHarness.create([
      ReadTool(),
      WriteTool(),
      EditTool(),
      ExecTool(),
    ], base: env);
    final gate = withGate ? FakeGate() : null;
    final p = await PolicyHarness.wrap(
      h,
      mode: mode,
      modeOverride: modeOverride,
      gate: gate,
      agentConfigPaths: config ?? skillConfig(),
      pathResolver: env,
    );
    return SkillHarness._(p, env, gate ?? FakeGate());
  }

  final PolicyHarness p;
  final ResolvingEnv env;
  final FakeGate gate;
  var _n = 0;

  /// Вызывает `exec` и возвращает исход; вопросы gate копятся в [gate].
  Future<ToolExecutionOutcome> exec(String command, {String? cwd}) =>
      p.run('exec', {'command': command, 'cwd': ?cwd}, id: 'x${_n++}');

  /// Команда — критический шаблон: gate спросил один раз, причина содержит
  /// [criticalLabel] (рядом могут стоять другие метки), без `allow_always`.
  Future<bool> critical(String command, {String? cwd}) async {
    gate.requests.clear();
    await exec(command, cwd: cwd);
    return gate.requests.length == 1 &&
        (gate.requests.single.reason?.contains(criticalLabel) ?? false) &&
        !gate.requests.single.allowAlwaysOffered;
  }

  /// Команда критична по любому шаблону §7.6 (не только PERM-11).
  Future<bool> criticalAny(String command, {String? cwd}) async {
    gate.requests.clear();
    await exec(command, cwd: cwd);
    return gate.requests.length == 1 &&
        (gate.requests.single.reason?.startsWith('critical command') ??
            false) &&
        !gate.requests.single.allowAlwaysOffered;
  }

  /// Команда не критична: в `bypass` gate не спрошен.
  Future<bool> ordinary(String command, {String? cwd}) async {
    gate.requests.clear();
    await exec(command, cwd: cwd);
    return gate.requests.isEmpty;
  }

  Future<void> expectCritical(Iterable<String> commands, {String? cwd}) async {
    for (final command in commands) {
      expect(await critical(command, cwd: cwd), isTrue, reason: command);
    }
  }

  Future<void> expectOrdinary(Iterable<String> commands, {String? cwd}) async {
    for (final command in commands) {
      expect(await ordinary(command, cwd: cwd), isTrue, reason: command);
    }
  }
}
