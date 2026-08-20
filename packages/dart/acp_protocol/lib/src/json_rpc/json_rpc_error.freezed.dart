// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'json_rpc_error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$JsonRpcError {

 int get code; String get message; Object? get data;
/// Create a copy of JsonRpcError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JsonRpcErrorCopyWith<JsonRpcError> get copyWith => _$JsonRpcErrorCopyWithImpl<JsonRpcError>(this as JsonRpcError, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonRpcError&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&const DeepCollectionEquality().equals(other.data, data));
}


@override
int get hashCode => Object.hash(runtimeType,code,message,const DeepCollectionEquality().hash(data));

@override
String toString() {
  return 'JsonRpcError(code: $code, message: $message, data: $data)';
}


}

/// @nodoc
abstract mixin class $JsonRpcErrorCopyWith<$Res>  {
  factory $JsonRpcErrorCopyWith(JsonRpcError value, $Res Function(JsonRpcError) _then) = _$JsonRpcErrorCopyWithImpl;
@useResult
$Res call({
 int code, String message, Object? data
});




}
/// @nodoc
class _$JsonRpcErrorCopyWithImpl<$Res>
    implements $JsonRpcErrorCopyWith<$Res> {
  _$JsonRpcErrorCopyWithImpl(this._self, this._then);

  final JsonRpcError _self;
  final $Res Function(JsonRpcError) _then;

/// Create a copy of JsonRpcError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? message = null,Object? data = freezed,}) {
  return _then(_self.copyWith(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,data: freezed == data ? _self.data : data ,
  ));
}

}


/// Adds pattern-matching-related methods to [JsonRpcError].
extension JsonRpcErrorPatterns on JsonRpcError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _JsonRpcError value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _JsonRpcError() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _JsonRpcError value)  $default,){
final _that = this;
switch (_that) {
case _JsonRpcError():
return $default(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _JsonRpcError value)?  $default,){
final _that = this;
switch (_that) {
case _JsonRpcError() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int code,  String message,  Object? data)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _JsonRpcError() when $default != null:
return $default(_that.code,_that.message,_that.data);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int code,  String message,  Object? data)  $default,) {final _that = this;
switch (_that) {
case _JsonRpcError():
return $default(_that.code,_that.message,_that.data);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int code,  String message,  Object? data)?  $default,) {final _that = this;
switch (_that) {
case _JsonRpcError() when $default != null:
return $default(_that.code,_that.message,_that.data);case _:
  return null;

}
}

}

/// @nodoc


class _JsonRpcError extends JsonRpcError {
  const _JsonRpcError({required this.code, required this.message, this.data}): super._();
  

@override final  int code;
@override final  String message;
@override final  Object? data;

/// Create a copy of JsonRpcError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$JsonRpcErrorCopyWith<_JsonRpcError> get copyWith => __$JsonRpcErrorCopyWithImpl<_JsonRpcError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _JsonRpcError&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&const DeepCollectionEquality().equals(other.data, data));
}


@override
int get hashCode => Object.hash(runtimeType,code,message,const DeepCollectionEquality().hash(data));

@override
String toString() {
  return 'JsonRpcError(code: $code, message: $message, data: $data)';
}


}

/// @nodoc
abstract mixin class _$JsonRpcErrorCopyWith<$Res> implements $JsonRpcErrorCopyWith<$Res> {
  factory _$JsonRpcErrorCopyWith(_JsonRpcError value, $Res Function(_JsonRpcError) _then) = __$JsonRpcErrorCopyWithImpl;
@override @useResult
$Res call({
 int code, String message, Object? data
});




}
/// @nodoc
class __$JsonRpcErrorCopyWithImpl<$Res>
    implements _$JsonRpcErrorCopyWith<$Res> {
  __$JsonRpcErrorCopyWithImpl(this._self, this._then);

  final _JsonRpcError _self;
  final $Res Function(_JsonRpcError) _then;

/// Create a copy of JsonRpcError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,Object? data = freezed,}) {
  return _then(_JsonRpcError(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as int,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,data: freezed == data ? _self.data : data ,
  ));
}


}

// dart format on
