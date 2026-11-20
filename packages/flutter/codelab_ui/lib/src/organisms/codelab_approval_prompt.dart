import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../l10n/codelab_localizations.dart';
import '../l10n/strings.dart';
import '../molecules/molecules.dart';

/// Риск действия, о котором агент спрашивает разрешения; его определяет
/// политика приложения, лента только показывает тег.
///
/// [unknown] — уровень риска вызова не определён: `other`, вида нет (например
/// MCP-инструмент), смена режима (`switch_mode`) или незнакомый вид, который
/// агент прислал сверх известных клиенту: такой вызов не помечается «только
/// чтение» (design.md change `add-provider-setup-ui`, D27, Q32; change
/// `tolerate-unknown-tool-kind`, D5).
enum CodeLabApprovalRisk {
  readOnly,
  unknown,
  localWrite,
  network,
  shell,
  destructive,
}

/// Подпись и тон тега риска в шапке строки вызова (change
/// `lighten-approval-block`, D6).
///
/// Подпись — пара «риск — текст» внутри кита (D4): на экране её показывает
/// [labelOf] на языке интерфейса, а [label] — английский эталон из
/// спецификаций без контекста (тесты, диагностика). Метка security (D14):
/// перевод не смягчает смысл риска.
extension CodeLabApprovalRiskTag on CodeLabApprovalRisk {
  /// Английская подпись без контекста; в UI используется [labelOf].
  ///
  /// Независимый switch по литералам, а не чтение каталога: это эталон
  /// спецификаций, с которым `codelab_l10n_en_reference_test.dart` сверяет
  /// английский каталог. Читай он каталог, тест был бы тавтологией.
  String get label => switch (this) {
    CodeLabApprovalRisk.readOnly => 'Read-only',
    CodeLabApprovalRisk.unknown => 'Unknown risk',
    CodeLabApprovalRisk.localWrite => 'Local write',
    CodeLabApprovalRisk.network => 'Network',
    CodeLabApprovalRisk.shell => 'Shell',
    CodeLabApprovalRisk.destructive => 'Destructive',
  };

  /// Подпись риска на языке интерфейса; без делегата кита — английская.
  String labelOf(BuildContext context) => _labelIn(codeLabStringsOf(context));

  String _labelIn(CodeLabLocalizations strings) => switch (this) {
    CodeLabApprovalRisk.readOnly => strings.codeLabRiskReadOnly,
    CodeLabApprovalRisk.unknown => strings.codeLabRiskUnknown,
    CodeLabApprovalRisk.localWrite => strings.codeLabRiskLocalWrite,
    CodeLabApprovalRisk.network => strings.codeLabRiskNetwork,
    CodeLabApprovalRisk.shell => strings.codeLabRiskShell,
    CodeLabApprovalRisk.destructive => strings.codeLabRiskDestructive,
  };

