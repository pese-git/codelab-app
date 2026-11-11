import 'dart:convert';
import 'dart:typed_data';

import 'project_files.dart';

/// Сколько первых байт файла проверяется на NUL при классификации.
///
/// Почему 8 КиБ: этого хватает, чтобы заметить двоичный формат по заголовку,
/// и мало, чтобы проверка стоила заметного времени (design.md change
/// `add-file-preview-and-tree`, D4).
const _binarySniffBytes = 8 * 1024;

/// Приводит относительный путь к виду «POSIX от корня без `.` и `//`».
///
/// Почему: путь приходит из UI и от вызовов агента; выход за корень через `..`
/// должен отклоняться до обращения к диску (D3, шаг 1; требование
/// `workspace-file-browser` «Граница рабочей папки браузера»). Правило —
/// в kit без `package:path`, чтобы быть web-безопасным и общим для всех
/// реализаций [ProjectFiles] (D1).
///
/// Для чего: первая, лексическая линия границы; вторую (realpath) держит
/// реализация порта.
///
/// Как использовать: `''` — сам корень. Сегменты `.` и пустые отбрасываются,
/// `..` снимает предыдущий сегмент; `..` выше корня, `\0` или абсолютный
/// путь дают [ProjectFilesFailure] `invalidPath`.
String normalizeRelativePath(String path) {
  if (path.contains('\u0000') || path.startsWith('/')) {
    throw ProjectFilesFailure(ProjectFilesFailureKind.invalidPath, path);
  }
  final out = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isEmpty) {
        throw ProjectFilesFailure(ProjectFilesFailureKind.invalidPath, path);
      }
      out.removeLast();
      continue;
    }
    out.add(segment);
  }
  return out.join('/');
}

/// Решает, что показать в просмотре, по голове файла и его размеру.
///
/// Почему: политика «двоичный / слишком большой / текст» нужна всем
/// реализациям порта одинаковая и проверяема без файловой системы (D4).
/// Расширение файла не учитывается: `notes.txt` с NUL — двоичный.
///
/// Как использовать: [head] — не меньше `min(size, maxBytes + 1)` первых
/// байт файла (реализация читает не больше `maxBytes + 1`); [size] — полный
/// размер файла. Порядок: NUL в первых 8 КиБ → [BinaryPreview]; иначе
/// `size > maxBytes` → [TooLargePreview]; иначе [TextPreview] в UTF-8 с
/// заменой неверных байт на U+FFFD.
FilePreview classifyPreview(
  Uint8List head, {
  required int size,
  int maxBytes = 1 << 20,
}) {
  final sniff = head.length < _binarySniffBytes
      ? head.length
      : _binarySniffBytes;
  for (var i = 0; i < sniff; i++) {
    if (head[i] == 0) return BinaryPreview(size);
  }
  if (size > maxBytes) return TooLargePreview(size);
  return TextPreview(utf8.decode(head, allowMalformed: true));
}

/// Похоже ли имя файла на файл с секретами: `.env*`, `*.pem`, `*.key`, `id_*`.
///
/// Почему: решение Q3 — такие файлы показываются как есть, но с
/// предупреждением; правило одно на браузер и будущие вложения (D-12,
/// `maybeSecret` §12.1.7), чтобы они не разошлись (D5).
///
/// Как использовать: передавать имя без каталога (`ProjectEntry.name`).
/// Регистр не учитывается (Q15): `.ENV` и `Server.PEM` совпадают, потому что
/// на файловых системах без учёта регистра это те же файлы.
bool isMaybeSecretFileName(String name) {
  final lower = name.toLowerCase();
  return lower.startsWith('.env') ||
      lower.endsWith('.pem') ||
      lower.endsWith('.key') ||
      lower.startsWith('id_');
}

/// Переводит абсолютный путь места вызова в путь от корня браузера.
///
/// Почему: ACP `ToolCallLocation.path` абсолютный и может идти через другой
/// путь к той же папке (macOS: `/tmp` и `/private/tmp`), поэтому снимается
/// префикс либо [sessionCwd], либо канонического [root] (D8).
///
/// Для чего: «Open file» и Following открывают в Files только то, что внутри
/// корня; окончательную проверку делает реализация порта (D3).
///
/// Как использовать: [sessionCwd] и [root] — абсолютные пути; пустая база
/// пропускается. Возвращает POSIX-путь от корня или `null`, если путь
/// относительный, вне обоих префиксов, выходит за корень через `..` или
/// указывает на сам корень (место вызова — файл). Путь POSIX; Windows-пути
/// kit не разбирает.
String? relativeToRoot(
  String absolutePath, {
  required String sessionCwd,
  required String root,
}) {
  if (!absolutePath.startsWith('/')) return null;
  for (final base in [sessionCwd, root]) {
    // Пустая база дала бы префикс «/» и приняла бы любой абсолютный путь.
    if (base.isEmpty) continue;
    final prefix = base.endsWith('/') ? base : '$base/';
    if (!absolutePath.startsWith(prefix)) continue;
    try {
      final relative = normalizeRelativePath(
        absolutePath.substring(prefix.length),
      );
      return relative.isEmpty ? null : relative;
    } on ProjectFilesFailure {
      continue;
    }
  }
  return null;
}

/// Упорядочивает записи перечисления: папки, затем остальное, по имени без
/// учёта регистра (D2).
///
/// Как использовать: реализация порта вызывает перед усечением до
/// `maxEntries`, чтобы «лишними» оказывались последние по порядку. Равные без
/// учёта регистра различаются по точному имени — порядок детерминирован.
/// Исходный список не меняется.
List<ProjectEntry> sortProjectEntries(Iterable<ProjectEntry> entries) {
  int rank(ProjectEntry e) => e.kind == ProjectEntryKind.directory ? 0 : 1;
  return entries.toList()..sort((a, b) {
    final byKind = rank(a).compareTo(rank(b));
    if (byKind != 0) return byKind;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.name.compareTo(b.name);
  });
}
