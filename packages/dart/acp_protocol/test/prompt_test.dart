import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('prompt turn DTOs', () {
    test('round-trips prompt request with text and resource link blocks', () {
      const request = PromptRequest(
        sessionId: SessionId('session-1'),
        prompt: [
          ContentBlock.text(
            text: 'Implement prompt DTOs',
            annotations: Annotations(audience: [Role.assistant], priority: 0.8),
          ),
          ContentBlock.resourceLink(
            uri: 'file:///workspace/lib/main.dart',
            name: 'main.dart',
            title: 'App entrypoint',
            mimeType: 'text/x-dart',
            size: 1200,
          ),
        ],
        meta: {'trace': 'prompt'},
      );

      expect(PromptRequest.fromJson(request.toJson()), request);
      expect(request.toJson(), {
        'sessionId': 'session-1',
        'prompt': [
          {
            'type': 'text',
            'text': 'Implement prompt DTOs',
            'annotations': {
              'audience': ['assistant'],
              'priority': 0.8,
            },
          },
          {
            'type': 'resource_link',
            'uri': 'file:///workspace/lib/main.dart',
            'name': 'main.dart',
            'title': 'App entrypoint',
            'mimeType': 'text/x-dart',
            'size': 1200,
          },
        ],
        '_meta': {'trace': 'prompt'},
      });
    });

    test('round-trips embedded resource, image, and audio content blocks', () {
      const blocks = [
        ContentBlock.resource(
          resource: EmbeddedResourceContents.text(
            uri: 'file:///workspace/README.md',
            text: '# README',
            mimeType: 'text/markdown',
          ),
        ),
        ContentBlock.resource(
          resource: EmbeddedResourceContents.blob(
            uri: 'file:///workspace/image.png',
            blob: 'base64-data',
            mimeType: 'image/png',
          ),
        ),
        ContentBlock.image(
          data: 'image-bytes',
          mimeType: 'image/png',
          uri: 'file:///workspace/image.png',
        ),
        ContentBlock.audio(data: 'audio-bytes', mimeType: 'audio/wav'),
      ];

      for (final block in blocks) {
        expect(ContentBlock.fromJson(block.toJson()), block);
      }
    });

    test('round-trips prompt response stop reasons', () {
      for (final reason in StopReason.values) {
        final response = PromptResponse(stopReason: reason);

        expect(PromptResponse.fromJson(response.toJson()), response);
      }

      expect(StopReason.values.map((reason) => reason.toJson()), [
        'end_turn',
        'max_tokens',
        'max_turn_requests',
        'refusal',
        'cancelled',
      ]);
    });

    test('round-trips cancel notification', () {
      const notification = CancelNotification(
        sessionId: SessionId('session-1'),
        meta: {'reason': 'user'},
      );

      expect(CancelNotification.fromJson(notification.toJson()), notification);
      expect(notification.toJson(), {
        'sessionId': 'session-1',
        '_meta': {'reason': 'user'},
      });
    });

    test('rejects invalid discriminators and shapes', () {
      expect(
        () => ContentBlock.fromJson({'type': 'video'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => ContentBlock.fromJson({'type': 'text'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => EmbeddedResourceContents.fromJson({
          'uri': 'file:///workspace/empty',
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => StopReason.fromJson('timeout'),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => PromptRequest.fromJson({
          'sessionId': 'session-1',
          'prompt': {'type': 'text', 'text': 'wrong container'},
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });
  });
}
