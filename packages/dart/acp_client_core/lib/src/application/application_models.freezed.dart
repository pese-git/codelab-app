// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'application_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CreateSessionCommand {

 String get cwd; List<McpServer> get mcpServers; Map<String, Object?>? get meta;
/// Create a copy of CreateSessionCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CreateSessionCommandCopyWith<CreateSessionCommand> get copyWith => _$CreateSessionCommandCopyWithImpl<CreateSessionCommand>(this as CreateSessionCommand, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CreateSessionCommand&&(identical(other.cwd, cwd) || other.cwd == cwd)&&const DeepCollectionEquality().equals(other.mcpServers, mcpServers)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,cwd,const DeepCollectionEquality().hash(mcpServers),const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'CreateSessionCommand(cwd: $cwd, mcpServers: $mcpServers, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $CreateSessionCommandCopyWith<$Res>  {
  factory $CreateSessionCommandCopyWith(CreateSessionCommand value, $Res Function(CreateSessionCommand) _then) = _$CreateSessionCommandCopyWithImpl;
@useResult
$Res call({
 String cwd, List<McpServer> mcpServers, Map<String, Object?>? meta
});




}
/// @nodoc
class _$CreateSessionCommandCopyWithImpl<$Res>
    implements $CreateSessionCommandCopyWith<$Res> {
  _$CreateSessionCommandCopyWithImpl(this._self, this._then);

  final CreateSessionCommand _self;
  final $Res Function(CreateSessionCommand) _then;

/// Create a copy of CreateSessionCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? cwd = null,Object? mcpServers = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,mcpServers: null == mcpServers ? _self.mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServer>,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}

}


