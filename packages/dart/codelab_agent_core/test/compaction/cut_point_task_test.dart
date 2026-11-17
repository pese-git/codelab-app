import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/cut_point.dart';
import 'package:codelab_agent_core/src/compaction/settings.dart';
import 'package:test/test.dart';

import 'region.dart';

/// Запись `task` при сжатии (`agent-core/17-16-task-list.md` §17.16.6
/// «Сжатие»): служебная, в контекст модели не входит и при срезе остаётся с
/// хвостом, как `plan`.
///
/// Отдельный файл, а не правка `cut_point_test.dart`: общий `RegionBuilder`
/// не ломается ради красного теста итерации 1. Красный до задачи 1.3: нет
/// `TaskRecord` и ветки `TaskRecord` в `isServiceRecord` (`cut_point.dart`).
void main() {
  const keep4096 = CompactionSettings(
    reserveTokens: 2048,
    keepRecentTokens: 4096,
    keepRecentUserTurns: 1,
  );

  test('task records right before the cut stay with the tail', () {
    final r = RegionBuilder()
      ..user(40)
      ..assistant(5000);
    r.records.add(
      TaskRecord(
        id: 'task-1',
        parentId: r.records.last.id,
        timestamp: DateTime.utc(2026),
        op: 'create',
        actor: const MainActor(),
        items: const [],
        deleted: const [],
      ),
    );
    r
      ..user(30)
      ..assistant(4500);

    final cut = findCutPoint(r.records, keep4096)!;

    expect(cut.firstKeptIndex, 2);
    expect(r.records[2], isA<TaskRecord>());
  });
}
