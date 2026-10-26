// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'state_machines.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StateTransitionResult<T> {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StateTransitionResult<T>);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'StateTransitionResult<$T>()';
}


}

/// @nodoc
class $StateTransitionResultCopyWith<T,$Res>  {
$StateTransitionResultCopyWith(StateTransitionResult<T> _, $Res Function(StateTransitionResult<T>) __);
}


/// Adds pattern-matching-related methods to [StateTransitionResult].
extension StateTransitionResultPatterns<T> on StateTransitionResult<T> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AppliedStateTransition<T> value)?  applied,TResult Function( IgnoredStateTransition<T> value)?  ignored,TResult Function( RejectedStateTransition<T> value)?  rejected,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AppliedStateTransition() when applied != null:
return applied(_that);case IgnoredStateTransition() when ignored != null:
return ignored(_that);case RejectedStateTransition() when rejected != null:
return rejected(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AppliedStateTransition<T> value)  applied,required TResult Function( IgnoredStateTransition<T> value)  ignored,required TResult Function( RejectedStateTransition<T> value)  rejected,}){
final _that = this;
switch (_that) {
case AppliedStateTransition():
return applied(_that);case IgnoredStateTransition():
return ignored(_that);case RejectedStateTransition():
return rejected(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AppliedStateTransition<T> value)?  applied,TResult? Function( IgnoredStateTransition<T> value)?  ignored,TResult? Function( RejectedStateTransition<T> value)?  rejected,}){
final _that = this;
switch (_that) {
case AppliedStateTransition() when applied != null:
return applied(_that);case IgnoredStateTransition() when ignored != null:
return ignored(_that);case RejectedStateTransition() when rejected != null:
return rejected(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( T state)?  applied,TResult Function( T state,  String reason)?  ignored,TResult Function( String reason)?  rejected,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AppliedStateTransition() when applied != null:
return applied(_that.state);case IgnoredStateTransition() when ignored != null:
return ignored(_that.state,_that.reason);case RejectedStateTransition() when rejected != null:
return rejected(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( T state)  applied,required TResult Function( T state,  String reason)  ignored,required TResult Function( String reason)  rejected,}) {final _that = this;
switch (_that) {
case AppliedStateTransition():
return applied(_that.state);case IgnoredStateTransition():
return ignored(_that.state,_that.reason);case RejectedStateTransition():
return rejected(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( T state)?  applied,TResult? Function( T state,  String reason)?  ignored,TResult? Function( String reason)?  rejected,}) {final _that = this;
switch (_that) {
case AppliedStateTransition() when applied != null:
return applied(_that.state);case IgnoredStateTransition() when ignored != null:
return ignored(_that.state,_that.reason);case RejectedStateTransition() when rejected != null:
return rejected(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class AppliedStateTransition<T> extends StateTransitionResult<T> {
  const AppliedStateTransition({required this.state}): super._();
  

 final  T state;

/// Create a copy of StateTransitionResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppliedStateTransitionCopyWith<T, AppliedStateTransition<T>> get copyWith => _$AppliedStateTransitionCopyWithImpl<T, AppliedStateTransition<T>>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppliedStateTransition<T>&&const DeepCollectionEquality().equals(other.state, state));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(state));

@override
String toString() {
  return 'StateTransitionResult<$T>.applied(state: $state)';
}


}

/// @nodoc
abstract mixin class $AppliedStateTransitionCopyWith<T,$Res> implements $StateTransitionResultCopyWith<T, $Res> {
  factory $AppliedStateTransitionCopyWith(AppliedStateTransition<T> value, $Res Function(AppliedStateTransition<T>) _then) = _$AppliedStateTransitionCopyWithImpl;
@useResult
$Res call({
 T state
});




}
/// @nodoc
class _$AppliedStateTransitionCopyWithImpl<T,$Res>
    implements $AppliedStateTransitionCopyWith<T, $Res> {
  _$AppliedStateTransitionCopyWithImpl(this._self, this._then);

  final AppliedStateTransition<T> _self;
  final $Res Function(AppliedStateTransition<T>) _then;

/// Create a copy of StateTransitionResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? state = freezed,}) {
  return _then(AppliedStateTransition<T>(
state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as T,
  ));
}


}

/// @nodoc


class IgnoredStateTransition<T> extends StateTransitionResult<T> {
  const IgnoredStateTransition({required this.state, required this.reason}): super._();
  

 final  T state;
 final  String reason;

/// Create a copy of StateTransitionResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IgnoredStateTransitionCopyWith<T, IgnoredStateTransition<T>> get copyWith => _$IgnoredStateTransitionCopyWithImpl<T, IgnoredStateTransition<T>>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is IgnoredStateTransition<T>&&const DeepCollectionEquality().equals(other.state, state)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(state),reason);

@override
String toString() {
  return 'StateTransitionResult<$T>.ignored(state: $state, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $IgnoredStateTransitionCopyWith<T,$Res> implements $StateTransitionResultCopyWith<T, $Res> {
  factory $IgnoredStateTransitionCopyWith(IgnoredStateTransition<T> value, $Res Function(IgnoredStateTransition<T>) _then) = _$IgnoredStateTransitionCopyWithImpl;
@useResult
$Res call({
 T state, String reason
});




}
/// @nodoc
class _$IgnoredStateTransitionCopyWithImpl<T,$Res>
    implements $IgnoredStateTransitionCopyWith<T, $Res> {
  _$IgnoredStateTransitionCopyWithImpl(this._self, this._then);

  final IgnoredStateTransition<T> _self;
  final $Res Function(IgnoredStateTransition<T>) _then;

/// Create a copy of StateTransitionResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? state = freezed,Object? reason = null,}) {
  return _then(IgnoredStateTransition<T>(
state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as T,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RejectedStateTransition<T> extends StateTransitionResult<T> {
  const RejectedStateTransition({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of StateTransitionResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RejectedStateTransitionCopyWith<T, RejectedStateTransition<T>> get copyWith => _$RejectedStateTransitionCopyWithImpl<T, RejectedStateTransition<T>>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RejectedStateTransition<T>&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'StateTransitionResult<$T>.rejected(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $RejectedStateTransitionCopyWith<T,$Res> implements $StateTransitionResultCopyWith<T, $Res> {
  factory $RejectedStateTransitionCopyWith(RejectedStateTransition<T> value, $Res Function(RejectedStateTransition<T>) _then) = _$RejectedStateTransitionCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$RejectedStateTransitionCopyWithImpl<T,$Res>
    implements $RejectedStateTransitionCopyWith<T, $Res> {
  _$RejectedStateTransitionCopyWithImpl(this._self, this._then);

  final RejectedStateTransition<T> _self;
  final $Res Function(RejectedStateTransition<T>) _then;

/// Create a copy of StateTransitionResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(RejectedStateTransition<T>(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ConnectionStateEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionStateEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConnectionStateEvent()';
}


}

/// @nodoc
class $ConnectionStateEventCopyWith<$Res>  {
$ConnectionStateEventCopyWith(ConnectionStateEvent _, $Res Function(ConnectionStateEvent) __);
}


/// Adds pattern-matching-related methods to [ConnectionStateEvent].
extension ConnectionStateEventPatterns on ConnectionStateEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ConnectionConnectRequested value)?  connect,TResult Function( ConnectionInitializeRequested value)?  initialize,TResult Function( ConnectionReadyReceived value)?  ready,TResult Function( ConnectionFailureReceived value)?  fail,TResult Function( ConnectionDisconnectReceived value)?  disconnect,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ConnectionConnectRequested() when connect != null:
return connect(_that);case ConnectionInitializeRequested() when initialize != null:
return initialize(_that);case ConnectionReadyReceived() when ready != null:
return ready(_that);case ConnectionFailureReceived() when fail != null:
return fail(_that);case ConnectionDisconnectReceived() when disconnect != null:
return disconnect(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ConnectionConnectRequested value)  connect,required TResult Function( ConnectionInitializeRequested value)  initialize,required TResult Function( ConnectionReadyReceived value)  ready,required TResult Function( ConnectionFailureReceived value)  fail,required TResult Function( ConnectionDisconnectReceived value)  disconnect,}){
final _that = this;
switch (_that) {
case ConnectionConnectRequested():
return connect(_that);case ConnectionInitializeRequested():
return initialize(_that);case ConnectionReadyReceived():
return ready(_that);case ConnectionFailureReceived():
return fail(_that);case ConnectionDisconnectReceived():
return disconnect(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ConnectionConnectRequested value)?  connect,TResult? Function( ConnectionInitializeRequested value)?  initialize,TResult? Function( ConnectionReadyReceived value)?  ready,TResult? Function( ConnectionFailureReceived value)?  fail,TResult? Function( ConnectionDisconnectReceived value)?  disconnect,}){
final _that = this;
switch (_that) {
case ConnectionConnectRequested() when connect != null:
return connect(_that);case ConnectionInitializeRequested() when initialize != null:
return initialize(_that);case ConnectionReadyReceived() when ready != null:
return ready(_that);case ConnectionFailureReceived() when fail != null:
return fail(_that);case ConnectionDisconnectReceived() when disconnect != null:
return disconnect(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  connect,TResult Function()?  initialize,TResult Function( ProtocolVersion protocolVersion,  Implementation? agentInfo,  AgentCapabilities capabilities)?  ready,TResult Function( ConnectionFailureReason reason,  String message,  Object? cause)?  fail,TResult Function()?  disconnect,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ConnectionConnectRequested() when connect != null:
return connect();case ConnectionInitializeRequested() when initialize != null:
return initialize();case ConnectionReadyReceived() when ready != null:
return ready(_that.protocolVersion,_that.agentInfo,_that.capabilities);case ConnectionFailureReceived() when fail != null:
return fail(_that.reason,_that.message,_that.cause);case ConnectionDisconnectReceived() when disconnect != null:
return disconnect();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  connect,required TResult Function()  initialize,required TResult Function( ProtocolVersion protocolVersion,  Implementation? agentInfo,  AgentCapabilities capabilities)  ready,required TResult Function( ConnectionFailureReason reason,  String message,  Object? cause)  fail,required TResult Function()  disconnect,}) {final _that = this;
switch (_that) {
case ConnectionConnectRequested():
return connect();case ConnectionInitializeRequested():
return initialize();case ConnectionReadyReceived():
return ready(_that.protocolVersion,_that.agentInfo,_that.capabilities);case ConnectionFailureReceived():
return fail(_that.reason,_that.message,_that.cause);case ConnectionDisconnectReceived():
return disconnect();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  connect,TResult? Function()?  initialize,TResult? Function( ProtocolVersion protocolVersion,  Implementation? agentInfo,  AgentCapabilities capabilities)?  ready,TResult? Function( ConnectionFailureReason reason,  String message,  Object? cause)?  fail,TResult? Function()?  disconnect,}) {final _that = this;
switch (_that) {
case ConnectionConnectRequested() when connect != null:
return connect();case ConnectionInitializeRequested() when initialize != null:
return initialize();case ConnectionReadyReceived() when ready != null:
return ready(_that.protocolVersion,_that.agentInfo,_that.capabilities);case ConnectionFailureReceived() when fail != null:
return fail(_that.reason,_that.message,_that.cause);case ConnectionDisconnectReceived() when disconnect != null:
return disconnect();case _:
  return null;

}
}

}

/// @nodoc


class ConnectionConnectRequested implements ConnectionStateEvent {
  const ConnectionConnectRequested();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionConnectRequested);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConnectionStateEvent.connect()';
}


}




/// @nodoc


class ConnectionInitializeRequested implements ConnectionStateEvent {
  const ConnectionInitializeRequested();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionInitializeRequested);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConnectionStateEvent.initialize()';
}


}




/// @nodoc


class ConnectionReadyReceived implements ConnectionStateEvent {
  const ConnectionReadyReceived({required this.protocolVersion, this.agentInfo, this.capabilities = const AgentCapabilities()});
  

 final  ProtocolVersion protocolVersion;
 final  Implementation? agentInfo;
@JsonKey() final  AgentCapabilities capabilities;

/// Create a copy of ConnectionStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionReadyReceivedCopyWith<ConnectionReadyReceived> get copyWith => _$ConnectionReadyReceivedCopyWithImpl<ConnectionReadyReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionReadyReceived&&(identical(other.protocolVersion, protocolVersion) || other.protocolVersion == protocolVersion)&&(identical(other.agentInfo, agentInfo) || other.agentInfo == agentInfo)&&(identical(other.capabilities, capabilities) || other.capabilities == capabilities));
}


@override
int get hashCode => Object.hash(runtimeType,protocolVersion,agentInfo,capabilities);

@override
String toString() {
  return 'ConnectionStateEvent.ready(protocolVersion: $protocolVersion, agentInfo: $agentInfo, capabilities: $capabilities)';
}


}

/// @nodoc
abstract mixin class $ConnectionReadyReceivedCopyWith<$Res> implements $ConnectionStateEventCopyWith<$Res> {
  factory $ConnectionReadyReceivedCopyWith(ConnectionReadyReceived value, $Res Function(ConnectionReadyReceived) _then) = _$ConnectionReadyReceivedCopyWithImpl;
@useResult
$Res call({
 ProtocolVersion protocolVersion, Implementation? agentInfo, AgentCapabilities capabilities
});


$ProtocolVersionCopyWith<$Res> get protocolVersion;$ImplementationCopyWith<$Res>? get agentInfo;$AgentCapabilitiesCopyWith<$Res> get capabilities;

}
/// @nodoc
class _$ConnectionReadyReceivedCopyWithImpl<$Res>
    implements $ConnectionReadyReceivedCopyWith<$Res> {
  _$ConnectionReadyReceivedCopyWithImpl(this._self, this._then);

  final ConnectionReadyReceived _self;
  final $Res Function(ConnectionReadyReceived) _then;

/// Create a copy of ConnectionStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? protocolVersion = null,Object? agentInfo = freezed,Object? capabilities = null,}) {
  return _then(ConnectionReadyReceived(
protocolVersion: null == protocolVersion ? _self.protocolVersion : protocolVersion // ignore: cast_nullable_to_non_nullable
as ProtocolVersion,agentInfo: freezed == agentInfo ? _self.agentInfo : agentInfo // ignore: cast_nullable_to_non_nullable
as Implementation?,capabilities: null == capabilities ? _self.capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as AgentCapabilities,
  ));
}

/// Create a copy of ConnectionStateEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProtocolVersionCopyWith<$Res> get protocolVersion {
  
  return $ProtocolVersionCopyWith<$Res>(_self.protocolVersion, (value) {
    return _then(_self.copyWith(protocolVersion: value));
  });
}/// Create a copy of ConnectionStateEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ImplementationCopyWith<$Res>? get agentInfo {
    if (_self.agentInfo == null) {
    return null;
  }

  return $ImplementationCopyWith<$Res>(_self.agentInfo!, (value) {
    return _then(_self.copyWith(agentInfo: value));
  });
}/// Create a copy of ConnectionStateEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentCapabilitiesCopyWith<$Res> get capabilities {
  
  return $AgentCapabilitiesCopyWith<$Res>(_self.capabilities, (value) {
    return _then(_self.copyWith(capabilities: value));
  });
}
}

