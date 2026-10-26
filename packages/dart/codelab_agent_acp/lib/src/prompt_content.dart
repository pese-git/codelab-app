import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'connection/acp_error.dart';

/// Блоки `prompt` из ACP в блоки ядра (`agent-core-architecture` §13.4,
/// «Контент промпта»).
///
/// Почему текстом: ядро и провайдеры знают только текст и картинки. Ресурс
/// с текстом встраивается с путём, бинарный ресурс и ссылка становятся
/// пометкой — модель прочитает файл сама инструментом `read`, если нужно.
/// Тексты пометок — для модели, поэтому английские.
///
/// Как использовать: обработчик `session/prompt` вызывает [promptContent]
/// до запуска хода. Пустой промпт и `audio` (не объявлен в
/// `promptCapabilities`) — [AcpRequestError] `-32602`.
List<ContentBlock> promptContent(List<acp.ContentBlock> prompt) {
  if (prompt.isEmpty) {
    throw const AcpRequestError.invalidParams('prompt must not be empty');
  }
  return [for (final block in prompt) _block(block)];
}

ContentBlock _block(acp.ContentBlock block) => switch (block) {
  acp.TextContent(:final text) => TextContent(text),
  acp.ImageContent(:final data, :final mimeType) => ImageContent(
    base64: data,
    mimeType: mimeType,
  ),
  acp.AudioContent() => throw const AcpRequestError.invalidParams(
    'audio content is not supported',
  ),
  acp.EmbeddedResource(:final resource) => switch (resource) {
    acp.TextResourceContents(:final uri, :final text) => TextContent(
      '<resource uri="$uri">$text</resource>',
    ),
    acp.BlobResourceContents(:final uri, :final blob) => TextContent(
      'Binary resource $uri, ${_decodedLength(blob)} bytes, not passed',
    ),
  },
  acp.ResourceLink(:final uri, :final name) => TextContent(
    'Resource link $uri ($name)',
  ),
};

/// Размер данных base64 без декодирования: 3 байта на 4 символа минус
/// дополнение `=`.
int _decodedLength(String base64) {
  final clean = base64.replaceAll(RegExp(r'\s'), '');
  final padding = clean.endsWith('==')
      ? 2
      : clean.endsWith('=')
      ? 1
      : 0;
  return clean.length * 3 ~/ 4 - padding;
}
