// Загрузка изображения через `ImageStream` (ревью итерации 4, MEDIUM).
//
// Отдельный файл: `testWidgets` ставит тестовый биндинг, а он подменяет все
// `HttpClient` заглушкой со статусом 400; здесь нужна настоящая сеть, поэтому
// `HttpOverrides` снимаются на время теста.

import 'dart:async';
import 'dart:io';

import 'package:codelab_desktop/core/platform/limited_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/png_fixture.dart';

void main() {
  testWidgets('the provider refuses an oversized image before decoding', (
    tester,
  ) async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
    // Сервер и загрузка — в реальной зоне `runAsync`: обработчик, созданный в
    // зоне fake-async, не получал бы микрозадач.
    final result = await tester.runAsync(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.add(png(1400, 100000));
        await request.response.close();
      });
      try {
        // Через `ImageStream`, а не прямой вызов проверки: если `_load` не
        // проверит размеры, декодер получит «бомбу» и ответит другой ошибкой
        // (не `dimensions`).
        final completer = Completer<Object>();
        LimitedNetworkImage(Uri.parse('http://127.0.0.1:${server.port}/bomb'))
            .resolve(ImageConfiguration.empty)
            .addListener(
              ImageStreamListener(
                (image, sync) => completer.complete('decoded'),
                onError: (error, stack) => completer.complete(error),
              ),
            );
        return await completer.future.timeout(const Duration(seconds: 10));
      } finally {
        await server.close(force: true);
      }
    });

    expect(
      result,
      isA<ImageRejectedException>().having(
        (e) => e.reason,
        'reason',
        'dimensions',
      ),
    );
  });
}
