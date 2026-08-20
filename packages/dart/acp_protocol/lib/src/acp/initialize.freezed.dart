// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'initialize.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ProtocolVersion {

 int get value;
/// Create a copy of ProtocolVersion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProtocolVersionCopyWith<ProtocolVersion> get copyWith => _$ProtocolVersionCopyWithImpl<ProtocolVersion>(this as ProtocolVersion, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProtocolVersion&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'ProtocolVersion(value: $value)';
}


}

/// @nodoc
abstract mixin class $ProtocolVersionCopyWith<$Res>  {
  factory $ProtocolVersionCopyWith(ProtocolVersion value, $Res Function(ProtocolVersion) _then) = _$ProtocolVersionCopyWithImpl;
@useResult
$Res call({
 int value
});




}
/// @nodoc
class _$ProtocolVersionCopyWithImpl<$Res>
    implements $ProtocolVersionCopyWith<$Res> {
  _$ProtocolVersionCopyWithImpl(this._self, this._then);

  final ProtocolVersion _self;
  final $Res Function(ProtocolVersion) _then;

/// Create a copy of ProtocolVersion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(_self.copyWith(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProtocolVersion].
extension ProtocolVersionPatterns on ProtocolVersion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProtocolVersion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProtocolVersion() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProtocolVersion value)  $default,){
final _that = this;
switch (_that) {
case _ProtocolVersion():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProtocolVersion value)?  $default,){
final _that = this;
switch (_that) {
case _ProtocolVersion() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProtocolVersion() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int value)  $default,) {final _that = this;
switch (_that) {
case _ProtocolVersion():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int value)?  $default,) {final _that = this;
switch (_that) {
case _ProtocolVersion() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ProtocolVersion extends ProtocolVersion {
  const _ProtocolVersion(this.value): super._();
  

@override final  int value;

/// Create a copy of ProtocolVersion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProtocolVersionCopyWith<_ProtocolVersion> get copyWith => __$ProtocolVersionCopyWithImpl<_ProtocolVersion>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProtocolVersion&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'ProtocolVersion(value: $value)';
}


}

/// @nodoc
abstract mixin class _$ProtocolVersionCopyWith<$Res> implements $ProtocolVersionCopyWith<$Res> {
  factory _$ProtocolVersionCopyWith(_ProtocolVersion value, $Res Function(_ProtocolVersion) _then) = __$ProtocolVersionCopyWithImpl;
@override @useResult
$Res call({
 int value
});




}
/// @nodoc
class __$ProtocolVersionCopyWithImpl<$Res>
    implements _$ProtocolVersionCopyWith<$Res> {
  __$ProtocolVersionCopyWithImpl(this._self, this._then);

  final _ProtocolVersion _self;
  final $Res Function(_ProtocolVersion) _then;

/// Create a copy of ProtocolVersion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_ProtocolVersion(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$Implementation {

 String get name; String get version; String? get title;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of Implementation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImplementationCopyWith<Implementation> get copyWith => _$ImplementationCopyWithImpl<Implementation>(this as Implementation, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Implementation&&(identical(other.name, name) || other.name == name)&&(identical(other.version, version) || other.version == version)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,name,version,title,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'Implementation(name: $name, version: $version, title: $title, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $ImplementationCopyWith<$Res>  {
  factory $ImplementationCopyWith(Implementation value, $Res Function(Implementation) _then) = _$ImplementationCopyWithImpl;
@useResult
$Res call({
 String name, String version, String? title,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$ImplementationCopyWithImpl<$Res>
    implements $ImplementationCopyWith<$Res> {
  _$ImplementationCopyWithImpl(this._self, this._then);

  final Implementation _self;
  final $Res Function(Implementation) _then;

/// Create a copy of Implementation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? version = null,Object? title = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

}


/// Adds pattern-matching-related methods to [Implementation].
extension ImplementationPatterns on Implementation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Implementation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Implementation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Implementation value)  $default,){
final _that = this;
switch (_that) {
case _Implementation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Implementation value)?  $default,){
final _that = this;
switch (_that) {
case _Implementation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String version,  String? title, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Implementation() when $default != null:
return $default(_that.name,_that.version,_that.title,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String version,  String? title, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _Implementation():
return $default(_that.name,_that.version,_that.title,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String version,  String? title, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _Implementation() when $default != null:
return $default(_that.name,_that.version,_that.title,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _Implementation extends Implementation {
  const _Implementation({required this.name, required this.version, this.title, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  String name;
@override final  String version;
@override final  String? title;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of Implementation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ImplementationCopyWith<_Implementation> get copyWith => __$ImplementationCopyWithImpl<_Implementation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Implementation&&(identical(other.name, name) || other.name == name)&&(identical(other.version, version) || other.version == version)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,name,version,title,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'Implementation(name: $name, version: $version, title: $title, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$ImplementationCopyWith<$Res> implements $ImplementationCopyWith<$Res> {
  factory _$ImplementationCopyWith(_Implementation value, $Res Function(_Implementation) _then) = __$ImplementationCopyWithImpl;
@override @useResult
$Res call({
 String name, String version, String? title,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class __$ImplementationCopyWithImpl<$Res>
    implements _$ImplementationCopyWith<$Res> {
  __$ImplementationCopyWithImpl(this._self, this._then);

  final _Implementation _self;
  final $Res Function(_Implementation) _then;

/// Create a copy of Implementation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? version = null,Object? title = freezed,Object? meta = freezed,}) {
  return _then(_Implementation(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$FileSystemCapabilities {

 bool get readTextFile; bool get writeTextFile;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of FileSystemCapabilities
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileSystemCapabilitiesCopyWith<FileSystemCapabilities> get copyWith => _$FileSystemCapabilitiesCopyWithImpl<FileSystemCapabilities>(this as FileSystemCapabilities, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileSystemCapabilities&&(identical(other.readTextFile, readTextFile) || other.readTextFile == readTextFile)&&(identical(other.writeTextFile, writeTextFile) || other.writeTextFile == writeTextFile)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,readTextFile,writeTextFile,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'FileSystemCapabilities(readTextFile: $readTextFile, writeTextFile: $writeTextFile, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $FileSystemCapabilitiesCopyWith<$Res>  {
  factory $FileSystemCapabilitiesCopyWith(FileSystemCapabilities value, $Res Function(FileSystemCapabilities) _then) = _$FileSystemCapabilitiesCopyWithImpl;
@useResult
$Res call({
 bool readTextFile, bool writeTextFile,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$FileSystemCapabilitiesCopyWithImpl<$Res>
    implements $FileSystemCapabilitiesCopyWith<$Res> {
  _$FileSystemCapabilitiesCopyWithImpl(this._self, this._then);

  final FileSystemCapabilities _self;
  final $Res Function(FileSystemCapabilities) _then;

/// Create a copy of FileSystemCapabilities
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? readTextFile = null,Object? writeTextFile = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
readTextFile: null == readTextFile ? _self.readTextFile : readTextFile // ignore: cast_nullable_to_non_nullable
as bool,writeTextFile: null == writeTextFile ? _self.writeTextFile : writeTextFile // ignore: cast_nullable_to_non_nullable
as bool,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

}


/// Adds pattern-matching-related methods to [FileSystemCapabilities].
extension FileSystemCapabilitiesPatterns on FileSystemCapabilities {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FileSystemCapabilities value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FileSystemCapabilities() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FileSystemCapabilities value)  $default,){
final _that = this;
switch (_that) {
case _FileSystemCapabilities():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FileSystemCapabilities value)?  $default,){
final _that = this;
switch (_that) {
case _FileSystemCapabilities() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool readTextFile,  bool writeTextFile, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FileSystemCapabilities() when $default != null:
return $default(_that.readTextFile,_that.writeTextFile,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool readTextFile,  bool writeTextFile, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _FileSystemCapabilities():
return $default(_that.readTextFile,_that.writeTextFile,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool readTextFile,  bool writeTextFile, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _FileSystemCapabilities() when $default != null:
return $default(_that.readTextFile,_that.writeTextFile,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _FileSystemCapabilities extends FileSystemCapabilities {
  const _FileSystemCapabilities({this.readTextFile = false, this.writeTextFile = false, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override@JsonKey() final  bool readTextFile;
@override@JsonKey() final  bool writeTextFile;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of FileSystemCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FileSystemCapabilitiesCopyWith<_FileSystemCapabilities> get copyWith => __$FileSystemCapabilitiesCopyWithImpl<_FileSystemCapabilities>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FileSystemCapabilities&&(identical(other.readTextFile, readTextFile) || other.readTextFile == readTextFile)&&(identical(other.writeTextFile, writeTextFile) || other.writeTextFile == writeTextFile)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,readTextFile,writeTextFile,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'FileSystemCapabilities(readTextFile: $readTextFile, writeTextFile: $writeTextFile, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$FileSystemCapabilitiesCopyWith<$Res> implements $FileSystemCapabilitiesCopyWith<$Res> {
  factory _$FileSystemCapabilitiesCopyWith(_FileSystemCapabilities value, $Res Function(_FileSystemCapabilities) _then) = __$FileSystemCapabilitiesCopyWithImpl;
@override @useResult
$Res call({
 bool readTextFile, bool writeTextFile,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class __$FileSystemCapabilitiesCopyWithImpl<$Res>
    implements _$FileSystemCapabilitiesCopyWith<$Res> {
  __$FileSystemCapabilitiesCopyWithImpl(this._self, this._then);

  final _FileSystemCapabilities _self;
  final $Res Function(_FileSystemCapabilities) _then;

/// Create a copy of FileSystemCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? readTextFile = null,Object? writeTextFile = null,Object? meta = freezed,}) {
  return _then(_FileSystemCapabilities(
readTextFile: null == readTextFile ? _self.readTextFile : readTextFile // ignore: cast_nullable_to_non_nullable
as bool,writeTextFile: null == writeTextFile ? _self.writeTextFile : writeTextFile // ignore: cast_nullable_to_non_nullable
as bool,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$ClientCapabilities {

 FileSystemCapabilities get fs; bool get terminal;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of ClientCapabilities
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClientCapabilitiesCopyWith<ClientCapabilities> get copyWith => _$ClientCapabilitiesCopyWithImpl<ClientCapabilities>(this as ClientCapabilities, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientCapabilities&&(identical(other.fs, fs) || other.fs == fs)&&(identical(other.terminal, terminal) || other.terminal == terminal)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,fs,terminal,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'ClientCapabilities(fs: $fs, terminal: $terminal, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $ClientCapabilitiesCopyWith<$Res>  {
  factory $ClientCapabilitiesCopyWith(ClientCapabilities value, $Res Function(ClientCapabilities) _then) = _$ClientCapabilitiesCopyWithImpl;
@useResult
$Res call({
 FileSystemCapabilities fs, bool terminal,@JsonKey(name: '_meta') JsonObject? meta
});


$FileSystemCapabilitiesCopyWith<$Res> get fs;

}
/// @nodoc
class _$ClientCapabilitiesCopyWithImpl<$Res>
    implements $ClientCapabilitiesCopyWith<$Res> {
  _$ClientCapabilitiesCopyWithImpl(this._self, this._then);

  final ClientCapabilities _self;
  final $Res Function(ClientCapabilities) _then;

/// Create a copy of ClientCapabilities
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? fs = null,Object? terminal = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
fs: null == fs ? _self.fs : fs // ignore: cast_nullable_to_non_nullable
as FileSystemCapabilities,terminal: null == terminal ? _self.terminal : terminal // ignore: cast_nullable_to_non_nullable
as bool,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of ClientCapabilities
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FileSystemCapabilitiesCopyWith<$Res> get fs {
  
  return $FileSystemCapabilitiesCopyWith<$Res>(_self.fs, (value) {
    return _then(_self.copyWith(fs: value));
  });
}
}


/// Adds pattern-matching-related methods to [ClientCapabilities].
extension ClientCapabilitiesPatterns on ClientCapabilities {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ClientCapabilities value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ClientCapabilities() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ClientCapabilities value)  $default,){
final _that = this;
switch (_that) {
case _ClientCapabilities():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ClientCapabilities value)?  $default,){
final _that = this;
switch (_that) {
case _ClientCapabilities() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( FileSystemCapabilities fs,  bool terminal, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ClientCapabilities() when $default != null:
return $default(_that.fs,_that.terminal,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( FileSystemCapabilities fs,  bool terminal, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _ClientCapabilities():
return $default(_that.fs,_that.terminal,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( FileSystemCapabilities fs,  bool terminal, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _ClientCapabilities() when $default != null:
return $default(_that.fs,_that.terminal,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _ClientCapabilities extends ClientCapabilities {
  const _ClientCapabilities({this.fs = const FileSystemCapabilities(), this.terminal = false, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override@JsonKey() final  FileSystemCapabilities fs;
@override@JsonKey() final  bool terminal;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ClientCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ClientCapabilitiesCopyWith<_ClientCapabilities> get copyWith => __$ClientCapabilitiesCopyWithImpl<_ClientCapabilities>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ClientCapabilities&&(identical(other.fs, fs) || other.fs == fs)&&(identical(other.terminal, terminal) || other.terminal == terminal)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,fs,terminal,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'ClientCapabilities(fs: $fs, terminal: $terminal, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$ClientCapabilitiesCopyWith<$Res> implements $ClientCapabilitiesCopyWith<$Res> {
  factory _$ClientCapabilitiesCopyWith(_ClientCapabilities value, $Res Function(_ClientCapabilities) _then) = __$ClientCapabilitiesCopyWithImpl;
@override @useResult
$Res call({
 FileSystemCapabilities fs, bool terminal,@JsonKey(name: '_meta') JsonObject? meta
});


@override $FileSystemCapabilitiesCopyWith<$Res> get fs;

}
/// @nodoc
class __$ClientCapabilitiesCopyWithImpl<$Res>
    implements _$ClientCapabilitiesCopyWith<$Res> {
  __$ClientCapabilitiesCopyWithImpl(this._self, this._then);

  final _ClientCapabilities _self;
  final $Res Function(_ClientCapabilities) _then;

/// Create a copy of ClientCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fs = null,Object? terminal = null,Object? meta = freezed,}) {
  return _then(_ClientCapabilities(
fs: null == fs ? _self.fs : fs // ignore: cast_nullable_to_non_nullable
as FileSystemCapabilities,terminal: null == terminal ? _self.terminal : terminal // ignore: cast_nullable_to_non_nullable
as bool,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of ClientCapabilities
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FileSystemCapabilitiesCopyWith<$Res> get fs {
  
  return $FileSystemCapabilitiesCopyWith<$Res>(_self.fs, (value) {
    return _then(_self.copyWith(fs: value));
  });
}
}

/// @nodoc
mixin _$McpCapabilities {

 bool get http; bool get sse;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of McpCapabilities
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpCapabilitiesCopyWith<McpCapabilities> get copyWith => _$McpCapabilitiesCopyWithImpl<McpCapabilities>(this as McpCapabilities, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpCapabilities&&(identical(other.http, http) || other.http == http)&&(identical(other.sse, sse) || other.sse == sse)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,http,sse,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'McpCapabilities(http: $http, sse: $sse, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $McpCapabilitiesCopyWith<$Res>  {
  factory $McpCapabilitiesCopyWith(McpCapabilities value, $Res Function(McpCapabilities) _then) = _$McpCapabilitiesCopyWithImpl;
@useResult
$Res call({
 bool http, bool sse,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$McpCapabilitiesCopyWithImpl<$Res>
    implements $McpCapabilitiesCopyWith<$Res> {
  _$McpCapabilitiesCopyWithImpl(this._self, this._then);

  final McpCapabilities _self;
  final $Res Function(McpCapabilities) _then;

/// Create a copy of McpCapabilities
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? http = null,Object? sse = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
http: null == http ? _self.http : http // ignore: cast_nullable_to_non_nullable
as bool,sse: null == sse ? _self.sse : sse // ignore: cast_nullable_to_non_nullable
as bool,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

}


/// Adds pattern-matching-related methods to [McpCapabilities].
extension McpCapabilitiesPatterns on McpCapabilities {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpCapabilities value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpCapabilities() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpCapabilities value)  $default,){
final _that = this;
switch (_that) {
case _McpCapabilities():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpCapabilities value)?  $default,){
final _that = this;
switch (_that) {
case _McpCapabilities() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool http,  bool sse, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpCapabilities() when $default != null:
return $default(_that.http,_that.sse,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool http,  bool sse, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _McpCapabilities():
return $default(_that.http,_that.sse,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool http,  bool sse, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _McpCapabilities() when $default != null:
return $default(_that.http,_that.sse,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _McpCapabilities extends McpCapabilities {
  const _McpCapabilities({this.http = false, this.sse = false, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override@JsonKey() final  bool http;
@override@JsonKey() final  bool sse;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of McpCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpCapabilitiesCopyWith<_McpCapabilities> get copyWith => __$McpCapabilitiesCopyWithImpl<_McpCapabilities>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpCapabilities&&(identical(other.http, http) || other.http == http)&&(identical(other.sse, sse) || other.sse == sse)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,http,sse,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'McpCapabilities(http: $http, sse: $sse, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$McpCapabilitiesCopyWith<$Res> implements $McpCapabilitiesCopyWith<$Res> {
  factory _$McpCapabilitiesCopyWith(_McpCapabilities value, $Res Function(_McpCapabilities) _then) = __$McpCapabilitiesCopyWithImpl;
@override @useResult
$Res call({
 bool http, bool sse,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class __$McpCapabilitiesCopyWithImpl<$Res>
    implements _$McpCapabilitiesCopyWith<$Res> {
  __$McpCapabilitiesCopyWithImpl(this._self, this._then);

  final _McpCapabilities _self;
  final $Res Function(_McpCapabilities) _then;

/// Create a copy of McpCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? http = null,Object? sse = null,Object? meta = freezed,}) {
  return _then(_McpCapabilities(
http: null == http ? _self.http : http // ignore: cast_nullable_to_non_nullable
as bool,sse: null == sse ? _self.sse : sse // ignore: cast_nullable_to_non_nullable
as bool,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$PromptCapabilities {

 bool get audio; bool get embeddedContext; bool get image;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of PromptCapabilities
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptCapabilitiesCopyWith<PromptCapabilities> get copyWith => _$PromptCapabilitiesCopyWithImpl<PromptCapabilities>(this as PromptCapabilities, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptCapabilities&&(identical(other.audio, audio) || other.audio == audio)&&(identical(other.embeddedContext, embeddedContext) || other.embeddedContext == embeddedContext)&&(identical(other.image, image) || other.image == image)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,audio,embeddedContext,image,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'PromptCapabilities(audio: $audio, embeddedContext: $embeddedContext, image: $image, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $PromptCapabilitiesCopyWith<$Res>  {
  factory $PromptCapabilitiesCopyWith(PromptCapabilities value, $Res Function(PromptCapabilities) _then) = _$PromptCapabilitiesCopyWithImpl;
@useResult
$Res call({
 bool audio, bool embeddedContext, bool image,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$PromptCapabilitiesCopyWithImpl<$Res>
    implements $PromptCapabilitiesCopyWith<$Res> {
  _$PromptCapabilitiesCopyWithImpl(this._self, this._then);

  final PromptCapabilities _self;
  final $Res Function(PromptCapabilities) _then;

/// Create a copy of PromptCapabilities
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? audio = null,Object? embeddedContext = null,Object? image = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
audio: null == audio ? _self.audio : audio // ignore: cast_nullable_to_non_nullable
as bool,embeddedContext: null == embeddedContext ? _self.embeddedContext : embeddedContext // ignore: cast_nullable_to_non_nullable
as bool,image: null == image ? _self.image : image // ignore: cast_nullable_to_non_nullable
as bool,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

}


/// Adds pattern-matching-related methods to [PromptCapabilities].
extension PromptCapabilitiesPatterns on PromptCapabilities {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PromptCapabilities value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PromptCapabilities() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PromptCapabilities value)  $default,){
final _that = this;
switch (_that) {
case _PromptCapabilities():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PromptCapabilities value)?  $default,){
final _that = this;
switch (_that) {
case _PromptCapabilities() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool audio,  bool embeddedContext,  bool image, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PromptCapabilities() when $default != null:
return $default(_that.audio,_that.embeddedContext,_that.image,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool audio,  bool embeddedContext,  bool image, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _PromptCapabilities():
return $default(_that.audio,_that.embeddedContext,_that.image,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool audio,  bool embeddedContext,  bool image, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _PromptCapabilities() when $default != null:
return $default(_that.audio,_that.embeddedContext,_that.image,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _PromptCapabilities extends PromptCapabilities {
  const _PromptCapabilities({this.audio = false, this.embeddedContext = false, this.image = false, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override@JsonKey() final  bool audio;
@override@JsonKey() final  bool embeddedContext;
@override@JsonKey() final  bool image;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of PromptCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PromptCapabilitiesCopyWith<_PromptCapabilities> get copyWith => __$PromptCapabilitiesCopyWithImpl<_PromptCapabilities>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PromptCapabilities&&(identical(other.audio, audio) || other.audio == audio)&&(identical(other.embeddedContext, embeddedContext) || other.embeddedContext == embeddedContext)&&(identical(other.image, image) || other.image == image)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,audio,embeddedContext,image,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'PromptCapabilities(audio: $audio, embeddedContext: $embeddedContext, image: $image, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$PromptCapabilitiesCopyWith<$Res> implements $PromptCapabilitiesCopyWith<$Res> {
  factory _$PromptCapabilitiesCopyWith(_PromptCapabilities value, $Res Function(_PromptCapabilities) _then) = __$PromptCapabilitiesCopyWithImpl;
@override @useResult
$Res call({
 bool audio, bool embeddedContext, bool image,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class __$PromptCapabilitiesCopyWithImpl<$Res>
    implements _$PromptCapabilitiesCopyWith<$Res> {
  __$PromptCapabilitiesCopyWithImpl(this._self, this._then);

  final _PromptCapabilities _self;
  final $Res Function(_PromptCapabilities) _then;

/// Create a copy of PromptCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? audio = null,Object? embeddedContext = null,Object? image = null,Object? meta = freezed,}) {
  return _then(_PromptCapabilities(
audio: null == audio ? _self.audio : audio // ignore: cast_nullable_to_non_nullable
as bool,embeddedContext: null == embeddedContext ? _self.embeddedContext : embeddedContext // ignore: cast_nullable_to_non_nullable
as bool,image: null == image ? _self.image : image // ignore: cast_nullable_to_non_nullable
as bool,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$SessionListCapabilities {

@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of SessionListCapabilities
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionListCapabilitiesCopyWith<SessionListCapabilities> get copyWith => _$SessionListCapabilitiesCopyWithImpl<SessionListCapabilities>(this as SessionListCapabilities, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionListCapabilities&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'SessionListCapabilities(meta: $meta)';
}


}

/// @nodoc
abstract mixin class $SessionListCapabilitiesCopyWith<$Res>  {
  factory $SessionListCapabilitiesCopyWith(SessionListCapabilities value, $Res Function(SessionListCapabilities) _then) = _$SessionListCapabilitiesCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$SessionListCapabilitiesCopyWithImpl<$Res>
    implements $SessionListCapabilitiesCopyWith<$Res> {
  _$SessionListCapabilitiesCopyWithImpl(this._self, this._then);

  final SessionListCapabilities _self;
  final $Res Function(SessionListCapabilities) _then;

/// Create a copy of SessionListCapabilities
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? meta = freezed,}) {
  return _then(_self.copyWith(
meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionListCapabilities].
extension SessionListCapabilitiesPatterns on SessionListCapabilities {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionListCapabilities value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionListCapabilities() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionListCapabilities value)  $default,){
final _that = this;
switch (_that) {
case _SessionListCapabilities():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionListCapabilities value)?  $default,){
final _that = this;
switch (_that) {
case _SessionListCapabilities() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionListCapabilities() when $default != null:
return $default(_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _SessionListCapabilities():
return $default(_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _SessionListCapabilities() when $default != null:
return $default(_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _SessionListCapabilities extends SessionListCapabilities {
  const _SessionListCapabilities({@JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of SessionListCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionListCapabilitiesCopyWith<_SessionListCapabilities> get copyWith => __$SessionListCapabilitiesCopyWithImpl<_SessionListCapabilities>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionListCapabilities&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'SessionListCapabilities(meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$SessionListCapabilitiesCopyWith<$Res> implements $SessionListCapabilitiesCopyWith<$Res> {
  factory _$SessionListCapabilitiesCopyWith(_SessionListCapabilities value, $Res Function(_SessionListCapabilities) _then) = __$SessionListCapabilitiesCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class __$SessionListCapabilitiesCopyWithImpl<$Res>
    implements _$SessionListCapabilitiesCopyWith<$Res> {
  __$SessionListCapabilitiesCopyWithImpl(this._self, this._then);

  final _SessionListCapabilities _self;
  final $Res Function(_SessionListCapabilities) _then;

/// Create a copy of SessionListCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? meta = freezed,}) {
  return _then(_SessionListCapabilities(
meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$SessionCapabilities {

 SessionListCapabilities? get list;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of SessionCapabilities
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCapabilitiesCopyWith<SessionCapabilities> get copyWith => _$SessionCapabilitiesCopyWithImpl<SessionCapabilities>(this as SessionCapabilities, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCapabilities&&(identical(other.list, list) || other.list == list)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,list,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'SessionCapabilities(list: $list, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $SessionCapabilitiesCopyWith<$Res>  {
  factory $SessionCapabilitiesCopyWith(SessionCapabilities value, $Res Function(SessionCapabilities) _then) = _$SessionCapabilitiesCopyWithImpl;
@useResult
$Res call({
 SessionListCapabilities? list,@JsonKey(name: '_meta') JsonObject? meta
});


$SessionListCapabilitiesCopyWith<$Res>? get list;

}
/// @nodoc
class _$SessionCapabilitiesCopyWithImpl<$Res>
    implements $SessionCapabilitiesCopyWith<$Res> {
  _$SessionCapabilitiesCopyWithImpl(this._self, this._then);

  final SessionCapabilities _self;
  final $Res Function(SessionCapabilities) _then;

/// Create a copy of SessionCapabilities
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? list = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
list: freezed == list ? _self.list : list // ignore: cast_nullable_to_non_nullable
as SessionListCapabilities?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of SessionCapabilities
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionListCapabilitiesCopyWith<$Res>? get list {
    if (_self.list == null) {
    return null;
  }

  return $SessionListCapabilitiesCopyWith<$Res>(_self.list!, (value) {
    return _then(_self.copyWith(list: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionCapabilities].
extension SessionCapabilitiesPatterns on SessionCapabilities {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionCapabilities value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionCapabilities() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionCapabilities value)  $default,){
final _that = this;
switch (_that) {
case _SessionCapabilities():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionCapabilities value)?  $default,){
final _that = this;
switch (_that) {
case _SessionCapabilities() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionListCapabilities? list, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionCapabilities() when $default != null:
return $default(_that.list,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionListCapabilities? list, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _SessionCapabilities():
return $default(_that.list,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionListCapabilities? list, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _SessionCapabilities() when $default != null:
return $default(_that.list,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _SessionCapabilities extends SessionCapabilities {
  const _SessionCapabilities({this.list, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  SessionListCapabilities? list;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of SessionCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionCapabilitiesCopyWith<_SessionCapabilities> get copyWith => __$SessionCapabilitiesCopyWithImpl<_SessionCapabilities>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionCapabilities&&(identical(other.list, list) || other.list == list)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,list,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'SessionCapabilities(list: $list, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$SessionCapabilitiesCopyWith<$Res> implements $SessionCapabilitiesCopyWith<$Res> {
  factory _$SessionCapabilitiesCopyWith(_SessionCapabilities value, $Res Function(_SessionCapabilities) _then) = __$SessionCapabilitiesCopyWithImpl;
@override @useResult
$Res call({
 SessionListCapabilities? list,@JsonKey(name: '_meta') JsonObject? meta
});


@override $SessionListCapabilitiesCopyWith<$Res>? get list;

}
/// @nodoc
class __$SessionCapabilitiesCopyWithImpl<$Res>
    implements _$SessionCapabilitiesCopyWith<$Res> {
  __$SessionCapabilitiesCopyWithImpl(this._self, this._then);

  final _SessionCapabilities _self;
  final $Res Function(_SessionCapabilities) _then;

/// Create a copy of SessionCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? list = freezed,Object? meta = freezed,}) {
  return _then(_SessionCapabilities(
list: freezed == list ? _self.list : list // ignore: cast_nullable_to_non_nullable
as SessionListCapabilities?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of SessionCapabilities
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionListCapabilitiesCopyWith<$Res>? get list {
    if (_self.list == null) {
    return null;
  }

  return $SessionListCapabilitiesCopyWith<$Res>(_self.list!, (value) {
    return _then(_self.copyWith(list: value));
  });
}
}

/// @nodoc
mixin _$AgentCapabilities {

 bool get loadSession; McpCapabilities get mcpCapabilities; PromptCapabilities get promptCapabilities; SessionCapabilities get sessionCapabilities;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of AgentCapabilities
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentCapabilitiesCopyWith<AgentCapabilities> get copyWith => _$AgentCapabilitiesCopyWithImpl<AgentCapabilities>(this as AgentCapabilities, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentCapabilities&&(identical(other.loadSession, loadSession) || other.loadSession == loadSession)&&(identical(other.mcpCapabilities, mcpCapabilities) || other.mcpCapabilities == mcpCapabilities)&&(identical(other.promptCapabilities, promptCapabilities) || other.promptCapabilities == promptCapabilities)&&(identical(other.sessionCapabilities, sessionCapabilities) || other.sessionCapabilities == sessionCapabilities)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,loadSession,mcpCapabilities,promptCapabilities,sessionCapabilities,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'AgentCapabilities(loadSession: $loadSession, mcpCapabilities: $mcpCapabilities, promptCapabilities: $promptCapabilities, sessionCapabilities: $sessionCapabilities, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $AgentCapabilitiesCopyWith<$Res>  {
  factory $AgentCapabilitiesCopyWith(AgentCapabilities value, $Res Function(AgentCapabilities) _then) = _$AgentCapabilitiesCopyWithImpl;
@useResult
$Res call({
 bool loadSession, McpCapabilities mcpCapabilities, PromptCapabilities promptCapabilities, SessionCapabilities sessionCapabilities,@JsonKey(name: '_meta') JsonObject? meta
});


$McpCapabilitiesCopyWith<$Res> get mcpCapabilities;$PromptCapabilitiesCopyWith<$Res> get promptCapabilities;$SessionCapabilitiesCopyWith<$Res> get sessionCapabilities;

}
/// @nodoc
class _$AgentCapabilitiesCopyWithImpl<$Res>
    implements $AgentCapabilitiesCopyWith<$Res> {
  _$AgentCapabilitiesCopyWithImpl(this._self, this._then);

  final AgentCapabilities _self;
  final $Res Function(AgentCapabilities) _then;

/// Create a copy of AgentCapabilities
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? loadSession = null,Object? mcpCapabilities = null,Object? promptCapabilities = null,Object? sessionCapabilities = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
loadSession: null == loadSession ? _self.loadSession : loadSession // ignore: cast_nullable_to_non_nullable
as bool,mcpCapabilities: null == mcpCapabilities ? _self.mcpCapabilities : mcpCapabilities // ignore: cast_nullable_to_non_nullable
as McpCapabilities,promptCapabilities: null == promptCapabilities ? _self.promptCapabilities : promptCapabilities // ignore: cast_nullable_to_non_nullable
as PromptCapabilities,sessionCapabilities: null == sessionCapabilities ? _self.sessionCapabilities : sessionCapabilities // ignore: cast_nullable_to_non_nullable
as SessionCapabilities,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of AgentCapabilities
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpCapabilitiesCopyWith<$Res> get mcpCapabilities {
  
  return $McpCapabilitiesCopyWith<$Res>(_self.mcpCapabilities, (value) {
    return _then(_self.copyWith(mcpCapabilities: value));
  });
}/// Create a copy of AgentCapabilities
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PromptCapabilitiesCopyWith<$Res> get promptCapabilities {
  
  return $PromptCapabilitiesCopyWith<$Res>(_self.promptCapabilities, (value) {
    return _then(_self.copyWith(promptCapabilities: value));
  });
}/// Create a copy of AgentCapabilities
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCapabilitiesCopyWith<$Res> get sessionCapabilities {
  
  return $SessionCapabilitiesCopyWith<$Res>(_self.sessionCapabilities, (value) {
    return _then(_self.copyWith(sessionCapabilities: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentCapabilities].
extension AgentCapabilitiesPatterns on AgentCapabilities {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentCapabilities value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentCapabilities() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentCapabilities value)  $default,){
final _that = this;
switch (_that) {
case _AgentCapabilities():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentCapabilities value)?  $default,){
final _that = this;
switch (_that) {
case _AgentCapabilities() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool loadSession,  McpCapabilities mcpCapabilities,  PromptCapabilities promptCapabilities,  SessionCapabilities sessionCapabilities, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentCapabilities() when $default != null:
return $default(_that.loadSession,_that.mcpCapabilities,_that.promptCapabilities,_that.sessionCapabilities,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool loadSession,  McpCapabilities mcpCapabilities,  PromptCapabilities promptCapabilities,  SessionCapabilities sessionCapabilities, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _AgentCapabilities():
return $default(_that.loadSession,_that.mcpCapabilities,_that.promptCapabilities,_that.sessionCapabilities,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool loadSession,  McpCapabilities mcpCapabilities,  PromptCapabilities promptCapabilities,  SessionCapabilities sessionCapabilities, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _AgentCapabilities() when $default != null:
return $default(_that.loadSession,_that.mcpCapabilities,_that.promptCapabilities,_that.sessionCapabilities,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _AgentCapabilities extends AgentCapabilities {
  const _AgentCapabilities({this.loadSession = false, this.mcpCapabilities = const McpCapabilities(), this.promptCapabilities = const PromptCapabilities(), this.sessionCapabilities = const SessionCapabilities(), @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override@JsonKey() final  bool loadSession;
@override@JsonKey() final  McpCapabilities mcpCapabilities;
@override@JsonKey() final  PromptCapabilities promptCapabilities;
@override@JsonKey() final  SessionCapabilities sessionCapabilities;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of AgentCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentCapabilitiesCopyWith<_AgentCapabilities> get copyWith => __$AgentCapabilitiesCopyWithImpl<_AgentCapabilities>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentCapabilities&&(identical(other.loadSession, loadSession) || other.loadSession == loadSession)&&(identical(other.mcpCapabilities, mcpCapabilities) || other.mcpCapabilities == mcpCapabilities)&&(identical(other.promptCapabilities, promptCapabilities) || other.promptCapabilities == promptCapabilities)&&(identical(other.sessionCapabilities, sessionCapabilities) || other.sessionCapabilities == sessionCapabilities)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,loadSession,mcpCapabilities,promptCapabilities,sessionCapabilities,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'AgentCapabilities(loadSession: $loadSession, mcpCapabilities: $mcpCapabilities, promptCapabilities: $promptCapabilities, sessionCapabilities: $sessionCapabilities, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$AgentCapabilitiesCopyWith<$Res> implements $AgentCapabilitiesCopyWith<$Res> {
  factory _$AgentCapabilitiesCopyWith(_AgentCapabilities value, $Res Function(_AgentCapabilities) _then) = __$AgentCapabilitiesCopyWithImpl;
@override @useResult
$Res call({
 bool loadSession, McpCapabilities mcpCapabilities, PromptCapabilities promptCapabilities, SessionCapabilities sessionCapabilities,@JsonKey(name: '_meta') JsonObject? meta
});


@override $McpCapabilitiesCopyWith<$Res> get mcpCapabilities;@override $PromptCapabilitiesCopyWith<$Res> get promptCapabilities;@override $SessionCapabilitiesCopyWith<$Res> get sessionCapabilities;

}
/// @nodoc
class __$AgentCapabilitiesCopyWithImpl<$Res>
    implements _$AgentCapabilitiesCopyWith<$Res> {
  __$AgentCapabilitiesCopyWithImpl(this._self, this._then);

  final _AgentCapabilities _self;
  final $Res Function(_AgentCapabilities) _then;

/// Create a copy of AgentCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? loadSession = null,Object? mcpCapabilities = null,Object? promptCapabilities = null,Object? sessionCapabilities = null,Object? meta = freezed,}) {
  return _then(_AgentCapabilities(
loadSession: null == loadSession ? _self.loadSession : loadSession // ignore: cast_nullable_to_non_nullable
as bool,mcpCapabilities: null == mcpCapabilities ? _self.mcpCapabilities : mcpCapabilities // ignore: cast_nullable_to_non_nullable
as McpCapabilities,promptCapabilities: null == promptCapabilities ? _self.promptCapabilities : promptCapabilities // ignore: cast_nullable_to_non_nullable
as PromptCapabilities,sessionCapabilities: null == sessionCapabilities ? _self.sessionCapabilities : sessionCapabilities // ignore: cast_nullable_to_non_nullable
as SessionCapabilities,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of AgentCapabilities
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpCapabilitiesCopyWith<$Res> get mcpCapabilities {
  
  return $McpCapabilitiesCopyWith<$Res>(_self.mcpCapabilities, (value) {
    return _then(_self.copyWith(mcpCapabilities: value));
  });
}/// Create a copy of AgentCapabilities
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PromptCapabilitiesCopyWith<$Res> get promptCapabilities {
  
  return $PromptCapabilitiesCopyWith<$Res>(_self.promptCapabilities, (value) {
    return _then(_self.copyWith(promptCapabilities: value));
  });
}/// Create a copy of AgentCapabilities
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCapabilitiesCopyWith<$Res> get sessionCapabilities {
  
  return $SessionCapabilitiesCopyWith<$Res>(_self.sessionCapabilities, (value) {
    return _then(_self.copyWith(sessionCapabilities: value));
  });
}
}

/// @nodoc
mixin _$AuthMethod {

 String get id; String get name; String? get description;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of AuthMethod
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuthMethodCopyWith<AuthMethod> get copyWith => _$AuthMethodCopyWithImpl<AuthMethod>(this as AuthMethod, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthMethod&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,description,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'AuthMethod(id: $id, name: $name, description: $description, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $AuthMethodCopyWith<$Res>  {
  factory $AuthMethodCopyWith(AuthMethod value, $Res Function(AuthMethod) _then) = _$AuthMethodCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? description,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$AuthMethodCopyWithImpl<$Res>
    implements $AuthMethodCopyWith<$Res> {
  _$AuthMethodCopyWithImpl(this._self, this._then);

  final AuthMethod _self;
  final $Res Function(AuthMethod) _then;

/// Create a copy of AuthMethod
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

}


/// Adds pattern-matching-related methods to [AuthMethod].
extension AuthMethodPatterns on AuthMethod {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AuthMethod value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AuthMethod() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AuthMethod value)  $default,){
final _that = this;
switch (_that) {
case _AuthMethod():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AuthMethod value)?  $default,){
final _that = this;
switch (_that) {
case _AuthMethod() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? description, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AuthMethod() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? description, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _AuthMethod():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? description, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _AuthMethod() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _AuthMethod extends AuthMethod {
  const _AuthMethod({required this.id, required this.name, this.description, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  String id;
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


/// Create a copy of AuthMethod
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AuthMethodCopyWith<_AuthMethod> get copyWith => __$AuthMethodCopyWithImpl<_AuthMethod>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AuthMethod&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,description,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'AuthMethod(id: $id, name: $name, description: $description, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$AuthMethodCopyWith<$Res> implements $AuthMethodCopyWith<$Res> {
  factory _$AuthMethodCopyWith(_AuthMethod value, $Res Function(_AuthMethod) _then) = __$AuthMethodCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? description,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class __$AuthMethodCopyWithImpl<$Res>
    implements _$AuthMethodCopyWith<$Res> {
  __$AuthMethodCopyWithImpl(this._self, this._then);

  final _AuthMethod _self;
  final $Res Function(_AuthMethod) _then;

/// Create a copy of AuthMethod
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? meta = freezed,}) {
  return _then(_AuthMethod(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$InitializeRequest {

 ProtocolVersion get protocolVersion; ClientCapabilities get clientCapabilities; Implementation? get clientInfo;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of InitializeRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitializeRequestCopyWith<InitializeRequest> get copyWith => _$InitializeRequestCopyWithImpl<InitializeRequest>(this as InitializeRequest, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitializeRequest&&(identical(other.protocolVersion, protocolVersion) || other.protocolVersion == protocolVersion)&&(identical(other.clientCapabilities, clientCapabilities) || other.clientCapabilities == clientCapabilities)&&(identical(other.clientInfo, clientInfo) || other.clientInfo == clientInfo)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,protocolVersion,clientCapabilities,clientInfo,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'InitializeRequest(protocolVersion: $protocolVersion, clientCapabilities: $clientCapabilities, clientInfo: $clientInfo, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $InitializeRequestCopyWith<$Res>  {
  factory $InitializeRequestCopyWith(InitializeRequest value, $Res Function(InitializeRequest) _then) = _$InitializeRequestCopyWithImpl;
@useResult
$Res call({
 ProtocolVersion protocolVersion, ClientCapabilities clientCapabilities, Implementation? clientInfo,@JsonKey(name: '_meta') JsonObject? meta
});


$ProtocolVersionCopyWith<$Res> get protocolVersion;$ClientCapabilitiesCopyWith<$Res> get clientCapabilities;$ImplementationCopyWith<$Res>? get clientInfo;

}
/// @nodoc
class _$InitializeRequestCopyWithImpl<$Res>
    implements $InitializeRequestCopyWith<$Res> {
  _$InitializeRequestCopyWithImpl(this._self, this._then);

  final InitializeRequest _self;
  final $Res Function(InitializeRequest) _then;

/// Create a copy of InitializeRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? protocolVersion = null,Object? clientCapabilities = null,Object? clientInfo = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
protocolVersion: null == protocolVersion ? _self.protocolVersion : protocolVersion // ignore: cast_nullable_to_non_nullable
as ProtocolVersion,clientCapabilities: null == clientCapabilities ? _self.clientCapabilities : clientCapabilities // ignore: cast_nullable_to_non_nullable
as ClientCapabilities,clientInfo: freezed == clientInfo ? _self.clientInfo : clientInfo // ignore: cast_nullable_to_non_nullable
as Implementation?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of InitializeRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProtocolVersionCopyWith<$Res> get protocolVersion {
  
  return $ProtocolVersionCopyWith<$Res>(_self.protocolVersion, (value) {
    return _then(_self.copyWith(protocolVersion: value));
  });
}/// Create a copy of InitializeRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientCapabilitiesCopyWith<$Res> get clientCapabilities {
  
  return $ClientCapabilitiesCopyWith<$Res>(_self.clientCapabilities, (value) {
    return _then(_self.copyWith(clientCapabilities: value));
  });
}/// Create a copy of InitializeRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ImplementationCopyWith<$Res>? get clientInfo {
    if (_self.clientInfo == null) {
    return null;
  }

  return $ImplementationCopyWith<$Res>(_self.clientInfo!, (value) {
    return _then(_self.copyWith(clientInfo: value));
  });
}
}


/// Adds pattern-matching-related methods to [InitializeRequest].
extension InitializeRequestPatterns on InitializeRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InitializeRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InitializeRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InitializeRequest value)  $default,){
final _that = this;
switch (_that) {
case _InitializeRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InitializeRequest value)?  $default,){
final _that = this;
switch (_that) {
case _InitializeRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProtocolVersion protocolVersion,  ClientCapabilities clientCapabilities,  Implementation? clientInfo, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InitializeRequest() when $default != null:
return $default(_that.protocolVersion,_that.clientCapabilities,_that.clientInfo,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProtocolVersion protocolVersion,  ClientCapabilities clientCapabilities,  Implementation? clientInfo, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _InitializeRequest():
return $default(_that.protocolVersion,_that.clientCapabilities,_that.clientInfo,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProtocolVersion protocolVersion,  ClientCapabilities clientCapabilities,  Implementation? clientInfo, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _InitializeRequest() when $default != null:
return $default(_that.protocolVersion,_that.clientCapabilities,_that.clientInfo,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _InitializeRequest extends InitializeRequest {
  const _InitializeRequest({required this.protocolVersion, this.clientCapabilities = const ClientCapabilities(), this.clientInfo, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  ProtocolVersion protocolVersion;
@override@JsonKey() final  ClientCapabilities clientCapabilities;
@override final  Implementation? clientInfo;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of InitializeRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InitializeRequestCopyWith<_InitializeRequest> get copyWith => __$InitializeRequestCopyWithImpl<_InitializeRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InitializeRequest&&(identical(other.protocolVersion, protocolVersion) || other.protocolVersion == protocolVersion)&&(identical(other.clientCapabilities, clientCapabilities) || other.clientCapabilities == clientCapabilities)&&(identical(other.clientInfo, clientInfo) || other.clientInfo == clientInfo)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,protocolVersion,clientCapabilities,clientInfo,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'InitializeRequest(protocolVersion: $protocolVersion, clientCapabilities: $clientCapabilities, clientInfo: $clientInfo, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$InitializeRequestCopyWith<$Res> implements $InitializeRequestCopyWith<$Res> {
  factory _$InitializeRequestCopyWith(_InitializeRequest value, $Res Function(_InitializeRequest) _then) = __$InitializeRequestCopyWithImpl;
@override @useResult
$Res call({
 ProtocolVersion protocolVersion, ClientCapabilities clientCapabilities, Implementation? clientInfo,@JsonKey(name: '_meta') JsonObject? meta
});


@override $ProtocolVersionCopyWith<$Res> get protocolVersion;@override $ClientCapabilitiesCopyWith<$Res> get clientCapabilities;@override $ImplementationCopyWith<$Res>? get clientInfo;

}
/// @nodoc
class __$InitializeRequestCopyWithImpl<$Res>
    implements _$InitializeRequestCopyWith<$Res> {
  __$InitializeRequestCopyWithImpl(this._self, this._then);

  final _InitializeRequest _self;
  final $Res Function(_InitializeRequest) _then;

/// Create a copy of InitializeRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? protocolVersion = null,Object? clientCapabilities = null,Object? clientInfo = freezed,Object? meta = freezed,}) {
  return _then(_InitializeRequest(
protocolVersion: null == protocolVersion ? _self.protocolVersion : protocolVersion // ignore: cast_nullable_to_non_nullable
as ProtocolVersion,clientCapabilities: null == clientCapabilities ? _self.clientCapabilities : clientCapabilities // ignore: cast_nullable_to_non_nullable
as ClientCapabilities,clientInfo: freezed == clientInfo ? _self.clientInfo : clientInfo // ignore: cast_nullable_to_non_nullable
as Implementation?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of InitializeRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProtocolVersionCopyWith<$Res> get protocolVersion {
  
  return $ProtocolVersionCopyWith<$Res>(_self.protocolVersion, (value) {
    return _then(_self.copyWith(protocolVersion: value));
  });
}/// Create a copy of InitializeRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientCapabilitiesCopyWith<$Res> get clientCapabilities {
  
  return $ClientCapabilitiesCopyWith<$Res>(_self.clientCapabilities, (value) {
    return _then(_self.copyWith(clientCapabilities: value));
  });
}/// Create a copy of InitializeRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ImplementationCopyWith<$Res>? get clientInfo {
    if (_self.clientInfo == null) {
    return null;
  }

  return $ImplementationCopyWith<$Res>(_self.clientInfo!, (value) {
    return _then(_self.copyWith(clientInfo: value));
  });
}
}

/// @nodoc
mixin _$InitializeResponse {

 ProtocolVersion get protocolVersion; AgentCapabilities get agentCapabilities; Implementation? get agentInfo; List<AuthMethod> get authMethods;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of InitializeResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitializeResponseCopyWith<InitializeResponse> get copyWith => _$InitializeResponseCopyWithImpl<InitializeResponse>(this as InitializeResponse, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InitializeResponse&&(identical(other.protocolVersion, protocolVersion) || other.protocolVersion == protocolVersion)&&(identical(other.agentCapabilities, agentCapabilities) || other.agentCapabilities == agentCapabilities)&&(identical(other.agentInfo, agentInfo) || other.agentInfo == agentInfo)&&const DeepCollectionEquality().equals(other.authMethods, authMethods)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,protocolVersion,agentCapabilities,agentInfo,const DeepCollectionEquality().hash(authMethods),const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'InitializeResponse(protocolVersion: $protocolVersion, agentCapabilities: $agentCapabilities, agentInfo: $agentInfo, authMethods: $authMethods, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $InitializeResponseCopyWith<$Res>  {
  factory $InitializeResponseCopyWith(InitializeResponse value, $Res Function(InitializeResponse) _then) = _$InitializeResponseCopyWithImpl;
@useResult
$Res call({
 ProtocolVersion protocolVersion, AgentCapabilities agentCapabilities, Implementation? agentInfo, List<AuthMethod> authMethods,@JsonKey(name: '_meta') JsonObject? meta
});


$ProtocolVersionCopyWith<$Res> get protocolVersion;$AgentCapabilitiesCopyWith<$Res> get agentCapabilities;$ImplementationCopyWith<$Res>? get agentInfo;

}
/// @nodoc
class _$InitializeResponseCopyWithImpl<$Res>
    implements $InitializeResponseCopyWith<$Res> {
  _$InitializeResponseCopyWithImpl(this._self, this._then);

  final InitializeResponse _self;
  final $Res Function(InitializeResponse) _then;

/// Create a copy of InitializeResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? protocolVersion = null,Object? agentCapabilities = null,Object? agentInfo = freezed,Object? authMethods = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
protocolVersion: null == protocolVersion ? _self.protocolVersion : protocolVersion // ignore: cast_nullable_to_non_nullable
as ProtocolVersion,agentCapabilities: null == agentCapabilities ? _self.agentCapabilities : agentCapabilities // ignore: cast_nullable_to_non_nullable
as AgentCapabilities,agentInfo: freezed == agentInfo ? _self.agentInfo : agentInfo // ignore: cast_nullable_to_non_nullable
as Implementation?,authMethods: null == authMethods ? _self.authMethods : authMethods // ignore: cast_nullable_to_non_nullable
as List<AuthMethod>,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of InitializeResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProtocolVersionCopyWith<$Res> get protocolVersion {
  
  return $ProtocolVersionCopyWith<$Res>(_self.protocolVersion, (value) {
    return _then(_self.copyWith(protocolVersion: value));
  });
}/// Create a copy of InitializeResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentCapabilitiesCopyWith<$Res> get agentCapabilities {
  
  return $AgentCapabilitiesCopyWith<$Res>(_self.agentCapabilities, (value) {
    return _then(_self.copyWith(agentCapabilities: value));
  });
}/// Create a copy of InitializeResponse
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
}
}


/// Adds pattern-matching-related methods to [InitializeResponse].
extension InitializeResponsePatterns on InitializeResponse {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InitializeResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InitializeResponse() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InitializeResponse value)  $default,){
final _that = this;
switch (_that) {
case _InitializeResponse():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InitializeResponse value)?  $default,){
final _that = this;
switch (_that) {
case _InitializeResponse() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProtocolVersion protocolVersion,  AgentCapabilities agentCapabilities,  Implementation? agentInfo,  List<AuthMethod> authMethods, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InitializeResponse() when $default != null:
return $default(_that.protocolVersion,_that.agentCapabilities,_that.agentInfo,_that.authMethods,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProtocolVersion protocolVersion,  AgentCapabilities agentCapabilities,  Implementation? agentInfo,  List<AuthMethod> authMethods, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _InitializeResponse():
return $default(_that.protocolVersion,_that.agentCapabilities,_that.agentInfo,_that.authMethods,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProtocolVersion protocolVersion,  AgentCapabilities agentCapabilities,  Implementation? agentInfo,  List<AuthMethod> authMethods, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _InitializeResponse() when $default != null:
return $default(_that.protocolVersion,_that.agentCapabilities,_that.agentInfo,_that.authMethods,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _InitializeResponse extends InitializeResponse {
  const _InitializeResponse({required this.protocolVersion, this.agentCapabilities = const AgentCapabilities(), this.agentInfo, final  List<AuthMethod> authMethods = const [], @JsonKey(name: '_meta') final  JsonObject? meta}): _authMethods = authMethods,_meta = meta,super._();
  

@override final  ProtocolVersion protocolVersion;
@override@JsonKey() final  AgentCapabilities agentCapabilities;
@override final  Implementation? agentInfo;
 final  List<AuthMethod> _authMethods;
@override@JsonKey() List<AuthMethod> get authMethods {
  if (_authMethods is EqualUnmodifiableListView) return _authMethods;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_authMethods);
}

 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of InitializeResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InitializeResponseCopyWith<_InitializeResponse> get copyWith => __$InitializeResponseCopyWithImpl<_InitializeResponse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InitializeResponse&&(identical(other.protocolVersion, protocolVersion) || other.protocolVersion == protocolVersion)&&(identical(other.agentCapabilities, agentCapabilities) || other.agentCapabilities == agentCapabilities)&&(identical(other.agentInfo, agentInfo) || other.agentInfo == agentInfo)&&const DeepCollectionEquality().equals(other._authMethods, _authMethods)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,protocolVersion,agentCapabilities,agentInfo,const DeepCollectionEquality().hash(_authMethods),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'InitializeResponse(protocolVersion: $protocolVersion, agentCapabilities: $agentCapabilities, agentInfo: $agentInfo, authMethods: $authMethods, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$InitializeResponseCopyWith<$Res> implements $InitializeResponseCopyWith<$Res> {
  factory _$InitializeResponseCopyWith(_InitializeResponse value, $Res Function(_InitializeResponse) _then) = __$InitializeResponseCopyWithImpl;
@override @useResult
$Res call({
 ProtocolVersion protocolVersion, AgentCapabilities agentCapabilities, Implementation? agentInfo, List<AuthMethod> authMethods,@JsonKey(name: '_meta') JsonObject? meta
});


@override $ProtocolVersionCopyWith<$Res> get protocolVersion;@override $AgentCapabilitiesCopyWith<$Res> get agentCapabilities;@override $ImplementationCopyWith<$Res>? get agentInfo;

}
/// @nodoc
class __$InitializeResponseCopyWithImpl<$Res>
    implements _$InitializeResponseCopyWith<$Res> {
  __$InitializeResponseCopyWithImpl(this._self, this._then);

  final _InitializeResponse _self;
  final $Res Function(_InitializeResponse) _then;

/// Create a copy of InitializeResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? protocolVersion = null,Object? agentCapabilities = null,Object? agentInfo = freezed,Object? authMethods = null,Object? meta = freezed,}) {
  return _then(_InitializeResponse(
protocolVersion: null == protocolVersion ? _self.protocolVersion : protocolVersion // ignore: cast_nullable_to_non_nullable
as ProtocolVersion,agentCapabilities: null == agentCapabilities ? _self.agentCapabilities : agentCapabilities // ignore: cast_nullable_to_non_nullable
as AgentCapabilities,agentInfo: freezed == agentInfo ? _self.agentInfo : agentInfo // ignore: cast_nullable_to_non_nullable
as Implementation?,authMethods: null == authMethods ? _self._authMethods : authMethods // ignore: cast_nullable_to_non_nullable
as List<AuthMethod>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of InitializeResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProtocolVersionCopyWith<$Res> get protocolVersion {
  
  return $ProtocolVersionCopyWith<$Res>(_self.protocolVersion, (value) {
    return _then(_self.copyWith(protocolVersion: value));
  });
}/// Create a copy of InitializeResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentCapabilitiesCopyWith<$Res> get agentCapabilities {
  
  return $AgentCapabilitiesCopyWith<$Res>(_self.agentCapabilities, (value) {
    return _then(_self.copyWith(agentCapabilities: value));
  });
}/// Create a copy of InitializeResponse
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
}
}

// dart format on
