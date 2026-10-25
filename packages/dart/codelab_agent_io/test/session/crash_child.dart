import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';

/// Дочерний процесс теста `core/session-crash-mid-turn-loads`
/// (`jsonl_crash_recovery_test.dart`).
///
/// Почему отдельный процесс: проверяется журнал, который оставляет
/// процесс, убитый `SIGKILL`, а не вежливое закрытие хранилища. Момент
/// сигнала посреди `write` не воспроизводится надёжно, поэтому процесс сам
/// оставляет в файле начало следующей строки — так выглядит обрыв посреди
/// записи (design.md, «Risks»), — печатает `ready` и ждёт сигнала.
///
/// Аргументы: `<root> <sessionId> <cwd>`.
Future<void> main(List<String> args) async {
  final [root, id, cwd] = args;
  final sid = SessionId(id);
  final clock = const SystemClock();
  final store = JsonlSessionStore(root: root, clock: clock);
  final at = clock.now();
  await store.create(
    SessionHeader(
      id: sid,
      cwd: cwd,
      created: at,
      agent: const AgentInfo(name: 'crash-child', version: '0'),
    ),
  );
  await store.append(
    sid,
    ModelChangeRecord(
      id: 'k3f9a1c2',
      parentId: null,
      timestamp: at,
      provider: 'test',
      modelId: 'model-1',
    ),
  );
  await store.append(
    sid,
    MessageRecord(
      id: 'p7d2e8b4',
      parentId: 'k3f9a1c2',
      timestamp: at,
      message: UserMessage(const [
        TextContent('start the task'),
      ], timestamp: at),
    ),
  );
  final cut = jsonEncode(
    MessageRecord(
      id: 'q1w2e3r4',
      parentId: 'p7d2e8b4',
      timestamp: at,
      message: UserMessage(const [
        TextContent('never finished'),
      ], timestamp: at),
    ).toJson(),
  );
  final file = Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .singleWhere((f) => f.path.endsWith('_$id.jsonl'));
  file.writeAsStringSync(
    cut.substring(0, cut.length ~/ 2),
    mode: FileMode.append,
  );
  stdout.writeln('ready');
  await stdout.flush();
  // Таймер держит процесс живым: незавершённый Future без событий не держит.
  await Future<void>.delayed(const Duration(hours: 1));
}
