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
