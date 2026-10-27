import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart'
    show DiagnosticSeverity;
import 'package:codelab_ui/codelab_ui.dart' show ToolPane;

import '../../../core/platform/dock_layout_store.dart';
import 'shell_part.dart';

/// Resizable-panel width bounds — CodeLab-specific, not baked into the
/// reusable `codelab_ui` layout/handle primitives (see
/// openspec/changes/add-resizable-panels/design.md).
const kSessionsPaneMinWidth = 220.0;
const kSessionsPaneMaxWidth = 480.0;

/// Границы ширины дока панелей инструментов (change
/// `redesign-workbench-shell`, D5).
const kDockMinWidth = 280.0;
const kDockMaxWidth = 560.0;
const kDockDefaultWidth = 360.0;

/// Раскладка окна: сайдбар, док панелей инструментов, открытая палитра.
final class LayoutState {
  const LayoutState({
    this.sessionsPaneWidth = 280,
    this.dockWidth = kDockDefaultWidth,
    this.isCommandPaletteOpen = false,
    this.sidebarCollapsed = false,
    this.sidebarOverlayOpen = false,
    this.openPanes = const [],
    this.activePane,
    this.dockOverlayOpen = false,
  });

  /// Ширина сайдбара; переживает перестройку виджетов в пределах запуска
  /// (add-resizable-panels/design.md).
  final double sessionsPaneWidth;

  /// Ширина дока; сохраняется между запусками ([DockLayoutStore]).
  final double dockWidth;
  final bool isCommandPaletteOpen;

  /// Сайдбар свёрнут в иконки (Cmd/Ctrl+B в среднем и широком классах).
  final bool sidebarCollapsed;

  /// Сайдбар выдвинут поверх контента (узкие классы).
  final bool sidebarOverlayOpen;

  /// Открытые панели дока в порядке открытия; пусто — дока нет.
  final List<ToolPane> openPanes;
  final ToolPane? activePane;

  /// Док выдвинут поверх ленты (классы уже широкого).
  final bool dockOverlayOpen;

  static const Object _unset = Object();

  LayoutState _copyWith({
    double? sessionsPaneWidth,
    double? dockWidth,
    bool? isCommandPaletteOpen,
    bool? sidebarCollapsed,
    bool? sidebarOverlayOpen,
    List<ToolPane>? openPanes,
    Object? activePane = _unset,
    bool? dockOverlayOpen,
  }) => LayoutState(
    sessionsPaneWidth: sessionsPaneWidth ?? this.sessionsPaneWidth,
    dockWidth: dockWidth ?? this.dockWidth,
    isCommandPaletteOpen: isCommandPaletteOpen ?? this.isCommandPaletteOpen,
    sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
    sidebarOverlayOpen: sidebarOverlayOpen ?? this.sidebarOverlayOpen,
    openPanes: openPanes ?? this.openPanes,
    // `null` здесь — «активной панели нет», а не «не менять».
    activePane: identical(activePane, _unset)
        ? this.activePane
        : activePane as ToolPane?,
    dockOverlayOpen: dockOverlayOpen ?? this.dockOverlayOpen,
  );
}

/// Презентационное состояние раскладки рабочего места.
///
/// Почему: ширины, сайдбар, док и открытая палитра не касаются клиента ACP,
/// поэтому остаются в app (таблица переноса `09-10`, строка «Панели»;
/// design D10 change `extract-acp-client-kit`). `NavigationCubit` из A13 не
/// вводится, пока экран один: состояние каркаса живёт здесь (change
/// `redesign-workbench-shell`, D1).
///
/// Для чего: единственный владелец раскладки; `CodeLabShellCubit` повторяет
/// его состояние в `CodeLabShellState`. Раскладку дока сохраняет в
/// [DockLayoutStore], если он передан.
///
/// Как использовать: создаётся вместе с остальными частями
/// (`CodeLabShellParts`); методы вызывает фасад. Что делает Cmd/Ctrl+B —
/// сворачивает сайдбар ([toggleSidebarCollapsed]) или выдвигает его
/// ([toggleSidebarOverlay]) — решает представление по классу раскладки.
final class LayoutCubit extends ShellPartCubit<LayoutState> {
  LayoutCubit({
    required super.changes,
    DockLayoutStore? dockLayoutStore,
    ShellDiagnostics? diagnostics,
  }) : _store = dockLayoutStore,
       _diagnostics = diagnostics,
       super(const LayoutState()) {
    if (dockLayoutStore != null) {
      unawaited(_restore());
    }
  }

