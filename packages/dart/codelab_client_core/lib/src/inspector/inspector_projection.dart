import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../diagnostics/diagnostics.dart';

part 'inspector_projection.freezed.dart';

/// Раздел инспектора, к которому относится запись.
enum InspectorCategory { approval, toolCall, protocol, diagnostic }

/// Запись инспектора: что видно о последнем ходе сессии на уровне протокола.
@freezed
abstract class InspectorEntry with _$InspectorEntry {
  const factory InspectorEntry({
    required String id,
    required InspectorCategory category,
    required String title,
    required String summary,
    String? risk,
    String? status,
    @Default([]) List<InspectorDetail> details,

    /// Сырые аргументы и результат вызова — JSON после редакции секретов.
    String? rawInput,
    String? rawOutput,
  }) = _InspectorEntry;
}

/// Строка подробностей записи инспектора.
@freezed
abstract class InspectorDetail with _$InspectorDetail {
  const factory InspectorDetail({
    required String label,
    required String value,
  }) = _InspectorDetail;
}

/// Инспектор сессии: одобрения, вызовы инструментов, обновления и сам ход.
///
/// Почему: инспектор нужен и панели app, и команде CLI `/inspect` (этап 6);
/// раньше его строил `CodeLabShellCubit` (`_inspectorEntriesFor*`,
/// design D9 change `extract-acp-client-kit`).
///
/// Для чего: чистая проекция снимка `AcpSession` — для последнего хода
/// сессии или, пока ходов нет, одна запись о сессии. Сырые аргументы
/// проходят `SecretRedactor`.
///
/// Как использовать: `const InspectorProjection().project(session)` для
/// показываемой сессии; результат не кешируется — хост вызывает проекцию,
/// когда ему нужен инспектор.
final class InspectorProjection {
  const InspectorProjection();

  List<InspectorEntry> project(AcpSession session) {
    final turn = session.turns.lastOrNull;
    if (turn == null) {
      return [
        InspectorEntry(
          id: 'session-${session.id.value}',
          category: InspectorCategory.protocol,
          title: 'Session ${session.id.value}',
          summary: 'Status ${session.status.name}',
          details: [
            InspectorDetail(label: 'CWD', value: session.cwd),
            InspectorDetail(label: 'Status', value: session.status.name),
          ],
        ),
      ];
    }
    return [
      for (final approval in turn.approvals.values) _approvalEntry(approval),
      for (final toolCall in turn.toolCalls.values) _toolCallEntry(toolCall),
      for (final (index, update) in turn.updates.indexed)
        _updateEntry(update, index),
      InspectorEntry(
        id: 'turn-${turn.id.value}',
        category: InspectorCategory.protocol,
        title: 'Prompt turn ${turn.id.value}',
        summary: 'Status ${turn.status.name}',
        status: turn.stopReason?.wireName ?? turn.status.name,
        details: [
          InspectorDetail(label: 'Session', value: turn.sessionId.value),
          InspectorDetail(label: 'Status', value: turn.status.name),
          if (turn.stopReason case final stopReason?)
            InspectorDetail(label: 'Stop reason', value: stopReason.wireName),
          InspectorDetail(
            label: 'Updates',
            value: turn.updates.length.toString(),
          ),
        ],
      ),
    ];
  }

  InspectorEntry _approvalEntry(ApprovalRequest approval) {
    final toolCall = approval.toolCall;
    return InspectorEntry(
      id: 'approval-${approval.id.value}',
      category: InspectorCategory.approval,
      title: 'Approval ${approval.id.value}',
      summary: toolCall.title,
      risk: approval.riskLevel.name,
      status: approval.status.name,
      details: [
        InspectorDetail(label: 'Tool', value: toolCall.title),
        InspectorDetail(label: 'Kind', value: toolCall.kind.wireName),
        InspectorDetail(label: 'Status', value: approval.status.name),
        InspectorDetail(
          label: 'Options',
          value: approval.options
              .map((option) => '${option.name} (${option.kind.wireName})')
              .join(', '),
        ),
        ..._contentDetails(toolCall.content),
        ..._locationDetails(toolCall.locations),
      ],
      rawInput: formatRedactedJson(toolCall.rawInput),
      rawOutput: formatRedactedJson(toolCall.rawOutput),
    );
  }

  InspectorEntry _toolCallEntry(ToolCallRecord toolCall) => InspectorEntry(
    id: 'tool-${toolCall.id.value}',
    category: InspectorCategory.toolCall,
    title: toolCall.title,
    summary: toolCall.kind.wireName,
    risk: toolCall.riskLevel.name,
    status: toolCall.status.wireName,
    details: [
      InspectorDetail(label: 'Tool call', value: toolCall.id.value),
      InspectorDetail(label: 'Kind', value: toolCall.kind.wireName),
      InspectorDetail(label: 'Status', value: toolCall.status.wireName),
      ..._contentDetails(toolCall.content),
      ..._locationDetails(toolCall.locations),
    ],
    rawInput: formatRedactedJson(toolCall.rawInput),
    rawOutput: formatRedactedJson(toolCall.rawOutput),
  );

