// Процесс-сервер MCP для тестов жизненного цикла встроенного агента (embedded-
// agent «Клиент закрыл соединение»): строки stdin идут в `FakeMcpServer`, его
// ответы — в stdout. Запуск: `dart fake_mcp_stdio_server.dart <файл-pid> [<файл-HOME>]`.
//
// Файл получает pid процесса при старте: по нему тест проверяет, что сервер
// остановлен вместе с агентом (E-02, R-24). Единственный инструмент `echo`
// отвечает текстом `hi`. Необязательный второй файл получает `HOME` процесса:
// по нему тест проверяет, из какого окружения запущен сервер. EOF stdin — сигнал закрытия: процесс выходит сам.
import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_mcp/testing.dart';

Future<void> main(List<String> args) async {
  File(args.first).writeAsStringSync('$pid');
  if (args.length > 1) {
    File(args[1]).writeAsStringSync(Platform.environment['HOME'] ?? '');
  }
  final server = FakeMcpServer(
    tools: [
      FakeMcpTool(
        'echo',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
          },
        },
      ),
    ],
    responses: {'echo': FakeToolResponse.text('hi')},
  );
  final transport = server.connect();
  transport.incoming.listen(stdout.writeln);
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    await transport.send(line);
  }
  await transport.close();
}
