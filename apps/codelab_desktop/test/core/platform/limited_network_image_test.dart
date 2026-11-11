// Загрузка изображения ответа агента с ограничениями (ревью итерации 4,
// MEDIUM: декомпрессионная бомба и редиректы; design.md D6, R4).
//
// Красный: `limited_network_image.dart` ещё нет. Настоящий локальный
// `HttpServer` вместо подмены клиента: проверяется то, что реально идёт по
// сокету — `Content-Length`, чтение потока и редиректы.

import 'dart:io';
import 'dart:typed_data';

import 'package:codelab_desktop/core/platform/limited_network_image.dart';

import '../../support/png_fixture.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Отказ с конкретной причиной: проверяется и ветка, а не только тип.
Matcher rejected(String reason) => throwsA(
  isA<ImageRejectedException>().having((e) => e.reason, 'reason', reason),
);

void main() {
  late HttpServer server;
  late HttpServer second;
  late Uri base;
  var secondRequests = 0;
  var requests = <String>[];

  setUp(() async {
    requests = [];
    secondRequests = 0;
    // Второй сервер — настоящая цель редиректа с валидной картинкой: если
    // загрузчик пойдёт за редиректом на `http`, счётчик покажет запрос.
    second = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    second.listen((request) async {
      secondRequests++;
      request.response.add(List.filled(100, 9));
      await request.response.close();
    });
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      requests.add(request.uri.path);
      final response = request.response;
      switch (request.uri.path) {
        case '/never':
          // Не отвечает: соединение висит до таймаута клиента.
          return;
        case '/small':
          response.add(List.filled(100, 7));
        case '/big-declared':
          response.headers.contentLength = 5000;
          response.add(List.filled(5000, 1));
        case '/big-chunked':
          response.headers.chunkedTransferEncoding = true;
          for (var i = 0; i < 10; i++) {
            response.add(List.filled(1000, 1));
            await response.flush();
          }
        case '/hang-declared':
          // Объявляет 5000 байт, отдаёт 10 и держит соединение: тело
          // «дочитать» нельзя, поэтому отказ возможен только по заголовку.
          response.headers.contentLength = 5000;
          response.add(List.filled(10, 1));
          await response.flush();
          return;
        case '/to-second-http':
          response.statusCode = HttpStatus.found;
          response.headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${second.port}/img',
          );
        case '/to-http':
          response.statusCode = HttpStatus.found;
          response.headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:1/x',
          );
        case '/to-file':
          response.statusCode = HttpStatus.found;
          response.headers.set(
            HttpHeaders.locationHeader,
            'file:///etc/passwd',
          );
        case '/missing':
          response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await second.close(force: true);
  });

  test('reads a small body', () async {
    final bytes = await fetchLimitedImageBytes(
      base.replace(path: '/small'),
      maxBytes: 1000,
    );
    expect(bytes, Uint8List.fromList(List.filled(100, 7)));
  });

  test(
    'rejects a body that declares more than the limit before reading',
    () async {
      await expectLater(
        fetchLimitedImageBytes(
          base.replace(path: '/big-declared'),
          maxBytes: 1000,
        ),
        rejected('too large'),
      );
    },
  );

  test('rejects a chunked body as soon as it grows past the limit', () async {
    await expectLater(
      fetchLimitedImageBytes(
        base.replace(path: '/big-chunked'),
        maxBytes: 3500,
      ),
      rejected('too large'),
    );
  });

  test(
    'rejects by the Content-Length header without waiting for the body',
    () async {
      // Тело так и не придёт целиком: без проверки заголовка загрузчик ждал бы
      // его вечно и тест упал бы по таймауту, а не по отказу.
      await expectLater(
        fetchLimitedImageBytes(
          base.replace(path: '/hang-declared'),
          maxBytes: 1000,
        ).timeout(const Duration(seconds: 3)),
        rejected('too large'),
      );
    },
  );

  test(
    'a redirect to a real http server is refused before any request',
    () async {
      await expectLater(
        fetchLimitedImageBytes(
          base.replace(path: '/to-second-http'),
          maxBytes: 1000,
        ),
        rejected('redirect is not allowed'),
      );
      // До второго сервера запрос не дошёл, хотя он отдал бы валидную картинку.
      expect(secondRequests, 0);
    },
  );

  test('does not follow a redirect to http or file', () async {
    for (final path in ['/to-http', '/to-file']) {
      await expectLater(
        fetchLimitedImageBytes(base.replace(path: path), maxBytes: 1000),
        rejected('redirect is not allowed'),
        reason: path,
      );
    }
    // Редирект не был выполнен: на порт 1 никто не ходил.
    expect(requests, ['/to-http', '/to-file']);
  });

  test('an error status is a rejection too', () async {
    await expectLater(
      fetchLimitedImageBytes(base.replace(path: '/missing'), maxBytes: 1000),
      rejected('bad status'),
    );
  });

  test('every rejection has a short log code from the allowed set', () {
    const allowed = {
      'timeout',
      'too_large',
      'dimensions',
      'redirect',
      'network',
      'decode',
    };
    for (final rejection in ImageRejection.values) {
      expect(allowed, contains(rejection.code), reason: '$rejection');
      expect(ImageRejectedException(rejection).code, rejection.code);
      expect(ImageRejectedException(rejection).reason, rejection.reason);
    }
    // Тексты причин остались прежними.
    expect(ImageRejection.tooLarge.reason, 'too large');
    expect(ImageRejection.redirectNotAllowed.code, 'redirect');
    expect(ImageRejection.notAnImage.code, 'decode');
  });

  test('the rejection does not carry the address', () async {
    try {
      await fetchLimitedImageBytes(
        base.replace(path: '/big-declared', query: 'd=secret'),
        maxBytes: 1000,
      );
      fail('must throw');
    } on ImageRejectedException catch (error) {
      expect('$error', isNot(contains('127.0.0.1')));
      expect('$error', isNot(contains('secret')));
    }
  });

  test('the provider for the app limits the decoded size to 1440 px', () {
    final provider = imageProviderFor(Uri.parse('https://x.example/y.png'));

    expect(provider, isA<ResizeImage>());
    final resize = provider as ResizeImage;
    expect(resize.width, 1440);
    expect(resize.height, 1440);
    expect(resize.policy, ResizeImagePolicy.fit);
    expect(resize.imageProvider, isA<LimitedNetworkImage>());
  });

  test('a server that never answers is dropped by the total timeout', () async {
    await expectLater(
      fetchLimitedImageBytes(
        base.replace(path: '/never'),
        maxBytes: 1000,
        connectionTimeout: const Duration(milliseconds: 200),
        totalTimeout: const Duration(milliseconds: 300),
      ),
      rejected('timeout'),
    );
  });

  group('decoded size is checked before decoding', () {
    test('an ordinary size passes', () async {
      await checkImageDimensions(png(64, 64));
    });

    test('too many pixels are rejected without decoding', () async {
      await expectLater(
        checkImageDimensions(png(1400, 100000)),
        rejected('dimensions'),
      );
      await expectLater(
        checkImageDimensions(png(7000, 7000)),
        rejected('dimensions'),
        reason: '49 million pixels',
      );
    });

    test('a side over 16384 is rejected', () async {
      await expectLater(
        checkImageDimensions(png(16385, 1)),
        rejected('dimensions'),
      );
    });

    test(
      'bytes that are not an image are rejected without the address',
      () async {
        try {
          await checkImageDimensions(Uint8List.fromList([1, 2, 3, 4]));
          fail('must throw');
        } on ImageRejectedException catch (error) {
          expect('$error', isNot(contains('http')));
        }
      },
    );
  });
}
