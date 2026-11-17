// Процесс-зонд тестового хранилища секретов (задача 2.3 change
// `add-embedded-agent-mode`, D5): открывает встроенного агента с окружением из
// аргументов, проводит один ход против `MockClient` и печатает одну строку
// JSON. Запускается тестом `test_secret_store_process_test.dart` командой
// `dart run [-DCODELAB_ALLOW_TEST_SECRETS=true] test/io/support/secret_store_probe.dart
// <CODELAB_HOME> <каталог хранилища> <папка проекта>`.
//
// Окружение процесса зонд не читает: открывателю отдаётся только то, что
// передал тест, поэтому настоящие `~/.codelab` и переменные разработчика
// недоступны. Значение ключа в вывод не попадает — только заголовок
// `Authorization` у запроса к `MockClient`, как в остальных тестах.
import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_embedded/io.dart';
import 'package:http/http.dart' as web;
import 'package:http/testing.dart';

import '../../support/acp_client.dart';

Future<void> main(List<String> args) async {
  final [home, store, project] = args;
  final logger = RecordingLogger();
  final authorizations = <String?>[];
  final mock = MockClient.streaming((request, body) async {
    authorizations.add(request.headers['authorization']);
    return web.StreamedResponse(
      Stream.value(utf8.encode('{"error":{"message":"denied"}}')),
      401,
      headers: {'content-type': 'application/json'},
    );
  });
  final agent = await localEmbeddedAgentOpener(
    environment: {'CODELAB_HOME': home, 'CODELAB_TEST_SECRET_STORE': store},
    logger: logger,
    httpClient: mock,
  )(cwd: project, hostProfile: 'embedded-cli');
  final client = TestAcpClient(agent.clientTransport);
  await client.start();
  await client.initialize();
  final session = await client.newSession(project);
  String outcome;
  try {
    outcome = await client.prompt(session, 'hi');
  } on StateError catch (error) {
    outcome = '$error';
  }
  await client.close();
  await agent.dispose();
  stdout.writeln(
    jsonEncode({
      'authorizations': authorizations,
      'backends': [
        for (final r in logger.eventsOf('secrets.backend.selected'))
          r.fields['backend'],
      ],
      'unknownVariables': [
        for (final r in logger.eventsOf('config.env.unknown')) r.fields['name'],
      ],
      'outcome': outcome,
    }),
  );
}