/// @nodoc


class ConnectionFailureReceived implements ConnectionStateEvent {
  const ConnectionFailureReceived({required this.reason, required this.message, this.cause});
  

 final  ConnectionFailureReason reason;
 final  String message;
 final  Object? cause;

/// Create a copy of ConnectionStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionFailureReceivedCopyWith<ConnectionFailureReceived> get copyWith => _$ConnectionFailureReceivedCopyWithImpl<ConnectionFailureReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionFailureReceived&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.message, message) || other.message == message)&&const DeepCollectionEquality().equals(other.cause, cause));
}


@override
int get hashCode => Object.hash(runtimeType,reason,message,const DeepCollectionEquality().hash(cause));

@override
String toString() {
  return 'ConnectionStateEvent.fail(reason: $reason, message: $message, cause: $cause)';
}


}

/// @nodoc
abstract mixin class $ConnectionFailureReceivedCopyWith<$Res> implements $ConnectionStateEventCopyWith<$Res> {
  factory $ConnectionFailureReceivedCopyWith(ConnectionFailureReceived value, $Res Function(ConnectionFailureReceived) _then) = _$ConnectionFailureReceivedCopyWithImpl;
@useResult
$Res call({
 ConnectionFailureReason reason, String message, Object? cause
});




}
/// @nodoc
class _$ConnectionFailureReceivedCopyWithImpl<$Res>
    implements $ConnectionFailureReceivedCopyWith<$Res> {
  _$ConnectionFailureReceivedCopyWithImpl(this._self, this._then);

  final ConnectionFailureReceived _self;
  final $Res Function(ConnectionFailureReceived) _then;

/// Create a copy of ConnectionStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,Object? message = null,Object? cause = freezed,}) {
  return _then(ConnectionFailureReceived(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ConnectionFailureReason,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,cause: freezed == cause ? _self.cause : cause ,
  ));
}


}

