// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'json_rpc_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$JsonRpcMessage {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonRpcMessage);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JsonRpcMessage()';
}


}

/// @nodoc
class $JsonRpcMessageCopyWith<$Res>  {
$JsonRpcMessageCopyWith(JsonRpcMessage _, $Res Function(JsonRpcMessage) __);
}


/// Adds pattern-matching-related methods to [JsonRpcMessage].
extension JsonRpcMessagePatterns on JsonRpcMessage {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( JsonRpcRequest value)?  request,TResult Function( JsonRpcNotification value)?  notification,TResult Function( JsonRpcResponse value)?  response,required TResult orElse(),}){
final _that = this;
switch (_that) {
case JsonRpcRequest() when request != null:
return request(_that);case JsonRpcNotification() when notification != null:
return notification(_that);case JsonRpcResponse() when response != null:
return response(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( JsonRpcRequest value)  request,required TResult Function( JsonRpcNotification value)  notification,required TResult Function( JsonRpcResponse value)  response,}){
final _that = this;
switch (_that) {
case JsonRpcRequest():
return request(_that);case JsonRpcNotification():
return notification(_that);case JsonRpcResponse():
return response(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( JsonRpcRequest value)?  request,TResult? Function( JsonRpcNotification value)?  notification,TResult? Function( JsonRpcResponse value)?  response,}){
final _that = this;
switch (_that) {
case JsonRpcRequest() when request != null:
return request(_that);case JsonRpcNotification() when notification != null:
return notification(_that);case JsonRpcResponse() when response != null:
return response(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( JsonRpcId id,  String method,  Object? params)?  request,TResult Function( String method,  Object? params)?  notification,TResult Function( JsonRpcId id,  Object? result,  JsonRpcError? error)?  response,required TResult orElse(),}) {final _that = this;
switch (_that) {
case JsonRpcRequest() when request != null:
return request(_that.id,_that.method,_that.params);case JsonRpcNotification() when notification != null:
return notification(_that.method,_that.params);case JsonRpcResponse() when response != null:
return response(_that.id,_that.result,_that.error);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( JsonRpcId id,  String method,  Object? params)  request,required TResult Function( String method,  Object? params)  notification,required TResult Function( JsonRpcId id,  Object? result,  JsonRpcError? error)  response,}) {final _that = this;
switch (_that) {
case JsonRpcRequest():
return request(_that.id,_that.method,_that.params);case JsonRpcNotification():
return notification(_that.method,_that.params);case JsonRpcResponse():
return response(_that.id,_that.result,_that.error);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( JsonRpcId id,  String method,  Object? params)?  request,TResult? Function( String method,  Object? params)?  notification,TResult? Function( JsonRpcId id,  Object? result,  JsonRpcError? error)?  response,}) {final _that = this;
switch (_that) {
case JsonRpcRequest() when request != null:
return request(_that.id,_that.method,_that.params);case JsonRpcNotification() when notification != null:
return notification(_that.method,_that.params);case JsonRpcResponse() when response != null:
return response(_that.id,_that.result,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class JsonRpcRequest extends JsonRpcMessage {
  const JsonRpcRequest({required this.id, required this.method, this.params}): super._();
  

 final  JsonRpcId id;
 final  String method;
 final  Object? params;

/// Create a copy of JsonRpcMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JsonRpcRequestCopyWith<JsonRpcRequest> get copyWith => _$JsonRpcRequestCopyWithImpl<JsonRpcRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonRpcRequest&&(identical(other.id, id) || other.id == id)&&(identical(other.method, method) || other.method == method)&&const DeepCollectionEquality().equals(other.params, params));
}


@override
int get hashCode => Object.hash(runtimeType,id,method,const DeepCollectionEquality().hash(params));

@override
String toString() {
  return 'JsonRpcMessage.request(id: $id, method: $method, params: $params)';
}


}

/// @nodoc
abstract mixin class $JsonRpcRequestCopyWith<$Res> implements $JsonRpcMessageCopyWith<$Res> {
  factory $JsonRpcRequestCopyWith(JsonRpcRequest value, $Res Function(JsonRpcRequest) _then) = _$JsonRpcRequestCopyWithImpl;
@useResult
$Res call({
 JsonRpcId id, String method, Object? params
});


$JsonRpcIdCopyWith<$Res> get id;

}
/// @nodoc
class _$JsonRpcRequestCopyWithImpl<$Res>
    implements $JsonRpcRequestCopyWith<$Res> {
  _$JsonRpcRequestCopyWithImpl(this._self, this._then);

  final JsonRpcRequest _self;
  final $Res Function(JsonRpcRequest) _then;

/// Create a copy of JsonRpcMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? method = null,Object? params = freezed,}) {
  return _then(JsonRpcRequest(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as JsonRpcId,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,params: freezed == params ? _self.params : params ,
  ));
}

/// Create a copy of JsonRpcMessage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JsonRpcIdCopyWith<$Res> get id {
  
  return $JsonRpcIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}
}

/// @nodoc


class JsonRpcNotification extends JsonRpcMessage {
  const JsonRpcNotification({required this.method, this.params}): super._();
  

 final  String method;
 final  Object? params;

/// Create a copy of JsonRpcMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JsonRpcNotificationCopyWith<JsonRpcNotification> get copyWith => _$JsonRpcNotificationCopyWithImpl<JsonRpcNotification>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonRpcNotification&&(identical(other.method, method) || other.method == method)&&const DeepCollectionEquality().equals(other.params, params));
}


@override
int get hashCode => Object.hash(runtimeType,method,const DeepCollectionEquality().hash(params));

@override
String toString() {
  return 'JsonRpcMessage.notification(method: $method, params: $params)';
}


}

/// @nodoc
abstract mixin class $JsonRpcNotificationCopyWith<$Res> implements $JsonRpcMessageCopyWith<$Res> {
  factory $JsonRpcNotificationCopyWith(JsonRpcNotification value, $Res Function(JsonRpcNotification) _then) = _$JsonRpcNotificationCopyWithImpl;
@useResult
$Res call({
 String method, Object? params
});




}
/// @nodoc
class _$JsonRpcNotificationCopyWithImpl<$Res>
    implements $JsonRpcNotificationCopyWith<$Res> {
  _$JsonRpcNotificationCopyWithImpl(this._self, this._then);

  final JsonRpcNotification _self;
  final $Res Function(JsonRpcNotification) _then;

/// Create a copy of JsonRpcMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? method = null,Object? params = freezed,}) {
  return _then(JsonRpcNotification(
method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as String,params: freezed == params ? _self.params : params ,
  ));
}


}

/// @nodoc


class JsonRpcResponse extends JsonRpcMessage {
  const JsonRpcResponse({required this.id, this.result, this.error}): super._();
  