/// Adds pattern-matching-related methods to [CreateSessionCommand].
extension CreateSessionCommandPatterns on CreateSessionCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CreateSessionCommand value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CreateSessionCommand() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CreateSessionCommand value)  $default,){
final _that = this;
switch (_that) {
case _CreateSessionCommand():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CreateSessionCommand value)?  $default,){
final _that = this;
switch (_that) {
case _CreateSessionCommand() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String cwd,  List<McpServer> mcpServers,  Map<String, Object?>? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CreateSessionCommand() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String cwd,  List<McpServer> mcpServers,  Map<String, Object?>? meta)  $default,) {final _that = this;
switch (_that) {
case _CreateSessionCommand():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String cwd,  List<McpServer> mcpServers,  Map<String, Object?>? meta)?  $default,) {final _that = this;
switch (_that) {
case _CreateSessionCommand() when $default != null:
return $default(_that.cwd,_that.mcpServers,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _CreateSessionCommand extends CreateSessionCommand {
  const _CreateSessionCommand({required this.cwd, final  List<McpServer> mcpServers = const [], final  Map<String, Object?>? meta}): _mcpServers = mcpServers,_meta = meta,super._();
  

@override final  String cwd;
 final  List<McpServer> _mcpServers;
@override@JsonKey() List<McpServer> get mcpServers {
  if (_mcpServers is EqualUnmodifiableListView) return _mcpServers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_mcpServers);
}

 final  Map<String, Object?>? _meta;
@override Map<String, Object?>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of CreateSessionCommand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CreateSessionCommandCopyWith<_CreateSessionCommand> get copyWith => __$CreateSessionCommandCopyWithImpl<_CreateSessionCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CreateSessionCommand&&(identical(other.cwd, cwd) || other.cwd == cwd)&&const DeepCollectionEquality().equals(other._mcpServers, _mcpServers)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,cwd,const DeepCollectionEquality().hash(_mcpServers),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'CreateSessionCommand(cwd: $cwd, mcpServers: $mcpServers, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$CreateSessionCommandCopyWith<$Res> implements $CreateSessionCommandCopyWith<$Res> {
  factory _$CreateSessionCommandCopyWith(_CreateSessionCommand value, $Res Function(_CreateSessionCommand) _then) = __$CreateSessionCommandCopyWithImpl;
@override @useResult
$Res call({
 String cwd, List<McpServer> mcpServers, Map<String, Object?>? meta
});




}
/// @nodoc
class __$CreateSessionCommandCopyWithImpl<$Res>
    implements _$CreateSessionCommandCopyWith<$Res> {
  __$CreateSessionCommandCopyWithImpl(this._self, this._then);

  final _CreateSessionCommand _self;
  final $Res Function(_CreateSessionCommand) _then;

/// Create a copy of CreateSessionCommand
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? cwd = null,Object? mcpServers = null,Object? meta = freezed,}) {
  return _then(_CreateSessionCommand(
cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,mcpServers: null == mcpServers ? _self._mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServer>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}


}

/// @nodoc
mixin _$LoadSessionCommand {

 SessionId get sessionId; String get cwd; List<McpServer> get mcpServers; Map<String, Object?>? get meta;
/// Create a copy of LoadSessionCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoadSessionCommandCopyWith<LoadSessionCommand> get copyWith => _$LoadSessionCommandCopyWithImpl<LoadSessionCommand>(this as LoadSessionCommand, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LoadSessionCommand&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.cwd, cwd) || other.cwd == cwd)&&const DeepCollectionEquality().equals(other.mcpServers, mcpServers)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,cwd,const DeepCollectionEquality().hash(mcpServers),const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'LoadSessionCommand(sessionId: $sessionId, cwd: $cwd, mcpServers: $mcpServers, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $LoadSessionCommandCopyWith<$Res>  {
  factory $LoadSessionCommandCopyWith(LoadSessionCommand value, $Res Function(LoadSessionCommand) _then) = _$LoadSessionCommandCopyWithImpl;
@useResult
$Res call({
 SessionId sessionId, String cwd, List<McpServer> mcpServers, Map<String, Object?>? meta
});


$SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class _$LoadSessionCommandCopyWithImpl<$Res>
    implements $LoadSessionCommandCopyWith<$Res> {
  _$LoadSessionCommandCopyWithImpl(this._self, this._then);

  final LoadSessionCommand _self;
  final $Res Function(LoadSessionCommand) _then;

/// Create a copy of LoadSessionCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? cwd = null,Object? mcpServers = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,mcpServers: null == mcpServers ? _self.mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServer>,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}
/// Create a copy of LoadSessionCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}
}


/// Adds pattern-matching-related methods to [LoadSessionCommand].
extension LoadSessionCommandPatterns on LoadSessionCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LoadSessionCommand value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LoadSessionCommand() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LoadSessionCommand value)  $default,){
final _that = this;
switch (_that) {
case _LoadSessionCommand():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LoadSessionCommand value)?  $default,){
final _that = this;
switch (_that) {
case _LoadSessionCommand() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionId sessionId,  String cwd,  List<McpServer> mcpServers,  Map<String, Object?>? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LoadSessionCommand() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionId sessionId,  String cwd,  List<McpServer> mcpServers,  Map<String, Object?>? meta)  $default,) {final _that = this;
switch (_that) {
case _LoadSessionCommand():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionId sessionId,  String cwd,  List<McpServer> mcpServers,  Map<String, Object?>? meta)?  $default,) {final _that = this;
switch (_that) {
case _LoadSessionCommand() when $default != null:
return $default(_that.sessionId,_that.cwd,_that.mcpServers,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _LoadSessionCommand extends LoadSessionCommand {
  const _LoadSessionCommand({required this.sessionId, required this.cwd, final  List<McpServer> mcpServers = const [], final  Map<String, Object?>? meta}): _mcpServers = mcpServers,_meta = meta,super._();
  

@override final  SessionId sessionId;
@override final  String cwd;
 final  List<McpServer> _mcpServers;
@override@JsonKey() List<McpServer> get mcpServers {
  if (_mcpServers is EqualUnmodifiableListView) return _mcpServers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_mcpServers);
}

 final  Map<String, Object?>? _meta;
@override Map<String, Object?>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of LoadSessionCommand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LoadSessionCommandCopyWith<_LoadSessionCommand> get copyWith => __$LoadSessionCommandCopyWithImpl<_LoadSessionCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LoadSessionCommand&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.cwd, cwd) || other.cwd == cwd)&&const DeepCollectionEquality().equals(other._mcpServers, _mcpServers)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,cwd,const DeepCollectionEquality().hash(_mcpServers),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'LoadSessionCommand(sessionId: $sessionId, cwd: $cwd, mcpServers: $mcpServers, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$LoadSessionCommandCopyWith<$Res> implements $LoadSessionCommandCopyWith<$Res> {
  factory _$LoadSessionCommandCopyWith(_LoadSessionCommand value, $Res Function(_LoadSessionCommand) _then) = __$LoadSessionCommandCopyWithImpl;
@override @useResult
$Res call({
 SessionId sessionId, String cwd, List<McpServer> mcpServers, Map<String, Object?>? meta
});


@override $SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class __$LoadSessionCommandCopyWithImpl<$Res>
    implements _$LoadSessionCommandCopyWith<$Res> {
  __$LoadSessionCommandCopyWithImpl(this._self, this._then);

  final _LoadSessionCommand _self;
  final $Res Function(_LoadSessionCommand) _then;

/// Create a copy of LoadSessionCommand
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? cwd = null,Object? mcpServers = null,Object? meta = freezed,}) {
  return _then(_LoadSessionCommand(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,mcpServers: null == mcpServers ? _self._mcpServers : mcpServers // ignore: cast_nullable_to_non_nullable
as List<McpServer>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}

/// Create a copy of LoadSessionCommand
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
mixin _$SendPromptCommand {

 SessionId get sessionId; List<ContentBlock> get prompt; Map<String, Object?>? get meta;
/// Create a copy of SendPromptCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SendPromptCommandCopyWith<SendPromptCommand> get copyWith => _$SendPromptCommandCopyWithImpl<SendPromptCommand>(this as SendPromptCommand, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SendPromptCommand&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&const DeepCollectionEquality().equals(other.prompt, prompt)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,const DeepCollectionEquality().hash(prompt),const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'SendPromptCommand(sessionId: $sessionId, prompt: $prompt, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $SendPromptCommandCopyWith<$Res>  {
  factory $SendPromptCommandCopyWith(SendPromptCommand value, $Res Function(SendPromptCommand) _then) = _$SendPromptCommandCopyWithImpl;
@useResult
$Res call({
 SessionId sessionId, List<ContentBlock> prompt, Map<String, Object?>? meta
});


$SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class _$SendPromptCommandCopyWithImpl<$Res>
    implements $SendPromptCommandCopyWith<$Res> {
  _$SendPromptCommandCopyWithImpl(this._self, this._then);

  final SendPromptCommand _self;
  final $Res Function(SendPromptCommand) _then;

/// Create a copy of SendPromptCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? prompt = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as List<ContentBlock>,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}
/// Create a copy of SendPromptCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}
}


/// Adds pattern-matching-related methods to [SendPromptCommand].
extension SendPromptCommandPatterns on SendPromptCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SendPromptCommand value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SendPromptCommand() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SendPromptCommand value)  $default,){
final _that = this;
switch (_that) {
case _SendPromptCommand():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SendPromptCommand value)?  $default,){
final _that = this;
switch (_that) {
case _SendPromptCommand() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionId sessionId,  List<ContentBlock> prompt,  Map<String, Object?>? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SendPromptCommand() when $default != null:
return $default(_that.sessionId,_that.prompt,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionId sessionId,  List<ContentBlock> prompt,  Map<String, Object?>? meta)  $default,) {final _that = this;
switch (_that) {
case _SendPromptCommand():
return $default(_that.sessionId,_that.prompt,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionId sessionId,  List<ContentBlock> prompt,  Map<String, Object?>? meta)?  $default,) {final _that = this;
switch (_that) {
case _SendPromptCommand() when $default != null:
return $default(_that.sessionId,_that.prompt,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _SendPromptCommand extends SendPromptCommand {
  const _SendPromptCommand({required this.sessionId, required final  List<ContentBlock> prompt, final  Map<String, Object?>? meta}): _prompt = prompt,_meta = meta,super._();
  

@override final  SessionId sessionId;
 final  List<ContentBlock> _prompt;
@override List<ContentBlock> get prompt {
  if (_prompt is EqualUnmodifiableListView) return _prompt;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_prompt);
}

 final  Map<String, Object?>? _meta;
@override Map<String, Object?>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of SendPromptCommand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SendPromptCommandCopyWith<_SendPromptCommand> get copyWith => __$SendPromptCommandCopyWithImpl<_SendPromptCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SendPromptCommand&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&const DeepCollectionEquality().equals(other._prompt, _prompt)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,const DeepCollectionEquality().hash(_prompt),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'SendPromptCommand(sessionId: $sessionId, prompt: $prompt, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$SendPromptCommandCopyWith<$Res> implements $SendPromptCommandCopyWith<$Res> {
  factory _$SendPromptCommandCopyWith(_SendPromptCommand value, $Res Function(_SendPromptCommand) _then) = __$SendPromptCommandCopyWithImpl;
@override @useResult
$Res call({
 SessionId sessionId, List<ContentBlock> prompt, Map<String, Object?>? meta
});


@override $SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class __$SendPromptCommandCopyWithImpl<$Res>
    implements _$SendPromptCommandCopyWith<$Res> {
  __$SendPromptCommandCopyWithImpl(this._self, this._then);

  final _SendPromptCommand _self;
  final $Res Function(_SendPromptCommand) _then;

/// Create a copy of SendPromptCommand
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? prompt = null,Object? meta = freezed,}) {
  return _then(_SendPromptCommand(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,prompt: null == prompt ? _self._prompt : prompt // ignore: cast_nullable_to_non_nullable
as List<ContentBlock>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}

/// Create a copy of SendPromptCommand
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
mixin _$CancelTurnCommand {

 SessionId get sessionId; Map<String, Object?>? get meta;
/// Create a copy of CancelTurnCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelTurnCommandCopyWith<CancelTurnCommand> get copyWith => _$CancelTurnCommandCopyWithImpl<CancelTurnCommand>(this as CancelTurnCommand, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelTurnCommand&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'CancelTurnCommand(sessionId: $sessionId, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $CancelTurnCommandCopyWith<$Res>  {
  factory $CancelTurnCommandCopyWith(CancelTurnCommand value, $Res Function(CancelTurnCommand) _then) = _$CancelTurnCommandCopyWithImpl;
@useResult
$Res call({
 SessionId sessionId, Map<String, Object?>? meta
});


$SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class _$CancelTurnCommandCopyWithImpl<$Res>
    implements $CancelTurnCommandCopyWith<$Res> {
  _$CancelTurnCommandCopyWithImpl(this._self, this._then);

  final CancelTurnCommand _self;
  final $Res Function(CancelTurnCommand) _then;

/// Create a copy of CancelTurnCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}
/// Create a copy of CancelTurnCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}
}


/// Adds pattern-matching-related methods to [CancelTurnCommand].
extension CancelTurnCommandPatterns on CancelTurnCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CancelTurnCommand value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CancelTurnCommand() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CancelTurnCommand value)  $default,){
final _that = this;
switch (_that) {
case _CancelTurnCommand():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CancelTurnCommand value)?  $default,){
final _that = this;
switch (_that) {
case _CancelTurnCommand() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionId sessionId,  Map<String, Object?>? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CancelTurnCommand() when $default != null:
return $default(_that.sessionId,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionId sessionId,  Map<String, Object?>? meta)  $default,) {final _that = this;
switch (_that) {
case _CancelTurnCommand():
return $default(_that.sessionId,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionId sessionId,  Map<String, Object?>? meta)?  $default,) {final _that = this;
switch (_that) {
case _CancelTurnCommand() when $default != null:
return $default(_that.sessionId,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _CancelTurnCommand extends CancelTurnCommand {
  const _CancelTurnCommand({required this.sessionId, final  Map<String, Object?>? meta}): _meta = meta,super._();
  

@override final  SessionId sessionId;
 final  Map<String, Object?>? _meta;
@override Map<String, Object?>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of CancelTurnCommand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CancelTurnCommandCopyWith<_CancelTurnCommand> get copyWith => __$CancelTurnCommandCopyWithImpl<_CancelTurnCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CancelTurnCommand&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'CancelTurnCommand(sessionId: $sessionId, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$CancelTurnCommandCopyWith<$Res> implements $CancelTurnCommandCopyWith<$Res> {
  factory _$CancelTurnCommandCopyWith(_CancelTurnCommand value, $Res Function(_CancelTurnCommand) _then) = __$CancelTurnCommandCopyWithImpl;
@override @useResult
$Res call({
 SessionId sessionId, Map<String, Object?>? meta
});


@override $SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class __$CancelTurnCommandCopyWithImpl<$Res>
    implements _$CancelTurnCommandCopyWith<$Res> {
  __$CancelTurnCommandCopyWithImpl(this._self, this._then);

  final _CancelTurnCommand _self;
  final $Res Function(_CancelTurnCommand) _then;

/// Create a copy of CancelTurnCommand
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? meta = freezed,}) {
  return _then(_CancelTurnCommand(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}

/// Create a copy of CancelTurnCommand
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
mixin _$ReconnectCommand {

 Duration? get closeTimeout; AcpTransportFactory? get transportFactory;
/// Create a copy of ReconnectCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReconnectCommandCopyWith<ReconnectCommand> get copyWith => _$ReconnectCommandCopyWithImpl<ReconnectCommand>(this as ReconnectCommand, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReconnectCommand&&(identical(other.closeTimeout, closeTimeout) || other.closeTimeout == closeTimeout)&&(identical(other.transportFactory, transportFactory) || other.transportFactory == transportFactory));
}


@override
int get hashCode => Object.hash(runtimeType,closeTimeout,transportFactory);

@override
String toString() {
  return 'ReconnectCommand(closeTimeout: $closeTimeout, transportFactory: $transportFactory)';
}


}

/// @nodoc
abstract mixin class $ReconnectCommandCopyWith<$Res>  {
  factory $ReconnectCommandCopyWith(ReconnectCommand value, $Res Function(ReconnectCommand) _then) = _$ReconnectCommandCopyWithImpl;
@useResult
$Res call({
 Duration? closeTimeout, AcpTransportFactory? transportFactory
});




}
/// @nodoc
class _$ReconnectCommandCopyWithImpl<$Res>
    implements $ReconnectCommandCopyWith<$Res> {
  _$ReconnectCommandCopyWithImpl(this._self, this._then);

  final ReconnectCommand _self;
  final $Res Function(ReconnectCommand) _then;

/// Create a copy of ReconnectCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? closeTimeout = freezed,Object? transportFactory = freezed,}) {
  return _then(_self.copyWith(
closeTimeout: freezed == closeTimeout ? _self.closeTimeout : closeTimeout // ignore: cast_nullable_to_non_nullable
as Duration?,transportFactory: freezed == transportFactory ? _self.transportFactory : transportFactory // ignore: cast_nullable_to_non_nullable
as AcpTransportFactory?,
  ));
}

}


/// Adds pattern-matching-related methods to [ReconnectCommand].
extension ReconnectCommandPatterns on ReconnectCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReconnectCommand value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReconnectCommand() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReconnectCommand value)  $default,){
final _that = this;
switch (_that) {
case _ReconnectCommand():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReconnectCommand value)?  $default,){
final _that = this;
switch (_that) {
case _ReconnectCommand() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Duration? closeTimeout,  AcpTransportFactory? transportFactory)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReconnectCommand() when $default != null:
return $default(_that.closeTimeout,_that.transportFactory);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Duration? closeTimeout,  AcpTransportFactory? transportFactory)  $default,) {final _that = this;
switch (_that) {
case _ReconnectCommand():
return $default(_that.closeTimeout,_that.transportFactory);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Duration? closeTimeout,  AcpTransportFactory? transportFactory)?  $default,) {final _that = this;
switch (_that) {
case _ReconnectCommand() when $default != null:
return $default(_that.closeTimeout,_that.transportFactory);case _:
  return null;

}
}

}

/// @nodoc


class _ReconnectCommand extends ReconnectCommand {
  const _ReconnectCommand({this.closeTimeout, this.transportFactory}): super._();
  

@override final  Duration? closeTimeout;
@override final  AcpTransportFactory? transportFactory;

/// Create a copy of ReconnectCommand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReconnectCommandCopyWith<_ReconnectCommand> get copyWith => __$ReconnectCommandCopyWithImpl<_ReconnectCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReconnectCommand&&(identical(other.closeTimeout, closeTimeout) || other.closeTimeout == closeTimeout)&&(identical(other.transportFactory, transportFactory) || other.transportFactory == transportFactory));
}


@override
int get hashCode => Object.hash(runtimeType,closeTimeout,transportFactory);

@override
String toString() {
  return 'ReconnectCommand(closeTimeout: $closeTimeout, transportFactory: $transportFactory)';
}


}

/// @nodoc
abstract mixin class _$ReconnectCommandCopyWith<$Res> implements $ReconnectCommandCopyWith<$Res> {
  factory _$ReconnectCommandCopyWith(_ReconnectCommand value, $Res Function(_ReconnectCommand) _then) = __$ReconnectCommandCopyWithImpl;
@override @useResult
$Res call({
 Duration? closeTimeout, AcpTransportFactory? transportFactory
});




}
/// @nodoc
class __$ReconnectCommandCopyWithImpl<$Res>
    implements _$ReconnectCommandCopyWith<$Res> {
  __$ReconnectCommandCopyWithImpl(this._self, this._then);

  final _ReconnectCommand _self;
  final $Res Function(_ReconnectCommand) _then;

/// Create a copy of ReconnectCommand
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? closeTimeout = freezed,Object? transportFactory = freezed,}) {
  return _then(_ReconnectCommand(
closeTimeout: freezed == closeTimeout ? _self.closeTimeout : closeTimeout // ignore: cast_nullable_to_non_nullable
as Duration?,transportFactory: freezed == transportFactory ? _self.transportFactory : transportFactory // ignore: cast_nullable_to_non_nullable
as AcpTransportFactory?,
  ));
}


}

/// @nodoc
mixin _$SetSessionConfigOptionCommand {

 SessionId get sessionId; SessionConfigId get configId; SessionConfigValueId get value; Map<String, Object?>? get meta;
/// Create a copy of SetSessionConfigOptionCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetSessionConfigOptionCommandCopyWith<SetSessionConfigOptionCommand> get copyWith => _$SetSessionConfigOptionCommandCopyWithImpl<SetSessionConfigOptionCommand>(this as SetSessionConfigOptionCommand, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SetSessionConfigOptionCommand&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.configId, configId) || other.configId == configId)&&(identical(other.value, value) || other.value == value)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,configId,value,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'SetSessionConfigOptionCommand(sessionId: $sessionId, configId: $configId, value: $value, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $SetSessionConfigOptionCommandCopyWith<$Res>  {
  factory $SetSessionConfigOptionCommandCopyWith(SetSessionConfigOptionCommand value, $Res Function(SetSessionConfigOptionCommand) _then) = _$SetSessionConfigOptionCommandCopyWithImpl;
@useResult
$Res call({
 SessionId sessionId, SessionConfigId configId, SessionConfigValueId value, Map<String, Object?>? meta
});


$SessionIdCopyWith<$Res> get sessionId;$SessionConfigIdCopyWith<$Res> get configId;$SessionConfigValueIdCopyWith<$Res> get value;

}
/// @nodoc
class _$SetSessionConfigOptionCommandCopyWithImpl<$Res>
    implements $SetSessionConfigOptionCommandCopyWith<$Res> {
  _$SetSessionConfigOptionCommandCopyWithImpl(this._self, this._then);

  final SetSessionConfigOptionCommand _self;
  final $Res Function(SetSessionConfigOptionCommand) _then;

/// Create a copy of SetSessionConfigOptionCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? configId = null,Object? value = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,configId: null == configId ? _self.configId : configId // ignore: cast_nullable_to_non_nullable
as SessionConfigId,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SessionConfigValueId,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}
/// Create a copy of SetSessionConfigOptionCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}/// Create a copy of SetSessionConfigOptionCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionConfigIdCopyWith<$Res> get configId {
  
  return $SessionConfigIdCopyWith<$Res>(_self.configId, (value) {
    return _then(_self.copyWith(configId: value));
  });
}/// Create a copy of SetSessionConfigOptionCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionConfigValueIdCopyWith<$Res> get value {
  
  return $SessionConfigValueIdCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [SetSessionConfigOptionCommand].
extension SetSessionConfigOptionCommandPatterns on SetSessionConfigOptionCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SetSessionConfigOptionCommand value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SetSessionConfigOptionCommand() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SetSessionConfigOptionCommand value)  $default,){
final _that = this;
switch (_that) {
case _SetSessionConfigOptionCommand():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SetSessionConfigOptionCommand value)?  $default,){
final _that = this;
switch (_that) {
case _SetSessionConfigOptionCommand() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionId sessionId,  SessionConfigId configId,  SessionConfigValueId value,  Map<String, Object?>? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SetSessionConfigOptionCommand() when $default != null:
return $default(_that.sessionId,_that.configId,_that.value,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionId sessionId,  SessionConfigId configId,  SessionConfigValueId value,  Map<String, Object?>? meta)  $default,) {final _that = this;
switch (_that) {
case _SetSessionConfigOptionCommand():
return $default(_that.sessionId,_that.configId,_that.value,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionId sessionId,  SessionConfigId configId,  SessionConfigValueId value,  Map<String, Object?>? meta)?  $default,) {final _that = this;
switch (_that) {
case _SetSessionConfigOptionCommand() when $default != null:
return $default(_that.sessionId,_that.configId,_that.value,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _SetSessionConfigOptionCommand extends SetSessionConfigOptionCommand {
  const _SetSessionConfigOptionCommand({required this.sessionId, required this.configId, required this.value, final  Map<String, Object?>? meta}): _meta = meta,super._();
  

@override final  SessionId sessionId;
@override final  SessionConfigId configId;
@override final  SessionConfigValueId value;
 final  Map<String, Object?>? _meta;
@override Map<String, Object?>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of SetSessionConfigOptionCommand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SetSessionConfigOptionCommandCopyWith<_SetSessionConfigOptionCommand> get copyWith => __$SetSessionConfigOptionCommandCopyWithImpl<_SetSessionConfigOptionCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SetSessionConfigOptionCommand&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.configId, configId) || other.configId == configId)&&(identical(other.value, value) || other.value == value)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,configId,value,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'SetSessionConfigOptionCommand(sessionId: $sessionId, configId: $configId, value: $value, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$SetSessionConfigOptionCommandCopyWith<$Res> implements $SetSessionConfigOptionCommandCopyWith<$Res> {
  factory _$SetSessionConfigOptionCommandCopyWith(_SetSessionConfigOptionCommand value, $Res Function(_SetSessionConfigOptionCommand) _then) = __$SetSessionConfigOptionCommandCopyWithImpl;
@override @useResult
$Res call({
 SessionId sessionId, SessionConfigId configId, SessionConfigValueId value, Map<String, Object?>? meta
});


@override $SessionIdCopyWith<$Res> get sessionId;@override $SessionConfigIdCopyWith<$Res> get configId;@override $SessionConfigValueIdCopyWith<$Res> get value;

}
/// @nodoc
class __$SetSessionConfigOptionCommandCopyWithImpl<$Res>
    implements _$SetSessionConfigOptionCommandCopyWith<$Res> {
  __$SetSessionConfigOptionCommandCopyWithImpl(this._self, this._then);

  final _SetSessionConfigOptionCommand _self;
  final $Res Function(_SetSessionConfigOptionCommand) _then;

/// Create a copy of SetSessionConfigOptionCommand
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? configId = null,Object? value = null,Object? meta = freezed,}) {
  return _then(_SetSessionConfigOptionCommand(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,configId: null == configId ? _self.configId : configId // ignore: cast_nullable_to_non_nullable
as SessionConfigId,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SessionConfigValueId,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}

/// Create a copy of SetSessionConfigOptionCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}/// Create a copy of SetSessionConfigOptionCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionConfigIdCopyWith<$Res> get configId {
  
  return $SessionConfigIdCopyWith<$Res>(_self.configId, (value) {
    return _then(_self.copyWith(configId: value));
  });
}/// Create a copy of SetSessionConfigOptionCommand
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
mixin _$RespondToPermissionCommand {

 SessionId get sessionId; ApprovalRequestId get approvalId; Map<String, Object?>? get meta;
/// Create a copy of RespondToPermissionCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RespondToPermissionCommandCopyWith<RespondToPermissionCommand> get copyWith => _$RespondToPermissionCommandCopyWithImpl<RespondToPermissionCommand>(this as RespondToPermissionCommand, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RespondToPermissionCommand&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.approvalId, approvalId) || other.approvalId == approvalId)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,approvalId,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'RespondToPermissionCommand(sessionId: $sessionId, approvalId: $approvalId, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $RespondToPermissionCommandCopyWith<$Res>  {
  factory $RespondToPermissionCommandCopyWith(RespondToPermissionCommand value, $Res Function(RespondToPermissionCommand) _then) = _$RespondToPermissionCommandCopyWithImpl;
@useResult
$Res call({
 SessionId sessionId, ApprovalRequestId approvalId, Map<String, Object?>? meta
});


$SessionIdCopyWith<$Res> get sessionId;$ApprovalRequestIdCopyWith<$Res> get approvalId;

}
/// @nodoc
class _$RespondToPermissionCommandCopyWithImpl<$Res>
    implements $RespondToPermissionCommandCopyWith<$Res> {
  _$RespondToPermissionCommandCopyWithImpl(this._self, this._then);

  final RespondToPermissionCommand _self;
  final $Res Function(RespondToPermissionCommand) _then;

/// Create a copy of RespondToPermissionCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? approvalId = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,approvalId: null == approvalId ? _self.approvalId : approvalId // ignore: cast_nullable_to_non_nullable
as ApprovalRequestId,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}
/// Create a copy of RespondToPermissionCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}/// Create a copy of RespondToPermissionCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ApprovalRequestIdCopyWith<$Res> get approvalId {
  
  return $ApprovalRequestIdCopyWith<$Res>(_self.approvalId, (value) {
    return _then(_self.copyWith(approvalId: value));
  });
}
}


/// Adds pattern-matching-related methods to [RespondToPermissionCommand].
extension RespondToPermissionCommandPatterns on RespondToPermissionCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SelectPermissionCommand value)?  selected,TResult Function( CancelPermissionCommand value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SelectPermissionCommand() when selected != null:
return selected(_that);case CancelPermissionCommand() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SelectPermissionCommand value)  selected,required TResult Function( CancelPermissionCommand value)  cancelled,}){
final _that = this;
switch (_that) {
case SelectPermissionCommand():
return selected(_that);case CancelPermissionCommand():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SelectPermissionCommand value)?  selected,TResult? Function( CancelPermissionCommand value)?  cancelled,}){
final _that = this;
switch (_that) {
case SelectPermissionCommand() when selected != null:
return selected(_that);case CancelPermissionCommand() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( SessionId sessionId,  ApprovalRequestId approvalId,  PermissionOptionId optionId,  Map<String, Object?>? meta)?  selected,TResult Function( SessionId sessionId,  ApprovalRequestId approvalId,  Map<String, Object?>? meta)?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SelectPermissionCommand() when selected != null:
return selected(_that.sessionId,_that.approvalId,_that.optionId,_that.meta);case CancelPermissionCommand() when cancelled != null:
return cancelled(_that.sessionId,_that.approvalId,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( SessionId sessionId,  ApprovalRequestId approvalId,  PermissionOptionId optionId,  Map<String, Object?>? meta)  selected,required TResult Function( SessionId sessionId,  ApprovalRequestId approvalId,  Map<String, Object?>? meta)  cancelled,}) {final _that = this;
switch (_that) {
case SelectPermissionCommand():
return selected(_that.sessionId,_that.approvalId,_that.optionId,_that.meta);case CancelPermissionCommand():
return cancelled(_that.sessionId,_that.approvalId,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( SessionId sessionId,  ApprovalRequestId approvalId,  PermissionOptionId optionId,  Map<String, Object?>? meta)?  selected,TResult? Function( SessionId sessionId,  ApprovalRequestId approvalId,  Map<String, Object?>? meta)?  cancelled,}) {final _that = this;
switch (_that) {
case SelectPermissionCommand() when selected != null:
return selected(_that.sessionId,_that.approvalId,_that.optionId,_that.meta);case CancelPermissionCommand() when cancelled != null:
return cancelled(_that.sessionId,_that.approvalId,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class SelectPermissionCommand extends RespondToPermissionCommand {
  const SelectPermissionCommand({required this.sessionId, required this.approvalId, required this.optionId, final  Map<String, Object?>? meta}): _meta = meta,super._();
  

@override final  SessionId sessionId;
@override final  ApprovalRequestId approvalId;
 final  PermissionOptionId optionId;
 final  Map<String, Object?>? _meta;
@override Map<String, Object?>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of RespondToPermissionCommand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SelectPermissionCommandCopyWith<SelectPermissionCommand> get copyWith => _$SelectPermissionCommandCopyWithImpl<SelectPermissionCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SelectPermissionCommand&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.approvalId, approvalId) || other.approvalId == approvalId)&&(identical(other.optionId, optionId) || other.optionId == optionId)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,approvalId,optionId,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'RespondToPermissionCommand.selected(sessionId: $sessionId, approvalId: $approvalId, optionId: $optionId, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $SelectPermissionCommandCopyWith<$Res> implements $RespondToPermissionCommandCopyWith<$Res> {
  factory $SelectPermissionCommandCopyWith(SelectPermissionCommand value, $Res Function(SelectPermissionCommand) _then) = _$SelectPermissionCommandCopyWithImpl;
@override @useResult
$Res call({
 SessionId sessionId, ApprovalRequestId approvalId, PermissionOptionId optionId, Map<String, Object?>? meta
});


@override $SessionIdCopyWith<$Res> get sessionId;@override $ApprovalRequestIdCopyWith<$Res> get approvalId;$PermissionOptionIdCopyWith<$Res> get optionId;

}
/// @nodoc
class _$SelectPermissionCommandCopyWithImpl<$Res>
    implements $SelectPermissionCommandCopyWith<$Res> {
  _$SelectPermissionCommandCopyWithImpl(this._self, this._then);

  final SelectPermissionCommand _self;
  final $Res Function(SelectPermissionCommand) _then;

/// Create a copy of RespondToPermissionCommand
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? approvalId = null,Object? optionId = null,Object? meta = freezed,}) {
  return _then(SelectPermissionCommand(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,approvalId: null == approvalId ? _self.approvalId : approvalId // ignore: cast_nullable_to_non_nullable
as ApprovalRequestId,optionId: null == optionId ? _self.optionId : optionId // ignore: cast_nullable_to_non_nullable
as PermissionOptionId,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}

/// Create a copy of RespondToPermissionCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}/// Create a copy of RespondToPermissionCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ApprovalRequestIdCopyWith<$Res> get approvalId {
  
  return $ApprovalRequestIdCopyWith<$Res>(_self.approvalId, (value) {
    return _then(_self.copyWith(approvalId: value));
  });
}/// Create a copy of RespondToPermissionCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PermissionOptionIdCopyWith<$Res> get optionId {
  
  return $PermissionOptionIdCopyWith<$Res>(_self.optionId, (value) {
    return _then(_self.copyWith(optionId: value));
  });
}
}

/// @nodoc


class CancelPermissionCommand extends RespondToPermissionCommand {
  const CancelPermissionCommand({required this.sessionId, required this.approvalId, final  Map<String, Object?>? meta}): _meta = meta,super._();
  

@override final  SessionId sessionId;
@override final  ApprovalRequestId approvalId;
 final  Map<String, Object?>? _meta;
@override Map<String, Object?>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of RespondToPermissionCommand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelPermissionCommandCopyWith<CancelPermissionCommand> get copyWith => _$CancelPermissionCommandCopyWithImpl<CancelPermissionCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelPermissionCommand&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.approvalId, approvalId) || other.approvalId == approvalId)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,approvalId,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'RespondToPermissionCommand.cancelled(sessionId: $sessionId, approvalId: $approvalId, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $CancelPermissionCommandCopyWith<$Res> implements $RespondToPermissionCommandCopyWith<$Res> {
  factory $CancelPermissionCommandCopyWith(CancelPermissionCommand value, $Res Function(CancelPermissionCommand) _then) = _$CancelPermissionCommandCopyWithImpl;
