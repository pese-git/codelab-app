import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';

/// Сочетания клавиш рабочего места: палитра, новая сессия, настройки, сайдбар,
/// панель Files, переход к одобрению и Esc отмены хода.
///
/// Почему: активаторы берутся из каталога [CodeLabShortcut], а не объявляются
/// здесь литералами, иначе страница «Keyboard» разошлась бы с привязками
/// (change `add-app-keyboard-page`, D3). Alt+←/→ зарезервированы за инспектором
/// (DSK-18), но не привязаны (решение пользователя Q2).
///
/// Сочетания ответа на одобрение (`onAnswerApproval`, change
/// `fix-approval-focus`, D14) привязаны здесь, а не к полосе: они действуют с
/// любого элемента рабочего места, включая композер.
///
/// Как использовать: хост передаёт колбэки только для доступных действий;
/// без колбэка сочетание не привязано.
class CodeLabWorkbenchShortcuts extends StatefulWidget {
  const CodeLabWorkbenchShortcuts({
    required this.child,
    this.onOpenCommandPalette,
    this.onCancel,
    this.onNewSession,
    this.onToggleSidebar,
    this.onOpenSettings,
    this.onToggleFiles,
    this.onGoToApproval,
    this.onAnswerApproval,
    this.enabled = true,
    this.clock,
    super.key,
  });

  final Widget child;

  /// Cmd/Ctrl+K — открыть палитру команд.
  final VoidCallback? onOpenCommandPalette;

  /// Esc — отменить идущий ход (и закрыть палитру, как решает хост).
  final VoidCallback? onCancel;

  /// Cmd/Ctrl+N — новая сессия (A13, шаг 3; change
  /// `redesign-workbench-shell`).
  final VoidCallback? onNewSession;

  /// Cmd/Ctrl+B — свернуть или развернуть сайдбар; что именно, решает хост
  /// по классу раскладки.
  final VoidCallback? onToggleSidebar;

  /// Cmd/Ctrl+, — открыть настройки (spec app-settings «Переход в настройки
  /// и обратно», DSK-24; change `add-app-settings-shell`). Что именно
  /// открывается, решает хост; на экране настроек сочетание не привязывают.
  final VoidCallback? onOpenSettings;

  /// Cmd/Ctrl+Shift+E — открыть или закрыть панель Files (A13, шаг 3; spec
  /// workspace-file-browser «Панель Files в доке инструментов»). Хост
  /// передаёт колбэк, только когда панель доступна; без колбэка сочетание не
  /// привязано (Cmd/Ctrl+` терминала — другое сочетание).
  final VoidCallback? onToggleFiles;

  /// Cmd/Ctrl+Shift+A — перейти к ожидающему одобрению (change
  /// `fix-approval-focus`, D3, D4). Хост передаёт колбэк всегда, а наличие
  /// цели проверяет при нажатии: иначе привязка появлялась бы и пропадала с
  /// каждым снимком состояния, и нажатие между снимком и перестроением
  /// терялось бы. Колбэк только прокручивает и ставит фокус на полосу, ответа
  /// не отправляет (AGENTS.md §10).
  final VoidCallback? onGoToApproval;

  /// Сочетания ответа на активное одобрение: ⌘Y, ⌥⌘Y, ⌥⌘Z, ⌥⇧⌘Z на macOS и
  /// Alt+Shift+Y, Q, X, W на остальных ОС (change `fix-approval-focus`,
  /// D14, D15). Колбэк получает вид варианта; вариант, цель, видимость и
  /// задержку после появления решает хост (AGENTS.md §10), кит только
  /// сообщает нажатие. Автоповтор не вызывает колбэк (`includeRepeats:
  /// false`): одно нажатие — не больше одного ответа. Клавиши зависят от
  /// платформы (`CodeLabShortcut.combosFor`, D15).
  ///
  /// Второй аргумент — сколько Alt и Shift зажаты вместе к моменту нажатия
  /// буквы (`CodeLabModifierHoldTracker`); на macOS (⌘) он `null` — условие
  /// не применяется. На Windows и Linux Alt+Shift — ещё и смена раскладки,
  /// поэтому хост не отвечает, если модификаторы зажаты недавно (решение
  /// пользователя 2026-11-20; порог — политика хоста).
  final void Function(
    CodeLabApprovalOptionKind kind,
    Duration? modifiersHeldFor,
  )?
  onAnswerApproval;
  final bool enabled;