/// @nodoc


class ConnectionDisconnectReceived implements ConnectionStateEvent {
  const ConnectionDisconnectReceived();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionDisconnectReceived);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConnectionStateEvent.disconnect()';
}


}




/// @nodoc
mixin _$PromptTurnStateEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptTurnStateEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PromptTurnStateEvent()';
}


}

/// @nodoc
class $PromptTurnStateEventCopyWith<$Res>  {
$PromptTurnStateEventCopyWith(PromptTurnStateEvent _, $Res Function(PromptTurnStateEvent) __);
}


/// Adds pattern-matching-related methods to [PromptTurnStateEvent].
extension PromptTurnStateEventPatterns on PromptTurnStateEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PromptTurnStartRequested value)?  start,TResult Function( PromptTurnUpdateReceived value)?  update,TResult Function( PromptTurnApprovalRequested value)?  requestApproval,TResult Function( PromptTurnApprovalSelected value)?  selectApproval,TResult Function( PromptTurnApprovalCancelled value)?  cancelApproval,TResult Function( PromptTurnCompleted value)?  complete,TResult Function( PromptTurnFailed value)?  fail,TResult Function( PromptTurnCancelled value)?  cancel,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PromptTurnStartRequested() when start != null:
return start(_that);case PromptTurnUpdateReceived() when update != null:
return update(_that);case PromptTurnApprovalRequested() when requestApproval != null:
return requestApproval(_that);case PromptTurnApprovalSelected() when selectApproval != null:
return selectApproval(_that);case PromptTurnApprovalCancelled() when cancelApproval != null:
return cancelApproval(_that);case PromptTurnCompleted() when complete != null:
return complete(_that);case PromptTurnFailed() when fail != null:
return fail(_that);case PromptTurnCancelled() when cancel != null:
return cancel(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PromptTurnStartRequested value)  start,required TResult Function( PromptTurnUpdateReceived value)  update,required TResult Function( PromptTurnApprovalRequested value)  requestApproval,required TResult Function( PromptTurnApprovalSelected value)  selectApproval,required TResult Function( PromptTurnApprovalCancelled value)  cancelApproval,required TResult Function( PromptTurnCompleted value)  complete,required TResult Function( PromptTurnFailed value)  fail,required TResult Function( PromptTurnCancelled value)  cancel,}){
final _that = this;
switch (_that) {
case PromptTurnStartRequested():
return start(_that);case PromptTurnUpdateReceived():
return update(_that);case PromptTurnApprovalRequested():
return requestApproval(_that);case PromptTurnApprovalSelected():
return selectApproval(_that);case PromptTurnApprovalCancelled():
return cancelApproval(_that);case PromptTurnCompleted():
return complete(_that);case PromptTurnFailed():
return fail(_that);case PromptTurnCancelled():
return cancel(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PromptTurnStartRequested value)?  start,TResult? Function( PromptTurnUpdateReceived value)?  update,TResult? Function( PromptTurnApprovalRequested value)?  requestApproval,TResult? Function( PromptTurnApprovalSelected value)?  selectApproval,TResult? Function( PromptTurnApprovalCancelled value)?  cancelApproval,TResult? Function( PromptTurnCompleted value)?  complete,TResult? Function( PromptTurnFailed value)?  fail,TResult? Function( PromptTurnCancelled value)?  cancel,}){
final _that = this;
switch (_that) {
case PromptTurnStartRequested() when start != null:
return start(_that);case PromptTurnUpdateReceived() when update != null:
return update(_that);case PromptTurnApprovalRequested() when requestApproval != null:
return requestApproval(_that);case PromptTurnApprovalSelected() when selectApproval != null:
return selectApproval(_that);case PromptTurnApprovalCancelled() when cancelApproval != null:
return cancelApproval(_that);case PromptTurnCompleted() when complete != null:
return complete(_that);case PromptTurnFailed() when fail != null:
return fail(_that);case PromptTurnCancelled() when cancel != null:
return cancel(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( DateTime? startedAt)?  start,TResult Function( SessionUpdate update)?  update,TResult Function( ApprovalRequest approval)?  requestApproval,TResult Function( ApprovalRequestId approvalId,  PermissionOptionId optionId,  DateTime? resolvedAt)?  selectApproval,TResult Function( ApprovalRequestId approvalId,  DateTime? resolvedAt)?  cancelApproval,TResult Function( StopReason stopReason,  DateTime? completedAt)?  complete,TResult Function( String message,  DateTime? completedAt)?  fail,TResult Function( DateTime? completedAt)?  cancel,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PromptTurnStartRequested() when start != null:
return start(_that.startedAt);case PromptTurnUpdateReceived() when update != null:
return update(_that.update);case PromptTurnApprovalRequested() when requestApproval != null:
return requestApproval(_that.approval);case PromptTurnApprovalSelected() when selectApproval != null:
return selectApproval(_that.approvalId,_that.optionId,_that.resolvedAt);case PromptTurnApprovalCancelled() when cancelApproval != null:
return cancelApproval(_that.approvalId,_that.resolvedAt);case PromptTurnCompleted() when complete != null:
return complete(_that.stopReason,_that.completedAt);case PromptTurnFailed() when fail != null:
return fail(_that.message,_that.completedAt);case PromptTurnCancelled() when cancel != null:
return cancel(_that.completedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( DateTime? startedAt)  start,required TResult Function( SessionUpdate update)  update,required TResult Function( ApprovalRequest approval)  requestApproval,required TResult Function( ApprovalRequestId approvalId,  PermissionOptionId optionId,  DateTime? resolvedAt)  selectApproval,required TResult Function( ApprovalRequestId approvalId,  DateTime? resolvedAt)  cancelApproval,required TResult Function( StopReason stopReason,  DateTime? completedAt)  complete,required TResult Function( String message,  DateTime? completedAt)  fail,required TResult Function( DateTime? completedAt)  cancel,}) {final _that = this;
switch (_that) {
case PromptTurnStartRequested():
return start(_that.startedAt);case PromptTurnUpdateReceived():
return update(_that.update);case PromptTurnApprovalRequested():
return requestApproval(_that.approval);case PromptTurnApprovalSelected():
return selectApproval(_that.approvalId,_that.optionId,_that.resolvedAt);case PromptTurnApprovalCancelled():
return cancelApproval(_that.approvalId,_that.resolvedAt);case PromptTurnCompleted():
return complete(_that.stopReason,_that.completedAt);case PromptTurnFailed():
return fail(_that.message,_that.completedAt);case PromptTurnCancelled():
return cancel(_that.completedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( DateTime? startedAt)?  start,TResult? Function( SessionUpdate update)?  update,TResult? Function( ApprovalRequest approval)?  requestApproval,TResult? Function( ApprovalRequestId approvalId,  PermissionOptionId optionId,  DateTime? resolvedAt)?  selectApproval,TResult? Function( ApprovalRequestId approvalId,  DateTime? resolvedAt)?  cancelApproval,TResult? Function( StopReason stopReason,  DateTime? completedAt)?  complete,TResult? Function( String message,  DateTime? completedAt)?  fail,TResult? Function( DateTime? completedAt)?  cancel,}) {final _that = this;
switch (_that) {
case PromptTurnStartRequested() when start != null:
return start(_that.startedAt);case PromptTurnUpdateReceived() when update != null:
return update(_that.update);case PromptTurnApprovalRequested() when requestApproval != null:
return requestApproval(_that.approval);case PromptTurnApprovalSelected() when selectApproval != null:
return selectApproval(_that.approvalId,_that.optionId,_that.resolvedAt);case PromptTurnApprovalCancelled() when cancelApproval != null:
return cancelApproval(_that.approvalId,_that.resolvedAt);case PromptTurnCompleted() when complete != null:
return complete(_that.stopReason,_that.completedAt);case PromptTurnFailed() when fail != null:
return fail(_that.message,_that.completedAt);case PromptTurnCancelled() when cancel != null:
return cancel(_that.completedAt);case _:
  return null;

}
}

}

/// @nodoc


class PromptTurnStartRequested implements PromptTurnStateEvent {
  const PromptTurnStartRequested({this.startedAt});
  

 final  DateTime? startedAt;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptTurnStartRequestedCopyWith<PromptTurnStartRequested> get copyWith => _$PromptTurnStartRequestedCopyWithImpl<PromptTurnStartRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptTurnStartRequested&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode => Object.hash(runtimeType,startedAt);

@override
String toString() {
  return 'PromptTurnStateEvent.start(startedAt: $startedAt)';
}


}

/// @nodoc
abstract mixin class $PromptTurnStartRequestedCopyWith<$Res> implements $PromptTurnStateEventCopyWith<$Res> {
  factory $PromptTurnStartRequestedCopyWith(PromptTurnStartRequested value, $Res Function(PromptTurnStartRequested) _then) = _$PromptTurnStartRequestedCopyWithImpl;
@useResult
$Res call({
 DateTime? startedAt
});




}
/// @nodoc
class _$PromptTurnStartRequestedCopyWithImpl<$Res>
    implements $PromptTurnStartRequestedCopyWith<$Res> {
  _$PromptTurnStartRequestedCopyWithImpl(this._self, this._then);

  final PromptTurnStartRequested _self;
  final $Res Function(PromptTurnStartRequested) _then;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,}) {
  return _then(PromptTurnStartRequested(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc


class PromptTurnUpdateReceived implements PromptTurnStateEvent {
  const PromptTurnUpdateReceived({required this.update});
  

 final  SessionUpdate update;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptTurnUpdateReceivedCopyWith<PromptTurnUpdateReceived> get copyWith => _$PromptTurnUpdateReceivedCopyWithImpl<PromptTurnUpdateReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptTurnUpdateReceived&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode => Object.hash(runtimeType,update);

@override
String toString() {
  return 'PromptTurnStateEvent.update(update: $update)';
}


}

/// @nodoc
abstract mixin class $PromptTurnUpdateReceivedCopyWith<$Res> implements $PromptTurnStateEventCopyWith<$Res> {
  factory $PromptTurnUpdateReceivedCopyWith(PromptTurnUpdateReceived value, $Res Function(PromptTurnUpdateReceived) _then) = _$PromptTurnUpdateReceivedCopyWithImpl;
@useResult
$Res call({
 SessionUpdate update
});


$SessionUpdateCopyWith<$Res> get update;

}
/// @nodoc
class _$PromptTurnUpdateReceivedCopyWithImpl<$Res>
    implements $PromptTurnUpdateReceivedCopyWith<$Res> {
  _$PromptTurnUpdateReceivedCopyWithImpl(this._self, this._then);

  final PromptTurnUpdateReceived _self;
  final $Res Function(PromptTurnUpdateReceived) _then;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? update = null,}) {
  return _then(PromptTurnUpdateReceived(
update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as SessionUpdate,
  ));
}

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionUpdateCopyWith<$Res> get update {
  
  return $SessionUpdateCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class PromptTurnApprovalRequested implements PromptTurnStateEvent {
  const PromptTurnApprovalRequested({required this.approval});
  

 final  ApprovalRequest approval;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptTurnApprovalRequestedCopyWith<PromptTurnApprovalRequested> get copyWith => _$PromptTurnApprovalRequestedCopyWithImpl<PromptTurnApprovalRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptTurnApprovalRequested&&(identical(other.approval, approval) || other.approval == approval));
}


@override
int get hashCode => Object.hash(runtimeType,approval);

@override
String toString() {
  return 'PromptTurnStateEvent.requestApproval(approval: $approval)';
}


}

/// @nodoc
abstract mixin class $PromptTurnApprovalRequestedCopyWith<$Res> implements $PromptTurnStateEventCopyWith<$Res> {
  factory $PromptTurnApprovalRequestedCopyWith(PromptTurnApprovalRequested value, $Res Function(PromptTurnApprovalRequested) _then) = _$PromptTurnApprovalRequestedCopyWithImpl;
@useResult
$Res call({
 ApprovalRequest approval
});


$ApprovalRequestCopyWith<$Res> get approval;

}
/// @nodoc
class _$PromptTurnApprovalRequestedCopyWithImpl<$Res>
    implements $PromptTurnApprovalRequestedCopyWith<$Res> {
  _$PromptTurnApprovalRequestedCopyWithImpl(this._self, this._then);

  final PromptTurnApprovalRequested _self;
  final $Res Function(PromptTurnApprovalRequested) _then;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? approval = null,}) {
  return _then(PromptTurnApprovalRequested(
approval: null == approval ? _self.approval : approval // ignore: cast_nullable_to_non_nullable
as ApprovalRequest,
  ));
}

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ApprovalRequestCopyWith<$Res> get approval {
  
  return $ApprovalRequestCopyWith<$Res>(_self.approval, (value) {
    return _then(_self.copyWith(approval: value));
  });
}
}

