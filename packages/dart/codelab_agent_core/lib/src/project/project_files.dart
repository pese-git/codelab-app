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
/// функциями (`assembleProjectContext` для инструкций, `parseCommandTemplates` для
/// шаблонов команд, `parseAgentDefinitions` для определений агентов).
///
/// Как использовать: хост кладёт реализацию в `AgentCoreServices.projectFiles`;
/// `null` значит «файлов проекта нет» (web, мобильные хосты, тесты) и
/// поведение прежнее.
library;

import '../cancel/cancel_token.dart';
import '../config/config_tree.dart';

/// Откуда файл: область определяет доверие и приоритет (D4).
///
/// Почему enum: файл репозитория и файл пользователя получают разное доверие
/// (CFG-6), а при совпадении имён проект заменяет пользователя; строковый
/// признак допускал бы опечатки.
///
/// Как использовать: загрузчик ставит значение в [ContextFile.scope] и
/// [MarkdownFile.scope]; ядро по нему решает приоритет и формулирует
/// диагностики.
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

/// Серьёзность диагностики файла (D6).
///
/// Почему три уровня: сообщение «файл пропущен» (`error`/`warning`) нужно
/// отличать от справочного («перекрыт», «проект не доверен» — `info`), иначе
/// пользователь привыкнет не читать вывод `config check`.
///
/// Как использовать: загрузчик и разборщики задают уровень в
/// [ExtensionDiagnostic.level]; ядро переносит его в уровень записи лога.
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

  /// Номер строки файла (с 1); `null` — диагностика относится к файлу целиком.
  final int? line;

  /// Номер столбца (с 1); `null`, если позиция неизвестна.
  final int? column;

  /// Серьёзность: по ней хост решает, показывать ли строку как ошибку.
  final DiagnosticLevel level;

  /// Стабильный код: `outside_root`, `not_utf8`, `shadowed`, `limit_exceeded`,
  /// `untrusted_project`, `unexpected` и т. д. (D3, D6).
  final String code;

  /// Фиксированный английский текст для пользователя; без фрагментов файла
  /// (D14).
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
/// (D3). Проверяют его `parseCommandTemplates` и `parseAgentDefinitions`.
///
/// Почему отдельно от [ContextFile]: у файлов расширений есть frontmatter и
/// номер строки тела для диагностик, а у инструкций проекта текст идёт в
/// промпт целиком и подчиняется бюджету.
///
/// Как использовать: загрузчик собирает значение из текста файла; поля
/// frontmatter ядро проверяет само, YAML не знает (CFG-5).
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

  /// Область файла: от неё зависят доверие и приоритет при совпадении имён.
  final ExtensionScope scope;

  /// Разобранный frontmatter со строками файла; `null` — frontmatter нет.
  final ConfigTree? frontmatter;

  /// Текст после frontmatter: тело шаблона или профиль агента как есть.
  final String body;

  /// Номер строки файла, с которой начинается [body] (с 1).
  final int bodyLine;
}

/// Откуда взят корень обхода контекста (D5): лог `project_context.loaded`.
///
/// Почему возвращается значением: по логу видно, нашёл ли загрузчик
/// репозиторий или искал только в `cwd`; от этого зависит, какие файлы
/// инструкций вошли в промпт.
///
/// Как использовать: загрузчик кладёт значение в [ProjectFiles.contextRoot],
/// ядро пишет его имя в поле `root` лога.
enum ContextRoot {
  /// Нашёлся каталог с записью `.git`.
  git,

  /// Репозитория нет: корень — `cwd`.
  cwd,
}

/// Запрос порту (D1).
///
/// Почему отдельный объект: порт читает файлы до ответа `session/new`, когда
/// у клиента ещё нет `sessionId` (D2), поэтому всё нужное — каталог, доверие,
/// бюджет и отмена — приходит в запросе, а не из состояния сессии.
///
/// Как использовать: рантайм создаёт запрос при открытии сессии и передаёт в
/// [ProjectFilesSource.load]; хост ничего в нём не меняет.
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
///
/// Почему «сырые»: хост только читает файлы, а проверку и применение делает
/// ядро чистыми функциями (PKG-1); ошибка файла — запись в [diagnostics], а не
/// исключение (D6).
///
/// Как использовать: порт возвращает значение из [ProjectFilesSource.load];
/// [ProjectFiles.empty] — «файлов нет».
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

  /// Откуда взят корень обхода [context]: репозиторий или только `cwd`.
  final ContextRoot contextRoot;

  /// Файлы шаблонов команд (`prompts/*.md`).
  final List<MarkdownFile> templates;

  /// Файлы определений агентов (`agents/*.md`).
  final List<MarkdownFile> agents;

  /// Всё, что хост не смог или не стал читать: недоверенный проект, файл вне
  /// корня, слишком большой файл (D6). Тексты файлов сюда не попадают (D14).
  final List<ExtensionDiagnostic> diagnostics;
}

/// Порт чтения файлов проекта.
///
/// Почему порт: чтение идёт с файловой системы агента, а ядро не имеет
/// `dart:io` (PKG-1); реализацию даёт хост (`ProjectFilesLoader` в
/// `codelab_agent_io`).
///
/// Как использовать: хост кладёт реализацию в `AgentCoreServices.projectFiles`;
/// рантайм вызывает [load] один раз при открытии сессии.
abstract interface class ProjectFilesSource {
  /// Читает файлы по [query]. НЕ бросает исключений для ошибок файлов: всё
  /// уходит в [ProjectFiles.diagnostics] (D6). Непредвиденное исключение
  /// ловит runtime и создаёт сессию без файлов проекта.
  Future<ProjectFiles> load(ProjectFilesQuery query);
}
