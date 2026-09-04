import 'dart:io';

import 'package:acp_client_core/acp_client_core.dart';

/// `dart:io`-backed implementation of the ACP `fs/read_text_file` and
/// `fs/write_text_file` client-side ports — see
/// `docs/architecture/platform-integration.md` §9-10 for why this adapter
/// lives here rather than in `acp_client_core`.
final class IoTextFileIo implements TextFileReader, TextFileWriter {
  const IoTextFileIo();

  @override
  Future<String> readText({required String path, int? line, int? limit}) async {
    try {
      final file = File(path);
      if (line == null && limit == null) {
        return await file.readAsString();
      }

      final lines = await file.readAsLines();
      final start = ((line ?? 1) - 1).clamp(0, lines.length);
      final end = limit == null
          ? lines.length
          : (start + limit).clamp(start, lines.length);
      return lines.sublist(start, end).join('\n');
    } on FileSystemException catch (error) {
      throw FsIoFailure(
        'Failed to read "$path": ${error.osError?.message ?? error.message}',
        cause: error,
      );
    }
  }

  @override
  Future<void> writeText({
    required String path,
    required String content,
  }) async {
    try {
      final file = File(path);
      await file.create(recursive: true);
      await file.writeAsString(content);
    } on FileSystemException catch (error) {
      throw FsIoFailure(
        'Failed to write "$path": ${error.osError?.message ?? error.message}',
        cause: error,
      );
    }
  }
}
