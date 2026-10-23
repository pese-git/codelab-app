/// Tokens and cost of a model answer (`agent-core-architecture` §2.2,
/// §2.12).
library;

final class Usage {
  const Usage({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
    this.reasoning,
    this.cost = UsageCost.zero,
  });

  factory Usage.fromJson(Map<String, Object?> json) => Usage(
    input: _int(json['input']),
    output: _int(json['output']),
    cacheRead: _int(json['cacheRead']),
    cacheWrite: _int(json['cacheWrite']),
    reasoning: json['reasoning'] is int ? json['reasoning']! as int : null,
    cost: json['cost'] is Map<String, Object?>
        ? UsageCost.fromJson(json['cost']! as Map<String, Object?>)
        : UsageCost.zero,
  );

  /// Input tokens WITHOUT the ones read from the cache.
  final int input;

  /// Output tokens, reasoning included.
  final int output;
  final int cacheRead, cacheWrite;

  /// Part of [output], when the provider reports it.
  final int? reasoning;
  final UsageCost cost;

  int get total => input + output + cacheRead + cacheWrite;

  static const zero = Usage();

  Usage operator +(Usage o) => Usage(
    input: input + o.input,
    output: output + o.output,
    cacheRead: cacheRead + o.cacheRead,
    cacheWrite: cacheWrite + o.cacheWrite,
    reasoning: (reasoning == null && o.reasoning == null)
        ? null
        : (reasoning ?? 0) + (o.reasoning ?? 0),
    cost: cost + o.cost,
  );

  Map<String, Object?> toJson() => {
    'input': input,
    'output': output,
    'cacheRead': cacheRead,
    'cacheWrite': cacheWrite,
    'reasoning': ?reasoning,
    'cost': cost.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is Usage &&
      other.input == input &&
      other.output == output &&
      other.cacheRead == cacheRead &&
      other.cacheWrite == cacheWrite &&
      other.reasoning == reasoning &&
      other.cost == cost;

  @override
  int get hashCode =>
      Object.hash(input, output, cacheRead, cacheWrite, reasoning, cost);

  @override
  String toString() =>
      'Usage(input: $input, output: $output, cacheRead: $cacheRead, '
      'cacheWrite: $cacheWrite, reasoning: $reasoning, '
      'cost: ${cost.total})';
}

/// US dollars.
final class UsageCost {
  const UsageCost({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
  });

  factory UsageCost.fromJson(Map<String, Object?> json) => UsageCost(
    input: _double(json['input']),
    output: _double(json['output']),
    cacheRead: _double(json['cacheRead']),
    cacheWrite: _double(json['cacheWrite']),
  );

  final double input, output, cacheRead, cacheWrite;

  double get total => input + output + cacheRead + cacheWrite;

  static const zero = UsageCost();

  UsageCost operator +(UsageCost o) => UsageCost(
    input: input + o.input,
    output: output + o.output,
    cacheRead: cacheRead + o.cacheRead,
    cacheWrite: cacheWrite + o.cacheWrite,
  );

  Map<String, Object?> toJson() => {
    'input': input,
    'output': output,
    'cacheRead': cacheRead,
    'cacheWrite': cacheWrite,
  };

  @override
  bool operator ==(Object other) =>
      other is UsageCost &&
      other.input == input &&
      other.output == output &&
      other.cacheRead == cacheRead &&
      other.cacheWrite == cacheWrite;

  @override
  int get hashCode => Object.hash(input, output, cacheRead, cacheWrite);
}

int _int(Object? value) => value is num ? value.toInt() : 0;

double _double(Object? value) => value is num ? value.toDouble() : 0;