/// @nodoc


class PromptTurnApprovalSelected implements PromptTurnStateEvent {
  const PromptTurnApprovalSelected({required this.approvalId, required this.optionId, this.resolvedAt});
  

 final  ApprovalRequestId approvalId;
 final  PermissionOptionId optionId;
 final  DateTime? resolvedAt;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptTurnApprovalSelectedCopyWith<PromptTurnApprovalSelected> get copyWith => _$PromptTurnApprovalSelectedCopyWithImpl<PromptTurnApprovalSelected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptTurnApprovalSelected&&(identical(other.approvalId, approvalId) || other.approvalId == approvalId)&&(identical(other.optionId, optionId) || other.optionId == optionId)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt));
}


@override
int get hashCode => Object.hash(runtimeType,approvalId,optionId,resolvedAt);

@override
String toString() {
  return 'PromptTurnStateEvent.selectApproval(approvalId: $approvalId, optionId: $optionId, resolvedAt: $resolvedAt)';
}


}

/// @nodoc
abstract mixin class $PromptTurnApprovalSelectedCopyWith<$Res> implements $PromptTurnStateEventCopyWith<$Res> {
  factory $PromptTurnApprovalSelectedCopyWith(PromptTurnApprovalSelected value, $Res Function(PromptTurnApprovalSelected) _then) = _$PromptTurnApprovalSelectedCopyWithImpl;
@useResult
$Res call({
 ApprovalRequestId approvalId, PermissionOptionId optionId, DateTime? resolvedAt
});


$ApprovalRequestIdCopyWith<$Res> get approvalId;$PermissionOptionIdCopyWith<$Res> get optionId;

}
/// @nodoc
class _$PromptTurnApprovalSelectedCopyWithImpl<$Res>
    implements $PromptTurnApprovalSelectedCopyWith<$Res> {
  _$PromptTurnApprovalSelectedCopyWithImpl(this._self, this._then);

  final PromptTurnApprovalSelected _self;
  final $Res Function(PromptTurnApprovalSelected) _then;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? approvalId = null,Object? optionId = null,Object? resolvedAt = freezed,}) {
  return _then(PromptTurnApprovalSelected(
approvalId: null == approvalId ? _self.approvalId : approvalId // ignore: cast_nullable_to_non_nullable
as ApprovalRequestId,optionId: null == optionId ? _self.optionId : optionId // ignore: cast_nullable_to_non_nullable
as PermissionOptionId,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ApprovalRequestIdCopyWith<$Res> get approvalId {
  
  return $ApprovalRequestIdCopyWith<$Res>(_self.approvalId, (value) {
    return _then(_self.copyWith(approvalId: value));
  });
}/// Create a copy of PromptTurnStateEvent
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


class PromptTurnApprovalCancelled implements PromptTurnStateEvent {
  const PromptTurnApprovalCancelled({required this.approvalId, this.resolvedAt});
  

 final  ApprovalRequestId approvalId;
 final  DateTime? resolvedAt;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptTurnApprovalCancelledCopyWith<PromptTurnApprovalCancelled> get copyWith => _$PromptTurnApprovalCancelledCopyWithImpl<PromptTurnApprovalCancelled>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptTurnApprovalCancelled&&(identical(other.approvalId, approvalId) || other.approvalId == approvalId)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt));
}


@override
int get hashCode => Object.hash(runtimeType,approvalId,resolvedAt);

@override
String toString() {
  return 'PromptTurnStateEvent.cancelApproval(approvalId: $approvalId, resolvedAt: $resolvedAt)';
}


}

