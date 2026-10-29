import 'dart:io';

/// Ending a process tree (`agent-core-architecture` §4.6, step 6): Dart
/// cannot start a process in a new process group, so descendants are found
/// through a snapshot of the process table and signalled in one pass —
/// otherwise a killed parent hands its children to init and they drop out
/// of the next snapshot.
Future<void> terminateTree(
  Process process, {
  Duration grace = const Duration(seconds: 2),
}) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', ['/T', '/F', '/PID', '${process.pid}']);
    return;
  }
  final family = await _descendants(process.pid);
  for (final pid in family) {
    Process.killPid(pid, ProcessSignal.sigterm);
  }
  final exited = await process.exitCode
      .then((_) => true)
      .timeout(grace, onTimeout: () => false);
  final survivors = {...family, ...await _descendantsOfAny(family)};
  if (exited) {
    survivors.remove(process.pid);
  }
  for (final pid in survivors) {
    Process.killPid(pid, ProcessSignal.sigkill);
  }
}

/// [root] and every descendant, breadth-first.
Future<List<int>> _descendants(int root) async {
  final children = await _table();
  final out = <int>[root];
  for (var i = 0; i < out.length; i++) {
    out.addAll(children[out[i]] ?? const []);
  }
  return out;
}

Future<Set<int>> _descendantsOfAny(List<int> roots) async {
  final children = await _table();
  final out = <int>{};
  final queue = [...roots];
  while (queue.isNotEmpty) {
    final pid = queue.removeLast();
    for (final child in children[pid] ?? const <int>[]) {
      if (out.add(child)) {
        queue.add(child);
      }
    }
  }
  return out;
}

/// Parent → children from `ps -A -o pid=,ppid=`.
Future<Map<int, List<int>>> _table() async {
  final result = await Process.run('ps', ['-A', '-o', 'pid=,ppid=']);
  final children = <int, List<int>>{};
  for (final line in '${result.stdout}'.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length != 2) {
      continue;
    }
    final pid = int.tryParse(parts[0]);
    final ppid = int.tryParse(parts[1]);
    if (pid != null && ppid != null) {
      (children[ppid] ??= []).add(pid);
    }
  }
  return children;
}

/// Потомки [root] (без него самого) на сейчас; пусто на Windows, где дерево
/// снимает `taskkill /T`.
///
/// Зачем отдельно от [terminateTree]: снимок берётся ДО того, как корень
/// выйдет, — после выхода корня потомки отдаются init и в таблице процессов
/// уже не связаны с ним (stdio-транспорт MCP, D9).
Future<List<int>> descendantsOf(int root) async {
  if (Platform.isWindows) {
    return const [];
  }
  return (await _descendants(root)).skip(1).toList();
}

/// Завершает [pids], если они ещё живы: `SIGTERM`, ожидание до [grace] и
/// `SIGKILL` оставшимся. Для потомков, переживших корень: они уже не наши
/// дети, поэтому выход определяется по таблице процессов.
Future<void> terminatePids(
  List<int> pids, {
  Duration grace = const Duration(seconds: 5),
}) async {
  var alive = await _alive(pids);
  if (alive.isEmpty) {
    return;
  }
  for (final pid in alive) {
    Process.killPid(pid, ProcessSignal.sigterm);
  }
  final deadline = DateTime.now().add(grace);
  while (DateTime.now().isBefore(deadline)) {
    alive = await _alive(alive);
    if (alive.isEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  for (final pid in await _alive(alive)) {
    Process.killPid(pid, ProcessSignal.sigkill);
  }
}

/// Из [pids] — те, что есть в таблице процессов.
Future<List<int>> _alive(List<int> pids) async {
  if (pids.isEmpty) {
    return const [];
  }
  final result = await Process.run('ps', ['-A', '-o', 'pid=']);
  final present = {
    for (final line in '${result.stdout}'.split('\n'))
      ?int.tryParse(line.trim()),
  };
  return [
    for (final pid in pids)
      if (present.contains(pid)) pid,
  ];
}
