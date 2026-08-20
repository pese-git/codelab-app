/// Public API for ACP JSON-RPC models, codecs, validation, and errors.
library;

export 'src/acp/acp_method_codec.dart';
export 'src/acp/initialize.dart';
export 'src/acp/permission.dart';
export 'src/acp/prompt.dart';
export 'src/acp/session.dart';
export 'src/acp/session_update.dart';
export 'src/acp/tool_call.dart';
export 'src/json_rpc/json_rpc_codec.dart';
export 'src/json_rpc/json_rpc_error.dart';
export 'src/json_rpc/json_rpc_id.dart';
export 'src/json_rpc/json_rpc_message.dart';
export 'src/json_rpc/protocol_error.dart';

const acpProtocolPackageName = 'acp_protocol';