@override @useResult
$Res call({
 SessionId sessionId, ApprovalRequestId approvalId, Map<String, Object?>? meta
});


@override $SessionIdCopyWith<$Res> get sessionId;@override $ApprovalRequestIdCopyWith<$Res> get approvalId;

}
/// @nodoc
class _$CancelPermissionCommandCopyWithImpl<$Res>
    implements $CancelPermissionCommandCopyWith<$Res> {
  _$CancelPermissionCommandCopyWithImpl(this._self, this._then);

  final CancelPermissionCommand _self;
  final $Res Function(CancelPermissionCommand) _then;

/// Create a copy of RespondToPermissionCommand
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? approvalId = null,Object? meta = freezed,}) {
  return _then(CancelPermissionCommand(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,approvalId: null == approvalId ? _self.approvalId : approvalId // ignore: cast_nullable_to_non_nullable
as ApprovalRequestId,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}

/// Create a copy of RespondToPermissionCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}/// Create a copy of RespondToPermissionCommand
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ApprovalRequestIdCopyWith<$Res> get approvalId {
  
  return $ApprovalRequestIdCopyWith<$Res>(_self.approvalId, (value) {
    return _then(_self.copyWith(approvalId: value));
  });
}
}

/// @nodoc
mixin _$AcpClientApplicationFailure {

 String get message; Object? get cause;
/// Create a copy of AcpClientApplicationFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpClientApplicationFailureCopyWith<AcpClientApplicationFailure> get copyWith => _$AcpClientApplicationFailureCopyWithImpl<AcpClientApplicationFailure>(this as AcpClientApplicationFailure, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpClientApplicationFailure&&(identical(other.message, message) || other.message == message)&&const DeepCollectionEquality().equals(other.cause, cause));
}


@override
int get hashCode => Object.hash(runtimeType,message,const DeepCollectionEquality().hash(cause));

@override
String toString() {
  return 'AcpClientApplicationFailure(message: $message, cause: $cause)';
}


}

