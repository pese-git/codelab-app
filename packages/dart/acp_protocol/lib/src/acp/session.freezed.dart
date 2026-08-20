// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SessionId {

 String get value;
/// Create a copy of SessionId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionIdCopyWith<SessionId> get copyWith => _$SessionIdCopyWithImpl<SessionId>(this as SessionId, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'SessionId(value: $value)';
}


}

/// @nodoc
abstract mixin class $SessionIdCopyWith<$Res>  {
  factory $SessionIdCopyWith(SessionId value, $Res Function(SessionId) _then) = _$SessionIdCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$SessionIdCopyWithImpl<$Res>
    implements $SessionIdCopyWith<$Res> {
  _$SessionIdCopyWithImpl(this._self, this._then);

  final SessionId _self;
  final $Res Function(SessionId) _then;

/// Create a copy of SessionId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(_self.copyWith(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionId].
extension SessionIdPatterns on SessionId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionId value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionId() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionId value)  $default,){
final _that = this;
switch (_that) {
case _SessionId():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionId value)?  $default,){
final _that = this;
switch (_that) {
case _SessionId() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionId() when $default != null:
return $default(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String value)  $default,) {final _that = this;
switch (_that) {
case _SessionId():
return $default(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String value)?  $default,) {final _that = this;
switch (_that) {
case _SessionId() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _SessionId extends SessionId {
  const _SessionId(this.value): super._();
  

@override final  String value;

/// Create a copy of SessionId
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionIdCopyWith<_SessionId> get copyWith => __$SessionIdCopyWithImpl<_SessionId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'SessionId(value: $value)';
}


}

/// @nodoc
abstract mixin class _$SessionIdCopyWith<$Res> implements $SessionIdCopyWith<$Res> {
  factory _$SessionIdCopyWith(_SessionId value, $Res Function(_SessionId) _then) = __$SessionIdCopyWithImpl;
@override @useResult
$Res call({
 String value
});




}
/// @nodoc
class __$SessionIdCopyWithImpl<$Res>
    implements _$SessionIdCopyWith<$Res> {
  __$SessionIdCopyWithImpl(this._self, this._then);

  final _SessionId _self;
  final $Res Function(_SessionId) _then;

/// Create a copy of SessionId
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_SessionId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$EnvVariable {

 String get name; String get value;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of EnvVariable
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EnvVariableCopyWith<EnvVariable> get copyWith => _$EnvVariableCopyWithImpl<EnvVariable>(this as EnvVariable, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EnvVariable&&(identical(other.name, name) || other.name == name)&&(identical(other.value, value) || other.value == value)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,name,value,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'EnvVariable(name: $name, value: $value, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $EnvVariableCopyWith<$Res>  {
  factory $EnvVariableCopyWith(EnvVariable value, $Res Function(EnvVariable) _then) = _$EnvVariableCopyWithImpl;
@useResult
$Res call({
 String name, String value,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$EnvVariableCopyWithImpl<$Res>
    implements $EnvVariableCopyWith<$Res> {
  _$EnvVariableCopyWithImpl(this._self, this._then);

  final EnvVariable _self;
  final $Res Function(EnvVariable) _then;

/// Create a copy of EnvVariable
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? value = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

}


/// Adds pattern-matching-related methods to [EnvVariable].
extension EnvVariablePatterns on EnvVariable {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EnvVariable value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EnvVariable() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EnvVariable value)  $default,){
final _that = this;
switch (_that) {
case _EnvVariable():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EnvVariable value)?  $default,){
final _that = this;
switch (_that) {
case _EnvVariable() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String value, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EnvVariable() when $default != null:
return $default(_that.name,_that.value,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String value, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _EnvVariable():
return $default(_that.name,_that.value,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String value, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _EnvVariable() when $default != null:
return $default(_that.name,_that.value,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _EnvVariable extends EnvVariable {
  const _EnvVariable({required this.name, required this.value, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  String name;
@override final  String value;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of EnvVariable
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EnvVariableCopyWith<_EnvVariable> get copyWith => __$EnvVariableCopyWithImpl<_EnvVariable>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _EnvVariable&&(identical(other.name, name) || other.name == name)&&(identical(other.value, value) || other.value == value)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,name,value,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'EnvVariable(name: $name, value: $value, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$EnvVariableCopyWith<$Res> implements $EnvVariableCopyWith<$Res> {
  factory _$EnvVariableCopyWith(_EnvVariable value, $Res Function(_EnvVariable) _then) = __$EnvVariableCopyWithImpl;
@override @useResult
$Res call({
 String name, String value,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class __$EnvVariableCopyWithImpl<$Res>
    implements _$EnvVariableCopyWith<$Res> {
  __$EnvVariableCopyWithImpl(this._self, this._then);

  final _EnvVariable _self;
  final $Res Function(_EnvVariable) _then;

/// Create a copy of EnvVariable
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? value = null,Object? meta = freezed,}) {
  return _then(_EnvVariable(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$HttpHeader {

 String get name; String get value;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of HttpHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HttpHeaderCopyWith<HttpHeader> get copyWith => _$HttpHeaderCopyWithImpl<HttpHeader>(this as HttpHeader, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HttpHeader&&(identical(other.name, name) || other.name == name)&&(identical(other.value, value) || other.value == value)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,name,value,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'HttpHeader(name: $name, value: $value, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $HttpHeaderCopyWith<$Res>  {
  factory $HttpHeaderCopyWith(HttpHeader value, $Res Function(HttpHeader) _then) = _$HttpHeaderCopyWithImpl;
@useResult
$Res call({
 String name, String value,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$HttpHeaderCopyWithImpl<$Res>
    implements $HttpHeaderCopyWith<$Res> {
  _$HttpHeaderCopyWithImpl(this._self, this._then);

  final HttpHeader _self;
  final $Res Function(HttpHeader) _then;

/// Create a copy of HttpHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? value = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

}


/// Adds pattern-matching-related methods to [HttpHeader].
extension HttpHeaderPatterns on HttpHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HttpHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HttpHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HttpHeader value)  $default,){
final _that = this;
switch (_that) {
case _HttpHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HttpHeader value)?  $default,){
final _that = this;
switch (_that) {
case _HttpHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String value, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HttpHeader() when $default != null:
return $default(_that.name,_that.value,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String value, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _HttpHeader():
return $default(_that.name,_that.value,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String value, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _HttpHeader() when $default != null:
return $default(_that.name,_that.value,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _HttpHeader extends HttpHeader {
  const _HttpHeader({required this.name, required this.value, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  String name;
@override final  String value;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of HttpHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HttpHeaderCopyWith<_HttpHeader> get copyWith => __$HttpHeaderCopyWithImpl<_HttpHeader>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _HttpHeader&&(identical(other.name, name) || other.name == name)&&(identical(other.value, value) || other.value == value)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,name,value,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'HttpHeader(name: $name, value: $value, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$HttpHeaderCopyWith<$Res> implements $HttpHeaderCopyWith<$Res> {
  factory _$HttpHeaderCopyWith(_HttpHeader value, $Res Function(_HttpHeader) _then) = __$HttpHeaderCopyWithImpl;
@override @useResult
$Res call({
 String name, String value,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class __$HttpHeaderCopyWithImpl<$Res>
    implements _$HttpHeaderCopyWith<$Res> {
  __$HttpHeaderCopyWithImpl(this._self, this._then);

  final _HttpHeader _self;
  final $Res Function(_HttpHeader) _then;

/// Create a copy of HttpHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? value = null,Object? meta = freezed,}) {
  return _then(_HttpHeader(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$McpServer {

 String get name;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpServerCopyWith<McpServer> get copyWith => _$McpServerCopyWithImpl<McpServer>(this as McpServer, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpServer&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,name,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'McpServer(name: $name, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $McpServerCopyWith<$Res>  {
  factory $McpServerCopyWith(McpServer value, $Res Function(McpServer) _then) = _$McpServerCopyWithImpl;
@useResult
$Res call({
 String name,@JsonKey(name: '_meta') Map<String, Object?>? meta
});




}
/// @nodoc
class _$McpServerCopyWithImpl<$Res>
    implements $McpServerCopyWith<$Res> {
  _$McpServerCopyWithImpl(this._self, this._then);

  final McpServer _self;
  final $Res Function(McpServer) _then;

/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}

}


/// Adds pattern-matching-related methods to [McpServer].
extension McpServerPatterns on McpServer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( McpServerStdio value)?  stdio,TResult Function( McpServerHttp value)?  http,TResult Function( McpServerSse value)?  sse,required TResult orElse(),}){
final _that = this;
switch (_that) {
case McpServerStdio() when stdio != null:
return stdio(_that);case McpServerHttp() when http != null:
return http(_that);case McpServerSse() when sse != null:
return sse(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( McpServerStdio value)  stdio,required TResult Function( McpServerHttp value)  http,required TResult Function( McpServerSse value)  sse,}){
final _that = this;
switch (_that) {
case McpServerStdio():
return stdio(_that);case McpServerHttp():
return http(_that);case McpServerSse():
return sse(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( McpServerStdio value)?  stdio,TResult? Function( McpServerHttp value)?  http,TResult? Function( McpServerSse value)?  sse,}){
final _that = this;
switch (_that) {
case McpServerStdio() when stdio != null:
return stdio(_that);case McpServerHttp() when http != null:
return http(_that);case McpServerSse() when sse != null:
return sse(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String name,  String command,  List<String> args,  List<EnvVariable> env, @JsonKey(name: '_meta')  JsonObject? meta)?  stdio,TResult Function( String name,  String url,  List<HttpHeader> headers, @JsonKey(name: '_meta')  JsonObject? meta)?  http,TResult Function( String name,  String url,  List<HttpHeader> headers, @JsonKey(name: '_meta')  JsonObject? meta)?  sse,required TResult orElse(),}) {final _that = this;
switch (_that) {
case McpServerStdio() when stdio != null:
return stdio(_that.name,_that.command,_that.args,_that.env,_that.meta);case McpServerHttp() when http != null:
return http(_that.name,_that.url,_that.headers,_that.meta);case McpServerSse() when sse != null:
return sse(_that.name,_that.url,_that.headers,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String name,  String command,  List<String> args,  List<EnvVariable> env, @JsonKey(name: '_meta')  JsonObject? meta)  stdio,required TResult Function( String name,  String url,  List<HttpHeader> headers, @JsonKey(name: '_meta')  JsonObject? meta)  http,required TResult Function( String name,  String url,  List<HttpHeader> headers, @JsonKey(name: '_meta')  JsonObject? meta)  sse,}) {final _that = this;
switch (_that) {
case McpServerStdio():
return stdio(_that.name,_that.command,_that.args,_that.env,_that.meta);case McpServerHttp():
return http(_that.name,_that.url,_that.headers,_that.meta);case McpServerSse():
return sse(_that.name,_that.url,_that.headers,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String name,  String command,  List<String> args,  List<EnvVariable> env, @JsonKey(name: '_meta')  JsonObject? meta)?  stdio,TResult? Function( String name,  String url,  List<HttpHeader> headers, @JsonKey(name: '_meta')  JsonObject? meta)?  http,TResult? Function( String name,  String url,  List<HttpHeader> headers, @JsonKey(name: '_meta')  JsonObject? meta)?  sse,}) {final _that = this;
switch (_that) {
case McpServerStdio() when stdio != null:
return stdio(_that.name,_that.command,_that.args,_that.env,_that.meta);case McpServerHttp() when http != null:
return http(_that.name,_that.url,_that.headers,_that.meta);case McpServerSse() when sse != null:
return sse(_that.name,_that.url,_that.headers,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class McpServerStdio extends McpServer {
  const McpServerStdio({required this.name, required this.command, final  List<String> args = const [], final  List<EnvVariable> env = const [], @JsonKey(name: '_meta') final  JsonObject? meta}): _args = args,_env = env,_meta = meta,super._();
  

@override final  String name;
 final  String command;
 final  List<String> _args;
@JsonKey() List<String> get args {
  if (_args is EqualUnmodifiableListView) return _args;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_args);
}

 final  List<EnvVariable> _env;
@JsonKey() List<EnvVariable> get env {
  if (_env is EqualUnmodifiableListView) return _env;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_env);
}

 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpServerStdioCopyWith<McpServerStdio> get copyWith => _$McpServerStdioCopyWithImpl<McpServerStdio>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpServerStdio&&(identical(other.name, name) || other.name == name)&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other._args, _args)&&const DeepCollectionEquality().equals(other._env, _env)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,name,command,const DeepCollectionEquality().hash(_args),const DeepCollectionEquality().hash(_env),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'McpServer.stdio(name: $name, command: $command, args: $args, env: $env, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $McpServerStdioCopyWith<$Res> implements $McpServerCopyWith<$Res> {
  factory $McpServerStdioCopyWith(McpServerStdio value, $Res Function(McpServerStdio) _then) = _$McpServerStdioCopyWithImpl;
@override @useResult
$Res call({
 String name, String command, List<String> args, List<EnvVariable> env,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$McpServerStdioCopyWithImpl<$Res>
    implements $McpServerStdioCopyWith<$Res> {
  _$McpServerStdioCopyWithImpl(this._self, this._then);

  final McpServerStdio _self;
  final $Res Function(McpServerStdio) _then;

/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? command = null,Object? args = null,Object? env = null,Object? meta = freezed,}) {
  return _then(McpServerStdio(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self._args : args // ignore: cast_nullable_to_non_nullable
as List<String>,env: null == env ? _self._env : env // ignore: cast_nullable_to_non_nullable
as List<EnvVariable>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc


class McpServerHttp extends McpServer {
  const McpServerHttp({required this.name, required this.url, final  List<HttpHeader> headers = const [], @JsonKey(name: '_meta') final  JsonObject? meta}): _headers = headers,_meta = meta,super._();
  

@override final  String name;
 final  String url;
 final  List<HttpHeader> _headers;
@JsonKey() List<HttpHeader> get headers {
  if (_headers is EqualUnmodifiableListView) return _headers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_headers);
}

 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpServerHttpCopyWith<McpServerHttp> get copyWith => _$McpServerHttpCopyWithImpl<McpServerHttp>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpServerHttp&&(identical(other.name, name) || other.name == name)&&(identical(other.url, url) || other.url == url)&&const DeepCollectionEquality().equals(other._headers, _headers)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,name,url,const DeepCollectionEquality().hash(_headers),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'McpServer.http(name: $name, url: $url, headers: $headers, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $McpServerHttpCopyWith<$Res> implements $McpServerCopyWith<$Res> {
  factory $McpServerHttpCopyWith(McpServerHttp value, $Res Function(McpServerHttp) _then) = _$McpServerHttpCopyWithImpl;
@override @useResult
$Res call({
 String name, String url, List<HttpHeader> headers,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$McpServerHttpCopyWithImpl<$Res>
    implements $McpServerHttpCopyWith<$Res> {
  _$McpServerHttpCopyWithImpl(this._self, this._then);

  final McpServerHttp _self;
  final $Res Function(McpServerHttp) _then;

/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? url = null,Object? headers = null,Object? meta = freezed,}) {
  return _then(McpServerHttp(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,headers: null == headers ? _self._headers : headers // ignore: cast_nullable_to_non_nullable
as List<HttpHeader>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc


class McpServerSse extends McpServer {
  const McpServerSse({required this.name, required this.url, final  List<HttpHeader> headers = const [], @JsonKey(name: '_meta') final  JsonObject? meta}): _headers = headers,_meta = meta,super._();
  

@override final  String name;
 final  String url;
 final  List<HttpHeader> _headers;
@JsonKey() List<HttpHeader> get headers {
  if (_headers is EqualUnmodifiableListView) return _headers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_headers);
}

 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpServerSseCopyWith<McpServerSse> get copyWith => _$McpServerSseCopyWithImpl<McpServerSse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpServerSse&&(identical(other.name, name) || other.name == name)&&(identical(other.url, url) || other.url == url)&&const DeepCollectionEquality().equals(other._headers, _headers)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,name,url,const DeepCollectionEquality().hash(_headers),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'McpServer.sse(name: $name, url: $url, headers: $headers, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $McpServerSseCopyWith<$Res> implements $McpServerCopyWith<$Res> {
  factory $McpServerSseCopyWith(McpServerSse value, $Res Function(McpServerSse) _then) = _$McpServerSseCopyWithImpl;
@override @useResult
$Res call({
 String name, String url, List<HttpHeader> headers,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$McpServerSseCopyWithImpl<$Res>
    implements $McpServerSseCopyWith<$Res> {
  _$McpServerSseCopyWithImpl(this._self, this._then);

  final McpServerSse _self;
  final $Res Function(McpServerSse) _then;

/// Create a copy of McpServer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? url = null,Object? headers = null,Object? meta = freezed,}) {
  return _then(McpServerSse(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,headers: null == headers ? _self._headers : headers // ignore: cast_nullable_to_non_nullable
as List<HttpHeader>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$SessionModeId {

 String get value;
/// Create a copy of SessionModeId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionModeIdCopyWith<SessionModeId> get copyWith => _$SessionModeIdCopyWithImpl<SessionModeId>(this as SessionModeId, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionModeId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'SessionModeId(value: $value)';
}


}

/// @nodoc
abstract mixin class $SessionModeIdCopyWith<$Res>  {
  factory $SessionModeIdCopyWith(SessionModeId value, $Res Function(SessionModeId) _then) = _$SessionModeIdCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$SessionModeIdCopyWithImpl<$Res>
    implements $SessionModeIdCopyWith<$Res> {
  _$SessionModeIdCopyWithImpl(this._self, this._then);

  final SessionModeId _self;
  final $Res Function(SessionModeId) _then;

/// Create a copy of SessionModeId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(_self.copyWith(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionModeId].
extension SessionModeIdPatterns on SessionModeId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionModeId value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionModeId() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionModeId value)  $default,){
final _that = this;
switch (_that) {
case _SessionModeId():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionModeId value)?  $default,){
final _that = this;
switch (_that) {
case _SessionModeId() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionModeId() when $default != null:
return $default(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String value)  $default,) {final _that = this;
switch (_that) {
case _SessionModeId():
return $default(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String value)?  $default,) {final _that = this;
switch (_that) {
case _SessionModeId() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _SessionModeId extends SessionModeId {
  const _SessionModeId(this.value): super._();
  

@override final  String value;

/// Create a copy of SessionModeId
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionModeIdCopyWith<_SessionModeId> get copyWith => __$SessionModeIdCopyWithImpl<_SessionModeId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionModeId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'SessionModeId(value: $value)';
}


}

/// @nodoc
abstract mixin class _$SessionModeIdCopyWith<$Res> implements $SessionModeIdCopyWith<$Res> {
  factory _$SessionModeIdCopyWith(_SessionModeId value, $Res Function(_SessionModeId) _then) = __$SessionModeIdCopyWithImpl;
@override @useResult
$Res call({
 String value
});




}
/// @nodoc
class __$SessionModeIdCopyWithImpl<$Res>
    implements _$SessionModeIdCopyWith<$Res> {
  __$SessionModeIdCopyWithImpl(this._self, this._then);

  final _SessionModeId _self;
  final $Res Function(_SessionModeId) _then;

/// Create a copy of SessionModeId
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_SessionModeId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$SessionMode {

 SessionModeId get id; String get name; String? get description;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of SessionMode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionModeCopyWith<SessionMode> get copyWith => _$SessionModeCopyWithImpl<SessionMode>(this as SessionMode, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionMode&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,description,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'SessionMode(id: $id, name: $name, description: $description, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $SessionModeCopyWith<$Res>  {
  factory $SessionModeCopyWith(SessionMode value, $Res Function(SessionMode) _then) = _$SessionModeCopyWithImpl;
@useResult
$Res call({
 SessionModeId id, String name, String? description,@JsonKey(name: '_meta') JsonObject? meta
});


$SessionModeIdCopyWith<$Res> get id;

}
/// @nodoc
class _$SessionModeCopyWithImpl<$Res>
    implements $SessionModeCopyWith<$Res> {
  _$SessionModeCopyWithImpl(this._self, this._then);

  final SessionMode _self;
  final $Res Function(SessionMode) _then;

/// Create a copy of SessionMode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as SessionModeId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of SessionMode
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionModeIdCopyWith<$Res> get id {
  
  return $SessionModeIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionMode].
extension SessionModePatterns on SessionMode {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionMode value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionMode() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionMode value)  $default,){
final _that = this;
switch (_that) {
case _SessionMode():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionMode value)?  $default,){
final _that = this;
switch (_that) {
case _SessionMode() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionModeId id,  String name,  String? description, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionMode() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionModeId id,  String name,  String? description, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _SessionMode():
return $default(_that.id,_that.name,_that.description,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionModeId id,  String name,  String? description, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _SessionMode() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _SessionMode extends SessionMode {
  const _SessionMode({required this.id, required this.name, this.description, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  SessionModeId id;
@override final  String name;
@override final  String? description;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of SessionMode
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionModeCopyWith<_SessionMode> get copyWith => __$SessionModeCopyWithImpl<_SessionMode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionMode&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,description,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'SessionMode(id: $id, name: $name, description: $description, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$SessionModeCopyWith<$Res> implements $SessionModeCopyWith<$Res> {
  factory _$SessionModeCopyWith(_SessionMode value, $Res Function(_SessionMode) _then) = __$SessionModeCopyWithImpl;
@override @useResult
$Res call({
 SessionModeId id, String name, String? description,@JsonKey(name: '_meta') JsonObject? meta
});


@override $SessionModeIdCopyWith<$Res> get id;

}
/// @nodoc
class __$SessionModeCopyWithImpl<$Res>
    implements _$SessionModeCopyWith<$Res> {
  __$SessionModeCopyWithImpl(this._self, this._then);

  final _SessionMode _self;
  final $Res Function(_SessionMode) _then;

/// Create a copy of SessionMode
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? meta = freezed,}) {
  return _then(_SessionMode(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as SessionModeId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of SessionMode
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionModeIdCopyWith<$Res> get id {
  
  return $SessionModeIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}
}

/// @nodoc
mixin _$SessionModeState {

 List<SessionMode> get availableModes; SessionModeId get currentModeId;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of SessionModeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionModeStateCopyWith<SessionModeState> get copyWith => _$SessionModeStateCopyWithImpl<SessionModeState>(this as SessionModeState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionModeState&&const DeepCollectionEquality().equals(other.availableModes, availableModes)&&(identical(other.currentModeId, currentModeId) || other.currentModeId == currentModeId)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(availableModes),currentModeId,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'SessionModeState(availableModes: $availableModes, currentModeId: $currentModeId, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $SessionModeStateCopyWith<$Res>  {
  factory $SessionModeStateCopyWith(SessionModeState value, $Res Function(SessionModeState) _then) = _$SessionModeStateCopyWithImpl;
@useResult
$Res call({
 List<SessionMode> availableModes, SessionModeId currentModeId,@JsonKey(name: '_meta') JsonObject? meta
});


$SessionModeIdCopyWith<$Res> get currentModeId;

}
/// @nodoc
class _$SessionModeStateCopyWithImpl<$Res>
    implements $SessionModeStateCopyWith<$Res> {
  _$SessionModeStateCopyWithImpl(this._self, this._then);

  final SessionModeState _self;
  final $Res Function(SessionModeState) _then;

/// Create a copy of SessionModeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? availableModes = null,Object? currentModeId = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
availableModes: null == availableModes ? _self.availableModes : availableModes // ignore: cast_nullable_to_non_nullable
as List<SessionMode>,currentModeId: null == currentModeId ? _self.currentModeId : currentModeId // ignore: cast_nullable_to_non_nullable
as SessionModeId,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of SessionModeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionModeIdCopyWith<$Res> get currentModeId {
  
  return $SessionModeIdCopyWith<$Res>(_self.currentModeId, (value) {
    return _then(_self.copyWith(currentModeId: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionModeState].
extension SessionModeStatePatterns on SessionModeState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionModeState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionModeState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionModeState value)  $default,){
final _that = this;
switch (_that) {
case _SessionModeState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionModeState value)?  $default,){
final _that = this;
switch (_that) {
case _SessionModeState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<SessionMode> availableModes,  SessionModeId currentModeId, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionModeState() when $default != null:
return $default(_that.availableModes,_that.currentModeId,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<SessionMode> availableModes,  SessionModeId currentModeId, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _SessionModeState():
return $default(_that.availableModes,_that.currentModeId,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<SessionMode> availableModes,  SessionModeId currentModeId, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _SessionModeState() when $default != null:
return $default(_that.availableModes,_that.currentModeId,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _SessionModeState extends SessionModeState {
  const _SessionModeState({required final  List<SessionMode> availableModes, required this.currentModeId, @JsonKey(name: '_meta') final  JsonObject? meta}): _availableModes = availableModes,_meta = meta,super._();
  

 final  List<SessionMode> _availableModes;
@override List<SessionMode> get availableModes {
  if (_availableModes is EqualUnmodifiableListView) return _availableModes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_availableModes);
}

@override final  SessionModeId currentModeId;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of SessionModeState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionModeStateCopyWith<_SessionModeState> get copyWith => __$SessionModeStateCopyWithImpl<_SessionModeState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionModeState&&const DeepCollectionEquality().equals(other._availableModes, _availableModes)&&(identical(other.currentModeId, currentModeId) || other.currentModeId == currentModeId)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_availableModes),currentModeId,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'SessionModeState(availableModes: $availableModes, currentModeId: $currentModeId, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$SessionModeStateCopyWith<$Res> implements $SessionModeStateCopyWith<$Res> {
  factory _$SessionModeStateCopyWith(_SessionModeState value, $Res Function(_SessionModeState) _then) = __$SessionModeStateCopyWithImpl;
@override @useResult
$Res call({
 List<SessionMode> availableModes, SessionModeId currentModeId,@JsonKey(name: '_meta') JsonObject? meta
});


@override $SessionModeIdCopyWith<$Res> get currentModeId;

}
/// @nodoc
class __$SessionModeStateCopyWithImpl<$Res>
    implements _$SessionModeStateCopyWith<$Res> {
  __$SessionModeStateCopyWithImpl(this._self, this._then);

  final _SessionModeState _self;
  final $Res Function(_SessionModeState) _then;

/// Create a copy of SessionModeState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? availableModes = null,Object? currentModeId = null,Object? meta = freezed,}) {
  return _then(_SessionModeState(
availableModes: null == availableModes ? _self._availableModes : availableModes // ignore: cast_nullable_to_non_nullable
as List<SessionMode>,currentModeId: null == currentModeId ? _self.currentModeId : currentModeId // ignore: cast_nullable_to_non_nullable
as SessionModeId,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of SessionModeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionModeIdCopyWith<$Res> get currentModeId {
  
  return $SessionModeIdCopyWith<$Res>(_self.currentModeId, (value) {
    return _then(_self.copyWith(currentModeId: value));
  });
}
}

/// @nodoc
mixin _$SessionConfigId {

 String get value;
/// Create a copy of SessionConfigId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionConfigIdCopyWith<SessionConfigId> get copyWith => _$SessionConfigIdCopyWithImpl<SessionConfigId>(this as SessionConfigId, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionConfigId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'SessionConfigId(value: $value)';
}


}

/// @nodoc
abstract mixin class $SessionConfigIdCopyWith<$Res>  {
  factory $SessionConfigIdCopyWith(SessionConfigId value, $Res Function(SessionConfigId) _then) = _$SessionConfigIdCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$SessionConfigIdCopyWithImpl<$Res>
    implements $SessionConfigIdCopyWith<$Res> {
  _$SessionConfigIdCopyWithImpl(this._self, this._then);

  final SessionConfigId _self;
  final $Res Function(SessionConfigId) _then;

/// Create a copy of SessionConfigId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(_self.copyWith(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionConfigId].
extension SessionConfigIdPatterns on SessionConfigId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionConfigId value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionConfigId() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionConfigId value)  $default,){
final _that = this;
switch (_that) {
case _SessionConfigId():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionConfigId value)?  $default,){
final _that = this;
switch (_that) {
case _SessionConfigId() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionConfigId() when $default != null:
return $default(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String value)  $default,) {final _that = this;
switch (_that) {
case _SessionConfigId():
return $default(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String value)?  $default,) {final _that = this;
switch (_that) {
case _SessionConfigId() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _SessionConfigId extends SessionConfigId {
  const _SessionConfigId(this.value): super._();
  

@override final  String value;

/// Create a copy of SessionConfigId
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionConfigIdCopyWith<_SessionConfigId> get copyWith => __$SessionConfigIdCopyWithImpl<_SessionConfigId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionConfigId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'SessionConfigId(value: $value)';
}


}

/// @nodoc
abstract mixin class _$SessionConfigIdCopyWith<$Res> implements $SessionConfigIdCopyWith<$Res> {
  factory _$SessionConfigIdCopyWith(_SessionConfigId value, $Res Function(_SessionConfigId) _then) = __$SessionConfigIdCopyWithImpl;
@override @useResult
$Res call({
 String value
});




}
/// @nodoc
class __$SessionConfigIdCopyWithImpl<$Res>
    implements _$SessionConfigIdCopyWith<$Res> {
  __$SessionConfigIdCopyWithImpl(this._self, this._then);

  final _SessionConfigId _self;
  final $Res Function(_SessionConfigId) _then;

/// Create a copy of SessionConfigId
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_SessionConfigId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$SessionConfigValueId {

 String get value;
/// Create a copy of SessionConfigValueId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionConfigValueIdCopyWith<SessionConfigValueId> get copyWith => _$SessionConfigValueIdCopyWithImpl<SessionConfigValueId>(this as SessionConfigValueId, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionConfigValueId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'SessionConfigValueId(value: $value)';
}


}

/// @nodoc
abstract mixin class $SessionConfigValueIdCopyWith<$Res>  {
  factory $SessionConfigValueIdCopyWith(SessionConfigValueId value, $Res Function(SessionConfigValueId) _then) = _$SessionConfigValueIdCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$SessionConfigValueIdCopyWithImpl<$Res>
    implements $SessionConfigValueIdCopyWith<$Res> {
  _$SessionConfigValueIdCopyWithImpl(this._self, this._then);

  final SessionConfigValueId _self;
  final $Res Function(SessionConfigValueId) _then;

/// Create a copy of SessionConfigValueId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(_self.copyWith(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionConfigValueId].
extension SessionConfigValueIdPatterns on SessionConfigValueId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionConfigValueId value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionConfigValueId() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionConfigValueId value)  $default,){
final _that = this;
switch (_that) {
case _SessionConfigValueId():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionConfigValueId value)?  $default,){
final _that = this;
switch (_that) {
case _SessionConfigValueId() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionConfigValueId() when $default != null:
return $default(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String value)  $default,) {final _that = this;
switch (_that) {
case _SessionConfigValueId():
return $default(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String value)?  $default,) {final _that = this;
switch (_that) {
case _SessionConfigValueId() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _SessionConfigValueId extends SessionConfigValueId {
  const _SessionConfigValueId(this.value): super._();
  

@override final  String value;

/// Create a copy of SessionConfigValueId
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionConfigValueIdCopyWith<_SessionConfigValueId> get copyWith => __$SessionConfigValueIdCopyWithImpl<_SessionConfigValueId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionConfigValueId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'SessionConfigValueId(value: $value)';
}


}

/// @nodoc
abstract mixin class _$SessionConfigValueIdCopyWith<$Res> implements $SessionConfigValueIdCopyWith<$Res> {
  factory _$SessionConfigValueIdCopyWith(_SessionConfigValueId value, $Res Function(_SessionConfigValueId) _then) = __$SessionConfigValueIdCopyWithImpl;
@override @useResult
$Res call({
 String value
});




}
/// @nodoc
class __$SessionConfigValueIdCopyWithImpl<$Res>
    implements _$SessionConfigValueIdCopyWith<$Res> {
  __$SessionConfigValueIdCopyWithImpl(this._self, this._then);

  final _SessionConfigValueId _self;
  final $Res Function(_SessionConfigValueId) _then;

/// Create a copy of SessionConfigValueId
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_SessionConfigValueId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$SessionConfigSelectOption {

 SessionConfigValueId get value; String get name; String? get description;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of SessionConfigSelectOption
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionConfigSelectOptionCopyWith<SessionConfigSelectOption> get copyWith => _$SessionConfigSelectOptionCopyWithImpl<SessionConfigSelectOption>(this as SessionConfigSelectOption, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionConfigSelectOption&&(identical(other.value, value) || other.value == value)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,value,name,description,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'SessionConfigSelectOption(value: $value, name: $name, description: $description, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $SessionConfigSelectOptionCopyWith<$Res>  {
  factory $SessionConfigSelectOptionCopyWith(SessionConfigSelectOption value, $Res Function(SessionConfigSelectOption) _then) = _$SessionConfigSelectOptionCopyWithImpl;
@useResult
$Res call({
 SessionConfigValueId value, String name, String? description,@JsonKey(name: '_meta') JsonObject? meta
});


$SessionConfigValueIdCopyWith<$Res> get value;

}
/// @nodoc
class _$SessionConfigSelectOptionCopyWithImpl<$Res>
    implements $SessionConfigSelectOptionCopyWith<$Res> {
  _$SessionConfigSelectOptionCopyWithImpl(this._self, this._then);

  final SessionConfigSelectOption _self;
  final $Res Function(SessionConfigSelectOption) _then;

/// Create a copy of SessionConfigSelectOption
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,Object? name = null,Object? description = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SessionConfigValueId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of SessionConfigSelectOption
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionConfigValueIdCopyWith<$Res> get value {
  
  return $SessionConfigValueIdCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionConfigSelectOption].
extension SessionConfigSelectOptionPatterns on SessionConfigSelectOption {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionConfigSelectOption value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionConfigSelectOption() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionConfigSelectOption value)  $default,){
final _that = this;
switch (_that) {
case _SessionConfigSelectOption():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionConfigSelectOption value)?  $default,){
final _that = this;
switch (_that) {
case _SessionConfigSelectOption() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionConfigValueId value,  String name,  String? description, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionConfigSelectOption() when $default != null:
return $default(_that.value,_that.name,_that.description,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionConfigValueId value,  String name,  String? description, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _SessionConfigSelectOption():
return $default(_that.value,_that.name,_that.description,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionConfigValueId value,  String name,  String? description, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _SessionConfigSelectOption() when $default != null:
return $default(_that.value,_that.name,_that.description,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _SessionConfigSelectOption extends SessionConfigSelectOption {
  const _SessionConfigSelectOption({required this.value, required this.name, this.description, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  SessionConfigValueId value;
@override final  String name;
@override final  String? description;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of SessionConfigSelectOption
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionConfigSelectOptionCopyWith<_SessionConfigSelectOption> get copyWith => __$SessionConfigSelectOptionCopyWithImpl<_SessionConfigSelectOption>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionConfigSelectOption&&(identical(other.value, value) || other.value == value)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,value,name,description,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'SessionConfigSelectOption(value: $value, name: $name, description: $description, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$SessionConfigSelectOptionCopyWith<$Res> implements $SessionConfigSelectOptionCopyWith<$Res> {
  factory _$SessionConfigSelectOptionCopyWith(_SessionConfigSelectOption value, $Res Function(_SessionConfigSelectOption) _then) = __$SessionConfigSelectOptionCopyWithImpl;
@override @useResult
$Res call({
 SessionConfigValueId value, String name, String? description,@JsonKey(name: '_meta') JsonObject? meta
});


@override $SessionConfigValueIdCopyWith<$Res> get value;

}
/// @nodoc
class __$SessionConfigSelectOptionCopyWithImpl<$Res>
    implements _$SessionConfigSelectOptionCopyWith<$Res> {
  __$SessionConfigSelectOptionCopyWithImpl(this._self, this._then);

  final _SessionConfigSelectOption _self;
  final $Res Function(_SessionConfigSelectOption) _then;

/// Create a copy of SessionConfigSelectOption
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,Object? name = null,Object? description = freezed,Object? meta = freezed,}) {
  return _then(_SessionConfigSelectOption(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SessionConfigValueId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of SessionConfigSelectOption
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionConfigValueIdCopyWith<$Res> get value {
  
  return $SessionConfigValueIdCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$SessionConfigOption {

 SessionConfigId get id; String get name; SessionConfigValueId get currentValue; List<SessionConfigSelectOption> get options; String? get category; String? get description;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of SessionConfigOption
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionConfigOptionCopyWith<SessionConfigOption> get copyWith => _$SessionConfigOptionCopyWithImpl<SessionConfigOption>(this as SessionConfigOption, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionConfigOption&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.currentValue, currentValue) || other.currentValue == currentValue)&&const DeepCollectionEquality().equals(other.options, options)&&(identical(other.category, category) || other.category == category)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,currentValue,const DeepCollectionEquality().hash(options),category,description,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'SessionConfigOption(id: $id, name: $name, currentValue: $currentValue, options: $options, category: $category, description: $description, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $SessionConfigOptionCopyWith<$Res>  {
  factory $SessionConfigOptionCopyWith(SessionConfigOption value, $Res Function(SessionConfigOption) _then) = _$SessionConfigOptionCopyWithImpl;
@useResult
$Res call({
 SessionConfigId id, String name, SessionConfigValueId currentValue, List<SessionConfigSelectOption> options, String? category, String? description,@JsonKey(name: '_meta') JsonObject? meta
});


$SessionConfigIdCopyWith<$Res> get id;$SessionConfigValueIdCopyWith<$Res> get currentValue;

}
/// @nodoc
class _$SessionConfigOptionCopyWithImpl<$Res>
    implements $SessionConfigOptionCopyWith<$Res> {
  _$SessionConfigOptionCopyWithImpl(this._self, this._then);

  final SessionConfigOption _self;
  final $Res Function(SessionConfigOption) _then;

/// Create a copy of SessionConfigOption
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? currentValue = null,Object? options = null,Object? category = freezed,Object? description = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as SessionConfigId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,currentValue: null == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as SessionConfigValueId,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<SessionConfigSelectOption>,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of SessionConfigOption
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionConfigIdCopyWith<$Res> get id {
  
  return $SessionConfigIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of SessionConfigOption
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionConfigValueIdCopyWith<$Res> get currentValue {
  
  return $SessionConfigValueIdCopyWith<$Res>(_self.currentValue, (value) {
    return _then(_self.copyWith(currentValue: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionConfigOption].
extension SessionConfigOptionPatterns on SessionConfigOption {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SessionConfigSelect value)?  select,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SessionConfigSelect() when select != null:
return select(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SessionConfigSelect value)  select,}){
final _that = this;
switch (_that) {
case SessionConfigSelect():
return select(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SessionConfigSelect value)?  select,}){
final _that = this;
switch (_that) {
case SessionConfigSelect() when select != null:
return select(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( SessionConfigId id,  String name,  SessionConfigValueId currentValue,  List<SessionConfigSelectOption> options,  String? category,  String? description, @JsonKey(name: '_meta')  JsonObject? meta)?  select,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SessionConfigSelect() when select != null:
return select(_that.id,_that.name,_that.currentValue,_that.options,_that.category,_that.description,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( SessionConfigId id,  String name,  SessionConfigValueId currentValue,  List<SessionConfigSelectOption> options,  String? category,  String? description, @JsonKey(name: '_meta')  JsonObject? meta)  select,}) {final _that = this;
switch (_that) {
case SessionConfigSelect():
return select(_that.id,_that.name,_that.currentValue,_that.options,_that.category,_that.description,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( SessionConfigId id,  String name,  SessionConfigValueId currentValue,  List<SessionConfigSelectOption> options,  String? category,  String? description, @JsonKey(name: '_meta')  JsonObject? meta)?  select,}) {final _that = this;
switch (_that) {
case SessionConfigSelect() when select != null:
return select(_that.id,_that.name,_that.currentValue,_that.options,_that.category,_that.description,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class SessionConfigSelect extends SessionConfigOption {
  const SessionConfigSelect({required this.id, required this.name, required this.currentValue, required final  List<SessionConfigSelectOption> options, this.category, this.description, @JsonKey(name: '_meta') final  JsonObject? meta}): _options = options,_meta = meta,super._();
  

@override final  SessionConfigId id;
@override final  String name;
@override final  SessionConfigValueId currentValue;
 final  List<SessionConfigSelectOption> _options;
@override List<SessionConfigSelectOption> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}

@override final  String? category;
@override final  String? description;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of SessionConfigOption
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionConfigSelectCopyWith<SessionConfigSelect> get copyWith => _$SessionConfigSelectCopyWithImpl<SessionConfigSelect>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionConfigSelect&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.currentValue, currentValue) || other.currentValue == currentValue)&&const DeepCollectionEquality().equals(other._options, _options)&&(identical(other.category, category) || other.category == category)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,currentValue,const DeepCollectionEquality().hash(_options),category,description,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'SessionConfigOption.select(id: $id, name: $name, currentValue: $currentValue, options: $options, category: $category, description: $description, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $SessionConfigSelectCopyWith<$Res> implements $SessionConfigOptionCopyWith<$Res> {
  factory $SessionConfigSelectCopyWith(SessionConfigSelect value, $Res Function(SessionConfigSelect) _then) = _$SessionConfigSelectCopyWithImpl;
@override @useResult
$Res call({
 SessionConfigId id, String name, SessionConfigValueId currentValue, List<SessionConfigSelectOption> options, String? category, String? description,@JsonKey(name: '_meta') JsonObject? meta
});


@override $SessionConfigIdCopyWith<$Res> get id;@override $SessionConfigValueIdCopyWith<$Res> get currentValue;

}
/// @nodoc
class _$SessionConfigSelectCopyWithImpl<$Res>
    implements $SessionConfigSelectCopyWith<$Res> {
  _$SessionConfigSelectCopyWithImpl(this._self, this._then);

  final SessionConfigSelect _self;
  final $Res Function(SessionConfigSelect) _then;

/// Create a copy of SessionConfigOption
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? currentValue = null,Object? options = null,Object? category = freezed,Object? description = freezed,Object? meta = freezed,}) {
  return _then(SessionConfigSelect(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as SessionConfigId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,currentValue: null == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as SessionConfigValueId,options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<SessionConfigSelectOption>,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of SessionConfigOption
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionConfigIdCopyWith<$Res> get id {
  
  return $SessionConfigIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of SessionConfigOption
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionConfigValueIdCopyWith<$Res> get currentValue {
  
  return $SessionConfigValueIdCopyWith<$Res>(_self.currentValue, (value) {
    return _then(_self.copyWith(currentValue: value));
  });
}
}

/// @nodoc
mixin _$NewSessionRequest {

 String get cwd; List<McpServer> get mcpServers;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of NewSessionRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NewSessionRequestCopyWith<NewSessionRequest> get copyWith => _$NewSessionRequestCopyWithImpl<NewSessionRequest>(this as NewSessionRequest, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NewSessionRequest&&(identical(other.cwd, cwd) || other.cwd == cwd)&&const DeepCollectionEquality().equals(other.mcpServers, mcpServers)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,cwd,const DeepCollectionEquality().hash(mcpServers),const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'NewSessionRequest(cwd: $cwd, mcpServers: $mcpServers, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $NewSessionRequestCopyWith<$Res>  {
  factory $NewSessionRequestCopyWith(NewSessionRequest value, $Res Function(NewSessionRequest) _then) = _$NewSessionRequestCopyWithImpl;
@useResult
$Res call({
 String cwd, List<McpServer> mcpServers,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$NewSessionRequestCopyWithImpl<$Res>
    implements $NewSessionRequestCopyWith<$Res> {
  _$NewSessionRequestCopyWithImpl(this._self, this._then);

  final NewSessionRequest _self;
  final $Res Function(NewSessionRequest) _then;

/// Create a copy of NewSessionRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? cwd = null,Object? mcpServers = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,mcpServers: null == mcpServers ? _self.mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServer>,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

}


/// Adds pattern-matching-related methods to [NewSessionRequest].
extension NewSessionRequestPatterns on NewSessionRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NewSessionRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NewSessionRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NewSessionRequest value)  $default,){
final _that = this;
switch (_that) {
case _NewSessionRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NewSessionRequest value)?  $default,){
final _that = this;
switch (_that) {
case _NewSessionRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String cwd,  List<McpServer> mcpServers, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NewSessionRequest() when $default != null:
return $default(_that.cwd,_that.mcpServers,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String cwd,  List<McpServer> mcpServers, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _NewSessionRequest():
return $default(_that.cwd,_that.mcpServers,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String cwd,  List<McpServer> mcpServers, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _NewSessionRequest() when $default != null:
return $default(_that.cwd,_that.mcpServers,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _NewSessionRequest extends NewSessionRequest {
  const _NewSessionRequest({required this.cwd, required final  List<McpServer> mcpServers, @JsonKey(name: '_meta') final  JsonObject? meta}): _mcpServers = mcpServers,_meta = meta,super._();
  

@override final  String cwd;
 final  List<McpServer> _mcpServers;
@override List<McpServer> get mcpServers {
  if (_mcpServers is EqualUnmodifiableListView) return _mcpServers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_mcpServers);
}

 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of NewSessionRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NewSessionRequestCopyWith<_NewSessionRequest> get copyWith => __$NewSessionRequestCopyWithImpl<_NewSessionRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NewSessionRequest&&(identical(other.cwd, cwd) || other.cwd == cwd)&&const DeepCollectionEquality().equals(other._mcpServers, _mcpServers)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,cwd,const DeepCollectionEquality().hash(_mcpServers),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'NewSessionRequest(cwd: $cwd, mcpServers: $mcpServers, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$NewSessionRequestCopyWith<$Res> implements $NewSessionRequestCopyWith<$Res> {
  factory _$NewSessionRequestCopyWith(_NewSessionRequest value, $Res Function(_NewSessionRequest) _then) = __$NewSessionRequestCopyWithImpl;
@override @useResult
$Res call({
 String cwd, List<McpServer> mcpServers,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class __$NewSessionRequestCopyWithImpl<$Res>
    implements _$NewSessionRequestCopyWith<$Res> {
  __$NewSessionRequestCopyWithImpl(this._self, this._then);

  final _NewSessionRequest _self;
  final $Res Function(_NewSessionRequest) _then;

/// Create a copy of NewSessionRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? cwd = null,Object? mcpServers = null,Object? meta = freezed,}) {
  return _then(_NewSessionRequest(
cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,mcpServers: null == mcpServers ? _self._mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServer>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$NewSessionResponse {

 SessionId get sessionId; SessionModeState? get modes; List<SessionConfigOption>? get configOptions;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of NewSessionResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NewSessionResponseCopyWith<NewSessionResponse> get copyWith => _$NewSessionResponseCopyWithImpl<NewSessionResponse>(this as NewSessionResponse, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NewSessionResponse&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.modes, modes) || other.modes == modes)&&const DeepCollectionEquality().equals(other.configOptions, configOptions)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,modes,const DeepCollectionEquality().hash(configOptions),const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'NewSessionResponse(sessionId: $sessionId, modes: $modes, configOptions: $configOptions, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $NewSessionResponseCopyWith<$Res>  {
  factory $NewSessionResponseCopyWith(NewSessionResponse value, $Res Function(NewSessionResponse) _then) = _$NewSessionResponseCopyWithImpl;
@useResult
$Res call({
 SessionId sessionId, SessionModeState? modes, List<SessionConfigOption>? configOptions,@JsonKey(name: '_meta') JsonObject? meta
});


$SessionIdCopyWith<$Res> get sessionId;$SessionModeStateCopyWith<$Res>? get modes;

}
/// @nodoc
class _$NewSessionResponseCopyWithImpl<$Res>
    implements $NewSessionResponseCopyWith<$Res> {
  _$NewSessionResponseCopyWithImpl(this._self, this._then);

  final NewSessionResponse _self;
  final $Res Function(NewSessionResponse) _then;

/// Create a copy of NewSessionResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? modes = freezed,Object? configOptions = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,modes: freezed == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as SessionModeState?,configOptions: freezed == configOptions ? _self.configOptions : configOptions // ignore: cast_nullable_to_non_nullable
as List<SessionConfigOption>?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of NewSessionResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}/// Create a copy of NewSessionResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionModeStateCopyWith<$Res>? get modes {
    if (_self.modes == null) {
    return null;
  }

  return $SessionModeStateCopyWith<$Res>(_self.modes!, (value) {
    return _then(_self.copyWith(modes: value));
  });
}
}


/// Adds pattern-matching-related methods to [NewSessionResponse].
extension NewSessionResponsePatterns on NewSessionResponse {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NewSessionResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NewSessionResponse() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NewSessionResponse value)  $default,){
final _that = this;
switch (_that) {
case _NewSessionResponse():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NewSessionResponse value)?  $default,){
final _that = this;
switch (_that) {
case _NewSessionResponse() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionId sessionId,  SessionModeState? modes,  List<SessionConfigOption>? configOptions, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NewSessionResponse() when $default != null:
return $default(_that.sessionId,_that.modes,_that.configOptions,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionId sessionId,  SessionModeState? modes,  List<SessionConfigOption>? configOptions, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _NewSessionResponse():
return $default(_that.sessionId,_that.modes,_that.configOptions,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionId sessionId,  SessionModeState? modes,  List<SessionConfigOption>? configOptions, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _NewSessionResponse() when $default != null:
return $default(_that.sessionId,_that.modes,_that.configOptions,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _NewSessionResponse extends NewSessionResponse {
  const _NewSessionResponse({required this.sessionId, this.modes, final  List<SessionConfigOption>? configOptions, @JsonKey(name: '_meta') final  JsonObject? meta}): _configOptions = configOptions,_meta = meta,super._();
  

@override final  SessionId sessionId;
@override final  SessionModeState? modes;
 final  List<SessionConfigOption>? _configOptions;
@override List<SessionConfigOption>? get configOptions {
  final value = _configOptions;
  if (value == null) return null;
  if (_configOptions is EqualUnmodifiableListView) return _configOptions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of NewSessionResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NewSessionResponseCopyWith<_NewSessionResponse> get copyWith => __$NewSessionResponseCopyWithImpl<_NewSessionResponse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NewSessionResponse&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.modes, modes) || other.modes == modes)&&const DeepCollectionEquality().equals(other._configOptions, _configOptions)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,modes,const DeepCollectionEquality().hash(_configOptions),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'NewSessionResponse(sessionId: $sessionId, modes: $modes, configOptions: $configOptions, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$NewSessionResponseCopyWith<$Res> implements $NewSessionResponseCopyWith<$Res> {
  factory _$NewSessionResponseCopyWith(_NewSessionResponse value, $Res Function(_NewSessionResponse) _then) = __$NewSessionResponseCopyWithImpl;
@override @useResult
$Res call({
 SessionId sessionId, SessionModeState? modes, List<SessionConfigOption>? configOptions,@JsonKey(name: '_meta') JsonObject? meta
});


@override $SessionIdCopyWith<$Res> get sessionId;@override $SessionModeStateCopyWith<$Res>? get modes;

}
/// @nodoc
class __$NewSessionResponseCopyWithImpl<$Res>
    implements _$NewSessionResponseCopyWith<$Res> {
  __$NewSessionResponseCopyWithImpl(this._self, this._then);

  final _NewSessionResponse _self;
  final $Res Function(_NewSessionResponse) _then;

/// Create a copy of NewSessionResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? modes = freezed,Object? configOptions = freezed,Object? meta = freezed,}) {
  return _then(_NewSessionResponse(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,modes: freezed == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as SessionModeState?,configOptions: freezed == configOptions ? _self._configOptions : configOptions // ignore: cast_nullable_to_non_nullable
as List<SessionConfigOption>?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of NewSessionResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}/// Create a copy of NewSessionResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionModeStateCopyWith<$Res>? get modes {
    if (_self.modes == null) {
    return null;
  }

  return $SessionModeStateCopyWith<$Res>(_self.modes!, (value) {
    return _then(_self.copyWith(modes: value));
  });
}
}

/// @nodoc
mixin _$LoadSessionRequest {

 SessionId get sessionId; String get cwd; List<McpServer> get mcpServers;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of LoadSessionRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoadSessionRequestCopyWith<LoadSessionRequest> get copyWith => _$LoadSessionRequestCopyWithImpl<LoadSessionRequest>(this as LoadSessionRequest, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LoadSessionRequest&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.cwd, cwd) || other.cwd == cwd)&&const DeepCollectionEquality().equals(other.mcpServers, mcpServers)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,cwd,const DeepCollectionEquality().hash(mcpServers),const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'LoadSessionRequest(sessionId: $sessionId, cwd: $cwd, mcpServers: $mcpServers, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $LoadSessionRequestCopyWith<$Res>  {
  factory $LoadSessionRequestCopyWith(LoadSessionRequest value, $Res Function(LoadSessionRequest) _then) = _$LoadSessionRequestCopyWithImpl;
@useResult
$Res call({
 SessionId sessionId, String cwd, List<McpServer> mcpServers,@JsonKey(name: '_meta') JsonObject? meta
});


$SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class _$LoadSessionRequestCopyWithImpl<$Res>
    implements $LoadSessionRequestCopyWith<$Res> {
  _$LoadSessionRequestCopyWithImpl(this._self, this._then);

  final LoadSessionRequest _self;
  final $Res Function(LoadSessionRequest) _then;

/// Create a copy of LoadSessionRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? cwd = null,Object? mcpServers = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,mcpServers: null == mcpServers ? _self.mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServer>,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of LoadSessionRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}
}


/// Adds pattern-matching-related methods to [LoadSessionRequest].
extension LoadSessionRequestPatterns on LoadSessionRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LoadSessionRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LoadSessionRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LoadSessionRequest value)  $default,){
final _that = this;
switch (_that) {
case _LoadSessionRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LoadSessionRequest value)?  $default,){
final _that = this;
switch (_that) {
case _LoadSessionRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionId sessionId,  String cwd,  List<McpServer> mcpServers, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LoadSessionRequest() when $default != null:
return $default(_that.sessionId,_that.cwd,_that.mcpServers,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionId sessionId,  String cwd,  List<McpServer> mcpServers, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _LoadSessionRequest():
return $default(_that.sessionId,_that.cwd,_that.mcpServers,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionId sessionId,  String cwd,  List<McpServer> mcpServers, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _LoadSessionRequest() when $default != null:
return $default(_that.sessionId,_that.cwd,_that.mcpServers,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _LoadSessionRequest extends LoadSessionRequest {
  const _LoadSessionRequest({required this.sessionId, required this.cwd, required final  List<McpServer> mcpServers, @JsonKey(name: '_meta') final  JsonObject? meta}): _mcpServers = mcpServers,_meta = meta,super._();
  

@override final  SessionId sessionId;
@override final  String cwd;
 final  List<McpServer> _mcpServers;
@override List<McpServer> get mcpServers {
  if (_mcpServers is EqualUnmodifiableListView) return _mcpServers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_mcpServers);
}

 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of LoadSessionRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LoadSessionRequestCopyWith<_LoadSessionRequest> get copyWith => __$LoadSessionRequestCopyWithImpl<_LoadSessionRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LoadSessionRequest&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.cwd, cwd) || other.cwd == cwd)&&const DeepCollectionEquality().equals(other._mcpServers, _mcpServers)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,cwd,const DeepCollectionEquality().hash(_mcpServers),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'LoadSessionRequest(sessionId: $sessionId, cwd: $cwd, mcpServers: $mcpServers, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$LoadSessionRequestCopyWith<$Res> implements $LoadSessionRequestCopyWith<$Res> {
  factory _$LoadSessionRequestCopyWith(_LoadSessionRequest value, $Res Function(_LoadSessionRequest) _then) = __$LoadSessionRequestCopyWithImpl;
@override @useResult
$Res call({
 SessionId sessionId, String cwd, List<McpServer> mcpServers,@JsonKey(name: '_meta') JsonObject? meta
});


@override $SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class __$LoadSessionRequestCopyWithImpl<$Res>
    implements _$LoadSessionRequestCopyWith<$Res> {
  __$LoadSessionRequestCopyWithImpl(this._self, this._then);

  final _LoadSessionRequest _self;
  final $Res Function(_LoadSessionRequest) _then;

/// Create a copy of LoadSessionRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? cwd = null,Object? mcpServers = null,Object? meta = freezed,}) {
  return _then(_LoadSessionRequest(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,mcpServers: null == mcpServers ? _self._mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServer>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of LoadSessionRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}
}

/// @nodoc
mixin _$LoadSessionResponse {

 SessionModeState? get modes; List<SessionConfigOption>? get configOptions;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of LoadSessionResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoadSessionResponseCopyWith<LoadSessionResponse> get copyWith => _$LoadSessionResponseCopyWithImpl<LoadSessionResponse>(this as LoadSessionResponse, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LoadSessionResponse&&(identical(other.modes, modes) || other.modes == modes)&&const DeepCollectionEquality().equals(other.configOptions, configOptions)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,modes,const DeepCollectionEquality().hash(configOptions),const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'LoadSessionResponse(modes: $modes, configOptions: $configOptions, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $LoadSessionResponseCopyWith<$Res>  {
  factory $LoadSessionResponseCopyWith(LoadSessionResponse value, $Res Function(LoadSessionResponse) _then) = _$LoadSessionResponseCopyWithImpl;
@useResult
$Res call({
 SessionModeState? modes, List<SessionConfigOption>? configOptions,@JsonKey(name: '_meta') JsonObject? meta
});


$SessionModeStateCopyWith<$Res>? get modes;

}
/// @nodoc
class _$LoadSessionResponseCopyWithImpl<$Res>
    implements $LoadSessionResponseCopyWith<$Res> {
  _$LoadSessionResponseCopyWithImpl(this._self, this._then);

  final LoadSessionResponse _self;
  final $Res Function(LoadSessionResponse) _then;

/// Create a copy of LoadSessionResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modes = freezed,Object? configOptions = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
modes: freezed == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as SessionModeState?,configOptions: freezed == configOptions ? _self.configOptions : configOptions // ignore: cast_nullable_to_non_nullable
as List<SessionConfigOption>?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of LoadSessionResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionModeStateCopyWith<$Res>? get modes {
    if (_self.modes == null) {
    return null;
  }

  return $SessionModeStateCopyWith<$Res>(_self.modes!, (value) {
    return _then(_self.copyWith(modes: value));
  });
}
}


/// Adds pattern-matching-related methods to [LoadSessionResponse].
extension LoadSessionResponsePatterns on LoadSessionResponse {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LoadSessionResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LoadSessionResponse() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LoadSessionResponse value)  $default,){
final _that = this;
switch (_that) {
case _LoadSessionResponse():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LoadSessionResponse value)?  $default,){
final _that = this;
switch (_that) {
case _LoadSessionResponse() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionModeState? modes,  List<SessionConfigOption>? configOptions, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LoadSessionResponse() when $default != null:
return $default(_that.modes,_that.configOptions,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionModeState? modes,  List<SessionConfigOption>? configOptions, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _LoadSessionResponse():
return $default(_that.modes,_that.configOptions,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionModeState? modes,  List<SessionConfigOption>? configOptions, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _LoadSessionResponse() when $default != null:
return $default(_that.modes,_that.configOptions,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _LoadSessionResponse extends LoadSessionResponse {
  const _LoadSessionResponse({this.modes, final  List<SessionConfigOption>? configOptions, @JsonKey(name: '_meta') final  JsonObject? meta}): _configOptions = configOptions,_meta = meta,super._();
  

@override final  SessionModeState? modes;
 final  List<SessionConfigOption>? _configOptions;
@override List<SessionConfigOption>? get configOptions {
  final value = _configOptions;
  if (value == null) return null;
  if (_configOptions is EqualUnmodifiableListView) return _configOptions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of LoadSessionResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LoadSessionResponseCopyWith<_LoadSessionResponse> get copyWith => __$LoadSessionResponseCopyWithImpl<_LoadSessionResponse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LoadSessionResponse&&(identical(other.modes, modes) || other.modes == modes)&&const DeepCollectionEquality().equals(other._configOptions, _configOptions)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,modes,const DeepCollectionEquality().hash(_configOptions),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'LoadSessionResponse(modes: $modes, configOptions: $configOptions, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$LoadSessionResponseCopyWith<$Res> implements $LoadSessionResponseCopyWith<$Res> {
  factory _$LoadSessionResponseCopyWith(_LoadSessionResponse value, $Res Function(_LoadSessionResponse) _then) = __$LoadSessionResponseCopyWithImpl;
@override @useResult
$Res call({
 SessionModeState? modes, List<SessionConfigOption>? configOptions,@JsonKey(name: '_meta') JsonObject? meta
});


@override $SessionModeStateCopyWith<$Res>? get modes;

}
/// @nodoc
class __$LoadSessionResponseCopyWithImpl<$Res>
    implements _$LoadSessionResponseCopyWith<$Res> {
  __$LoadSessionResponseCopyWithImpl(this._self, this._then);

  final _LoadSessionResponse _self;
  final $Res Function(_LoadSessionResponse) _then;

/// Create a copy of LoadSessionResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modes = freezed,Object? configOptions = freezed,Object? meta = freezed,}) {
  return _then(_LoadSessionResponse(
modes: freezed == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as SessionModeState?,configOptions: freezed == configOptions ? _self._configOptions : configOptions // ignore: cast_nullable_to_non_nullable
as List<SessionConfigOption>?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of LoadSessionResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionModeStateCopyWith<$Res>? get modes {
    if (_self.modes == null) {
    return null;
  }

  return $SessionModeStateCopyWith<$Res>(_self.modes!, (value) {
    return _then(_self.copyWith(modes: value));
  });
}
}

/// @nodoc
mixin _$ListSessionsRequest {

 String? get cwd; String? get cursor;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of ListSessionsRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ListSessionsRequestCopyWith<ListSessionsRequest> get copyWith => _$ListSessionsRequestCopyWithImpl<ListSessionsRequest>(this as ListSessionsRequest, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ListSessionsRequest&&(identical(other.cwd, cwd) || other.cwd == cwd)&&(identical(other.cursor, cursor) || other.cursor == cursor)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,cwd,cursor,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'ListSessionsRequest(cwd: $cwd, cursor: $cursor, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $ListSessionsRequestCopyWith<$Res>  {
  factory $ListSessionsRequestCopyWith(ListSessionsRequest value, $Res Function(ListSessionsRequest) _then) = _$ListSessionsRequestCopyWithImpl;
@useResult
$Res call({
 String? cwd, String? cursor,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$ListSessionsRequestCopyWithImpl<$Res>
    implements $ListSessionsRequestCopyWith<$Res> {
  _$ListSessionsRequestCopyWithImpl(this._self, this._then);

  final ListSessionsRequest _self;
  final $Res Function(ListSessionsRequest) _then;

/// Create a copy of ListSessionsRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? cwd = freezed,Object? cursor = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
cwd: freezed == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String?,cursor: freezed == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

}


/// Adds pattern-matching-related methods to [ListSessionsRequest].
extension ListSessionsRequestPatterns on ListSessionsRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ListSessionsRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ListSessionsRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ListSessionsRequest value)  $default,){
final _that = this;
switch (_that) {
case _ListSessionsRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ListSessionsRequest value)?  $default,){
final _that = this;
switch (_that) {
case _ListSessionsRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? cwd,  String? cursor, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ListSessionsRequest() when $default != null:
return $default(_that.cwd,_that.cursor,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? cwd,  String? cursor, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _ListSessionsRequest():
return $default(_that.cwd,_that.cursor,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? cwd,  String? cursor, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _ListSessionsRequest() when $default != null:
return $default(_that.cwd,_that.cursor,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _ListSessionsRequest extends ListSessionsRequest {
  const _ListSessionsRequest({this.cwd, this.cursor, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  String? cwd;
@override final  String? cursor;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ListSessionsRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ListSessionsRequestCopyWith<_ListSessionsRequest> get copyWith => __$ListSessionsRequestCopyWithImpl<_ListSessionsRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ListSessionsRequest&&(identical(other.cwd, cwd) || other.cwd == cwd)&&(identical(other.cursor, cursor) || other.cursor == cursor)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,cwd,cursor,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'ListSessionsRequest(cwd: $cwd, cursor: $cursor, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$ListSessionsRequestCopyWith<$Res> implements $ListSessionsRequestCopyWith<$Res> {
  factory _$ListSessionsRequestCopyWith(_ListSessionsRequest value, $Res Function(_ListSessionsRequest) _then) = __$ListSessionsRequestCopyWithImpl;
@override @useResult
$Res call({
 String? cwd, String? cursor,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class __$ListSessionsRequestCopyWithImpl<$Res>
    implements _$ListSessionsRequestCopyWith<$Res> {
  __$ListSessionsRequestCopyWithImpl(this._self, this._then);

  final _ListSessionsRequest _self;
  final $Res Function(_ListSessionsRequest) _then;

/// Create a copy of ListSessionsRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? cwd = freezed,Object? cursor = freezed,Object? meta = freezed,}) {
  return _then(_ListSessionsRequest(
cwd: freezed == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String?,cursor: freezed == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$SessionInfo {

 SessionId get sessionId; String get cwd; String? get title; String? get updatedAt;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of SessionInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionInfoCopyWith<SessionInfo> get copyWith => _$SessionInfoCopyWithImpl<SessionInfo>(this as SessionInfo, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionInfo&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.cwd, cwd) || other.cwd == cwd)&&(identical(other.title, title) || other.title == title)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,cwd,title,updatedAt,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'SessionInfo(sessionId: $sessionId, cwd: $cwd, title: $title, updatedAt: $updatedAt, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $SessionInfoCopyWith<$Res>  {
  factory $SessionInfoCopyWith(SessionInfo value, $Res Function(SessionInfo) _then) = _$SessionInfoCopyWithImpl;
@useResult
$Res call({
 SessionId sessionId, String cwd, String? title, String? updatedAt,@JsonKey(name: '_meta') JsonObject? meta
});


$SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class _$SessionInfoCopyWithImpl<$Res>
    implements $SessionInfoCopyWith<$Res> {
  _$SessionInfoCopyWithImpl(this._self, this._then);

  final SessionInfo _self;
  final $Res Function(SessionInfo) _then;

/// Create a copy of SessionInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? cwd = null,Object? title = freezed,Object? updatedAt = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of SessionInfo
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionInfo].
extension SessionInfoPatterns on SessionInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionInfo value)  $default,){
final _that = this;
switch (_that) {
case _SessionInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionInfo value)?  $default,){
final _that = this;
switch (_that) {
case _SessionInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionId sessionId,  String cwd,  String? title,  String? updatedAt, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionInfo() when $default != null:
return $default(_that.sessionId,_that.cwd,_that.title,_that.updatedAt,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionId sessionId,  String cwd,  String? title,  String? updatedAt, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _SessionInfo():
return $default(_that.sessionId,_that.cwd,_that.title,_that.updatedAt,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionId sessionId,  String cwd,  String? title,  String? updatedAt, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _SessionInfo() when $default != null:
return $default(_that.sessionId,_that.cwd,_that.title,_that.updatedAt,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _SessionInfo extends SessionInfo {
  const _SessionInfo({required this.sessionId, required this.cwd, this.title, this.updatedAt, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  SessionId sessionId;
@override final  String cwd;
@override final  String? title;
@override final  String? updatedAt;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of SessionInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionInfoCopyWith<_SessionInfo> get copyWith => __$SessionInfoCopyWithImpl<_SessionInfo>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionInfo&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.cwd, cwd) || other.cwd == cwd)&&(identical(other.title, title) || other.title == title)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,cwd,title,updatedAt,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'SessionInfo(sessionId: $sessionId, cwd: $cwd, title: $title, updatedAt: $updatedAt, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$SessionInfoCopyWith<$Res> implements $SessionInfoCopyWith<$Res> {
  factory _$SessionInfoCopyWith(_SessionInfo value, $Res Function(_SessionInfo) _then) = __$SessionInfoCopyWithImpl;
@override @useResult
$Res call({
 SessionId sessionId, String cwd, String? title, String? updatedAt,@JsonKey(name: '_meta') JsonObject? meta
});


@override $SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class __$SessionInfoCopyWithImpl<$Res>
    implements _$SessionInfoCopyWith<$Res> {
  __$SessionInfoCopyWithImpl(this._self, this._then);

  final _SessionInfo _self;
  final $Res Function(_SessionInfo) _then;

/// Create a copy of SessionInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? cwd = null,Object? title = freezed,Object? updatedAt = freezed,Object? meta = freezed,}) {
  return _then(_SessionInfo(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of SessionInfo
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}
}

/// @nodoc
mixin _$ListSessionsResponse {

 List<SessionInfo> get sessions; String? get nextCursor;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of ListSessionsResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ListSessionsResponseCopyWith<ListSessionsResponse> get copyWith => _$ListSessionsResponseCopyWithImpl<ListSessionsResponse>(this as ListSessionsResponse, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ListSessionsResponse&&const DeepCollectionEquality().equals(other.sessions, sessions)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(sessions),nextCursor,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'ListSessionsResponse(sessions: $sessions, nextCursor: $nextCursor, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $ListSessionsResponseCopyWith<$Res>  {
  factory $ListSessionsResponseCopyWith(ListSessionsResponse value, $Res Function(ListSessionsResponse) _then) = _$ListSessionsResponseCopyWithImpl;
@useResult
$Res call({
 List<SessionInfo> sessions, String? nextCursor,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$ListSessionsResponseCopyWithImpl<$Res>
    implements $ListSessionsResponseCopyWith<$Res> {
  _$ListSessionsResponseCopyWithImpl(this._self, this._then);

  final ListSessionsResponse _self;
  final $Res Function(ListSessionsResponse) _then;

/// Create a copy of ListSessionsResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessions = null,Object? nextCursor = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
sessions: null == sessions ? _self.sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<SessionInfo>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

}


/// Adds pattern-matching-related methods to [ListSessionsResponse].
extension ListSessionsResponsePatterns on ListSessionsResponse {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ListSessionsResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ListSessionsResponse() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ListSessionsResponse value)  $default,){
final _that = this;
switch (_that) {
case _ListSessionsResponse():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ListSessionsResponse value)?  $default,){
final _that = this;
switch (_that) {
case _ListSessionsResponse() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<SessionInfo> sessions,  String? nextCursor, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ListSessionsResponse() when $default != null:
return $default(_that.sessions,_that.nextCursor,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<SessionInfo> sessions,  String? nextCursor, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _ListSessionsResponse():
return $default(_that.sessions,_that.nextCursor,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<SessionInfo> sessions,  String? nextCursor, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _ListSessionsResponse() when $default != null:
return $default(_that.sessions,_that.nextCursor,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _ListSessionsResponse extends ListSessionsResponse {
  const _ListSessionsResponse({required final  List<SessionInfo> sessions, this.nextCursor, @JsonKey(name: '_meta') final  JsonObject? meta}): _sessions = sessions,_meta = meta,super._();
  

 final  List<SessionInfo> _sessions;
@override List<SessionInfo> get sessions {
  if (_sessions is EqualUnmodifiableListView) return _sessions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sessions);
}

@override final  String? nextCursor;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ListSessionsResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ListSessionsResponseCopyWith<_ListSessionsResponse> get copyWith => __$ListSessionsResponseCopyWithImpl<_ListSessionsResponse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ListSessionsResponse&&const DeepCollectionEquality().equals(other._sessions, _sessions)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_sessions),nextCursor,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'ListSessionsResponse(sessions: $sessions, nextCursor: $nextCursor, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$ListSessionsResponseCopyWith<$Res> implements $ListSessionsResponseCopyWith<$Res> {
  factory _$ListSessionsResponseCopyWith(_ListSessionsResponse value, $Res Function(_ListSessionsResponse) _then) = __$ListSessionsResponseCopyWithImpl;
@override @useResult
$Res call({
 List<SessionInfo> sessions, String? nextCursor,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class __$ListSessionsResponseCopyWithImpl<$Res>
    implements _$ListSessionsResponseCopyWith<$Res> {
  __$ListSessionsResponseCopyWithImpl(this._self, this._then);

  final _ListSessionsResponse _self;
  final $Res Function(_ListSessionsResponse) _then;

/// Create a copy of ListSessionsResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessions = null,Object? nextCursor = freezed,Object? meta = freezed,}) {
  return _then(_ListSessionsResponse(
sessions: null == sessions ? _self._sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<SessionInfo>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

// dart format on