  /// Часы отсчёта зажатых модификаторов; без них — `DateTime.now`. Шов тестов
  /// и хоста: одни и те же часы двигают отсчёт задержек хоста.
  ///
  /// Функция должна быть стабильной: смена идентичности пересоздаёт трекер и
  /// обнуляет отсчёт (безопасная сторона, но на Windows и Linux ответа не
  /// будет, пока Alt и Shift не зажаты заново).
  final DateTime Function()? clock;

  /// Запись каталога и вид варианта, на который она отвечает (D14).
  static const _answerKinds = [
    (CodeLabShortcut.allowOnce, CodeLabApprovalOptionKind.allowOnce),
    (CodeLabShortcut.allowAlways, CodeLabApprovalOptionKind.allowAlways),
    (CodeLabShortcut.rejectOnce, CodeLabApprovalOptionKind.rejectOnce),
    (CodeLabShortcut.rejectAlways, CodeLabApprovalOptionKind.rejectAlways),
  ];

  @override
  State<CodeLabWorkbenchShortcuts> createState() =>
      _CodeLabWorkbenchShortcutsState();
}

class _CodeLabWorkbenchShortcutsState extends State<CodeLabWorkbenchShortcuts> {
  late CodeLabModifierHoldTracker _hold;

  @override
  void initState() {
    super.initState();
    _hold = CodeLabModifierHoldTracker(clock: widget.clock)..attach();
  }

  @override
  void didUpdateWidget(CodeLabWorkbenchShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clock != widget.clock) {
      _hold.detach();
      _hold = CodeLabModifierHoldTracker(clock: widget.clock)..attach();
    }
  }

  @override
  void dispose() {
    _hold.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onOpenCommandPalette = widget.onOpenCommandPalette;
    final onCancel = widget.onCancel;
    final onNewSession = widget.onNewSession;
    final onToggleSidebar = widget.onToggleSidebar;
    final onOpenSettings = widget.onOpenSettings;
    final onToggleFiles = widget.onToggleFiles;
    final onGoToApproval = widget.onGoToApproval;
    final onAnswerApproval = widget.onAnswerApproval;
    if (!widget.enabled) {
      return widget.child;
    }

    final bindings = <ShortcutActivator, VoidCallback>{
      if (onOpenCommandPalette != null)
        ...CodeLabShortcut.commandPalette.bind(onOpenCommandPalette),
      if (onCancel != null) ...CodeLabShortcut.cancelTurn.bind(onCancel),
      if (onNewSession != null)
        ...CodeLabShortcut.newSession.bind(onNewSession),
      if (onToggleSidebar != null)
        ...CodeLabShortcut.toggleSidebar.bind(onToggleSidebar),
      if (onOpenSettings != null)
        ...CodeLabShortcut.openSettings.bind(onOpenSettings),
      if (onToggleFiles != null)
        ...CodeLabShortcut.toggleFiles.bind(onToggleFiles),
      if (onGoToApproval != null)
        ...CodeLabShortcut.goToApproval.bind(onGoToApproval),
      if (onAnswerApproval != null)
        for (final (shortcut, kind) in CodeLabWorkbenchShortcuts._answerKinds)
          ...shortcut.bind(
            () => onAnswerApproval(
              kind,
              // ⌘ на macOS смену раскладки не вызывает: условия «зажаты
              // заранее» там нет.
              defaultTargetPlatform == TargetPlatform.macOS
                  ? null
                  : _hold.heldFor,
            ),
            includeRepeats: false,
          ),
    };

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(autofocus: true, child: widget.child),
    );
  }
}
