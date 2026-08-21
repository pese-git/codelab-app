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