/// @nodoc
abstract mixin class $AcpClientApplicationFailureCopyWith<$Res>  {
  factory $AcpClientApplicationFailureCopyWith(AcpClientApplicationFailure value, $Res Function(AcpClientApplicationFailure) _then) = _$AcpClientApplicationFailureCopyWithImpl;
@useResult
$Res call({
 String message, Object? cause
});




}
/// @nodoc
class _$AcpClientApplicationFailureCopyWithImpl<$Res>
    implements $AcpClientApplicationFailureCopyWith<$Res> {
  _$AcpClientApplicationFailureCopyWithImpl(this._self, this._then);

  final AcpClientApplicationFailure _self;
  final $Res Function(AcpClientApplicationFailure) _then;

/// Create a copy of AcpClientApplicationFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? message = null,Object? cause = freezed,}) {
  return _then(_self.copyWith(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,cause: freezed == cause ? _self.cause : cause ,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpClientApplicationFailure].
extension AcpClientApplicationFailurePatterns on AcpClientApplicationFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AcpClientTransportFailure value)?  transport,TResult Function( AcpClientProtocolFailure value)?  protocol,TResult Function( AcpClientStateRejectedFailure value)?  stateRejected,TResult Function( AcpClientMissingSessionFailure value)?  missingSession,TResult Function( AcpClientUnexpectedFailure value)?  unexpected,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AcpClientTransportFailure() when transport != null:
return transport(_that);case AcpClientProtocolFailure() when protocol != null:
return protocol(_that);case AcpClientStateRejectedFailure() when stateRejected != null:
return stateRejected(_that);case AcpClientMissingSessionFailure() when missingSession != null:
return missingSession(_that);case AcpClientUnexpectedFailure() when unexpected != null:
return unexpected(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AcpClientTransportFailure value)  transport,required TResult Function( AcpClientProtocolFailure value)  protocol,required TResult Function( AcpClientStateRejectedFailure value)  stateRejected,required TResult Function( AcpClientMissingSessionFailure value)  missingSession,required TResult Function( AcpClientUnexpectedFailure value)  unexpected,}){
final _that = this;
switch (_that) {
case AcpClientTransportFailure():
return transport(_that);case AcpClientProtocolFailure():
return protocol(_that);case AcpClientStateRejectedFailure():
return stateRejected(_that);case AcpClientMissingSessionFailure():
return missingSession(_that);case AcpClientUnexpectedFailure():
return unexpected(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AcpClientTransportFailure value)?  transport,TResult? Function( AcpClientProtocolFailure value)?  protocol,TResult? Function( AcpClientStateRejectedFailure value)?  stateRejected,TResult? Function( AcpClientMissingSessionFailure value)?  missingSession,TResult? Function( AcpClientUnexpectedFailure value)?  unexpected,}){
final _that = this;
switch (_that) {
case AcpClientTransportFailure() when transport != null:
return transport(_that);case AcpClientProtocolFailure() when protocol != null:
return protocol(_that);case AcpClientStateRejectedFailure() when stateRejected != null:
return stateRejected(_that);case AcpClientMissingSessionFailure() when missingSession != null:
return missingSession(_that);case AcpClientUnexpectedFailure() when unexpected != null:
return unexpected(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String message,  AcpTransportErrorCode? code,  Object? cause)?  transport,TResult Function( String message,  Object? cause)?  protocol,TResult Function( String message,  Object? cause)?  stateRejected,TResult Function( SessionId sessionId,  String message,  Object? cause)?  missingSession,TResult Function( String message,  Object? cause)?  unexpected,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AcpClientTransportFailure() when transport != null:
return transport(_that.message,_that.code,_that.cause);case AcpClientProtocolFailure() when protocol != null:
return protocol(_that.message,_that.cause);case AcpClientStateRejectedFailure() when stateRejected != null:
return stateRejected(_that.message,_that.cause);case AcpClientMissingSessionFailure() when missingSession != null:
return missingSession(_that.sessionId,_that.message,_that.cause);case AcpClientUnexpectedFailure() when unexpected != null:
return unexpected(_that.message,_that.cause);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String message,  AcpTransportErrorCode? code,  Object? cause)  transport,required TResult Function( String message,  Object? cause)  protocol,required TResult Function( String message,  Object? cause)  stateRejected,required TResult Function( SessionId sessionId,  String message,  Object? cause)  missingSession,required TResult Function( String message,  Object? cause)  unexpected,}) {final _that = this;
switch (_that) {
case AcpClientTransportFailure():
return transport(_that.message,_that.code,_that.cause);case AcpClientProtocolFailure():
return protocol(_that.message,_that.cause);case AcpClientStateRejectedFailure():
return stateRejected(_that.message,_that.cause);case AcpClientMissingSessionFailure():
return missingSession(_that.sessionId,_that.message,_that.cause);case AcpClientUnexpectedFailure():
return unexpected(_that.message,_that.cause);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String message,  AcpTransportErrorCode? code,  Object? cause)?  transport,TResult? Function( String message,  Object? cause)?  protocol,TResult? Function( String message,  Object? cause)?  stateRejected,TResult? Function( SessionId sessionId,  String message,  Object? cause)?  missingSession,TResult? Function( String message,  Object? cause)?  unexpected,}) {final _that = this;
switch (_that) {
case AcpClientTransportFailure() when transport != null:
return transport(_that.message,_that.code,_that.cause);case AcpClientProtocolFailure() when protocol != null:
return protocol(_that.message,_that.cause);case AcpClientStateRejectedFailure() when stateRejected != null:
return stateRejected(_that.message,_that.cause);case AcpClientMissingSessionFailure() when missingSession != null:
return missingSession(_that.sessionId,_that.message,_that.cause);case AcpClientUnexpectedFailure() when unexpected != null:
return unexpected(_that.message,_that.cause);case _:
  return null;

}
}

}

