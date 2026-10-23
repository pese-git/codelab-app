import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package_dir.dart';

/// How a fixture body is cut into chunks of the HTTP response.
enum Chunking { whole, byChar, random }

String readSseFixture(String path) =>
    File(corePath('test/fixtures/sse/$path')).readAsStringSync();

List<List<int>> chunkBody(String body, Chunking chunking) {
  final bytes = utf8.encode(body);
  switch (chunking) {
    case Chunking.whole:
      return [bytes];
    case Chunking.byChar:
      return [
        for (final rune in body.runes) utf8.encode(String.fromCharCode(rune)),
      ];
    case Chunking.random:
      final random = Random(7);
      final chunks = <List<int>>[];
      var i = 0;
      while (i < bytes.length) {
        final end = min(bytes.length, i + 1 + random.nextInt(11));
        chunks.add(bytes.sublist(i, end));
        i = end;
      }
      return chunks;
  }
}

/// A captured request with its decoded JSON body.
final class CapturedRequest {
  CapturedRequest(this.request, this.body);

  final http.BaseRequest request;
  final String body;

  Map<String, Object?> get json => jsonDecode(body) as Map<String, Object?>;
}

/// Runs a [StreamFunction] made by [make] against a [MockClient] that
/// answers every request with [body].
final class ProviderHarness {
  ProviderHarness({
    this.body = '',
    this.status = 200,
    this.headers = const {'content-type': 'text/event-stream'},
    this.chunking = Chunking.whole,
  });

  final String body;
  final int status;
  final Map<String, String> headers;
  final Chunking chunking;
  final requests = <CapturedRequest>[];
  final logger = RecordingLogger();
  final clock = FakeClock(start: DateTime.utc(2026, 10, 23, 8));

  late final http.Client client = MockClient.streaming((request, stream) async {
    requests.add(CapturedRequest(request, await utf8.decodeStream(stream)));
    return http.StreamedResponse(
      Stream.fromIterable(chunkBody(body, chunking)),
      status,
      headers: headers,
    );
  });

  CoreLlmServices get services => CoreLlmServices(
    httpClient: client,
    clock: clock,
    random: Random(42),
    logger: logger,
  );

  Future<List<AssistantMessageEvent>> run(
    StreamFunction stream,
    ModelRef model,
    LlmContext context, {
    CancelToken? cancel,
  }) => stream(model, context, cancel: cancel).toList();
}
