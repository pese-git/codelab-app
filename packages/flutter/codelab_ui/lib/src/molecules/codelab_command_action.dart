import 'package:fluent_ui/fluent_ui.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'codelab_command_action.freezed.dart';

/// Where an [CodeLabCommandAction] came from — used by the command palette only
/// to render visually separate sections; it does not affect filtering.
enum CodeLabCommandSource { client, agent }

/// Поиск команд палитры по запросу пользователя; результат — в порядке
/// важности.
///
/// Почему: правила отбора (конфликты имён, нечёткий поиск) живут в kit
/// (`CommandCatalog`), а не в виджете (change
/// `add-command-palette-agent-commands`, D5).
///
/// Как использовать: app передаёт функцию в
/// `CodeLabCommandPaletteSurface.search` и `CodeLabPromptComposer.search`;
/// [query] — текст поля поиска или фрагмент `/word` композера как есть.
typedef CodeLabCommandSearch =
    List<CodeLabCommandAction> Function(String query);

@freezed
sealed class CodeLabCommandAction with _$CodeLabCommandAction {
  const CodeLabCommandAction._();

  const factory CodeLabCommandAction({
    required String id,
    required String label,
    required String slashCommand,
    required String description,
    required IconData icon,
    @Default(CodeLabCommandSource.client) CodeLabCommandSource source,

    /// Whether selecting this command performs a real action. `false`
    /// renders the command as disabled/"coming soon" instead of a silent
    /// no-op.
    @Default(true) bool isAvailable,

    /// The agent-declared `AvailableCommandInput.hint`, if any. Shown as a
    /// placeholder in the composer right after this command's `/{name} `
    /// is inserted — never part of `description` or the submitted prompt
    /// text itself.
    String? hint,
  }) = _AcpCommandAction;

  static const List<CodeLabCommandAction> defaults = [
    CodeLabCommandAction(
      id: 'new',
      label: 'New session',
      slashCommand: '/new',
      description: 'Start a fresh ACP session.',
      icon: FluentIcons.add,
    ),
    CodeLabCommandAction(
      id: 'plan',
      label: 'Plan mode',
      slashCommand: '/plan',
      description: 'Switch the prompt turn into planning.',
      icon: FluentIcons.plan_view,
      isAvailable: false,
    ),
    CodeLabCommandAction(
      id: 'permissions',
      label: 'Permissions',
      slashCommand: '/permissions',
      description: 'Open permission mode controls.',
      icon: FluentIcons.permissions,
      isAvailable: false,
    ),
    CodeLabCommandAction(
      id: 'logs',
      label: 'Logs',
      slashCommand: '/logs',
      description: 'Open protocol and diagnostic logs.',
      icon: FluentIcons.command_prompt,
    ),
    CodeLabCommandAction(
      id: 'compact',
      label: 'Compact transcript',
      slashCommand: '/compact',
      description: 'Prepare the transcript for compaction.',
      icon: FluentIcons.view_list,
      isAvailable: false,
    ),
    CodeLabCommandAction(
      id: 'reconnect',
      label: 'Reconnect',
      slashCommand: '/reconnect',
      description: 'Retry the current agent connection.',
      icon: FluentIcons.refresh,
    ),
  ];

  static List<CodeLabCommandAction> filter(
    Iterable<CodeLabCommandAction> actions,
    String query,
  ) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty || normalizedQuery == '/') {
      return List.unmodifiable(actions);
    }

    return List.unmodifiable(
      actions.where((action) {
        final normalizedSlashCommand = action.slashCommand.toLowerCase();
        final normalizedLabel = action.label.toLowerCase();
        final normalizedDescription = action.description.toLowerCase();

        return normalizedSlashCommand.contains(normalizedQuery) ||
            normalizedLabel.contains(normalizedQuery.replaceFirst('/', '')) ||
            normalizedDescription.contains(
              normalizedQuery.replaceFirst('/', ''),
            );
      }),
    );
  }
}
