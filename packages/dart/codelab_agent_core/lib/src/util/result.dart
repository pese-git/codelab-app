import 'package:collection/collection.dart';

/// A value or an expected error (`agent-core-architecture` §4.2): ports of
/// the core return it instead of throwing for expected failures (ENV-1).
///
/// ```dart
/// switch (result) { Ok(:final value) => ..., Err(:final error) => ... }
/// ```
sealed class Result<T, E> {
  const Result();
}

const _deep = DeepCollectionEquality();

final class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) =>
      other is Ok<T, E> && _deep.equals(other.value, value);

  @override
  int get hashCode => _deep.hash(value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T, E> extends Result<T, E> {
  const Err(this.error);

  final E error;

  @override
  bool operator ==(Object other) =>
      other is Err<T, E> && _deep.equals(other.error, error);

  @override
  int get hashCode => _deep.hash(error);

  @override
  String toString() => 'Err($error)';
}