/// @nodoc


class AcpClientTransportFailure extends AcpClientApplicationFailure {
  const AcpClientTransportFailure({required this.message, this.code, this.cause}): super._();
  

@override final  String message;
 final  AcpTransportErrorCode? code;
@override final  Object? cause;

/// Create a copy of AcpClientApplicationFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpClientTransportFailureCopyWith<AcpClientTransportFailure> get copyWith => _$AcpClientTransportFailureCopyWithImpl<AcpClientTransportFailure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpClientTransportFailure&&(identical(other.message, message) || other.message == message)&&(identical(other.code, code) || other.code == code)&&const DeepCollectionEquality().equals(other.cause, cause));
}


@override
int get hashCode => Object.hash(runtimeType,message,code,const DeepCollectionEquality().hash(cause));

@override
String toString() {
  return 'AcpClientApplicationFailure.transport(message: $message, code: $code, cause: $cause)';
}


}

/// @nodoc
abstract mixin class $AcpClientTransportFailureCopyWith<$Res> implements $AcpClientApplicationFailureCopyWith<$Res> {
  factory $AcpClientTransportFailureCopyWith(AcpClientTransportFailure value, $Res Function(AcpClientTransportFailure) _then) = _$AcpClientTransportFailureCopyWithImpl;
@override @useResult
$Res call({
 String message, AcpTransportErrorCode? code, Object? cause
});




}
/// @nodoc
class _$AcpClientTransportFailureCopyWithImpl<$Res>
    implements $AcpClientTransportFailureCopyWith<$Res> {
  _$AcpClientTransportFailureCopyWithImpl(this._self, this._then);

  final AcpClientTransportFailure _self;
  final $Res Function(AcpClientTransportFailure) _then;

/// Create a copy of AcpClientApplicationFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? code = freezed,Object? cause = freezed,}) {
  return _then(AcpClientTransportFailure(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as AcpTransportErrorCode?,cause: freezed == cause ? _self.cause : cause ,
  ));
}


}

