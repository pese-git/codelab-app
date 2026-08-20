// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'prompt.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Annotations {

 List<Role>? get audience; String? get lastModified; num? get priority;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of Annotations
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnnotationsCopyWith<Annotations> get copyWith => _$AnnotationsCopyWithImpl<Annotations>(this as Annotations, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Annotations&&const DeepCollectionEquality().equals(other.audience, audience)&&(identical(other.lastModified, lastModified) || other.lastModified == lastModified)&&(identical(other.priority, priority) || other.priority == priority)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(audience),lastModified,priority,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'Annotations(audience: $audience, lastModified: $lastModified, priority: $priority, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $AnnotationsCopyWith<$Res>  {
  factory $AnnotationsCopyWith(Annotations value, $Res Function(Annotations) _then) = _$AnnotationsCopyWithImpl;
@useResult
$Res call({
 List<Role>? audience, String? lastModified, num? priority,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$AnnotationsCopyWithImpl<$Res>
    implements $AnnotationsCopyWith<$Res> {
  _$AnnotationsCopyWithImpl(this._self, this._then);

  final Annotations _self;
  final $Res Function(Annotations) _then;

/// Create a copy of Annotations
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? audience = freezed,Object? lastModified = freezed,Object? priority = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
audience: freezed == audience ? _self.audience : audience // ignore: cast_nullable_to_non_nullable
as List<Role>?,lastModified: freezed == lastModified ? _self.lastModified : lastModified // ignore: cast_nullable_to_non_nullable
as String?,priority: freezed == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as num?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

}


/// Adds pattern-matching-related methods to [Annotations].
extension AnnotationsPatterns on Annotations {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Annotations value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Annotations() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Annotations value)  $default,){
final _that = this;
switch (_that) {
case _Annotations():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Annotations value)?  $default,){
final _that = this;
switch (_that) {
case _Annotations() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Role>? audience,  String? lastModified,  num? priority, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Annotations() when $default != null:
return $default(_that.audience,_that.lastModified,_that.priority,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Role>? audience,  String? lastModified,  num? priority, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _Annotations():
return $default(_that.audience,_that.lastModified,_that.priority,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Role>? audience,  String? lastModified,  num? priority, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _Annotations() when $default != null:
return $default(_that.audience,_that.lastModified,_that.priority,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _Annotations extends Annotations {
  const _Annotations({final  List<Role>? audience, this.lastModified, this.priority, @JsonKey(name: '_meta') final  JsonObject? meta}): _audience = audience,_meta = meta,super._();
  

 final  List<Role>? _audience;
@override List<Role>? get audience {
  final value = _audience;
  if (value == null) return null;
  if (_audience is EqualUnmodifiableListView) return _audience;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

@override final  String? lastModified;
@override final  num? priority;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of Annotations
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AnnotationsCopyWith<_Annotations> get copyWith => __$AnnotationsCopyWithImpl<_Annotations>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Annotations&&const DeepCollectionEquality().equals(other._audience, _audience)&&(identical(other.lastModified, lastModified) || other.lastModified == lastModified)&&(identical(other.priority, priority) || other.priority == priority)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_audience),lastModified,priority,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'Annotations(audience: $audience, lastModified: $lastModified, priority: $priority, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$AnnotationsCopyWith<$Res> implements $AnnotationsCopyWith<$Res> {
  factory _$AnnotationsCopyWith(_Annotations value, $Res Function(_Annotations) _then) = __$AnnotationsCopyWithImpl;
@override @useResult
$Res call({
 List<Role>? audience, String? lastModified, num? priority,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class __$AnnotationsCopyWithImpl<$Res>
    implements _$AnnotationsCopyWith<$Res> {
  __$AnnotationsCopyWithImpl(this._self, this._then);

  final _Annotations _self;
  final $Res Function(_Annotations) _then;

/// Create a copy of Annotations
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? audience = freezed,Object? lastModified = freezed,Object? priority = freezed,Object? meta = freezed,}) {
  return _then(_Annotations(
audience: freezed == audience ? _self._audience : audience // ignore: cast_nullable_to_non_nullable
as List<Role>?,lastModified: freezed == lastModified ? _self.lastModified : lastModified // ignore: cast_nullable_to_non_nullable
as String?,priority: freezed == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as num?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$ContentBlock {

 Annotations? get annotations;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContentBlockCopyWith<ContentBlock> get copyWith => _$ContentBlockCopyWithImpl<ContentBlock>(this as ContentBlock, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContentBlock&&(identical(other.annotations, annotations) || other.annotations == annotations)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,annotations,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'ContentBlock(annotations: $annotations, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $ContentBlockCopyWith<$Res>  {
  factory $ContentBlockCopyWith(ContentBlock value, $Res Function(ContentBlock) _then) = _$ContentBlockCopyWithImpl;
@useResult
$Res call({
 Annotations? annotations,@JsonKey(name: '_meta') Map<String, Object?>? meta
});


$AnnotationsCopyWith<$Res>? get annotations;

}
/// @nodoc
class _$ContentBlockCopyWithImpl<$Res>
    implements $ContentBlockCopyWith<$Res> {
  _$ContentBlockCopyWithImpl(this._self, this._then);

  final ContentBlock _self;
  final $Res Function(ContentBlock) _then;

/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? annotations = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
annotations: freezed == annotations ? _self.annotations : annotations // ignore: cast_nullable_to_non_nullable
as Annotations?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}
/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AnnotationsCopyWith<$Res>? get annotations {
    if (_self.annotations == null) {
    return null;
  }

  return $AnnotationsCopyWith<$Res>(_self.annotations!, (value) {
    return _then(_self.copyWith(annotations: value));
  });
}
}


/// Adds pattern-matching-related methods to [ContentBlock].
extension ContentBlockPatterns on ContentBlock {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TextContent value)?  text,TResult Function( ImageContent value)?  image,TResult Function( AudioContent value)?  audio,TResult Function( ResourceLink value)?  resourceLink,TResult Function( EmbeddedResource value)?  resource,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TextContent() when text != null:
return text(_that);case ImageContent() when image != null:
return image(_that);case AudioContent() when audio != null:
return audio(_that);case ResourceLink() when resourceLink != null:
return resourceLink(_that);case EmbeddedResource() when resource != null:
return resource(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TextContent value)  text,required TResult Function( ImageContent value)  image,required TResult Function( AudioContent value)  audio,required TResult Function( ResourceLink value)  resourceLink,required TResult Function( EmbeddedResource value)  resource,}){
final _that = this;
switch (_that) {
case TextContent():
return text(_that);case ImageContent():
return image(_that);case AudioContent():
return audio(_that);case ResourceLink():
return resourceLink(_that);case EmbeddedResource():
return resource(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TextContent value)?  text,TResult? Function( ImageContent value)?  image,TResult? Function( AudioContent value)?  audio,TResult? Function( ResourceLink value)?  resourceLink,TResult? Function( EmbeddedResource value)?  resource,}){
final _that = this;
switch (_that) {
case TextContent() when text != null:
return text(_that);case ImageContent() when image != null:
return image(_that);case AudioContent() when audio != null:
return audio(_that);case ResourceLink() when resourceLink != null:
return resourceLink(_that);case EmbeddedResource() when resource != null:
return resource(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)?  text,TResult Function( String data,  String mimeType,  String? uri,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)?  image,TResult Function( String data,  String mimeType,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)?  audio,TResult Function( String uri,  String name,  String? title,  String? description,  String? mimeType,  int? size,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)?  resourceLink,TResult Function( EmbeddedResourceContents resource,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)?  resource,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TextContent() when text != null:
return text(_that.text,_that.annotations,_that.meta);case ImageContent() when image != null:
return image(_that.data,_that.mimeType,_that.uri,_that.annotations,_that.meta);case AudioContent() when audio != null:
return audio(_that.data,_that.mimeType,_that.annotations,_that.meta);case ResourceLink() when resourceLink != null:
return resourceLink(_that.uri,_that.name,_that.title,_that.description,_that.mimeType,_that.size,_that.annotations,_that.meta);case EmbeddedResource() when resource != null:
return resource(_that.resource,_that.annotations,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)  text,required TResult Function( String data,  String mimeType,  String? uri,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)  image,required TResult Function( String data,  String mimeType,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)  audio,required TResult Function( String uri,  String name,  String? title,  String? description,  String? mimeType,  int? size,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)  resourceLink,required TResult Function( EmbeddedResourceContents resource,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)  resource,}) {final _that = this;
switch (_that) {
case TextContent():
return text(_that.text,_that.annotations,_that.meta);case ImageContent():
return image(_that.data,_that.mimeType,_that.uri,_that.annotations,_that.meta);case AudioContent():
return audio(_that.data,_that.mimeType,_that.annotations,_that.meta);case ResourceLink():
return resourceLink(_that.uri,_that.name,_that.title,_that.description,_that.mimeType,_that.size,_that.annotations,_that.meta);case EmbeddedResource():
return resource(_that.resource,_that.annotations,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)?  text,TResult? Function( String data,  String mimeType,  String? uri,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)?  image,TResult? Function( String data,  String mimeType,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)?  audio,TResult? Function( String uri,  String name,  String? title,  String? description,  String? mimeType,  int? size,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)?  resourceLink,TResult? Function( EmbeddedResourceContents resource,  Annotations? annotations, @JsonKey(name: '_meta')  JsonObject? meta)?  resource,}) {final _that = this;
switch (_that) {
case TextContent() when text != null:
return text(_that.text,_that.annotations,_that.meta);case ImageContent() when image != null:
return image(_that.data,_that.mimeType,_that.uri,_that.annotations,_that.meta);case AudioContent() when audio != null:
return audio(_that.data,_that.mimeType,_that.annotations,_that.meta);case ResourceLink() when resourceLink != null:
return resourceLink(_that.uri,_that.name,_that.title,_that.description,_that.mimeType,_that.size,_that.annotations,_that.meta);case EmbeddedResource() when resource != null:
return resource(_that.resource,_that.annotations,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class TextContent extends ContentBlock {
  const TextContent({required this.text, this.annotations, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

 final  String text;
@override final  Annotations? annotations;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TextContentCopyWith<TextContent> get copyWith => _$TextContentCopyWithImpl<TextContent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TextContent&&(identical(other.text, text) || other.text == text)&&(identical(other.annotations, annotations) || other.annotations == annotations)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,text,annotations,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'ContentBlock.text(text: $text, annotations: $annotations, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $TextContentCopyWith<$Res> implements $ContentBlockCopyWith<$Res> {
  factory $TextContentCopyWith(TextContent value, $Res Function(TextContent) _then) = _$TextContentCopyWithImpl;
@override @useResult
$Res call({
 String text, Annotations? annotations,@JsonKey(name: '_meta') JsonObject? meta
});


@override $AnnotationsCopyWith<$Res>? get annotations;

}
/// @nodoc
class _$TextContentCopyWithImpl<$Res>
    implements $TextContentCopyWith<$Res> {
  _$TextContentCopyWithImpl(this._self, this._then);

  final TextContent _self;
  final $Res Function(TextContent) _then;

/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? text = null,Object? annotations = freezed,Object? meta = freezed,}) {
  return _then(TextContent(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,annotations: freezed == annotations ? _self.annotations : annotations // ignore: cast_nullable_to_non_nullable
as Annotations?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AnnotationsCopyWith<$Res>? get annotations {
    if (_self.annotations == null) {
    return null;
  }

  return $AnnotationsCopyWith<$Res>(_self.annotations!, (value) {
    return _then(_self.copyWith(annotations: value));
  });
}
}

/// @nodoc


class ImageContent extends ContentBlock {
  const ImageContent({required this.data, required this.mimeType, this.uri, this.annotations, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

 final  String data;
 final  String mimeType;
 final  String? uri;
@override final  Annotations? annotations;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ImageContentCopyWith<ImageContent> get copyWith => _$ImageContentCopyWithImpl<ImageContent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ImageContent&&(identical(other.data, data) || other.data == data)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.uri, uri) || other.uri == uri)&&(identical(other.annotations, annotations) || other.annotations == annotations)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,data,mimeType,uri,annotations,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'ContentBlock.image(data: $data, mimeType: $mimeType, uri: $uri, annotations: $annotations, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $ImageContentCopyWith<$Res> implements $ContentBlockCopyWith<$Res> {
  factory $ImageContentCopyWith(ImageContent value, $Res Function(ImageContent) _then) = _$ImageContentCopyWithImpl;
@override @useResult
$Res call({
 String data, String mimeType, String? uri, Annotations? annotations,@JsonKey(name: '_meta') JsonObject? meta
});


@override $AnnotationsCopyWith<$Res>? get annotations;

}
/// @nodoc
class _$ImageContentCopyWithImpl<$Res>
    implements $ImageContentCopyWith<$Res> {
  _$ImageContentCopyWithImpl(this._self, this._then);

  final ImageContent _self;
  final $Res Function(ImageContent) _then;

/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? data = null,Object? mimeType = null,Object? uri = freezed,Object? annotations = freezed,Object? meta = freezed,}) {
  return _then(ImageContent(
data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as String,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,uri: freezed == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String?,annotations: freezed == annotations ? _self.annotations : annotations // ignore: cast_nullable_to_non_nullable
as Annotations?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AnnotationsCopyWith<$Res>? get annotations {
    if (_self.annotations == null) {
    return null;
  }

  return $AnnotationsCopyWith<$Res>(_self.annotations!, (value) {
    return _then(_self.copyWith(annotations: value));
  });
}
}

/// @nodoc


class AudioContent extends ContentBlock {
  const AudioContent({required this.data, required this.mimeType, this.annotations, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

 final  String data;
 final  String mimeType;
@override final  Annotations? annotations;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AudioContentCopyWith<AudioContent> get copyWith => _$AudioContentCopyWithImpl<AudioContent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AudioContent&&(identical(other.data, data) || other.data == data)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.annotations, annotations) || other.annotations == annotations)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,data,mimeType,annotations,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'ContentBlock.audio(data: $data, mimeType: $mimeType, annotations: $annotations, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $AudioContentCopyWith<$Res> implements $ContentBlockCopyWith<$Res> {
  factory $AudioContentCopyWith(AudioContent value, $Res Function(AudioContent) _then) = _$AudioContentCopyWithImpl;
@override @useResult
$Res call({
 String data, String mimeType, Annotations? annotations,@JsonKey(name: '_meta') JsonObject? meta
});


@override $AnnotationsCopyWith<$Res>? get annotations;

}
/// @nodoc
class _$AudioContentCopyWithImpl<$Res>
    implements $AudioContentCopyWith<$Res> {
  _$AudioContentCopyWithImpl(this._self, this._then);

  final AudioContent _self;
  final $Res Function(AudioContent) _then;

/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? data = null,Object? mimeType = null,Object? annotations = freezed,Object? meta = freezed,}) {
  return _then(AudioContent(
data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as String,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,annotations: freezed == annotations ? _self.annotations : annotations // ignore: cast_nullable_to_non_nullable
as Annotations?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AnnotationsCopyWith<$Res>? get annotations {
    if (_self.annotations == null) {
    return null;
  }

  return $AnnotationsCopyWith<$Res>(_self.annotations!, (value) {
    return _then(_self.copyWith(annotations: value));
  });
}
}

/// @nodoc


class ResourceLink extends ContentBlock {
  const ResourceLink({required this.uri, required this.name, this.title, this.description, this.mimeType, this.size, this.annotations, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

 final  String uri;
 final  String name;
 final  String? title;
 final  String? description;
 final  String? mimeType;
 final  int? size;
@override final  Annotations? annotations;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResourceLinkCopyWith<ResourceLink> get copyWith => _$ResourceLinkCopyWithImpl<ResourceLink>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResourceLink&&(identical(other.uri, uri) || other.uri == uri)&&(identical(other.name, name) || other.name == name)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.size, size) || other.size == size)&&(identical(other.annotations, annotations) || other.annotations == annotations)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,uri,name,title,description,mimeType,size,annotations,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'ContentBlock.resourceLink(uri: $uri, name: $name, title: $title, description: $description, mimeType: $mimeType, size: $size, annotations: $annotations, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $ResourceLinkCopyWith<$Res> implements $ContentBlockCopyWith<$Res> {
  factory $ResourceLinkCopyWith(ResourceLink value, $Res Function(ResourceLink) _then) = _$ResourceLinkCopyWithImpl;
@override @useResult
$Res call({
 String uri, String name, String? title, String? description, String? mimeType, int? size, Annotations? annotations,@JsonKey(name: '_meta') JsonObject? meta
});


@override $AnnotationsCopyWith<$Res>? get annotations;

}
/// @nodoc
class _$ResourceLinkCopyWithImpl<$Res>
    implements $ResourceLinkCopyWith<$Res> {
  _$ResourceLinkCopyWithImpl(this._self, this._then);

  final ResourceLink _self;
  final $Res Function(ResourceLink) _then;

/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? uri = null,Object? name = null,Object? title = freezed,Object? description = freezed,Object? mimeType = freezed,Object? size = freezed,Object? annotations = freezed,Object? meta = freezed,}) {
  return _then(ResourceLink(
uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,size: freezed == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int?,annotations: freezed == annotations ? _self.annotations : annotations // ignore: cast_nullable_to_non_nullable
as Annotations?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AnnotationsCopyWith<$Res>? get annotations {
    if (_self.annotations == null) {
    return null;
  }

  return $AnnotationsCopyWith<$Res>(_self.annotations!, (value) {
    return _then(_self.copyWith(annotations: value));
  });
}
}

/// @nodoc


class EmbeddedResource extends ContentBlock {
  const EmbeddedResource({required this.resource, this.annotations, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

 final  EmbeddedResourceContents resource;
@override final  Annotations? annotations;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EmbeddedResourceCopyWith<EmbeddedResource> get copyWith => _$EmbeddedResourceCopyWithImpl<EmbeddedResource>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EmbeddedResource&&(identical(other.resource, resource) || other.resource == resource)&&(identical(other.annotations, annotations) || other.annotations == annotations)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,resource,annotations,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'ContentBlock.resource(resource: $resource, annotations: $annotations, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $EmbeddedResourceCopyWith<$Res> implements $ContentBlockCopyWith<$Res> {
  factory $EmbeddedResourceCopyWith(EmbeddedResource value, $Res Function(EmbeddedResource) _then) = _$EmbeddedResourceCopyWithImpl;
@override @useResult
$Res call({
 EmbeddedResourceContents resource, Annotations? annotations,@JsonKey(name: '_meta') JsonObject? meta
});


$EmbeddedResourceContentsCopyWith<$Res> get resource;@override $AnnotationsCopyWith<$Res>? get annotations;

}
/// @nodoc
class _$EmbeddedResourceCopyWithImpl<$Res>
    implements $EmbeddedResourceCopyWith<$Res> {
  _$EmbeddedResourceCopyWithImpl(this._self, this._then);

  final EmbeddedResource _self;
  final $Res Function(EmbeddedResource) _then;

/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? resource = null,Object? annotations = freezed,Object? meta = freezed,}) {
  return _then(EmbeddedResource(
resource: null == resource ? _self.resource : resource // ignore: cast_nullable_to_non_nullable
as EmbeddedResourceContents,annotations: freezed == annotations ? _self.annotations : annotations // ignore: cast_nullable_to_non_nullable
as Annotations?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EmbeddedResourceContentsCopyWith<$Res> get resource {
  
  return $EmbeddedResourceContentsCopyWith<$Res>(_self.resource, (value) {
    return _then(_self.copyWith(resource: value));
  });
}/// Create a copy of ContentBlock
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AnnotationsCopyWith<$Res>? get annotations {
    if (_self.annotations == null) {
    return null;
  }

  return $AnnotationsCopyWith<$Res>(_self.annotations!, (value) {
    return _then(_self.copyWith(annotations: value));
  });
}
}

/// @nodoc
mixin _$EmbeddedResourceContents {

 String get uri; String? get mimeType;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of EmbeddedResourceContents
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EmbeddedResourceContentsCopyWith<EmbeddedResourceContents> get copyWith => _$EmbeddedResourceContentsCopyWithImpl<EmbeddedResourceContents>(this as EmbeddedResourceContents, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EmbeddedResourceContents&&(identical(other.uri, uri) || other.uri == uri)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,uri,mimeType,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'EmbeddedResourceContents(uri: $uri, mimeType: $mimeType, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $EmbeddedResourceContentsCopyWith<$Res>  {
  factory $EmbeddedResourceContentsCopyWith(EmbeddedResourceContents value, $Res Function(EmbeddedResourceContents) _then) = _$EmbeddedResourceContentsCopyWithImpl;
@useResult
$Res call({
 String uri, String? mimeType,@JsonKey(name: '_meta') Map<String, Object?>? meta
});




}
/// @nodoc
class _$EmbeddedResourceContentsCopyWithImpl<$Res>
    implements $EmbeddedResourceContentsCopyWith<$Res> {
  _$EmbeddedResourceContentsCopyWithImpl(this._self, this._then);

  final EmbeddedResourceContents _self;
  final $Res Function(EmbeddedResourceContents) _then;

/// Create a copy of EmbeddedResourceContents
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? uri = null,Object? mimeType = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>?,
  ));
}

}


/// Adds pattern-matching-related methods to [EmbeddedResourceContents].
extension EmbeddedResourceContentsPatterns on EmbeddedResourceContents {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TextResourceContents value)?  text,TResult Function( BlobResourceContents value)?  blob,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TextResourceContents() when text != null:
return text(_that);case BlobResourceContents() when blob != null:
return blob(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TextResourceContents value)  text,required TResult Function( BlobResourceContents value)  blob,}){
final _that = this;
switch (_that) {
case TextResourceContents():
return text(_that);case BlobResourceContents():
return blob(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TextResourceContents value)?  text,TResult? Function( BlobResourceContents value)?  blob,}){
final _that = this;
switch (_that) {
case TextResourceContents() when text != null:
return text(_that);case BlobResourceContents() when blob != null:
return blob(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String uri,  String text,  String? mimeType, @JsonKey(name: '_meta')  JsonObject? meta)?  text,TResult Function( String uri,  String blob,  String? mimeType, @JsonKey(name: '_meta')  JsonObject? meta)?  blob,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TextResourceContents() when text != null:
return text(_that.uri,_that.text,_that.mimeType,_that.meta);case BlobResourceContents() when blob != null:
return blob(_that.uri,_that.blob,_that.mimeType,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String uri,  String text,  String? mimeType, @JsonKey(name: '_meta')  JsonObject? meta)  text,required TResult Function( String uri,  String blob,  String? mimeType, @JsonKey(name: '_meta')  JsonObject? meta)  blob,}) {final _that = this;
switch (_that) {
case TextResourceContents():
return text(_that.uri,_that.text,_that.mimeType,_that.meta);case BlobResourceContents():
return blob(_that.uri,_that.blob,_that.mimeType,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String uri,  String text,  String? mimeType, @JsonKey(name: '_meta')  JsonObject? meta)?  text,TResult? Function( String uri,  String blob,  String? mimeType, @JsonKey(name: '_meta')  JsonObject? meta)?  blob,}) {final _that = this;
switch (_that) {
case TextResourceContents() when text != null:
return text(_that.uri,_that.text,_that.mimeType,_that.meta);case BlobResourceContents() when blob != null:
return blob(_that.uri,_that.blob,_that.mimeType,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class TextResourceContents extends EmbeddedResourceContents {
  const TextResourceContents({required this.uri, required this.text, this.mimeType, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  String uri;
 final  String text;
@override final  String? mimeType;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of EmbeddedResourceContents
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TextResourceContentsCopyWith<TextResourceContents> get copyWith => _$TextResourceContentsCopyWithImpl<TextResourceContents>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TextResourceContents&&(identical(other.uri, uri) || other.uri == uri)&&(identical(other.text, text) || other.text == text)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,uri,text,mimeType,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'EmbeddedResourceContents.text(uri: $uri, text: $text, mimeType: $mimeType, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $TextResourceContentsCopyWith<$Res> implements $EmbeddedResourceContentsCopyWith<$Res> {
  factory $TextResourceContentsCopyWith(TextResourceContents value, $Res Function(TextResourceContents) _then) = _$TextResourceContentsCopyWithImpl;
@override @useResult
$Res call({
 String uri, String text, String? mimeType,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$TextResourceContentsCopyWithImpl<$Res>
    implements $TextResourceContentsCopyWith<$Res> {
  _$TextResourceContentsCopyWithImpl(this._self, this._then);

  final TextResourceContents _self;
  final $Res Function(TextResourceContents) _then;

/// Create a copy of EmbeddedResourceContents
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? uri = null,Object? text = null,Object? mimeType = freezed,Object? meta = freezed,}) {
  return _then(TextResourceContents(
uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc


class BlobResourceContents extends EmbeddedResourceContents {
  const BlobResourceContents({required this.uri, required this.blob, this.mimeType, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  String uri;
 final  String blob;
@override final  String? mimeType;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of EmbeddedResourceContents
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlobResourceContentsCopyWith<BlobResourceContents> get copyWith => _$BlobResourceContentsCopyWithImpl<BlobResourceContents>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlobResourceContents&&(identical(other.uri, uri) || other.uri == uri)&&(identical(other.blob, blob) || other.blob == blob)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,uri,blob,mimeType,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'EmbeddedResourceContents.blob(uri: $uri, blob: $blob, mimeType: $mimeType, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BlobResourceContentsCopyWith<$Res> implements $EmbeddedResourceContentsCopyWith<$Res> {
  factory $BlobResourceContentsCopyWith(BlobResourceContents value, $Res Function(BlobResourceContents) _then) = _$BlobResourceContentsCopyWithImpl;
@override @useResult
$Res call({
 String uri, String blob, String? mimeType,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$BlobResourceContentsCopyWithImpl<$Res>
    implements $BlobResourceContentsCopyWith<$Res> {
  _$BlobResourceContentsCopyWithImpl(this._self, this._then);

  final BlobResourceContents _self;
  final $Res Function(BlobResourceContents) _then;

/// Create a copy of EmbeddedResourceContents
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? uri = null,Object? blob = null,Object? mimeType = freezed,Object? meta = freezed,}) {
  return _then(BlobResourceContents(
uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String,blob: null == blob ? _self.blob : blob // ignore: cast_nullable_to_non_nullable
as String,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$PromptRequest {

 SessionId get sessionId; List<ContentBlock> get prompt;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of PromptRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptRequestCopyWith<PromptRequest> get copyWith => _$PromptRequestCopyWithImpl<PromptRequest>(this as PromptRequest, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptRequest&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&const DeepCollectionEquality().equals(other.prompt, prompt)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,const DeepCollectionEquality().hash(prompt),const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'PromptRequest(sessionId: $sessionId, prompt: $prompt, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $PromptRequestCopyWith<$Res>  {
  factory $PromptRequestCopyWith(PromptRequest value, $Res Function(PromptRequest) _then) = _$PromptRequestCopyWithImpl;
@useResult
$Res call({
 SessionId sessionId, List<ContentBlock> prompt,@JsonKey(name: '_meta') JsonObject? meta
});


$SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class _$PromptRequestCopyWithImpl<$Res>
    implements $PromptRequestCopyWith<$Res> {
  _$PromptRequestCopyWithImpl(this._self, this._then);

  final PromptRequest _self;
  final $Res Function(PromptRequest) _then;

/// Create a copy of PromptRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? prompt = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,prompt: null == prompt ? _self.prompt : prompt // ignore: cast_nullable_to_non_nullable
as List<ContentBlock>,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of PromptRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}
}


/// Adds pattern-matching-related methods to [PromptRequest].
extension PromptRequestPatterns on PromptRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PromptRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PromptRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PromptRequest value)  $default,){
final _that = this;
switch (_that) {
case _PromptRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PromptRequest value)?  $default,){
final _that = this;
switch (_that) {
case _PromptRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionId sessionId,  List<ContentBlock> prompt, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PromptRequest() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionId sessionId,  List<ContentBlock> prompt, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _PromptRequest():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionId sessionId,  List<ContentBlock> prompt, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _PromptRequest() when $default != null:
return $default(_that.sessionId,_that.prompt,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _PromptRequest extends PromptRequest {
  const _PromptRequest({required this.sessionId, required final  List<ContentBlock> prompt, @JsonKey(name: '_meta') final  JsonObject? meta}): _prompt = prompt,_meta = meta,super._();
  

@override final  SessionId sessionId;
 final  List<ContentBlock> _prompt;
@override List<ContentBlock> get prompt {
  if (_prompt is EqualUnmodifiableListView) return _prompt;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_prompt);
}

 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of PromptRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PromptRequestCopyWith<_PromptRequest> get copyWith => __$PromptRequestCopyWithImpl<_PromptRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PromptRequest&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&const DeepCollectionEquality().equals(other._prompt, _prompt)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,const DeepCollectionEquality().hash(_prompt),const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'PromptRequest(sessionId: $sessionId, prompt: $prompt, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$PromptRequestCopyWith<$Res> implements $PromptRequestCopyWith<$Res> {
  factory _$PromptRequestCopyWith(_PromptRequest value, $Res Function(_PromptRequest) _then) = __$PromptRequestCopyWithImpl;
@override @useResult
$Res call({
 SessionId sessionId, List<ContentBlock> prompt,@JsonKey(name: '_meta') JsonObject? meta
});


@override $SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class __$PromptRequestCopyWithImpl<$Res>
    implements _$PromptRequestCopyWith<$Res> {
  __$PromptRequestCopyWithImpl(this._self, this._then);

  final _PromptRequest _self;
  final $Res Function(_PromptRequest) _then;

/// Create a copy of PromptRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? prompt = null,Object? meta = freezed,}) {
  return _then(_PromptRequest(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,prompt: null == prompt ? _self._prompt : prompt // ignore: cast_nullable_to_non_nullable
as List<ContentBlock>,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of PromptRequest
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
mixin _$PromptResponse {

 StopReason get stopReason;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of PromptResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PromptResponseCopyWith<PromptResponse> get copyWith => _$PromptResponseCopyWithImpl<PromptResponse>(this as PromptResponse, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PromptResponse&&(identical(other.stopReason, stopReason) || other.stopReason == stopReason)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,stopReason,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'PromptResponse(stopReason: $stopReason, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $PromptResponseCopyWith<$Res>  {
  factory $PromptResponseCopyWith(PromptResponse value, $Res Function(PromptResponse) _then) = _$PromptResponseCopyWithImpl;
@useResult
$Res call({
 StopReason stopReason,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class _$PromptResponseCopyWithImpl<$Res>
    implements $PromptResponseCopyWith<$Res> {
  _$PromptResponseCopyWithImpl(this._self, this._then);

  final PromptResponse _self;
  final $Res Function(PromptResponse) _then;

/// Create a copy of PromptResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stopReason = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
stopReason: null == stopReason ? _self.stopReason : stopReason // ignore: cast_nullable_to_non_nullable
as StopReason,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

}


/// Adds pattern-matching-related methods to [PromptResponse].
extension PromptResponsePatterns on PromptResponse {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PromptResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PromptResponse() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PromptResponse value)  $default,){
final _that = this;
switch (_that) {
case _PromptResponse():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PromptResponse value)?  $default,){
final _that = this;
switch (_that) {
case _PromptResponse() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StopReason stopReason, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PromptResponse() when $default != null:
return $default(_that.stopReason,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StopReason stopReason, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _PromptResponse():
return $default(_that.stopReason,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StopReason stopReason, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _PromptResponse() when $default != null:
return $default(_that.stopReason,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _PromptResponse extends PromptResponse {
  const _PromptResponse({required this.stopReason, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  StopReason stopReason;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of PromptResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PromptResponseCopyWith<_PromptResponse> get copyWith => __$PromptResponseCopyWithImpl<_PromptResponse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PromptResponse&&(identical(other.stopReason, stopReason) || other.stopReason == stopReason)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,stopReason,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'PromptResponse(stopReason: $stopReason, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$PromptResponseCopyWith<$Res> implements $PromptResponseCopyWith<$Res> {
  factory _$PromptResponseCopyWith(_PromptResponse value, $Res Function(_PromptResponse) _then) = __$PromptResponseCopyWithImpl;
@override @useResult
$Res call({
 StopReason stopReason,@JsonKey(name: '_meta') JsonObject? meta
});




}
/// @nodoc
class __$PromptResponseCopyWithImpl<$Res>
    implements _$PromptResponseCopyWith<$Res> {
  __$PromptResponseCopyWithImpl(this._self, this._then);

  final _PromptResponse _self;
  final $Res Function(_PromptResponse) _then;

/// Create a copy of PromptResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stopReason = null,Object? meta = freezed,}) {
  return _then(_PromptResponse(
stopReason: null == stopReason ? _self.stopReason : stopReason // ignore: cast_nullable_to_non_nullable
as StopReason,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}


}

/// @nodoc
mixin _$CancelNotification {

 SessionId get sessionId;@JsonKey(name: '_meta') JsonObject? get meta;
/// Create a copy of CancelNotification
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelNotificationCopyWith<CancelNotification> get copyWith => _$CancelNotificationCopyWithImpl<CancelNotification>(this as CancelNotification, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelNotification&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&const DeepCollectionEquality().equals(other.meta, meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,const DeepCollectionEquality().hash(meta));

@override
String toString() {
  return 'CancelNotification(sessionId: $sessionId, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $CancelNotificationCopyWith<$Res>  {
  factory $CancelNotificationCopyWith(CancelNotification value, $Res Function(CancelNotification) _then) = _$CancelNotificationCopyWithImpl;
@useResult
$Res call({
 SessionId sessionId,@JsonKey(name: '_meta') JsonObject? meta
});


$SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class _$CancelNotificationCopyWithImpl<$Res>
    implements $CancelNotificationCopyWith<$Res> {
  _$CancelNotificationCopyWithImpl(this._self, this._then);

  final CancelNotification _self;
  final $Res Function(CancelNotification) _then;

/// Create a copy of CancelNotification
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? meta = freezed,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}
/// Create a copy of CancelNotification
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}
}


/// Adds pattern-matching-related methods to [CancelNotification].
extension CancelNotificationPatterns on CancelNotification {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CancelNotification value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CancelNotification() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CancelNotification value)  $default,){
final _that = this;
switch (_that) {
case _CancelNotification():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CancelNotification value)?  $default,){
final _that = this;
switch (_that) {
case _CancelNotification() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionId sessionId, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CancelNotification() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionId sessionId, @JsonKey(name: '_meta')  JsonObject? meta)  $default,) {final _that = this;
switch (_that) {
case _CancelNotification():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionId sessionId, @JsonKey(name: '_meta')  JsonObject? meta)?  $default,) {final _that = this;
switch (_that) {
case _CancelNotification() when $default != null:
return $default(_that.sessionId,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class _CancelNotification extends CancelNotification {
  const _CancelNotification({required this.sessionId, @JsonKey(name: '_meta') final  JsonObject? meta}): _meta = meta,super._();
  

@override final  SessionId sessionId;
 final  JsonObject? _meta;
@override@JsonKey(name: '_meta') JsonObject? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of CancelNotification
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CancelNotificationCopyWith<_CancelNotification> get copyWith => __$CancelNotificationCopyWithImpl<_CancelNotification>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CancelNotification&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&const DeepCollectionEquality().equals(other._meta, _meta));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,const DeepCollectionEquality().hash(_meta));

@override
String toString() {
  return 'CancelNotification(sessionId: $sessionId, meta: $meta)';
}


}

/// @nodoc
abstract mixin class _$CancelNotificationCopyWith<$Res> implements $CancelNotificationCopyWith<$Res> {
  factory _$CancelNotificationCopyWith(_CancelNotification value, $Res Function(_CancelNotification) _then) = __$CancelNotificationCopyWithImpl;
@override @useResult
$Res call({
 SessionId sessionId,@JsonKey(name: '_meta') JsonObject? meta
});


@override $SessionIdCopyWith<$Res> get sessionId;

}
/// @nodoc
class __$CancelNotificationCopyWithImpl<$Res>
    implements _$CancelNotificationCopyWith<$Res> {
  __$CancelNotificationCopyWithImpl(this._self, this._then);

  final _CancelNotification _self;
  final $Res Function(_CancelNotification) _then;

/// Create a copy of CancelNotification
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? meta = freezed,}) {
  return _then(_CancelNotification(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as SessionId,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as JsonObject?,
  ));
}

/// Create a copy of CancelNotification
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionIdCopyWith<$Res> get sessionId {
  
  return $SessionIdCopyWith<$Res>(_self.sessionId, (value) {
    return _then(_self.copyWith(sessionId: value));
  });
}
}

// dart format on
