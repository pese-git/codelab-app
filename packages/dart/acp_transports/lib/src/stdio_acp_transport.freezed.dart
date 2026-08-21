// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'stdio_acp_transport.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StdioAcpTransportConfig {

 String get command; List<String> get args; String? get cwd; Map<String, String> get env;
/// Create a copy of StdioAcpTransportConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StdioAcpTransportConfigCopyWith<StdioAcpTransportConfig> get copyWith => _$StdioAcpTransportConfigCopyWithImpl<StdioAcpTransportConfig>(this as StdioAcpTransportConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StdioAcpTransportConfig&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other.args, args)&&(identical(other.cwd, cwd) || other.cwd == cwd)&&const DeepCollectionEquality().equals(other.env, env));
}


@override
int get hashCode => Object.hash(runtimeType,command,const DeepCollectionEquality().hash(args),cwd,const DeepCollectionEquality().hash(env));

@override
String toString() {
  return 'StdioAcpTransportConfig(command: $command, args: $args, cwd: $cwd, env: $env)';
}


}

/// @nodoc
abstract mixin class $StdioAcpTransportConfigCopyWith<$Res>  {
  factory $StdioAcpTransportConfigCopyWith(StdioAcpTransportConfig value, $Res Function(StdioAcpTransportConfig) _then) = _$StdioAcpTransportConfigCopyWithImpl;
@useResult
$Res call({
 String command, List<String> args, String? cwd, Map<String, String> env
});




}
/// @nodoc
class _$StdioAcpTransportConfigCopyWithImpl<$Res>
    implements $StdioAcpTransportConfigCopyWith<$Res> {
  _$StdioAcpTransportConfigCopyWithImpl(this._self, this._then);

  final StdioAcpTransportConfig _self;
  final $Res Function(StdioAcpTransportConfig) _then;

/// Create a copy of StdioAcpTransportConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? command = null,Object? args = null,Object? cwd = freezed,Object? env = null,}) {
  return _then(_self.copyWith(
command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as List<String>,cwd: freezed == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String?,env: null == env ? _self.env : env // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}

}


/// Adds pattern-matching-related methods to [StdioAcpTransportConfig].
extension StdioAcpTransportConfigPatterns on StdioAcpTransportConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StdioAcpTransportConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StdioAcpTransportConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StdioAcpTransportConfig value)  $default,){
final _that = this;
switch (_that) {
case _StdioAcpTransportConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StdioAcpTransportConfig value)?  $default,){
final _that = this;
switch (_that) {
case _StdioAcpTransportConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String command,  List<String> args,  String? cwd,  Map<String, String> env)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StdioAcpTransportConfig() when $default != null:
return $default(_that.command,_that.args,_that.cwd,_that.env);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String command,  List<String> args,  String? cwd,  Map<String, String> env)  $default,) {final _that = this;
switch (_that) {
case _StdioAcpTransportConfig():
return $default(_that.command,_that.args,_that.cwd,_that.env);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String command,  List<String> args,  String? cwd,  Map<String, String> env)?  $default,) {final _that = this;
switch (_that) {
case _StdioAcpTransportConfig() when $default != null:
return $default(_that.command,_that.args,_that.cwd,_that.env);case _:
  return null;

}
}

}

/// @nodoc


class _StdioAcpTransportConfig implements StdioAcpTransportConfig {
  const _StdioAcpTransportConfig({required this.command, final  List<String> args = const [], this.cwd, final  Map<String, String> env = const {}}): _args = args,_env = env;
  

@override final  String command;
 final  List<String> _args;
@override@JsonKey() List<String> get args {
  if (_args is EqualUnmodifiableListView) return _args;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_args);
}

@override final  String? cwd;
 final  Map<String, String> _env;
@override@JsonKey() Map<String, String> get env {
  if (_env is EqualUnmodifiableMapView) return _env;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_env);
}


