import 'shell_part.dart';

/// Resizable-panel width bounds — CodeLab-specific, not baked into the
/// reusable `codelab_ui` layout/handle primitives (see
/// openspec/changes/add-resizable-panels/design.md).
const kSessionsPaneMinWidth = 220.0;
const kSessionsPaneMaxWidth = 480.0;
const kInspectorPaneMinWidth = 260.0;
const kInspectorPaneMaxWidth = 520.0;

/// Раскладка окна: ширины панелей, открытая палитра, инспектор в узкой
/// раскладке.
final class LayoutState {
  const LayoutState({
    this.sessionsPaneWidth = 280,
    this.inspectorPaneWidth = 320,
    this.isCommandPaletteOpen = false,
    this.isInspectorVisibleInNarrowLayout = false,
  });

  /// Ширины, до которых пользователь перетащил разделители панелей сессий и
  /// инспектора; переживают перестройку виджетов в пределах запуска, между
  /// запусками не сохраняются (add-resizable-panels/design.md, Open
  /// Questions).
  final double sessionsPaneWidth;
  final double inspectorPaneWidth;
  final bool isCommandPaletteOpen;
  final bool isInspectorVisibleInNarrowLayout;

  LayoutState _copyWith({
    double? sessionsPaneWidth,
    double? inspectorPaneWidth,
    bool? isCommandPaletteOpen,
    bool? isInspectorVisibleInNarrowLayout,
  }) => LayoutState(
    sessionsPaneWidth: sessionsPaneWidth ?? this.sessionsPaneWidth,
    inspectorPaneWidth: inspectorPaneWidth ?? this.inspectorPaneWidth,
    isCommandPaletteOpen: isCommandPaletteOpen ?? this.isCommandPaletteOpen,
    isInspectorVisibleInNarrowLayout:
        isInspectorVisibleInNarrowLayout ??
        this.isInspectorVisibleInNarrowLayout,
  );
}

/// Презентационное состояние раскладки рабочего места.
///
/// Почему: ширины панелей и открытая палитра не касаются клиента ACP, поэтому
/// при переносе логики в kit остаются в app целиком (таблица переноса
/// `09-10`, строка «Панели»; design D10 change `extract-acp-client-kit`).
///
/// Для чего: единственный владелец раскладки; `CodeLabShellCubit` повторяет
/// его состояние в `CodeLabShellState`.
///
/// Как использовать: создаётся вместе с остальными частями
/// (`CodeLabShellParts`); методы вызывает фасад.
final class LayoutCubit extends ShellPartCubit<LayoutState> {
  LayoutCubit({required super.changes}) : super(const LayoutState());

  /// Принимает ширину панели сессий в конце перетаскивания
  /// (`AcpWorkbenchLayout.onSessionsPaneResizeEnd`) в пределах
  /// [kSessionsPaneMinWidth]–[kSessionsPaneMaxWidth].
  void resizeSessionsPane(double width) => emit(
    state._copyWith(
      sessionsPaneWidth: width.clamp(
        kSessionsPaneMinWidth,
        kSessionsPaneMaxWidth,
      ),
    ),
  );

  /// То же, что [resizeSessionsPane], для панели инспектора.
  void resizeInspectorPane(double width) => emit(
    state._copyWith(
      inspectorPaneWidth: width.clamp(
        kInspectorPaneMinWidth,
        kInspectorPaneMaxWidth,
      ),
    ),
  );

  void openCommandPalette() =>
      emit(state._copyWith(isCommandPaletteOpen: true));

  void closeCommandPalette() =>
      emit(state._copyWith(isCommandPaletteOpen: false));

  /// Показывает инспектор в узкой раскладке (команда палитры `/logs`).
  void showInspectorInNarrowLayout() =>
      emit(state._copyWith(isInspectorVisibleInNarrowLayout: true));
}
