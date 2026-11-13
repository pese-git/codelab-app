import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import '../config/agent_config_paths.dart'
    show projectSkillSubdirs, sessionSkillRootsFor;
import '../env/host_path.dart';
import '../env/local_execution_env.dart';
import 'frontmatter.dart';
import 'skill_roots.dart';

/// Читает файлы проекта и пользователя с локальной файловой системы процесса
/// агента (design.md change `add-agent-project-files`, D1, D2, D4–D6;
/// `agent-core-architecture` §11.5).
///
/// Почему не env сессии: чтение идёт внутри `createSession`, до ответа
/// `session/new`, когда клиент ещё не знает `sessionId` (ACP-8); в ACP нет
/// `stat` и листинга каталога, а `$CODELAB_HOME` лежит на машине агента.
///
/// Для чего: реализация порта [ProjectFilesSource] для настольных хостов.
/// Читает файлы инструкций `AGENTS.md`/`CLAUDE.md` (E-01) и шаблоны команд
/// `*.md` из `$CODELAB_HOME/prompts` и `<cwd>/.codelab/prompts`, а также
/// определения агентов из `$CODELAB_HOME/agents` и `<cwd>/.codelab/agents`
/// (каталоги проекта — только для доверенного проекта, D4, CFG-6). Оба вида
/// файлов читаются одним кодом с одной границей и одними лимитами (D2, D6).
///
/// Как использовать: хост создаёт один загрузчик —
/// `ProjectFilesLoader(home: codelabHomeOf(env), local: LocalExecutionEnv(...))` —
/// и кладёт его в `AgentCoreServices.projectFiles`. `home: null` выключает
/// пользовательскую область (сценарий `--llm-script` не трогает
/// `$CODELAB_HOME`, D16). Метод [load] не бросает для ошибок файлов: каждая
/// ошибка — диагностика. Содержимое файлов в диагностики не попадает (D14).
///
/// Навыки (design.md change `add-agent-skills`, D1, D3, D5, D16): тот же класс
/// реализует порт [SkillFilesSource] (`loadSkills`) теми же границей и лимитами.
/// Корни — уровни проекта от `cwd` до корня git (`.codelab/skills`, затем
/// `.agents/skills`; только доверенный проект), `$CODELAB_HOME/skills`,
/// `~/.agents/skills` и `skills.extra_roots`. [userHome] — домашний каталог
/// процесса: корень `~/.agents/skills` и раскрытие `~` в `extra_roots`
/// (`null` — не читается, `--llm-script`). Починку YAML делает
/// `readMarkdownFile(repairYaml: true)` только для навыков.
///
/// Безопасность (приоритет 1): каждое чтение содержимого идёт через
/// `BoundedEnv.wrap(local, корень области)`; путь, чей `realpath` вне корня
/// (symlink наружу), отклоняется до чтения с диагностикой `outside_root`.
/// Корни навыков проекта и `$CODELAB_HOME/skills` раскрываются через
/// `BoundedEnv` своего уровня (Q42); `~/.agents/skills` и элементы
/// `extra_roots` названы пользователем явно и не ограничиваются. Вне границы
/// выполняются только операции над метаданными, содержимое не читается:
/// проверка существования `<каталог>/.git` у предков `cwd` при поиске корня
/// репозитория, `stat` корней навыков недоверенного проекта (для диагностики
/// `untrusted_project`), `realpath` и `stat` корней `~/.agents/skills` и
/// `extra_roots`.
final class ProjectFilesLoader implements ProjectFilesSource, SkillFilesSource {
  /// [local] — именно [LocalExecutionEnv]: граница чтения опирается на его
  /// `realpath` (`PathResolver`), а окружение без резолвера оставило бы
  /// границу лексической, и symlink наружу прошёл бы незамеченным
  /// (приоритет 1). Поэтому тип сужен до реализации, которая резолвер имеет.
  ProjectFilesLoader({
    required this.home,
    this.userHome,
    required LocalExecutionEnv local,
  }) : _local = local,
       _beforeOpen = null;

  /// Точка внедрения для тестов fail-closed веток, недостижимых через
  /// [ProjectFilesLoader.new] (agent-project-context «Окружение без
  /// PathResolver», «Путь подменён после проверки»; D2).
  ///
  /// Почему отдельный конструктор: публичный тип [LocalExecutionEnv] намеренно
  /// сужен, поэтому окружение без `PathResolver` через него не передать, а
  /// подмену файла между проверкой и открытием иначе не воспроизвести
  /// детерминированно. Продакшен-код этот конструктор не вызывает.
  ///
  /// Как использовать: [local] — любое окружение (в том числе без
  /// `PathResolver`); [beforeOpen] вызывается с реальным путём файла после
  /// `realpath` и `stat`, но до `open`, и может подменить файл на диске.
  @visibleForTesting
  ProjectFilesLoader.testing({
    required this.home,
    this.userHome,
    required ExecutionEnv local,
    Future<void> Function(String path)? beforeOpen,
  }) : _local = local,
       _beforeOpen = beforeOpen;