  CodeLabTone get tone => switch (this) {
    CodeLabApprovalRisk.readOnly => CodeLabTone.success,
    CodeLabApprovalRisk.unknown => CodeLabTone.warning,
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
/// (design D3). Кнопки активного одобрения показывают сочетания ответа по
/// платформе; привязаны они на рабочем месте и не зависят от охвата (D14).
/// «View raw input» — значок в полосе (D8). Команду полоса
/// не повторяет: она в шапке строки вызова.
///
/// Как использовать: `CodeLabToolCallTile` кладёт её в тело строки, пока
/// одобрение ждёт решения. [shortcutsEnabled] — активное одобрение (признак
/// модели `focused`), не клавиатурный фокус: только у него действуют
/// сочетания и видны подсказки. Охват — черновик решения в `State` полосы:
/// каждое новое одобрение начинается с охвата по умолчанию.
///
/// Фокус: полоса НЕ берёт клавиатурный фокус сама (change
/// `fix-approval-focus`, D1, D2). Прежний `Focus(autofocus: true)` ловил
/// фокус, когда он был потерян (клик по пустой ленте, закрытая палитра), и
/// Cmd/Ctrl+Enter отвечал `allow_once` на запрос разрешения без явного
/// действия пользователя (AGENTS.md §10). Итерация 7 убрала и локальные
/// сочетания: ответ с клавиатуры даёт только рабочее место
/// (`CodeLabWorkbenchShortcuts.onAnswerApproval`, D14), а у активного
/// одобрения кнопки показывают его клавиши.
///
/// Переход и вид: к полосе фокус приходит Tab или сочетанием «Go to
/// approval» (лента ставит фокус на её узел, см. [barKey] и
/// `CodeLabTranscriptShowRequest.focusApproval`, D4). Узел полосы с
/// `skipTraversal`: Tab идёт сразу к кнопкам, а Enter и Space на самой полосе
/// ничего не выбирают. Пока фокус в полосе, видна рамка [focusFrameKey]
/// цветами темы; для чтения с экрана полоса — контейнер `Awaiting approval` с
/// перечнем сочетаний словами. Отдельной подсказки перехода нет (D14).
/// Ключ полосы (`ValueKey` по id запроса) задаёт хост: новый запрос даёт новый
/// `State` и новый узел, фокус к нему не переносится.
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
    this.onApprovalFocusReleased,
    super.key,
  });

  static const allowKey = ValueKey('approval-allow');
  static const rejectKey = ValueKey('approval-reject');
  static const scopeKey = ValueKey('approval-scope');
  static const viewRawInputKey = ValueKey('approval-view-raw-input');
  static const rawInputKey = ValueKey('approval-raw-input');

  /// Ключ содержимого полосы внутри её `Focus`: `Focus.of(element)` даёт узел
  /// полосы, и лента ставит на него фокус при переходе «Go to approval»
  /// (change `fix-approval-focus`, D4). Служит и тестам, и автоматизации.
  static const barKey = ValueKey('approval-bar');

  /// Ключ полосы по сессии и id запроса.
  ///
  /// Почему: новый запрос того же вызова на том же месте ленты должен получить
  /// новый `State` полосы, а значит и новый узел фокуса: фокус прежнего
  /// запроса на него не переносится, и каждое одобрение начинает с охвата по
  /// умолчанию (change `fix-approval-focus`, D4, п. 4). Id JSON-RPC уникальны
  /// только в пределах соединения, поэтому в ключ входит и сессия.
  ///
  /// Для чего: по этому ключу лента находит полосу именно выбранного запроса
  /// при «Go to approval» и не ставит фокус на чужую (D13).
  static Key keyFor(String sessionId, String approvalId) =>
      ValueKey('approval-prompt-$sessionId-$approvalId');

  /// Ключ рамки фокуса: рамка есть, пока фокус на полосе или внутри неё
  /// (D4, п. 3).
  static const focusFrameKey = ValueKey('approval-focus-frame');

  /// Английский эталон подсказки недоступной кнопки, когда у агента нет
  /// варианта для выбранного охвата.
  ///
  /// Почему константа осталась: на неё ссылаются тесты и спецификации. На
  /// экране текст берётся из каталога (`codeLabApprovalNoSuchOption`, метка
  /// security, D14) и в `en` совпадает с этой константой; расхождение ловит
  /// `codelab_l10n_en_reference_test.dart`.
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

  /// Полоса с клавиатурным фокусом уходит (`dispose` или смена ключа):
  /// хост возвращает фокус в композер (change `fix-approval-focus`, D5).
  ///
  /// Почему: когда полоса с фокусом исчезает, Flutter отдаёт фокус ближайшей
  /// области или никому, и пользователь теряет место на клавиатуре. Полоса
  /// знает, что фокус был у неё, а выбрать, куда его вернуть, может только
  /// хост (композер, иначе рабочее место).
  ///
  /// Как использовать: вызывается синхронно из `dispose` и ровно один раз;
  /// хост не должен трогать дерево сразу. Если Flutter отдал фокус внутрь
  /// другой полосы одобрения, хост переводит его сразу (в микротаске), иначе
  /// переносит в следующем кадре и только если за это время пользователь не
  /// перевёл фокус сам (D5, §12). Полоса без фокуса колбэк не вызывает.
  final VoidCallback? onApprovalFocusReleased;

  @override
  State<CodeLabApprovalPrompt> createState() => _CodeLabApprovalPromptState();
}

class _CodeLabApprovalPromptState extends State<CodeLabApprovalPrompt> {
  /// Ширина, ниже которой решение и охват не помещаются в одну строку.
  static const _narrowWidth = 460.0;

  _Scope? _chosenScope;
  bool _rawInputShown = false;

  /// Узел фокуса самой полосы (D4, п. 3). Принадлежит `State`: новый запрос
  /// даёт новый `State` (ключ полосы — id запроса) и новый узел, поэтому фокус
  /// к другому запросу не переносится. `skipTraversal`: Tab идёт сразу к
  /// кнопкам, лишней остановки нет, а программный `requestFocus` работает.
  late final FocusNode _barNode = FocusNode(
    debugLabel: 'approval-bar',
    skipTraversal: true,
  );

  /// Фокус на полосе или внутри неё: от него зависят рамка и подсказка
  /// перехода. Это отображение, а не источник истины о сессии (§8).
  bool _hasFocus = false;

  /// Фокус был на полосе или внутри неё в момент, когда её убирают из дерева.
  /// Запоминается в `deactivate`: к `dispose` узел детей уже отсоединён и
  /// `hasFocus` ложен (дети освобождаются раньше родителя).
  bool _hadFocusOnLeave = false;

  @override
  void deactivate() {
    _hadFocusOnLeave = _barNode.hasFocus;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _hadFocusOnLeave = false;
  }

