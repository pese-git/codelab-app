import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../config/yaml_reader.dart';

/// Результат [readMarkdownFile]: файл либо диагностики, не оба сразу.
///
/// Инвариант: [file] равен `null` тогда и только тогда, когда [diagnostics]
/// не пуст. Файл с ошибкой frontmatter в `ProjectFiles` не попадает.
final class MarkdownRead {
  const MarkdownRead.file(MarkdownFile this.file) : diagnostics = const [];

  const MarkdownRead.failed(this.diagnostics) : file = null;

  final MarkdownFile? file;
  final List<ExtensionDiagnostic> diagnostics;
}

/// Отделяет frontmatter от тела и разбирает его в строгом профиле CFG-21
/// (design.md change `add-agent-project-files`, D3, пункт 1;
/// `agent-core-architecture` §15.5, §17.2.2).
///
/// Почему поверх `readYamlTree`: ошибки frontmatter должны выглядеть как
/// ошибки `config.yaml` — тот же профиль (без якорей, тегов, повторяющихся
/// ключей) и те же позиции; вторая реализация разошлась бы с первой.
///
/// Для чего: `ProjectFilesLoader` превращает текст файла в [MarkdownFile]
/// (`frontmatter` — `ConfigTree`, `body`, `bodyLine`), а ядро проверяет поля
/// (`parseCommandTemplates`). YAML ядро не знает (CFG-5).
///
/// Как использовать: `readMarkdownFile(text, path: …, scope: …)`.
/// - Первая строка (после BOM) равна `---` → frontmatter до следующей строки
///   `---`; пробелы в конце строки допустимы; CRLF читается как LF, тело
///   возвращается с LF.
/// - Первой строки `---` нет → frontmatter нет, тело — весь текст.
/// - Незакрытый `---` → `error` `syntax` на строке 1. Нарушение профиля или
///   синтаксис YAML → `error` `profile` / `syntax`; позиции — в координатах
///   файла, а не блока (`readYamlTree(lineOffset: 1)`), в том числе позиция
///   «first defined at» повторного ключа в тексте сообщения.
/// Сообщения строит `readYamlTree` из фиксированных текстов: фрагментов файла
/// в них нет (секрет не попадёт в лог, D14).
MarkdownRead readMarkdownFile(
  String text, {
  required String path,
  required ExtensionScope scope,
}) {
  var source = text.startsWith('\u{FEFF}') ? text.substring(1) : text;
  source = source.replaceAll('\r\n', '\n');
  final lines = source.split('\n');
  if (lines.first.trimRight() != '---') {
    return MarkdownRead.file(
      MarkdownFile(path: path, scope: scope, body: source, bodyLine: 1),
    );
  }

  final close = lines.indexWhere((l) => l.trimRight() == '---', 1);
  if (close < 0) {
    return MarkdownRead.failed([
      ExtensionDiagnostic(
        path: path,
        line: 1,
        column: 1,
        level: DiagnosticLevel.error,
        code: 'syntax',
        message: 'the frontmatter is not closed by a "---" line',
      ),
    ]);
  }

  // Блок YAML начинается со второй строки файла: `lineOffset` переводит
  // позиции в координаты файла прямо в разборщике.
  final result = readYamlTree(
    lines.sublist(1, close).join('\n'),
    source: path,
    kind: scope == ExtensionScope.project
        ? ConfigLayerKind.project
        : ConfigLayerKind.user,
    lineOffset: 1,
  );
  final tree = result.tree;
  if (tree == null) {
    return MarkdownRead.failed([
      for (final issue in result.issues)
        ExtensionDiagnostic(
          path: path,
          line: issue.line ?? 1,
          column: issue.column,
          level: DiagnosticLevel.error,
          code: issue.kind == ConfigIssueKind.syntax ? 'syntax' : 'profile',
          message: issue.message,
        ),
    ]);
  }

  return MarkdownRead.file(
    MarkdownFile(
      path: path,
      scope: scope,
      frontmatter: tree,
      body: lines.sublist(close + 1).join('\n'),
      bodyLine: close + 2,
    ),
  );
}