  /// `$CODELAB_HOME`; `null` — пользовательская область не читается.
  final String? home;

  /// Домашний каталог пользователя процесса (`userHomeOf(environment)`):
  /// корень `~/.agents/skills` и раскрытие `~` в `skills.extra_roots`
  /// (design.md change `add-agent-skills`, D3, D16, Q41). `null` — не
  /// читается (`--llm-script`).
  final String? userHome;
  final ExecutionEnv _local;

  /// Тестовый хук между проверкой и открытием файла; `null` в продакшене.
  final Future<void> Function(String path)? _beforeOpen;

  /// Предел обхода вверх к корню репозитория (D5, пункт 1; D6).
  static const maxLevels = maxProjectLevels;

  /// Предел числа `*.md` в каталоге шаблонов или агентов (D6).
  static const maxTemplateFiles = 100;

  /// Предел размера файла шаблона или определения, байты (D6): больший файл не
  /// читается.
  static const maxTemplateFileBytes = 64 * 1024;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async {
    final diagnostics = <ExtensionDiagnostic>[];
    final context = <ContextFile>[];
    var root = ContextRoot.cwd;
    if (query.contextMaxBytes > 0) {
      root = await _loadContext(query, context, diagnostics);
    }
    final templates = <MarkdownFile>[];
    await _loadMarkdownDirs(
      query,
      subdir: 'prompts',
      noun: 'prompt templates',
      out: templates,
      diagnostics: diagnostics,
    );
    final agents = <MarkdownFile>[];
    await _loadMarkdownDirs(
      query,
      subdir: 'agents',
      noun: 'agent definitions',
      out: agents,
      diagnostics: diagnostics,
    );
    return ProjectFiles(
      context: context,
      contextRoot: root,
      templates: templates,
      agents: agents,
      diagnostics: diagnostics,
    );
  }

  /// Каталог `.md`-файлов [subdir] (`prompts` или `agents`): проект (только
  /// доверенный) и пользователь (D4, D7, D10). [noun] — как каталог назван в
  /// сообщениях диагностики.
  ///
  /// Область проекта ограничена `cwd`, пользовательская — `$CODELAB_HOME`:
  /// сначала каталог проверяется относительно корня области, и только потом
  /// файлы — относительно самого каталога (см. [_readMarkdownDir]).
  Future<void> _loadMarkdownDirs(
    ProjectFilesQuery query, {
    required String subdir,
    required String noun,
    required List<MarkdownFile> out,
    required List<ExtensionDiagnostic> diagnostics,
  }) async {
    final projectDir = '${query.cwd == '/' ? '' : query.cwd}/.codelab/$subdir';
    final projectArea = await BoundedEnv.wrap(_local, query.cwd);
    if (query.projectTrusted) {
      await _readMarkdownDir(
        projectArea,
        projectDir,
        ExtensionScope.project,
        query.cancel,
        out,
        diagnostics,
        noun,
      );
    } else if (await _exists(projectArea, projectDir)) {
      // Файлы недоверенного репозитория не читаются: он не вправе добавить
      // команды и агентов, которые выберет пользователь не глядя (D4, CFG-6).
      // Пользователь видит причину.
      diagnostics.add(
        ExtensionDiagnostic(
          path: projectDir,
          level: DiagnosticLevel.info,
          code: 'untrusted_project',
          message:
              'the project is not in trusted_projects; its $noun are not read',
        ),
      );
    }

    final homeDir = home;
    if (homeDir != null && !query.cancel.isCancelled) {
      await _readMarkdownDir(
        await BoundedEnv.wrap(_local, homeDir),
        '$homeDir/$subdir',
        ExtensionScope.user,
        query.cancel,
        out,
        diagnostics,
        noun,
      );
    }
  }

