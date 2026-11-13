import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent/codelab_agent.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import 'build_host.dart';
import 'client_acp_peer.dart';

/// Шаг сценария модели: вызов инструмента.
Map<String, Object?> callJson(
  String id,
  String name,
  Map<String, Object?> arguments,
) => {
  'reply': [
    {
      'toolCall': {'id': id, 'name': name, 'arguments': arguments},
    },
  ],
  'stopReason': 'toolUse',
};

/// Шаг сценария модели: текст и конец хода.
Map<String, Object?> textJson(String text) => {
  'reply': [
    {'text': text},
  ],
  'stopReason': 'stop',
};

/// Тексты результатов инструментов последнего запроса к модели: пары
/// «ошибка ли» и текст, по порядку вызовов.
List<({bool isError, String text})> toolResultsOf(LlmContext context) => [
  for (final m in context.messages.whereType<ToolResultMessage>())
    (
      isError: m.isError,
      text: [
        for (final b in m.content.whereType<TextContent>()) b.text,
      ].join('\n'),
    ),
];

/// Временные каталоги и хост `codelab-agent` для тестов навыков хостов
/// (change `add-agent-skills`, итерация 5; design.md D3).
///
/// Почему: каждому тесту нужны изолированные `CODELAB_HOME` (конфиг с
/// провайдером `p/m`), домашний каталог пользователя (`HOME` — только в
/// словаре окружения хоста, настоящий `HOME` процесса не читается) и папка
/// проекта. Ключ провайдера — фейковая переменная `LLM_KEY`.
///
/// Как использовать: `final rig = await SkillsRig.create(trusted: true)`;
/// `rig.writeSkill(rig.codelabSkills, 'notes')` кладёт навык;
/// `rig.startHost([...])` собирает [AgentHost] с моделью-сценарием
/// (`modelsFor`) и запоминает контексты запросов в [contexts]; `rig.acp(host)`
/// даёт ACP-клиента, обслуживающего запросы агента. Всё удаляется в
/// `addTearDown`.
final class SkillsRig {
  SkillsRig._(this.temp, {required this.project});

  final Directory temp;

  /// Канонический (`realpath`) корень проекта; сессии открываются в нём.
  final String project;

  String get home => '${temp.path}/home';
  String get userHome => '${temp.path}/userhome';

  /// Каталог навыков пользователя `$CODELAB_HOME/skills`.
  String get codelabSkills => '$home/skills';

  /// Каталог навыков пользователя `~/.agents/skills`.
  String get agentsSkills => '$userHome/.agents/skills';

  /// Запросы к модели в порядке прихода (шов `modelsFor`).
  final contexts = <LlmContext>[];

  final logger = RecordingLogger();

  /// [extraConfig] — дополнительный YAML в конец `$CODELAB_HOME/config.yaml`.
  static Future<SkillsRig> create({
    bool trusted = false,
    String extraConfig = '',
  }) async {
    final temp = await Directory.systemTemp.createTemp('codelab_skills_host_');
    addTearDown(() => temp.delete(recursive: true));
    final projectDir = Directory('${temp.path}/project')..createSync();
    final rig = SkillsRig._(
      temp,
      project: projectDir.resolveSymbolicLinksSync(),
    );
    Directory(rig.home).createSync();
    Directory(rig.userHome).createSync();
    final trust = trusted
        ? 'trusted_projects: [${jsonEncode(rig.project)}]\n'
        : '';
    File('${rig.home}/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_env: LLM_KEY
    models:
      m: {}
agent:
  default_model: p/m
$trust$extraConfig''');
    return rig;
  }

  /// Окружение процесса агента: только временные каталоги и фейковый ключ.
  Map<String, String> get environment => {
    'CODELAB_HOME': home,
    'HOME': userHome,
    'LLM_KEY': 'sk-test',
  };

  /// Создаёт навык `<root>/<name>/SKILL.md` и файлы [files] (путь внутри
  /// каталога навыка → содержимое); возвращает канонический каталог навыка.
  String writeSkill(
    String root,
    String name, {
    String description = 'Does the thing',
    String body = 'Follow the steps.\n',
    Map<String, String> files = const {},
  }) {
    final dir = Directory('$root/$name')..createSync(recursive: true);
    File('${dir.path}/SKILL.md').writeAsStringSync(
      '---\nname: $name\ndescription: $description\n---\n$body',
    );
    for (final MapEntry(:key, :value) in files.entries) {
      File('${dir.path}/$key')
        ..createSync(recursive: true)
        ..writeAsStringSync(value);
    }
    return dir.resolveSymbolicLinksSync();
  }

  ServeOptions options(List<String> args) =>
      parseServeArgs(['serve', ...args], environment: environment);

  /// Хост без `--llm-script`: сценарий модели подменяет `modelsFor`, запросы
  /// копятся в [contexts].
  Future<AgentHost> startHost(
    List<String> args,
    List<Map<String, Object?>> steps,
  ) async {
    final script = ScriptedStreamFunction.fromJson({'steps': steps});
    final host = await buildHost(
      options(args),
      cwd: project,
      logger: logger,
      modelsFor: (config) => (
        stream: (model, context, {cancel}) {
          contexts.add(context);
          return script.call(model, context, cancel: cancel);
        },
        catalog: StaticModelCatalog(config.providers, logger: logger),
      ),
    );
    addTearDown(() => host.shutdown(grace: Duration.zero));
    return host;
  }

  /// Хост по готовым [options] без подмены модели: для `--llm-script`, где
  /// сценарий задаёт сам флаг.
  Future<AgentHost> startHostWith(ServeOptions options) async {
    final host = await buildHost(options, cwd: project, logger: logger);
    addTearDown(() => host.shutdown(grace: Duration.zero));
    return host;
  }

  /// ACP-клиент на паре транспортов с сервером [host]; запросы агента
  /// обслуживает сам тест через `handlers`.
  Future<ClientAcpPeer> acp(AgentHost host) async {
    final link = InProcessAcpLink();
    unawaited(host.createServer().serve(link.agent));
    await link.client.start();
    final peer = ClientAcpPeer(link.client);
    addTearDown(peer.dispose);
    return peer;
  }
}
