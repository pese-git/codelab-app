import 'dart:io';
import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';

/// Время создания журналов в тестах пакета.
final t0 = DateTime.utc(2026, 10, 21, 8);

/// Заголовок журнала в рабочей папке [cwd].
SessionHeader headerOf(String id, {String cwd = '/work/demo'}) => SessionHeader(
  id: SessionId(id),
  cwd: cwd,
  created: t0,
  agent: const AgentInfo(name: 'codelab-agent', version: '0.1.0'),
);

/// Запись слов пользователя с текстом [text].
MessageRecord userRecord(String id, String? parent, String text) =>
    MessageRecord(
      id: id,
      parentId: parent,
      timestamp: t0,
      message: UserMessage([TextContent(text)], timestamp: t0),
    );

/// Временный каталог журналов; удаляется после теста.
///
/// Путь разрешён через symlink (на macOS `/var` → `/private/var`), чтобы
/// сравнения путей в тестах не зависели от ОС.
String tempRoot(String prefix, void Function(void Function()) addTearDown) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir.resolveSymbolicLinksSync();
}

/// Хранилище над [root] с детерминированным временем.
JsonlSessionStore storeAt(
  String root, {
  FsyncPolicy fsync = FsyncPolicy.checkpoints,
  FileSync? sync,
  Logger? logger,
}) => JsonlSessionStore(
  root: root,
  fsync: fsync,
  clock: FakeClock(start: t0),
  logger: logger,
  sync: sync,
);

/// Единственный файл журнала под [root] с суффиксом `_<id>.jsonl`.
File journalFile(String root, String id) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .singleWhere((f) => f.path.endsWith('_$id.jsonl'));

/// Байты файла — для проверок «файл побайтово не изменён».
Uint8List bytesOf(File file) => file.readAsBytesSync();