  /// Читает `*.md` первого уровня каталога [dir] (D3, D6, §17.2.2).
  /// [noun] — название файлов в сообщении о превышении предела.
  ///
  /// Граница двухступенчатая. [area] — корень области (`cwd` или
  /// `$CODELAB_HOME`): каталог, чей `realpath` вне области, не читается
  /// (`BoundedEnv.wrap` канонизирует корень, поэтому симлинк `prompts` наружу
  /// иначе сам стал бы корнем и проверка потеряла бы смысл). Файлы читаются
  /// через env с корнем в реальном каталоге шаблонов: symlink на файл вне
  /// каталога — `outside_root`.
  Future<void> _readMarkdownDir(
    ExecutionEnv area,
    String dir,
    ExtensionScope scope,
    CancelToken cancel,
    List<MarkdownFile> out,
    List<ExtensionDiagnostic> diagnostics,
    String noun,
  ) async {
    void report(DiagnosticLevel level, String path, String code, String text) =>
        diagnostics.add(
          ExtensionDiagnostic(
            path: path,
            level: level,
            code: code,
            message: text,
          ),
        );

    if (area is! PathResolver) {
      report(
        DiagnosticLevel.warning,
        dir,
        'unreadable',
        'the environment cannot resolve real paths; the directory is not read',
      );
      return;
    }
    final String realDir;
    switch (await (area as PathResolver).realpath(dir)) {
      case Ok(:final value):
        realDir = value;
      case Err(:final error):
        switch (error.code) {
          case FileErrorCode.notFound:
            break;
          case FileErrorCode.outsideWorkspace:
            report(
              DiagnosticLevel.warning,
              dir,
              'outside_root',
              'the directory resolves outside its root and is not read',
            );
          default:
            report(
              DiagnosticLevel.warning,
              dir,
              'unreadable',
              'the directory cannot be read: ${error.code.name}',
            );
        }
        return;
    }

    final env = await BoundedEnv.wrap(_local, realDir);
    if (env is! DirectoryListing) {
      report(
        DiagnosticLevel.warning,
        dir,
        'unreadable',
        'the environment cannot list directories',
      );
      return;
    }
    final listing = await (env as DirectoryListing).listDir(realDir);
    if (listing is! Ok<List<FileStat>, FileError>) {
      report(
        DiagnosticLevel.warning,
        dir,
        'unreadable',
        'the directory cannot be listed',
      );
      return;
    }
    // Подкаталоги не обходятся, точечные и не-`.md` файлы пропускаются молча
    // (D6, §17.2.2). Порядок — по имени, чтобы предел 100 был детерминирован.
    final names = [
      for (final entry in listing.value)
        if (entry.type != FileType.directory)
          if (entry.path.split('/').last case final name
              when !name.startsWith('.') && name.endsWith('.md'))
            name,
    ]..sort();
    final kept = names.take(maxTemplateFiles);
    if (names.length > maxTemplateFiles) {
      report(
        DiagnosticLevel.warning,
        dir,
        'limit_exceeded',
        'more than $maxTemplateFiles $noun; the extra files are skipped',
      );
    }

    for (final name in kept) {
      if (cancel.isCancelled) {
        return;
      }
      final shown = '$dir/$name';
      final read = await _readText(
        env,
        '$realDir/$name',
        maxTemplateFileBytes,
        diagnostics,
        reportPath: shown,
        wholeFile: true,
      );
      if (read == null) {
        continue;
      }
      final markdown = readMarkdownFile(
        read.text.startsWith('\u{FEFF}') ? read.text.substring(1) : read.text,
        path: shown,
        scope: scope,
      );
      diagnostics.addAll(markdown.diagnostics);
      if (markdown.file case final file?) {
        out.add(file);
      }
    }
  }

  // ---- навыки (design.md change `add-agent-skills`, D1, D3, D5, D16) -------

  /// Предел подкаталогов одного корня навыков (D3).
  static const maxSkillEntries = 1000;

  /// Предел размера `SKILL.md`, байты (D4): больший файл не читается.
  static const maxSkillFileBytes = 128 * 1024;

  /// Предел перечисляемых сопутствующих файлов навыка и глубина (D5).
  static const maxCompanions = 50;
  static const maxCompanionDepth = 3;

  @override
  Future<SkillFiles> loadSkills(SkillFilesQuery query) async {
    final diagnostics = <ExtensionDiagnostic>[];
    final skills = <SkillFile>[];
    final roots = await _skillRoots(query, diagnostics);
    final seen = <String>{};
    for (final (index, root) in roots.indexed) {
      if (query.cancel.isCancelled) {
        break;
      }
      await _readSkillRoot(
        root,
        index,
        query.cancel,
        skills,
        diagnostics,
        seen,
      );
    }
    return SkillFiles(
      skills: skills,
      diagnostics: diagnostics,
      sessionRoots: await _sessionRoots(query),
    );
  }