  final DockLayoutStore? _store;
  final ShellDiagnostics? _diagnostics;

  /// Принимает ширину сайдбара в конце перетаскивания в пределах
  /// [kSessionsPaneMinWidth]–[kSessionsPaneMaxWidth].
  void resizeSessionsPane(double width) => emit(
    state._copyWith(
      sessionsPaneWidth: width.clamp(
        kSessionsPaneMinWidth,
        kSessionsPaneMaxWidth,
      ),
    ),
  );

  /// Принимает ширину дока в конце перетаскивания в пределах
  /// [kDockMinWidth]–[kDockMaxWidth].
  void resizeDock(double width) {
    emit(state._copyWith(dockWidth: width.clamp(kDockMinWidth, kDockMaxWidth)));
    _persist();
  }

  void openCommandPalette() =>
      emit(state._copyWith(isCommandPaletteOpen: true));

  void closeCommandPalette() =>
      emit(state._copyWith(isCommandPaletteOpen: false));

  void toggleSidebarCollapsed() =>
      emit(state._copyWith(sidebarCollapsed: !state.sidebarCollapsed));

  void toggleSidebarOverlay() =>
      emit(state._copyWith(sidebarOverlayOpen: !state.sidebarOverlayOpen));

  void closeSidebarOverlay() =>
      emit(state._copyWith(sidebarOverlayOpen: false));

  /// Переключатель панели в app bar: активная панель закрывается, иначе
  /// панель открывается (если ещё не открыта), становится активной и
  /// выдвигает док в узких классах.
  void togglePane(ToolPane pane) {
    if (state.activePane == pane && state.openPanes.contains(pane)) {
      closePane(pane);
      return;
    }
    openPane(pane);
  }

  /// Открывает и активирует панель — например, Protocol по `/logs`.
  void openPane(ToolPane pane) {
    emit(
      state._copyWith(
        openPanes: state.openPanes.contains(pane)
            ? state.openPanes
            : List.unmodifiable([...state.openPanes, pane]),
        activePane: pane,
        dockOverlayOpen: true,
      ),
    );
    _persist();
  }

  void selectPane(ToolPane pane) {
    if (!state.openPanes.contains(pane)) {
      return;
    }
    emit(state._copyWith(activePane: pane));
    _persist();
  }

  /// Закрывает вкладку; активной становится последняя оставшаяся панель.
  void closePane(ToolPane pane) {
    final rest = [
      for (final open in state.openPanes)
        if (open != pane) open,
    ];
    emit(
      state._copyWith(
        openPanes: List.unmodifiable(rest),
        activePane: state.activePane == pane
            ? (rest.isEmpty ? null : rest.last)
            : state.activePane,
        dockOverlayOpen: rest.isEmpty ? false : state.dockOverlayOpen,
      ),
    );
    _persist();
  }

  /// Убирает выдвинутый док (клик мимо, Esc); панели остаются открытыми.
  void dismissDockOverlay() => emit(state._copyWith(dockOverlayOpen: false));

  Future<void> _restore() async {
    try {
      final saved = await _store!.load();
      if (saved == null || isClosed) {
        return;
      }
      // Имя панели, которой больше нет, пропускается: раскладку сохранила
      // другая версия app.
      final byName = ToolPane.values.asNameMap();
      final panes = [
        for (final name in saved.openPanes)
          if (byName[name] case final pane?) pane,
      ];
      final active = byName[saved.activePane];
      emit(
        state._copyWith(
          openPanes: List.unmodifiable(panes),
          activePane: panes.contains(active)
              ? active
              : (panes.isEmpty ? null : panes.last),
          dockWidth: saved.width <= 0
              ? state.dockWidth
              : saved.width.clamp(kDockMinWidth, kDockMaxWidth),
        ),
      );
    } on Object catch (error) {
      _diagnostics?.record(
        'Failed to restore the tool dock layout: $error',
        severity: DiagnosticSeverity.warning,
        source: 'layout',
      );
    }
  }

  void _persist() {
    final store = _store;
    if (store == null) {
      return;
    }
    final layout = DockLayout(
      openPanes: [for (final pane in state.openPanes) pane.name],
      activePane: state.activePane?.name,
      width: state.dockWidth,
    );
    unawaited(
      store.save(layout).catchError((Object error) {
        _diagnostics?.record(
          'Failed to save the tool dock layout: $error',
          severity: DiagnosticSeverity.warning,
          source: 'layout',
        );
      }),
    );
  }
}
