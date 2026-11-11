import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

import 'link_policy.dart';

/// Наибольший размер тела изображения ответа агента.
const int kMaxImageBytes = 32 * 1024 * 1024;

/// Сторона, больше которой изображение не декодируется (ширина колонки ×2).
const int kMaxDecodedImageSide = 1440;

/// Причина отказа загрузки изображения: текст для сообщений и короткий код
/// для журнала (`image.load`, D12).
///
/// Почему enum: опечатка в строке причины молча давала бы код `network`.
/// Коды: `timeout`, `too_large`, `dimensions`, `redirect`, `network`,
/// `decode` — без адреса и без текста исключения сети.
enum ImageRejection {
  timeout('timeout', 'timeout'),
  tooLarge('too_large', 'too large'),
  dimensions('dimensions', 'dimensions'),
  redirectNotAllowed('redirect', 'redirect is not allowed'),
  tooManyRedirects('redirect', 'too many redirects'),
  badStatus('network', 'bad status'),
  loadFailed('network', 'load failed'),
  notAnImage('decode', 'not an image');

  const ImageRejection(this.code, this.reason);

  /// Короткий код для журнала.
  final String code;

  /// Текст причины для сообщения исключения и тестов.
  final String reason;
}

/// Изображение отклонено: слишком большое, редирект не на `https`, плохой
/// статус или сбой чтения.
///
/// Сообщение без адреса и без текста исключения сети: адрес приходит из
/// недоверенного ответа и может нести данные (`AGENTS.md` §16). О `codelab_ui`
/// не знает: код причины читает `CodeLabShellCubit` (инфраструктура не зависит
/// от презентации, §6).
final class ImageRejectedException implements Exception {
  const ImageRejectedException(this.rejection);

  final ImageRejection rejection;

  String get reason => rejection.reason;

  /// Короткий код для журнала.
  String get code => rejection.code;

  @override
  String toString() => 'ImageRejectedException: ${rejection.reason}';
}

/// Читает тело изображения [uri] не больше [maxBytes].
///
/// Почему: враждебный сервер может отдать гигабайтное тело или сжатую «бомбу»,
/// а `NetworkImage` читает всё в память и следует любым редиректам, в том числе
/// на `http` (ревью итерации 4, MEDIUM; D6, R4).
///
/// Для чего: лимит проверяется дважды — по `Content-Length` до чтения и по
/// факту прочитанного; редиректы не выполняются автоматически, а каждый
/// следующий адрес проверяется `isLoadableImage` (не больше трёх). Любой отказ —
/// [ImageRejectedException] без адреса. Начальный адрес не перепроверяется:
/// политику применил вызывающий.
///
/// Как использовать: из `LimitedNetworkImage`; тест передаёт малый [maxBytes].
Future<Uint8List> fetchLimitedImageBytes(
  Uri uri, {
  int maxBytes = kMaxImageBytes,
  Duration connectionTimeout = const Duration(seconds: 10),
  Duration totalTimeout = const Duration(seconds: 30),
  HttpClient Function()? clientFactory,
}) async {
  final client = (clientFactory ?? HttpClient.new)()
    ..connectionTimeout = connectionTimeout;
  try {
    // Общий таймаут: медленный или молчащий сервер не держит соединение и
    // память бесконечно; клиент закрывается принудительно в `finally`.
    return await _download(client, uri, maxBytes).timeout(
      totalTimeout,
      onTimeout: () =>
          throw const ImageRejectedException(ImageRejection.timeout),
    );
  } on ImageRejectedException {
    rethrow;
  } on Object {
    throw const ImageRejectedException(ImageRejection.loadFailed);
  } finally {
    client.close(force: true);
  }
}

