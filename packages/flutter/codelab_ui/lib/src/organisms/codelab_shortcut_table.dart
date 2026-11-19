/// Таблица сочетаний: заглушка сигнатур для красного теста 2.1 change
/// `add-app-keyboard-page` (D6, D9).
///
/// Почему: `CodeLabStatusTable` не знает строк-заголовков групп; смешивать две
/// таблицы с разной семантикой нельзя.
///
/// Для чего: шапка колонок и группы с заголовками; строки приходят готовыми
/// от app, виджет только раскладывает их (AGENTS кита §2).
///
/// Как использовать: сейчас виджет ничего не рисует (заглушка); поведение —
/// задача 2.2.
library;

import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Строка таблицы: готовые тексты и комбинации.
class CodeLabShortcutTableRow {
  const CodeLabShortcutTableRow({
    required this.key,
    required this.action,
    required this.combos,
    required this.where,
  });

  final Key key;
  final String action;
  final List<CodeLabKeyCombo> combos;
  final String where;
}

/// Группа строк с заголовком.
class CodeLabShortcutTableGroup {
  const CodeLabShortcutTableGroup({
    required this.key,
    required this.title,
    required this.rows,
  });

  final Key key;
  final String title;
  final List<CodeLabShortcutTableRow> rows;
}

class CodeLabShortcutTable extends StatelessWidget {
  const CodeLabShortcutTable({
    required this.actionHeader,
    required this.shortcutHeader,
    required this.whereHeader,
    required this.groups,
    super.key,
  });

  final String actionHeader;
  final String shortcutHeader;
  final String whereHeader;
  final List<CodeLabShortcutTableGroup> groups;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
