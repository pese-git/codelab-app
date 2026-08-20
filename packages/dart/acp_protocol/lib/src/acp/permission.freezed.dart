// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'permission.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PermissionOptionId {

 String get value;
/// Create a copy of PermissionOptionId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PermissionOptionIdCopyWith<PermissionOptionId> get copyWith => _$PermissionOptionIdCopyWithImpl<PermissionOptionId>(this as PermissionOptionId, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PermissionOptionId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'PermissionOptionId(value: $value)';
}


}

/// @nodoc
abstract mixin class $PermissionOptionIdCopyWith<$Res>  {
  factory $PermissionOptionIdCopyWith(PermissionOptionId value, $Res Function(PermissionOptionId) _then) = _$PermissionOptionIdCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$PermissionOptionIdCopyWithImpl<$Res>
    implements $PermissionOptionIdCopyWith<$Res> {
  _$PermissionOptionIdCopyWithImpl(this._self, this._then);

  final PermissionOptionId _self;
  final $Res Function(PermissionOptionId) _then;

/// Create a copy of PermissionOptionId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(_self.copyWith(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PermissionOptionId].
extension PermissionOptionIdPatterns on PermissionOptionId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PermissionOptionId value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PermissionOptionId() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PermissionOptionId value)  $default,){
final _that = this;
switch (_that) {
case _PermissionOptionId():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PermissionOptionId value)?  $default,){
final _that = this;
switch (_that) {
case _PermissionOptionId() when $default != null:
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
case _PermissionOptionId() when $default != null:
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
case _PermissionOptionId():
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
case _PermissionOptionId() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _PermissionOptionId extends PermissionOptionId {
  const _PermissionOptionId(this.value): super._();
  

@override final  String value;

/// Create a copy of PermissionOptionId
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PermissionOptionIdCopyWith<_PermissionOptionId> get copyWith => __$PermissionOptionIdCopyWithImpl<_PermissionOptionId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PermissionOptionId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'PermissionOptionId(value: $value)';
}


}

/// @nodoc
abstract mixin class _$PermissionOptionIdCopyWith<$Res> implements $PermissionOptionIdCopyWith<$Res> {
  factory _$PermissionOptionIdCopyWith(_PermissionOptionId value, $Res Function(_PermissionOptionId) _then) = __$PermissionOptionIdCopyWithImpl;
@override @useResult
$Res call({
 String value
});




}
/// @nodoc
class __$PermissionOptionIdCopyWithImpl<$Res>
    implements _$PermissionOptionIdCopyWith<$Res> {
  __$PermissionOptionIdCopyWithImpl(this._self, this._then);

  final _PermissionOptionId _self;
  final $Res Function(_PermissionOptionId) _then;

/// Create a copy of PermissionOptionId
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_PermissionOptionId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$PermissionOption {

 PermissionOptionId get optionId; String get name; PermissionOptionKind get kind;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of PermissionOption
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PermissionOptionCopyWith<PermissionOption> get copyWith => _$PermissionOptionCopyWithImpl<PermissionOption>(this as PermissionOption, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PermissionOption&&(identical(other.optionId, optionId) || other.optionId == optionId)&&(identical(other.name, name) || other.name == name)&&(identical(other.kind, kind) || other.kind == kind)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,optionId,name,kind,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'PermissionOption(optionId: $optionId, name: $name, kind: $kind, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $PermissionOptionCopyWith<$Res>  {
  factory $PermissionOptionCopyWith(PermissionOption value, $Res Function(PermissionOption) _then) = _$PermissionOptionCopyWithImpl;
@useResult
$Res call({
 PermissionOptionId optionId, String name, PermissionOptionKind kind,@JsonKey(name: '_meta') JsonObject? meta
});


$PermissionOptionIdCopyWith<$Res> get optionId;

}
/// @nodoc
class _$PermissionOptionCopyWithImpl<$Res>
    implements $PermissionOptionCopyWith<$Res> {
  _$PermissionOptionCopyWithImpl(this._self, this._then);

  final PermissionOption _self;
  final $Res Function(PermissionOption) _then;

/// Create a copy of PermissionOption
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? optionId = null,Object? name = null,Object? kind = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
optionId: null == optionId ? _self.optionId : optionId // ignore: cast_nullable_to_non_nullable
as PermissionOptionId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as PermissionOptionKind,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of PermissionOption
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PermissionOptionIdCopyWith<$Res> get optionId {
  
  return $PermissionOptionIdCopyWith<$Res>(_self.optionId, (value) {
    return _then(_self.copyWith(optionId: value));
  });
}
}


/// Adds pattern-matching-related methods to [PermissionOption].
extension PermissionOptionPatterns on PermissionOption {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PermissionOption value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PermissionOption() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PermissionOption value)  $default,){
final _that = this;
switch (_that) {
case _PermissionOption():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PermissionOption value)?  $default,){
final _that = this;
switch (_that) {
case _PermissionOption() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PermissionOptionId optionId,  String name,  PermissionOptionKind kind, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PermissionOption() when $default != null:
return $default(_that.optionId,_that.name,_that.kind,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PermissionOptionId optionId,  String name,  PermissionOptionKind kind, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _PermissionOption():
return $default(_that.optionId,_that.name,_that.kind,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PermissionOptionId optionId,  String name,  PermissionOptionKind kind, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _PermissionOption() when $default != null:
return $default(_that.optionId,_that.name,_that.kind,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _PermissionOption extends PermissionOption {
  const _PermissionOption({required this.optionId, required this.name, required this.kind, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  PermissionOptionId optionId;
@override final  String name;
@override final  PermissionOptionKind kind;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of PermissionOption
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PermissionOptionCopyWith<_PermissionOption> get copyWith => __$PermissionOptionCopyWithImpl<_PermissionOption>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PermissionOption&&(identical(other.optionId, optionId) || other.optionId == optionId)&&(identical(other.name, name) || other.name == name)&&(identical(other.kind, kind) || other.kind == kind)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,optionId,name,kind,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'PermissionOption(optionId: $optionId, name: $name, kind: $kind, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$PermissionOptionCopyWith<$Res> implements $PermissionOptionCopyWith<$Res> {
  factory _$PermissionOptionCopyWith(_PermissionOption value, $Res Function(_PermissionOption) _then) = __$PermissionOptionCopyWithImpl;
@override @useResult
$Res call({
 PermissionOptionId optionId, String name, PermissionOptionKind kind,@JsonKey(name: '_meta') JsonObject? meta
});


@override $PermissionOptionIdCopyWith<$Res> get optionId;

}
/// @nodoc
class __$PermissionOptionCopyWithImpl<$Res>
    implements _$PermissionOptionCopyWith<$Res> {
  __$PermissionOptionCopyWithImpl(this._self, this._then);

  final _PermissionOption _self;
  final $Res Function(_PermissionOption) _then;

/// Create a copy of PermissionOption
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? optionId = null,Object? name = null,Object? kind = null,Object? meta = freezed,}) {
  return _then(_PermissionOption(
optionId: null == optionId ? _self.optionId : optionId // ignore: cast_nullable_to_non_nullable
as PermissionOptionId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as PermissionOptionKind,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of PermissionOption
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
mixin _$ToolCallId {

 String get value;
/// Create a copy of ToolCallId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ToolCallIdCopyWith<ToolCallId> get copyWith => _$ToolCallIdCopyWithImpl<ToolCallId>(this as ToolCallId, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ToolCallId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'ToolCallId(value: $value)';
}


}

/// @nodoc
abstract mixin class $ToolCallIdCopyWith<$Res>  {
  factory $ToolCallIdCopyWith(ToolCallId value, $Res Function(ToolCallId) _then) = _$ToolCallIdCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$ToolCallIdCopyWithImpl<$Res>
    implements $ToolCallIdCopyWith<$Res> {
  _$ToolCallIdCopyWithImpl(this._self, this._then);

  final ToolCallId _self;
  final $Res Function(ToolCallId) _then;

/// Create a copy of ToolCallId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(_self.copyWith(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ToolCallId].
extension ToolCallIdPatterns on ToolCallId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ToolCallId value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ToolCallId() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ToolCallId value)  $default,){
final _that = this;
switch (_that) {
case _ToolCallId():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ToolCallId value)?  $default,){
final _that = this;
switch (_that) {
case _ToolCallId() when $default != null:
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
case _ToolCallId() when $default != null:
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
case _ToolCallId():
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
case _ToolCallId() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ToolCallId extends ToolCallId {
  const _ToolCallId(this.value): super._();
  

@override final  String value;

/// Create a copy of ToolCallId
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ToolCallIdCopyWith<_ToolCallId> get copyWith => __$ToolCallIdCopyWithImpl<_ToolCallId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ToolCallId&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'ToolCallId(value: $value)';
}


}

/// @nodoc
abstract mixin class _$ToolCallIdCopyWith<$Res> implements $ToolCallIdCopyWith<$Res> {
  factory _$ToolCallIdCopyWith(_ToolCallId value, $Res Function(_ToolCallId) _then) = __$ToolCallIdCopyWithImpl;
@override @useResult
$Res call({
 String value
});




}
/// @nodoc
class __$ToolCallIdCopyWithImpl<$Res>
    implements _$ToolCallIdCopyWith<$Res> {
  __$ToolCallIdCopyWithImpl(this._self, this._then);

  final _ToolCallId _self;
  final $Res Function(_ToolCallId) _then;

/// Create a copy of ToolCallId
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_ToolCallId(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ToolCallUpdate {

 ToolCallId get toolCallId; String? get title; String? get kind; ToolCallStatus? get status; JsonArray? get content; JsonArray? get locations; JsonObject? get rawInput; JsonObject? get rawOutput;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of ToolCallUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ToolCallUpdateCopyWith<ToolCallUpdate> get copyWith => _$ToolCallUpdateCopyWithImpl<ToolCallUpdate>(this as ToolCallUpdate, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ToolCallUpdate&&(identical(other.toolCallId, toolCallId) || other.toolCallId == toolCallId)&&(identical(other.title, title) || other.title == title)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.content, content)&&const DeepCollectionEquality().equals(other.locations, locations)&&const DeepCollectionEquality().equals(other.rawInput, rawInput)&&const DeepCollectionEquality().equals(other.rawOutput, rawOutput)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,toolCallId,title,kind,status,const DeepCollectionEquality().hash(content),const DeepCollectionEquality().hash(locations),const DeepCollectionEquality().hash(rawInput),const DeepCollectionEquality().hash(rawOutput),const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'ToolCallUpdate(toolCallId: $toolCallId, title: $title, kind: $kind, status: $status, content: $content, locations: $locations, rawInput: $rawInput, rawOutput: $rawOutput, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $ToolCallUpdateCopyWith<$Res>  {
  factory $ToolCallUpdateCopyWith(ToolCallUpdate value, $Res Function(ToolCallUpdate) _then) = _$ToolCallUpdateCopyWithImpl;
@useResult
$Res call({
 ToolCallId toolCallId, String? title, String? kind, ToolCallStatus? status, JsonArray? content, JsonArray? locations, JsonObject? rawInput, JsonObject? rawOutput,@JsonKey(name: '_meta') JsonObject? meta
});


$ToolCallIdCopyWith<$Res> get toolCallId;

}
/// @nodoc
class _$ToolCallUpdateCopyWithImpl<$Res>
    implements $ToolCallUpdateCopyWith<$Res> {
  _$ToolCallUpdateCopyWithImpl(this._self, this._then);

  final ToolCallUpdate _self;
  final $Res Function(ToolCallUpdate) _then;

/// Create a copy of ToolCallUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? toolCallId = null,Object? title = freezed,Object? kind = freezed,Object? status = freezed,Object? content = freezed,Object? locations = freezed,Object? rawInput = freezed,Object? rawOutput = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
toolCallId: null == toolCallId ? _self.toolCallId : toolCallId // ignore: cast_nullable_to_non_nullable
as ToolCallId,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,kind: freezed == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ToolCallStatus?,content: freezed == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as JsonArray?,locations: freezed == locations ? _self.locations : locations // ignore: cast_nullable_to_non_nullable
as JsonArray?,rawInput: freezed == rawInput ? _self.rawInput : rawInput // ignore: cast_nullable_to_non_nullable
as JsonObject?,rawOutput: freezed == rawOutput ? _self.rawOutput : rawOutput // ignore: cast_nullable_to_non_nullable
as JsonObject?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of ToolCallUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ToolCallIdCopyWith<$Res> get toolCallId {
  
  return $ToolCallIdCopyWith<$Res>(_self.toolCallId, (value) {
    return _then(_self.copyWith(toolCallId: value));
  });
}
}


/// Adds pattern-matching-related methods to [ToolCallUpdate].
extension ToolCallUpdatePatterns on ToolCallUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ToolCallUpdate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ToolCallUpdate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ToolCallUpdate value)  $default,){
final _that = this;
switch (_that) {
case _ToolCallUpdate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ToolCallUpdate value)?  $default,){
final _that = this;
switch (_that) {
case _ToolCallUpdate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ToolCallId toolCallId,  String? title,  String? kind,  ToolCallStatus? status,  JsonArray? content,  JsonArray? locations,  JsonObject? rawInput,  JsonObject? rawOutput, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ToolCallUpdate() when $default != null:
return $default(_that.toolCallId,_that.title,_that.kind,_that.status,_that.content,_that.locations,_that.rawInput,_that.rawOutput,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ToolCallId toolCallId,  String? title,  String? kind,  ToolCallStatus? status,  JsonArray? content,  JsonArray? locations,  JsonObject? rawInput,  JsonObject? rawOutput, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _ToolCallUpdate():
return $default(_that.toolCallId,_that.title,_that.kind,_that.status,_that.content,_that.locations,_that.rawInput,_that.rawOutput,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ToolCallId toolCallId,  String? title,  String? kind,  ToolCallStatus? status,  JsonArray? content,  JsonArray? locations,  JsonObject? rawInput,  JsonObject? rawOutput, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _ToolCallUpdate() when $default != null:
return $default(_that.toolCallId,_that.title,_that.kind,_that.status,_that.content,_that.locations,_that.rawInput,_that.rawOutput,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _ToolCallUpdate extends ToolCallUpdate {
  const _ToolCallUpdate({required this.toolCallId, this.title, this.kind, this.status, final  JsonArray? content, final  JsonArray? locations, final  JsonObject? rawInput, final  JsonObject? rawOutput, @JsonKey(name: '_meta') final  JsonObject? meta}): _content = content,_locations = locations,_rawInput = rawInput,_rawOutput = rawOutput,_meta = meta,super._();
  

@override final  ToolCallId toolCallId;
@override final  String? title;
@override final  String? kind;
@override final  ToolCallStatus? status;
 final  JsonArray? _content;
@override JsonArray? get content {
  final value = _content;
  if (value == null) return null;
  if (_content is EqualUnmodifiableListView) return _content;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  JsonArray? _locations;
@override JsonArray? get locations {
  final value = _locations;
  if (value == null) return null;
  if (_locations is EqualUnmodifiableListView) return _locations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  JsonObject? _rawInput;
@override JsonObject? get rawInput {
  final value = _rawInput;
  if (value == null) return null;
  if (_rawInput is EqualUnmodifiableMapView) return _rawInput;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

 final  JsonObject? _rawOutput;
@override JsonObject? get rawOutput {
  final value = _rawOutput;
  if (value == null) return null;
  if (_rawOutput is EqualUnmodifiableMapView) return _rawOutput;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ToolCallUpdate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ToolCallUpdateCopyWith<_ToolCallUpdate> get copyWith => __$ToolCallUpdateCopyWithImpl<_ToolCallUpdate>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ToolCallUpdate&&(identical(other.toolCallId, toolCallId) || other.toolCallId == toolCallId)&&(identical(other.title, title) || other.title == title)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other._content, _content)&&const DeepCollectionEquality().equals(other._locations, _locations)&&const DeepCollectionEquality().equals(other._rawInput, _rawInput)&&const DeepCollectionEquality().equals(other._rawOutput, _rawOutput)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,toolCallId,title,kind,status,const DeepCollectionEquality().hash(_content),const DeepCollectionEquality().hash(_locations),const DeepCollectionEquality().hash(_rawInput),const DeepCollectionEquality().hash(_rawOutput),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'ToolCallUpdate(toolCallId: $toolCallId, title: $title, kind: $kind, status: $status, content: $content, locations: $locations, rawInput: $rawInput, rawOutput: $rawOutput, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$ToolCallUpdateCopyWith<$Res> implements $ToolCallUpdateCopyWith<$Res> {
  factory _$ToolCallUpdateCopyWith(_ToolCallUpdate value, $Res Function(_ToolCallUpdate) _then) = __$ToolCallUpdateCopyWithImpl;
@override @useResult
$Res call({
 ToolCallId toolCallId, String? title, String? kind, ToolCallStatus? status, JsonArray? content, JsonArray? locations, JsonObject? rawInput, JsonObject? rawOutput,@JsonKey(name: '_meta') JsonObject? meta
});


@override $ToolCallIdCopyWith<$Res> get toolCallId;

}
/// @nodoc
class __$ToolCallUpdateCopyWithImpl<$Res>
    implements _$ToolCallUpdateCopyWith<$Res> {
  __$ToolCallUpdateCopyWithImpl(this._self, this._then);

  final _ToolCallUpdate _self;
  final $Res Function(_ToolCallUpdate) _then;

/// Create a copy of ToolCallUpdate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? toolCallId = null,Object? title = freezed,Object? kind = freezed,Object? status = freezed,Object? content = freezed,Object? locations = freezed,Object? rawInput = freezed,Object? rawOutput = freezed,Object? meta = freezed,}) {
  return _then(_ToolCallUpdate(
toolCallId: null == toolCallId ? _self.toolCallId : toolCallId // ignore: cast_nullable_to_non_nullable
as ToolCallId,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,kind: freezed == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as String?,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ToolCallStatus?,content: freezed == content ? _self._content : content // ignore: cast_nullable_to_non_nullable
as JsonArray?,locations: freezed == locations ? _self._locations : locations // ignore: cast_nullable_to_non_nullable
as JsonArray?,rawInput: freezed == rawInput ? _self._rawInput : rawInput // ignore: cast_nullable_to_non_nullable
as JsonObject?,rawOutput: freezed == rawOutput ? _self._rawOutput : rawOutput // ignore: cast_nullable_to_non_nullable
as JsonObject?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of ToolCallUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ToolCallIdCopyWith<$Res> get toolCallId {
  
  return $ToolCallIdCopyWith<$Res>(_self.toolCallId, (value) {
    return _then(_self.copyWith(toolCallId: value));
  });
}
}

/// @nodoc
mixin _$RequestPermissionRequest {

 SessionId get sessionId; ToolCallUpdate get toolCall; List<PermissionOption> get options;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of RequestPermissionRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RequestPermissionRequestCopyWith<RequestPermissionRequest> get copyWith => _$RequestPermissionRequestCopyWithImpl<RequestPermissionRequest>(this as RequestPermissionRequest, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RequestPermissionRequest&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.toolCall, toolCall) || other.toolCall == toolCall)&&const DeepCollectionEquality().equals(other.options, options)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,toolCall,const DeepCollectionEquality().hash(options),const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'RequestPermissionRequest(sessionId: $sessionId, toolCall: $toolCall, options: $options, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $RequestPermissionRequestCopyWith<$Res>  {
  factory $RequestPermissionRequestCopyWith(RequestPermissionRequest value, $Res Function(RequestPermissionRequest) _then) = _$RequestPermissionRequestCopyWithImpl;
@useResult
$Res call({
 SessionId sessionId, ToolCallUpdate toolCall, List<PermissionOption> options,@JsonKey(name: '_meta') JsonObject? meta
});


$SessionIdCopyWith<$Res> get sessionId;$ToolCallUpdateCopyWith<$Res> get toolCall;

}
/// @nodoc
class _$RequestPermissionRequestCopyWithImpl<$Res>
    implements $RequestPermissionRequestCopyWith<$Res> {
  _$RequestPermissionRequestCopyWithImpl(this._self, this._then);

  final RequestPermissionRequest _self;
  final $Res Function(RequestPermissionRequest) _then;

/// Create a copy of RequestPermissionRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? toolCall = null,Object? options = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,toolCall: null == toolCall ? _self.toolCall : toolCall // ignore: cast_nullable_to_non_nullable
as ToolCallUpdate,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<PermissionOption>,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of RequestPermissionRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}/// Create a copy of RequestPermissionRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ToolCallUpdateCopyWith<$Res> get toolCall {
  
  return $ToolCallUpdateCopyWith<$Res>(_self.toolCall, (value) {
    return _then(_self.copyWith(toolCall: value));
  });
}
}


/// Adds pattern-matching-related methods to [RequestPermissionRequest].
extension RequestPermissionRequestPatterns on RequestPermissionRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RequestPermissionRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RequestPermissionRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RequestPermissionRequest value)  $default,){
final _that = this;
switch (_that) {
case _RequestPermissionRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RequestPermissionRequest value)?  $default,){
final _that = this;
switch (_that) {
case _RequestPermissionRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionId sessionId,  ToolCallUpdate toolCall,  List<PermissionOption> options, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RequestPermissionRequest() when $default != null:
return $default(_that.sessionId,_that.toolCall,_that.options,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionId sessionId,  ToolCallUpdate toolCall,  List<PermissionOption> options, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _RequestPermissionRequest():
return $default(_that.sessionId,_that.toolCall,_that.options,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionId sessionId,  ToolCallUpdate toolCall,  List<PermissionOption> options, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _RequestPermissionRequest() when $default != null:
return $default(_that.sessionId,_that.toolCall,_that.options,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _RequestPermissionRequest extends RequestPermissionRequest {
  const _RequestPermissionRequest({required this.sessionId, required this.toolCall, required final  List<PermissionOption> options, @JsonKey(name: '_meta') final  JsonObject? meta}): _options = options,_meta = meta,super._();
  

@override final  SessionId sessionId;
@override final  ToolCallUpdate toolCall;
 final  List<PermissionOption> _options;
@override List<PermissionOption> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}

 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of RequestPermissionRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RequestPermissionRequestCopyWith<_RequestPermissionRequest> get copyWith => __$RequestPermissionRequestCopyWithImpl<_RequestPermissionRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RequestPermissionRequest&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.toolCall, toolCall) || other.toolCall == toolCall)&&const DeepCollectionEquality().equals(other._options, _options)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,toolCall,const DeepCollectionEquality().hash(_options),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'RequestPermissionRequest(sessionId: $sessionId, toolCall: $toolCall, options: $options, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$RequestPermissionRequestCopyWith<$Res> implements $RequestPermissionRequestCopyWith<$Res> {
  factory _$RequestPermissionRequestCopyWith(_RequestPermissionRequest value, $Res Function(_RequestPermissionRequest) _then) = __$RequestPermissionRequestCopyWithImpl;
@override @useResult
$Res call({
 SessionId sessionId, ToolCallUpdate toolCall, List<PermissionOption> options,@JsonKey(name: '_meta') JsonObject? meta
});


@override $SessionIdCopyWith<$Res> get sessionId;@override $ToolCallUpdateCopyWith<$Res> get toolCall;

}
/// @nodoc
class __$RequestPermissionRequestCopyWithImpl<$Res>
    implements _$RequestPermissionRequestCopyWith<$Res> {
  __$RequestPermissionRequestCopyWithImpl(this._self, this._then);

  final _RequestPermissionRequest _self;
  final $Res Function(_RequestPermissionRequest) _then;

/// Create a copy of RequestPermissionRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? toolCall = null,Object? options = null,Object? meta = freezed,}) {
  return _then(_RequestPermissionRequest(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,toolCall: null == toolCall ? _self.toolCall : toolCall // ignore: cast_nullable_to_non_nullable
as ToolCallUpdate,options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<PermissionOption>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of RequestPermissionRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}/// Create a copy of RequestPermissionRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ToolCallUpdateCopyWith<$Res> get toolCall {
  
  return $ToolCallUpdateCopyWith<$Res>(_self.toolCall, (value) {
    return _then(_self.copyWith(toolCall: value));
  });
}
}

/// @nodoc
mixin _$RequestPermissionOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RequestPermissionOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RequestPermissionOutcome()';
}


}

/// @nodoc
class $RequestPermissionOutcomeCopyWith<$Res>  {
$RequestPermissionOutcomeCopyWith(RequestPermissionOutcome _, $Res Function(RequestPermissionOutcome) __);
}


/// Adds pattern-matching-related methods to [RequestPermissionOutcome].
extension RequestPermissionOutcomePatterns on RequestPermissionOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RequestPermissionCancelledOutcome value)?  cancelled,TResult Function( SelectedPermissionOutcome value)?  selected,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RequestPermissionCancelledOutcome() when cancelled != null:
return cancelled(_that);case SelectedPermissionOutcome() when selected != null:
return selected(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RequestPermissionCancelledOutcome value)  cancelled,required TResult Function( SelectedPermissionOutcome value)  selected,}){
final _that = this;
switch (_that) {
case RequestPermissionCancelledOutcome():
return cancelled(_that);case SelectedPermissionOutcome():
return selected(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RequestPermissionCancelledOutcome value)?  cancelled,TResult? Function( SelectedPermissionOutcome value)?  selected,}){
final _that = this;
switch (_that) {
case RequestPermissionCancelledOutcome() when cancelled != null:
return cancelled(_that);case SelectedPermissionOutcome() when selected != null:
return selected(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  cancelled,TResult Function( PermissionOptionId optionId, @JsonKey(name: '_meta')  JsonObject? meta)?  selected,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RequestPermissionCancelledOutcome() when cancelled != null:
return cancelled();case SelectedPermissionOutcome() when selected != null:
return selected(_that.optionId,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  cancelled,required TResult Function( PermissionOptionId optionId, @JsonKey(name: '_meta')  JsonObject? meta)  selected,}) {final _that = this;
switch (_that) {
case RequestPermissionCancelledOutcome():
return cancelled();case SelectedPermissionOutcome():
return selected(_that.optionId,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  cancelled,TResult? Function( PermissionOptionId optionId, @JsonKey(name: '_meta')  JsonObject? meta)?  selected,}) {final _that = this;
switch (_that) {
case RequestPermissionCancelledOutcome() when cancelled != null:
return cancelled();case SelectedPermissionOutcome() when selected != null:
return selected(_that.optionId,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class RequestPermissionCancelledOutcome extends RequestPermissionOutcome {
  const RequestPermissionCancelledOutcome(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RequestPermissionCancelledOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RequestPermissionOutcome.cancelled()';
}


}




/// @nodoc


class SelectedPermissionOutcome extends RequestPermissionOutcome {
  const SelectedPermissionOutcome({required this.optionId, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

 final  PermissionOptionId optionId;
 final  JsonObject? _meta;
@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of RequestPermissionOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SelectedPermissionOutcomeCopyWith<SelectedPermissionOutcome> get copyWith => _$SelectedPermissionOutcomeCopyWithImpl<SelectedPermissionOutcome>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SelectedPermissionOutcome&&(identical(other.optionId, optionId) || other.optionId == optionId)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,optionId,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'RequestPermissionOutcome.selected(optionId: $optionId, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $SelectedPermissionOutcomeCopyWith<$Res> implements $RequestPermissionOutcomeCopyWith<$Res> {
  factory $SelectedPermissionOutcomeCopyWith(SelectedPermissionOutcome value, $Res Function(SelectedPermissionOutcome) _then) = _$SelectedPermissionOutcomeCopyWithImpl;
@useResult
$Res call({
 PermissionOptionId optionId,@JsonKey(name: '_meta') JsonObject? meta
});


$PermissionOptionIdCopyWith<$Res> get optionId;

}
/// @nodoc
class _$SelectedPermissionOutcomeCopyWithImpl<$Res>
    implements $SelectedPermissionOutcomeCopyWith<$Res> {
  _$SelectedPermissionOutcomeCopyWithImpl(this._self, this._then);

  final SelectedPermissionOutcome _self;
  final $Res Function(SelectedPermissionOutcome) _then;

/// Create a copy of RequestPermissionOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? optionId = null,Object? meta = freezed,}) {
  return _then(SelectedPermissionOutcome(
optionId: null == optionId ? _self.optionId : optionId // ignore: cast_nullable_to_non_nullable
as PermissionOptionId,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of RequestPermissionOutcome
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
mixin _$RequestPermissionResponse {

 RequestPermissionOutcome get outcome;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of RequestPermissionResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RequestPermissionResponseCopyWith<RequestPermissionResponse> get copyWith => _$RequestPermissionResponseCopyWithImpl<RequestPermissionResponse>(this as RequestPermissionResponse, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RequestPermissionResponse&&(identical(other.outcome, outcome) || other.outcome == outcome)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,outcome,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'RequestPermissionResponse(outcome: $outcome, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $RequestPermissionResponseCopyWith<$Res>  {
  factory $RequestPermissionResponseCopyWith(RequestPermissionResponse value, $Res Function(RequestPermissionResponse) _then) = _$RequestPermissionResponseCopyWithImpl;
@useResult
$Res call({
 RequestPermissionOutcome outcome,@JsonKey(name: '_meta') JsonObject? meta
});


$RequestPermissionOutcomeCopyWith<$Res> get outcome;

}
/// @nodoc
class _$RequestPermissionResponseCopyWithImpl<$Res>
    implements $RequestPermissionResponseCopyWith<$Res> {
  _$RequestPermissionResponseCopyWithImpl(this._self, this._then);

  final RequestPermissionResponse _self;
  final $Res Function(RequestPermissionResponse) _then;

/// Create a copy of RequestPermissionResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? outcome = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as RequestPermissionOutcome,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of RequestPermissionResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RequestPermissionOutcomeCopyWith<$Res> get outcome {
  
  return $RequestPermissionOutcomeCopyWith<$Res>(_self.outcome, (value) {
    return _then(_self.copyWith(outcome: value));
  });
}
}


/// Adds pattern-matching-related methods to [RequestPermissionResponse].
extension RequestPermissionResponsePatterns on RequestPermissionResponse {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RequestPermissionResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RequestPermissionResponse() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RequestPermissionResponse value)  $default,){
final _that = this;
switch (_that) {
case _RequestPermissionResponse():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RequestPermissionResponse value)?  $default,){
final _that = this;
switch (_that) {
case _RequestPermissionResponse() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RequestPermissionOutcome outcome, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RequestPermissionResponse() when $default != null:
return $default(_that.outcome,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RequestPermissionOutcome outcome, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _RequestPermissionResponse():
return $default(_that.outcome,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RequestPermissionOutcome outcome, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _RequestPermissionResponse() when $default != null:
return $default(_that.outcome,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _RequestPermissionResponse extends RequestPermissionResponse {
  const _RequestPermissionResponse({required this.outcome, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  RequestPermissionOutcome outcome;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of RequestPermissionResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RequestPermissionResponseCopyWith<_RequestPermissionResponse> get copyWith => __$RequestPermissionResponseCopyWithImpl<_RequestPermissionResponse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RequestPermissionResponse&&(identical(other.outcome, outcome) || other.outcome == outcome)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,outcome,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'RequestPermissionResponse(outcome: $outcome, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$RequestPermissionResponseCopyWith<$Res> implements $RequestPermissionResponseCopyWith<$Res> {
  factory _$RequestPermissionResponseCopyWith(_RequestPermissionResponse value, $Res Function(_RequestPermissionResponse) _then) = __$RequestPermissionResponseCopyWithImpl;
@override @useResult
$Res call({
 RequestPermissionOutcome outcome,@JsonKey(name: '_meta') JsonObject? meta
});


@override $RequestPermissionOutcomeCopyWith<$Res> get outcome;

}
/// @nodoc
class __$RequestPermissionResponseCopyWithImpl<$Res>
    implements _$RequestPermissionResponseCopyWith<$Res> {
  __$RequestPermissionResponseCopyWithImpl(this._self, this._then);

  final _RequestPermissionResponse _self;
  final $Res Function(_RequestPermissionResponse) _then;

/// Create a copy of RequestPermissionResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? outcome = null,Object? meta = freezed,}) {
  return _then(_RequestPermissionResponse(
outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as RequestPermissionOutcome,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of RequestPermissionResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RequestPermissionOutcomeCopyWith<$Res> get outcome {
  
  return $RequestPermissionOutcomeCopyWith<$Res>(_self.outcome, (value) {
    return _then(_self.copyWith(outcome: value));
  });
}
}

// dart format on
