import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';

/// A configurable tool for executor and loop tests.
final class FakeTool extends AgentTool {
  FakeTool(
    this.name, {
    this.parameters = const {'type': 'object'},
    this.tier = ToolTier.read,
    this.kind = ToolKind.other,
    this.executionMode,
    this.onExecute,
    this.preflightText,
    this.sequentialWhen,
    this.lockArg,
    this.lockKeyValue,
    this.lockKeyOf,
  });

  @override
  final String name;

  @override
  String get description => 'Fake tool $name.';

  @override
  final Map<String, Object?> parameters;

  @override
  final ToolTier tier;

  @override
  final ToolKind kind;

  @override
  final ToolExecutionMode? executionMode;

  final FutureOr<ToolExecutionResult> Function(
    Map<String, Object?> args,
    ToolContext ctx,
  )?
  onExecute;
  final String? preflightText;

  /// `executionModeOf` is sequential when this argument is present.
  final String? sequentialWhen;

  /// Аргумент с путём, который точка исполнения держит под `PathLock`.
  final String? lockArg;

  /// Постоянный ключ очереди `AgentTool.lockKey`; `null` — ключа нет.
  final String? lockKeyValue;

  /// Ключ по аргументам (приоритетнее [lockKeyValue]); может бросить — так
  /// тест проверяет сбой вычисления ключа до резервирования.
  final String? Function(Map<String, Object?> args)? lockKeyOf;

  final executed = <Map<String, Object?>>[];

  @override
  String? lockPath(Map<String, Object?> args) =>
      lockArg == null ? null : args[lockArg] as String?;

  @override
  String? lockKey(Map<String, Object?> args) =>
      lockKeyOf != null ? lockKeyOf!(args) : lockKeyValue;

  @override
  ContentTrust outputTrust(Map<String, Object?> args) => ContentTrust.trusted;

  @override
  ToolExecutionMode? executionModeOf(Map<String, Object?> args) =>
      sequentialWhen != null && args.containsKey(sequentialWhen)
      ? ToolExecutionMode.sequential
      : executionMode;

  @override
  String? preflight(Map<String, Object?> args) => preflightText;

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    executed.add(args);
    final handler = onExecute;
    if (handler != null) {
      return handler(args, ctx);
    }
    return ToolExecutionResult([TextContent('$name ok')]);
  }
}
