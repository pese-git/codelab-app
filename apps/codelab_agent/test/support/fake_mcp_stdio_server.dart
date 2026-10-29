// Реальный процесс MCP-сервера для e2e бинаря (design.md change
// `add-agent-mcp-client`, D15): строки stdin идут в `FakeMcpServer`, его
// ответы — в stdout.
//
// Запуск: `dart fake_mcp_stdio_server.dart <сценарий.json> <файл-pid>`.
// Сценарий — `{"tools": [{"name", "inputSchema"}], "results": {"<tool>":
// "<текст>"}}`, эпоха — modern. Файл-pid получает pid процесса при старте:
// по нему тест проверяет, что сервер умер вместе с агентом (E-02, R-24).
import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_mcp/testing.dart';

Future<void> main(List<String> args) async {
  final scenario =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, Object?>;
  File(args[1]).writeAsStringSync('$pid');
  final server = FakeMcpServer(
    tools: [
      for (final tool
          in (scenario['tools']! as List<Object?>).cast<Map<String, Object?>>())
        FakeMcpTool(tool['name']! as String, inputSchema: tool['inputSchema']),
    ],
    responses: {
      for (final entry
          in (scenario['results']! as Map<String, Object?>).entries)
        entry.key: FakeToolResponse.text(entry.value! as String),
    },
  );
  final transport = server.connect();
  transport.incoming.listen(stdout.writeln);
  // EOF stdin — сигнал закрытия: процесс выходит сам, а если не выйдет,
  // транспорт агента добьёт его SIGTERM/SIGKILL.
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    await transport.send(line);
  }
  await transport.close();
}
