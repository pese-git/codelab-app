import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';

/// Риск действия, о котором агент спрашивает разрешения; его определяет
/// политика приложения, лента только показывает тег.
enum CodeLabApprovalRisk { readOnly, localWrite, network, shell, destructive }

/// Подпись и тон тега риска в шапке строки вызова (change
/// `lighten-approval-block`, D6).
extension CodeLabApprovalRiskTag on CodeLabApprovalRisk {
  String get label => switch (this) {
    CodeLabApprovalRisk.readOnly => 'Read-only',
    CodeLabApprovalRisk.localWrite => 'Local write',
    CodeLabApprovalRisk.network => 'Network',
    CodeLabApprovalRisk.shell => 'Shell',
    CodeLabApprovalRisk.destructive => 'Destructive',
  };

  CodeLabTone get tone => switch (this) {
    CodeLabApprovalRisk.readOnly => CodeLabTone.success,
    CodeLabApprovalRisk.localWrite => CodeLabTone.warning,
    CodeLabApprovalRisk.network => CodeLabTone.warning,
    CodeLabApprovalRisk.shell => CodeLabTone.danger,
    CodeLabApprovalRisk.destructive => CodeLabTone.danger,
  };
}

/// Охват решения: один раз или всегда.
enum _Scope { once, always }

/// Полоса решения ожидающего одобрения внизу строки вызова.
///
/// Почему: карточка одобрения повторяла команду и вид действия, а четыре
/// равноправные кнопки переносились во второй ряд (change
/// `lighten-approval-block`). Решение отделено от охвата, как в агентской
/// панели Zed (идея взаимодействия, не код; источник — design.md change):
/// частое действие — одна из двух кнопок, постоянный вариант — явный выбор
/// охвата.
///
/// Для чего: кнопки «Allow» и «Reject» и выбор охвата «Only this time» /
/// «Always»; кнопка отвечает вариантом агента по паре «решение × охват»
/// (design D3). Сочетания всех четырёх видов привязаны здесь и не зависят
/// от охвата (D2). «View raw input» — значок в полосе (D8). Команду полоса
/// не повторяет: она в шапке строки вызова.
///
/// Как использовать: `CodeLabToolCallTile` кладёт её в тело строки, пока
/// одобрение ждёт решения. [shortcutsEnabled] — одобрение в фокусе: только
/// у него действуют сочетания и видны подсказки. Охват — черновик решения в
/// `State` полосы: каждое новое одобрение начинается с охвата по умолчанию.
class CodeLabApprovalPrompt extends StatefulWidget {
  const CodeLabApprovalPrompt({
    required this.options,
    required this.onOptionSelected,
    this.reason,
    this.diffSummary,
    this.rawInput,
    this.enabled = true,
    this.approveOptionId,
    this.rejectOptionId,
    this.shortcutsEnabled = true,
    super.key,
  });

  static const allowKey = ValueKey('approval-allow');
  static const rejectKey = ValueKey('approval-reject');
  static const scopeKey = ValueKey('approval-scope');
  static const viewRawInputKey = ValueKey('approval-view-raw-input');
  static const rawInputKey = ValueKey('approval-raw-input');

  /// Подпись недоступной кнопки, когда у агента нет варианта для выбранного
  /// охвата.
  static const noSuchOption = 'The agent offers no such option';

  final List<CodeLabApprovalOption> options;
  final CodeLabApprovalOptionSelected onOptionSelected;
  final String? reason;
  final String? diffSummary;
  final String? rawInput;
  final bool enabled;
  final String? approveOptionId;
  final String? rejectOptionId;
  final bool shortcutsEnabled;

  @override
  State<CodeLabApprovalPrompt> createState() => _CodeLabApprovalPromptState();
}

class _CodeLabApprovalPromptState extends State<CodeLabApprovalPrompt> {
  /// Ширина, ниже которой решение и охват не помещаются в одну строку.
  static const _narrowWidth = 460.0;

  _Scope? _chosenScope;
  bool _rawInputShown = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final muted = theme.resources.textFillColorSecondary;
    final shortcuts = CodeLabApprovalShortcuts(
      widget.options,
      approveOptionId: widget.approveOptionId,
      rejectOptionId: widget.rejectOptionId,
    );
    final scopes = [
      if (shortcuts.allowOnceId != null || shortcuts.rejectOnceId != null)
        _Scope.once,
      if (shortcuts.allowAlwaysId != null || shortcuts.rejectAlwaysId != null)
        _Scope.always,
    ];
    // Выбор пользователя — только среди охватов, которые есть у агента.
    final scope = scopes.contains(_chosenScope)
        ? _chosenScope!
        : (scopes.firstOrNull ?? _Scope.once);
    final allowId = scope == _Scope.once
        ? shortcuts.allowOnceId
        : shortcuts.allowAlwaysId;
    final rejectId = scope == _Scope.once
        ? shortcuts.rejectOnceId
        : shortcuts.rejectAlwaysId;
    final rawInput = widget.rawInput;
    final reason = widget.reason;
    final diffSummary = widget.diffSummary;
    String? hint(String? optionId) =>
        widget.shortcutsEnabled && optionId != null
        ? shortcuts.labelFor(optionId)
        : null;

