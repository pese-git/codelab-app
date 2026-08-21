// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'domain_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PromptTurnId {

 String get value;
/// Create a copy of PromptTurnId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptTurnIdCopyWith<PromptTurnId> get copyWith => _$PromptTurnIdCopyWithImpl<PromptTurnId>(this as PromptTurnId, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptTurnId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'PromptTurnId(value: $value)';
}


}

/// @nodoc
abstract mixin class $PromptTurnIdCopyWith<$Res>  {
  factory $PromptTurnIdCopyWith(PromptTurnId value, $Res Function(PromptTurnId) _then) = _$PromptTurnIdCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$PromptTurnIdCopyWithImpl<$Res>
    implements $PromptTurnIdCopyWith<$Res> {
  _$PromptTurnIdCopyWithImpl(this._self, this._then);

  final PromptTurnId _self;
  final $Res Function(PromptTurnId) _then;

/// Create a copy of PromptTurnId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(_self.copyWith(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PromptTurnId].
extension PromptTurnIdPatterns on PromptTurnId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PromptTurnId value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PromptTurnId() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PromptTurnId value)  $default,){
final _that = this;
switch (_that) {
case _PromptTurnId():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PromptTurnId value)?  $default,){
final _that = this;
switch (_that) {
case _PromptTurnId() when $default != null:
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
case _PromptTurnId() when $default != null:
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
case _PromptTurnId():
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
case _PromptTurnId() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _PromptTurnId extends PromptTurnId {
  const _PromptTurnId(this.value): super._();
  

@override final  String value;

/// Create a copy of PromptTurnId
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PromptTurnIdCopyWith<_PromptTurnId> get copyWith => __$PromptTurnIdCopyWithImpl<_PromptTurnId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PromptTurnId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'PromptTurnId(value: $value)';
}


}

/// @nodoc
abstract mixin class _$PromptTurnIdCopyWith<$Res> implements $PromptTurnIdCopyWith<$Res> {
  factory _$PromptTurnIdCopyWith(_PromptTurnId value, $Res Function(_PromptTurnId) _then) = __$PromptTurnIdCopyWithImpl;
@override @useResult
$Res call({
 String value
});




}
/// @nodoc
class __$PromptTurnIdCopyWithImpl<$Res>
    implements _$PromptTurnIdCopyWith<$Res> {
  __$PromptTurnIdCopyWithImpl(this._self, this._then);

  final _PromptTurnId _self;
  final $Res Function(_PromptTurnId) _then;

/// Create a copy of PromptTurnId
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_PromptTurnId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ApprovalRequestId {

 String get value;
/// Create a copy of ApprovalRequestId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApprovalRequestIdCopyWith<ApprovalRequestId> get copyWith => _$ApprovalRequestIdCopyWithImpl<ApprovalRequestId>(this as ApprovalRequestId, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ApprovalRequestId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'ApprovalRequestId(value: $value)';
}


}

/// @nodoc
abstract mixin class $ApprovalRequestIdCopyWith<$Res>  {
  factory $ApprovalRequestIdCopyWith(ApprovalRequestId value, $Res Function(ApprovalRequestId) _then) = _$ApprovalRequestIdCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$ApprovalRequestIdCopyWithImpl<$Res>
    implements $ApprovalRequestIdCopyWith<$Res> {
  _$ApprovalRequestIdCopyWithImpl(this._self, this._then);

  final ApprovalRequestId _self;
  final $Res Function(ApprovalRequestId) _then;

/// Create a copy of ApprovalRequestId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(_self.copyWith(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ApprovalRequestId].
extension ApprovalRequestIdPatterns on ApprovalRequestId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ApprovalRequestId value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ApprovalRequestId() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ApprovalRequestId value)  $default,){
final _that = this;
switch (_that) {
case _ApprovalRequestId():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ApprovalRequestId value)?  $default,){
final _that = this;
switch (_that) {
case _ApprovalRequestId() when $default != null:
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
case _ApprovalRequestId() when $default != null:
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
case _ApprovalRequestId():
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
case _ApprovalRequestId() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ApprovalRequestId extends ApprovalRequestId {
  const _ApprovalRequestId(this.value): super._();
  

@override final  String value;

/// Create a copy of ApprovalRequestId
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ApprovalRequestIdCopyWith<_ApprovalRequestId> get copyWith => __$ApprovalRequestIdCopyWithImpl<_ApprovalRequestId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ApprovalRequestId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'ApprovalRequestId(value: $value)';
}


}

/// @nodoc
abstract mixin class _$ApprovalRequestIdCopyWith<$Res> implements $ApprovalRequestIdCopyWith<$Res> {
  factory _$ApprovalRequestIdCopyWith(_ApprovalRequestId value, $Res Function(_ApprovalRequestId) _then) = __$ApprovalRequestIdCopyWithImpl;
@override @useResult
$Res call({
 String value
});




}
/// @nodoc
class __$ApprovalRequestIdCopyWithImpl<$Res>
    implements _$ApprovalRequestIdCopyWith<$Res> {
  __$ApprovalRequestIdCopyWithImpl(this._self, this._then);

  final _ApprovalRequestId _self;
  final $Res Function(_ApprovalRequestId) _then;

/// Create a copy of ApprovalRequestId
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_ApprovalRequestId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$DiagnosticEntryId {

 String get value;
/// Create a copy of DiagnosticEntryId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticEntryIdCopyWith<DiagnosticEntryId> get copyWith => _$DiagnosticEntryIdCopyWithImpl<DiagnosticEntryId>(this as DiagnosticEntryId, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticEntryId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'DiagnosticEntryId(value: $value)';
}


}

/// @nodoc
abstract mixin class $DiagnosticEntryIdCopyWith<$Res>  {
  factory $DiagnosticEntryIdCopyWith(DiagnosticEntryId value, $Res Function(DiagnosticEntryId) _then) = _$DiagnosticEntryIdCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$DiagnosticEntryIdCopyWithImpl<$Res>
    implements $DiagnosticEntryIdCopyWith<$Res> {
  _$DiagnosticEntryIdCopyWithImpl(this._self, this._then);

  final DiagnosticEntryId _self;
  final $Res Function(DiagnosticEntryId) _then;

/// Create a copy of DiagnosticEntryId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(_self.copyWith(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [DiagnosticEntryId].
extension DiagnosticEntryIdPatterns on DiagnosticEntryId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DiagnosticEntryId value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DiagnosticEntryId() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DiagnosticEntryId value)  $default,){
final _that = this;
switch (_that) {
case _DiagnosticEntryId():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DiagnosticEntryId value)?  $default,){
final _that = this;
switch (_that) {
case _DiagnosticEntryId() when $default != null:
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
case _DiagnosticEntryId() when $default != null:
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
case _DiagnosticEntryId():
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
case _DiagnosticEntryId() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _DiagnosticEntryId extends DiagnosticEntryId {
  const _DiagnosticEntryId(this.value): super._();
  

@override final  String value;

/// Create a copy of DiagnosticEntryId
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DiagnosticEntryIdCopyWith<_DiagnosticEntryId> get copyWith => __$DiagnosticEntryIdCopyWithImpl<_DiagnosticEntryId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DiagnosticEntryId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'DiagnosticEntryId(value: $value)';
}


}

/// @nodoc
abstract mixin class _$DiagnosticEntryIdCopyWith<$Res> implements $DiagnosticEntryIdCopyWith<$Res> {
  factory _$DiagnosticEntryIdCopyWith(_DiagnosticEntryId value, $Res Function(_DiagnosticEntryId) _then) = __$DiagnosticEntryIdCopyWithImpl;
@override @useResult
$Res call({
 String value
});




}
/// @nodoc
class __$DiagnosticEntryIdCopyWithImpl<$Res>
    implements _$DiagnosticEntryIdCopyWith<$Res> {
  __$DiagnosticEntryIdCopyWithImpl(this._self, this._then);

  final _DiagnosticEntryId _self;
  final $Res Function(_DiagnosticEntryId) _then;

/// Create a copy of DiagnosticEntryId
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_DiagnosticEntryId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ClientConnectionState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientConnectionState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ClientConnectionState()';
}


}

/// @nodoc
class $ClientConnectionStateCopyWith<$Res>  {
$ClientConnectionStateCopyWith(ClientConnectionState _, $Res Function(ClientConnectionState) __);
}


/// Adds pattern-matching-related methods to [ClientConnectionState].
extension ClientConnectionStatePatterns on ClientConnectionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ClientConnectionDisconnected value)?  disconnected,TResult Function( ClientConnectionConnecting value)?  connecting,TResult Function( ClientConnectionInitializing value)?  initializing,TResult Function( ClientConnectionReady value)?  ready,TResult Function( ClientConnectionFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ClientConnectionDisconnected() when disconnected != null:
return disconnected(_that);case ClientConnectionConnecting() when connecting != null:
return connecting(_that);case ClientConnectionInitializing() when initializing != null:
return initializing(_that);case ClientConnectionReady() when ready != null:
return ready(_that);case ClientConnectionFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ClientConnectionDisconnected value)  disconnected,required TResult Function( ClientConnectionConnecting value)  connecting,required TResult Function( ClientConnectionInitializing value)  initializing,required TResult Function( ClientConnectionReady value)  ready,required TResult Function( ClientConnectionFailed value)  failed,}){
final _that = this;
switch (_that) {
case ClientConnectionDisconnected():
return disconnected(_that);case ClientConnectionConnecting():
return connecting(_that);case ClientConnectionInitializing():
return initializing(_that);case ClientConnectionReady():
return ready(_that);case ClientConnectionFailed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ClientConnectionDisconnected value)?  disconnected,TResult? Function( ClientConnectionConnecting value)?  connecting,TResult? Function( ClientConnectionInitializing value)?  initializing,TResult? Function( ClientConnectionReady value)?  ready,TResult? Function( ClientConnectionFailed value)?  failed,}){
final _that = this;
switch (_that) {
case ClientConnectionDisconnected() when disconnected != null:
return disconnected(_that);case ClientConnectionConnecting() when connecting != null:
return connecting(_that);case ClientConnectionInitializing() when initializing != null:
return initializing(_that);case ClientConnectionReady() when ready != null:
return ready(_that);case ClientConnectionFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  disconnected,TResult Function()?  connecting,TResult Function()?  initializing,TResult Function( ProtocolVersion protocolVersion,  Implementation? agentInfo,  AgentCapabilities capabilities)?  ready,TResult Function( ConnectionFailureReason reason,  String message,  Object? cause)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ClientConnectionDisconnected() when disconnected != null:
return disconnected();case ClientConnectionConnecting() when connecting != null:
return connecting();case ClientConnectionInitializing() when initializing != null:
return initializing();case ClientConnectionReady() when ready != null:
return ready(_that.protocolVersion,_that.agentInfo,_that.capabilities);case ClientConnectionFailed() when failed != null:
return failed(_that.reason,_that.message,_that.cause);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  disconnected,required TResult Function()  connecting,required TResult Function()  initializing,required TResult Function( ProtocolVersion protocolVersion,  Implementation? agentInfo,  AgentCapabilities capabilities)  ready,required TResult Function( ConnectionFailureReason reason,  String message,  Object? cause)  failed,}) {final _that = this;
switch (_that) {
case ClientConnectionDisconnected():
return disconnected();case ClientConnectionConnecting():
return connecting();case ClientConnectionInitializing():
return initializing();case ClientConnectionReady():
return ready(_that.protocolVersion,_that.agentInfo,_that.capabilities);case ClientConnectionFailed():
return failed(_that.reason,_that.message,_that.cause);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  disconnected,TResult? Function()?  connecting,TResult? Function()?  initializing,TResult? Function( ProtocolVersion protocolVersion,  Implementation? agentInfo,  AgentCapabilities capabilities)?  ready,TResult? Function( ConnectionFailureReason reason,  String message,  Object? cause)?  failed,}) {final _that = this;
switch (_that) {
case ClientConnectionDisconnected() when disconnected != null:
return disconnected();case ClientConnectionConnecting() when connecting != null:
return connecting();case ClientConnectionInitializing() when initializing != null:
return initializing();case ClientConnectionReady() when ready != null:
return ready(_that.protocolVersion,_that.agentInfo,_that.capabilities);case ClientConnectionFailed() when failed != null:
return failed(_that.reason,_that.message,_that.cause);case _:
  return null;

}
}

}

