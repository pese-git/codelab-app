// Тест проверяет внутренний тип клиента MCP, которого нет в барeле пакета.
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';
import 'package:codelab_agent_mcp/src/mcp_client.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/io.dart';
import 'package:codelab_embedded/testing.dart';
import 'package:http/http.dart' as web;
import 'package:test/test.dart';

import 'support/acp_client.dart';
import 'support/package_dir.dart';

/// Фейковый MCP-сервер на loopback HTTP (change `add-provider-setup-ui`,
/// задача 5.3a, решение Q28; design.md D20, D22; §12.4.13, шаги 1–4).
///
/// Почему отдельный тест: интеграционный тест app (5.11) подставляет URL
/// хоста в `mcp.servers` временного `CODELAB_HOME`, поэтому сам хост должен
/// быть надёжен: слушать только loopback, не светить заголовок `Authorization`
/// в журнал и отпускать порт. Сети наружу нет; секрет — синтетический маркер.
/// Модель не вызывается: статус MCP читается без промпта (SETUP-11).
///
/// Выбранное API (узкое, в `codelab_embedded/testing.dart`):
/// `FakeMcpHttpHost.start({Logger? logger, List<FakeMcpTool>? tools})` →
/// `url`, `address`, `authorizations` (значения `Authorization` запросов, в
/// порядке прихода), `server` (`FakeMcpServer` за хостом), `close()`.
void main() {
  // Маркер секретного заголовка шага 1 §12.4.13; в журнале его быть не должно.
  const marker = 'sk-test-leak-0123456789';

  late RecordingLogger logger;
  FakeMcpHttpHost? host;
  EmbeddedAgent? agent;
  TestAcpClient? client;
  Directory? temp;

  setUp(() => logger = RecordingLogger());

  tearDown(() async {
    await client?.close();
    await agent?.dispose();
    await host?.close();
    host = null;
    agent = client = null;
    if (temp != null && temp!.existsSync()) {
      temp!.deleteSync(recursive: true);
    }
    temp = null;
  });

  /// Подключает клиент `codelab_agent_mcp` по настоящему HTTP к [url].
  Future<McpClient> connectClient(
    Uri url, {
    List<(String, String)> headers = const [],
  }) async {
    final server = McpHttpServerConfig(
      name: 'github',
      url: url,
      headers: headers,
    );
    final httpClient = web.Client();
    final transport = await StreamableHttpTransportFactory(
      client: httpClient,
      clock: const SystemClock(),
    ).open(server, cwd: '/', cancel: CancelToken.none, logger: logger);
    return McpClient.connect(
      server: server,
      transport: transport,
      clock: const SystemClock(),
      logger: logger,
      sessionId: const SessionId('s1'),
    );
  }

  group('хост', () {
    test('слушает только loopback и отдаёт URL с реальным портом', () async {
      host = await FakeMcpHttpHost.start();

      expect(host!.address.isLoopback, isTrue);
      expect(host!.address.address, '127.0.0.1');
      expect(host!.url.scheme, 'http');
      expect(host!.url.host, '127.0.0.1');
      expect(host!.url.port, greaterThan(0), reason: 'порт 0 разрешён в порт');
    });

    test('клиент codelab_agent_mcp проходит initialize и tools/list: один '
        'инструмент по умолчанию', () async {
      host = await FakeMcpHttpHost.start();

      final mcp = await connectClient(host!.url);
      addTearDown(mcp.close);

      expect(mcp.tools, hasLength(1));
      expect(host!.server.methods, contains('tools/list'));
      expect(host!.server.methods, contains('initialize'));
    });

    test('Authorization виден тесту, но не попадает в журнал хоста', () async {
      host = await FakeMcpHttpHost.start(logger: logger);

      final mcp = await connectClient(
        host!.url,
        headers: [('Authorization', 'Bearer $marker')],
      );
      addTearDown(mcp.close);

      expect(host!.authorizations, isNotEmpty);
      expect(host!.authorizations, everyElement('Bearer $marker'));
      expect(
        logger.records,
        isNotEmpty,
        reason: 'хост пишет журнал: иначе проверка ниже ничего не доказывает',
      );
      for (final record in logger.records) {
        expect(
          '${record.event} ${record.fields} ${record.error}',
          isNot(contains(marker)),
        );
      }
    });

    test('close() освобождает порт', () async {
      host = await FakeMcpHttpHost.start();
      final port = host!.url.port;

      await host!.close();
      host = null;

      final rebound = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await rebound.close();
    });
  });

  test('встроенный агент с сервером в mcp.servers: mcpStatus даёт connected '
      'с одним инструментом', () async {
    temp = Directory.systemTemp.createTempSync('codelab_fake_mcp_host_');
    final home = '${temp!.path}/home';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    final project = Directory('${temp!.path}/project')..createSync();
    host = await FakeMcpHttpHost.start(logger: logger);
    File('$home/config.yaml').writeAsStringSync(
      'providers:\n'
      '  p:\n'
      '    kind: openai-compatible\n'
      '    base_url: https://p.test/v1\n'
      '    models:\n'
      '      m: {}\n'
      'agent:\n'
      '  default_model: p/m\n'
      'mcp:\n'
      '  servers:\n'
      '    - name: github\n'
      '      url: ${host!.url}\n'
      '      headers:\n'
      '        Authorization: "Bearer $marker"\n',
    );

    // Настоящий открыватель на временном CODELAB_HOME; HTTP-клиент по
    // умолчанию — настоящий сокет до loopback, модель не вызывается.
    agent = await localEmbeddedAgentOpener(
      environment: {'CODELAB_HOME': home},
      logger: logger,
    )(cwd: project.path, hostProfile: 'embedded-cli');
    client = TestAcpClient(agent!.clientTransport);
    await client!.start();
    await client!.initialize();
    final created = await client!.call('session/new', {
      'cwd': project.path,
      'mcpServers': const <Object?>[],
    });

    final port = agent!.mcpStatus(created['sessionId']! as String)!;
    bool ready(List<McpServerSummary> l) =>
        l.any((s) => s.state == McpServerState.connected);
    if (!ready(port.servers)) {
      await port.changes.firstWhere(ready).timeout(const Duration(seconds: 10));
    }

    final github = port.servers.singleWhere((s) => s.name == 'github');
    expect(github.state, McpServerState.connected);
    expect(github.toolCount, 1);
    expect(host!.authorizations, contains('Bearer $marker'));
  });

  test('основной барель и io.dart хост не экспортируют (сторож, '
      'web-compile)', () {
    final root = embeddedRoot;
    for (final path in ['lib/codelab_embedded.dart', 'lib/io.dart']) {
      final source = File('$root/$path').readAsStringSync();
      expect(source, isNot(contains('FakeMcpHttpHost')), reason: path);
      expect(source, isNot(contains('fake_mcp_http_host')), reason: path);
    }
    expect(
      File('$root/lib/testing.dart').readAsStringSync(),
      contains('fake_mcp_http_host'),
      reason: 'хост экспортирует только testing.dart',
    );
  });
}
