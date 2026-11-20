/// Страница «Keyboard» настроек: таблица сочетаний app только для чтения
/// (change `add-app-keyboard-page`; D5–D9).
///
/// Почему: сочетания app — каталог кита `CodeLabShortcut`, из которого берутся
/// и привязки, и эта страница, поэтому она не расходится с привязками (D2,
/// D3). Cubit и порты не нужны: у страницы нет внешних данных, асинхронности
/// и записи (D6, §13).
///
/// Для чего: заголовок, поле поиска, подпись «только для чтения», таблица
/// «Action · Shortcut · Where» с группами и строка «Agent commands». Записи
/// собираются из каталога и ARB в каждом `build`, поэтому смена языка
/// пересобирает страницу сразу, а запрос поиска (временное состояние поля)
/// сохраняется.
///
/// Как использовать: `buildKeyboardPage` — построитель в
/// `settingsPageBuilders`. Соответствие «запись каталога → текст» —
/// исчерпывающие `switch` ниже: новая запись без текста не компилируется.
/// Обозначения клавиш в ARB не живут: их выбирает каталог по платформе (D4).
library;

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../../l10n/app_localizations_en.dart';
import '../../../l10n/l10n.dart';
import '../application/keyboard_shortcut_search.dart';

/// Построитель тела страницы для `settingsPageBuilders`.
Widget buildKeyboardPage(BuildContext context) => const KeyboardPage();

/// Текст «Action» записи каталога на языке [l10n].
///
/// Тексты строк одобрения помечены `security` в ARB (D14
/// `add-desktop-localization`). «New session» — прежнее сообщение
/// `commonNewSession`.
String keyboardShortcutActionOf(
  AppLocalizations l10n,
  CodeLabShortcut shortcut,
) => switch (shortcut) {
  CodeLabShortcut.commandPalette => l10n.settingsKeyboardActionCommandPalette,
  CodeLabShortcut.newSession => l10n.commonNewSession,
  CodeLabShortcut.openSettings => l10n.settingsKeyboardActionOpenSettings,
  CodeLabShortcut.closeOverlay => l10n.settingsKeyboardActionCloseOverlay,
  CodeLabShortcut.leaveSettings => l10n.settingsKeyboardActionLeaveSettings,
  CodeLabShortcut.toggleSidebar => l10n.settingsKeyboardActionToggleSidebar,
  CodeLabShortcut.toggleFiles => l10n.settingsKeyboardActionToggleFiles,
  CodeLabShortcut.fileTreeMove => l10n.settingsKeyboardActionFileTreeMove,
  CodeLabShortcut.fileTreeFold => l10n.settingsKeyboardActionFileTreeFold,
  CodeLabShortcut.fileTreeOpen => l10n.settingsKeyboardActionFileTreeOpen,
  CodeLabShortcut.cancelTurn => l10n.settingsKeyboardActionCancelTurn,
  CodeLabShortcut.send => l10n.settingsKeyboardActionSend,
  CodeLabShortcut.commandMenuMove => l10n.settingsKeyboardActionCommandMenuMove,
  CodeLabShortcut.commandMenuRun => l10n.settingsKeyboardActionCommandMenuRun,
  CodeLabShortcut.commandMenuClose =>
    l10n.settingsKeyboardActionCommandMenuClose,
  CodeLabShortcut.goToApproval => l10n.settingsKeyboardActionGoToApproval,
  CodeLabShortcut.allowOnce => l10n.settingsKeyboardActionAllowOnce,
  CodeLabShortcut.allowAlways => l10n.settingsKeyboardActionAllowAlways,
  CodeLabShortcut.rejectOnce => l10n.settingsKeyboardActionRejectOnce,
  CodeLabShortcut.rejectAlways => l10n.settingsKeyboardActionRejectAlways,
};

/// Текст «Where» записи каталога на языке [l10n]. Одинаковые места разных
/// записей делят одно сообщение.
String keyboardShortcutWhereOf(
  AppLocalizations l10n,
  CodeLabShortcut shortcut,
) => switch (shortcut) {
  CodeLabShortcut.commandPalette ||
  CodeLabShortcut.openSettings ||
  CodeLabShortcut.toggleSidebar => l10n.settingsKeyboardWhereWorkbench,
  CodeLabShortcut.newSession => l10n.settingsKeyboardWhereWorkbenchProject,
  CodeLabShortcut.closeOverlay => l10n.settingsKeyboardWhereOverlay,
  CodeLabShortcut.leaveSettings => l10n.settingsKeyboardWhereSettings,
  CodeLabShortcut.toggleFiles => l10n.settingsKeyboardWhereWorkbenchFiles,
  CodeLabShortcut.fileTreeMove ||
  CodeLabShortcut.fileTreeOpen => l10n.settingsKeyboardWhereFilesTree,
  CodeLabShortcut.fileTreeFold => l10n.settingsKeyboardWhereFilesTreeFolder,
  CodeLabShortcut.cancelTurn => l10n.settingsKeyboardWhereTurnRunning,
  CodeLabShortcut.send => l10n.settingsKeyboardWhereComposer,
  CodeLabShortcut.commandMenuMove ||
  CodeLabShortcut.commandMenuRun ||
  CodeLabShortcut.commandMenuClose => l10n.settingsKeyboardWhereCommandMenu,
  CodeLabShortcut.goToApproval => l10n.settingsKeyboardWhereApprovalPending,
  CodeLabShortcut.allowOnce ||
  CodeLabShortcut.allowAlways ||
  CodeLabShortcut.rejectOnce ||
  CodeLabShortcut.rejectAlways => l10n.settingsKeyboardWhereApproval,
};

