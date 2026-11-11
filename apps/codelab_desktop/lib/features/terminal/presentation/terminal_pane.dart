import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:xterm2/ui.dart' show TerminalView;

import '../application/terminal_tabs_cubit.dart';
import '../application/terminal_tabs_state.dart';
import 'terminal_tab_view.dart';
import 'terminal_theme.dart';

/// Предупреждение панели (spec `integrated-terminal` «Терминал вне одобрений
/// агента»); показывается, пока пользователь не закроет его (Q7).
const _disclosureText =
    "Commands here run as you, outside the agent's approval flow. "
    'Output is shown as is and is not redacted for secrets.';

/// Внутренний отступ области терминала.
///
/// Почему: без него текст прижат к краям панели (ручная проверка итерации 2).
/// Для чего: `TerminalView` рисует фон темы и под отступом, поэтому цвет
/// отступа совпадает с цветом терминала. Как использовать: передаётся в
/// `TerminalView.padding`.
const terminalViewPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);

/// Содержимое панели Terminal дока: вкладки активной сессии и эмулятор.
///
/// Почему: панель только отображает состояние `TerminalTabsCubit` и отдаёт
/// ему решения пользователя (новая вкладка, выбор, закрытие); опасно ли
/// действие, виджет не решает — терминал пользователя вне одобрений (D7).
///
/// Для чего: собирает `CodeLabTerminalPane` из кита, подставляя `TerminalView`
/// над моделью активной вкладки. Модель создаёт фабрика `terminalModel()` в
/// application, и её обработчики буфера обмена виджет не перезаписывает (Q13).
///
/// Как использовать: слот `ToolPane.terminal` в `CodeLabShell`; нужен
/// `BlocProvider<TerminalTabsCubit>` выше по дереву (`CodeLabApp`).
class WorkbenchTerminalPane extends StatelessWidget {
  const WorkbenchTerminalPane({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TerminalTabsCubit>();
    return BlocBuilder<TerminalTabsCubit, TerminalTabsState>(
      builder: (context, state) {
        final activeId = state.activeTabId;
        final model = activeId == null ? null : cubit.terminalOf(activeId);
        return CodeLabTerminalPane(
          tabs: [for (final tab in state.tabs) terminalTabViewOf(tab)],
          activeTabId: activeId,
          hasSession: state.hasSession,
          disclosure: state.disclosureShown ? null : _disclosureText,
          onSelected: cubit.selectTab,
          onClosed: cubit.closeTab,
          onNewTab: () => unawaited(cubit.newTab()),
          onDisclosureClosed: cubit.acknowledgeDisclosure,
          content: model == null
              ? const SizedBox.shrink()
              : TerminalView(
                  model,
                  // Ключ по вкладке: у каждой свои прокрутка и фокус.
                  key: ValueKey('terminal-view-$activeId'),
                  theme: terminalThemeOf(FluentTheme.of(context)),
                  autofocus: true,
                  padding: terminalViewPadding,
                ),
        );
      },
    );
  }
}