/// Create a copy of StdioAcpTransportConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StdioAcpTransportConfigCopyWith<_StdioAcpTransportConfig> get copyWith => __$StdioAcpTransportConfigCopyWithImpl<_StdioAcpTransportConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StdioAcpTransportConfig&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other._args, _args)&&(identical(other.cwd, cwd) || other.cwd == cwd)&&const DeepCollectionEquality().equals(other._env, _env));
}


@override
int get hashCode => Object.hash(runtimeType,command,const DeepCollectionEquality().hash(_args),cwd,const DeepCollectionEquality().hash(_env));

@override
String toString() {
  return 'StdioAcpTransportConfig(command: $command, args: $args, cwd: $cwd, env: $env)';
}


}

/// @nodoc
abstract mixin class _$StdioAcpTransportConfigCopyWith<$Res> implements $StdioAcpTransportConfigCopyWith<$Res> {
  factory _$StdioAcpTransportConfigCopyWith(_StdioAcpTransportConfig value, $Res Function(_StdioAcpTransportConfig) _then) = __$StdioAcpTransportConfigCopyWithImpl;
@override @useResult
$Res call({
 String command, List<String> args, String? cwd, Map<String, String> env
});




}
/// @nodoc
class __$StdioAcpTransportConfigCopyWithImpl<$Res>
    implements _$StdioAcpTransportConfigCopyWith<$Res> {
  __$StdioAcpTransportConfigCopyWithImpl(this._self, this._then);

  final _StdioAcpTransportConfig _self;
  final $Res Function(_StdioAcpTransportConfig) _then;

/// Create a copy of StdioAcpTransportConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? command = null,Object? args = null,Object? cwd = freezed,Object? env = null,}) {
  return _then(_StdioAcpTransportConfig(
command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self._args : args // ignore: cast_nullable_to_non_nullable
as List<String>,cwd: freezed == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String?,env: null == env ? _self._env : env // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}

/// @nodoc
mixin _$StdioAcpAgentProfile {

 String get name; String get type; String get command; List<String> get args; String? get cwd; Map<String, String> get env;
/// Create a copy of StdioAcpAgentProfile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StdioAcpAgentProfileCopyWith<StdioAcpAgentProfile> get copyWith => _$StdioAcpAgentProfileCopyWithImpl<StdioAcpAgentProfile>(this as StdioAcpAgentProfile, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StdioAcpAgentProfile&&(identical(other.name, name) || other.name == name)&&(identical(other.type, type) || other.type == type)&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other.args, args)&&(identical(other.cwd, cwd) || other.cwd == cwd)&&const DeepCollectionEquality().equals(other.env, env));
}


@override
int get hashCode => Object.hash(runtimeType,name,type,command,const DeepCollectionEquality().hash(args),cwd,const DeepCollectionEquality().hash(env));

@override
String toString() {
  return 'StdioAcpAgentProfile(name: $name, type: $type, command: $command, args: $args, cwd: $cwd, env: $env)';
}


}

/// @nodoc
abstract mixin class $StdioAcpAgentProfileCopyWith<$Res>  {
  factory $StdioAcpAgentProfileCopyWith(StdioAcpAgentProfile value, $Res Function(StdioAcpAgentProfile) _then) = _$StdioAcpAgentProfileCopyWithImpl;
@useResult
$Res call({
 String name, String type, String command, List<String> args, String? cwd, Map<String, String> env
});




}
/// @nodoc
class _$StdioAcpAgentProfileCopyWithImpl<$Res>
    implements $StdioAcpAgentProfileCopyWith<$Res> {
  _$StdioAcpAgentProfileCopyWithImpl(this._self, this._then);

  final StdioAcpAgentProfile _self;
  final $Res Function(StdioAcpAgentProfile) _then;

/// Create a copy of StdioAcpAgentProfile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? type = null,Object? command = null,Object? args = null,Object? cwd = freezed,Object? env = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as List<String>,cwd: freezed == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String?,env: null == env ? _self.env : env // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}

}


/// Adds pattern-matching-related methods to [StdioAcpAgentProfile].
extension StdioAcpAgentProfilePatterns on StdioAcpAgentProfile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StdioAcpAgentProfile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StdioAcpAgentProfile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StdioAcpAgentProfile value)  $default,){
final _that = this;
switch (_that) {
case _StdioAcpAgentProfile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StdioAcpAgentProfile value)?  $default,){
final _that = this;
switch (_that) {
case _StdioAcpAgentProfile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String type,  String command,  List<String> args,  String? cwd,  Map<String, String> env)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StdioAcpAgentProfile() when $default != null:
return $default(_that.name,_that.type,_that.command,_that.args,_that.cwd,_that.env);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String type,  String command,  List<String> args,  String? cwd,  Map<String, String> env)  $default,) {final _that = this;
switch (_that) {
case _StdioAcpAgentProfile():
return $default(_that.name,_that.type,_that.command,_that.args,_that.cwd,_that.env);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String type,  String command,  List<String> args,  String? cwd,  Map<String, String> env)?  $default,) {final _that = this;
switch (_that) {
case _StdioAcpAgentProfile() when $default != null:
return $default(_that.name,_that.type,_that.command,_that.args,_that.cwd,_that.env);case _:
  return null;

}
}

}