/// Заголовок группы таблицы на языке [l10n].
String keyboardShortcutGroupOf(
  AppLocalizations l10n,
  CodeLabShortcutGroup group,
) => switch (group) {
  CodeLabShortcutGroup.global => l10n.settingsKeyboardGroupGlobal,
  CodeLabShortcutGroup.navigation => l10n.settingsKeyboardGroupNavigation,
  CodeLabShortcutGroup.transcript => l10n.settingsKeyboardGroupTranscript,
  CodeLabShortcutGroup.composer => l10n.settingsKeyboardGroupComposer,
  CodeLabShortcutGroup.approvals => l10n.settingsKeyboardGroupApprovals,
};

/// Записи для поиска: каталог и тексты языка [l10n] плюс английские.
///
/// Почему отдельная функция: в `build` логики быть не должно, а сборка
/// записей заново при каждой пересборке — то, что делает смену языка
/// безподписочной (D6).
List<KeyboardShortcutEntry> keyboardEntriesOf(AppLocalizations l10n) {
  final english = AppLocalizationsEn();
  return [
    for (final shortcut in CodeLabShortcut.values)
      KeyboardShortcutEntry(
        shortcut: shortcut,
        action: keyboardShortcutActionOf(l10n, shortcut),
        englishAction: keyboardShortcutActionOf(english, shortcut),
        notations: [
          for (final combo in shortcut.combos) ...combo.searchNotations(),
        ],
      ),
  ];
}

/// Тело страницы «Keyboard»: заголовок, поиск, таблица и строка «Agent
/// commands».
///
/// Почему `StatefulWidget`: запрос поиска — временное состояние поля, как
/// `_query` в `SettingsShell`; он не сохраняется между открытиями настроек
/// (D6, D8).
///
/// Для чего: показать каталог сочетаний только для чтения; ничего не пишет,
/// не читает файлы и не обращается к агенту.
///
/// Как использовать: строится через `buildKeyboardPage` из
/// `settingsPageBuilders`; отдельных зависимостей и провайдеров не требует,
/// кроме локализации app и темы Fluent.
class KeyboardPage extends StatefulWidget {
  const KeyboardPage({super.key});

  @override
  State<KeyboardPage> createState() => _KeyboardPageState();
}

class _KeyboardPageState extends State<KeyboardPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final query = _query.text;
    final found = filterKeyboardShortcuts(keyboardEntriesOf(l10n), query);
    final muted = FluentTheme.of(context).resources.textFillColorSecondary;

    return Column(
      key: const ValueKey('settings-keyboard'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CodeLabText(l10n.settingsKeyboardTitle, role: CodeLabTextRole.title),
        const SizedBox(height: 12),
        TextBox(
          key: const ValueKey('settings-keyboard-search'),
          controller: _query,
          placeholder: l10n.settingsKeyboardSearchPlaceholder,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        CodeLabText(
          l10n.settingsKeyboardReadOnly,
          role: CodeLabTextRole.caption,
          color: muted,
        ),
        const SizedBox(height: 12),
        if (found.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: CodeLabText(
              l10n.settingsKeyboardEmpty(query.trim()),
              key: const ValueKey('settings-keyboard-empty'),
              color: muted,
            ),
          )
        else
          CodeLabShortcutTable(
            actionHeader: l10n.settingsKeyboardColumnAction,
            shortcutHeader: l10n.settingsKeyboardColumnShortcut,
            whereHeader: l10n.settingsKeyboardColumnWhere,
            groups: [
              for (final group in CodeLabShortcutGroup.values)
                if (found.any((e) => e.shortcut.group == group))
                  CodeLabShortcutTableGroup(
                    key: ValueKey('settings-keyboard-group-${group.name}'),
                    title: keyboardShortcutGroupOf(l10n, group),
                    rows: [
                      for (final entry in found)
                        if (entry.shortcut.group == group)
                          CodeLabShortcutTableRow(
                            key: ValueKey(
                              'settings-keyboard-row-${entry.shortcut.id}',
                            ),
                            action: entry.action,
                            combos: entry.shortcut.combos,
                            where: keyboardShortcutWhereOf(
                              l10n,
                              entry.shortcut,
                            ),
                          ),
                    ],
                  ),
            ],
          ),
        const SizedBox(height: 16),
        CodeLabText(
          l10n.settingsKeyboardFooter,
          key: const ValueKey('settings-keyboard-footer'),
          role: CodeLabTextRole.caption,
          color: muted,
        ),
      ],
    );
  }
}
