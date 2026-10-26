import 'dart:io';

import 'package:acp_client_core/acp_client_core.dart';

/// Реализация клиентских портов ACP `fs/read_text_file` и
/// `fs/write_text_file` на `dart:io`.
///
/// Почему: `acp_client_core` и kit web-безопасны и не трогают файловую
/// систему; адаптер живёт в `acp_client_io`, общем для app и CLI
/// (`docs/architecture/platform-integration.md` §9–10; design D2 change
/// `extract-acp-client-kit`).
///
/// Как использовать: composition root передаёт экземпляр в
/// `AcpClientApplication(textFileReader:, textFileWriter:)`. Ограничение
/// путей рабочей папкой сессии делает ядро клиента до вызова адаптера
/// (`AGENTS.md` §10). Отсутствующий файл — `FsNotFoundFailure`, остальные
/// ошибки файловой системы — `FsIoFailure`.
final class IoTextFileIo implements TextFileReader, TextFileWriter {
  const IoTextFileIo();

  @override
  Future<String> readText({required String path, int? line, int? limit}) async {
    try {
      final file = File(path);
      // Отсутствующий файл — отдельный отказ: клиент ответит -32002, и агент
      // поймёт, что файл нужно создать (agent-core §4.7).
      if (!await file.exists()) {
        throw FsNotFoundFailure(path);
      }
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