/// @nodoc


class ClientConnectionDisconnected implements ClientConnectionState {
  const ClientConnectionDisconnected();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientConnectionDisconnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ClientConnectionState.disconnected()';
}


}




/// @nodoc


class ClientConnectionConnecting implements ClientConnectionState {
  const ClientConnectionConnecting();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientConnectionConnecting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ClientConnectionState.connecting()';
}


}




/// @nodoc


class ClientConnectionInitializing implements ClientConnectionState {
  const ClientConnectionInitializing();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientConnectionInitializing);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ClientConnectionState.initializing()';
}


}




/// @nodoc


class ClientConnectionReady implements ClientConnectionState {
  const ClientConnectionReady({required this.protocolVersion, this.agentInfo, this.capabilities = const AgentCapabilities()});
  

 final  ProtocolVersion protocolVersion;
 final  Implementation? agentInfo;
@JsonKey() final  AgentCapabilities capabilities;

/// Create a copy of ClientConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClientConnectionReadyCopyWith<ClientConnectionReady> get copyWith => _$ClientConnectionReadyCopyWithImpl<ClientConnectionReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientConnectionReady&&(identical(other.protocolVersion, protocolVersion) || other.protocolVersion == protocolVersion)&&(identical(other.agentInfo, agentInfo) || other.agentInfo == agentInfo)&&(identical(other.capabilities, capabilities) || other.capabilities == capabilities));
}


@override
int get hashCode => Object.hash(runtimeType,protocolVersion,agentInfo,capabilities);

@override
String toString() {
  return 'ClientConnectionState.ready(protocolVersion: $protocolVersion, agentInfo: $agentInfo, capabilities: $capabilities)';
}


}

/// @nodoc
abstract mixin class $ClientConnectionReadyCopyWith<$Res> implements $ClientConnectionStateCopyWith<$Res> {
  factory $ClientConnectionReadyCopyWith(ClientConnectionReady value, $Res Function(ClientConnectionReady) _then) = _$ClientConnectionReadyCopyWithImpl;
@useResult
$Res call({
 ProtocolVersion protocolVersion, Implementation? agentInfo, AgentCapabilities capabilities
});


$ProtocolVersionCopyWith<$Res> get protocolVersion;$ImplementationCopyWith<$Res>? get agentInfo;$AgentCapabilitiesCopyWith<$Res> get capabilities;

}
/// @nodoc
class _$ClientConnectionReadyCopyWithImpl<$Res>
    implements $ClientConnectionReadyCopyWith<$Res> {
  _$ClientConnectionReadyCopyWithImpl(this._self, this._then);

  final ClientConnectionReady _self;
  final $Res Function(ClientConnectionReady) _then;

/// Create a copy of ClientConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? protocolVersion = null,Object? agentInfo = freezed,Object? capabilities = null,}) {
  return _then(ClientConnectionReady(
protocolVersion: null == protocolVersion ? _self.protocolVersion : protocolVersion // ignore: cast_nullable_to_non_nullable
as ProtocolVersion,agentInfo: freezed == agentInfo ? _self.agentInfo : agentInfo // ignore: cast_nullable_to_non_nullable
as Implementation?,capabilities: null == capabilities ? _self.capabilities : capabilities // ignore: cast_nullable_to_non_nullable
as AgentCapabilities,
  ));
}

/// Create a copy of ClientConnectionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProtocolVersionCopyWith<$Res> get protocolVersion {
  
  return $ProtocolVersionCopyWith<$Res>(_self.protocolVersion, (value) {
    return _then(_self.copyWith(protocolVersion: value));
  });
}/// Create a copy of ClientConnectionState
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
}/// Create a copy of ClientConnectionState
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


class ClientConnectionFailed implements ClientConnectionState {
  const ClientConnectionFailed({required this.reason, required this.message, this.cause});
  

