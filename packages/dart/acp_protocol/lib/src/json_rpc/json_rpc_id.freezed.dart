// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'json_rpc_id.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$JsonRpcId {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonRpcId);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JsonRpcId()';
}


}

/// @nodoc
class $JsonRpcIdCopyWith<$Res>  {
$JsonRpcIdCopyWith(JsonRpcId _, $Res Function(JsonRpcId) __);
}


/// Adds pattern-matching-related methods to [JsonRpcId].
extension JsonRpcIdPatterns on JsonRpcId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( JsonRpcStringId value)?  string,TResult Function( JsonRpcIntId value)?  integer,TResult Function( JsonRpcNullId value)?  nullValue,required TResult orElse(),}){
final _that = this;
switch (_that) {
case JsonRpcStringId() when string != null:
return string(_that);case JsonRpcIntId() when integer != null:
return integer(_that);case JsonRpcNullId() when nullValue != null:
return nullValue(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( JsonRpcStringId value)  string,required TResult Function( JsonRpcIntId value)  integer,required TResult Function( JsonRpcNullId value)  nullValue,}){
final _that = this;
switch (_that) {
case JsonRpcStringId():
return string(_that);case JsonRpcIntId():
return integer(_that);case JsonRpcNullId():
return nullValue(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( JsonRpcStringId value)?  string,TResult? Function( JsonRpcIntId value)?  integer,TResult? Function( JsonRpcNullId value)?  nullValue,}){
final _that = this;
switch (_that) {
case JsonRpcStringId() when string != null:
return string(_that);case JsonRpcIntId() when integer != null:
return integer(_that);case JsonRpcNullId() when nullValue != null:
return nullValue(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String value)?  string,TResult Function( int value)?  integer,TResult Function()?  nullValue,required TResult orElse(),}) {final _that = this;
switch (_that) {
case JsonRpcStringId() when string != null:
return string(_that.value);case JsonRpcIntId() when integer != null:
return integer(_that.value);case JsonRpcNullId() when nullValue != null:
return nullValue();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String value)  string,required TResult Function( int value)  integer,required TResult Function()  nullValue,}) {final _that = this;
switch (_that) {
case JsonRpcStringId():
return string(_that.value);case JsonRpcIntId():
return integer(_that.value);case JsonRpcNullId():
return nullValue();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String value)?  string,TResult? Function( int value)?  integer,TResult? Function()?  nullValue,}) {final _that = this;
switch (_that) {
case JsonRpcStringId() when string != null:
return string(_that.value);case JsonRpcIntId() when integer != null:
return integer(_that.value);case JsonRpcNullId() when nullValue != null:
return nullValue();case _:
  return null;

}
}

}

/// @nodoc


class JsonRpcStringId extends JsonRpcId {
  const JsonRpcStringId(this.value): super._();
  

 final  String value;

/// Create a copy of JsonRpcId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JsonRpcStringIdCopyWith<JsonRpcStringId> get copyWith => _$JsonRpcStringIdCopyWithImpl<JsonRpcStringId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonRpcStringId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'JsonRpcId.string(value: $value)';
}


}

/// @nodoc
abstract mixin class $JsonRpcStringIdCopyWith<$Res> implements $JsonRpcIdCopyWith<$Res> {
  factory $JsonRpcStringIdCopyWith(JsonRpcStringId value, $Res Function(JsonRpcStringId) _then) = _$JsonRpcStringIdCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$JsonRpcStringIdCopyWithImpl<$Res>
    implements $JsonRpcStringIdCopyWith<$Res> {
  _$JsonRpcStringIdCopyWithImpl(this._self, this._then);

  final JsonRpcStringId _self;
  final $Res Function(JsonRpcStringId) _then;

/// Create a copy of JsonRpcId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(JsonRpcStringId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class JsonRpcIntId extends JsonRpcId {
  const JsonRpcIntId(this.value): super._();
  

 final  int value;

/// Create a copy of JsonRpcId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$JsonRpcIntIdCopyWith<JsonRpcIntId> get copyWith => _$JsonRpcIntIdCopyWithImpl<JsonRpcIntId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonRpcIntId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'JsonRpcId.integer(value: $value)';
}


}

/// @nodoc
abstract mixin class $JsonRpcIntIdCopyWith<$Res> implements $JsonRpcIdCopyWith<$Res> {
  factory $JsonRpcIntIdCopyWith(JsonRpcIntId value, $Res Function(JsonRpcIntId) _then) = _$JsonRpcIntIdCopyWithImpl;
@useResult
$Res call({
 int value
});




}
/// @nodoc
class _$JsonRpcIntIdCopyWithImpl<$Res>
    implements $JsonRpcIntIdCopyWith<$Res> {
  _$JsonRpcIntIdCopyWithImpl(this._self, this._then);

  final JsonRpcIntId _self;
  final $Res Function(JsonRpcIntId) _then;

/// Create a copy of JsonRpcId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(JsonRpcIntId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class JsonRpcNullId extends JsonRpcId {
  const JsonRpcNullId(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is JsonRpcNullId);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'JsonRpcId.nullValue()';
}


}




// dart format on
