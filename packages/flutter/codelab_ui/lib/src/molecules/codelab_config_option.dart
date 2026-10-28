import 'package:freezed_annotation/freezed_annotation.dart';

part 'codelab_config_option.freezed.dart';

/// One selectable value of an [CodeLabConfigOption].
@freezed
sealed class CodeLabConfigOptionValue with _$CodeLabConfigOptionValue {
  const factory CodeLabConfigOptionValue({
    required String value,
    required String name,
    String? description,
  }) = _AcpConfigOptionValue;
}

/// A UI-facing projection of an agent-declared `SessionConfigOption`
/// (`docs/protocols/acp/protocol/13-Session Config Options.md`) — typically a model or
/// mode selector. Deliberately not the protocol DTO itself: `codelab_ui` has no
/// dependency on `codelab_acp_protocol`, so the mapping happens at the application
/// boundary (`CodeLabShellCubit`), same as `AvailableCommand` -> [CodeLabCommandAction].
@freezed
sealed class CodeLabConfigOption with _$CodeLabConfigOption {
  const factory CodeLabConfigOption({
    required String id,
    required String name,
    required String currentValue,
    required List<CodeLabConfigOptionValue> values,
    String? description,
  }) = _AcpConfigOption;
}