 final  ConnectionFailureReason reason;
 final  String message;
 final  Object? cause;

/// Create a copy of ClientConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClientConnectionFailedCopyWith<ClientConnectionFailed> get copyWith => _$ClientConnectionFailedCopyWithImpl<ClientConnectionFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientConnectionFailed&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.message, message) || other.message == message)&&const DeepCollectionEquality().equals(other.cause, cause));
}


@override
int get hashCode => Object.hash(runtimeType,reason,message,const DeepCollectionEquality().hash(cause));

@override
String toString() {
  return 'ClientConnectionState.failed(reason: $reason, message: $message, cause: $cause)';
}


}

/// @nodoc
abstract mixin class $ClientConnectionFailedCopyWith<$Res> implements $ClientConnectionStateCopyWith<$Res> {
  factory $ClientConnectionFailedCopyWith(ClientConnectionFailed value, $Res Function(ClientConnectionFailed) _then) = _$ClientConnectionFailedCopyWithImpl;
@useResult
$Res call({
 ConnectionFailureReason reason, String message, Object? cause
});




}
/// @nodoc
class _$ClientConnectionFailedCopyWithImpl<$Res>
    implements $ClientConnectionFailedCopyWith<$Res> {
  _$ClientConnectionFailedCopyWithImpl(this._self, this._then);

  final ClientConnectionFailed _self;
  final $Res Function(ClientConnectionFailed) _then;

/// Create a copy of ClientConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,Object? message = null,Object? cause = freezed,}) {
  return _then(ClientConnectionFailed(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ConnectionFailureReason,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,cause: freezed == cause ? _self.cause : cause ,
  ));
}


}

/// @nodoc
mixin _$PromptTurn {

 PromptTurnId get id; SessionId get sessionId; List<ContentBlock> get prompt; PromptTurnStatus get status; StopReason? get stopReason; List<SessionUpdate> get updates; Map<ToolCallId, ToolCallRecord> get toolCalls; Map<ApprovalRequestId, ApprovalRequest> get approvals; String? get failureMessage; DateTime? get startedAt; DateTime? get completedAt;
/// Create a copy of PromptTurn
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptTurnCopyWith<PromptTurn> get copyWith => _$PromptTurnCopyWithImpl<PromptTurn>(this as PromptTurn, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptTurn&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&const DeepCollectionEquality().equals(other.prompt, prompt)&&(identical(other.status, status) || other.status == status)&&(identical(other.stopReason, stopReason) || other.stopReason == stopReason)&&const DeepCollectionEquality().equals(other.updates, updates)&&const DeepCollectionEquality().equals(other.toolCalls, toolCalls)&&const DeepCollectionEquality().equals(other.approvals, approvals)&&(identical(other.failureMessage, failureMessage) || other.failureMessage == failureMessage)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,sessionId,const DeepCollectionEquality().hash(prompt),status,stopReason,const DeepCollectionEquality().hash(updates),const DeepCollectionEquality().hash(toolCalls),const DeepCollectionEquality().hash(approvals),failureMessage,startedAt,completedAt);

@override
String toString() {
  return 'PromptTurn(id: $id, sessionId: $sessionId, prompt: $prompt, status: $status, stopReason: $stopReason, updates: $updates, toolCalls: $toolCalls, approvals: $approvals, failureMessage: $failureMessage, startedAt: $startedAt, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $PromptTurnCopyWith<$Res>  {
  factory $PromptTurnCopyWith(PromptTurn value, $Res Function(PromptTurn) _then) = _$PromptTurnCopyWithImpl;
@useResult
$Res call({
 PromptTurnId id, SessionId sessionId, List<ContentBlock> prompt, PromptTurnStatus status, StopReason? stopReason, List<SessionUpdate> updates, Map<ToolCallId, ToolCallRecord> toolCalls, Map<ApprovalRequestId, ApprovalRequest> approvals, String? failureMessage, DateTime? startedAt, DateTime? completedAt
});


$PromptTurnIdCopyWith<$Res> get id;$SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class _$PromptTurnCopyWithImpl<$Res>
    implements $PromptTurnCopyWith<$Res> {
  _$PromptTurnCopyWithImpl(this._self, this._then);

  final PromptTurn _self;
  final $Res Function(PromptTurn) _then;

/// Create a copy of PromptTurn
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sessionId = null,Object? prompt = null,Object? status = null,Object? stopReason = freezed,Object? updates = null,Object? toolCalls = null,Object? approvals = null,Object? failureMessage = freezed,Object? startedAt = freezed,Object? completedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as PromptTurnId,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as List<ContentBlock>,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PromptTurnStatus,stopReason: freezed == stopReason ? _self.stopReason : stopReason // ignore: cast_nullable_to_non_nullable
as StopReason?,updates: null == updates ? _self.updates : updates // ignore: cast_nullable_to_non_nullable
as List<SessionUpdate>,toolCalls: null == toolCalls ? _self.toolCalls : toolCalls // ignore: cast_nullable_to_non_nullable
as Map<ToolCallId, ToolCallRecord>,approvals: null == approvals ? _self.approvals : approvals // ignore: cast_nullable_to_non_nullable
as Map<ApprovalRequestId, ApprovalRequest>,failureMessage: freezed == failureMessage ? _self.failureMessage : failureMessage // ignore: cast_nullable_to_non_nullable
as String?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of PromptTurn
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PromptTurnIdCopyWith<$Res> get id {
  
  return $PromptTurnIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of PromptTurn
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}
}


/// Adds pattern-matching-related methods to [PromptTurn].
extension PromptTurnPatterns on PromptTurn {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PromptTurn value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PromptTurn() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PromptTurn value)  $default,){
final _that = this;
switch (_that) {
case _PromptTurn():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PromptTurn value)?  $default,){
final _that = this;
switch (_that) {
case _PromptTurn() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PromptTurnId id,  SessionId sessionId,  List<ContentBlock> prompt,  PromptTurnStatus status,  StopReason? stopReason,  List<SessionUpdate> updates,  Map<ToolCallId, ToolCallRecord> toolCalls,  Map<ApprovalRequestId, ApprovalRequest> approvals,  String? failureMessage,  DateTime? startedAt,  DateTime? completedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PromptTurn() when $default != null:
return $default(_that.id,_that.sessionId,_that.prompt,_that.status,_that.stopReason,_that.updates,_that.toolCalls,_that.approvals,_that.failureMessage,_that.startedAt,_that.completedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PromptTurnId id,  SessionId sessionId,  List<ContentBlock> prompt,  PromptTurnStatus status,  StopReason? stopReason,  List<SessionUpdate> updates,  Map<ToolCallId, ToolCallRecord> toolCalls,  Map<ApprovalRequestId, ApprovalRequest> approvals,  String? failureMessage,  DateTime? startedAt,  DateTime? completedAt)  $default,) {final _that = this;
switch (_that) {
case _PromptTurn():
return $default(_that.id,_that.sessionId,_that.prompt,_that.status,_that.stopReason,_that.updates,_that.toolCalls,_that.approvals,_that.failureMessage,_that.startedAt,_that.completedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PromptTurnId id,  SessionId sessionId,  List<ContentBlock> prompt,  PromptTurnStatus status,  StopReason? stopReason,  List<SessionUpdate> updates,  Map<ToolCallId, ToolCallRecord> toolCalls,  Map<ApprovalRequestId, ApprovalRequest> approvals,  String? failureMessage,  DateTime? startedAt,  DateTime? completedAt)?  $default,) {final _that = this;
switch (_that) {
case _PromptTurn() when $default != null:
return $default(_that.id,_that.sessionId,_that.prompt,_that.status,_that.stopReason,_that.updates,_that.toolCalls,_that.approvals,_that.failureMessage,_that.startedAt,_that.completedAt);case _:
  return null;

}
}

}

/// @nodoc


class _PromptTurn extends PromptTurn {
  const _PromptTurn({required this.id, required this.sessionId, required final  List<ContentBlock> prompt, this.status = PromptTurnStatus.pending, this.stopReason, final  List<SessionUpdate> updates = const [], final  Map<ToolCallId, ToolCallRecord> toolCalls = const {}, final  Map<ApprovalRequestId, ApprovalRequest> approvals = const {}, this.failureMessage, this.startedAt, this.completedAt}): _prompt = prompt,_updates = updates,_toolCalls = toolCalls,_approvals = approvals,super._();
  

@override final  PromptTurnId id;
@override final  SessionId sessionId;
 final  List<ContentBlock> _prompt;
@override List<ContentBlock> get prompt {
  if (_prompt is EqualUnmodifiableListView) return _prompt;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_prompt);
}

@override@JsonKey() final  PromptTurnStatus status;
@override final  StopReason? stopReason;
 final  List<SessionUpdate> _updates;
@override@JsonKey() List<SessionUpdate> get updates {
  if (_updates is EqualUnmodifiableListView) return _updates;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_updates);
}

 final  Map<ToolCallId, ToolCallRecord> _toolCalls;
@override@JsonKey() Map<ToolCallId, ToolCallRecord> get toolCalls {
  if (_toolCalls is EqualUnmodifiableMapView) return _toolCalls;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_toolCalls);
}

 final  Map<ApprovalRequestId, ApprovalRequest> _approvals;
