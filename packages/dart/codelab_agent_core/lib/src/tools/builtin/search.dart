import 'dart:collection';

import '../../env/execution_env.dart';
import '../../llm/messages.dart';
import '../../util/posix_path.dart';
import '../../util/result.dart';
import '../agent_tool.dart';
import '../fence.dart';
import '../glob.dart';
import '../truncate.dart';
import 'common.dart';

const _defaultLimit = 100;
const _maxFiles = 10000;
const _maxFileBytes = 1 << 20;
const _binaryProbe = 8 * 1024;
const _maxLineLength = 200;

/// Каталоги, которые обход пропускает: служебные и сборочные (§6.4, шаг 2).
const _skippedDirs = {
  '.git',
  '.hg',
  '.svn',
  'node_modules',
  '.dart_tool',
  'build',
  '.idea',
};

/// `search` — поиск по содержимому файлов (`agent-core-architecture` §6.4,
/// T-07).
///
/// Почему свой обход, а не `rg`: одинаковое поведение во всех env (локально,
/// через ACP-клиент, в браузере) и детерминированный вывод для golden-тестов.
///
/// Для чего: обход в ширину от `path`, каталоги в отсортированном порядке;
/// служебные и скрытые каталоги, файлы больше 1 МиБ и бинарные
/// пропускаются; вывод — `<путь>:<строка>: <текст>`.
///
/// Как использовать: регистрируется при capability `fileListing` (§10.7,
/// шаг 5b). `pattern` — `RegExp` Dart или литерал (`literal: true`); `glob`
/// фильтрует пути относительно `path`; лимиты — 100 совпадений и 10 000
/// просмотренных файлов.
final class SearchTool extends AgentTool {
  @override
  String get name => 'search';

  @override
  String get description =>
      'Search file contents of the workspace with a regular expression (Dart '
      'syntax) or literal text. Prints "<path>:<line>: <text>". Skips VCS, '
      'build and hidden directories and binary files.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'pattern': {
        'type': 'string',
        'description': 'Regular expression (Dart syntax) or literal text.',
      },
      'path': {
        'type': 'string',
        'description': 'Directory or file to search. Default: workspace root.',
      },
      'glob': {
        'type': 'string',
        'description': 'Filter by relative path, e.g. **/*.dart',
      },
      'literal': {
        'type': 'boolean',
        'description': 'Treat pattern as plain text. Default false.',
      },
      'ignoreCase': {'type': 'boolean', 'description': 'Default false.'},
      'limit': {
        'type': 'integer',
        'description': 'Maximum matches. Default 100.',
      },
    },
    'required': ['pattern'],
  };

  @override
  ToolTier get tier => ToolTier.read;

  @override
  ToolKind get kind => ToolKind.search;

  /// Совпадения из `node_modules` и подобных каталогов — данные, которым
  /// модель не подчиняется (§6.3.6, P-15).
  @override
  ContentTrust outputTrust(Map<String, Object?> args) =>
      isUntrustedPath(pathPattern('${args['path'] ?? '.'}', ''))
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
    final path = '${args['path'] ?? '.'}';
    final abs = absolutePath(ctx, path);
    return ToolPresentation(
      title: 'Search ${args['pattern']} in ${displayPath(ctx, path)}',
      locations: [if (abs != null) Location(abs)],
    );
  }

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final pattern = args['pattern']! as String;
    final path = args['path'] as String? ?? '.';
    final limit = args['limit'] as int? ?? _defaultLimit;
    if (limit < 1) {
      return errorResult('limit must be >= 1');
    }
    final RegExp regex;
    try {
      regex = RegExp(
        args['literal'] == true ? RegExp.escape(pattern) : pattern,
        caseSensitive: args['ignoreCase'] != true,
      );
    } on FormatException catch (error) {
      return errorResult('Invalid regular expression: ${error.message}');
    }
    final env = ctx.env;
    if (env is! DirectoryListing) {
      return errorResult(unsupportedText);
    }
    final FileStat start;
    switch (await env.stat(path)) {
      case Ok(:final value):
        start = value;
      case Err(:final error):
        return errorResult(fileErrorText(error, ctx, path));
    }
    final glob = switch (args['glob']) {
      final String g when g.isNotEmpty => Glob(g),
      _ => null,
    };
    final walk = _Walk(ctx, env as DirectoryListing, regex, limit);
    if (start.type == FileType.directory) {
      await walk.directory(start.path, glob);
    } else {
      await walk.file(
        start,
        glob == null || glob.matches(baseName(start.path)),
      );
    }
    return ToolExecutionResult([TextContent(walk.render())]);
  }
}

/// Состояние одного обхода: найденные строки и лимиты.
final class _Walk {
  _Walk(this.ctx, this.listing, this.regex, this.limit);

  final ToolContext ctx;
  final DirectoryListing listing;
  final RegExp regex;
  final int limit;
  final _matches = <String>[];
  var _scanned = 0;
  var _moreMatches = false;
  var _stoppedByFiles = false;

  bool get _done => _moreMatches || _stoppedByFiles;

  /// Обход в ширину: файлы каталога по порядку имён, затем его подкаталоги
  /// в очередь.
  Future<void> directory(String root, Glob? glob) async {
    final queue = Queue<String>()..add(root);
    while (queue.isNotEmpty && !_done) {
      final dir = queue.removeFirst();
      final entries = switch (await listing.listDir(dir)) {
        Ok(:final value) => [
          ...value,
        ]..sort((a, b) => baseName(a.path).compareTo(baseName(b.path))),
        Err() => const <FileStat>[],
      };
      for (final entry in entries) {
        if (_done) {
          return;
        }
        final name = baseName(entry.path);
        switch (entry.type) {
          case FileType.directory:
            if (!_skippedDirs.contains(name) && !name.startsWith('.')) {
              queue.add(entry.path);
            }
          case FileType.file || FileType.link:
            // Ссылка на каталог не обходится: её чтение как файла даст
            // ошибку, и она пропустится.
            final relative = relativeTo(root, entry.path);
            await file(entry, glob == null || glob.matches(relative));
          case FileType.other:
            break;
        }
      }
    }
  }

  Future<void> file(FileStat stat, bool selected) async {
    if (!selected) {
      return;
    }
    if (_scanned == _maxFiles) {
      _stoppedByFiles = true;
      return;
    }
    _scanned++;
    if ((stat.size ?? 0) > _maxFileBytes) {
      return;
    }
    final text = switch (await ctx.env.readText(stat.path)) {
      Ok(:final value) => value,
      Err() => null,
    };
    if (text == null || _isBinary(text)) {
      return;
    }
    final shown = displayPath(ctx, stat.path);
    for (final (i, line) in splitLines(text).indexed) {
      if (!regex.hasMatch(line)) {
        continue;
      }
      if (_matches.length == limit) {
        _moreMatches = true;
        return;
      }
      final cut = line.length > _maxLineLength
          ? line.substring(0, _maxLineLength)
          : line;
      _matches.add('$shown:${i + 1}: $cut');
    }
  }

  String render() {
    final out = <String>[];
    if (_matches.isEmpty) {
      out.add('No matches found.');
    } else {
      final cut = truncateHead(_matches.join('\n'));
      out.add(cut.text);
      if (_moreMatches || cut.truncated) {
        out.add(TruncationNotices.search(limit: cut.keptLines));
      }
    }
    if (_stoppedByFiles) {
      out.add('[Search stopped after scanning $_maxFiles files.]');
    }
    return out.join('\n');
  }

  static bool _isBinary(String text) =>
      (text.length > _binaryProbe ? text.substring(0, _binaryProbe) : text)
          .contains('\u0000');
}
