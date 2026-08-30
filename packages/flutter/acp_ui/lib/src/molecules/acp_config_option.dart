import 'package:freezed_annotation/freezed_annotation.dart';

part 'acp_config_option.freezed.dart';

/// One selectable value of an [AcpConfigOption].
@freezed
sealed class AcpConfigOptionValue with _$AcpConfigOptionValue {
  const factory AcpConfigOptionValue({
    required String value,
    required String name,
    String? description,
  }) = _AcpConfigOptionValue;
}

/// A UI-facing projection of an agent-declared `SessionConfigOption`
/// (`docs/acp/protocol/13-Session Config Options.md`) — typically a model or
/// mode selector. Deliberately not the protocol DTO itself: `acp_ui` has no
/// dependency on `acp_protocol`, so the mapping happens at the application
/// boundary (`CodeLabShellCubit`), same as `AvailableCommand` -> [AcpCommandAction].
@freezed
sealed class AcpConfigOption with _$AcpConfigOption {
  const factory AcpConfigOption({
    required String id,
    required String name,
    required String currentValue,
    required List<AcpConfigOptionValue> values,
    String? description,
  }) = _AcpConfigOption;
}
