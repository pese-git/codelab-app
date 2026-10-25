import 'dart:convert';
import 'dart:typed_data';

import '../../env/execution_env.dart';
import '../../llm/messages.dart';
import '../../util/result.dart';
import '../../prompts/prompts.g.dart';
import '../agent_tool.dart';
import '../fence.dart';
import '../truncate.dart';
import 'common.dart';

const _defaultLimit = 2000;
const _maxLineLength = 2000;
const _binaryProbe = 8 * 1024;
const _maxImageBytes = 4 * 1024 * 1024;

/// Картинки, которые `read` отдаёт модели блоком `ImageContent` (§6.4,
/// шаг 2): расширение → MIME-тип.
const _imageTypes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
};

/// `read` — пронумерованные строки текстового файла или картинка
/// (`agent-core-architecture` §6.4).
///
/// Почему номера строк: по ним модель ссылается на место в файле и
/// продолжает чтение с `offset`; сам текст для `edit` она копирует без
/// префикса.
///
/// Как использовать: модель передаёт `path` и при необходимости `offset` и
/// `limit`. Картинку инструмент отдаёт, только если env реализует
/// `BinaryFiles`, а модель шага принимает картинки
/// (`ToolContext.supportsImages`); иначе — текст ошибки. Вывод усекается
/// самим инструментом с уведомлением, как продолжить.
final class ReadTool extends AgentTool {
  @override
  String get name => 'read';

  /// Текст — в `prompts/tool_descriptions/read.md` (PR-2); лимиты
  /// подставляются из констант усечения.
  @override
  String get description => Prompts.toolDescriptionsRead.render({
    'maxLines': '$defaultMaxLines',
    'maxKb': '${defaultMaxBytes ~/ 1024}',
  });

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'File path, relative to the workspace root or absolute.',
      },
      'offset': {
        'type': 'integer',
        'description': '1-based line number to start from. Default 1.',
      },
      'limit': {
        'type': 'integer',
        'description': 'Maximum number of lines. Default 2000.',
      },
    },
    'required': ['path'],
  };

  @override
  ToolTier get tier => ToolTier.read;

  @override
  ToolKind get kind => ToolKind.read;

  /// Сторонние файлы (`node_modules`, `.dart_tool`, `vendor`) — данные,
  /// которым модель не подчиняется (§6.3.6).
  @override
  ContentTrust outputTrust(Map<String, Object?> args) =>
      isUntrustedPath(pathPattern('${args['path']}', ''))
      ? ContentTrust.untrusted
      : ContentTrust.trusted;

  @override
  String permissionPattern(Map<String, Object?> args, String cwd) =>
      pathPattern('${args['path'] ?? '.'}', cwd);

  @override
  bool get truncatesOutput => true;

  @override
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    // Сырые аргументы бывают без path: вызов ещё не валидирован (§6.2).
    final path = args['path'];
    if (path is! String) {
      return ToolPresentation(title: name);
    }
    final abs = absolutePath(ctx, path);
    final offset = args['offset'];
    return ToolPresentation(
      title: 'Read ${displayPath(ctx, path)}',
      locations: [
        if (abs != null) Location(abs, line: offset is int ? offset : null),
      ],
    );
  }

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final path = args['path']! as String;
    if (_imageTypes[_extension(path)] case final mime?) {
      return _image(ctx, path, mime);
    }
    final limit = args['limit'] as int? ?? _defaultLimit;
    if (limit < 1) {
      return errorResult('limit must be >= 1');
    }
    var offset = args['offset'] as int? ?? 1;
    final notes = <String>[];
    if (offset < 1) {
      offset = 1;
      notes.add('[Note: offset must be >= 1; using 1.]');
    }
    final String text;
    switch (await ctx.env.readText(path, line: offset, limit: limit + 1)) {
      case Ok(:final value):
        text = value;
      case Err(:final error):
        return errorResult(fileErrorText(error, ctx, path));
    }
    final display = displayPath(ctx, path);
    final probe = text.length > _binaryProbe
        ? text.substring(0, _binaryProbe)
        : text;
    if (probe.contains('\u0000')) {
      return errorResult('$display appears to be a binary file.');
    }
    var lines = splitLines(text);
    final hasMore = lines.length > limit;
    if (hasMore) {
      lines = lines.sublist(0, limit);
    }
    if (lines.isEmpty) {
      return ToolExecutionResult([
        TextContent(
          [
            offset == 1 ? '(empty file)' : 'No lines at offset $offset.',
            ...notes,
          ].join('\n'),
        ),
      ]);
    }
    final numbered = [
      for (final (i, line) in lines.indexed)
        '${offset + i}| ${line.length > _maxLineLength ? '${line.substring(0, _maxLineLength)}$lineTruncatedSuffix' : line}',
    ];
    final cut = truncateHead(numbered.join('\n'));
    final out = [cut.text];
    if (cut.truncated || hasMore) {
      final last = offset + cut.keptLines - 1;
      out.add(
        TruncationNotices.read(
          first: offset,
          last: last,
          total: await _totalLines(ctx, path),
        ),
      );
    }
    out.addAll(notes);
    return ToolExecutionResult([TextContent(out.join('\n'))]);
  }

  /// Картинка: `ImageContent` и подпись с размером. Без `BinaryFiles` или
  /// без поддержки картинок у модели — ошибка; больше 4 МиБ — тоже.
  static Future<ToolExecutionResult> _image(
    ToolContext ctx,
    String path,
    String mime,
  ) async {
    final display = displayPath(ctx, path);
    final env = ctx.env;
    if (env is! BinaryFiles || !ctx.supportsImages) {
      return errorResult(
        'Cannot show image $display: the current model or environment does '
        'not support images.',
      );
    }
    final Uint8List bytes;
    switch (await (env as BinaryFiles).readBytes(path)) {
      case Ok(:final value):
        bytes = value;
      case Err(:final error):
        return errorResult(fileErrorText(error, ctx, path));
    }
    if (bytes.length > _maxImageBytes) {
      return errorResult('Image is too large');
    }
    return ToolExecutionResult([
      ImageContent(base64: base64Encode(bytes), mimeType: mime),
      TextContent('Image $display (${bytes.length} bytes)'),
    ]);
  }

  static String _extension(String path) {
    final name = path.substring(path.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// Число строк, когда env может дёшево прочитать файл целиком; `null` —
  /// неизвестно (ACP-клиент).
  static Future<int?> _totalLines(ToolContext ctx, String path) async {
    final env = ctx.env;
    if (env is! BinaryFiles) {
      return null;
    }
    return switch (await (env as BinaryFiles).readBytes(path)) {
      Ok(:final value) => splitLines(
        utf8.decode(value, allowMalformed: true),
      ).length,
      Err() => null,
    };
  }
}
