import 'dart:convert';

/// Builders of journal lines for parser and projection tests: short ids,
/// one fixed time, the JSON form of §8.2.

const at = '2026-10-21T08:00:00.000Z';

String journal(List<String> lines) => '${lines.join('\n')}\n';

String header({
  int version = 1,
  String id = '01JB8Q2W6R9T3M5K7N1P4X8Z0C',
  String cwd = '/work/demo',
}) => jsonEncode({
  'type': 'session',
  'version': version,
  'id': id,
  'cwd': cwd,
  'created': at,
  'agent': {'name': 'codelab-agent', 'version': '0.1.0'},
});

Map<String, Object?> _common(String type, String id, String? parent) => {
  'type': type,
  'id': id,
  'parentId': parent,
  'timestamp': at,
};

const _zeroUsage = {
  'input': 0,
  'output': 0,
  'cacheRead': 0,
  'cacheWrite': 0,
  'cost': {'input': 0.0, 'output': 0.0, 'cacheRead': 0.0, 'cacheWrite': 0.0},
};

String user(
  String id,
  String? parent, {
  String text = 'hello',
  String? origin,
  Map<String, Object?> originFields = const {},
}) => jsonEncode({
  ..._common('message', id, parent),
  'origin': ?origin,
  ...originFields,
  'message': {
    'role': 'user',
    'content': [
      {'type': 'text', 'text': text},
    ],
    'timestamp': at,
  },
});

/// An assistant answer; [calls] are `(id, name, arguments)`.
String answer(
  String id,
  String? parent, {
  String? text = 'ok',
  List<(String, String, Map<String, Object?>)> calls = const [],
  Map<String, Object?> usage = _zeroUsage,
  String stopReason = 'stop',
}) => jsonEncode({
  ..._common('message', id, parent),
  'message': {
    'role': 'assistant',
    'content': [
      if (text != null) {'type': 'text', 'text': text},
      for (final (callId, name, args) in calls)
        {'type': 'toolCall', 'id': callId, 'name': name, 'arguments': args},
    ],
    'model': {'provider': 'test', 'id': 'model-1'},
    'usage': usage,
    'stopReason': calls.isEmpty ? stopReason : 'toolUse',
    'timestamp': at,
  },
});

String toolResult(
  String id,
  String? parent, {
  required String callId,
  String tool = 'read',
  String text = 'result',
  String outcome = 'completed',
  bool isError = false,
  Map<String, Object?>? toolMeta,
}) => jsonEncode({
  ..._common('message', id, parent),
  'outcome': outcome,
  'toolMeta': ?toolMeta,
  'message': {
    'role': 'toolResult',
    'toolCallId': callId,
    'toolName': tool,
    'content': [
      {'type': 'text', 'text': text},
    ],
    'isError': isError,
    'timestamp': at,
  },
});

String leaf(String id, String? parent, {required String target}) =>
    jsonEncode({..._common('leaf', id, parent), 'targetId': target});

String modeChange(String id, String? parent, String mode) =>
    jsonEncode({..._common('mode_change', id, parent), 'modeId': mode});

String modelChange(String id, String? parent, {String provider = 'test'}) =>
    jsonEncode({
      ..._common('model_change', id, parent),
      'provider': provider,
      'modelId': 'model-1',
    });

String sessionInfo(String id, String? parent, String title) => jsonEncode({
  ..._common('session_info', id, parent),
  'title': title,
  'source': 'auto',
});

String plan(String id, String? parent, List<String> contents) => jsonEncode({
  ..._common('plan', id, parent),
  'entries': [
    for (final c in contents)
      {'content': c, 'priority': 'high', 'status': 'pending'},
  ],
});

String compaction(
  String id,
  String? parent, {
  required String firstKept,
  String summary = '## Goal\nFix it',
}) => jsonEncode({
  ..._common('compaction', id, parent),
  'summary': summary,
  'firstKeptId': firstKept,
  'tokensBefore': 1000,
  'tokensAfter': 100,
});