  @override
  void didUpdateWidget(CodeLabApprovalPrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Пока идёт ответ на другое одобрение, хост гасит кнопки всех полос
    // (`enabled: false`, защита от двойного ответа). Выключенная кнопка
    // теряет фокус, и пользователь, который сам довёл фокус до этой полосы,
    // оказался бы без фокуса, когда ответ придёт. Поэтому фокус внутри полосы
    // переходит на неё саму: он остаётся в полосе, а выбор вариантов
    // по-прежнему только по явному действию (design.md, D4, п. 4).
    if (oldWidget.enabled &&
        !widget.enabled &&
        _barNode.hasFocus &&
        !_barNode.hasPrimaryFocus) {
      _barNode.requestFocus();
    }
  }

  @override
  void dispose() {
    if (_hadFocusOnLeave) {
      widget.onApprovalFocusReleased?.call();
    }
    _barNode.dispose();
    super.dispose();
  }

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

    final strings = codeLabStringsOf(context);
    final allow = _DecisionButton(
      key: CodeLabApprovalPrompt.allowKey,
      icon: FluentIcons.check_mark,
      tone: CodeLabTone.success,
      label: strings.codeLabApprovalAllow,
      shortcut: hint(allowId),
      unavailable: allowId == null,
      onPressed: _onPressed(allowId),
    );
    final reject = _DecisionButton(
      key: CodeLabApprovalPrompt.rejectKey,
      icon: FluentIcons.cancel,
      tone: CodeLabTone.danger,
      label: strings.codeLabApprovalReject,
      shortcut: hint(rejectId),
      unavailable: rejectId == null,
      onPressed: _onPressed(rejectId),
    );
    final viewRawInput = rawInput == null
        ? null
        : Tooltip(
            message: _rawInputShown
                ? strings.codeLabApprovalHideRawInput
                : strings.codeLabApprovalViewRawInput,
            child: Semantics(
              label: strings.codeLabApprovalViewRawInput,
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
          // Кнопки решения стоят в `Wrap` внутри `Expanded`: подписи на русском
          // длиннее английских (`add-desktop-localization`, D8, R4), и ряд из
          // двух кнопок и правой группы на ширине ленты 696 px переполнялся на
          // 16 px. Теперь при нехватке места «Reject» переносится на вторую
          // строку, подписи не обрезаются, порядок и привязка решений те же.
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [allow, reject],
                    ),
                  ),
                ),
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

    // Структура одна и та же у активного и неактивного одобрения: когда
    // `shortcutsEnabled` меняется (раннее решено, и это одобрение стало
    // активным), кнопки не пересоздаются, и фокус, который пользователь сам
    // поставил на них клавишей Tab, не теряется (design.md, D4, п. 4). От
    // `shortcutsEnabled` зависят только подсказки клавиш и подпись для чтения
    // с экрана. Своих привязок у полосы нет: ответ с клавиатуры даёт только
    // рабочее место (`CodeLabWorkbenchShortcuts.onAnswerApproval`, D14).
    //
    // Без `autofocus`: полоса не берёт фокус сама (`fix-approval-focus`, D1).
    return Focus(
      focusNode: _barNode,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (mounted && focused != _hasFocus) {
          setState(() => _hasFocus = focused);
        }
      },
      // Для чтения с экрана полоса — контейнер: название и перечень
      // сочетаний словами (`spokenFor`), без символов клавиш (D4, п. 5).
      //
      // `explicitChildNodes`: без него подписи кнопок и подсказок сливаются в
      // подпись контейнера, и «Awaiting approval» теряется среди них.
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        focusable: true,
        focused: _hasFocus,
        label: strings.codeLabApprovalAwaiting,
        hint: widget.shortcutsEnabled ? _spokenShortcuts(shortcuts) : null,
        // Рамка — наложение поверх содержимого, а не обёртка вокруг него:
        // содержимое остаётся на месте в дереве, пока рамка появляется и
        // исчезает.
        child: Stack(
          children: [
            KeyedSubtree(key: CodeLabApprovalPrompt.barKey, child: content),
            if (_hasFocus)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: CodeLabApprovalPrompt.focusFrameKey,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.resources.focusStrokeColorOuter,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// «Название варианта: клавиши словами» для каждого варианта с сочетанием.
  /// Название — текст агента и не переводится.
  String _spokenShortcuts(CodeLabApprovalShortcuts shortcuts) {
    final parts = <String>[];
    for (final option in widget.options) {
      final spoken = shortcuts.spokenFor(option.id);
      if (spoken != null) {
        parts.add('${option.label}: $spoken');
      }
    }
    return parts.join('; ');
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
        child: CodeLabText(_scopeLabel(context, scope), color: muted),
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
      title: CodeLabText(_scopeLabel(context, scope), color: muted),
      items: [
        MenuFlyoutItem(
          text: Text(_scopeLabel(context, _Scope.once)),
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
              Text(_scopeLabel(context, _Scope.always)),
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

  static String _scopeLabel(BuildContext context, _Scope scope) {
    final strings = codeLabStringsOf(context);
    return switch (scope) {
      _Scope.once => strings.codeLabApprovalScopeOnce,
      _Scope.always => strings.codeLabApprovalScopeAlways,
    };
  }

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
    return Tooltip(
      message: codeLabStringsOf(context).codeLabApprovalNoSuchOption,
      child: button,
    );
  }
}