 final  JsonRpcId id;
 final  Object? result;
 final  JsonRpcError? error;

/// Create a copy of JsonRpcMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JsonRpcResponseCopyWith<JsonRpcResponse> get copyWith => _$JsonRpcResponseCopyWithImpl<JsonRpcResponse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonRpcResponse&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other.result, result)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,id,const DeepCollectionEquality().hash(result),error);

@override
String toString() {
  return 'JsonRpcMessage.response(id: $id, result: $result, error: $error)';
}


}

/// @nodoc
abstract mixin class $JsonRpcResponseCopyWith<$Res> implements $JsonRpcMessageCopyWith<$Res> {
  factory $JsonRpcResponseCopyWith(JsonRpcResponse value, $Res Function(JsonRpcResponse) _then) = _$JsonRpcResponseCopyWithImpl;
@useResult
$Res call({
 JsonRpcId id, Object? result, JsonRpcError? error
});


$JsonRpcIdCopyWith<$Res> get id;$JsonRpcErrorCopyWith<$Res>? get error;

}
/// @nodoc
class _$JsonRpcResponseCopyWithImpl<$Res>
    implements $JsonRpcResponseCopyWith<$Res> {
  _$JsonRpcResponseCopyWithImpl(this._self, this._then);

  final JsonRpcResponse _self;
  final $Res Function(JsonRpcResponse) _then;

/// Create a copy of JsonRpcMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? result = freezed,Object? error = freezed,}) {
  return _then(JsonRpcResponse(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as JsonRpcId,result: freezed == result ? _self.result : result ,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as JsonRpcError?,
  ));
}

/// Create a copy of JsonRpcMessage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JsonRpcIdCopyWith<$Res> get id {
  
  return $JsonRpcIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of JsonRpcMessage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$JsonRpcErrorCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $JsonRpcErrorCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