Future<Uint8List> _download(HttpClient client, Uri uri, int maxBytes) async {
  {
    var target = uri;
    for (var hop = 0; hop <= 3; hop++) {
      final request = await client.getUrl(target);
      request.followRedirects = false;
      final response = await request.close();
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        final next = location == null ? null : target.resolve(location);
        if (next == null || !isLoadableImage(next)) {
          throw const ImageRejectedException(ImageRejection.redirectNotAllowed);
        }
        target = next;
        continue;
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw const ImageRejectedException(ImageRejection.badStatus);
      }
      if (response.contentLength > maxBytes) {
        await response.drain<void>().timeout(
          const Duration(milliseconds: 1),
          onTimeout: () {},
        );
        throw const ImageRejectedException(ImageRejection.tooLarge);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw const ImageRejectedException(ImageRejection.tooLarge);
        }
      }
      return builder.takeBytes();
    }
    throw const ImageRejectedException(ImageRejection.tooManyRedirects);
  }
}

/// `ImageProvider` для изображения ответа агента с лимитом тела и без
/// небезопасных редиректов.
///
/// Почему: см. [fetchLimitedImageBytes]. Для чего: картинка, которую
/// пользователь явно попросил показать (D6). Как использовать: через
/// [imageProviderFor], который добавляет ограничение декодирования.
@immutable
class LimitedNetworkImage extends ImageProvider<LimitedNetworkImage> {
  const LimitedNetworkImage(this.uri);

  final Uri uri;

  @override
  Future<LimitedNetworkImage> obtainKey(ImageConfiguration configuration) =>
      Future.value(this);

  @override
  ImageStreamCompleter loadImage(
    LimitedNetworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    // Без `informationCollector`: он положил бы адрес в отчёт.
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await fetchLimitedImageBytes(uri);
    // Размер из заголовка проверяется до декодирования (ревью итерации 4).
    await checkImageDimensions(bytes);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is LimitedNetworkImage && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

/// Наибольшие размеры картинки до декодирования: сторона и число пикселей.
const int kMaxImageSide = 16384;
const int kMaxImagePixels = 40000000;

/// Читает размеры изображения из заголовка и отклоняет «бомбу».
///
/// Почему: PNG с заголовком 1400×100000 и крошечными данными занимает пару
/// килобайт, но декодер выделил бы сотни мегабайт (ревью итерации 4, MEDIUM).
/// `ResizeImage` ограничивает размер результата, а не выделение при разборе.
///
/// Для чего: вызывается до декодирования. Дескриптор читает только заголовок;
/// буфер и дескриптор освобождаются. Не изображение или неподдержанный формат —
/// тоже отказ; сообщение без адреса.
///
/// Как использовать: после [fetchLimitedImageBytes], перед `decode`.
Future<void> checkImageDimensions(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    if (width > kMaxImageSide ||
        height > kMaxImageSide ||
        width * height > kMaxImagePixels) {
      throw const ImageRejectedException(ImageRejection.dimensions);
    }
  } on ImageRejectedException {
    rethrow;
  } on Object {
    throw const ImageRejectedException(ImageRejection.notAnImage);
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Поставщик изображения приложения; привязывается в графе (`app_scope.dart`).
typedef ImageProviderFor = ImageProvider Function(Uri uri);

/// Поставщик по умолчанию — [imageProviderFor].
ImageProvider defaultImageProviderFor(Uri uri) => imageProviderFor(uri);

/// Поставщик изображения для `CodeLabMarkdownScope.imageFor`: загрузка с
/// лимитами и декодирование не больше [kMaxDecodedImageSide] по каждой стороне
/// с сохранением пропорций (`fit`), чтобы «бомба» не раздула память.
///
/// Функция верхнего уровня: устойчивая ссылка, смена которой перестраивала бы
/// картинки в ленте.
ImageProvider imageProviderFor(Uri uri) => ResizeImage(
  LimitedNetworkImage(uri),
  width: kMaxDecodedImageSide,
  height: kMaxDecodedImageSide,
  policy: ResizeImagePolicy.fit,
);
