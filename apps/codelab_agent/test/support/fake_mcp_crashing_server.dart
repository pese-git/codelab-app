// Stdio-сервер MCP, который падает по сигналу SIGUSR1 (первый запуск)
// (design.md change `add-config-writer-and-reload`, D11, E-04).
//
// Почему отдельный файл: `fake_mcp_stdio_server.dart` живёт до конца сессии,
// а переподключение проверяется только на настоящем выходе процесса.
//
// Запуск: `dart fake_mcp_crashing_server.dart <сценарий.json> <файл-pid>`.
// Сценарий — как у `fake_mcp_stdio_server.dart`. В файл-pid КАЖДЫЙ запуск
// дописывает свой pid отдельной строкой: по нему тест видит переподключение и
// проверяет, что после закрытия агента не осталось ни одного процесса.
// Падает только первый запуск (в файле до него не было строк), и не по
// таймеру, а по сигналу SIGUSR1: тест посылает его, когда сам решил, что
// пора, — детерминированно, без пауз. Второй экземпляр, поднятый после
// переподключения, живёт до EOF stdin.
import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_mcp/testing.dart';

Future<void> main(List<String> args) async {
  final scenario =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, Object?>;
  final pidFile = File(args[1]);
  final first = !pidFile.existsSync() || pidFile.readAsStringSync().isEmpty;
  pidFile.writeAsStringSync('$pid\n', mode: FileMode.append, flush: true);

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
  // `exit(1)` без EOF — как настоящее падение сервера. Подписка на сигнал
  // держит процесс живым, поэтому её снимают после EOF stdin.
  final crash = first
      ? ProcessSignal.sigusr1.watch().listen((_) => exit(1))
      : null;
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    await transport.send(line);
  }
  await crash?.cancel();
  await transport.close();
}
