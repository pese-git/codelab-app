/// Файлы конфигурации агента: что наблюдает `ConfigWatcher` и что защищает
/// политика разрешений (design.md change `add-config-writer-and-reload`, D7,
/// D8, «Пути конфигурации агента для PERM-11»; PERM-11, `agent-core-
/// architecture` §7.6.1).
///
/// Почему одна функция на оба списка: «что агент перечитывает на лету, то
/// модель не правит без человека». Два независимых вычисления разошлись бы
/// (новый слой конфига попал бы в наблюдатель, но не под защиту), поэтому
/// [agentConfigPathsFor] строится поверх [watchedConfigFiles] по тем же
/// входам, что у `ConfigLoader.load`.
///
/// Как использовать: `AgentHost` и открыватель `codelab_embedded` вызывают
/// [agentConfigPathsFor] один раз при сборке и кладут результат в
/// `AgentCoreServices.agentConfigPaths`; `ConfigWatcher` берёт список из
/// [watchedConfigFiles].
library;

import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../env/host_path.dart';
import '../project/skill_roots.dart';
import 'config_link_containment.dart' show projectLayerFiles;

export '../project/skill_roots.dart' show hostSkillRoot;
import 'config_loader.dart';
import 'config_paths.dart' show canonicalDirectory;

/// Файлы, которые загрузчик читает или прочитал бы (D7), в порядке слоёв.
///
/// Для чего: `$CODELAB_HOME/config.yaml`; файл `--config`/`CODELAB_CONFIG`
/// (относительный — от корня запуска); `<корень запуска>/.codelab/
/// config.yaml` и `config.local.yaml`, в том числе ещё не созданные;
/// `$CODELAB_HOME/secrets.yaml` при [secretsFile] (`secrets.backend: file`).
///
/// Как использовать: параметры — те же, что у `ConfigLoader.load`; [cwd]
/// канонизируется, как у загрузчика. Пути лексические, без разбора ссылок
/// (наблюдателю нужен путь, который пишет писатель). Неверный
/// `CODELAB_HOME` бросает `ConfigUsageException`, как загрузчик.
List<String> watchedConfigFiles({
  required String cwd,
  required Map<String, String> environment,
  String? extraConfig,
  bool secretsFile = false,
}) {
  final home = codelabHomeOf(environment);
  final root = canonicalDirectory(cwd);
  final explicit =
      _nonEmpty(extraConfig) ?? _nonEmpty(environment['CODELAB_CONFIG']);
  return [
    '$home/config.yaml',
    if (explicit != null)
      isAbsoluteConfigPath(explicit) ? explicit : '$root/$explicit',
    // Пути проектных слоёв строит `projectLayerFiles` (8.5): источник файлов
    // с признаком слоя сравнивает не строки разных видов, а те же значения.
    ...projectLayerFiles(cwd),
    if (secretsFile) '$home/secrets.yaml',
  ];
}