  /// Корни, которые защищает политика этой сессии (D9, D17; Q27, Q44):
  /// зависящие от `cwd` — той же функцией, что и PERM-11 хоста, — плюс
  /// абсолютные и `~`-элементы `extra_roots` этой папки: у сессии другой
  /// папки свои `extra_roots`, а путей хоста из конфига корня запуска для неё
  /// мало. Не зависит от доверия проекта и от существования каталогов.
  Future<List<String>> _sessionRoots(SkillFilesQuery query) async {
    final roots = <String>{
      ...await sessionSkillRootsFor(
        cwd: query.cwd,
        extraRoots: query.extraRoots,
      ),
    };
    for (final raw in query.extraRoots) {
      if (hostSkillRoot(raw, userHome) case final path?) {
        roots.add(
          toCorePath(canonicalPath(path), windows: io.Platform.isWindows),
        );
      }
    }
    return roots.toList();
  }

  /// Список корней в порядке приоритета (D3, D16): уровни проекта от `cwd`
  /// вверх (только для доверенного проекта), `$CODELAB_HOME/skills`,
  /// `~/.agents/skills`, затем `skills.extra_roots`. Номер корня — его
  /// позиция в этом списке; корень, пропущенный по доверию или без домашнего
  /// каталога, номера не получает и в список не попадает.
  Future<List<_SkillRoot>> _skillRoots(
    SkillFilesQuery query,
    List<ExtensionDiagnostic> diagnostics,
  ) async {
    final roots = <_SkillRoot>[];
    // Уровни проекта нужны и недоверенному проекту: `untrusted_project`
    // называет каждый существующий корень (D16).
    final scan = <ExtensionDiagnostic>[];
    final (:levels, found: _) = await _findRoot(query.cwd, scan);
    for (final item in scan) {
      diagnostics.add(
        ExtensionDiagnostic(
          path: item.path,
          level: item.level,
          code: item.code,
          message:
              'more than $maxLevels levels above the working directory; the '
              'search for the git root stops',
        ),
      );
    }
    for (final level in levels.reversed) {
      for (final sub in projectSkillSubdirs) {
        final path = '${level == '/' ? '' : level}/$sub';
        if (query.projectTrusted) {
          roots.add(_SkillRoot(path, ExtensionScope.project, area: level));
        } else if (await _isDirectory(path)) {
          diagnostics.add(
            ExtensionDiagnostic(
              path: path,
              level: DiagnosticLevel.info,
              code: 'untrusted_project',
              message:
                  'the project is not in trusted_projects; its skills are not '
                  'read',
            ),
          );
        }
      }
    }
    if (home case final homeDir?) {
      roots.add(
        _SkillRoot('$homeDir/skills', ExtensionScope.user, area: homeDir),
      );
    }
    if (userHome case final dir?) {
      roots.add(_SkillRoot('$dir/.agents/skills', ExtensionScope.user));
    }
    for (final raw in query.extraRoots) {
      if (isHomeSkillRoot(raw)) {
        final dir = userHome;
        if (dir == null) {
          diagnostics.add(
            ExtensionDiagnostic(
              path: raw,
              level: DiagnosticLevel.warning,
              code: 'unresolved_root',
              message:
                  'the skills root starts with ~ but the home directory is '
                  'unknown; it is not read',
            ),
          );
          continue;
        }
        roots.add(_SkillRoot('$dir${raw.substring(1)}', ExtensionScope.extra));
      } else if (hostSkillRoot(raw, userHome) case final path?) {
        roots.add(_SkillRoot(path, ExtensionScope.extra));
      } else if (isRelativeSkillRoot(raw)) {
        final path = '${query.cwd == '/' ? '' : query.cwd}/$raw';
        if (query.projectTrusted) {
          roots.add(_SkillRoot(path, ExtensionScope.extra));
        } else {
          diagnostics.add(
            ExtensionDiagnostic(
              path: path,
              level: DiagnosticLevel.warning,
              code: 'untrusted_project',
              message:
                  'the project is not trusted; a relative skills.extra_roots '
                  'entry is not read',
            ),
          );
        }
      }
      // `~user/…` и `<scheme>://…` не корни: их отвергает проверка конфига, а
      // PERM-11 их не защищает — загрузчик их тоже не читает (Q41).
    }
    return roots;
  }

  Future<bool> _isDirectory(String path) async =>
      switch (await _local.stat(path)) {
        Ok(:final value) => value.type == FileType.directory,
        Err() => false,
      };

