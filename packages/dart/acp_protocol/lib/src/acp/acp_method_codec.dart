import '../json_rpc/json_rpc_message.dart';
import '../json_rpc/json_rpc_id.dart';
import '../json_rpc/json_value.dart';
import '../json_rpc/protocol_error.dart';
import 'initialize.dart';
import 'permission.dart';
import 'prompt.dart';
import 'session.dart';
import 'session_update.dart';

const initializeMethod = 'initialize';
const sessionNewMethod = 'session/new';
const sessionLoadMethod = 'session/load';
const sessionListMethod = 'session/list';
const sessionPromptMethod = 'session/prompt';
const sessionCancelMethod = 'session/cancel';
const sessionSetConfigOptionMethod = 'session/set_config_option';
const sessionRequestPermissionMethod = 'session/request_permission';
const sessionUpdateMethod = 'session/update';

typedef AcpDecoder<T> = T Function(Object? value);
typedef AcpEncoder<T> = JsonObject Function(T value);

sealed class AcpMethodDefinition<TParams, TResult> {
  const AcpMethodDefinition._({
    required this.method,
    required AcpDecoder<TParams> decodeParams,
    required AcpEncoder<TParams> encodeParams,
    AcpDecoder<TResult>? decodeResult,
    AcpEncoder<TResult>? encodeResult,
  }) : _decodeParams = decodeParams,
       _encodeParams = encodeParams,
       _decodeResult = decodeResult,
       _encodeResult = encodeResult;

  const factory AcpMethodDefinition.request({
    required String method,
    required AcpDecoder<TParams> decodeParams,
    required AcpEncoder<TParams> encodeParams,
    required AcpDecoder<TResult> decodeResult,
    required AcpEncoder<TResult> encodeResult,
  }) = AcpRequestMethod<TParams, TResult>;

  const factory AcpMethodDefinition.notification({
    required String method,
    required AcpDecoder<TParams> decodeParams,
    required AcpEncoder<TParams> encodeParams,
  }) = AcpNotificationMethod<TParams>;

  final String method;
  final AcpDecoder<TParams> _decodeParams;
  final AcpEncoder<TParams> _encodeParams;
  final AcpDecoder<TResult>? _decodeResult;
  final AcpEncoder<TResult>? _encodeResult;

  bool get hasResult => _decodeResult != null;

  TParams decodeParams(Object? value) => _decodeParams(value);

  JsonObject encodeParams(TParams value) => _encodeParams(value);

  TResult decodeResult(Object? value) {
    final decode = _decodeResult;
    if (decode == null) {
      throw JsonRpcProtocolException.invalidShape(
        '$method does not have a result payload.',
      );
    }

    return decode(value);
  }

  JsonObject encodeResult(TResult value) {
    final encode = _encodeResult;
    if (encode == null) {
      throw JsonRpcProtocolException.invalidShape(
        '$method does not have a result payload.',
      );
    }

    return encode(value);
  }
}

final class AcpRequestMethod<TParams, TResult>
    extends AcpMethodDefinition<TParams, TResult> {
  const AcpRequestMethod({
    required super.method,
    required super.decodeParams,
    required super.encodeParams,
    required super.decodeResult,
    required super.encodeResult,
  }) : super._();
}

final class AcpNotificationMethod<TParams>
    extends AcpMethodDefinition<TParams, Never> {
  const AcpNotificationMethod({
    required super.method,
    required super.decodeParams,
    required super.encodeParams,
  }) : super._();
}

const acpInitialize =
    AcpMethodDefinition<InitializeRequest, InitializeResponse>.request(
      method: initializeMethod,
      decodeParams: InitializeRequest.fromJson,
      encodeParams: _encodeInitializeRequest,
      decodeResult: InitializeResponse.fromJson,
      encodeResult: _encodeInitializeResponse,
    );

