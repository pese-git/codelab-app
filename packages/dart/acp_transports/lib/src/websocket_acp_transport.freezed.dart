// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'websocket_acp_transport.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WebSocketAcpTransportConfig {

 Uri get uri; Map<String, String> get headers; String? get token; String get tokenHeader; String get tokenPrefix;
/// Create a copy of WebSocketAcpTransportConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WebSocketAcpTransportConfigCopyWith<WebSocketAcpTransportConfig> get copyWith => _$WebSocketAcpTransportConfigCopyWithImpl<WebSocketAcpTransportConfig>(this as WebSocketAcpTransportConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WebSocketAcpTransportConfig&&(identical(other.uri, uri) || other.uri == uri)&&const DeepCollectionEquality().equals(other.headers, headers)&&(identical(other.token, token) || other.token == token)&&(identical(other.tokenHeader, tokenHeader) || other.tokenHeader == tokenHeader)&&(identical(other.tokenPrefix, tokenPrefix) || other.tokenPrefix == tokenPrefix));
}


@override
int get hashCode => Object.hash(runtimeType,uri,const DeepCollectionEquality().hash(headers),token,tokenHeader,tokenPrefix);

@override
String toString() {
  return 'WebSocketAcpTransportConfig(uri: $uri, headers: $headers, token: $token, tokenHeader: $tokenHeader, tokenPrefix: $tokenPrefix)';
}


}

/// @nodoc
abstract mixin class $WebSocketAcpTransportConfigCopyWith<$Res>  {
  factory $WebSocketAcpTransportConfigCopyWith(WebSocketAcpTransportConfig value, $Res Function(WebSocketAcpTransportConfig) _then) = _$WebSocketAcpTransportConfigCopyWithImpl;
@useResult
$Res call({
 Uri uri, Map<String, String> headers, String? token, String tokenHeader, String tokenPrefix
});




}
/// @nodoc
class _$WebSocketAcpTransportConfigCopyWithImpl<$Res>
    implements $WebSocketAcpTransportConfigCopyWith<$Res> {
  _$WebSocketAcpTransportConfigCopyWithImpl(this._self, this._then);

  final WebSocketAcpTransportConfig _self;
  final $Res Function(WebSocketAcpTransportConfig) _then;

/// Create a copy of WebSocketAcpTransportConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? uri = null,Object? headers = null,Object? token = freezed,Object? tokenHeader = null,Object? tokenPrefix = null,}) {
  return _then(_self.copyWith(
uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as Uri,headers: null == headers ? _self.headers : headers // ignore: cast_nullable_to_non_nullable
as Map<String, String>,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,tokenHeader: null == tokenHeader ? _self.tokenHeader : tokenHeader // ignore: cast_nullable_to_non_nullable
as String,tokenPrefix: null == tokenPrefix ? _self.tokenPrefix : tokenPrefix // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [WebSocketAcpTransportConfig].
extension WebSocketAcpTransportConfigPatterns on WebSocketAcpTransportConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WebSocketAcpTransportConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WebSocketAcpTransportConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WebSocketAcpTransportConfig value)  $default,){
final _that = this;
switch (_that) {
case _WebSocketAcpTransportConfig():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WebSocketAcpTransportConfig value)?  $default,){
final _that = this;
switch (_that) {
case _WebSocketAcpTransportConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Uri uri,  Map<String, String> headers,  String? token,  String tokenHeader,  String tokenPrefix)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WebSocketAcpTransportConfig() when $default != null:
return $default(_that.uri,_that.headers,_that.token,_that.tokenHeader,_that.tokenPrefix);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Uri uri,  Map<String, String> headers,  String? token,  String tokenHeader,  String tokenPrefix)  $default,) {final _that = this;
switch (_that) {
case _WebSocketAcpTransportConfig():
return $default(_that.uri,_that.headers,_that.token,_that.tokenHeader,_that.tokenPrefix);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Uri uri,  Map<String, String> headers,  String? token,  String tokenHeader,  String tokenPrefix)?  $default,) {final _that = this;
switch (_that) {
case _WebSocketAcpTransportConfig() when $default != null:
return $default(_that.uri,_that.headers,_that.token,_that.tokenHeader,_that.tokenPrefix);case _:
  return null;

}
}

}

/// @nodoc


class _WebSocketAcpTransportConfig extends WebSocketAcpTransportConfig {
  const _WebSocketAcpTransportConfig({required this.uri, final  Map<String, String> headers = const {}, this.token, this.tokenHeader = 'Authorization', this.tokenPrefix = 'Bearer'}): _headers = headers,super._();
  

@override final  Uri uri;
 final  Map<String, String> _headers;
@override@JsonKey() Map<String, String> get headers {
  if (_headers is EqualUnmodifiableMapView) return _headers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_headers);
}

@override final  String? token;
@override@JsonKey() final  String tokenHeader;
@override@JsonKey() final  String tokenPrefix;

/// Create a copy of WebSocketAcpTransportConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WebSocketAcpTransportConfigCopyWith<_WebSocketAcpTransportConfig> get copyWith => __$WebSocketAcpTransportConfigCopyWithImpl<_WebSocketAcpTransportConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WebSocketAcpTransportConfig&&(identical(other.uri, uri) || other.uri == uri)&&const DeepCollectionEquality().equals(other._headers, _headers)&&(identical(other.token, token) || other.token == token)&&(identical(other.tokenHeader, tokenHeader) || other.tokenHeader == tokenHeader)&&(identical(other.tokenPrefix, tokenPrefix) || other.tokenPrefix == tokenPrefix));
}


@override
int get hashCode => Object.hash(runtimeType,uri,const DeepCollectionEquality().hash(_headers),token,tokenHeader,tokenPrefix);

@override
String toString() {
  return 'WebSocketAcpTransportConfig(uri: $uri, headers: $headers, token: $token, tokenHeader: $tokenHeader, tokenPrefix: $tokenPrefix)';
}


}

/// @nodoc
abstract mixin class _$WebSocketAcpTransportConfigCopyWith<$Res> implements $WebSocketAcpTransportConfigCopyWith<$Res> {
  factory _$WebSocketAcpTransportConfigCopyWith(_WebSocketAcpTransportConfig value, $Res Function(_WebSocketAcpTransportConfig) _then) = __$WebSocketAcpTransportConfigCopyWithImpl;
@override @useResult
$Res call({
 Uri uri, Map<String, String> headers, String? token, String tokenHeader, String tokenPrefix
});




}
/// @nodoc
class __$WebSocketAcpTransportConfigCopyWithImpl<$Res>
    implements _$WebSocketAcpTransportConfigCopyWith<$Res> {
  __$WebSocketAcpTransportConfigCopyWithImpl(this._self, this._then);

  final _WebSocketAcpTransportConfig _self;
  final $Res Function(_WebSocketAcpTransportConfig) _then;

/// Create a copy of WebSocketAcpTransportConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? uri = null,Object? headers = null,Object? token = freezed,Object? tokenHeader = null,Object? tokenPrefix = null,}) {
  return _then(_WebSocketAcpTransportConfig(
uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as Uri,headers: null == headers ? _self._headers : headers // ignore: cast_nullable_to_non_nullable
as Map<String, String>,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,tokenHeader: null == tokenHeader ? _self.tokenHeader : tokenHeader // ignore: cast_nullable_to_non_nullable
as String,tokenPrefix: null == tokenPrefix ? _self.tokenPrefix : tokenPrefix // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