  /// Читает подкаталоги первого уровня корня [root]: каждый с `SKILL.md`
  /// становится [SkillFile]. Корень раскрывается `realpath`; каталог навыка,
  /// чей `realpath` вне корня, — `outside_root`; сам `SKILL.md` и список
  /// файлов идут через `BoundedEnv` с корнем в реальном каталоге навыка (D3).
  Future<void> _readSkillRoot(
    _SkillRoot root,
    int index,
    CancelToken cancel,
    List<SkillFile> skills,
    List<ExtensionDiagnostic> diagnostics,
    Set<String> seen,
  ) async {
    // Корень проекта и `$CODELAB_HOME/skills` раскрываются через
    // `BoundedEnv`, привязанный к своему уровню (Q42, как `_readMarkdownDir`):
    // symlink корня наружу — `outside_root`. `~/.agents/skills` и элементы
    // `extra_roots` названы пользователем явно и раскрываются без границы.
    final ExecutionEnv resolver = root.area == null
        ? _local
        : await BoundedEnv.wrap(_local, root.area!);
    if (resolver is! PathResolver) {
      diagnostics.add(
        ExtensionDiagnostic(
          path: root.path,
          level: DiagnosticLevel.warning,
          code: 'unreadable',
          message:
              'the environment cannot resolve real paths; the directory is '
              'not read',
        ),
      );
      return;
    }
    // Записи-не-каталоги и отсутствующий корень пропускаются молча (D10).
    final String realRoot;
    switch (await (resolver as PathResolver).realpath(root.path)) {
      case Ok(:final value):
        realRoot = value;
      case Err(:final error):
        if (error.code == FileErrorCode.outsideWorkspace) {
          diagnostics.add(
            ExtensionDiagnostic(
              path: root.path,
              level: DiagnosticLevel.warning,
              code: 'outside_root',
              message:
                  'the skills root resolves outside its area; its skills are '
                  'not read',
            ),
          );
        }
        return;
    }
    if (!await _isDirectory(realRoot)) {
      return;
    }
    final bounded = await BoundedEnv.wrap(_local, realRoot);
    if (bounded is! DirectoryListing) {
      return;
    }
    final listing = await (bounded as DirectoryListing).listDir(realRoot);
    if (listing is! Ok<List<FileStat>, FileError>) {
      return;
    }
    // Каталоги на `.` и файлы не читаются; ссылки проверяет `realpath`.
    final names = [
      for (final entry in listing.value)
        if (entry.type == FileType.directory || entry.type == FileType.link)
          if (entry.path.split('/').last case final name
              when !name.startsWith('.'))
            name,
    ]..sort();
    final kept = names.take(maxSkillEntries);
    if (names.length > maxSkillEntries) {
      diagnostics.add(
        ExtensionDiagnostic(
          path: root.path,
          level: DiagnosticLevel.warning,
          code: 'limit_exceeded',
          message:
              'more than $maxSkillEntries entries in the skills root; the '
              'rest are not read',
        ),
      );
    }
    for (final name in kept) {
      if (cancel.isCancelled) {
        return;
      }
      final shown = '${root.path}/$name';
      final String realDir;
      switch (await (bounded as PathResolver).realpath('$realRoot/$name')) {
        case Ok(:final value):
          realDir = value;
        case Err(:final error):
          if (error.code == FileErrorCode.outsideWorkspace) {
            diagnostics.add(
              ExtensionDiagnostic(
                path: shown,
                level: DiagnosticLevel.warning,
                code: 'outside_root',
                message:
                    'the skill directory resolves outside its root; the '
                    'skill is skipped',
              ),
            );
          }
          continue;
      }
      if (!await _isDirectory(realDir) || !seen.add(realDir)) {
        continue;
      }
      final file = await _readSkill(
        realDir,
        root.scope,
        index,
        cancel,
        diagnostics,
      );
      if (file != null) {
        skills.add(file);
      }
    }
  }