/// Пути конфигурации агента для политики разрешений (PERM-11, D8).
///
/// Почему канонические: политика сравнивает цель `write`/`edit` после
/// канонизации `BoundedEnv`, а `$CODELAB_HOME/config.yaml` может быть ссылкой
/// на `~/dotfiles/codelab.yaml` — цель ссылки и есть тот файл, который
/// правит инструмент (agent-permissions «Символическая ссылка»).
///
/// Для чего: [watchedConfigFiles] плюс каталоги `$CODELAB_HOME/agents` и
/// `prompts` (паритет с проектными `.codelab/agents/**`, `prompts/**`). Пути
/// абсолютные, `~` раскрыт, ссылки раскрыты по самому глубокому
/// существующему предку (так же для ещё не созданных файлов).
/// `expansions` — `HOME` и `CODELAB_HOME` окружения хоста для раскрытия в
/// командах `exec`; они лексические: так их видит оболочка.
///
/// Как использовать: [caseInsensitive] — признак файловой системы без
/// учёта регистра; без него — по платформе (macOS и Windows). Ссылка, цель
/// которой ещё не существует, не раскрывается (`realpath` её не видит):
/// остаток пути берётся как есть.
///
/// Корни навыков (design.md change `add-agent-skills`, D9, D17; Q9, Q16,
/// Q27): `$CODELAB_HOME/skills`, `<userHome>/.agents/skills` и элементы
/// [skillExtraRoots] — абсолютные и `~`/`~/…` (раскрыты в домашний каталог
/// процесса); относительные, `~user/…` и `<scheme>://` пропускаются. Корни
/// защищены с поддеревом, существуют они или нет, независимо от доверия
/// проекту. Корни, зависящие от `cwd` сессии, даёт [sessionSkillRootsFor].
AgentConfigPaths agentConfigPathsFor({
  required String cwd,
  required Map<String, String> environment,
  String? extraConfig,
  bool? caseInsensitive,
  List<String> skillExtraRoots = const [],
}) {
  final home = codelabHomeOf(environment);
  final files = [
    ...watchedConfigFiles(
      cwd: cwd,
      environment: environment,
      extraConfig: extraConfig,
      // Защита не зависит от `secrets.backend`: файл остаётся под PERM-11 и
      // тогда, когда бэкенд позже переключат на `file` (решение пользователя
      // 2026-11-03); наблюдение (`watchedConfigFiles`) зависит от бэкенда.
      secretsFile: true,
    ),
    // PERM-11 (design.md change `optional-default-model`, D7): память
    // последней модели влияет на выбор модели следующих сессий, поэтому
    // инструмент записи не должен её править. В наблюдатель путь не входит:
    // это не конфиг, перезагрузки по нему нет.
    '$home/state/last-model.json',
    // Весь каталог `state/`: производное состояние агента, как `agents` и
    // `prompts`, защищается поддеревом.
    '$home/state',
    '$home/agents',
    '$home/prompts',
  ];
  final windows = Platform.isWindows;
  final userHome = userHomeOf(environment);
  files.addAll([
    '$home/skills',
    ?(userHome == null ? null : '$userHome/.agents/skills'),
    for (final raw in skillExtraRoots) ?hostSkillRoot(raw, userHome),
  ]);
  // Для файлов состояния кладутся и лексический, и канонический путь:
  // `FileLastModelStore.write` заменяет ссылку обычным файлом (`rename`), и
  // защита только по канонической цели перестала бы действовать (PERM-11).
  final lexical = {'$home/state/last-model.json', '$home/state'};
  final paths = <String>{
    for (final file in files) ...[
      toCorePath(canonicalPath(file), windows: windows),
      if (lexical.contains(file))
        toCorePath(File(file).absolute.path, windows: windows),
    ],
  };
  return AgentConfigPaths(
    paths: paths,
    expansions: {
      if (userHome != null) 'HOME': toCorePath(userHome, windows: windows),
      'CODELAB_HOME': toCorePath(home, windows: windows),
    },
    caseInsensitive: caseInsensitive ?? (Platform.isMacOS || windows),
  );
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

/// Подкаталоги навыков каждого уровня проекта в порядке приоритета (D3).
const projectSkillSubdirs = ['.codelab/skills', '.agents/skills'];

/// Корни навыков, зависящие от `cwd` сессии (PERM-11, D9, D17, Q27):
/// `<уровень>/.codelab/skills` и `<уровень>/.agents/skills` для уровней от
/// [cwd] до корня git (без репозитория — только [cwd]; не выше 64 уровней),
/// затем относительные элементы [extraRoots], разрешённые от [cwd].
///
/// Почему: эти корни зависят от папки сессии, поэтому их нельзя положить в
/// поле хоста `agentConfigPaths`; рантайм добавляет их к политике сессии
/// (`AgentConfigPaths.withSession`). Защита не зависит от доверия проекту и
/// от существования каталога.
///
/// Как использовать: пути канонические (ссылки раскрыты по самому глубокому
/// существующему предку), в POSIX-виде ядра. Абсолютные и `~`-элементы
/// не входят — их даёт [agentConfigPathsFor] (вопрос B3: `environment` не
/// нужен). Подъём к корню git — тот же `projectLevels`, что у загрузчика (`.git` —
/// каталог или файл, ссылка маркером не считается); [cwd] — в форме ядра.
Future<List<String>> sessionSkillRootsFor({
  required String cwd,
  List<String> extraRoots = const [],
}) async {
  final windows = Platform.isWindows;
  // Подъём — тот же, что у загрузчика (`projectLevels`): списки не расходятся.
  final (:levels, found: _, limitHit: _) = projectLevels(cwd);
  final start = levels.last;
  final roots = <String>[
    // Порядок приоритета: от `cwd` вверх.
    for (final level in levels.reversed)
      for (final sub in projectSkillSubdirs)
        '${level == '/' ? '' : level}/$sub',
    for (final raw in extraRoots)
      if (isRelativeSkillRoot(raw)) '${start == '/' ? '' : start}/$raw',
  ];
  return [
    // Корни в форме ядра: в `dart:io` — через форму хоста и обратно.
    for (final root in roots)
      toCorePath(
        canonicalPath(toHostPath(root, windows: windows)),
        windows: windows,
      ),
  ];
}