/// @nodoc


class AcpClientProtocolFailure extends AcpClientApplicationFailure {
  const AcpClientProtocolFailure({required this.message, this.cause}): super._();
  

@override final  String message;
@override final  Object? cause;

/// Create a copy of AcpClientApplicationFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpClientProtocolFailureCopyWith<AcpClientProtocolFailure> get copyWith => _$AcpClientProtocolFailureCopyWithImpl<AcpClientProtocolFailure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpClientProtocolFailure&&(identical(other.message, message) || other.message == message)&&const DeepCollectionEquality().equals(other.cause, cause));
}


@override
int get hashCode => Object.hash(runtimeType,message,const DeepCollectionEquality().hash(cause));

@override
String toString() {
  return 'AcpClientApplicationFailure.protocol(message: $message, cause: $cause)';
}


}

/// @nodoc
abstract mixin class $AcpClientProtocolFailureCopyWith<$Res> implements $AcpClientApplicationFailureCopyWith<$Res> {
  factory $AcpClientProtocolFailureCopyWith(AcpClientProtocolFailure value, $Res Function(AcpClientProtocolFailure) _then) = _$AcpClientProtocolFailureCopyWithImpl;
@override @useResult
$Res call({
 String message, Object? cause
});




}
/// @nodoc
class _$AcpClientProtocolFailureCopyWithImpl<$Res>
    implements $AcpClientProtocolFailureCopyWith<$Res> {
  _$AcpClientProtocolFailureCopyWithImpl(this._self, this._then);

  final AcpClientProtocolFailure _self;
  final $Res Function(AcpClientProtocolFailure) _then;

/// Create a copy of AcpClientApplicationFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? cause = freezed,}) {
  return _then(AcpClientProtocolFailure(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,cause: freezed == cause ? _self.cause : cause ,
  ));
}


}

