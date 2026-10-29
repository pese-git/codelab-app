// Дочерний процесс для `test/mcp/stdio_process_transport_test.dart`: строка
// на stdin — строка на stdout. Не копия чужого кода: набор команд придуман
// под сценарии stdio-транспорта (design.md change `add-agent-mcp-client`, D9).
//
// Команды (всё остальное эхом возвращается как есть):
//   env:NAME     -> `NAME=<значение>` или `NAME=<unset>`
//   pwd          -> рабочая папка процесса
//   big:N        -> одна строка из N байт `x`
//   stderr:N     -> N байт в stderr строками по 100 символов, затем `stderr-done`
//   exit:N       -> завершение с кодом N
// На EOF stdin процесс выходит с кодом 0.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.startsWith('env:')) {
      final name = line.substring(4);
      stdout.writeln('$name=${Platform.environment[name] ?? '<unset>'}');
    } else if (line == 'pwd') {
      stdout.writeln(Directory.current.path);
    } else if (line.startsWith('big:')) {
      final size = int.parse(line.substring(4));
      stdout.write('x' * size);
      stdout.write('\n');
    } else if (line.startsWith('stderr:')) {
      var left = int.parse(line.substring(7));
      while (left > 0) {
        final chunk = left < 100 ? left : 100;
        stderr.write('${'e' * (chunk - 1)}\n');
        left -= chunk;
      }
      stdout.writeln('stderr-done');
    } else if (line.startsWith('exit:')) {
      await stdout.flush();
      exit(int.parse(line.substring(5)));
    } else {
      stdout.writeln(line);
    }
    await stdout.flush();
  }
}
