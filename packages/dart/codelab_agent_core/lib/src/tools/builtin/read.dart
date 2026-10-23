import 'dart:convert';

import '../../env/execution_env.dart';
import '../../llm/messages.dart';
import '../../util/result.dart';
import '../agent_tool.dart';
import '../truncate.dart';
import 'common.dart';

const _defaultLimit = 2000;
const _maxLineLength = 2000;
const _binaryProbe = 8 * 1024;

/// `read` — numbered lines of a text file (`agent-core-architecture` §6.4).
final class ReadTool extends AgentTool {
  @override
  String get name => 'read';

  @override
  String get description =>
      'Read a text file of the workspace. Lines are numbered "<n>| <text>". '
      'Use offset and limit to read a part of a long file.';

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

  @override
  ContentTrust outputTrust(Map<String, Object?> args) => ContentTrust.trusted;

  @override
  bool get truncatesOutput => true;

  @override
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final path = '${args['path']}';
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

  /// The number of lines when the env can read the whole file cheaply;
  /// `null` — unknown (the ACP client).
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