/// @nodoc


class AcpClientStateRejectedFailure extends AcpClientApplicationFailure {
  const AcpClientStateRejectedFailure({required this.message, this.cause}): super._();
  

@override final  String message;
@override final  Object? cause;

/// Create a copy of AcpClientApplicationFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpClientStateRejectedFailureCopyWith<AcpClientStateRejectedFailure> get copyWith => _$AcpClientStateRejectedFailureCopyWithImpl<AcpClientStateRejectedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpClientStateRejectedFailure&&(identical(other.message, message) || other.message == message)&&const DeepCollectionEquality().equals(other.cause, cause));
}


@override
int get hashCode => Object.hash(runtimeType,message,const DeepCollectionEquality().hash(cause));

@override
String toString() {
  return 'AcpClientApplicationFailure.stateRejected(message: $message, cause: $cause)';
}


}

/// @nodoc
abstract mixin class $AcpClientStateRejectedFailureCopyWith<$Res> implements $AcpClientApplicationFailureCopyWith<$Res> {
  factory $AcpClientStateRejectedFailureCopyWith(AcpClientStateRejectedFailure value, $Res Function(AcpClientStateRejectedFailure) _then) = _$AcpClientStateRejectedFailureCopyWithImpl;
@override @useResult
$Res call({
 String message, Object? cause
});




}
/// @nodoc
class _$AcpClientStateRejectedFailureCopyWithImpl<$Res>
    implements $AcpClientStateRejectedFailureCopyWith<$Res> {
  _$AcpClientStateRejectedFailureCopyWithImpl(this._self, this._then);

  final AcpClientStateRejectedFailure _self;
  final $Res Function(AcpClientStateRejectedFailure) _then;

/// Create a copy of AcpClientApplicationFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? cause = freezed,}) {
  return _then(AcpClientStateRejectedFailure(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,cause: freezed == cause ? _self.cause : cause ,
  ));
}


}