/// @nodoc


class _StdioAcpAgentProfile extends StdioAcpAgentProfile {
  const _StdioAcpAgentProfile({required this.name, this.type = 'custom', required this.command, final  List<String> args = const [], this.cwd, final  Map<String, String> env = const {}}): _args = args,_env = env,super._();
  

@override final  String name;
@override@JsonKey() final  String type;
@override final  String command;
 final  List<String> _args;
@override@JsonKey() List<String> get args {
  if (_args is EqualUnmodifiableListView) return _args;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_args);
}

@override final  String? cwd;
 final  Map<String, String> _env;
@override@JsonKey() Map<String, String> get env {
  if (_env is EqualUnmodifiableMapView) return _env;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_env);
}


/// Create a copy of StdioAcpAgentProfile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StdioAcpAgentProfileCopyWith<_StdioAcpAgentProfile> get copyWith => __$StdioAcpAgentProfileCopyWithImpl<_StdioAcpAgentProfile>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StdioAcpAgentProfile&&(identical(other.name, name) || other.name == name)&&(identical(other.type, type) || other.type == type)&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other._args, _args)&&(identical(other.cwd, cwd) || other.cwd == cwd)&&const DeepCollectionEquality().equals(other._env, _env));
}


@override
int get hashCode => Object.hash(runtimeType,name,type,command,const DeepCollectionEquality().hash(_args),cwd,const DeepCollectionEquality().hash(_env));

@override
String toString() {
  return 'StdioAcpAgentProfile(name: $name, type: $type, command: $command, args: $args, cwd: $cwd, env: $env)';
}


}

/// @nodoc
abstract mixin class _$StdioAcpAgentProfileCopyWith<$Res> implements $StdioAcpAgentProfileCopyWith<$Res> {
  factory _$StdioAcpAgentProfileCopyWith(_StdioAcpAgentProfile value, $Res Function(_StdioAcpAgentProfile) _then) = __$StdioAcpAgentProfileCopyWithImpl;
@override @useResult
$Res call({
 String name, String type, String command, List<String> args, String? cwd, Map<String, String> env
});




}
/// @nodoc
class __$StdioAcpAgentProfileCopyWithImpl<$Res>
    implements _$StdioAcpAgentProfileCopyWith<$Res> {
  __$StdioAcpAgentProfileCopyWithImpl(this._self, this._then);

  final _StdioAcpAgentProfile _self;
  final $Res Function(_StdioAcpAgentProfile) _then;

/// Create a copy of StdioAcpAgentProfile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? type = null,Object? command = null,Object? args = null,Object? cwd = freezed,Object? env = null,}) {
  return _then(_StdioAcpAgentProfile(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self._args : args // ignore: cast_nullable_to_non_nullable
as List<String>,cwd: freezed == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String?,env: null == env ? _self._env : env // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}

// dart format on