/// @nodoc
abstract mixin class $PromptTurnApprovalCancelledCopyWith<$Res> implements $PromptTurnStateEventCopyWith<$Res> {
  factory $PromptTurnApprovalCancelledCopyWith(PromptTurnApprovalCancelled value, $Res Function(PromptTurnApprovalCancelled) _then) = _$PromptTurnApprovalCancelledCopyWithImpl;
@useResult
$Res call({
 ApprovalRequestId approvalId, DateTime? resolvedAt
});


$ApprovalRequestIdCopyWith<$Res> get approvalId;

}
/// @nodoc
class _$PromptTurnApprovalCancelledCopyWithImpl<$Res>
    implements $PromptTurnApprovalCancelledCopyWith<$Res> {
  _$PromptTurnApprovalCancelledCopyWithImpl(this._self, this._then);

  final PromptTurnApprovalCancelled _self;
  final $Res Function(PromptTurnApprovalCancelled) _then;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? approvalId = null,Object? resolvedAt = freezed,}) {
  return _then(PromptTurnApprovalCancelled(
approvalId: null == approvalId ? _self.approvalId : approvalId // ignore: cast_nullable_to_non_nullable
as ApprovalRequestId,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of PromptTurnStateEvent
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


class PromptTurnCompleted implements PromptTurnStateEvent {
  const PromptTurnCompleted({required this.stopReason, this.completedAt});
  

 final  StopReason stopReason;
 final  DateTime? completedAt;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptTurnCompletedCopyWith<PromptTurnCompleted> get copyWith => _$PromptTurnCompletedCopyWithImpl<PromptTurnCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptTurnCompleted&&(identical(other.stopReason, stopReason) || other.stopReason == stopReason)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hash(runtimeType,stopReason,completedAt);

@override
String toString() {
  return 'PromptTurnStateEvent.complete(stopReason: $stopReason, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $PromptTurnCompletedCopyWith<$Res> implements $PromptTurnStateEventCopyWith<$Res> {
  factory $PromptTurnCompletedCopyWith(PromptTurnCompleted value, $Res Function(PromptTurnCompleted) _then) = _$PromptTurnCompletedCopyWithImpl;
@useResult
$Res call({
 StopReason stopReason, DateTime? completedAt
});




}
/// @nodoc
class _$PromptTurnCompletedCopyWithImpl<$Res>
    implements $PromptTurnCompletedCopyWith<$Res> {
  _$PromptTurnCompletedCopyWithImpl(this._self, this._then);

  final PromptTurnCompleted _self;
  final $Res Function(PromptTurnCompleted) _then;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? stopReason = null,Object? completedAt = freezed,}) {
  return _then(PromptTurnCompleted(
stopReason: null == stopReason ? _self.stopReason : stopReason // ignore: cast_nullable_to_non_nullable
as StopReason,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc


class PromptTurnFailed implements PromptTurnStateEvent {
  const PromptTurnFailed({required this.message, this.completedAt});
  

 final  String message;
 final  DateTime? completedAt;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptTurnFailedCopyWith<PromptTurnFailed> get copyWith => _$PromptTurnFailedCopyWithImpl<PromptTurnFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptTurnFailed&&(identical(other.message, message) || other.message == message)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hash(runtimeType,message,completedAt);

@override
String toString() {
  return 'PromptTurnStateEvent.fail(message: $message, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $PromptTurnFailedCopyWith<$Res> implements $PromptTurnStateEventCopyWith<$Res> {
  factory $PromptTurnFailedCopyWith(PromptTurnFailed value, $Res Function(PromptTurnFailed) _then) = _$PromptTurnFailedCopyWithImpl;
@useResult
$Res call({
 String message, DateTime? completedAt
});




}
/// @nodoc
class _$PromptTurnFailedCopyWithImpl<$Res>
    implements $PromptTurnFailedCopyWith<$Res> {
  _$PromptTurnFailedCopyWithImpl(this._self, this._then);

  final PromptTurnFailed _self;
  final $Res Function(PromptTurnFailed) _then;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,Object? completedAt = freezed,}) {
  return _then(PromptTurnFailed(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc


class PromptTurnCancelled implements PromptTurnStateEvent {
  const PromptTurnCancelled({this.completedAt});
  

 final  DateTime? completedAt;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptTurnCancelledCopyWith<PromptTurnCancelled> get copyWith => _$PromptTurnCancelledCopyWithImpl<PromptTurnCancelled>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptTurnCancelled&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hash(runtimeType,completedAt);

@override
String toString() {
  return 'PromptTurnStateEvent.cancel(completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $PromptTurnCancelledCopyWith<$Res> implements $PromptTurnStateEventCopyWith<$Res> {
  factory $PromptTurnCancelledCopyWith(PromptTurnCancelled value, $Res Function(PromptTurnCancelled) _then) = _$PromptTurnCancelledCopyWithImpl;
@useResult
$Res call({
 DateTime? completedAt
});




}
/// @nodoc
class _$PromptTurnCancelledCopyWithImpl<$Res>
    implements $PromptTurnCancelledCopyWith<$Res> {
  _$PromptTurnCancelledCopyWithImpl(this._self, this._then);

  final PromptTurnCancelled _self;
  final $Res Function(PromptTurnCancelled) _then;

/// Create a copy of PromptTurnStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = freezed,}) {
  return _then(PromptTurnCancelled(
completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc
mixin _$SessionStateEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionStateEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SessionStateEvent()';
}


}

/// @nodoc
class $SessionStateEventCopyWith<$Res>  {
$SessionStateEventCopyWith(SessionStateEvent _, $Res Function(SessionStateEvent) __);
}


/// Adds pattern-matching-related methods to [SessionStateEvent].
extension SessionStateEventPatterns on SessionStateEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SessionActivateRequested value)?  activate,TResult Function( SessionTurnStartRequested value)?  startTurn,TResult Function( SessionUpdateReceived value)?  update,TResult Function( SessionApprovalRequested value)?  requestApproval,TResult Function( SessionApprovalSelected value)?  selectApproval,TResult Function( SessionApprovalCancelled value)?  cancelApproval,TResult Function( SessionTurnCompleted value)?  completeTurn,TResult Function( SessionTurnFailed value)?  failTurn,TResult Function( SessionTurnCancelled value)?  cancelTurn,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SessionActivateRequested() when activate != null:
return activate(_that);case SessionTurnStartRequested() when startTurn != null:
return startTurn(_that);case SessionUpdateReceived() when update != null:
return update(_that);case SessionApprovalRequested() when requestApproval != null:
return requestApproval(_that);case SessionApprovalSelected() when selectApproval != null:
return selectApproval(_that);case SessionApprovalCancelled() when cancelApproval != null:
return cancelApproval(_that);case SessionTurnCompleted() when completeTurn != null:
return completeTurn(_that);case SessionTurnFailed() when failTurn != null:
return failTurn(_that);case SessionTurnCancelled() when cancelTurn != null:
return cancelTurn(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SessionActivateRequested value)  activate,required TResult Function( SessionTurnStartRequested value)  startTurn,required TResult Function( SessionUpdateReceived value)  update,required TResult Function( SessionApprovalRequested value)  requestApproval,required TResult Function( SessionApprovalSelected value)  selectApproval,required TResult Function( SessionApprovalCancelled value)  cancelApproval,required TResult Function( SessionTurnCompleted value)  completeTurn,required TResult Function( SessionTurnFailed value)  failTurn,required TResult Function( SessionTurnCancelled value)  cancelTurn,}){
final _that = this;
switch (_that) {
case SessionActivateRequested():
return activate(_that);case SessionTurnStartRequested():
return startTurn(_that);case SessionUpdateReceived():
return update(_that);case SessionApprovalRequested():
return requestApproval(_that);case SessionApprovalSelected():
return selectApproval(_that);case SessionApprovalCancelled():
return cancelApproval(_that);case SessionTurnCompleted():
return completeTurn(_that);case SessionTurnFailed():
return failTurn(_that);case SessionTurnCancelled():
return cancelTurn(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SessionActivateRequested value)?  activate,TResult? Function( SessionTurnStartRequested value)?  startTurn,TResult? Function( SessionUpdateReceived value)?  update,TResult? Function( SessionApprovalRequested value)?  requestApproval,TResult? Function( SessionApprovalSelected value)?  selectApproval,TResult? Function( SessionApprovalCancelled value)?  cancelApproval,TResult? Function( SessionTurnCompleted value)?  completeTurn,TResult? Function( SessionTurnFailed value)?  failTurn,TResult? Function( SessionTurnCancelled value)?  cancelTurn,}){
final _that = this;
switch (_that) {
case SessionActivateRequested() when activate != null:
return activate(_that);case SessionTurnStartRequested() when startTurn != null:
return startTurn(_that);case SessionUpdateReceived() when update != null:
return update(_that);case SessionApprovalRequested() when requestApproval != null:
return requestApproval(_that);case SessionApprovalSelected() when selectApproval != null:
return selectApproval(_that);case SessionApprovalCancelled() when cancelApproval != null:
return cancelApproval(_that);case SessionTurnCompleted() when completeTurn != null:
return completeTurn(_that);case SessionTurnFailed() when failTurn != null:
return failTurn(_that);case SessionTurnCancelled() when cancelTurn != null:
return cancelTurn(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( DateTime? updatedAt)?  activate,TResult Function( PromptTurn turn,  DateTime? startedAt)?  startTurn,TResult Function( SessionUpdate update)?  update,TResult Function( ApprovalRequest approval)?  requestApproval,TResult Function( ApprovalRequestId approvalId,  PermissionOptionId optionId,  DateTime? resolvedAt)?  selectApproval,TResult Function( ApprovalRequestId approvalId,  DateTime? resolvedAt)?  cancelApproval,TResult Function( StopReason stopReason,  DateTime? completedAt)?  completeTurn,TResult Function( String message,  DateTime? completedAt)?  failTurn,TResult Function( DateTime? completedAt)?  cancelTurn,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SessionActivateRequested() when activate != null:
return activate(_that.updatedAt);case SessionTurnStartRequested() when startTurn != null:
return startTurn(_that.turn,_that.startedAt);case SessionUpdateReceived() when update != null:
return update(_that.update);case SessionApprovalRequested() when requestApproval != null:
return requestApproval(_that.approval);case SessionApprovalSelected() when selectApproval != null:
return selectApproval(_that.approvalId,_that.optionId,_that.resolvedAt);case SessionApprovalCancelled() when cancelApproval != null:
return cancelApproval(_that.approvalId,_that.resolvedAt);case SessionTurnCompleted() when completeTurn != null:
return completeTurn(_that.stopReason,_that.completedAt);case SessionTurnFailed() when failTurn != null:
return failTurn(_that.message,_that.completedAt);case SessionTurnCancelled() when cancelTurn != null:
return cancelTurn(_that.completedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( DateTime? updatedAt)  activate,required TResult Function( PromptTurn turn,  DateTime? startedAt)  startTurn,required TResult Function( SessionUpdate update)  update,required TResult Function( ApprovalRequest approval)  requestApproval,required TResult Function( ApprovalRequestId approvalId,  PermissionOptionId optionId,  DateTime? resolvedAt)  selectApproval,required TResult Function( ApprovalRequestId approvalId,  DateTime? resolvedAt)  cancelApproval,required TResult Function( StopReason stopReason,  DateTime? completedAt)  completeTurn,required TResult Function( String message,  DateTime? completedAt)  failTurn,required TResult Function( DateTime? completedAt)  cancelTurn,}) {final _that = this;
switch (_that) {
case SessionActivateRequested():
return activate(_that.updatedAt);case SessionTurnStartRequested():
return startTurn(_that.turn,_that.startedAt);case SessionUpdateReceived():
return update(_that.update);case SessionApprovalRequested():
return requestApproval(_that.approval);case SessionApprovalSelected():
return selectApproval(_that.approvalId,_that.optionId,_that.resolvedAt);case SessionApprovalCancelled():
return cancelApproval(_that.approvalId,_that.resolvedAt);case SessionTurnCompleted():
return completeTurn(_that.stopReason,_that.completedAt);case SessionTurnFailed():
return failTurn(_that.message,_that.completedAt);case SessionTurnCancelled():
return cancelTurn(_that.completedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( DateTime? updatedAt)?  activate,TResult? Function( PromptTurn turn,  DateTime? startedAt)?  startTurn,TResult? Function( SessionUpdate update)?  update,TResult? Function( ApprovalRequest approval)?  requestApproval,TResult? Function( ApprovalRequestId approvalId,  PermissionOptionId optionId,  DateTime? resolvedAt)?  selectApproval,TResult? Function( ApprovalRequestId approvalId,  DateTime? resolvedAt)?  cancelApproval,TResult? Function( StopReason stopReason,  DateTime? completedAt)?  completeTurn,TResult? Function( String message,  DateTime? completedAt)?  failTurn,TResult? Function( DateTime? completedAt)?  cancelTurn,}) {final _that = this;
switch (_that) {
case SessionActivateRequested() when activate != null:
return activate(_that.updatedAt);case SessionTurnStartRequested() when startTurn != null:
return startTurn(_that.turn,_that.startedAt);case SessionUpdateReceived() when update != null:
return update(_that.update);case SessionApprovalRequested() when requestApproval != null:
return requestApproval(_that.approval);case SessionApprovalSelected() when selectApproval != null:
return selectApproval(_that.approvalId,_that.optionId,_that.resolvedAt);case SessionApprovalCancelled() when cancelApproval != null:
return cancelApproval(_that.approvalId,_that.resolvedAt);case SessionTurnCompleted() when completeTurn != null:
return completeTurn(_that.stopReason,_that.completedAt);case SessionTurnFailed() when failTurn != null:
return failTurn(_that.message,_that.completedAt);case SessionTurnCancelled() when cancelTurn != null:
return cancelTurn(_that.completedAt);case _:
  return null;

}
}

}

/// @nodoc


class SessionActivateRequested implements SessionStateEvent {
  const SessionActivateRequested({this.updatedAt});
  

 final  DateTime? updatedAt;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionActivateRequestedCopyWith<SessionActivateRequested> get copyWith => _$SessionActivateRequestedCopyWithImpl<SessionActivateRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionActivateRequested&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,updatedAt);

@override
String toString() {
  return 'SessionStateEvent.activate(updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $SessionActivateRequestedCopyWith<$Res> implements $SessionStateEventCopyWith<$Res> {
  factory $SessionActivateRequestedCopyWith(SessionActivateRequested value, $Res Function(SessionActivateRequested) _then) = _$SessionActivateRequestedCopyWithImpl;
@useResult
$Res call({
 DateTime? updatedAt
});




}
/// @nodoc
class _$SessionActivateRequestedCopyWithImpl<$Res>
    implements $SessionActivateRequestedCopyWith<$Res> {
  _$SessionActivateRequestedCopyWithImpl(this._self, this._then);

  final SessionActivateRequested _self;
  final $Res Function(SessionActivateRequested) _then;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? updatedAt = freezed,}) {
  return _then(SessionActivateRequested(
updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc


class SessionTurnStartRequested implements SessionStateEvent {
  const SessionTurnStartRequested({required this.turn, this.startedAt});
  

 final  PromptTurn turn;
 final  DateTime? startedAt;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionTurnStartRequestedCopyWith<SessionTurnStartRequested> get copyWith => _$SessionTurnStartRequestedCopyWithImpl<SessionTurnStartRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionTurnStartRequested&&(identical(other.turn, turn) || other.turn == turn)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode => Object.hash(runtimeType,turn,startedAt);

@override
String toString() {
  return 'SessionStateEvent.startTurn(turn: $turn, startedAt: $startedAt)';
}


}

/// @nodoc
abstract mixin class $SessionTurnStartRequestedCopyWith<$Res> implements $SessionStateEventCopyWith<$Res> {
  factory $SessionTurnStartRequestedCopyWith(SessionTurnStartRequested value, $Res Function(SessionTurnStartRequested) _then) = _$SessionTurnStartRequestedCopyWithImpl;
@useResult
$Res call({
 PromptTurn turn, DateTime? startedAt
});


$PromptTurnCopyWith<$Res> get turn;

}
/// @nodoc
class _$SessionTurnStartRequestedCopyWithImpl<$Res>
    implements $SessionTurnStartRequestedCopyWith<$Res> {
  _$SessionTurnStartRequestedCopyWithImpl(this._self, this._then);

  final SessionTurnStartRequested _self;
  final $Res Function(SessionTurnStartRequested) _then;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turn = null,Object? startedAt = freezed,}) {
  return _then(SessionTurnStartRequested(
turn: null == turn ? _self.turn : turn // ignore: cast_nullable_to_non_nullable
as PromptTurn,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PromptTurnCopyWith<$Res> get turn {
  
  return $PromptTurnCopyWith<$Res>(_self.turn, (value) {
    return _then(_self.copyWith(turn: value));
  });
}
}

/// @nodoc


class SessionUpdateReceived implements SessionStateEvent {
  const SessionUpdateReceived({required this.update});
  

 final  SessionUpdate update;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionUpdateReceivedCopyWith<SessionUpdateReceived> get copyWith => _$SessionUpdateReceivedCopyWithImpl<SessionUpdateReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionUpdateReceived&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode => Object.hash(runtimeType,update);

@override
String toString() {
  return 'SessionStateEvent.update(update: $update)';
}


}

/// @nodoc
abstract mixin class $SessionUpdateReceivedCopyWith<$Res> implements $SessionStateEventCopyWith<$Res> {
  factory $SessionUpdateReceivedCopyWith(SessionUpdateReceived value, $Res Function(SessionUpdateReceived) _then) = _$SessionUpdateReceivedCopyWithImpl;
@useResult
$Res call({
 SessionUpdate update
});


$SessionUpdateCopyWith<$Res> get update;

}
/// @nodoc
class _$SessionUpdateReceivedCopyWithImpl<$Res>
    implements $SessionUpdateReceivedCopyWith<$Res> {
  _$SessionUpdateReceivedCopyWithImpl(this._self, this._then);

  final SessionUpdateReceived _self;
  final $Res Function(SessionUpdateReceived) _then;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? update = null,}) {
  return _then(SessionUpdateReceived(
update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as SessionUpdate,
  ));
}

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionUpdateCopyWith<$Res> get update {
  
  return $SessionUpdateCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class SessionApprovalRequested implements SessionStateEvent {
  const SessionApprovalRequested({required this.approval});
  

 final  ApprovalRequest approval;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionApprovalRequestedCopyWith<SessionApprovalRequested> get copyWith => _$SessionApprovalRequestedCopyWithImpl<SessionApprovalRequested>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionApprovalRequested&&(identical(other.approval, approval) || other.approval == approval));
}


@override
int get hashCode => Object.hash(runtimeType,approval);

@override
String toString() {
  return 'SessionStateEvent.requestApproval(approval: $approval)';
}


}

/// @nodoc
abstract mixin class $SessionApprovalRequestedCopyWith<$Res> implements $SessionStateEventCopyWith<$Res> {
  factory $SessionApprovalRequestedCopyWith(SessionApprovalRequested value, $Res Function(SessionApprovalRequested) _then) = _$SessionApprovalRequestedCopyWithImpl;
@useResult
$Res call({
 ApprovalRequest approval
});


$ApprovalRequestCopyWith<$Res> get approval;

}
/// @nodoc
class _$SessionApprovalRequestedCopyWithImpl<$Res>
    implements $SessionApprovalRequestedCopyWith<$Res> {
  _$SessionApprovalRequestedCopyWithImpl(this._self, this._then);

  final SessionApprovalRequested _self;
  final $Res Function(SessionApprovalRequested) _then;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? approval = null,}) {
  return _then(SessionApprovalRequested(
approval: null == approval ? _self.approval : approval // ignore: cast_nullable_to_non_nullable
as ApprovalRequest,
  ));
}

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ApprovalRequestCopyWith<$Res> get approval {
  
  return $ApprovalRequestCopyWith<$Res>(_self.approval, (value) {
    return _then(_self.copyWith(approval: value));
  });
}
}

/// @nodoc


class SessionApprovalSelected implements SessionStateEvent {
  const SessionApprovalSelected({required this.approvalId, required this.optionId, this.resolvedAt});
  

 final  ApprovalRequestId approvalId;
 final  PermissionOptionId optionId;
 final  DateTime? resolvedAt;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionApprovalSelectedCopyWith<SessionApprovalSelected> get copyWith => _$SessionApprovalSelectedCopyWithImpl<SessionApprovalSelected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionApprovalSelected&&(identical(other.approvalId, approvalId) || other.approvalId == approvalId)&&(identical(other.optionId, optionId) || other.optionId == optionId)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt));
}


@override
int get hashCode => Object.hash(runtimeType,approvalId,optionId,resolvedAt);

@override
String toString() {
  return 'SessionStateEvent.selectApproval(approvalId: $approvalId, optionId: $optionId, resolvedAt: $resolvedAt)';
}


}

/// @nodoc
abstract mixin class $SessionApprovalSelectedCopyWith<$Res> implements $SessionStateEventCopyWith<$Res> {
  factory $SessionApprovalSelectedCopyWith(SessionApprovalSelected value, $Res Function(SessionApprovalSelected) _then) = _$SessionApprovalSelectedCopyWithImpl;
@useResult
$Res call({
 ApprovalRequestId approvalId, PermissionOptionId optionId, DateTime? resolvedAt
});


$ApprovalRequestIdCopyWith<$Res> get approvalId;$PermissionOptionIdCopyWith<$Res> get optionId;

}
/// @nodoc
class _$SessionApprovalSelectedCopyWithImpl<$Res>
    implements $SessionApprovalSelectedCopyWith<$Res> {
  _$SessionApprovalSelectedCopyWithImpl(this._self, this._then);

  final SessionApprovalSelected _self;
  final $Res Function(SessionApprovalSelected) _then;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? approvalId = null,Object? optionId = null,Object? resolvedAt = freezed,}) {
  return _then(SessionApprovalSelected(
approvalId: null == approvalId ? _self.approvalId : approvalId // ignore: cast_nullable_to_non_nullable
as ApprovalRequestId,optionId: null == optionId ? _self.optionId : optionId // ignore: cast_nullable_to_non_nullable
as PermissionOptionId,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ApprovalRequestIdCopyWith<$Res> get approvalId {
  
  return $ApprovalRequestIdCopyWith<$Res>(_self.approvalId, (value) {
    return _then(_self.copyWith(approvalId: value));
  });
}/// Create a copy of SessionStateEvent
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


class SessionApprovalCancelled implements SessionStateEvent {
  const SessionApprovalCancelled({required this.approvalId, this.resolvedAt});
  

 final  ApprovalRequestId approvalId;
 final  DateTime? resolvedAt;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionApprovalCancelledCopyWith<SessionApprovalCancelled> get copyWith => _$SessionApprovalCancelledCopyWithImpl<SessionApprovalCancelled>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionApprovalCancelled&&(identical(other.approvalId, approvalId) || other.approvalId == approvalId)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt));
}


@override
int get hashCode => Object.hash(runtimeType,approvalId,resolvedAt);

@override
String toString() {
  return 'SessionStateEvent.cancelApproval(approvalId: $approvalId, resolvedAt: $resolvedAt)';
}


}

/// @nodoc
abstract mixin class $SessionApprovalCancelledCopyWith<$Res> implements $SessionStateEventCopyWith<$Res> {
  factory $SessionApprovalCancelledCopyWith(SessionApprovalCancelled value, $Res Function(SessionApprovalCancelled) _then) = _$SessionApprovalCancelledCopyWithImpl;
@useResult
$Res call({
 ApprovalRequestId approvalId, DateTime? resolvedAt
});


$ApprovalRequestIdCopyWith<$Res> get approvalId;

}
/// @nodoc
class _$SessionApprovalCancelledCopyWithImpl<$Res>
    implements $SessionApprovalCancelledCopyWith<$Res> {
  _$SessionApprovalCancelledCopyWithImpl(this._self, this._then);

  final SessionApprovalCancelled _self;
  final $Res Function(SessionApprovalCancelled) _then;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? approvalId = null,Object? resolvedAt = freezed,}) {
  return _then(SessionApprovalCancelled(
approvalId: null == approvalId ? _self.approvalId : approvalId // ignore: cast_nullable_to_non_nullable
as ApprovalRequestId,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of SessionStateEvent
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


class SessionTurnCompleted implements SessionStateEvent {
  const SessionTurnCompleted({required this.stopReason, this.completedAt});
  

 final  StopReason stopReason;
 final  DateTime? completedAt;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionTurnCompletedCopyWith<SessionTurnCompleted> get copyWith => _$SessionTurnCompletedCopyWithImpl<SessionTurnCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionTurnCompleted&&(identical(other.stopReason, stopReason) || other.stopReason == stopReason)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hash(runtimeType,stopReason,completedAt);

@override
String toString() {
  return 'SessionStateEvent.completeTurn(stopReason: $stopReason, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $SessionTurnCompletedCopyWith<$Res> implements $SessionStateEventCopyWith<$Res> {
  factory $SessionTurnCompletedCopyWith(SessionTurnCompleted value, $Res Function(SessionTurnCompleted) _then) = _$SessionTurnCompletedCopyWithImpl;
@useResult
$Res call({
 StopReason stopReason, DateTime? completedAt
});




}
/// @nodoc
class _$SessionTurnCompletedCopyWithImpl<$Res>
    implements $SessionTurnCompletedCopyWith<$Res> {
  _$SessionTurnCompletedCopyWithImpl(this._self, this._then);

  final SessionTurnCompleted _self;
  final $Res Function(SessionTurnCompleted) _then;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? stopReason = null,Object? completedAt = freezed,}) {
  return _then(SessionTurnCompleted(
stopReason: null == stopReason ? _self.stopReason : stopReason // ignore: cast_nullable_to_non_nullable
as StopReason,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc


class SessionTurnFailed implements SessionStateEvent {
  const SessionTurnFailed({required this.message, this.completedAt});
  

 final  String message;
 final  DateTime? completedAt;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionTurnFailedCopyWith<SessionTurnFailed> get copyWith => _$SessionTurnFailedCopyWithImpl<SessionTurnFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionTurnFailed&&(identical(other.message, message) || other.message == message)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hash(runtimeType,message,completedAt);

@override
String toString() {
  return 'SessionStateEvent.failTurn(message: $message, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $SessionTurnFailedCopyWith<$Res> implements $SessionStateEventCopyWith<$Res> {
  factory $SessionTurnFailedCopyWith(SessionTurnFailed value, $Res Function(SessionTurnFailed) _then) = _$SessionTurnFailedCopyWithImpl;
@useResult
$Res call({
 String message, DateTime? completedAt
});




}
/// @nodoc
class _$SessionTurnFailedCopyWithImpl<$Res>
    implements $SessionTurnFailedCopyWith<$Res> {
  _$SessionTurnFailedCopyWithImpl(this._self, this._then);

  final SessionTurnFailed _self;
  final $Res Function(SessionTurnFailed) _then;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,Object? completedAt = freezed,}) {
  return _then(SessionTurnFailed(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc


class SessionTurnCancelled implements SessionStateEvent {
  const SessionTurnCancelled({this.completedAt});
  

 final  DateTime? completedAt;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionTurnCancelledCopyWith<SessionTurnCancelled> get copyWith => _$SessionTurnCancelledCopyWithImpl<SessionTurnCancelled>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionTurnCancelled&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hash(runtimeType,completedAt);

@override
String toString() {
  return 'SessionStateEvent.cancelTurn(completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $SessionTurnCancelledCopyWith<$Res> implements $SessionStateEventCopyWith<$Res> {
  factory $SessionTurnCancelledCopyWith(SessionTurnCancelled value, $Res Function(SessionTurnCancelled) _then) = _$SessionTurnCancelledCopyWithImpl;
@useResult
$Res call({
 DateTime? completedAt
});




}
/// @nodoc
class _$SessionTurnCancelledCopyWithImpl<$Res>
    implements $SessionTurnCancelledCopyWith<$Res> {
  _$SessionTurnCancelledCopyWithImpl(this._self, this._then);

  final SessionTurnCancelled _self;
  final $Res Function(SessionTurnCancelled) _then;

/// Create a copy of SessionStateEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = freezed,}) {
  return _then(SessionTurnCancelled(
completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