@override@JsonKey() Map<ApprovalRequestId, ApprovalRequest> get approvals {
  if (_approvals is EqualUnmodifiableMapView) return _approvals;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_approvals);
}

@override final  String? failureMessage;
@override final  DateTime? startedAt;
@override final  DateTime? completedAt;

/// Create a copy of PromptTurn
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PromptTurnCopyWith<_PromptTurn> get copyWith => __$PromptTurnCopyWithImpl<_PromptTurn>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PromptTurn&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&const DeepCollectionEquality().equals(other._prompt, _prompt)&&(identical(other.status, status) || other.status == status)&&(identical(other.stopReason, stopReason) || other.stopReason == stopReason)&&const DeepCollectionEquality().equals(other._updates, _updates)&&const DeepCollectionEquality().equals(other._toolCalls, _toolCalls)&&const DeepCollectionEquality().equals(other._approvals, _approvals)&&(identical(other.failureMessage, failureMessage) || other.failureMessage == failureMessage)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,sessionId,const DeepCollectionEquality().hash(_prompt),status,stopReason,const DeepCollectionEquality().hash(_updates),const DeepCollectionEquality().hash(_toolCalls),const DeepCollectionEquality().hash(_approvals),failureMessage,startedAt,completedAt);

@override
String toString() {
  return 'PromptTurn(id: $id, sessionId: $sessionId, prompt: $prompt, status: $status, stopReason: $stopReason, updates: $updates, toolCalls: $toolCalls, approvals: $approvals, failureMessage: $failureMessage, startedAt: $startedAt, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class _$PromptTurnCopyWith<$Res> implements $PromptTurnCopyWith<$Res> {
  factory _$PromptTurnCopyWith(_PromptTurn value, $Res Function(_PromptTurn) _then) = __$PromptTurnCopyWithImpl;
@override @useResult
$Res call({
 PromptTurnId id, SessionId sessionId, List<ContentBlock> prompt, PromptTurnStatus status, StopReason? stopReason, List<SessionUpdate> updates, Map<ToolCallId, ToolCallRecord> toolCalls, Map<ApprovalRequestId, ApprovalRequest> approvals, String? failureMessage, DateTime? startedAt, DateTime? completedAt
});


@override $PromptTurnIdCopyWith<$Res> get id;@override $SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class __$PromptTurnCopyWithImpl<$Res>
    implements _$PromptTurnCopyWith<$Res> {
  __$PromptTurnCopyWithImpl(this._self, this._then);

  final _PromptTurn _self;
  final $Res Function(_PromptTurn) _then;

/// Create a copy of PromptTurn
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sessionId = null,Object? prompt = null,Object? status = null,Object? stopReason = freezed,Object? updates = null,Object? toolCalls = null,Object? approvals = null,Object? failureMessage = freezed,Object? startedAt = freezed,Object? completedAt = freezed,}) {
  return _then(_PromptTurn(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as PromptTurnId,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,prompt: null == prompt ? _self._prompt : prompt // ignore: cast_nullable_to_non_nullable
as List<ContentBlock>,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PromptTurnStatus,stopReason: freezed == stopReason ? _self.stopReason : stopReason // ignore: cast_nullable_to_non_nullable
as StopReason?,updates: null == updates ? _self._updates : updates // ignore: cast_nullable_to_non_nullable
as List<SessionUpdate>,toolCalls: null == toolCalls ? _self._toolCalls : toolCalls // ignore: cast_nullable_to_non_nullable
as Map<ToolCallId, ToolCallRecord>,approvals: null == approvals ? _self._approvals : approvals // ignore: cast_nullable_to_non_nullable
as Map<ApprovalRequestId, ApprovalRequest>,failureMessage: freezed == failureMessage ? _self.failureMessage : failureMessage // ignore: cast_nullable_to_non_nullable
as String?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of PromptTurn
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PromptTurnIdCopyWith<$Res> get id {
  
  return $PromptTurnIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of PromptTurn
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
mixin _$ApprovalRequest {

 ApprovalRequestId get id; SessionId get sessionId; PromptTurnId get turnId; ToolCallRecord get toolCall; List<PermissionOption> get options; ApprovalRiskLevel get riskLevel; ApprovalStatus get status; PermissionOptionId? get selectedOptionId; DateTime? get requestedAt; DateTime? get resolvedAt;
/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApprovalRequestCopyWith<ApprovalRequest> get copyWith => _$ApprovalRequestCopyWithImpl<ApprovalRequest>(this as ApprovalRequest, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ApprovalRequest&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.toolCall, toolCall) || other.toolCall == toolCall)&&const DeepCollectionEquality().equals(other.options, options)&&(identical(other.riskLevel, riskLevel) || other.riskLevel == riskLevel)&&(identical(other.status, status) || other.status == status)&&(identical(other.selectedOptionId, selectedOptionId) || other.selectedOptionId == selectedOptionId)&&(identical(other.requestedAt, requestedAt) || other.requestedAt == requestedAt)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,sessionId,turnId,toolCall,const DeepCollectionEquality().hash(options),riskLevel,status,selectedOptionId,requestedAt,resolvedAt);

@override
String toString() {
  return 'ApprovalRequest(id: $id, sessionId: $sessionId, turnId: $turnId, toolCall: $toolCall, options: $options, riskLevel: $riskLevel, status: $status, selectedOptionId: $selectedOptionId, requestedAt: $requestedAt, resolvedAt: $resolvedAt)';
}


}

/// @nodoc
abstract mixin class $ApprovalRequestCopyWith<$Res>  {
  factory $ApprovalRequestCopyWith(ApprovalRequest value, $Res Function(ApprovalRequest) _then) = _$ApprovalRequestCopyWithImpl;
@useResult
$Res call({
 ApprovalRequestId id, SessionId sessionId, PromptTurnId turnId, ToolCallRecord toolCall, List<PermissionOption> options, ApprovalRiskLevel riskLevel, ApprovalStatus status, PermissionOptionId? selectedOptionId, DateTime? requestedAt, DateTime? resolvedAt
});


$ApprovalRequestIdCopyWith<$Res> get id;$SessionIdCopyWith<$Res> get sessionId;$PromptTurnIdCopyWith<$Res> get turnId;$ToolCallRecordCopyWith<$Res> get toolCall;$PermissionOptionIdCopyWith<$Res>? get selectedOptionId;

}
/// @nodoc
class _$ApprovalRequestCopyWithImpl<$Res>
    implements $ApprovalRequestCopyWith<$Res> {
  _$ApprovalRequestCopyWithImpl(this._self, this._then);

  final ApprovalRequest _self;
  final $Res Function(ApprovalRequest) _then;

/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sessionId = null,Object? turnId = null,Object? toolCall = null,Object? options = null,Object? riskLevel = null,Object? status = null,Object? selectedOptionId = freezed,Object? requestedAt = freezed,Object? resolvedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ApprovalRequestId,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as PromptTurnId,toolCall: null == toolCall ? _self.toolCall : toolCall // ignore: cast_nullable_to_non_nullable
as ToolCallRecord,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<PermissionOption>,riskLevel: null == riskLevel ? _self.riskLevel : riskLevel // ignore: cast_nullable_to_non_nullable
as ApprovalRiskLevel,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ApprovalStatus,selectedOptionId: freezed == selectedOptionId ? _self.selectedOptionId : selectedOptionId // ignore: cast_nullable_to_non_nullable
as PermissionOptionId?,requestedAt: freezed == requestedAt ? _self.requestedAt : requestedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ApprovalRequestIdCopyWith<$Res> get id {
  
  return $ApprovalRequestIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PromptTurnIdCopyWith<$Res> get turnId {
  
  return $PromptTurnIdCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ToolCallRecordCopyWith<$Res> get toolCall {
  
  return $ToolCallRecordCopyWith<$Res>(_self.toolCall, (value) {
    return _then(_self.copyWith(toolCall: value));
  });
}/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PermissionOptionIdCopyWith<$Res>? get selectedOptionId {
    if (_self.selectedOptionId == null) {
    return null;
  }

  return $PermissionOptionIdCopyWith<$Res>(_self.selectedOptionId!, (value) {
    return _then(_self.copyWith(selectedOptionId: value));
  });
}
}


/// Adds pattern-matching-related methods to [ApprovalRequest].
extension ApprovalRequestPatterns on ApprovalRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ApprovalRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ApprovalRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ApprovalRequest value)  $default,){
final _that = this;
switch (_that) {
case _ApprovalRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ApprovalRequest value)?  $default,){
final _that = this;
switch (_that) {
case _ApprovalRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ApprovalRequestId id,  SessionId sessionId,  PromptTurnId turnId,  ToolCallRecord toolCall,  List<PermissionOption> options,  ApprovalRiskLevel riskLevel,  ApprovalStatus status,  PermissionOptionId? selectedOptionId,  DateTime? requestedAt,  DateTime? resolvedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ApprovalRequest() when $default != null:
return $default(_that.id,_that.sessionId,_that.turnId,_that.toolCall,_that.options,_that.riskLevel,_that.status,_that.selectedOptionId,_that.requestedAt,_that.resolvedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ApprovalRequestId id,  SessionId sessionId,  PromptTurnId turnId,  ToolCallRecord toolCall,  List<PermissionOption> options,  ApprovalRiskLevel riskLevel,  ApprovalStatus status,  PermissionOptionId? selectedOptionId,  DateTime? requestedAt,  DateTime? resolvedAt)  $default,) {final _that = this;
switch (_that) {
case _ApprovalRequest():
return $default(_that.id,_that.sessionId,_that.turnId,_that.toolCall,_that.options,_that.riskLevel,_that.status,_that.selectedOptionId,_that.requestedAt,_that.resolvedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ApprovalRequestId id,  SessionId sessionId,  PromptTurnId turnId,  ToolCallRecord toolCall,  List<PermissionOption> options,  ApprovalRiskLevel riskLevel,  ApprovalStatus status,  PermissionOptionId? selectedOptionId,  DateTime? requestedAt,  DateTime? resolvedAt)?  $default,) {final _that = this;
switch (_that) {
case _ApprovalRequest() when $default != null:
return $default(_that.id,_that.sessionId,_that.turnId,_that.toolCall,_that.options,_that.riskLevel,_that.status,_that.selectedOptionId,_that.requestedAt,_that.resolvedAt);case _:
  return null;

}
}

}

/// @nodoc


class _ApprovalRequest extends ApprovalRequest {
  const _ApprovalRequest({required this.id, required this.sessionId, required this.turnId, required this.toolCall, required final  List<PermissionOption> options, this.riskLevel = ApprovalRiskLevel.readOnly, this.status = ApprovalStatus.pending, this.selectedOptionId, this.requestedAt, this.resolvedAt}): _options = options,super._();
  

@override final  ApprovalRequestId id;
@override final  SessionId sessionId;
@override final  PromptTurnId turnId;
@override final  ToolCallRecord toolCall;
 final  List<PermissionOption> _options;
@override List<PermissionOption> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}

@override@JsonKey() final  ApprovalRiskLevel riskLevel;
@override@JsonKey() final  ApprovalStatus status;
@override final  PermissionOptionId? selectedOptionId;
@override final  DateTime? requestedAt;
@override final  DateTime? resolvedAt;

/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ApprovalRequestCopyWith<_ApprovalRequest> get copyWith => __$ApprovalRequestCopyWithImpl<_ApprovalRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ApprovalRequest&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.toolCall, toolCall) || other.toolCall == toolCall)&&const DeepCollectionEquality().equals(other._options, _options)&&(identical(other.riskLevel, riskLevel) || other.riskLevel == riskLevel)&&(identical(other.status, status) || other.status == status)&&(identical(other.selectedOptionId, selectedOptionId) || other.selectedOptionId == selectedOptionId)&&(identical(other.requestedAt, requestedAt) || other.requestedAt == requestedAt)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,sessionId,turnId,toolCall,const DeepCollectionEquality().hash(_options),riskLevel,status,selectedOptionId,requestedAt,resolvedAt);

