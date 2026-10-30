/// Порт файлов проекта и его данные (design.md change
/// `add-agent-project-files`, D1, D3, D6; `agent-core-architecture` §11.5,
/// §17.2).
///
/// Почему порт в ядре: файлы проекта читаются при создании и загрузке
/// сессии, до ответа `session/new` и без `sessionId` (D2). У `loadSession`
/// нет спецификации, а ACP-адаптер не знает `$CODELAB_HOME` и не имеет
/// `dart:io` (PKG-3), поэтому поле `SessionSpec` не подходит — так же
/// устроены `McpConnector` и `SessionStore`.
///
/// Для чего: хост читает и разбирает файлы (YAML и файловая система — не
/// дело ядра, PKG-1, CFG-5), а ядро проверяет и применяет результат чистыми
/// функциями (`assembleProjectContext`; позже — шаблоны и агенты).
///
/// Как использовать: хост кладёт реализацию в `AgentCoreServices.projectFiles`;
/// `null` значит «файлов проекта нет» (web, мобильные хосты, тесты) и
/// поведение прежнее.
library;

import '../cancel/cancel_token.dart';
import '../config/config_tree.dart';

/// Откуда файл: область определяет доверие и приоритет (D4).
enum ExtensionScope {
  /// Файл проекта (`<cwd>/…`, `<cwd>/.codelab/…`).
  project,

  /// Файл пользователя (`$CODELAB_HOME/…`).
  user,

  /// Каталог, названный явно (`prompts.templates_dirs`, после MVP).
  ///
  /// Значение входит в контракт `ExtensionScope` §17.2.3 и нужно, чтобы
  /// добавление `templates_dirs` не меняло публичный enum; сейчас ни один
  /// загрузчик его не отдаёт.
  extra,
}

/// Серьёзность диагностики файла.
enum DiagnosticLevel { error, warning, info }

/// Диагностика файла проекта: ошибка файла — значение, а не исключение
/// (D6; тип §17.2.3, `column` добавлен для единообразия с `ConfigIssue`).
///
/// [message] строится из фиксированных текстов и не содержит фрагментов
/// файла: содержимое не должно попадать в логи (D14).
final class ExtensionDiagnostic {
  const ExtensionDiagnostic({
    required this.path,
    required this.level,
    required this.code,
    required this.message,
    this.line,
    this.column,
  });

  /// Путь файла или каталога, как его видит пользователь.
  final String path;
  final int? line;
  final int? column;
  final DiagnosticLevel level;

  /// Стабильный код: `outside_root`, `not_utf8`, `shadowed`, `limit_exceeded`,
  /// `untrusted_project`, `unexpected` и т. д. (D3, D6).
  final String code;
  final String message;

  @override
  String toString() => 'ExtensionDiagnostic(${level.name} $code $path)';
}

/// Файл инструкций проекта (`AGENTS.md`/`CLAUDE.md`), уже прочитанный
/// хостом.
///
/// Почему [content] и [totalBytes] отдельно: загрузчик читает не больше
/// `contextMaxBytes + 1` байт, а полный размер берёт из `stat` (D5): так
/// огромный файл не читается целиком, а пометка об усечении называет
/// настоящий размер.
final class ContextFile {
  /// [path] — путь в секции промпта (D5, пункт 6), а не путь на диске.
  /// [totalBytes] по умолчанию — длина [content] в UTF-8.
  ContextFile({
    required this.path,
    required this.content,
    int? totalBytes,
    this.scope = ExtensionScope.project,
  }) : contentBytes = _utf8Length(content),
       totalBytes = totalBytes ?? _utf8Length(content);

  final String path;

  /// Прочитанный текст (возможно, лишь начало файла).
  final String content;

  /// Длина [content] в UTF-8.
  final int contentBytes;

  /// Полный размер файла, байты.
  final int totalBytes;
  final ExtensionScope scope;

  /// [content] — только начало файла: файл больше прочитанного.
  bool get isPartial => totalBytes > contentBytes;

  static int _utf8Length(String text) {
    var n = 0;
    for (final unit in text.runes) {
      n += unit < 0x80
          ? 1
          : unit < 0x800
          ? 2
          : unit < 0x10000
          ? 3
          : 4;
    }
    return n;
  }
}

/// Файл шаблона команды или определения агента с отделённым frontmatter
/// (D3). В итерации 1 загрузчик такие файлы не отдаёт: тип нужен порту, чтобы
/// итерации 2–3 расширяли его без смены сигнатур.
final class MarkdownFile {
  const MarkdownFile({
    required this.path,
    required this.scope,
    required this.body,
    required this.bodyLine,
    this.frontmatter,
  });

  /// Абсолютный путь файла.
  final String path;
  final ExtensionScope scope;

  /// Разобранный frontmatter со строками файла; `null` — frontmatter нет.
  final ConfigTree? frontmatter;
  final String body;

  /// Номер строки файла, с которой начинается [body] (с 1).
  final int bodyLine;
}

/// Откуда взят корень обхода контекста (D5): лог `project_context.loaded`.
enum ContextRoot {
  /// Нашёлся каталог с записью `.git`.
  git,

  /// Репозитория нет: корень — `cwd`.
  cwd,
}

/// Запрос порту (D1).
final class ProjectFilesQuery {
  const ProjectFilesQuery({
    required this.cwd,
    required this.projectTrusted,
    required this.contextMaxBytes,
    required this.cancel,
  });

  /// Канонический корень сессии.
  final String cwd;

  /// `cwd` равен одному из `CoreConfig.trustedProjects` (D4).
  final bool projectTrusted;

  /// `tools.project_context.max_bytes`; `0` — контекст не читается.
  final int contextMaxBytes;

  /// Закрытие сессии или рантайма: результат после отмены выбрасывается (D6).
  final CancelToken cancel;
}

/// Результат чтения (D1): сырые файлы и диагностика.
final class ProjectFiles {
  const ProjectFiles({
    this.context = const [],
    this.contextRoot = ContextRoot.cwd,
    this.templates = const [],
    this.agents = const [],
    this.diagnostics = const [],
  });

  static const empty = ProjectFiles();

  /// Файлы инструкций от общего к частному: пользовательский, затем от корня
  /// к `cwd` (D5, пункт 1).
  final List<ContextFile> context;
  final ContextRoot contextRoot;

  /// Шаблоны команд (итерация 2).
  final List<MarkdownFile> templates;

  /// Определения агентов (итерация 3).
  final List<MarkdownFile> agents;
  final List<ExtensionDiagnostic> diagnostics;
}

/// Порт чтения файлов проекта.
abstract interface class ProjectFilesSource {
  /// Читает файлы по [query]. НЕ бросает исключений для ошибок файлов: всё
  /// уходит в [ProjectFiles.diagnostics] (D6). Непредвиденное исключение
  /// ловит runtime и создаёт сессию без файлов проекта.
  Future<ProjectFiles> load(ProjectFilesQuery query);
}