  /// Читает `SKILL.md` каталога [realDir] и перечисляет сопутствующие файлы.
  Future<SkillFile?> _readSkill(
    String realDir,
    ExtensionScope scope,
    int index,
    CancelToken cancel,
    List<ExtensionDiagnostic> diagnostics,
  ) async {
    final env = await BoundedEnv.wrap(_local, realDir);
    final path = '$realDir/SKILL.md';
    final local = <ExtensionDiagnostic>[];
    final read = await _readText(
      env,
      path,
      maxSkillFileBytes,
      local,
      wholeFile: true,
    );
    for (final item in local) {
      // Тексты скилл-файла фиксированы D16 и не называют лимит в байтах.
      final message = switch (item.code) {
        'too_large' => 'SKILL.md is larger than 128 KiB; the skill is skipped',
        'not_utf8' => 'SKILL.md is not valid UTF-8; the skill is skipped',
        _ => item.message,
      };
      diagnostics.add(
        ExtensionDiagnostic(
          path: item.path,
          level: item.level,
          code: item.code,
          message: message,
        ),
      );
    }
    if (read == null || cancel.isCancelled) {
      return null;
    }
    final markdown = readMarkdownFile(
      read.text.startsWith('\u{FEFF}') ? read.text.substring(1) : read.text,
      path: path,
      scope: scope,
      repairYaml: true,
    );
    final (:files, :truncated) = await _companions(env, realDir, cancel);
    final parsed = markdown.file;
    return SkillFile(
      dir: realDir,
      scope: scope,
      rootIndex: index,
      frontmatter: parsed?.frontmatter,
      parseErrors: markdown.diagnostics,
      repaired: markdown.repaired,
      body: parsed?.body ?? '',
      bodyLine: parsed?.bodyLine ?? 1,
      companions: files,
      companionsTruncated: truncated,
    );
  }

  /// Сопутствующие файлы каталога навыка (D5): обычные файлы на глубине до
  /// [maxCompanionDepth], не больше [maxCompanions] путей в байтовом порядке,
  /// без каталогов на `.`, `evals/` верхнего уровня, `SKILL.md` и записей,
  /// чей `realpath` вне каталога навыка. Содержимое не читается.
  Future<({List<String> files, bool truncated})> _companions(
    ExecutionEnv env,
    String realDir,
    CancelToken cancel,
  ) async {
    if (env is! DirectoryListing || env is! PathResolver) {
      return (files: const <String>[], truncated: false);
    }
    final listing = env as DirectoryListing;
    final resolver = env as PathResolver;
    // Предел обхода — защита ресурсов (D5), а не часть контракта: огромный
    // каталог не должен держать чтение. Считаются ВСЕ просмотренные записи
    // (файлы и каталоги, в том числе пропущенные), на 5000-й обход
    // останавливается и ставит `truncated`. Пока записей меньше предела,
    // список точен (первые 50 в байтовом порядке); записи каждого каталога
    // сортируются перед обходом, чтобы результат не зависел от `listDir`.
    const walkLimit = 5000;
    final found = <String>[];
    var looked = 0;
    var capped = false;

    Future<void> walk(String dir, String prefix, int depth) async {
      if (cancel.isCancelled || capped) {
        return;
      }
      final entries = await listing.listDir(dir);
      if (entries is! Ok<List<FileStat>, FileError>) {
        return;
      }
      final sorted = [...entries.value]
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final entry in sorted) {
        if (cancel.isCancelled || capped) {
          return;
        }
        if (++looked >= walkLimit) {
          capped = true;
        }
        final name = entry.path.split('/').last;
        final relative = prefix.isEmpty ? name : '$prefix/$name';
        var type = entry.type;
        if (type == FileType.link) {
          // Ссылка наружу не перечисляется; внутри — как её цель.
          switch (await resolver.realpath(entry.path)) {
            case Ok(:final value):
              type = switch (await env.stat(value)) {
                Ok(value: final target) => target.type,
                Err() => FileType.other,
              };
            case Err():
              continue;
          }
        }
        if (type == FileType.directory) {
          if (name.startsWith('.') ||
              (prefix.isEmpty && name == 'evals') ||
              depth >= maxCompanionDepth) {
            continue;
          }
          await walk(entry.path, relative, depth + 1);
        } else if (type == FileType.file) {
          if (prefix.isEmpty && name == 'SKILL.md') {
            continue;
          }
          found.add(relative);
        }
      }
    }

