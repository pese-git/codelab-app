import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Процесс scripted-агента и разбор его вывода для тестов режимов
/// `CodelabCompatibleStdioAgentMode` на настоящем Dart VM.
///
/// Почему: режимы агента проверяются через настоящий stdin/stdout, а не
/// in-process, — так же их запускают e2e app; общий помощник не даёт тестам
/// режимов расходиться в разборе кадров.
///
/// Как использовать: `final agent = await AgentProcess.start(script);`,
/// `addTearDown(agent.stop)`, затем [request]. Уведомления и запросы агента
/// копятся в [received].
final class AgentProcess {
  AgentProcess._(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onFrame);
  }

  static Future<AgentProcess> start(File script) async => AgentProcess._(
    await Process.start(dartExecutable(), [script.path, 'serve', '--stdio']),
  );

  final Process _process;
  final _responses = <Object?, Completer<Map<String, Object?>>>{};

  /// Все кадры агента, кроме ответов на [request], в порядке прихода:
  /// уведомления и запросы. Копятся с запуска процесса, поэтому кадр,
  /// пришедший между двумя запросами, не теряется.
  final received = <Map<String, Object?>>[];
  var _nextId = 1;

  void _onFrame(String line) {
    final frame = jsonDecode(line) as Map<String, Object?>;
    final pending = frame['method'] == null
        ? _responses.remove(frame['id'])
        : null;
    if (pending != null) {
      pending.complete(frame);
    } else {
      received.add(frame);
    }
  }

  /// Отправляет запрос и возвращает ответ.
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    final id = _nextId++;
    final response = Completer<Map<String, Object?>>();
    _responses[id] = response;
    _process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return response.future.timeout(const Duration(seconds: 20));
  }

  /// `session/new` в [cwd]; возвращает id сессии.
  Future<String> newSession(String cwd) async =>
      ((await request('session/new', {
                'cwd': cwd,
                'mcpServers': <Object?>[],
              }))['result']!
              as Map)['sessionId']
          as String;

  /// Уведомление JSON-RPC (без `id`), например `session/cancel`.
  void notify(String method, Map<String, Object?> params) =>
      _process.stdin.writeln(
        jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}),
      );

  /// Ответ клиента на запрос агента с [id].
  void reply(Object? id, Map<String, Object?> result) => _process.stdin.writeln(
    jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
  );

  /// `session/prompt` с одним текстовым блоком; возвращает ответ.
  Future<Map<String, Object?>> prompt(String sessionId, String text) =>
      request('session/prompt', {
        'sessionId': sessionId,
        'prompt': [
          {'type': 'text', 'text': text},
        ],
      });

  /// Обновления `session/update` из [received]: поле `update` каждого.
  List<Map<String, Object?>> get updates => [
    for (final frame in received)
      if (frame['method'] == 'session/update')
        ((frame['params']! as Map)['update']! as Map).cast<String, Object?>(),
  ];

  Future<void> stop() async {
    await _process.stdin.close();
    await _process.exitCode.timeout(const Duration(seconds: 10));
  }
}

/// Путь к `dart`: под `flutter test` (`melos run test`)
/// `Platform.resolvedExecutable` — это `flutter_tester`, а агенту нужен Dart
/// VM; поэтому сначала берётся SDK из `FLUTTER_ROOT` — как в
/// `codelab_client_io/test/transport/io_transport_resolver_test.dart`.
String dartExecutable() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final dart = File('$flutterRoot/bin/cache/dart-sdk/bin/dart');
    if (dart.existsSync()) {
      return dart.path;
    }
  }
  return Platform.resolvedExecutable;
}
