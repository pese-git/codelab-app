/// Сборка контекста проекта для системного промпта (design.md change
/// `add-agent-project-files`, D5; `agent-core-architecture` §11.5, шаг 10).
///
/// Почему чистая функция в ядре: бюджет, усечение и порядок — логика, которую
/// должны одинаково получить любые хосты (настольный, мобильный, встроенный),
/// а чтение файлов и разбор — дело хоста (D1).
///
/// Для чего: `assembleProjectContext` превращает прочитанные [ContextFile] в
/// [ProjectContext], который `composeSystemPrompt` рендерит секцией
/// `project_context`.
///
/// Как использовать: runtime вызывает функцию с `ProjectFiles.context` и
/// `tools.project_context.max_bytes`; результат кладётся в
/// `PromptInputs.projectContext`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'project_files.dart';

/// Файл, вошедший в секцию.
final class ProjectContextFile {
  const ProjectContextFile({
    required this.path,
    required this.text,
    required this.shownBytes,
    required this.totalBytes,
    required this.truncated,
  });

  /// Путь в секции (D5, пункт 6).
  final String path;

  /// Текст блока вместе с пометкой `[file truncated: …]`, если файл усечён.
  /// Закрывающий тег блока здесь НЕ экранирован: экранирует рендер секции,
  /// последний рубеж перед промптом.
  final String text;

  /// Байты оставленного текста (`N` пометки).
  final int shownBytes;

  /// Полный размер файла (`M` пометки).
  final int totalBytes;
  final bool truncated;
}

/// Итог сборки: файлы секции от общего к частному и число пропущенных.
final class ProjectContext {
  ProjectContext({required List<ProjectContextFile> files, this.omitted = 0})
    : files = List.unmodifiable(files);

  final List<ProjectContextFile> files;

  /// Файлы, не вошедшие из-за исчерпанного бюджета (D5, пункт 4).
  final int omitted;

  /// Сумма байт оставленного текста: расход бюджета.
  int get bytes => files.fold(0, (sum, f) => sum + f.shownBytes);

  /// Число усечённых файлов.
  int get truncated => files.where((f) => f.truncated).length;
}

/// Собирает контекст по правилам D5.
///
/// [files] — от общего к частному (так их отдаёт `ProjectFiles.context`);
/// порядок результата тот же. Бюджет [maxBytes] (байты UTF-8, без пометок об
/// усечении) раздаётся в обратном порядке: сначала самому частному файлу
/// (ближайшему к `cwd`, E-01).
///
/// Файл, не поместившийся целиком, усекается по последней границе строки в
/// остатке бюджета; если в остатке нет ни одного перевода строки (одна
/// длинная первая строка), — по границе символа UTF-8, чтобы файл не терялся
/// молча. После усечения бюджет считается исчерпанным: обрывок дальнего
/// файла в оставшиеся байты не вставляется. Пустые после обрезки пробелов
/// файлы пропускаются и в `omitted` не считаются.
///
/// Возвращает `null`, если [maxBytes] не положителен или ни один файл не
/// вошёл (секции нет).
ProjectContext? assembleProjectContext(List<ContextFile> files, int maxBytes) {
  if (maxBytes <= 0) {
    return null;
  }
  var remaining = maxBytes;
  var exhausted = false;
  var omitted = 0;
  final taken = <ProjectContextFile>[];
  for (final file in files.reversed) {
    final text = file.content.trim();
    if (text.isEmpty) {
      continue;
    }
    if (exhausted || remaining <= 0) {
      omitted++;
      continue;
    }
    final bytes = Uint8List.fromList(utf8.encode(text));
    if (!file.isPartial && bytes.length <= remaining) {
      taken.add(
        ProjectContextFile(
          path: file.path,
          text: text,
          shownBytes: bytes.length,
          totalBytes: file.totalBytes,
          truncated: false,
        ),
      );
      remaining -= bytes.length;
      continue;
    }
    final kept = _cut(bytes, remaining);
    taken.add(
      ProjectContextFile(
        path: file.path,
        text:
            '${kept.text}\n'
            '[file truncated: showing ${kept.bytes} of ${file.totalBytes} bytes]',
        shownBytes: kept.bytes,
        totalBytes: file.totalBytes,
        truncated: true,
      ),
    );
    exhausted = true;
  }
  if (taken.isEmpty) {
    return null;
  }
  return ProjectContext(files: taken.reversed.toList(), omitted: omitted);
}

/// Начало [bytes] не длиннее [limit]: по границе строки, иначе — символа.
({String text, int bytes}) _cut(Uint8List bytes, int limit) {
  var end = limit < bytes.length ? limit : bytes.length;
  // Граница строки: перевод строки не позже `limit`-го байта.
  var lineEnd = -1;
  for (var i = end; i >= 0; i--) {
    if (i < bytes.length && bytes[i] == 0x0A) {
      lineEnd = i;
      break;
    }
  }
  if (lineEnd > 0) {
    end = lineEnd;
  } else {
    // Нет границы строки: не режем символ UTF-8 посередине.
    while (end > 0 && end < bytes.length && (bytes[end] & 0xC0) == 0x80) {
      end--;
    }
  }
  final text = utf8.decode(Uint8List.sublistView(bytes, 0, end)).trimRight();
  return (text: text, bytes: utf8.encode(text).length);
}
