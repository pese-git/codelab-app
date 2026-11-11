import 'package:meta/meta.dart';

/// Вид записи папки проекта.
///
/// Почему: браузер файлов должен отличать ссылку, ведущую за корень, от
/// обычной папки или файла, иначе выход наружу превратится в обычное
/// раскрытие (design.md change `add-file-preview-and-tree`, D2, D3).
///
/// Для чего: хост рисует значок и решает, можно ли раскрыть или открыть запись.
/// Как использовать: значение выставляет реализация порта [ProjectFiles].
enum ProjectEntryKind {
  /// Обычный файл (в том числе ссылка на файл внутри корня).
  file,

  /// Папка (в том числе ссылка на папку внутри корня).
  directory,

  /// Символическая ссылка с целью вне корня: показывается (↗), но не
  /// раскрывается и не открывается (Q2).
  symlinkOutside,

  /// Всё прочее: битая ссылка, сокет, канал, устройство.
  other,
}

/// Причина отказа операции порта [ProjectFiles].
enum ProjectFilesFailureKind {
  /// Путь после разрешения ссылок лежит вне корня.
  outsideRoot,

  /// Файла или папки нет.
  notFound,

  /// Нет прав или иная ошибка чтения.
  unreadable,

  /// Относительный путь недопустим: `\0`, абсолютный или `..`, уводящий выше
  /// корня (внутренний `a/b/../c` допустим и схлопывается).
  invalidPath,
}

/// Типизированная ошибка чтения папки проекта.
///
/// Почему: хосту нужно отличать «вышли за корень» от «нет файла» без разбора
/// текста (`docs/architecture/error-handling.md`, AGENTS.md §15).
///
/// Для чего: единый вид отказа для всех реализаций [ProjectFiles] и для
/// чистых правил kit. Текст не содержит содержимого файла (D2, D5).
///
/// Как использовать: ловить в Cubit-е панели; [relativePath] — путь от корня
/// в том виде, в каком его запросил вызывающий.
final class ProjectFilesFailure implements Exception {
  const ProjectFilesFailure(this.kind, this.relativePath);

  /// Причина отказа; по ней хост выбирает текст и поведение.
  final ProjectFilesFailureKind kind;

  /// Запрошенный путь для диагностики хоста. В [toString] он НЕ попадает:
  /// путь может раскрыть структуру проекта, а события пишут его только на
  /// уровне debug (D5).
  final String relativePath;

  @override
  String toString() => 'ProjectFilesFailure(${kind.name})';
}

/// Запись перечисления папки проекта.
///
/// Как использовать: [relativePath] — POSIX-путь от корня без начального
/// `/`; [size] задан только у файлов.
@immutable
final class ProjectEntry {
  const ProjectEntry({
    required this.relativePath,
    required this.name,
    required this.kind,
    this.size,
  });

  /// POSIX-путь от корня без начального `/`; ключ строки дерева.
  final String relativePath;

  /// Последний сегмент пути, как его рисует дерево.
  final String name;

  final ProjectEntryKind kind;

  /// Размер в байтах; `null` у не-файлов и если размер не удалось получить.
  final int? size;

  @override
  bool operator ==(Object other) =>
      other is ProjectEntry &&
      other.relativePath == relativePath &&
      other.name == name &&
      other.kind == kind &&
      other.size == size;

  @override
  int get hashCode => Object.hash(relativePath, name, kind, size);

  @override
  String toString() => 'ProjectEntry($relativePath, ${kind.name}, $size)';
}

/// Один уровень папки проекта.
///
/// Почему: огромные папки не должны вешать дерево, поэтому перечисление
/// усечено, а число отброшенных записей известно (`omitted`, D2).
///
/// Как использовать: [entries] уже отсортированы (папки, затем файлы, по
/// имени без учёта регистра, [sortProjectEntries]); `.git` в них нет.
@immutable
final class DirectoryListing {
  const DirectoryListing({
    required this.relativeDir,
    required this.entries,
    this.omitted = 0,
  });

  /// Папка от корня; пустая строка — сам корень.
  final String relativeDir;
  final List<ProjectEntry> entries;

  /// Сколько записей не вошло из-за лимита `maxEntries`.
  final int omitted;
}

/// Результат чтения файла для просмотра (закрытая иерархия, D2, D4).
sealed class FilePreview {
  const FilePreview();
}

/// Текст файла: просмотр показывает его как есть (Q3).
///
/// Почему отдельный класс: двоичный и слишком большой файл не несут текста,
/// и закрытая иерархия не даёт показать то, чего нет (D4).
final class TextPreview extends FilePreview {
  const TextPreview(this.text);

  /// Содержимое. НЕ ДОЛЖНО попадать в логи, диагностику и снимок (D5).
  final String text;
}

/// Двоичный файл (NUL в первых 8 КиБ): просмотр пишет «Binary file (N KB)».
///
/// [size] — размер файла в байтах.
final class BinaryPreview extends FilePreview {
  const BinaryPreview(this.size);

  final int size;
}

/// Файл больше `maxBytes`: просмотр пишет «File too large to preview».
///
/// [size] — полный размер в байтах, а не прочитанная часть.
final class TooLargePreview extends FilePreview {
  const TooLargePreview(this.size);

  final int size;
}

/// Порт чтения папки проекта в границах корня.
///
/// Почему: браузер файлов — чтение клиента, а не ACP `fs/*`; граница корня
/// здесь строже лексической (realpath), а `dart:io` kit запрещён, поэтому
/// порт объявлен в kit, а реализация — в `codelab_client_io` (D1, D3).
///
/// Для чего: единственный путь хоста к файлам проекта для панели Files.
/// Политику (что двоичное, большое, похоже на секрет) держат чистые
/// правила kit, реализация только читает.
///
/// Как использовать: `root` — результат [canonicalRoot]; пути `relative*` —
/// POSIX от корня. Любая операция проверяет путь до открытия и при отказе
/// бросает [ProjectFilesFailure].
abstract interface class ProjectFiles {
  /// realpath папки; [ProjectFilesFailure] `notFound`, если её нет.
  Future<String> canonicalRoot(String folder);

  /// Один уровень папки [relativeDir] (пусто — корень), не больше
  /// [maxEntries] записей; остаток в `omitted`.
  Future<DirectoryListing> list(
    String root,
    String relativeDir, {
    int maxEntries = 5000,
  });

  /// Просмотр файла: читается не больше `maxBytes + 1` байт.
  Future<FilePreview> read(
    String root,
    String relativePath, {
    int maxBytes = 1 << 20,
  });
}
