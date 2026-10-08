import '../json_rpc/json_value.dart';
import '../json_rpc/protocol_error.dart';

JsonObject requireAcpObject(
  Object? value, {
  required String path,
  required Set<String> allowedKeys,
}) {
  final source = requireJsonObject(value, path: path);
  requireOnlyRootKeys(source, path: path, allowedKeys: allowedKeys);
  return source;
}

/// Validates a capability object of the `initialize` handshake
/// (`agentCapabilities` and everything nested under it).
///
/// Unlike [requireAcpObject] this does not reject unknown root fields.
/// Capability flags are extended independently by each side of the
/// connection, so a newer agent legitimately announces flags this client has
/// not modelled yet (e.g. `sessionCapabilities.fork`/`resume`); rejecting
/// them would fail the whole handshake. The model's `fromJson` reads only the
/// fields it knows, so an unknown one is ignored, never interpreted.
///
/// Runtime ACP messages (`session/update`, `tool_call`, `permission`, `fs/*`,
/// `terminal/*`, ...) are not capability negotiation and must keep using the
/// strict [requireAcpObject]: an unexpected field there is a real protocol
/// error.
JsonObject requireAcpCapabilityObject(Object? value, {required String path}) {
  return requireJsonObject(value, path: path);
}

void requireOnlyRootKeys(
  JsonObject source, {
  required String path,
  required Set<String> allowedKeys,
}) {
  for (final key in source.keys) {
    if (!allowedKeys.contains(key)) {
      throw JsonRpcProtocolException.invalidShape(
        '$path contains unsupported root field "$key"; use _meta for extensions.',
      );
    }
  }
}