    await walk(realDir, '', 1);
    found.sort();
    return (
      files: found.take(maxCompanions).toList(),
      truncated: capped || found.length > maxCompanions,
    );
  }

  /// Файлы контекста в порядке «пользовательский, затем от корня к `cwd`»
  /// (D5, пункт 1).
  Future<ContextRoot> _loadContext(
    ProjectFilesQuery query,
    List<ContextFile> out,
    List<ExtensionDiagnostic> diagnostics,
  ) async {
    final max = query.contextMaxBytes;
    final homeDir = home;
    if (homeDir != null && !query.cancel.isCancelled) {
      final env = await BoundedEnv.wrap(_local, homeDir);
      final file = await _readFile(
        env,
        '$homeDir/AGENTS.md',
        max,
        diagnostics,
        displayPath: r'$CODELAB_HOME/AGENTS.md',
        scope: ExtensionScope.user,
      );
      if (file != null) {
        out.add(file);
      }
    }

    final (:levels, :found) = await _findRoot(query.cwd, diagnostics);
    final root = levels.first;
    final env = await BoundedEnv.wrap(_local, root);
    for (final dir in levels) {
      if (query.cancel.isCancelled) {
        break;
      }
      final prefix = dir == root ? '' : '${dir.substring(root.length + 1)}/';
      final agents = '$dir/AGENTS.md';
      final claude = '$dir/CLAUDE.md';
      var name = 'AGENTS.md';
      var path = agents;
      if (!await _exists(env, agents)) {
        name = 'CLAUDE.md';
        path = claude;
      } else if (await _exists(env, claude)) {
        diagnostics.add(
          ExtensionDiagnostic(
            path: claude,
            level: DiagnosticLevel.info,
            code: 'shadowed',
            message: 'CLAUDE.md is ignored: AGENTS.md exists at the same level',
          ),
        );
      }
      final file = await _readFile(
        env,
        path,
        max,
        diagnostics,
        displayPath: '$prefix$name',
        scope: ExtensionScope.project,
      );
      if (file != null) {
        out.add(file);
      }
    }
    return found ? ContextRoot.git : ContextRoot.cwd;
  }

  /// Каталоги от корня репозитория к [cwd] и признак «репозиторий найден».
  ///
  /// Репозитория нет или он дальше [maxLevels] — единственный уровень `cwd`;
  /// в предел это даёт диагностику `info` (D6).
  Future<({List<String> levels, bool found})> _findRoot(
    String cwd,
    List<ExtensionDiagnostic> diagnostics,
  ) async {
    // Подъём общий с PERM-11 (`projectLevels`): списки корней не расходятся.
    final result = projectLevels(cwd);
    if (result.limitHit) {
      diagnostics.add(
        ExtensionDiagnostic(
          path: cwd,
          level: DiagnosticLevel.info,
          code: 'limit_exceeded',
          message:
              'no git repository within $maxLevels levels above the working '
              'directory; only the working directory is searched',
        ),
      );
    }
    return (levels: result.levels, found: result.found);
  }

  /// Есть ли запись по [path] внутри границы [env]. Symlink наружу тоже
  /// «есть»: решение об отказе принимает [_readFile] с диагностикой.
  Future<bool> _exists(ExecutionEnv env, String path) async =>
      switch (await env.stat(path)) {
        Ok() => true,
        Err(:final error) => error.code == FileErrorCode.outsideWorkspace,
      };

  /// Читает файл контекста не больше `max + 1` байт (D5, пункт 4).
  ///
  /// Граница проверяется `realpath` через [env]; дальше читается уже
  /// проверенный реальный путь. Лишний байт нужен сборщику, чтобы отличить
  /// «файл ровно по бюджету» от «файл больше бюджета»; полный размер `M` —
  /// из `stat`, файл целиком не читается.
  Future<ContextFile?> _readFile(
    ExecutionEnv env,
    String path,
    int max,
    List<ExtensionDiagnostic> diagnostics, {
    required String displayPath,
    required ExtensionScope scope,
  }) async {
    final read = await _readText(env, path, max + 1, diagnostics);
    if (read == null) {
      return null;
    }
    return ContextFile(
      path: displayPath,
      content: read.text.startsWith('\u{FEFF}')
          ? read.text.substring(1)
          : read.text,
      totalBytes: read.size > read.bytes ? read.size : null,
      scope: scope,
    );
  }

  /// Читает текст файла по [path] внутри границы [env] и возвращает его с
  /// размером; `null` — файл не прочитан, причина уже в [diagnostics].
  ///
  /// Общая часть чтения контекста и шаблонов: `realpath` через [env]
  /// (нет резолвера, путь вне корня → диагностика), `stat` реального пути,
  /// чтение не больше [limit] байт `dart:io` и повторная проверка после
  /// открытия (D2). С [wholeFile] файл больше [limit] байт не читается
  /// вовсе: `too_large` (шаблоны, D6); иначе читается префикс [limit] байт, а
  /// усечение — дело вызывающего (контекст, D5). [reportPath] — путь в
  /// диагностиках, если он должен отличаться от [path].
  Future<({String text, int size, int bytes})?> _readText(
    ExecutionEnv env,
    String path,
    int limit,
    List<ExtensionDiagnostic> diagnostics, {
    String? reportPath,
    bool wholeFile = false,
  }) async {
    void report(DiagnosticLevel level, String code, String message) =>
        diagnostics.add(
          ExtensionDiagnostic(
            path: reportPath ?? path,
            level: level,
            code: code,
            message: message,
          ),
        );

    // `BoundedEnv` реализует `PathResolver`, потому что его реализует
    // `LocalExecutionEnv` (ENV-4). Иначе читать нельзя: без `realpath`
    // граница лексическая.
    if (env is! PathResolver) {
      report(
        DiagnosticLevel.warning,
        'unreadable',
        'the environment cannot resolve real paths; the file is not read',
      );
      return null;
    }
    final real = await (env as PathResolver).realpath(path);
    final String realPath;
    switch (real) {
      case Ok(:final value):
        realPath = value;
      case Err(:final error):
        switch (error.code) {
          case FileErrorCode.notFound:
            return null;
          case FileErrorCode.outsideWorkspace:
            report(
              DiagnosticLevel.warning,
              'outside_root',
              'the file resolves outside its root and is not read',
            );
          default:
            report(
              DiagnosticLevel.warning,
              'unreadable',
              'the file cannot be read: ${error.code.name}',
            );
        }
        return null;
    }
    final stat = await env.stat(realPath);
    if (stat case Ok(:final value) when value.type == FileType.file) {
      final size = value.size ?? 0;
      if (wholeFile && size > limit) {
        report(
          DiagnosticLevel.error,
          'too_large',
          'the file is larger than $limit bytes and is not read',
        );
        return null;
      }
      try {
        final bytes = await _readPrefix(realPath, limit + (wholeFile ? 1 : 0));
        if (bytes == null) {
          report(
            DiagnosticLevel.warning,
            'outside_root',
            'the file changed while it was being opened and is not read',
          );
          return null;
        }
        if (wholeFile && bytes.length > limit) {
          // Файл вырос между `stat` и чтением.
          report(
            DiagnosticLevel.error,
            'too_large',
            'the file is larger than $limit bytes and is not read',
          );
          return null;
        }
        final partial = !wholeFile && size > bytes.length;
        final text = _decode(bytes, partial: partial);
        if (text == null) {
          report(
            DiagnosticLevel.warning,
            'not_utf8',
            'the file is not valid UTF-8 and is skipped',
          );
          return null;
        }
        return (text: text, size: size, bytes: bytes.length);
      } on io.FileSystemException {
        report(
          DiagnosticLevel.warning,
          'unreadable',
          'the file cannot be read',
        );
        return null;
      }
    }
    report(
      DiagnosticLevel.warning,
      'unreadable',
      'the path is not a regular file',
    );
    return null;
  }

  /// Читает первые [count] байт проверенного [corePath]; `null` — файл
  /// подменили между проверкой и открытием.
  ///
  /// После `open` путь проверяется ещё раз: `resolveSymbolicLinks` должен
  /// совпасть с проверенным реальным путём, а открытый путь — оставаться
  /// обычным файлом. Остаточный TOCTOU: в Dart нет `O_NOFOLLOW`, поэтому
  /// подмена между повторной проверкой и `read` возможна; её цена — чтение
  /// одного файла, который владелец каталога уже мог положить сам, а не обход
  /// контейнмента для произвольных путей. FIFO отсекает `stat` до `open`
  /// (открытие FIFO на чтение блокируется).
  Future<Uint8List?> _readPrefix(String corePath, int count) async {
    await _beforeOpen?.call(corePath);
    final host = toHostPath(corePath, windows: io.Platform.isWindows);
    final file = await io.File(host).open();
    try {
      if (await io.File(host).resolveSymbolicLinks() != host ||
          (await io.FileStat.stat(host)).type != io.FileSystemEntityType.file) {
        return null;
      }
      return await file.read(count);
    } finally {
      await file.close();
    }
  }

  /// Строгое декодирование UTF-8. У префикса (файл больше прочитанного)
  /// оборванная последовательность в конце не ошибка: до трёх байт хвоста
  /// отбрасываются.
  String? _decode(Uint8List bytes, {required bool partial}) {
    for (var drop = 0; drop <= (partial ? 3 : 0); drop++) {
      if (drop > bytes.length) {
        break;
      }
      try {
        return utf8.decode(
          Uint8List.sublistView(bytes, 0, bytes.length - drop),
        );
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}

/// Корень навыков списка загрузчика (D16): [path] как его видит
/// пользователь, [scope] и [area] — каталог, которым ограничено раскрытие
/// корня (`null` — явный корень `extra_roots`, граница не применяется).
final class _SkillRoot {
  const _SkillRoot(this.path, this.scope, {this.area});

  final String path;
  final ExtensionScope scope;
  final String? area;
}
