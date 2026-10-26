import 'dart:async';

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

/// Zone key marking a decode that must ignore unknown root fields.
///
/// A zone value rather than a global flag or a parameter threaded through
/// every `fromJson`: it is scoped to one call, exception-safe, needs no
/// cleanup, and reaches nested value objects without touching their
/// (generated) factory signatures.
const _tolerateUnknownRootFieldsKey = #acpTolerateUnknownRootFields;

/// Runs [decode] so that [requireOnlyRootKeys] ignores unknown root fields of
/// every object it decodes, at any nesting depth.
///
/// Used for the `result` of an agent's response: the agent is an external
/// process, so rejecting the whole response over a field this client has not
/// modelled yet (e.g. `session/new` -> `models`) costs a valid, already
/// created session and protects nothing. Only extra root keys are tolerated;
/// a non-object, a missing required field, a wrong type or an unknown
/// discriminator is still an `invalidShape`.
///
/// Requests this client sends and the requests/notifications the agent
/// initiates are not wrapped by this, so they stay strict.
T tolerateUnknownRootFields<T>(T Function() decode) {
  return Zone.current
      .fork(zoneValues: {_tolerateUnknownRootFieldsKey: true})
      .run(decode);
}

void requireOnlyRootKeys(
  JsonObject source, {
  required String path,
  required Set<String> allowedKeys,
}) {
  if (Zone.current[_tolerateUnknownRootFieldsKey] == true) {
    return;
  }

  for (final key in source.keys) {
    if (!allowedKeys.contains(key)) {
      throw JsonRpcProtocolException.invalidShape(
        '$path contains unsupported root field "$key"; use _meta for extensions.',
      );
    }
  }
}