    final allow = _DecisionButton(
      key: CodeLabApprovalPrompt.allowKey,
      icon: FluentIcons.check_mark,
      tone: CodeLabTone.success,
      label: 'Allow',
      shortcut: hint(allowId),
      unavailable: allowId == null,
      onPressed: _onPressed(allowId),
    );
    final reject = _DecisionButton(
      key: CodeLabApprovalPrompt.rejectKey,
      icon: FluentIcons.cancel,
      tone: CodeLabTone.danger,
      label: 'Reject',
      shortcut: hint(rejectId),
      unavailable: rejectId == null,
      onPressed: _onPressed(rejectId),
    );
    final viewRawInput = rawInput == null
        ? null
        : Tooltip(
            message: _rawInputShown ? 'Hide raw input' : 'View raw input',
            child: Semantics(
              label: 'View raw input',
              child: IconButton(
                key: CodeLabApprovalPrompt.viewRawInputKey,
                icon: const Icon(FluentIcons.code, size: 14),
                onPressed: () =>
                    setState(() => _rawInputShown = !_rawInputShown),
              ),
            ),
          );
    final scopeSelector = _scopeSelector(context, scopes, scope);
    // Решение слева, охват справа; в узкой колонке (телефон) полоса
    // переносится, а не обрезается.
    final bar = LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < _narrowWidth
          ? Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [allow, reject, ?viewRawInput, scopeSelector],
            )
          : Row(
              children: [
                allow,
                const SizedBox(width: 4),
                reject,
                const Spacer(),
                ?viewRawInput,
                const SizedBox(width: 4),
                scopeSelector,
              ],
            ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reason != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: CodeLabText(
              reason,
              role: CodeLabTextRole.caption,
              color: muted,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (diffSummary != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: CodeLabText(
              diffSummary,
              role: CodeLabTextRole.caption,
              color: muted,
            ),
          ),
        if (rawInput != null && _rawInputShown)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: DecoratedBox(
              key: CodeLabApprovalPrompt.rawInputKey,
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.resources.cardStrokeColorDefault,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  rawInput,
                  style: CodeLabText.styleOf(context, CodeLabTextRole.mono),
                ),
              ),
            ),
          ),
        bar,
      ],
    );

    if (!widget.shortcutsEnabled) {
      return content;
    }
    return CallbackShortcuts(
      bindings: shortcuts.bindings(_select),
      child: Focus(autofocus: true, child: content),
    );
  }

  /// Выбор охвата справа: меню, если у агента оба охвата, иначе название
  /// единственного охвата без шеврона.
  Widget _scopeSelector(
    BuildContext context,
    List<_Scope> scopes,
    _Scope scope,
  ) {
    final muted = FluentTheme.of(context).resources.textFillColorSecondary;
    if (scopes.length < 2) {
      return Padding(
        key: CodeLabApprovalPrompt.scopeKey,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: CodeLabText(_scopeLabel(scope), color: muted),
      );
    }
    final alwaysNames = [
      for (final option in widget.options)
        if (option.kind == CodeLabApprovalOptionKind.allowAlways ||
            option.kind == CodeLabApprovalOptionKind.rejectAlways)
          option.label,
    ];
    return DropDownButton(
      key: CodeLabApprovalPrompt.scopeKey,
      title: CodeLabText(_scopeLabel(scope), color: muted),
      items: [
        MenuFlyoutItem(
          text: Text(_scopeLabel(_Scope.once)),
          selected: scope == _Scope.once,
          onPressed: () => setState(() => _chosenScope = _Scope.once),
        ),
        MenuFlyoutItem(
          // Подписи агента называют, что именно станет постоянным
          // («Always allow echo *»), — их видно до выбора (design D3).
          text: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_scopeLabel(_Scope.always)),
              for (final name in alwaysNames)
                CodeLabText(name, role: CodeLabTextRole.caption, color: muted),
            ],
          ),
          selected: scope == _Scope.always,
          onPressed: () => setState(() => _chosenScope = _Scope.always),
        ),
      ],
    );
  }

  static String _scopeLabel(_Scope scope) => switch (scope) {
    _Scope.once => 'Only this time',
    _Scope.always => 'Always',
  };

  VoidCallback? _onPressed(String? optionId) =>
      widget.enabled && optionId != null ? () => _select(optionId) : null;

  void _select(String optionId) {
    if (!widget.enabled) {
      return;
    }
    widget.onOptionSelected(optionId);
  }
}

/// Кнопка решения без заливки: цветной значок, подпись и подсказка
/// сочетания. Без варианта для охвата недоступна и объясняет почему.
class _DecisionButton extends StatelessWidget {
  const _DecisionButton({
    required this.icon,
    required this.tone,
    required this.label,
    required this.onPressed,
    this.shortcut,
    this.unavailable = false,
    super.key,
  });

  final IconData icon;
  final CodeLabTone tone;
  final String label;
  final String? shortcut;
  final VoidCallback? onPressed;

  /// У агента нет варианта для выбранного охвата — кнопка объясняет это
  /// подсказкой, а не просто серая.
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final shortcut = this.shortcut;
    final button = Button(
      onPressed: onPressed,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        // Без заливки и рамки, фон только под указателем: в полосе две
        // равные кнопки, ни одна не тянет на себя внимание.
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed)
              ? resources.subtleFillColorTertiary
              : states.contains(WidgetState.hovered)
              ? resources.subtleFillColorSecondary
              : resources.subtleFillColorTransparent,
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: onPressed == null ? 0.4 : 1,
            child: CodeLabIcon(icon, tone: tone, size: 12),
          ),
          const SizedBox(width: 6),
          Text(label),
          if (shortcut != null) ...[
            const SizedBox(width: 6),
            CodeLabText(
              shortcut,
              role: CodeLabTextRole.caption,
              color: resources.textFillColorTertiary,
            ),
          ],
        ],
      ),
    );
    if (!unavailable) {
      return button;
    }
    return Tooltip(message: CodeLabApprovalPrompt.noSuchOption, child: button);
  }
}
