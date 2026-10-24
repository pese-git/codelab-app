import '../../llm/messages.dart';
import '../../util/result.dart';
import '../../prompts/prompts.g.dart';
import '../agent_tool.dart';
import '../unified_diff.dart';
import 'common.dart';

const _bom = '﻿';

/// `edit` — заменить один точный фрагмент файла (`agent-core-architecture`
/// §6.4).
///
/// Почему точное совпадение: правка по номерам строк или нечёткому поиску
/// молча портит файл, когда модель ошиблась в контексте. Здесь файл не
/// меняется, если `oldText` встречается не ровно один раз (TOOL-8).
///
/// Как использовать: модель передаёт `path`, `oldText` и `newText`. Стиль
/// переводов строк (CRLF) и BOM сохраняются. Точка исполнения держит путь
/// под `PathLock` ([lockPath]), поэтому параллельные правки одного файла
/// применяются по очереди (TOOL-7).
final class EditTool extends AgentTool {
  @override
  String get name => 'edit';

  @override
  String get description => Prompts.toolDescriptionsEdit.render(const {});

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'path': {'type': 'string'},
      'oldText': {
        'type': 'string',
        'description': 'Exact text to replace. Must occur exactly once.',
      },
      'newText': {'type': 'string', 'description': 'Replacement text.'},
    },
    'required': ['path', 'oldText', 'newText'],
  };

  @override
  ToolTier get tier => ToolTier.write;

  @override
  ToolKind get kind => ToolKind.edit;

  @override
  ContentTrust outputTrust(Map<String, Object?> args) => ContentTrust.trusted;

  @override
  String permissionPattern(Map<String, Object?> args, String cwd) =>
      pathPattern('${args['path']}', cwd);

  @override
  String? lockPath(Map<String, Object?> args) =>
      args['path'] is String ? args['path']! as String : null;

  @override
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final path = '${args['path']}';
    final title = 'Edit ${displayPath(ctx, path)}';
    final abs = absolutePath(ctx, path);
    final plan = await _plan(args, ctx);
    if (abs == null || plan is! _Planned) {
      return ToolPresentation(
        title: title,
        locations: [if (abs != null) Location(abs)],
      );
    }
    return ToolPresentation(
      title: title,
      locations: [Location(abs, line: plan.firstLine + 1)],
      diffs: [
        FileDiff(path: abs, oldText: plan.oldFile, newText: plan.newFile),
      ],
    );
  }

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final path = args['path']! as String;
    switch (await _plan(args, ctx)) {
      case _Failed(:final text):
        return errorResult(text);
      case final _Planned plan:
        if (await ctx.env.writeText(path, plan.newFile) case Err(
          :final error,
        )) {
          return errorResult(fileErrorText(error, ctx, path));
        }
        final fragment = replacementFragment(
          oldText: plan.oldLf,
          newText: plan.newLf,
          index: plan.index,
          oldLength: plan.oldLength,
          newLength: plan.newLength,
        );
        return ToolExecutionResult(
          [
            TextContent(
              'Edited ${displayPath(ctx, path)}: replaced lines '
              '${plan.firstLine + 1}-${plan.lastLine + 1}.\n$fragment',
            ),
          ],
          diffs: [
            FileDiff(
              path: absolutePath(ctx, path)!,
              oldText: plan.oldFile,
              newText: plan.newFile,
            ),
          ],
        );
    }
  }

  static Future<_Plan> _plan(Map<String, Object?> args, ToolContext ctx) async {
    final path = '${args['path']}';
    final oldArg = args['oldText'];
    final newArg = args['newText'];
    if (oldArg is! String || newArg is! String) {
      return const _Failed('oldText and newText must be strings.');
    }
    if (oldArg.isEmpty) {
      return const _Failed('oldText must not be empty.');
    }
    if (oldArg == newArg) {
      return const _Failed(
        'oldText and newText are identical; nothing to change.',
      );
    }
    final String file;
    switch (await ctx.env.readText(path)) {
      case Ok(:final value):
        file = value;
      case Err(:final error):
        return _Failed(fileErrorText(error, ctx, path));
    }
    final bom = file.startsWith(_bom);
    final body = bom ? file.substring(1) : file;
    final crlf = _isCrlf(body);
    String lf(String text) => crlf ? text.replaceAll('\r\n', '\n') : text;
    final content = lf(body);
    final oldText = lf(oldArg);
    final newText = lf(newArg);
    final display = displayPath(ctx, path);
    final count = _occurrences(content, oldText);
    if (count == 0) {
      return _Failed(
        'No exact match for oldText in $display. The text must match byte for '
        'byte, including whitespace and indentation. Read the file again '
        'before editing.',
      );
    }
    if (count > 1) {
      return _Failed(
        'oldText occurs $count times in $display. Include more surrounding '
        'context to make it unique.',
      );
    }
    final index = content.indexOf(oldText);
    final newLf = content.replaceRange(index, index + oldText.length, newText);
    final restored = crlf ? newLf.replaceAll('\n', '\r\n') : newLf;
    return _Planned(
      oldFile: file,
      newFile: bom ? '$_bom$restored' : restored,
      oldLf: content,
      newLf: newLf,
      index: index,
      oldLength: oldText.length,
      newLength: newText.length,
      firstLine: lineOf(content, index),
      lastLine: lineOf(content, index + oldText.length - 1),
    );
  }

  /// CRLF style: the file has `\r\n` and no lone `\n`.
  static bool _isCrlf(String text) {
    final crlf = '\r\n'.allMatches(text).length;
    return crlf > 0 && crlf == '\n'.allMatches(text).length;
  }

  /// Occurrences without overlap: the search goes on after each match.
  static int _occurrences(String text, String pattern) {
    var count = 0;
    var from = 0;
    while (true) {
      final i = text.indexOf(pattern, from);
      if (i < 0) {
        return count;
      }
      count++;
      from = i + pattern.length;
    }
  }
}

sealed class _Plan {
  const _Plan();
}

final class _Failed extends _Plan {
  const _Failed(this.text);

  final String text;
}

final class _Planned extends _Plan {
  const _Planned({
    required this.oldFile,
    required this.newFile,
    required this.oldLf,
    required this.newLf,
    required this.index,
    required this.oldLength,
    required this.newLength,
    required this.firstLine,
    required this.lastLine,
  });

  /// Whole files as on disk (BOM, CRLF) — for the diff of ACP.
  final String oldFile, newFile;

  /// Whole files without BOM, with LF — for the fragment for the model.
  final String oldLf, newLf;
  final int index, oldLength, newLength, firstLine, lastLine;
}
