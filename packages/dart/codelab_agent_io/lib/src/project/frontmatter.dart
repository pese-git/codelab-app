import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../config/yaml_reader.dart';

/// Результат [readMarkdownFile]: файл либо диагностики, не оба сразу.
///
/// Инвариант: [file] равен `null` тогда и только тогда, когда [diagnostics]
/// не пуст. Файл с ошибкой frontmatter в `ProjectFiles` не попадает.
final class MarkdownRead {
  const MarkdownRead.file(MarkdownFile this.file, {this.repaired = false})
    : diagnostics = const [];

  const MarkdownRead.failed(this.diagnostics) : file = null, repaired = false;

  /// Разбор удался только после починки YAML (`repairYaml: true`, навыки,
  /// design.md change `add-agent-skills`, D4): диагностику `yaml_repaired`
  /// по признаку выдаёт ядро (`parseSkills`).
  final bool repaired;

  /// Разобранный файл; `null`, если frontmatter не разобран.
  final MarkdownFile? file;

  /// Причины отказа (позиции в файле); пусто, когда [file] есть.
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
///
/// [repairYaml] (только навыки, D4): если разбор не удался, строки верхнего
/// уровня `ключ: значение` со значением без кавычек и с `: ` внутри один раз
/// переписываются в строки в одинарных кавычках YAML (`'` удваивается;
/// одинарные кавычки не обрабатывают `\`, поэтому `C:\temp` и `"` остаются
/// как есть) и блок разбирается снова. Успех — `repaired`; неудача —
/// диагностики первого разбора, с позициями исходного файла. Номера строк при
/// починке не меняются. Шаблоны и определения агентов остаются строгими.
MarkdownRead readMarkdownFile(
  String text, {
  required String path,
  required ExtensionScope scope,
  bool repairYaml = false,
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
  final kind = scope == ExtensionScope.project
      ? ConfigLayerKind.project
      : ConfigLayerKind.user;
  final block = lines.sublist(1, close);
  var result = readYamlTree(
    block.join('\n'),
    source: path,
    kind: kind,
    lineOffset: 1,
  );
  var repaired = false;
  if (result.tree == null && repairYaml) {
    final fixed = _quoteColonValues(block);
    if (fixed != null) {
      final second = readYamlTree(
        fixed.join('\n'),
        source: path,
        kind: kind,
        lineOffset: 1,
      );
      if (second.tree != null) {
        result = second;
        repaired = true;
      }
    }
  }
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
    repaired: repaired,
  );
}

// Строка верхнего уровня `ключ: значение`: ключ — простой идентификатор.
final _topLevelPair = RegExp(r'^([A-Za-z0-9_][A-Za-z0-9_.-]*):[ \t]+(\S.*)$');

// Значение начинается с индикатора YAML (кавычка, блок, поток, якорь, тег,
// комментарий): это не «простая строка», её не трогаем.
const _yamlIndicators = '"\'|>[{&*!#%@`';

/// Переписывает значения без кавычек с `: ` в строки в одинарных кавычках;
/// `null`, если переписывать нечего.
List<String>? _quoteColonValues(List<String> block) {
  var changed = false;
  final out = <String>[];
  for (final line in block) {
    final match = _topLevelPair.firstMatch(line);
    if (match != null) {
      // Значение без кавычек: хвостовой комментарий (` #…`) в него не входит
      // и не должен превращать bool/число в строку из-за `: ` в комментарии.
      var value = match.group(2)!;
      final comment = RegExp(r'[ \t]#').firstMatch(value);
      if (comment != null) {
        value = value.substring(0, comment.start);
      }
      value = value.trimRight();
      if (value.isNotEmpty &&
          !_yamlIndicators.contains(value[0]) &&
          value.contains(': ')) {
        out.add("${match.group(1)}: '${value.replaceAll("'", "''")}'");
        changed = true;
        continue;
      }
    }
    out.add(line);
  }
  return changed ? out : null;
}