/// @nodoc


class AcpClientMissingSessionFailure extends AcpClientApplicationFailure {
  const AcpClientMissingSessionFailure({required this.sessionId, required this.message, this.cause}): super._();
  

 final  SessionId sessionId;
@override final  String message;
@override final  Object? cause;

/// Create a copy of AcpClientApplicationFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpClientMissingSessionFailureCopyWith<AcpClientMissingSessionFailure> get copyWith => _$AcpClientMissingSessionFailureCopyWithImpl<AcpClientMissingSessionFailure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpClientMissingSessionFailure&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.message, message) || other.message == message)&&const DeepCollectionEquality().equals(other.cause, cause));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,message,const DeepCollectionEquality().hash(cause));

@override
String toString() {
  return 'AcpClientApplicationFailure.missingSession(sessionId: $sessionId, message: $message, cause: $cause)';
}


}

/// @nodoc
abstract mixin class $AcpClientMissingSessionFailureCopyWith<$Res> implements $AcpClientApplicationFailureCopyWith<$Res> {
  factory $AcpClientMissingSessionFailureCopyWith(AcpClientMissingSessionFailure value, $Res Function(AcpClientMissingSessionFailure) _then) = _$AcpClientMissingSessionFailureCopyWithImpl;
@override @useResult
$Res call({
 SessionId sessionId, String message, Object? cause
});


$SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class _$AcpClientMissingSessionFailureCopyWithImpl<$Res>
    implements $AcpClientMissingSessionFailureCopyWith<$Res> {
  _$AcpClientMissingSessionFailureCopyWithImpl(this._self, this._then);

  final AcpClientMissingSessionFailure _self;
  final $Res Function(AcpClientMissingSessionFailure) _then;

/// Create a copy of AcpClientApplicationFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? message = null,Object? cause = freezed,}) {
  return _then(AcpClientMissingSessionFailure(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,cause: freezed == cause ? _self.cause : cause ,
  ));
}

/// Create a copy of AcpClientApplicationFailure
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


class AcpClientUnexpectedFailure extends AcpClientApplicationFailure {
  const AcpClientUnexpectedFailure({required this.message, this.cause}): super._();
  

@override final  String message;
@override final  Object? cause;

/// Create a copy of AcpClientApplicationFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpClientUnexpectedFailureCopyWith<AcpClientUnexpectedFailure> get copyWith => _$AcpClientUnexpectedFailureCopyWithImpl<AcpClientUnexpectedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpClientUnexpectedFailure&&(identical(other.message, message) || other.message == message)&&const DeepCollectionEquality().equals(other.cause, cause));
}


@override
int get hashCode => Object.hash(runtimeType,message,const DeepCollectionEquality().hash(cause));

@override
String toString() {
  return 'AcpClientApplicationFailure.unexpected(message: $message, cause: $cause)';
}


}

/// @nodoc
abstract mixin class $AcpClientUnexpectedFailureCopyWith<$Res> implements $AcpClientApplicationFailureCopyWith<$Res> {
  factory $AcpClientUnexpectedFailureCopyWith(AcpClientUnexpectedFailure value, $Res Function(AcpClientUnexpectedFailure) _then) = _$AcpClientUnexpectedFailureCopyWithImpl;
@override @useResult
$Res call({
 String message, Object? cause
});




}
/// @nodoc
class _$AcpClientUnexpectedFailureCopyWithImpl<$Res>
    implements $AcpClientUnexpectedFailureCopyWith<$Res> {
  _$AcpClientUnexpectedFailureCopyWithImpl(this._self, this._then);

  final AcpClientUnexpectedFailure _self;
  final $Res Function(AcpClientUnexpectedFailure) _then;

/// Create a copy of AcpClientApplicationFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? cause = freezed,}) {
  return _then(AcpClientUnexpectedFailure(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,cause: freezed == cause ? _self.cause : cause ,
  ));
}


}

// dart format on
