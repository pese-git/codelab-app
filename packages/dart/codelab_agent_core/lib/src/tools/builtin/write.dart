import 'dart:convert';

import '../../env/execution_env.dart';
import '../../llm/messages.dart';
import '../../util/result.dart';
import '../../prompts/prompts.g.dart';
import '../agent_tool.dart';
import 'common.dart';

/// `write` — создать или целиком перезаписать файл (`agent-core-architecture`
/// §6.4).
///
/// Почему отдельный инструмент: `edit` меняет один фрагмент и требует его
/// точного совпадения; новый файл или полная замена содержимого через него
/// невозможны.
///
/// Как использовать: модель передаёт `path` и `content`; родительские
/// каталоги создаются. Точка исполнения держит путь под `PathLock` на всё
/// окно «прочитать старое — записать новое» ([lockPath]), а `present`
/// заранее строит тот же diff для запроса разрешения.
final class WriteTool extends AgentTool {
  @override
  String get name => 'write';

  @override
  String get description => Prompts.toolDescriptionsWrite.render(const {});

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'File path to create or overwrite.',
      },
      'content': {'type': 'string', 'description': 'Full new file content.'},
    },
    'required': ['path', 'content'],
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
    final abs = absolutePath(ctx, path);
    final content = args['content'];
    final title = 'Write ${displayPath(ctx, path)}';
    if (abs == null) {
      return ToolPresentation(title: title);
    }
    final old = await _oldText(ctx, path);
    return ToolPresentation(
      title: title,
      locations: [Location(abs)],
      diffs: [
        if (content is String && old is! _ReadFailed)
          FileDiff(path: abs, oldText: (old as _Old).text, newText: content),
      ],
    );
  }

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final path = args['path']! as String;
    final content = args['content']! as String;
    final String? oldText;
    switch (await _oldText(ctx, path)) {
      case _ReadFailed(:final error):
        return errorResult(fileErrorText(error, ctx, path));
      case _Old(:final text):
        oldText = text;
    }
    if (await ctx.env.writeText(path, content) case Err(:final error)) {
      return errorResult(fileErrorText(error, ctx, path));
    }
    final bytes = utf8.encode(content).length;
    final verb = oldText == null ? 'Created' : 'Overwrote';
    return ToolExecutionResult(
      [TextContent('$verb ${displayPath(ctx, path)} ($bytes bytes).')],
      diffs: [
        FileDiff(
          path: absolutePath(ctx, path)!,
          oldText: oldText,
          newText: content,
        ),
      ],
    );
  }

  /// Старое содержимое: `notFound` — новый файл (`text == null`), прочие
  /// ошибки (каталог, вне рабочей папки) — отказ.
  static Future<_OldRead> _oldText(ToolContext ctx, String path) async =>
      switch (await ctx.env.readText(path)) {
        Ok(:final value) => _Old(value),
        Err(error: FileError(code: FileErrorCode.notFound)) => const _Old(null),
        Err(:final error) => _ReadFailed(error),
      };
}

sealed class _OldRead {
  const _OldRead();
}

final class _Old extends _OldRead {
  const _Old(this.text);

  final String? text;
}

final class _ReadFailed extends _OldRead {
  const _ReadFailed(this.error);

  final FileError error;
}
