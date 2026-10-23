import '../cancel/cancel_token.dart';
import '../llm/messages.dart';
import '../tools/pairing.dart';
import 'loop_config.dart';

/// The payload of one model request (`agent-core-architecture` §5.2): the
/// transcript through [transform] (or a copy of it), then the pairing
/// repair. The transcript itself is never changed (LOOP-7).
Future<PairingRepair> buildPayload(
  List<Message> transcript, {
  required CancelToken cancel,
  TransformContextHook? transform,
}) async {
  final messages = transform == null
      ? List<Message>.of(transcript)
      : await transform(List.unmodifiable(transcript), cancel);
  return repairToolPairing(messages);
}

final _pairingError = RegExp(
  r'tool[_ ]?(use|call|result)',
  caseSensitive: false,
);

/// A `badRequest` that describes a broken call/result pairing, as OpenAI
/// (`tool_call_id`) and Anthropic (`tool_use` / `tool_result`) word it
/// (design.md, D8).
bool isPairingError(String? message) =>
    message != null && _pairingError.hasMatch(message);
