import 'dart:io';

import 'package:path/path.dart' as p;

/// Ручная сборка ядра в обход `buildAgentCore` (HOST-6): конструктор
/// `ToolRegistry`, `Agent` или `AgentRuntime`, не часть более длинного
/// имени (`AcpAgentServer(` — не нарушение).
final _manualAssembly = RegExp(
  r'(?<![A-Za-z0-9_])(ToolRegistry|Agent|AgentRuntime)\(',
);

/// Нарушения HOST-6 в файлах `*.dart` каталога [dir] в виде
/// `файл:строка -> конструктор(`; строки комментариев пропускаются.
List<String> scanHostAssembly(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) {
    return const [];
  }
  final violations = <String>[];
  final files =
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (final (i, line) in lines.indexed) {
      if (line.trimLeft().startsWith('//')) {
        continue;
      }
      for (final match in _manualAssembly.allMatches(line)) {
        violations.add(
          '${p.relative(file.path, from: p.dirname(dir))}:${i + 1} -> '
          '${match.group(1)}(',
        );
      }
    }
  }
  return violations;
}