const acpSessionNew =
    AcpMethodDefinition<NewSessionRequest, NewSessionResponse>.request(
      method: sessionNewMethod,
      decodeParams: NewSessionRequest.fromJson,
      encodeParams: _encodeNewSessionRequest,
      decodeResult: NewSessionResponse.fromJson,
      encodeResult: _encodeNewSessionResponse,
    );

const acpSessionLoad =
    AcpMethodDefinition<LoadSessionRequest, LoadSessionResponse>.request(
      method: sessionLoadMethod,
      decodeParams: LoadSessionRequest.fromJson,
      encodeParams: _encodeLoadSessionRequest,
      decodeResult: LoadSessionResponse.fromJson,
      encodeResult: _encodeLoadSessionResponse,
    );

const acpSessionList =
    AcpMethodDefinition<ListSessionsRequest, ListSessionsResponse>.request(
      method: sessionListMethod,
      decodeParams: ListSessionsRequest.fromJson,
      encodeParams: _encodeListSessionsRequest,
      decodeResult: ListSessionsResponse.fromJson,
      encodeResult: _encodeListSessionsResponse,
    );

const acpSessionPrompt =
    AcpMethodDefinition<PromptRequest, PromptResponse>.request(
      method: sessionPromptMethod,
      decodeParams: PromptRequest.fromJson,
      encodeParams: _encodePromptRequest,
      decodeResult: PromptResponse.fromJson,
      encodeResult: _encodePromptResponse,
    );

const acpSessionCancel =
    AcpMethodDefinition<CancelNotification, Never>.notification(
      method: sessionCancelMethod,
      decodeParams: CancelNotification.fromJson,
      encodeParams: _encodeCancelNotification,
    );

const acpSessionSetConfigOption =
    AcpMethodDefinition<
      SetSessionConfigOptionRequest,
      SetSessionConfigOptionResponse
    >.request(
      method: sessionSetConfigOptionMethod,
      decodeParams: SetSessionConfigOptionRequest.fromJson,
      encodeParams: _encodeSetSessionConfigOptionRequest,
      decodeResult: SetSessionConfigOptionResponse.fromJson,
      encodeResult: _encodeSetSessionConfigOptionResponse,
    );

const acpSessionRequestPermission =
    AcpMethodDefinition<
      RequestPermissionRequest,
      RequestPermissionResponse
    >.request(
      method: sessionRequestPermissionMethod,
      decodeParams: RequestPermissionRequest.fromJson,
      encodeParams: _encodeRequestPermissionRequest,
      decodeResult: RequestPermissionResponse.fromJson,
      encodeResult: _encodeRequestPermissionResponse,
    );

const acpSessionUpdate =
    AcpMethodDefinition<SessionNotification, Never>.notification(
      method: sessionUpdateMethod,
      decodeParams: SessionNotification.fromJson,
      encodeParams: _encodeSessionNotification,
    );

const acpMethodRegistry = <String, AcpMethodDefinition<Object, Object>>{
  initializeMethod: acpInitialize,
  sessionNewMethod: acpSessionNew,
  sessionLoadMethod: acpSessionLoad,
  sessionListMethod: acpSessionList,
  sessionPromptMethod: acpSessionPrompt,
  sessionCancelMethod: acpSessionCancel,
  sessionSetConfigOptionMethod: acpSessionSetConfigOption,
  sessionRequestPermissionMethod: acpSessionRequestPermission,
  sessionUpdateMethod: acpSessionUpdate,
};

AcpMethodDefinition<Object, Object> requireAcpMethod(String method) {
  final definition = acpMethodRegistry[method];
  if (definition != null) {
    return definition;
  }

  throw JsonRpcProtocolException.unknownMethod(method);
}

Object decodeAcpParams(String method, Object? params) {
  return requireAcpMethod(method).decodeParams(params);
}

JsonObject encodeAcpParams(String method, Object params) {
  return requireAcpMethod(method).encodeParams(params);
}