@override
String toString() {
  return 'ApprovalRequest(id: $id, sessionId: $sessionId, turnId: $turnId, toolCall: $toolCall, options: $options, riskLevel: $riskLevel, status: $status, selectedOptionId: $selectedOptionId, requestedAt: $requestedAt, resolvedAt: $resolvedAt)';
}


}

/// @nodoc
abstract mixin class _$ApprovalRequestCopyWith<$Res> implements $ApprovalRequestCopyWith<$Res> {
  factory _$ApprovalRequestCopyWith(_ApprovalRequest value, $Res Function(_ApprovalRequest) _then) = __$ApprovalRequestCopyWithImpl;
@override @useResult
$Res call({
 ApprovalRequestId id, SessionId sessionId, PromptTurnId turnId, ToolCallRecord toolCall, List<PermissionOption> options, ApprovalRiskLevel riskLevel, ApprovalStatus status, PermissionOptionId? selectedOptionId, DateTime? requestedAt, DateTime? resolvedAt
});


@override $ApprovalRequestIdCopyWith<$Res> get id;@override $SessionIdCopyWith<$Res> get sessionId;@override $PromptTurnIdCopyWith<$Res> get turnId;@override $ToolCallRecordCopyWith<$Res> get toolCall;@override $PermissionOptionIdCopyWith<$Res>? get selectedOptionId;

}
/// @nodoc
class __$ApprovalRequestCopyWithImpl<$Res>
    implements _$ApprovalRequestCopyWith<$Res> {
  __$ApprovalRequestCopyWithImpl(this._self, this._then);

  final _ApprovalRequest _self;
  final $Res Function(_ApprovalRequest) _then;

/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sessionId = null,Object? turnId = null,Object? toolCall = null,Object? options = null,Object? riskLevel = null,Object? status = null,Object? selectedOptionId = freezed,Object? requestedAt = freezed,Object? resolvedAt = freezed,}) {
  return _then(_ApprovalRequest(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ApprovalRequestId,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as PromptTurnId,toolCall: null == toolCall ? _self.toolCall : toolCall // ignore: cast_nullable_to_non_nullable
as ToolCallRecord,options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<PermissionOption>,riskLevel: null == riskLevel ? _self.riskLevel : riskLevel // ignore: cast_nullable_to_non_nullable
as ApprovalRiskLevel,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ApprovalStatus,selectedOptionId: freezed == selectedOptionId ? _self.selectedOptionId : selectedOptionId // ignore: cast_nullable_to_non_nullable
as PermissionOptionId?,requestedAt: freezed == requestedAt ? _self.requestedAt : requestedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ApprovalRequestIdCopyWith<$Res> get id {
  
  return $ApprovalRequestIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PromptTurnIdCopyWith<$Res> get turnId {
  
  return $PromptTurnIdCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ToolCallRecordCopyWith<$Res> get toolCall {
  
  return $ToolCallRecordCopyWith<$Res>(_self.toolCall, (value) {
    return _then(_self.copyWith(toolCall: value));
  });
}/// Create a copy of ApprovalRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PermissionOptionIdCopyWith<$Res>? get selectedOptionId {
    if (_self.selectedOptionId == null) {
    return null;
  }

  return $PermissionOptionIdCopyWith<$Res>(_self.selectedOptionId!, (value) {
    return _then(_self.copyWith(selectedOptionId: value));
  });
}
}

/// @nodoc
mixin _$ToolCallRecord {

 ToolCallId get id; String get title; ToolKind get kind; ToolCallStatus get status; ApprovalRiskLevel get riskLevel; List<ToolCallContent> get content; List<ToolCallLocation> get locations; Map<String, Object?>? get rawInput; Map<String, Object?>? get rawOutput; DateTime? get startedAt; DateTime? get completedAt;
/// Create a copy of ToolCallRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ToolCallRecordCopyWith<ToolCallRecord> get copyWith => _$ToolCallRecordCopyWithImpl<ToolCallRecord>(this as ToolCallRecord, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ToolCallRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.status, status) || other.status == status)&&(identical(other.riskLevel, riskLevel) || other.riskLevel == riskLevel)&&const DeepCollectionEquality().equals(other.content, content)&&const DeepCollectionEquality().equals(other.locations, locations)&&const DeepCollectionEquality().equals(other.rawInput, rawInput)&&const DeepCollectionEquality().equals(other.rawOutput, rawOutput)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,kind,status,riskLevel,const DeepCollectionEquality().hash(content),const DeepCollectionEquality().hash(locations),const DeepCollectionEquality().hash(rawInput),const DeepCollectionEquality().hash(rawOutput),startedAt,completedAt);

@override
String toString() {
  return 'ToolCallRecord(id: $id, title: $title, kind: $kind, status: $status, riskLevel: $riskLevel, content: $content, locations: $locations, rawInput: $rawInput, rawOutput: $rawOutput, startedAt: $startedAt, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $ToolCallRecordCopyWith<$Res>  {
  factory $ToolCallRecordCopyWith(ToolCallRecord value, $Res Function(ToolCallRecord) _then) = _$ToolCallRecordCopyWithImpl;
@useResult
$Res call({
 ToolCallId id, String title, ToolKind kind, ToolCallStatus status, ApprovalRiskLevel riskLevel, List<ToolCallContent> content, List<ToolCallLocation> locations, Map<String, Object?>? rawInput, Map<String, Object?>? rawOutput, DateTime? startedAt, DateTime? completedAt
});


$ToolCallIdCopyWith<$Res> get id;

}
/// @nodoc
class _$ToolCallRecordCopyWithImpl<$Res>
    implements $ToolCallRecordCopyWith<$Res> {
  _$ToolCallRecordCopyWithImpl(this._self, this._then);

  final ToolCallRecord _self;
  final $Res Function(ToolCallRecord) _then;

/// Create a copy of ToolCallRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? kind = null,Object? status = null,Object? riskLevel = null,Object? content = null,Object? locations = null,Object? rawInput = freezed,Object? rawOutput = freezed,Object? startedAt = freezed,Object? completedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ToolCallId,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ToolKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ToolCallStatus,riskLevel: null == riskLevel ? _self.riskLevel : riskLevel // ignore: cast_nullable_to_non_nullable
as ApprovalRiskLevel,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as List<ToolCallContent>,locations: null == locations ? _self.locations : locations // ignore: cast_nullable_to_non_nullable
as List<ToolCallLocation>,rawInput: freezed == rawInput ? _self.rawInput : rawInput // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,rawOutput: freezed == rawOutput ? _self.rawOutput : rawOutput // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of ToolCallRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ToolCallIdCopyWith<$Res> get id {
  
  return $ToolCallIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}
}


/// Adds pattern-matching-related methods to [ToolCallRecord].
extension ToolCallRecordPatterns on ToolCallRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ToolCallRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ToolCallRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ToolCallRecord value)  $default,){
final _that = this;
switch (_that) {
case _ToolCallRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ToolCallRecord value)?  $default,){
final _that = this;
switch (_that) {
case _ToolCallRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ToolCallId id,  String title,  ToolKind kind,  ToolCallStatus status,  ApprovalRiskLevel riskLevel,  List<ToolCallContent> content,  List<ToolCallLocation> locations,  Map<String, Object?>? rawInput,  Map<String, Object?>? rawOutput,  DateTime? startedAt,  DateTime? completedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ToolCallRecord() when $default != null:
return $default(_that.id,_that.title,_that.kind,_that.status,_that.riskLevel,_that.content,_that.locations,_that.rawInput,_that.rawOutput,_that.startedAt,_that.completedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ToolCallId id,  String title,  ToolKind kind,  ToolCallStatus status,  ApprovalRiskLevel riskLevel,  List<ToolCallContent> content,  List<ToolCallLocation> locations,  Map<String, Object?>? rawInput,  Map<String, Object?>? rawOutput,  DateTime? startedAt,  DateTime? completedAt)  $default,) {final _that = this;
switch (_that) {
case _ToolCallRecord():
return $default(_that.id,_that.title,_that.kind,_that.status,_that.riskLevel,_that.content,_that.locations,_that.rawInput,_that.rawOutput,_that.startedAt,_that.completedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ToolCallId id,  String title,  ToolKind kind,  ToolCallStatus status,  ApprovalRiskLevel riskLevel,  List<ToolCallContent> content,  List<ToolCallLocation> locations,  Map<String, Object?>? rawInput,  Map<String, Object?>? rawOutput,  DateTime? startedAt,  DateTime? completedAt)?  $default,) {final _that = this;
switch (_that) {
case _ToolCallRecord() when $default != null:
return $default(_that.id,_that.title,_that.kind,_that.status,_that.riskLevel,_that.content,_that.locations,_that.rawInput,_that.rawOutput,_that.startedAt,_that.completedAt);case _:
  return null;

}
}

}

/// @nodoc


class _ToolCallRecord extends ToolCallRecord {
  const _ToolCallRecord({required this.id, required this.title, this.kind = ToolKind.other, this.status = ToolCallStatus.pending, this.riskLevel = ApprovalRiskLevel.readOnly, final  List<ToolCallContent> content = const [], final  List<ToolCallLocation> locations = const [], final  Map<String, Object?>? rawInput, final  Map<String, Object?>? rawOutput, this.startedAt, this.completedAt}): _content = content,_locations = locations,_rawInput = rawInput,_rawOutput = rawOutput,super._();
  

@override final  ToolCallId id;
@override final  String title;
@override@JsonKey() final  ToolKind kind;
@override@JsonKey() final  ToolCallStatus status;
@override@JsonKey() final  ApprovalRiskLevel riskLevel;
 final  List<ToolCallContent> _content;
@override@JsonKey() List<ToolCallContent> get content {
  if (_content is EqualUnmodifiableListView) return _content;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_content);
}

 final  List<ToolCallLocation> _locations;
@override@JsonKey() List<ToolCallLocation> get locations {
  if (_locations is EqualUnmodifiableListView) return _locations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_locations);
}

 final  Map<String, Object?>? _rawInput;
@override Map<String, Object?>? get rawInput {
  final value = _rawInput;
  if (value == null) return null;
  if (_rawInput is EqualUnmodifiableMapView) return _rawInput;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

 final  Map<String, Object?>? _rawOutput;
@override Map<String, Object?>? get rawOutput {
  final value = _rawOutput;
  if (value == null) return null;
  if (_rawOutput is EqualUnmodifiableMapView) return _rawOutput;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override final  DateTime? startedAt;
@override final  DateTime? completedAt;

/// Create a copy of ToolCallRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ToolCallRecordCopyWith<_ToolCallRecord> get copyWith => __$ToolCallRecordCopyWithImpl<_ToolCallRecord>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ToolCallRecord&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.status, status) || other.status == status)&&(identical(other.riskLevel, riskLevel) || other.riskLevel == riskLevel)&&const DeepCollectionEquality().equals(other._content, _content)&&const DeepCollectionEquality().equals(other._locations, _locations)&&const DeepCollectionEquality().equals(other._rawInput, _rawInput)&&const DeepCollectionEquality().equals(other._rawOutput, _rawOutput)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,kind,status,riskLevel,const DeepCollectionEquality().hash(_content),const DeepCollectionEquality().hash(_locations),const DeepCollectionEquality().hash(_rawInput),const DeepCollectionEquality().hash(_rawOutput),startedAt,completedAt);

@override
String toString() {
  return 'ToolCallRecord(id: $id, title: $title, kind: $kind, status: $status, riskLevel: $riskLevel, content: $content, locations: $locations, rawInput: $rawInput, rawOutput: $rawOutput, startedAt: $startedAt, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class _$ToolCallRecordCopyWith<$Res> implements $ToolCallRecordCopyWith<$Res> {
  factory _$ToolCallRecordCopyWith(_ToolCallRecord value, $Res Function(_ToolCallRecord) _then) = __$ToolCallRecordCopyWithImpl;
@override @useResult
$Res call({
 ToolCallId id, String title, ToolKind kind, ToolCallStatus status, ApprovalRiskLevel riskLevel, List<ToolCallContent> content, List<ToolCallLocation> locations, Map<String, Object?>? rawInput, Map<String, Object?>? rawOutput, DateTime? startedAt, DateTime? completedAt
});


@override $ToolCallIdCopyWith<$Res> get id;

}
/// @nodoc
class __$ToolCallRecordCopyWithImpl<$Res>
    implements _$ToolCallRecordCopyWith<$Res> {
  __$ToolCallRecordCopyWithImpl(this._self, this._then);

  final _ToolCallRecord _self;
  final $Res Function(_ToolCallRecord) _then;

/// Create a copy of ToolCallRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? kind = null,Object? status = null,Object? riskLevel = null,Object? content = null,Object? locations = null,Object? rawInput = freezed,Object? rawOutput = freezed,Object? startedAt = freezed,Object? completedAt = freezed,}) {
  return _then(_ToolCallRecord(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ToolCallId,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ToolKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ToolCallStatus,riskLevel: null == riskLevel ? _self.riskLevel : riskLevel // ignore: cast_nullable_to_non_nullable
as ApprovalRiskLevel,content: null == content ? _self._content : content // ignore: cast_nullable_to_non_nullable
as List<ToolCallContent>,locations: null == locations ? _self._locations : locations // ignore: cast_nullable_to_non_nullable
as List<ToolCallLocation>,rawInput: freezed == rawInput ? _self._rawInput : rawInput // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,rawOutput: freezed == rawOutput ? _self._rawOutput : rawOutput // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of ToolCallRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ToolCallIdCopyWith<$Res> get id {
  
  return $ToolCallIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}
}

/// @nodoc
mixin _$AcpSession {

 SessionId get id; String get cwd; String? get title; SessionLifecycleStatus get status; List<PromptTurn> get turns; List<DiagnosticEntry> get diagnostics; SessionModeState? get modes; List<SessionConfigOption>? get configOptions; DateTime? get createdAt; DateTime? get updatedAt;
/// Create a copy of AcpSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpSessionCopyWith<AcpSession> get copyWith => _$AcpSessionCopyWithImpl<AcpSession>(this as AcpSession, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpSession&&(identical(other.id, id) || other.id == id)&&(identical(other.cwd, cwd) || other.cwd == cwd)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.turns, turns)&&const DeepCollectionEquality().equals(other.diagnostics, diagnostics)&&(identical(other.modes, modes) || other.modes == modes)&&const DeepCollectionEquality().equals(other.configOptions, configOptions)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,cwd,title,status,const DeepCollectionEquality().hash(turns),const DeepCollectionEquality().hash(diagnostics),modes,const DeepCollectionEquality().hash(configOptions),createdAt,updatedAt);

@override
String toString() {
  return 'AcpSession(id: $id, cwd: $cwd, title: $title, status: $status, turns: $turns, diagnostics: $diagnostics, modes: $modes, configOptions: $configOptions, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $AcpSessionCopyWith<$Res>  {
  factory $AcpSessionCopyWith(AcpSession value, $Res Function(AcpSession) _then) = _$AcpSessionCopyWithImpl;
@useResult
$Res call({
 SessionId id, String cwd, String? title, SessionLifecycleStatus status, List<PromptTurn> turns, List<DiagnosticEntry> diagnostics, SessionModeState? modes, List<SessionConfigOption>? configOptions, DateTime? createdAt, DateTime? updatedAt
});


$SessionIdCopyWith<$Res> get id;$SessionModeStateCopyWith<$Res>? get modes;

}
/// @nodoc
class _$AcpSessionCopyWithImpl<$Res>
    implements $AcpSessionCopyWith<$Res> {
  _$AcpSessionCopyWithImpl(this._self, this._then);

  final AcpSession _self;
  final $Res Function(AcpSession) _then;

/// Create a copy of AcpSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? cwd = null,Object? title = freezed,Object? status = null,Object? turns = null,Object? diagnostics = null,Object? modes = freezed,Object? configOptions = freezed,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as SessionId,cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as SessionLifecycleStatus,turns: null == turns ? _self.turns : turns // ignore: cast_nullable_to_non_nullable
as List<PromptTurn>,diagnostics: null == diagnostics ? _self.diagnostics : diagnostics // ignore: cast_nullable_to_non_nullable
as List<DiagnosticEntry>,modes: freezed == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as SessionModeState?,configOptions: freezed == configOptions ? _self.configOptions : configOptions // ignore: cast_nullable_to_non_nullable
as List<SessionConfigOption>?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of AcpSession
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get id {
  
  return $SessionIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of AcpSession
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


/// Adds pattern-matching-related methods to [AcpSession].
extension AcpSessionPatterns on AcpSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpSession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpSession value)  $default,){
final _that = this;
switch (_that) {
case _AcpSession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpSession value)?  $default,){
final _that = this;
switch (_that) {
case _AcpSession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionId id,  String cwd,  String? title,  SessionLifecycleStatus status,  List<PromptTurn> turns,  List<DiagnosticEntry> diagnostics,  SessionModeState? modes,  List<SessionConfigOption>? configOptions,  DateTime? createdAt,  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpSession() when $default != null:
return $default(_that.id,_that.cwd,_that.title,_that.status,_that.turns,_that.diagnostics,_that.modes,_that.configOptions,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionId id,  String cwd,  String? title,  SessionLifecycleStatus status,  List<PromptTurn> turns,  List<DiagnosticEntry> diagnostics,  SessionModeState? modes,  List<SessionConfigOption>? configOptions,  DateTime? createdAt,  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _AcpSession():
return $default(_that.id,_that.cwd,_that.title,_that.status,_that.turns,_that.diagnostics,_that.modes,_that.configOptions,_that.createdAt,_that.updatedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionId id,  String cwd,  String? title,  SessionLifecycleStatus status,  List<PromptTurn> turns,  List<DiagnosticEntry> diagnostics,  SessionModeState? modes,  List<SessionConfigOption>? configOptions,  DateTime? createdAt,  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _AcpSession() when $default != null:
return $default(_that.id,_that.cwd,_that.title,_that.status,_that.turns,_that.diagnostics,_that.modes,_that.configOptions,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _AcpSession extends AcpSession {
  const _AcpSession({required this.id, required this.cwd, this.title, this.status = SessionLifecycleStatus.idle, final  List<PromptTurn> turns = const [], final  List<DiagnosticEntry> diagnostics = const [], this.modes, final  List<SessionConfigOption>? configOptions, this.createdAt, this.updatedAt}): _turns = turns,_diagnostics = diagnostics,_configOptions = configOptions,super._();
  

@override final  SessionId id;
@override final  String cwd;
@override final  String? title;
@override@JsonKey() final  SessionLifecycleStatus status;
 final  List<PromptTurn> _turns;
@override@JsonKey() List<PromptTurn> get turns {
  if (_turns is EqualUnmodifiableListView) return _turns;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_turns);
}

 final  List<DiagnosticEntry> _diagnostics;
@override@JsonKey() List<DiagnosticEntry> get diagnostics {
  if (_diagnostics is EqualUnmodifiableListView) return _diagnostics;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_diagnostics);
}

@override final  SessionModeState? modes;
 final  List<SessionConfigOption>? _configOptions;
@override List<SessionConfigOption>? get configOptions {
  final value = _configOptions;
  if (value == null) return null;
  if (_configOptions is EqualUnmodifiableListView) return _configOptions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

@override final  DateTime? createdAt;
@override final  DateTime? updatedAt;

/// Create a copy of AcpSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpSessionCopyWith<_AcpSession> get copyWith => __$AcpSessionCopyWithImpl<_AcpSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpSession&&(identical(other.id, id) || other.id == id)&&(identical(other.cwd, cwd) || other.cwd == cwd)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other._turns, _turns)&&const DeepCollectionEquality().equals(other._diagnostics, _diagnostics)&&(identical(other.modes, modes) || other.modes == modes)&&const DeepCollectionEquality().equals(other._configOptions, _configOptions)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,cwd,title,status,const DeepCollectionEquality().hash(_turns),const DeepCollectionEquality().hash(_diagnostics),modes,const DeepCollectionEquality().hash(_configOptions),createdAt,updatedAt);

@override
String toString() {
  return 'AcpSession(id: $id, cwd: $cwd, title: $title, status: $status, turns: $turns, diagnostics: $diagnostics, modes: $modes, configOptions: $configOptions, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$AcpSessionCopyWith<$Res> implements $AcpSessionCopyWith<$Res> {
  factory _$AcpSessionCopyWith(_AcpSession value, $Res Function(_AcpSession) _then) = __$AcpSessionCopyWithImpl;
@override @useResult
$Res call({
 SessionId id, String cwd, String? title, SessionLifecycleStatus status, List<PromptTurn> turns, List<DiagnosticEntry> diagnostics, SessionModeState? modes, List<SessionConfigOption>? configOptions, DateTime? createdAt, DateTime? updatedAt
});


@override $SessionIdCopyWith<$Res> get id;@override $SessionModeStateCopyWith<$Res>? get modes;

}
/// @nodoc
class __$AcpSessionCopyWithImpl<$Res>
    implements _$AcpSessionCopyWith<$Res> {
  __$AcpSessionCopyWithImpl(this._self, this._then);

  final _AcpSession _self;
  final $Res Function(_AcpSession) _then;

/// Create a copy of AcpSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? cwd = null,Object? title = freezed,Object? status = null,Object? turns = null,Object? diagnostics = null,Object? modes = freezed,Object? configOptions = freezed,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_AcpSession(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as SessionId,cwd: null == cwd ? _self.cwd : cwd // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as SessionLifecycleStatus,turns: null == turns ? _self._turns : turns // ignore: cast_nullable_to_non_nullable
as List<PromptTurn>,diagnostics: null == diagnostics ? _self._diagnostics : diagnostics // ignore: cast_nullable_to_non_nullable
as List<DiagnosticEntry>,modes: freezed == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as SessionModeState?,configOptions: freezed == configOptions ? _self._configOptions : configOptions // ignore: cast_nullable_to_non_nullable
as List<SessionConfigOption>?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of AcpSession
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get id {
  
  return $SessionIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of AcpSession
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
mixin _$DiagnosticEntry {

 DiagnosticEntryId get id; String get message; DiagnosticSeverity get severity; String? get source; Object? get cause; DateTime? get createdAt;
/// Create a copy of DiagnosticEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticEntryCopyWith<DiagnosticEntry> get copyWith => _$DiagnosticEntryCopyWithImpl<DiagnosticEntry>(this as DiagnosticEntry, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.message, message) || other.message == message)&&(identical(other.severity, severity) || other.severity == severity)&&(identical(other.source, source) || other.source == source)&&const DeepCollectionEquality().equals(other.cause, cause)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,message,severity,source,const DeepCollectionEquality().hash(cause),createdAt);

@override
String toString() {
  return 'DiagnosticEntry(id: $id, message: $message, severity: $severity, source: $source, cause: $cause, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $DiagnosticEntryCopyWith<$Res>  {
  factory $DiagnosticEntryCopyWith(DiagnosticEntry value, $Res Function(DiagnosticEntry) _then) = _$DiagnosticEntryCopyWithImpl;
@useResult
$Res call({
 DiagnosticEntryId id, String message, DiagnosticSeverity severity, String? source, Object? cause, DateTime? createdAt
});


$DiagnosticEntryIdCopyWith<$Res> get id;

}
/// @nodoc
class _$DiagnosticEntryCopyWithImpl<$Res>
    implements $DiagnosticEntryCopyWith<$Res> {
  _$DiagnosticEntryCopyWithImpl(this._self, this._then);

  final DiagnosticEntry _self;
  final $Res Function(DiagnosticEntry) _then;

/// Create a copy of DiagnosticEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? message = null,Object? severity = null,Object? source = freezed,Object? cause = freezed,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as DiagnosticEntryId,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,severity: null == severity ? _self.severity : severity // ignore: cast_nullable_to_non_nullable
as DiagnosticSeverity,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,cause: freezed == cause ? _self.cause : cause ,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of DiagnosticEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DiagnosticEntryIdCopyWith<$Res> get id {
  
  return $DiagnosticEntryIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}
}


/// Adds pattern-matching-related methods to [DiagnosticEntry].
extension DiagnosticEntryPatterns on DiagnosticEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DiagnosticEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DiagnosticEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DiagnosticEntry value)  $default,){
final _that = this;
switch (_that) {
case _DiagnosticEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DiagnosticEntry value)?  $default,){
final _that = this;
switch (_that) {
case _DiagnosticEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DiagnosticEntryId id,  String message,  DiagnosticSeverity severity,  String? source,  Object? cause,  DateTime? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DiagnosticEntry() when $default != null:
return $default(_that.id,_that.message,_that.severity,_that.source,_that.cause,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DiagnosticEntryId id,  String message,  DiagnosticSeverity severity,  String? source,  Object? cause,  DateTime? createdAt)  $default,) {final _that = this;
switch (_that) {
case _DiagnosticEntry():
return $default(_that.id,_that.message,_that.severity,_that.source,_that.cause,_that.createdAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DiagnosticEntryId id,  String message,  DiagnosticSeverity severity,  String? source,  Object? cause,  DateTime? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _DiagnosticEntry() when $default != null:
return $default(_that.id,_that.message,_that.severity,_that.source,_that.cause,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _DiagnosticEntry extends DiagnosticEntry {
  const _DiagnosticEntry({required this.id, required this.message, this.severity = DiagnosticSeverity.info, this.source, this.cause, this.createdAt}): super._();
  

@override final  DiagnosticEntryId id;
@override final  String message;
@override@JsonKey() final  DiagnosticSeverity severity;
@override final  String? source;
@override final  Object? cause;
@override final  DateTime? createdAt;

/// Create a copy of DiagnosticEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DiagnosticEntryCopyWith<_DiagnosticEntry> get copyWith => __$DiagnosticEntryCopyWithImpl<_DiagnosticEntry>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DiagnosticEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.message, message) || other.message == message)&&(identical(other.severity, severity) || other.severity == severity)&&(identical(other.source, source) || other.source == source)&&const DeepCollectionEquality().equals(other.cause, cause)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,message,severity,source,const DeepCollectionEquality().hash(cause),createdAt);

@override
String toString() {
  return 'DiagnosticEntry(id: $id, message: $message, severity: $severity, source: $source, cause: $cause, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$DiagnosticEntryCopyWith<$Res> implements $DiagnosticEntryCopyWith<$Res> {
  factory _$DiagnosticEntryCopyWith(_DiagnosticEntry value, $Res Function(_DiagnosticEntry) _then) = __$DiagnosticEntryCopyWithImpl;
@override @useResult
$Res call({
 DiagnosticEntryId id, String message, DiagnosticSeverity severity, String? source, Object? cause, DateTime? createdAt
});


@override $DiagnosticEntryIdCopyWith<$Res> get id;

}
/// @nodoc
class __$DiagnosticEntryCopyWithImpl<$Res>
    implements _$DiagnosticEntryCopyWith<$Res> {
  __$DiagnosticEntryCopyWithImpl(this._self, this._then);

  final _DiagnosticEntry _self;
  final $Res Function(_DiagnosticEntry) _then;

/// Create a copy of DiagnosticEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? message = null,Object? severity = null,Object? source = freezed,Object? cause = freezed,Object? createdAt = freezed,}) {
  return _then(_DiagnosticEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as DiagnosticEntryId,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,severity: null == severity ? _self.severity : severity // ignore: cast_nullable_to_non_nullable
as DiagnosticSeverity,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,cause: freezed == cause ? _self.cause : cause ,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of DiagnosticEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DiagnosticEntryIdCopyWith<$Res> get id {
  
  return $DiagnosticEntryIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}
}

// dart format on
