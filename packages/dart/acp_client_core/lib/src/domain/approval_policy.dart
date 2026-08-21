import 'package:acp_protocol/acp_protocol.dart';

import 'domain_models.dart';

enum PermissionMode { readOnly, ask, plan, autoEdits }

enum PermissionModeDecision {
  allowWithoutApproval,
  requireExplicitApproval,
  unavailable,
}

final class ApprovalPolicy {
  const ApprovalPolicy._();

  static ApprovalRiskLevel classifyToolCall(ToolCall toolCall) {
    return _classifyToolAction(
      kind: toolCall.kind,
      title: toolCall.title,
      content: toolCall.content,
      locations: toolCall.locations,
      rawInput: toolCall.rawInput,
      rawOutput: toolCall.rawOutput,
    );
  }

  static ApprovalRiskLevel classifyToolCallUpdate(ToolCallUpdate update) {
    return _classifyToolAction(
      kind: update.kind,
      title: update.title,
      content: update.content,
      locations: update.locations,
      rawInput: update.rawInput,
      rawOutput: update.rawOutput,
    );
  }

  static ApprovalRiskLevel max(
    ApprovalRiskLevel first,
    ApprovalRiskLevel second,
  ) {
    return _rank(first) >= _rank(second) ? first : second;
  }

  static PermissionModeDecision decidePermission({
    required PermissionMode mode,
    required ApprovalRiskLevel riskLevel,
  }) {
    return switch (mode) {
      PermissionMode.readOnly => switch (riskLevel) {
        ApprovalRiskLevel.readOnly =>
          PermissionModeDecision.allowWithoutApproval,
        ApprovalRiskLevel.localWrite ||
        ApprovalRiskLevel.network ||
        ApprovalRiskLevel.shell ||
        ApprovalRiskLevel.destructive =>
          PermissionModeDecision.requireExplicitApproval,
      },
      PermissionMode.ask => switch (riskLevel) {
        ApprovalRiskLevel.readOnly =>
          PermissionModeDecision.allowWithoutApproval,
        ApprovalRiskLevel.localWrite ||
        ApprovalRiskLevel.network ||
        ApprovalRiskLevel.shell ||
        ApprovalRiskLevel.destructive =>
          PermissionModeDecision.requireExplicitApproval,
      },
      PermissionMode.plan => switch (riskLevel) {
        ApprovalRiskLevel.readOnly =>
          PermissionModeDecision.allowWithoutApproval,
        ApprovalRiskLevel.localWrite ||
        ApprovalRiskLevel.destructive => PermissionModeDecision.unavailable,
        ApprovalRiskLevel.network || ApprovalRiskLevel.shell =>
          PermissionModeDecision.requireExplicitApproval,
      },
      PermissionMode.autoEdits => switch (riskLevel) {
        ApprovalRiskLevel.readOnly || ApprovalRiskLevel.localWrite =>
          PermissionModeDecision.allowWithoutApproval,
        ApprovalRiskLevel.network ||
        ApprovalRiskLevel.shell ||
        ApprovalRiskLevel.destructive =>
          PermissionModeDecision.requireExplicitApproval,
      },
    };
  }

  static bool requiresExplicitApproval({
    required PermissionMode mode,
    required ApprovalRiskLevel riskLevel,
  }) {
    return decidePermission(mode: mode, riskLevel: riskLevel) ==
        PermissionModeDecision.requireExplicitApproval;
  }
}

ApprovalRiskLevel _classifyToolAction({
  required ToolKind? kind,
  required String? title,
  required List<ToolCallContent>? content,
  required List<ToolCallLocation>? locations,
  required Map<String, Object?>? rawInput,
  required Map<String, Object?>? rawOutput,
}) {
  var risk = _riskForKind(kind);
  for (final item in content ?? const <ToolCallContent>[]) {
    risk = ApprovalPolicy.max(risk, _riskForContent(item));
  }

  for (final value in [title, locations, rawInput, rawOutput]) {
    risk = ApprovalPolicy.max(risk, _riskForUntrustedValue(value));
  }

  return risk;
}

ApprovalRiskLevel _riskForKind(ToolKind? kind) {
  return switch (kind) {
    ToolKind.delete => ApprovalRiskLevel.destructive,
    ToolKind.edit || ToolKind.move => ApprovalRiskLevel.localWrite,
    ToolKind.execute => ApprovalRiskLevel.shell,
    ToolKind.fetch => ApprovalRiskLevel.network,
    ToolKind.read ||
    ToolKind.search ||
    ToolKind.think ||
    ToolKind.other ||
    null => ApprovalRiskLevel.readOnly,
  };
}

ApprovalRiskLevel _riskForContent(ToolCallContent content) {
  return switch (content) {
    ToolCallDiff(:final diff) => ApprovalPolicy.max(
      ApprovalRiskLevel.localWrite,
      _riskForUntrustedValue(diff.toJson()),
    ),
    ToolCallTerminal() => ApprovalRiskLevel.shell,
    ToolCallContentBlock(:final content) => _riskForUntrustedValue(
      content.toJson(),
    ),
  };
}

ApprovalRiskLevel _riskForUntrustedValue(Object? value) {
  if (value == null) {
    return ApprovalRiskLevel.readOnly;
  }
  if (value is String) {
    return _riskForString(value);
  }
  if (value is Map) {
    var risk = ApprovalRiskLevel.readOnly;
    for (final entry in value.entries) {
      risk = ApprovalPolicy.max(risk, _riskForUntrustedValue(entry.key));
      risk = ApprovalPolicy.max(risk, _riskForUntrustedValue(entry.value));
    }
    return risk;
  }
  if (value is Iterable) {
    var risk = ApprovalRiskLevel.readOnly;
    for (final item in value) {
      risk = ApprovalPolicy.max(risk, _riskForUntrustedValue(item));
    }
    return risk;
  }

  return ApprovalRiskLevel.readOnly;
}

ApprovalRiskLevel _riskForString(String value) {
  final text = value.toLowerCase();
  if (_containsAny(text, const [
    'rm -rf',
    'git reset',
    'git push --force',
    'force push',
    'drop database',
    'truncate table',
    'delete ',
    'delete_',
    'delete-',
    'remove ',
    'reset ',
    'migration',
    'migrate',
    'wipe',
    'erase',
    'destructive',
    'irreversible',
  ])) {
    return ApprovalRiskLevel.destructive;
  }
  if (_containsAny(text, const [
    'http://',
    'https://',
    'curl ',
    'wget ',
    'api.',
  ])) {
    return ApprovalRiskLevel.network;
  }
  if (_containsAny(text, const [
    'bash ',
    'sh ',
    'zsh ',
    'shell',
    'terminal',
    'command',
  ])) {
    return ApprovalRiskLevel.shell;
  }
  if (_containsAny(text, const [
    'write',
    'edit',
    'patch',
    'diff',
    'newtext',
    'oldtext',
  ])) {
    return ApprovalRiskLevel.localWrite;
  }

  return ApprovalRiskLevel.readOnly;
}

bool _containsAny(String value, List<String> needles) {
  return needles.any(value.contains);
}

int _rank(ApprovalRiskLevel risk) {
  return switch (risk) {
    ApprovalRiskLevel.readOnly => 0,
    ApprovalRiskLevel.localWrite => 1,
    ApprovalRiskLevel.network => 2,
    ApprovalRiskLevel.shell => 3,
    ApprovalRiskLevel.destructive => 4,
  };
}
