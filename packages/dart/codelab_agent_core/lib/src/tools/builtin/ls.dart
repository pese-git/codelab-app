import '../../env/execution_env.dart';
import '../../llm/messages.dart';
import '../../util/result.dart';
import '../../prompts/prompts.g.dart';
import '../agent_tool.dart';
import '../truncate.dart';
import 'common.dart';

const _defaultLimit = 500;

/// `ls` — содержимое одного каталога (`agent-core-architecture` §6.4,
/// T-06).
///
/// Почему: модели нужно увидеть структуру проекта до чтения файлов, а
/// `exec ls` есть не во всех env (браузер, ACP-клиент без терминала) и
/// требует разрешения уровня `exec`.
///
/// Для чего: один уровень без рекурсии; скрытые файлы показываются;
/// сортировка без учёта регистра; каталоги с суффиксом `/`, ссылки — с `@`.
///
/// Как использовать: регистрируется при capability `fileListing` (§10.7,
/// шаг 5b) — env должен реализовать `DirectoryListing`. `path` по
/// умолчанию — корень рабочей папки, `limit` — 500 записей.
final class LsTool extends AgentTool {
  @override
  String get name => 'ls';

  @override
  String get description => Prompts.toolDescriptionsLs.render(const {});

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': 'Directory to list. Default: workspace root.',
      },
      'limit': {
        'type': 'integer',
        'description': 'Maximum entries. Default 500.',
      },
    },
  };

  @override
  ToolTier get tier => ToolTier.read;

  @override
  ToolKind get kind => ToolKind.search;

  @override
  ContentTrust outputTrust(Map<String, Object?> args) => ContentTrust.trusted;

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
      title: 'List ${displayPath(ctx, path)}',
      locations: [if (abs != null) Location(abs)],
    );
  }

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final path = args['path'] as String? ?? '.';
    final limit = args['limit'] as int? ?? _defaultLimit;
    if (limit < 1) {
      return errorResult('limit must be >= 1');
    }
    final env = ctx.env;
    if (env is! DirectoryListing) {
      return errorResult(unsupportedText);
    }
    final List<FileStat> entries;
    switch (await (env as DirectoryListing).listDir(path)) {
      case Ok(:final value):
        entries = value;
      case Err(:final error):
        return errorResult(fileErrorText(error, ctx, path));
    }
    if (entries.isEmpty) {
      return const ToolExecutionResult([TextContent('(empty directory)')]);
    }
    final names = [
      for (final entry in entries)
        '${baseName(entry.path)}${switch (entry.type) {
          FileType.directory => '/',
          FileType.link => '@',
          _ => '',
        }}',
    ]..sort(compareIgnoringCase);
    final shown = names.length > limit ? names.sublist(0, limit) : names;
    final cut = truncateHead(shown.join('\n'));
    final out = [cut.text];
    if (cut.keptLines < names.length) {
      out.add(TruncationNotices.ls(shown: cut.keptLines, total: names.length));
    }
    return ToolExecutionResult([TextContent(out.join('\n'))]);
  }
}
