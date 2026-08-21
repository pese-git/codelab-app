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