Object decodeAcpResult(String method, Object? result) {
  return requireAcpMethod(method).decodeResult(result);
}

JsonObject encodeAcpResult(String method, Object result) {
  return requireAcpMethod(method).encodeResult(result);
}

Object decodeAcpRequestParams(JsonRpcRequest request) {
  final definition = requireAcpMethod(request.method);
  if (definition is AcpNotificationMethod<Object>) {
    throw JsonRpcProtocolException.invalidShape(
      '${request.method} must be a notification.',
    );
  }

  return definition.decodeParams(request.params);
}

Object decodeAcpNotificationParams(JsonRpcNotification notification) {
  final definition = requireAcpMethod(notification.method);
  if (definition is! AcpNotificationMethod<Object>) {
    throw JsonRpcProtocolException.invalidShape(
      '${notification.method} must be a request.',
    );
  }

  return definition.decodeParams(notification.params);
}

Object decodeAcpResponseResult({
  required String method,
  required JsonRpcResponse response,
}) {
  if (response.error != null) {
    throw JsonRpcProtocolException.invalidShape(
      'cannot decode an error response result.',
    );
  }

  return decodeAcpResult(method, response.result);
}

JsonRpcRequest encodeAcpRequest({
  required JsonRpcId id,
  required String method,
  required Object params,
}) {
  final definition = requireAcpMethod(method);
  if (definition is AcpNotificationMethod<Object>) {
    throw JsonRpcProtocolException.invalidShape(
      '$method must be encoded as a notification.',
    );
  }

  return JsonRpcMessage.request(
        id: id,
        method: method,
        params: definition.encodeParams(params),
      )
      as JsonRpcRequest;
}

JsonRpcNotification encodeAcpNotification({
  required String method,
  required Object params,
}) {
  final definition = requireAcpMethod(method);
  if (definition is! AcpNotificationMethod<Object>) {
    throw JsonRpcProtocolException.invalidShape(
      '$method must be encoded as a request.',
    );
  }

  return JsonRpcMessage.notification(
        method: method,
        params: definition.encodeParams(params),
      )
      as JsonRpcNotification;
}

JsonRpcResponse encodeAcpResponse({
  required JsonRpcId id,
  required String method,
  required Object result,
}) {
  return JsonRpcMessage.response(
        id: id,
        result: encodeAcpResult(method, result),
      )
      as JsonRpcResponse;
}

JsonObject _encodeInitializeRequest(InitializeRequest value) => value.toJson();
JsonObject _encodeInitializeResponse(InitializeResponse value) =>
    value.toJson();
JsonObject _encodeNewSessionRequest(NewSessionRequest value) => value.toJson();
JsonObject _encodeNewSessionResponse(NewSessionResponse value) =>
    value.toJson();
JsonObject _encodeLoadSessionRequest(LoadSessionRequest value) =>
    value.toJson();
JsonObject _encodeLoadSessionResponse(LoadSessionResponse value) =>
    value.toJson();
JsonObject _encodeListSessionsRequest(ListSessionsRequest value) =>
    value.toJson();
JsonObject _encodeListSessionsResponse(ListSessionsResponse value) =>
    value.toJson();
JsonObject _encodePromptRequest(PromptRequest value) => value.toJson();
JsonObject _encodePromptResponse(PromptResponse value) => value.toJson();
JsonObject _encodeCancelNotification(CancelNotification value) =>
    value.toJson();
JsonObject _encodeSetSessionConfigOptionRequest(
  SetSessionConfigOptionRequest value,
) => value.toJson();
JsonObject _encodeSetSessionConfigOptionResponse(
  SetSessionConfigOptionResponse value,
) => value.toJson();
JsonObject _encodeRequestPermissionRequest(RequestPermissionRequest value) =>
    value.toJson();
JsonObject _encodeRequestPermissionResponse(RequestPermissionResponse value) =>
    value.toJson();
JsonObject _encodeSessionNotification(SessionNotification value) =>
    value.toJson();
