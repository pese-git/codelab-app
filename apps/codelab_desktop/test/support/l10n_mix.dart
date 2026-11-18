import 'dart:convert';
import 'dart:io';

import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:fluent_ui/fluent_ui.dart' show TextBox, Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Проверяет, что после смены языка на экране не осталось строк языка [from].
///
/// Почему: главная защита от смеси языков (`add-desktop-localization`, D5, D9):
/// Cubit, который забыли подписать на смену языка, или кэш, который хранит
/// переведённую строку, показали бы старый язык рядом с новым.
///
/// Для чего: собирает видимые строки дерева (`Text`, `RichText`, `placeholder`
/// полей, `Tooltip.message`, `Semantics.label`) и падает, если среди них есть
/// значение сообщения каталога [from] без плейсхолдеров, у которого перевод в
/// [to] отличается. Сообщения с плейсхолдерами и строки, одинаковые в обоих
/// языках (`OK`, `MCP`, эндонимы), пропускаются; ответы агента, пути и команды
/// в каталог не входят, поэтому ложных срабатываний нет.
///
/// Как использовать: экран в [from] с данными → `AppLanguageCubit.select` →
/// `pumpAndSettle` → `await expectNoStaleLanguage(tester, from: …, to: …)`;
/// затем обратно. Каталоги читаются из `lib/l10n/app_<язык>.arb` текущего
/// пакета (каталог кита добавляется вместе с итерацией 2).
Future<void> expectNoStaleLanguage(
  WidgetTester tester, {
  required AppLocalizations from,
  required AppLocalizations to,
}) async {
  final source = _catalog(from.localeName);
  final target = _catalog(to.localeName);

  // Значения `from` без плейсхолдеров, у которых перевод отличается.
  final staleCandidates = <String, String>{
    for (final entry in source.entries)
      if (!entry.value.contains('{') &&
          target[entry.key] != null &&
          target[entry.key] != entry.value)
        entry.value: entry.key,
  };

  final visible = _visibleStrings(tester);
  final stale = [
    for (final text in visible)
      if (staleCandidates.containsKey(text.trim()))
        '"$text" (${staleCandidates[text.trim()]})',
  ];
  if (stale.isNotEmpty) {
    fail(
      'После смены языка на экране остались строки ${from.localeName}: '
      '${stale.toSet().join(', ')}',
    );
  }
}

Map<String, String> _catalog(String localeName) {
  final json =
      jsonDecode(File('lib/l10n/app_$localeName.arb').readAsStringSync())
          as Map<String, dynamic>;
  return {
    for (final entry in json.entries)
      if (!entry.key.startsWith('@')) entry.key: entry.value as String,
  };
}

List<String> _visibleStrings(WidgetTester tester) {
  final result = <String>[];
  for (final widget in tester.allWidgets) {
    switch (widget) {
      case Text(:final data?):
        result.add(data);
      case RichText(:final text):
        result.add(text.toPlainText());
      case Tooltip(:final message?):
        result.add(message);
      case Semantics(:final properties):
        final label = properties.label;
        if (label != null) result.add(label);
      case TextBox(:final placeholder?):
        result.add(placeholder);
    }
  }
  return result;
}