  InspectorEntry _updateEntry(SessionUpdate update, int index) {
    final id = 'update-$index';
    return switch (update) {
      UserMessageChunk(:final content) => _contentEntry(
        id,
        'session/update user_message_chunk',
        content,
      ),
      AgentMessageChunk(:final content) => _contentEntry(
        id,
        'session/update agent_message_chunk',
        content,
      ),
      AgentThoughtChunk(:final content) => _contentEntry(
        id,
        'session/update agent_thought_chunk',
        content,
      ),
      ToolCallSessionUpdate(:final toolCall) => InspectorEntry(
        id: id,
        category: InspectorCategory.protocol,
        title: 'session/update tool_call',
        summary: toolCall.title,
        details: [
          InspectorDetail(label: 'Tool call', value: toolCall.toolCallId.value),
          InspectorDetail(label: 'Kind', value: toolCall.kind.wireName),
          InspectorDetail(label: 'Status', value: toolCall.status.wireName),
          ..._contentDetails(toolCall.content ?? const []),
          ..._locationDetails(toolCall.locations ?? const []),
        ],
        rawInput: formatRedactedJson(toolCall.rawInput),
        rawOutput: formatRedactedJson(toolCall.rawOutput),
      ),
      ToolCallUpdateSessionUpdate(:final toolCallUpdate) => InspectorEntry(
        id: id,
        category: InspectorCategory.protocol,
        title: 'session/update tool_call_update',
        summary: toolCallUpdate.title ?? toolCallUpdate.toolCallId.value,
        details: [
          InspectorDetail(
            label: 'Tool call',
            value: toolCallUpdate.toolCallId.value,
          ),
          if (toolCallUpdate.kind case final kind?)
            InspectorDetail(label: 'Kind', value: kind.wireName),
          if (toolCallUpdate.status case final status?)
            InspectorDetail(label: 'Status', value: status.wireName),
          ..._contentDetails(toolCallUpdate.content ?? const []),
          ..._locationDetails(toolCallUpdate.locations ?? const []),
        ],
        rawInput: formatRedactedJson(toolCallUpdate.rawInput),
        rawOutput: formatRedactedJson(toolCallUpdate.rawOutput),
      ),
      PlanUpdate(:final entries) => InspectorEntry(
        id: id,
        category: InspectorCategory.protocol,
        title: 'session/update plan',
        summary: '${entries.length} entries',
        details: [
          for (final entry in entries)
            InspectorDetail(label: entry.status.wireName, value: entry.content),
        ],
      ),
      AvailableCommandsUpdate(:final availableCommands) => InspectorEntry(
        id: id,
        category: InspectorCategory.protocol,
        title: 'session/update available_commands_update',
        summary: '${availableCommands.length} commands',
      ),
      CurrentModeUpdate(:final currentModeId) => InspectorEntry(
        id: id,
        category: InspectorCategory.protocol,
        title: 'session/update current_mode_update',
        summary: currentModeId.value,
      ),
      ConfigOptionUpdate(:final configOptions) => InspectorEntry(
        id: id,
        category: InspectorCategory.protocol,
        title: 'session/update config_option_update',
        summary: '${configOptions.length} options',
      ),
      SessionInfoUpdate(:final title) => InspectorEntry(
        id: id,
        category: InspectorCategory.protocol,
        title: 'session/update session_info_update',
        summary: title ?? 'Session info updated',
      ),
    };
  }

  InspectorEntry _contentEntry(String id, String title, ContentBlock content) =>
      InspectorEntry(
        id: id,
        category: InspectorCategory.protocol,
        title: title,
        summary: _contentSummary(content),
      );

  List<InspectorDetail> _contentDetails(List<ToolCallContent> content) => [
    for (final item in content)
      switch (item) {
        ToolCallDiff(:final diff) => InspectorDetail(
          label: 'Diff',
          value: '${diff.path} (${diff.oldText == null ? 'new' : 'edit'})',
        ),
        ToolCallTerminal(:final terminalId) => InspectorDetail(
          label: 'Terminal',
          value: terminalId,
        ),
        ToolCallContentBlock(:final content) => InspectorDetail(
          label: 'Content',
          value: _contentSummary(content),
        ),
      },
  ];

  List<InspectorDetail> _locationDetails(List<ToolCallLocation> locations) => [
    for (final location in locations)
      InspectorDetail(
        label: 'Location',
        value: location.line == null
            ? location.path
            : '${location.path}:${location.line}',
      ),
  ];

  String _contentSummary(ContentBlock content) => switch (content) {
    TextContent(:final text) => text,
    ImageContent(:final mimeType) => 'Image $mimeType',
    AudioContent(:final mimeType) => 'Audio $mimeType',
    ResourceLink(:final uri) => uri,
    EmbeddedResource(:final resource) => formatRedactedJson(resource.toJson())!,
  };
}
