import '../util/ids.dart';

/// [IdGenerator] giving `id-1`, `id-2`, … — the same sequence on every run.
final class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator({this.prefix = 'id-'});

  final String prefix;
  var _next = 1;

  @override
  String nextId() => '$prefix${_next++}';
}
